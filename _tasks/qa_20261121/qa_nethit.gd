extends SceneTree
## QA 用例（只读测试）：BUG-04 联机受击时攻击来源找不到（raid_manager.net_take_hit 的 src = null，例如别人名下的怪在本机没有木偶）。
##   1 地面挨一下：应进受击硬直、不报错   2 地面致命一下：应陨落（dead、player_dead 事件、本局结算）
##   3 御剑飞行中致命一下：应陨落（以前只扣到 0、dead 不置位）
## 跑法：Godot --headless --path . -s res://_tasks/qa_20261121/qa_nethit.gd -- --qa-nethit     （看 stderr 有没有 SCRIPT ERROR）

var m: Node
var ev := {}


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	_boot.call_deferred()


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func enter() -> Node:
	var ui: Node = m.get("level_ui")
	ui.call("open")
	await wait(0.3)
	ui.call("pick", 0, true)
	while m.get("level") == null or bool(m.get("_switching")):
		await process_frame
	await wait(2.0)
	var lv: Node = m.get("level")
	var rd: Node = lv.get("raid")
	(rd.get("_mob_root") as Node).process_mode = Node.PROCESS_MODE_DISABLED     # 只测这一下，别被别的怪打
	return rd


func back_home() -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		if m.get("level") == null and not bool(m.get("_switching")):
			return true
		await process_frame
	return false


func _boot() -> void:
	await process_frame
	current_scene = m
	var cam: Node = m.get("cam")
	if cam != null:
		cam.set("capture_mouse", false)
	await wait(3.0)
	var p: Node3D = m.get("player") as Node3D
	var melee: Node = p.get("melee")
	melee.connect("combat_event", func(kind: String, _info: Dictionary) -> void:
		ev[kind] = int(ev.get(kind, 0)) + 1)
	# ---- 1 / 2 地面 ----
	var rd: Node = await enter()
	p.call("force_ground")
	await wait(0.6)
	melee.set("hp", 100.0)
	var h0 := int(ev.get("hurt", 0))
	rd.call("net_take_hit", null, 0, 5.0, Vector3(1.0, 0.0, 0.0), 6.0, false, "", false)
	var st1 := int(melee.get("state"))
	print("[nethit] 1 地面、来源未知挨一下：气血 100 → %.1f，近战状态码 %d（7 = 受击硬直），受击事件 +%d" % [float(melee.get("hp")), st1, int(ev.get("hurt", 0)) - h0])
	await wait(1.2)
	melee.set("hp", 3.0)
	var d0 := int(ev.get("player_dead", 0))
	rd.call("net_take_hit", null, 0, 99.0, Vector3(1.0, 0.0, 0.0), 6.0, true, "", false)
	await wait(0.3)
	print("[nethit] 2 地面、来源未知致命一下：dead=%s，陨落事件 +%d，近战状态码 %d（10 = 倒地），本局还在跑=%s" % [p.get("dead"), int(ev.get("player_dead", 0)) - d0,
			int(melee.get("state")), rd.get("running")])
	var home: bool = await back_home()
	await wait(1.0)
	print("[nethit] 2 结算后回城=%s dead=%s 气血 %.0f" % [home, p.get("dead"), float(melee.get("hp"))])
	# ---- 3 御剑飞行中 ----
	await wait(1.0)
	rd = await enter()
	p.call("force_ground")
	await wait(0.8)
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
	var st0: String = names[int(p.get("st"))]
	var y0 := p.global_position.y
	melee.set("hp", 3.0)
	var d1 := int(ev.get("player_dead", 0))
	rd.call("net_take_hit", null, 0, 99.0, Vector3(1.0, 0.0, 0.0), 6.0, true, "", false)
	await wait(0.3)
	var pp := p.global_position
	key(KEY_W, true)
	await wait(1.0)
	key(KEY_W, false)
	print("[nethit] 3 %s 中、来源未知致命一下：dead=%s，陨落事件 +%d，状态 %s，本局还在跑=%s；之后按 W 1 秒水平挪了 %.2f 米（离地 %.1f 米起）" % [st0, p.get("dead"),
			int(ev.get("player_dead", 0)) - d1, names[int(p.get("st"))], rd.get("running"), Vector2(p.global_position.x - pp.x, p.global_position.z - pp.z).length(),
			y0 - float((m.get("level") as Node).call("ground", pp.x, pp.z)) if m.get("level") != null else 0.0])
	var home2: bool = await back_home()
	await wait(1.0)
	print("[nethit] 3 结算后回城=%s dead=%s 气血 %.0f" % [home2, p.get("dead"), float(melee.get("hp"))])
	print("[nethit] 完")
	quit()
