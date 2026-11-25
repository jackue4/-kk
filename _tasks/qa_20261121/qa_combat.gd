extends SceneTree
## QA 战斗用例（只读测试，不改产品代码）：正常开机 → 单人入境（不开房间）→ 把怪冻住只测一只，排除走位 / 围殴的干扰：
##   1 地面近战 J 命中（炼气，地面近战）  2 格挡 / 弹反  3 飞行（FLY）时贴着会出手的怪掉不掉血，对照地面
##   4 真实致死：气血压到 1、让怪出手一下 → 陨落 → 结算 → 回城
## 跑法：python run_hidden.py . <log> --resolution 1280x720 -s res://_tasks/qa_20261121/qa_combat.gd -- --qa-combat [--touch]

var m: Node
var dmg_acc := 0.0
var track := false
var _prev_hp := -1.0
var events := {}


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	process_frame.connect(_on_frame)
	_boot.call_deferred()


func _on_frame() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if track and m.get("player") != null:
		var hp := float(((m.get("player") as Node).get("melee") as Node).get("hp"))
		if _prev_hp >= 0.0 and hp < _prev_hp:
			dmg_acc += _prev_hp - hp
		_prev_hp = hp


func say(s: String) -> void:
	print("[qc] " + s)


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func wait_until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		if bool(cond.call()):
			return true
		await process_frame
	return bool(cond.call())


func key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func tap(code: Key, hold := 0.08) -> void:
	key(code, true)
	await wait(hold)
	key(code, false)


func st_name(p: Node) -> String:
	var names := ["GROUND", "TAKEOFF", "FLY", "AIR", "DIVE"]
	var i := int(p.get("st"))
	return names[i] if i >= 0 and i < names.size() else str(i)


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
		events[kind] = int(events.get(kind, 0)) + 1)
	var ui: Node = m.get("level_ui")
	ui.call("open")
	await wait(0.3)
	ui.call("pick", 0, true)
	var entered: bool = await wait_until(func() -> bool: return m.get("level") != null and not bool(m.get("_switching")), 90.0)
	say("单人入境=%s" % entered)
	if not entered:
		quit()
		return
	var lv: Node = m.get("level")
	var rd: Node = lv.get("raid")
	await wait(4.0)
	# 等到有怪
	var mob: Node3D = null
	var t0 := Time.get_ticks_msec()
	while mob == null and Time.get_ticks_msec() - t0 < 30000:
		var want_float := OS.get_cmdline_user_args().has("--qa-floater")
		for mo: Variant in rd.get("_mobs"):
			if is_instance_valid(mo) and mo is Node3D and float((mo as Node3D).get("hp")) > 0.0 and not bool((mo as Node3D).get("boss")):
				var shp := str(((mo as Node3D).get("def") as Dictionary).get("shape", ""))
				if want_float and shp != "floater":
					continue
				mob = mo
				break
		await wait(0.5)
	if mob == null:
		say("没等到怪")
		quit()
		return
	var mroot: Node = rd.get("_mob_root")
	# ---- 1 地面近战：冻住所有怪，主角站到怪面前 2.2 米，每下前重新站位、面朝它 ----
	mroot.process_mode = Node.PROCESS_MODE_DISABLED
	p.call("force_ground")
	await wait(0.5)
	var hits0 := int(events.get("hit", 0))
	var hp0 := float(mob.get("hp"))
	var hp_max := float(mob.get("hp_max")) if mob.get("hp_max") != null else hp0
	var d1 := 1.5 if OS.get_cmdline_user_args().has("--qa-floater") else 2.2
	for i in 6:
		_place_front(p, mob, lv, d1)
		await wait(0.15)
		await tap(KEY_J, 0.06)
		await wait(0.45)
	var alive := is_instance_valid(mob)
	var hp1 := float(mob.get("hp")) if alive else 0.0
	var def: Variant = mob.get("def") if alive else {}
	var mpos: Vector3 = mob.global_position if alive else p.global_position
	var gy := float(lv.call("ground", mpos.x, mpos.z))
	var to := mpos - p.global_position
	say("1 地面近战（怪冻住、炼气）：按 J 6 下，命中事件 %d 次，怪血 %.0f → %.0f（上限 %.0f），主角近战状态码 %d；怪「%s」离地 %.2f 米，和主角高差 %.2f 米（地面近战竖直判定 1.3~1.7），水平距 %.2f" % [
			int(events.get("hit", 0)) - hits0, hp0, hp1, hp_max, int(melee.get("state")),
			str((def as Dictionary).get("name", "?")) if def is Dictionary else "?",
			mpos.y - gy, to.y, Vector2(to.x, to.z).length()])
	if not alive:
		say("1 （这只怪已经没了：被打死或被刷怪导演清掉）")
	# 1b 同样的站位，用更高处的怪 / 换一只在地上的怪再试（找离地 < 0.5 米的）
	var ground_mob: Node3D = null
	for mo2: Variant in rd.get("_mobs"):
		if is_instance_valid(mo2) and mo2 is Node3D and float((mo2 as Node3D).get("hp")) > 0.0:
			var g2 := float(lv.call("ground", (mo2 as Node3D).global_position.x, (mo2 as Node3D).global_position.z))
			if absf((mo2 as Node3D).global_position.y - g2) < 0.5:
				ground_mob = mo2
				break
	if ground_mob != null and ground_mob != mob:
		var h0 := int(events.get("hit", 0))
		var gh0 := float(ground_mob.get("hp"))
		for i2 in 6:
			_place_front(p, ground_mob, lv, 2.2)
			await wait(0.15)
			await tap(KEY_J, 0.06)
			await wait(0.45)
		var gm_alive := is_instance_valid(ground_mob)
		say("1b 换一只贴地的怪：按 J 6 下命中 %d 次，怪血 %.0f → %.0f%s" % [int(events.get("hit", 0)) - h0, gh0,
				float(ground_mob.get("hp")) if gm_alive else 0.0, "" if gm_alive else "（已打死）"])
	# 第 1 步的怪打死了就换一只活着的贴地怪接着测
	if not is_instance_valid(mob) or float(mob.get("hp")) <= 0.0:
		mob = null
		for mo3: Variant in rd.get("_mobs"):
			if is_instance_valid(mo3) and mo3 is Node3D and float((mo3 as Node3D).get("hp")) > 0.0 and not bool((mo3 as Node3D).get("boss")) 					and str(((mo3 as Node3D).get("def") as Dictionary).get("shape", "")) != "floater":
				mob = mo3
				break
		say("（换一只怪继续：%s）" % ("有" if mob != null else "没有可用的怪"))
	# ---- 2 格挡 / 弹反（怪冻住，直接调它的出手入口）----
	if is_instance_valid(mob):
		_place_front(p, mob, lv, 2.2)
		await wait(1.0)
		key(KEY_K, true)
		await wait(0.5)
		var r_block := int(mob.call("_hit_player", 5.0, false, Vector3.FORWARD, false))
		key(KEY_K, false)
		await wait(1.5)
		_place_front(p, mob, lv, 2.2)
		await wait(0.6)
		var parry_res: Array = []
		for delay_f in [1, 3, 6, 10]:
			key(KEY_K, true)
			for f in delay_f:
				await process_frame
			parry_res.append("%d 帧后=%d" % [delay_f, int(mob.call("_hit_player", 5.0, false, Vector3.FORWARD, false))])
			key(KEY_K, false)
			await wait(1.5)
			_place_front(p, mob, lv, 2.2)
			await wait(0.4)
		say("2 格挡：按住 K 0.5 秒后挨一下 → %d（1 = 挡下）；刚按 K 后 N 帧挨一下 → %s（2 = 弹反，1 = 挡下，0 = 挨打）；弹反窗口 %.3fs" % [r_block,
				", ".join(parry_res), float(melee.get("_parry_win"))])
	# ---- 3 飞行时贴着怪 ----
	p.call("force_ground")
	(melee as Node).set("hp", 100.0)
	await wait(1.0)
	var flew := false
	for attempt in 3:
		await tap(KEY_SPACE, 0.08)
		await wait(0.2)
		await tap(KEY_SPACE, 0.08)
		await wait(1.0)
		if st_name(p) == "FLY":
			flew = true
			break
		await wait(0.8)
	say("3 炼气连点两下跳起飞（怪冻住、没挨打时）：起飞=%s 状态 %s" % [flew, st_name(p)])
	var rets := {}
	if is_instance_valid(mob):
		rets[st_name(p)] = int(mob.call("_hit_player", 5.0, false, Vector3.FORWARD, false))
		rets[st_name(p) + "·远程"] = int(mob.call("_hit_player", 5.0, false, Vector3.FORWARD, true))
	# 放开怪，让它自己打 8 秒：主角飞在它头顶侧上方 2 米
	mroot.process_mode = Node.PROCESS_MODE_INHERIT
	for other: Variant in rd.get("_mobs"):
		if is_instance_valid(other) and other is Node3D and other != mob:
			(other as Node3D).process_mode = Node.PROCESS_MODE_DISABLED
	dmg_acc = 0.0
	_prev_hp = float(melee.get("hp"))
	track = true
	var t := 0.0
	var states := {}
	while t < 8.0 and is_instance_valid(mob):
		var mp := mob.global_position
		p.global_position = mp + Vector3(1.8, 1.2, 0.0)
		(p as CharacterBody3D).velocity = Vector3.ZERO
		states[st_name(p)] = true
		await process_frame
		t += 1.0 / 60.0
	var fly_dmg := dmg_acc
	# 对照：地面上贴着同一只怪 8 秒（不出手、不格挡）
	p.call("force_ground")
	await wait(0.3)
	(melee as Node).set("hp", 100.0)
	_prev_hp = 100.0
	dmg_acc = 0.0
	t = 0.0
	while t < 8.0 and is_instance_valid(mob) and float(melee.get("hp")) > 5.0:
		var mp2 := mob.global_position
		var gp := mp2 + Vector3(1.8, 0.0, 0.0)
		gp.y = float(lv.call("ground", gp.x, gp.z)) + 0.1
		p.global_position = gp
		await process_frame
		t += 1.0 / 60.0
	track = false
	say("3 飞行时怪的出手入口返回 %s（-1 = 打不到）；飞在会出手的怪身边 8 秒（期间状态 %s）累计掉血 %.0f；对照：地面上贴着同一只怪 %.1f 秒累计掉血 %.0f" % [str(rets),
			str(states.keys()), fly_dmg, t, dmg_acc])
	# ---- 4 真实致死 ----
	for other2: Variant in rd.get("_mobs"):
		if is_instance_valid(other2) and other2 is Node3D:
			(other2 as Node3D).process_mode = Node.PROCESS_MODE_INHERIT
	mroot.process_mode = Node.PROCESS_MODE_DISABLED
	p.call("force_ground")
	await wait(0.5)
	if is_instance_valid(mob):
		_place_front(p, mob, lv, 2.2)
	await wait(0.3)
	var ev0 := int(events.get("player_dead", 0))
	(melee as Node).set("hp", 1.0)
	var r_kill := int(mob.call("_hit_player", 5.0, true, Vector3.FORWARD, false)) if is_instance_valid(mob) else -9
	await wait(0.3)
	var dead_now := bool(p.get("dead"))
	var pp := p.global_position
	key(KEY_W, true)
	await wait(1.0)
	key(KEY_W, false)
	say("4 气血 1 时被怪打一下：返回 %d，dead=%s，陨落事件 %d 次，局在跑=%s，陨落后按 W 1 秒挪了 %.2f 米" % [r_kill, dead_now,
			int(events.get("player_dead", 0)) - ev0, rd.get("running"), Vector2(p.global_position.x - pp.x, p.global_position.z - pp.z).length()])
	var home: bool = await wait_until(func() -> bool: return m.get("level") == null and not bool(m.get("_switching")), 20.0)
	await wait(0.5)
	say("4 结算后回城=%s dead=%s 气血 %.0f" % [home, p.get("dead"), float(melee.get("hp"))])
	say("完")
	quit()


func _place_front(p: Node3D, mob_o: Variant, lv: Node, dist: float) -> void:
	if not is_instance_valid(mob_o):
		return
	var mob: Node3D = mob_o as Node3D
	if not is_instance_valid(mob):
		return
	var mp := mob.global_position
	var d := Vector3(p.global_position.x - mp.x, 0.0, p.global_position.z - mp.z)
	if d.length() < 0.1:
		d = Vector3.BACK
	d = d.normalized()
	var spot := mp + d * dist
	spot.y = float(lv.call("ground", spot.x, spot.z)) + 0.1
	p.global_position = spot
	p.call("face_now", atan2(d.x, d.z))
	(p as CharacterBody3D).velocity = Vector3.ZERO
