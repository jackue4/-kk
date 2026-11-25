extends SceneTree
## QA 用例（只读测试）：BUG-08 手机双指缩放。触屏模式开机（--touch，存档走自检档），往引擎里发 InputEventScreenTouch / Drag：
##   1 单指在镜头区拖动 = 转镜头（原有行为）  2 再按第二根、两指张开 = 拉近，捏拢 = 拉远  3 上下限 3~16
##   4 缩放期间不转镜头  5 先抬转镜头那根，留下那根接着转镜头  6 摇杆同时推着不受影响
## 跑法：Godot --headless --path . -s res://_tasks/qa_20261121/qa_touch_zoom.gd -- --qa-touch-zoom --touch

var m: Node
var fails := 0


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	_boot.call_deferred()


func wait_frames(n: int) -> void:
	for i in n:
		await process_frame


func touch(idx: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * pos     # 界面坐标 → 窗口坐标（和 main.gd 的触屏自检一样）
	e.pressed = down
	Input.parse_input_event(e)


func drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.relative = Vector2(500.0, -300.0)     # 故意给错的 relative：引擎在网页多指时会串，脚本应自己用前后位置算
	Input.parse_input_event(e)


func check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("[zoom] %s %s｜%s" % ["通过" if ok else "不通过", name, detail])


func _boot() -> void:
	await process_frame
	current_scene = m
	await create_timer(3.0).timeout
	var cam: Node = m.get("cam")
	var tc: Node = m.get("touch")
	if tc == null:
		print("[zoom] 没有触屏层（要带 --touch）")
		quit()
		return
	var vs: Vector2 = root.get_visible_rect().size
	var look0 := Vector2(vs.x * 0.62, vs.y * 0.45)
	var stick0 := Vector2(vs.x * 0.16, vs.y * 0.72)
	cam.set("zoom", 8.0)
	await wait_frames(3)
	# 1 单指转镜头
	var yaw0 := float(cam.get("yaw"))
	touch(1, look0, true)
	await wait_frames(2)
	for i in 6:
		drag(1, look0 + Vector2(10.0 * float(i + 1), 0.0))
		await process_frame
	var yaw1 := float(cam.get("yaw"))
	check("单指拖动转镜头", absf(angle_difference(yaw0, yaw1) + 60.0 * 0.0052) < 0.02 and is_equal_approx(float(cam.get("zoom")), 8.0),
			"转了 %.3f（应 %.3f），zoom %.2f（应不变 8）" % [angle_difference(yaw0, yaw1), -60.0 * 0.0052, float(cam.get("zoom"))])
	# 2 第二根落下、两指张开：间距 200 → 400 = 拉近一倍
	var a := look0 + Vector2(60.0, 0.0)
	var b := a + Vector2(200.0, 0.0)
	touch(2, b, true)
	await wait_frames(2)
	var yaw2 := float(cam.get("yaw"))
	for i in 10:
		b += Vector2(20.0, 0.0)
		drag(2, b)
		await process_frame
	var z_in := float(cam.get("zoom"))
	check("两指张开拉近", z_in < 8.0 * 0.6 and z_in >= 3.0, "zoom 8 → %.2f（两指 200 → 400 像素，应约 4）" % z_in)
	check("缩放期间不转镜头", absf(angle_difference(yaw2, float(cam.get("yaw")))) < 0.001, "转了 %.4f" % angle_difference(yaw2, float(cam.get("yaw"))))
	# 3 捏拢拉远，超过上限被夹住
	for i in 30:
		b -= Vector2(12.0, 0.0)
		drag(2, b)
		await process_frame
	var z_out := float(cam.get("zoom"))
	check("两指捏拢拉远、不超过上限 16", z_out > z_in and z_out <= 16.0 + 1e-3, "zoom %.2f → %.2f" % [z_in, z_out])
	# 张很开，不低于下限 3
	for i in 30:
		b += Vector2(40.0, 0.0)
		drag(2, b)
		await process_frame
	check("不低于下限 3", float(cam.get("zoom")) >= 3.0 - 1e-3, "zoom %.2f" % float(cam.get("zoom")))
	# 5 先抬转镜头那根（1），留下的 2 号接着转镜头
	touch(1, a, false)
	await wait_frames(2)
	var yaw5 := float(cam.get("yaw"))
	var z5 := float(cam.get("zoom"))
	for i in 5:
		b += Vector2(-10.0, 0.0)
		drag(2, b)
		await process_frame
	check("先抬转镜头的那根，留下那根接着转镜头", absf(angle_difference(yaw5, float(cam.get("yaw"))) - 50.0 * 0.0052) < 0.02 and is_equal_approx(float(cam.get("zoom")), z5),
			"转了 %.3f（应 %.3f），zoom %.2f 不变" % [angle_difference(yaw5, float(cam.get("yaw"))), 50.0 * 0.0052, float(cam.get("zoom"))])
	touch(2, b, false)
	await wait_frames(2)
	check("全部抬起后不占用", not bool(tc.call("_busy")), "_busy=%s" % tc.call("_busy"))
	# 6 推着摇杆时双指缩放，摇杆不受影响（先把镜头距离放回 8）
	cam.set("zoom", 8.0)
	touch(0, stick0, true)
	await wait_frames(2)
	drag(0, stick0 + Vector2(90.0, 0.0))
	await wait_frames(2)
	touch(1, look0, true)
	touch(2, look0 + Vector2(150.0, 0.0), true)
	await wait_frames(2)
	var z6 := float(cam.get("zoom"))
	drag(2, look0 + Vector2(300.0, 0.0))
	await wait_frames(2)
	var r6 := Input.get_action_strength("move_right")
	check("推着摇杆双指缩放，摇杆照常", r6 > 0.6 and float(cam.get("zoom")) < z6, "向右力度 %.2f，zoom %.2f → %.2f" % [r6, z6, float(cam.get("zoom"))])
	touch(1, look0, false)
	touch(2, look0, false)
	touch(0, stick0, false)
	await wait_frames(2)
	check("全部抬起后摇杆归零", Input.get_action_strength("move_right") < 0.01 and not bool(tc.call("_busy")), "向右 %.2f" % Input.get_action_strength("move_right"))
	print("[zoom] 小结：不通过 %d 项" % fails)
	quit()
