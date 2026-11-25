extends SceneTree
## QA 用例（只读测试，不改产品代码）：主城走进木兰草原门 → 选关「入境」后的载入黑场里按 B → 带着打开的洞府进大世界，
## 在洞府「佩戴」页点「取下」把身上的法宝放回仓库，关掉洞府，再分别 A 陨落 / B 撤离，结算后数存档里这件法宝有几份。
## 跑法：Godot --headless --path . -s res://_tasks/qa_20261121/qa_dupe.gd -- --qa-dupe   （存档走自检档）

const Profile := preload("res://scripts/raid_profile.gd")
const Data := preload("res://scripts/raid_data.gd")
var m: Node


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	process_frame.connect(func() -> void:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	_boot.call_deferred()


func say(s: String) -> void:
	print("[dupe] " + s)


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


func tap(code: Key) -> void:
	key(code, true)
	await wait(0.08)
	key(code, false)


func count_tag(tag: String) -> Array:
	var d: Dictionary = Profile.data()
	var n_st := 0
	var n_g := 0
	for it: Dictionary in d["stash"]:
		if str(it.get("qa_tag", "")) == tag:
			n_st += 1
	for it2: Dictionary in d["gear"]:
		if str(it2.get("qa_tag", "")) == tag:
			n_g += 1
	return [n_st, n_g]


func _boot() -> void:
	await process_frame
	current_scene = m
	var cam: Node = m.get("cam")
	if cam != null:
		cam.set("capture_mouse", false)
	await wait(3.0)
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--qa-only="):
			only = a.substr(10)
	for variant: String in ["death", "extract"]:
		if only != "" and only != variant:
			continue
		await wait(3.0)
		await _round(variant)
	say("完")
	quit()


func _round(variant: String) -> void:
	var p: Node3D = m.get("player") as Node3D
	var hub: Node = m.get("hub")
	var ui: Node = m.get("level_ui")
	var tag := "QA_" + variant
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var g: Dictionary = Data.make_gear(2, rng)
	g["qa_tag"] = tag
	(Profile.data()["gear"] as Array).clear()
	(Profile.data()["gear"] as Array).append(g)
	Profile.save()
	say("[%s] 开局前：身上法宝「%s」，仓库 %d 件；这件在 仓库 / 身上 = %s" % [variant, str(g.get("name", "")), (Profile.data()["stash"] as Array).size(), str(count_tag(tag))])
	var hc: Dictionary = (hub.get_script() as GDScript).get_script_constant_map()
	p.call("force_ground")
	p.global_position = Vector3(float((hc["GATES"] as Array)[0]["x"]), float(hc["TERRACE_H"]) + 0.1, float(hc["WALL_Z"]) + 12.0)
	p.call("face_now", 0.0)
	await wait(0.5)
	key(KEY_W, true)
	var opened: bool = await wait_until(func() -> bool: return bool(ui.call("is_open")), 6.0)
	key(KEY_W, false)
	if not opened:
		say("[%s] 选关没打开，跳过" % variant)
		return
	await wait(0.4)
	if OS.get_cmdline_user_args().has("--qa-match"):
		# 真实界面路径：点关卡卡片 → 入境页 → 点「开始匹配」（会开一个局域网房间）
		ui.call("pick", 0)
		await wait(0.4)
		var go: Button = null
		for b: Node in ui.find_children("*", "Button", true, false):
			if (b as Button).text == "开始匹配":
				go = b
		say("[%s] 入境页「开始匹配」按钮=%s" % [variant, go != null])
		if go == null:
			return
		go.pressed.emit()
	else:
		ui.call("pick", 0, true)
	await wait(0.25)
	if OS.get_cmdline_user_args().has("--qa-tap"):
		# 触屏变体：载入黑场里手指点一下右上角「洞府」圆按钮所在的位置（黑场 ColorRect 的 mouse_filter 是 IGNORE）
		var hud: Node = m.get("hud")
		var btn: Control = hud.get("_bag_btn") as Control
		var c := btn.get_global_rect().get_center()
		var wpos: Vector2 = root.get_final_transform() * c
		var fade: ColorRect = ui.get("_fade") as ColorRect
		say("[%s] 载入黑场：黑场不透明度 %.2f，洞府按钮可见=%s 在 %s（窗口坐标 %s）；手指点一下" % [variant, fade.color.a, btn.is_visible_in_tree(), str(c.round()), str(wpos.round())])
		var t1 := InputEventScreenTouch.new()
		t1.index = 0
		t1.position = wpos
		t1.pressed = true
		Input.parse_input_event(t1)
		await wait(0.06)
		var t2 := InputEventScreenTouch.new()
		t2.index = 0
		t2.position = wpos
		t2.pressed = false
		Input.parse_input_event(t2)
	else:
		await tap(KEY_B)                 # ← 载入黑场里按 B
	var entered: bool = await wait_until(func() -> bool: return m.get("level") != null and not bool(m.get("_switching")), 90.0)
	await wait(0.5)
	var ab: Variant = ui.get("_abode")
	var ab_open := ab != null and is_instance_valid(ab)
	var rd: Node = (m.get("level") as Node).get("raid") if entered else null
	say("[%s] 进图=%s 暂停=%s 洞府开着=%s；局内身上法宝 %d 件（含这件=%s）" % [variant, entered, paused, ab_open,
			(rd.get("gear") as Array).size() if rd != null else -1,
			rd != null and (rd.get("gear") as Array).any(func(x: Dictionary) -> bool: return str(x.get("qa_tag", "")) == tag)])
	if rd == null:
		say("[%s] 没进图，跳过" % variant)
		return
	if ab_open:
		# 走真实的界面按钮：选中「佩戴」里第 0 件 → 点「取下」
		(ab as Node).call("_select", "gear", 0)
		await process_frame
		var pressed := false
		for b: Node in (ab as Node).find_children("*", "Button", true, false):
			if (b as Button).text == "取下" and (b as Button).is_visible_in_tree():
				(b as Button).pressed.emit()
				pressed = true
				break
		await process_frame
		say("[%s] 在大世界里的洞府点「取下」=%s → 存档里这件在 仓库 / 身上 = %s；局内身上法宝仍有 %d 件" % [variant, pressed, str(count_tag(tag)), (rd.get("gear") as Array).size()])
		(ab as Node).call("_close")
		await wait(0.5)
		say("[%s] 关洞府后暂停=%s" % [variant, paused])
	else:
		# 洞府没被带进来（修复后应如此）：再直接调存档层的「取下」，验证局内兜底
		var r: Variant = Profile.unequip(0)
		var r2: Variant = Profile.sell(0)
		say("[%s] 洞府没被带进大世界；局内直接调 Profile.unequip(0) → 「%s」，Profile.sell(0) → %s；存档里这件在 仓库 / 身上 = %s" % [variant, str(r), str(r2), str(count_tag(tag))])
	if variant == "death":
		rd.set("_mob_root", rd.get("_mob_root"))
		(p.get("melee") as Node).set("hp", 0.0)    # 让局自己判陨落（raid_manager._process 里 hp <= 0 → _finish(false)）
	else:
		var target: Dictionary = {}
		for e: Dictionary in rd.get("_extracts"):
			if bool(e["active"]) and str(e.get("kind", "gate")) == "gate":
				target = e
				break
		if target.is_empty():
			say("[extract] 没有亮着的传送阵")
			return
		(rd.get("_mob_root") as Node).process_mode = Node.PROCESS_MODE_DISABLED
		var pos: Vector3 = target["pos"]
		p.global_position = Vector3(pos.x, float((m.get("level") as Node).call("ground", pos.x, pos.z)) + 0.2, pos.z)
	var done: bool = await wait_until(func() -> bool: return not bool(rd.get("running")), 40.0)
	var home: bool = await wait_until(func() -> bool: return m.get("level") == null and not bool(m.get("_switching")), 20.0)
	await wait(0.5)
	var c := count_tag(tag)
	say("[%s] 结算完=%s 回城=%s → 存档里这件在 仓库 / 身上 = %s（%s）" % [variant, done, home, str(c),
			"陨落后应为 0 / 0（佩戴的法宝陨落即失）" if variant == "death" else "撤离后应总共 1 份"])
