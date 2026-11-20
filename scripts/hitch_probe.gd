extends Node
## 「场景里的东西头一回进画面才现编着色器」的卡顿探针：`-- --hitch-probe --touch`。
## 网页版用探针页传同样的参数，配 _tasks/web_probe/web_probe.py 收控制台（它把每次 linkProgram 打成 `[gl] link` 行），
## 再用 _tasks/web_probe/hitch_report.py 按下面的段标记数「每一段里现编了几个着色器、最长帧多少」。
## 和别的自检不一样：这里走的是正式游玩的开机流程（不放旧的木人桩 / 刀客 / 空战对手，照常做载入预热），
## 然后在大厅、大世界里各做一遍：静置 → 原地环视两遍 → 朝四个方向各迸一次碎块和尘土（两遍）。
## 第一遍带着「头一次」的开销，第二遍是对照。每段打印 `[hp] <<< 段名` / `[hp] >>> 段名：…`。
## `--hp-hall` 只测大厅；`--no-scene-warm` 是修之前的对照：载入预热不做「把四周画一遍」（warmup.gd 的 _sweep），
## 剑冢 Boss 身上的点光照旧亮着（boss_demon.gd，以前手机档没关）。
## 探针参数不在 raid_profile.gd 的 PLAY_ARGS 里：用的是自检存档、炼气起步、大世界出生在正中（每次看到的东西一样，才好前后对比）。
## 故意不写 class_name。

const Warm := preload("res://scripts/warmup.gd")
const Debris := preload("res://scripts/voxel_debris.gd")
const ROCK: Array = [Color(0.42, 0.43, 0.47), Color(0.32, 0.33, 0.37), Color(0.55, 0.55, 0.58)]

var m: Node                      # main.gd
var _on := false
var _last := 0
var _ms := PackedFloat32Array()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	m = get_parent()
	if OS.get_cmdline_user_args().has("--no-scene-warm"):
		# 修之前的对照：载入预热不环视；剑冢 Boss 身上那盏点光照旧亮着（以前手机档没跟着关）
		Warm.scene_sweep = false
		if m.arena != null and m.arena.boss != null and m.arena.boss._light != null:
			m.arena.boss._light.visible = true
	_run()


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if _on and _last > 0:
		_ms.append(float(now - _last) / 1000.0)
	_last = now


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _begin(tag: String) -> void:
	print("[hp] <<< %s" % tag)
	_ms = PackedFloat32Array()
	_last = Time.get_ticks_usec()      # 从这里起算：段里做的事是在「下一次 _process 之前的那一帧」画出来的，卡顿正好落在这一帧
	_on = true


func _end(tag: String) -> void:
	_on = false
	var a := Array(_ms)
	a.sort()
	var n := a.size()
	if n == 0:
		print("[hp] >>> %s：没有帧" % tag)
		return
	var med: float = a[n / 2]
	var long_n := 0
	var extra := 0.0
	for v: float in a:
		if v > 50.0:
			long_n += 1
			extra += v - med
	print("[hp] >>> %s：%d 帧 中位 %.1f ms 最长 %d ms ｜ 超过 50 ms 的 %d 帧，合计多花 %d ms" % [tag, n, med, int(a[n - 1]), long_n, int(extra)])


func _ground(x: float, z: float) -> float:
	return float(m.level.ground(x, z)) if m.level != null else 0.0


## 原地环视一圈（带一点俯仰）：和 main.gd 的 _spark_perf 开头那一段同样的转法
func _look(tag: String) -> void:
	var c: CameraRig = m.cam
	var lock := c.lock_turn
	c.lock_turn = false
	_begin(tag)
	for i in 48:
		c.yaw += TAU / 48.0
		c.pitch = CameraRig.PITCH_DEFAULT + 0.5 * sin(float(i) / 48.0 * TAU)
		await _wait(0.06)
	c.pitch = CameraRig.PITCH_DEFAULT
	await _wait(0.3)
	_end(tag)
	c.lock_turn = lock


## 朝四个方向各迸一次受击碎块 + 方块尘土，落在脚下的地面上
func _debris(where: String, pass_i: int) -> void:
	var c: CameraRig = m.cam
	var lock := c.lock_turn
	c.lock_turn = false
	for k in 4:
		var yaw := float(k) * PI * 0.5
		var turn := "%s 镜头转到 %d 度 · 第 %d 遍" % [where, k * 90, pass_i]
		_begin(turn)
		c.snap(yaw, CameraRig.PITCH_DEFAULT, 6.5)
		await _wait(0.6)
		_end(turn)
		var tag := "%s 碎块落地 朝向 %d 度 · 第 %d 遍" % [where, k * 90, pass_i]
		_begin(tag)
		var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
		var q: Vector3 = m.player.global_position + fwd * 3.0
		var gy := _ground(q.x, q.z)
		var d: Node3D = Debris.new()
		d.floor_y = gy
		Vfx.root.add_child(d)
		d.burst(Vector3(q.x, gy + 1.2, q.z), fwd, ROCK, 10, 5.0, 1.5)
		var dust: Node3D = Debris.new()
		dust.floor_y = gy
		Vfx.root.add_child(dust)
		dust.dust(Vector3(q.x, gy, q.z), 10, 4.0, 1.5)
		await _wait(1.4)
		_end(tag)
	c.lock_turn = lock


func _scene(where: String) -> void:
	_begin("%s 静置 2 秒" % where)
	await _wait(2.0)
	_end("%s 静置 2 秒" % where)
	await _look("%s 环视 · 第 1 遍" % where)
	await _look("%s 环视 · 第 2 遍" % where)
	await _debris(where, 1)
	await _debris(where, 2)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var t_boot := Time.get_ticks_msec()
	_begin("开机（大厅载入 + 预热）")
	# 等开机预热做完、黑幕退掉（没开预热的话等 3 秒就算）
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await get_tree().process_frame
		if Warm.done and m.level_ui._fade.color.a <= 0.01:
			break
		if not bool(m._warm) and Time.get_ticks_msec() - t0 > 3000:
			break
	_end("开机（大厅载入 + 预热）")
	print("[hp] 渲染器 %s  手机画质档=%s  3D 缩放 %.2f  窗口 %s  预热=%s  环视预热=%s  相机归位=%s" % [RenderingServer.get_current_rendering_method(), m._mobile,
			get_viewport().scaling_3d_scale, get_window().size, m._warm, Warm.scene_sweep, get_viewport().get_camera_3d() == m.cam.cam])
	print("[hp] 大厅开机到能玩 %d ms，其中预热 %d ms（分项见上面的 [warm] 行）" % [Time.get_ticks_msec() - t_boot, Warm.last_ms])
	await _scene("大厅")
	if not args.has("--hp-hall"):
		var t1 := Time.get_ticks_msec()
		_begin("进大世界（载入 + 预热）")
		m.level_ui.mode = "solo"
		await m._enter_level("meadow")
		_end("进大世界（载入 + 预热）")
		print("[hp] 进大世界到能玩 %d ms，其中预热 %d ms（分项见上面的 [warm] 行）" % [Time.get_ticks_msec() - t1, Warm.last_ms])
		if m.level != null:
			m._raid_immortal()
			await _scene("大世界")
	print("[hp] DONE")
	if not OS.has_feature("web"):
		get_tree().quit()
