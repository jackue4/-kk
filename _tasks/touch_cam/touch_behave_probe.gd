extends SceneTree
## 滑屏平滑之后、原有镜头行为的回归（2026-11-21，只读测试，不改玩法）。逐项打印 [tb] 通过 / 不通过：
##   触屏（-- --touch）：1 单指转镜头总量准、停手后画面与 yaw 重合  2 双指捏合缩放期间不转、zoom 照常  3 抬起转镜头那根、留下那根接着转（画面不跳）
##                      4 摇杆和转镜头同时动  5 传送（cam.snap(yaw + dy)，择境门 / 主城门那种）时画面整体跟着转、不丢不跳
##                      6 锁定对打（duel 锁定）：拖镜头时自动回正让开，松手 0.25 秒后照常回正，画面跟 yaw 不打架
##                      7 慢动作（time_scale 0.3）里滑屏：按真实时间播完，不被拖慢
##   桌面（不带 --touch）：8 鼠标转镜头照旧当帧到位（不走平滑），画面 = yaw
## 跑法：Godot --path . --resolution 1280x720 -s res://_tasks/touch_cam/touch_behave_probe.gd -- [--touch]

const SENS := 0.0052
var m: Node
var cam: CameraRig
var tc: Node
var fails := 0


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	_boot.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func touch(idx: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.pressed = down
	Input.parse_input_event(e)


func drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.relative = Vector2(500.0, -300.0)
	Input.parse_input_event(e)


func vyaw() -> float:
	return cam.global_transform.basis.get_euler().y


func check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("[tb] %s %s｜%s" % ["通过" if ok else "不通过", name, detail])


## 逐帧记画面偏航的变化（弧度），返回 [最大一步, 平均一步]
func steps(rec: Array[float]) -> Vector2:
	var mx := 0.0
	var sm := 0.0
	for i in range(1, rec.size()):
		var s := absf(angle_difference(rec[i - 1], rec[i]))
		mx = maxf(mx, s)
		sm += s
	return Vector2(mx, sm / maxf(float(rec.size() - 1), 1.0))


func _boot() -> void:
	await process_frame
	current_scene = m
	await create_timer(3.0).timeout
	cam = m.get("cam")
	tc = m.get("touch")
	var vs: Vector2 = root.get_visible_rect().size
	var look0 := Vector2(vs.x * 0.62, vs.y * 0.45)
	var stick0 := Vector2(vs.x * 0.16, vs.y * 0.72)
	if tc == null:
		await _desktop()
		print("[tb] 小结：不通过 %d 项" % fails)
		quit()
		return
	print("[tb] 触屏 画面 %dx%d" % [int(vs.x), int(vs.y)])
	cam.zoom = 8.0
	await frames(4)
	# 1 单指：每帧拖 10 像素共 20 帧，停手后画面和 yaw 重合、总量准
	var y0 := cam.yaw
	touch(1, look0, true)
	await frames(2)
	var rec: Array[float] = []
	for i in 20:
		drag(1, look0 + Vector2(10.0 * float(i + 1), 0.0))
		await process_frame
		rec.append(vyaw())
	var y_now := cam.yaw
	var lag_now := angle_difference(vyaw(), y_now)
	await create_timer(0.2).timeout
	var st := steps(rec)
	check("单指转镜头：yaw 当帧到位、停手后画面 0.2 秒内追平", absf(angle_difference(y0, y_now) + 200.0 * SENS) < 0.002 and absf(angle_difference(vyaw(), cam.yaw)) < 1e-5,
			"yaw 转了 %.4f（应 %.4f），拖动刚停时画面还差 %.4f，0.2 秒后差 %.6f；拖动中画面每帧最大 %.4f 平均 %.4f" % [angle_difference(y0, y_now), -200.0 * SENS,
			lag_now, angle_difference(vyaw(), cam.yaw), st.x, st.y])
	# 2 第二根落下、两指张开：拉近，期间 yaw 和画面都不转
	var a := look0 + Vector2(200.0, 0.0)
	var b := a + Vector2(200.0, 0.0)
	touch(2, b, true)
	await frames(3)
	var y2 := cam.yaw
	var v2 := vyaw()
	for i in 10:
		b += Vector2(20.0, 0.0)
		drag(2, b)
		await process_frame
	await frames(3)
	check("双指张开拉近、期间不转", cam.zoom < 8.0 * 0.6 and absf(angle_difference(y2, cam.yaw)) < 1e-6 and absf(angle_difference(v2, vyaw())) < 1e-5,
			"zoom 8 → %.2f，yaw 变 %.6f 画面变 %.6f" % [cam.zoom, angle_difference(y2, cam.yaw), angle_difference(v2, vyaw())])
	# 3 先抬转镜头那根，留下那根接着转：画面不跳、每帧转角均匀
	touch(1, a, false)
	await frames(2)
	var y3 := cam.yaw
	var rec3: Array[float] = [vyaw()]
	for i in 12:
		b += Vector2(-10.0, 0.0)
		drag(2, b)
		await process_frame
		rec3.append(vyaw())
	await create_timer(0.2).timeout
	var st3 := steps(rec3)
	check("抬起转镜头那根，留下那根接着转、画面不跳", absf(angle_difference(y3, cam.yaw) - 120.0 * SENS) < 0.002 and st3.x < 10.0 * SENS * 1.6 and absf(angle_difference(vyaw(), cam.yaw)) < 1e-5,
			"yaw 转了 %.4f（应 %.4f），画面每帧最大 %.4f（每帧拖动量 %.4f）" % [angle_difference(y3, cam.yaw), 120.0 * SENS, st3.x, 10.0 * SENS])
	touch(2, b, false)
	await frames(3)
	# 4 摇杆推着 + 另一根转镜头
	touch(0, stick0, true)
	await frames(2)
	drag(0, stick0 + Vector2(90.0, 0.0))
	touch(3, look0, true)
	await frames(2)
	var y4 := cam.yaw
	for i in 10:
		drag(3, look0 + Vector2(-12.0 * float(i + 1), 0.0))
		drag(0, stick0 + Vector2(90.0, 4.0 * float(i % 3)))
		await process_frame
	var r4 := Input.get_action_strength("move_right")
	await create_timer(0.2).timeout
	check("摇杆和转镜头同时动", r4 > 0.6 and absf(angle_difference(y4, cam.yaw) - 120.0 * SENS) < 0.002 and absf(angle_difference(vyaw(), cam.yaw)) < 1e-5,
			"向右力度 %.2f，yaw 转了 %.4f（应 %.4f）" % [r4, angle_difference(y4, cam.yaw), 120.0 * SENS])
	touch(3, look0, false)
	touch(0, stick0, false)
	await frames(3)
	# 5 传送：滑到一半时整体转 dy（主城门 / 择境门的做法），画面跟着转 dy、剩下的照常播完
	touch(4, look0, true)
	await frames(2)
	for i in 4:
		drag(4, look0 + Vector2(30.0 * float(i + 1), 0.0))
		await process_frame
	var lag5 := angle_difference(cam.yaw, vyaw())
	var vb := vyaw()
	cam.snap(cam.yaw + 1.0, cam.pitch, cam.zoom)
	await process_frame
	var jump := angle_difference(vb, vyaw())
	await create_timer(0.2).timeout
	check("传送时画面整体转过去、不跳", absf(jump - 1.0) < 30.0 * SENS * 1.2 and absf(angle_difference(vyaw(), cam.yaw)) < 1e-5,
			"传送那一帧画面转了 %.4f（传送 1.0 + 这一帧该播的滑动），传送前画面落后 %.4f，0.2 秒后画面和 yaw 差 %.6f" % [jump, lag5, angle_difference(vyaw(), cam.yaw)])
	touch(4, look0 + Vector2(120.0, 0.0), false)
	await frames(3)
	# 6 锁定对打：拖镜头时不回正；松手后回正，画面跟 yaw 一起走
	var tgt := Node3D.new()
	m.add_child(tgt)
	var pp: Vector3 = (m.get("player") as Node3D).global_position
	var fw := cam.flat_forward()
	tgt.global_position = pp + fw * 6.0 + Vector3(0.0, 1.0, 0.0)
	cam.lock = tgt
	cam.duel = true
	await create_timer(1.0).timeout
	touch(5, look0, true)
	await frames(2)
	for i in 15:
		drag(5, look0 + Vector2(20.0 * float(i + 1), 0.0))
		await process_frame
	var y6 := cam.yaw
	await create_timer(0.15).timeout
	var y6b := cam.yaw
	touch(5, look0 + Vector2(300.0, 0.0), false)
	await create_timer(2.0).timeout
	var back := absf(angle_difference(cam.yaw, atan2(-fw.x, -fw.z)))
	check("锁定对打：拖动中不回正、松手后照常回正，画面跟得上", absf(angle_difference(y6, y6b)) < 1e-4 and back < absf(angle_difference(y6, atan2(-fw.x, -fw.z))) - 0.5
			and absf(angle_difference(vyaw(), cam.yaw)) < 1e-4, "手指停住 0.15 秒内 yaw 动了 %.5f；松手 2 秒后离对手方向 %.3f（松手时 %.3f）；画面和 yaw 差 %.6f" % [
			angle_difference(y6, y6b), back, absf(angle_difference(y6, atan2(-fw.x, -fw.z))), angle_difference(vyaw(), cam.yaw)])
	cam.lock = null
	cam.duel = false
	tgt.queue_free()
	await create_timer(1.0).timeout
	# 7 慢动作里滑屏：按真实时间播完（0.3 倍速下 0.12 秒真实时间内画面追平）
	Engine.time_scale = 0.3
	touch(6, look0, true)
	await frames(2)
	for i in 8:
		drag(6, look0 + Vector2(15.0 * float(i + 1), 0.0))
		await process_frame
	var t7 := Time.get_ticks_msec()
	while absf(angle_difference(vyaw(), cam.yaw)) > 1e-5 and Time.get_ticks_msec() - t7 < 2000:
		await process_frame
	var ms7 := Time.get_ticks_msec() - t7
	Engine.time_scale = 1.0
	touch(6, look0, false)
	check("慢动作里滑屏按真实时间播完", ms7 < 160, "停手后画面 %d 毫秒追平（真实时间）" % ms7)
	print("[tb] 小结：不通过 %d 项" % fails)
	quit()


func _desktop() -> void:
	print("[tb] 桌面（鼠标）")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frames(3)
	var cap := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var y0 := cam.yaw
	var worst := 0.0       # 平滑队列里还没播完的量（鼠标不该走平滑，应一直是 0）
	var queued := 0
	# 鼠标位移是窗口像素，进到界面里会按画面拉伸换算（1280 宽的窗口 = 1600 宽的界面时 ×1.25）
	var px := (root.get_final_transform().affine_inverse().basis_xform(Vector2(14.0, 0.0))).x
	for i in 20:
		var e := InputEventMouseMotion.new()
		e.relative = Vector2(14.0, 0.0)
		Input.parse_input_event(e)
		await process_frame
		worst = maxf(worst, cam.view_off.length())
		queued = maxi(queued, (cam.get("_tl") as Array).size())
	await process_frame
	await process_frame
	var turned := angle_difference(y0, cam.yaw)
	var gap := absf(angle_difference(vyaw(), cam.yaw))
	if not cap:
		check("鼠标转镜头（隐藏窗口抓不住鼠标，跳过转动量）：不走平滑", worst < 1e-9 and queued == 0, "鼠标没被抓住；平滑队列最多 %d 条、画面落后最多 %.6f" % [queued, worst])
		return
	check("鼠标转镜头当帧到位（不走平滑）", absf(turned + 20.0 * px * CameraRig.SENS) < 0.002 and worst < 1e-9 and queued == 0 and gap < 1e-5,
			"yaw 转了 %.4f（应 %.4f），平滑队列最多 %d 条、画面落后最多 %.6f，停下后画面和 yaw 差 %.6f" % [turned, -20.0 * px * CameraRig.SENS, queued, worst, gap])
