extends SceneTree
## 手机滑屏转镜头的平滑量测（2026-11-21，只读测试，不改玩法）。
## 触屏模式开机（--touch），按「手指采样时刻」往引擎里发 InputEventScreenTouch / Drag（采样率、抖动、整像素量化按剧本给），
## 逐帧记：画面上实际的镜头朝向（镜头节点的变换）、yaw / pitch、手指理想位置对应的角度。
## 同一个进程里「改之前」（CameraRig.touch_raw = true：画面当帧转到位）和「现在」交替跑同一套剧本。
## 跑法：Godot --path . --resolution 1280x720 [--fixed-fps 60] -s res://_tasks/touch_cam/touch_look_probe.gd -- --touch --tl-csv <路径> [--tl-fixed 60] [--tl-uneven] [--tl-tag 名字]
##   --fixed-fps N：每帧游戏时间固定 1/N 秒（剧本的手指时钟也按帧算，结果可复现）；不给就按真实时间（--tl-uneven 再故意让帧长忽长忽短）
## 打印 [tl] 行；CSV 每帧一行，交给同目录的 analyze.py 出指标和曲线图。

const SENS := 0.0052
const PITCH_MAX := 1.3

var m: Node
var cam: Node3D
var tc: Node
var fixed_fps := 0
var uneven := false
var rng := RandomNumberGenerator.new()
var csv: FileAccess
var tag := "run"
var _f0 := 0
var _t0 := 0


func _initialize() -> void:
	var u := OS.get_cmdline_user_args()
	var fi := u.find("--tl-fixed")      # 和引擎参数 --fixed-fps 给同一个数（引擎参数脚本里读不到）
	if fi >= 0 and fi + 1 < u.size():
		fixed_fps = int(u[fi + 1])
	uneven = u.has("--tl-uneven")
	var ci := u.find("--tl-csv")
	if ci >= 0 and ci + 1 < u.size():
		csv = FileAccess.open(u[ci + 1], FileAccess.WRITE)
		csv.store_line("tag,scene,mode,t,phase,view_yaw,view_pitch,yaw,pitch,ideal_yaw,ideal_pitch,dt")
	var ti := u.find("--tl-tag")
	if ti >= 0 and ti + 1 < u.size():
		tag = u[ti + 1]
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	_boot.call_deferred()


## 剧本时钟（秒）：固定帧率时按帧数算，否则按真实时间
func clock() -> float:
	if fixed_fps > 0:
		return float(Engine.get_process_frames() - _f0) / float(fixed_fps)
	return float(Time.get_ticks_usec() - _t0) / 1e6


func touch(idx: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.relative = Vector2(500.0, -300.0)     # 故意给错的 relative（网页多指时引擎会串），触控层应自己用前后位置算
	Input.parse_input_event(e)


func view() -> Vector2:
	var e := cam.global_transform.basis.get_euler()
	return Vector2(e.y, e.x)


## 手指相对按下点的位移（像素），t = 开始滑动后的秒数
func finger(sc: Dictionary, t: float) -> Vector2:
	var dur: float = sc["dur"]
	var tt := clampf(t, 0.0, dur)
	match str(sc["kind"]):
		"const":
			return Vector2(sc["vx"], sc["vy"]) * tt
		"sine":
			return Vector2(float(sc["amp"]) * sin(TAU * float(sc["hz"]) * tt), 0.0)
		"natural":
			# 先加速后减速的一下（速度是半个正弦），总位移 dist
			return Vector2(float(sc["dist"]) * (tt / dur - sin(TAU * tt / dur) / TAU), 0.0)
	return Vector2.ZERO


func run_scene(sc: Dictionary, raw: bool, look0: Vector2) -> void:
	CameraRig.touch_raw = raw
	cam.set("pitch", CameraRig.PITCH_DEFAULT)     # 每段都从默认俯仰起（上一段可能顶在上限）
	for i in 3:
		await process_frame
	var mode := "raw" if raw else "new"
	var rate: float = sc["rate"]
	var q: float = sc.get("quant", 0.0)
	var jit: float = sc.get("jit", 0.0015)
	var dur: float = sc["dur"]
	rng.seed = int(sc["seed"])
	# 采样时刻：开始滑动后 n / rate 秒，加一点抖动；和画面帧的相位故意错开一点
	var samples: Array[float] = []
	var n := 0
	while true:
		var s := float(sc.get("phase", 0.004)) + float(n) / rate + rng.randfn(0.0, jit)
		if s > dur + 0.0001:
			break
		samples.append(clampf(s, 0.0, dur))
		n += 1
	samples.sort()
	if samples[samples.size() - 1] < dur:
		samples.append(dur)      # 最后一下正好停在终点
	var idx := 5
	touch(idx, look0, true)
	for i in 6:
		await process_frame
	var y0 := float(cam.get("yaw"))
	var p0 := float(cam.get("pitch"))
	var v0 := view()
	var pre := 0.12
	var hold := 0.45
	var tstart := clock() + pre
	var si := 0
	var prev_t := clock()
	# 显示时钟：引擎每帧的 delta 累加（开着垂直同步时引擎会把 delta 抹平成刷新间隔 = 画面真正显示出来的节奏）。
	# 指标按它算；手指采样按真实时间送（固定帧率时两者一样）
	var disp := 0.0
	var disp_prev := 0.0
	var last_pos := look0
	var over_pitch := 0.0
	while true:
		await process_frame
		var now := clock()
		var ddt := root.get_process_delta_time() / maxf(Engine.time_scale, 0.05)
		disp += ddt
		# 记上一帧画完的状态（镜头节点的变换是上一帧算好的）
		var rel := disp_prev - pre
		var ph := 0 if rel < 0.0 else (1 if rel <= dur else 2)
		var vv := view()
		var fid := finger(sc, rel)
		var ideal := Vector2(y0 - fid.x * SENS, clampf(p0 - fid.y * SENS, -1.4, PITCH_MAX))
		over_pitch = maxf(over_pitch, vv.y - PITCH_MAX)
		if csv != null:
			csv.store_line("%s,%s,%s,%.5f,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.5f" % [tag, sc["name"], mode, rel, ph, vv.x, vv.y,
					float(cam.get("yaw")), float(cam.get("pitch")), ideal.x, ideal.y, disp - disp_prev])
		prev_t = now
		disp_prev = disp
		if rel > dur + hold:
			break
		# 这一帧之前采到的手指位置都送进去（引擎会把同一根手指的几次拖动合成一次）
		var sent := false
		while si < samples.size() and tstart + samples[si] <= now:
			var f := finger(sc, samples[si])
			if q > 0.0:
				f = Vector2(floorf(f.x / q) * q, floorf(f.y / q) * q)
			last_pos = look0 + f
			drag(idx, last_pos)
			si += 1
			sent = true
		if sent:
			Input.flush_buffered_events()
		if uneven:
			# 帧长忽长忽短：两成的帧卡过一次垂直同步（16 → 33 毫秒，手机网页掉帧时常见），再有三成处理时刻抖几毫秒
			var r := rng.randf()
			OS.delay_usec(int(22000.0 if r < 0.2 else (7000.0 if r < 0.5 else 0.0)))
	touch(idx, last_pos, false)
	var vend := view()
	var yend := float(cam.get("yaw"))
	var fend := finger(sc, dur)
	print("[tl] %s %s %s：手指 %.0f 像素 → yaw 转了 %.4f（应 %.4f），画面最后 %.4f，画面和 yaw 差 %.6f，俯仰超上限 %.4f" % [tag, sc["name"], mode,
			fend.length(), yend - y0, -fend.x * SENS, angle_difference(v0.x, vend.x), angle_difference(vend.x, yend), over_pitch])
	for i in 12:
		await process_frame


func _boot() -> void:
	await process_frame
	current_scene = m
	await create_timer(3.0).timeout
	cam = m.get("cam")
	tc = m.get("touch")
	if tc == null:
		print("[tl] 没有触屏层（要带 --touch）")
		quit()
		return
	_f0 = Engine.get_process_frames()
	_t0 = Time.get_ticks_usec()
	var vs: Vector2 = root.get_visible_rect().size
	var look0 := Vector2(vs.x * 0.62, vs.y * 0.5)
	print("[tl] 开始 %s 固定帧率 %d 帧长不均 %s 画面 %dx%d" % [tag, fixed_fps, uneven, int(vs.x), int(vs.y)])
	var scenes := [
		{"name": "fast60", "kind": "const", "vx": 900.0, "vy": 0.0, "rate": 60.0, "dur": 0.9, "seed": 11},
		{"name": "mid60", "kind": "const", "vx": 400.0, "vy": 0.0, "rate": 60.0, "dur": 0.9, "seed": 12},
		{"name": "slow60q", "kind": "const", "vx": 80.0, "vy": 0.0, "rate": 60.0, "dur": 1.2, "seed": 13, "quant": 2.0},
		{"name": "mid30", "kind": "const", "vx": 400.0, "vy": 0.0, "rate": 30.0, "dur": 0.9, "seed": 14, "jit": 0.002},
		{"name": "mid120", "kind": "const", "vx": 400.0, "vy": 0.0, "rate": 120.0, "dur": 0.9, "seed": 15, "jit": 0.0008},
		{"name": "flick", "kind": "natural", "dist": 520.0, "rate": 60.0, "dur": 0.35, "seed": 16},
		{"name": "sine", "kind": "sine", "amp": 160.0, "hz": 1.2, "rate": 60.0, "dur": 1.6, "seed": 17},
		{"name": "pitchcap", "kind": "const", "vx": 250.0, "vy": -700.0, "rate": 60.0, "dur": 0.8, "seed": 18},
	]
	for sc: Dictionary in scenes:
		for raw: bool in [true, false]:
			await run_scene(sc, raw, look0)
		# 俯仰放回默认，免得顶在上限影响下一段
		cam.set("pitch", CameraRig.PITCH_DEFAULT)
		for i in 6:
			await process_frame
	CameraRig.touch_raw = false
	if csv != null:
		csv.close()
	print("[tl] 完")
	quit()
