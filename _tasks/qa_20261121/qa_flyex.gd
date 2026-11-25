extends SceneTree
## QA 用例（只读测试）：炼气御剑（FLY）悬在亮着的撤离阵上方几米，看能不能照常读条撤离；期间放一只会出手的怪在旁边，看挨不挨打。
## 跑法：Godot --headless --path . -s res://_tasks/qa_20261121/qa_flyex.gd -- --qa-flyex

var m: Node


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	_boot.call_deferred()


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _boot() -> void:
	await process_frame
	current_scene = m
	await wait(3.0)
	var ui: Node = m.get("level_ui")
	ui.call("open")
	await wait(0.3)
	ui.call("pick", 0, true)
	while m.get("level") == null or bool(m.get("_switching")):
		await process_frame
	await wait(3.0)
	var lv: Node = m.get("level")
	var rd: Node = lv.get("raid")
	var p: Node3D = m.get("player") as Node3D
	var target: Dictionary = {}
	for e: Dictionary in rd.get("_extracts"):
		if bool(e["active"]) and str(e.get("kind", "gate")) == "gate":
			target = e
			break
	if target.is_empty():
		print("[flyex] 没有亮着的传送阵")
		quit()
		return
	var pos: Vector3 = target["pos"]
	# 在阵外 20 米起飞
	p.call("force_ground")
	var out := pos + Vector3(20.0, 0.0, 0.0)
	out.y = float(lv.call("ground", out.x, out.z)) + 0.2
	p.global_position = out
	await wait(1.0)
	for i in 3:
		key(KEY_SPACE, true)
		await wait(0.08)
		key(KEY_SPACE, false)
		await wait(0.2)
		key(KEY_SPACE, true)
		await wait(0.08)
		key(KEY_SPACE, false)
		await wait(1.0)
		if int(p.get("st")) == 2:
			break
	var names := ["GROUND", "TAKEOFF", "FLY", "AIR", "DIVE"]
	print("[flyex] 起飞后状态 %s" % names[int(p.get("st"))])
	# 悬在阵心上方 5 米，保持 FLY；每帧钉住位置
	var hover := Vector3(pos.x, pos.y + 5.0, pos.z)
	var t := 0.0
	var k_max := 0.0
	var states := {}
	var done := false
	var hp0 := float((p.get("melee") as Node).get("hp"))
	while t < 30.0:
		p.global_position = hover
		(p as CharacterBody3D).velocity = Vector3.ZERO
		states[names[int(p.get("st"))]] = true
		k_max = maxf(k_max, float(rd.get("extract_k")))
		if not bool(rd.get("running")):
			done = true
			break
		await process_frame
		t += 1.0 / 60.0
	print("[flyex] 悬在阵心上方 5 米（状态 %s）%.1f 秒：读条最高 %.2f，撤离完成=%s，气血 %.0f → %.0f" % [str(states.keys()), t, k_max, done, hp0,
			float((p.get("melee") as Node).get("hp"))])
	await wait(6.0)
	quit()
