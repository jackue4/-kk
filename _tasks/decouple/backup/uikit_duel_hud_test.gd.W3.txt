extends SceneTree
## 擂台对决时的界面自检（2026-11-24 用户：对战时右上角那块目标面板和顶上的对决血条重复、底部的一键服丹条也不要）。
## 正常游玩模式开机（用户参数里放 --qa-duelhud：不在 raid_profile.gd 的 PLAY_ARGS 里，存档走自检档，不碰玩家的档），
## 自己站上白虎擂、等 AI 陪练入场、真按「攻」打一阵，逐帧看：
##   · 进主城 / 匹配等人：服丹条在
##   · 入场倒数 / 对决 / 结算：服丹条收起；按老规矩该出目标面板的那些帧（进了战斗、目标有效）面板都没出
##   · 收场回到空闲：服丹条回来
## 跑法（要真窗口，走 run_hidden）：
##   python _tasks/trailer/run_hidden.py . _shots/duelhud --resolution 1701x900 -s res://_tasks/ui_kit/duel_hud_test.gd -- <输出目录> --qa-duelhud [--touch]
## 每条输出以 [duelhud] 开头，最后一行「结论」；有不通过的退出码是 1。

var m: Node
var fails := 0
var _dir := ""
var _immortal := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--qa-duelhud"):
		push_error("要带 --qa-duelhud（否则会读写玩家自己的存档）")
		quit(1)
		return
	var plain: Array = []
	for a: String in args:
		if not a.begins_with("--"):
			plain.append(a)
	_dir = str(plain[0]) if plain.size() > 0 else ProjectSettings.globalize_path("res://_shots/preview")
	var ps: PackedScene = load("res://scenes/main.tscn")
	m = ps.instantiate()
	root.add_child.call_deferred(m)
	process_frame.connect(_on_frame)
	_boot.call_deferred()


func _boot() -> void:
	await process_frame
	current_scene = m
	var cam: Variant = m.get("cam")
	if is_instance_valid(cam):
		cam.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run()


func _on_frame() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE       # 隐藏窗口别抓用户的鼠标
	if _immortal and m != null:
		var pl: Variant = m.get("player")
		if is_instance_valid(pl):
			var me: Object = pl.get("melee")
			if me != null and float(me.get("hp")) < 40.0:
				me.set("hp", 40.0)                        # 采样期间别被陪练打倒（打倒了对决就结束了）


func say(s: String) -> void:
	print("[duelhud] " + s)


func check(what: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("[duelhud] %s %s｜%s" % ["通过" if ok else "不通过", what, detail])


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func wait_until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		if bool(cond.call()):
			return true
		await process_frame
	return bool(cond.call())


func shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGB8)
	var path := _dir.path_join("duelhud_%s.jpg" % tag)
	img.save_jpg(path, 0.9)
	print("[duelhud] saved ", path, " ", img.get_size())


## hud.gd 原来出目标面板的条件（2026-11-24 之前的 _refresh_combat）：进了战斗、当前目标有效而且有 state_name
func _old_cond(hud: Node, p: Node, st_air: int) -> bool:
	if not (hud.get("_combat") as Control).visible:
		return false
	var air: Object = p.get("air")
	var air_on: bool = int(p.get("st")) == st_air and bool(air.call("engaged"))
	var tv: Variant = air.get("target") if air_on else (p.get("melee") as Object).get("target")
	return is_instance_valid(tv) and (tv as Object).has_method("state_name")


func _run() -> void:
	# 等开机黑幕 / 预热过去，人落在主城
	var hub: Node = null
	var p: Node3D = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var h: Variant = m.get("hub")
		var pl: Variant = m.get("player")
		if is_instance_valid(h) and bool(h.get("active")) and is_instance_valid(pl) and (pl as Node).process_mode != Node.PROCESS_MODE_DISABLED:
			hub = h
			p = pl
			break
		await process_frame
	if hub == null:
		check("开机", false, "300 秒内没进主城")
		quit(1)
		return
	await wait(3.0)
	say("开机完成（%.0f 秒），画面 %s" % [float(Time.get_ticks_msec() - t0) * 0.001, root.get_visible_rect().size])
	var hud: Node = m.get("hud")
	var pills: Node = m.get_node_or_null("HallPills")
	var duel: Node = hub.get("duel")
	if hud == null or pills == null or duel == null:
		check("节点", false, "hud=%s HallPills=%s duel=%s" % [hud, pills, duel])
		quit(1)
		return
	var bar: Control = pills.get("_bar")
	var tgt: Control = hud.get("_tgt")
	var ph: Dictionary = (duel.get_script() as GDScript).get_script_constant_map()["Ph"]
	var st_air := int(((p.get_script() as GDScript).get_script_constant_map()["St"] as Dictionary)["AIR"])
	var arena: GDScript = load("res://scripts/hub_arena.gd")
	duel.set("verbose", true)
	duel.set("use_net", false)        # 只走 AI 陪练那条路，也免得真有别的窗口在排
	duel.set("queue_t", 1.5)

	# 1) 主城里站着：服丹条在
	check("主城里服丹条在", bar.visible and not bool(hud.call("_in_duel")), "服丹条=%s 对决中=%s 文字「%s」" % [bar.visible, hud.call("_in_duel"), (pills.get("_btn") as Button).text])
	await shot("0_hall")

	# 2) 站上白虎擂：匹配等人的时候还在
	p.call("force_ground")
	p.global_position = (arena.call("center", 0) as Vector3) + Vector3(5.0, 0.1, 3.0)
	p.velocity = Vector3.ZERO
	(m.get("cam") as Node).call("snap", PI * 0.5, -0.2, 8.0)
	var q := await wait_until(func() -> bool: return bool(duel.call("queueing")), 5.0)
	await wait(0.2)
	check("匹配等人时服丹条还在", q and bar.visible, "开始匹配=%s 服丹条=%s" % [q, bar.visible])

	# 3) 陪练入场（倒数）：服丹条收起
	var b := await wait_until(func() -> bool: return bool(duel.call("busy")), 8.0)
	await wait(0.3)
	check("入场倒数时服丹条收起", b and not bar.visible, "对决开始=%s 阶段=%d 服丹条=%s 顶上的对决血条=%s" % [b, int(duel.get("phase")), bar.visible, (duel.get("_vs") as Control).visible])
	await shot("1_ready")

	# 4) 对决：真按「攻」打一阵，逐帧数
	await wait_until(func() -> bool: return int(duel.get("phase")) == int(ph["FIGHT"]), 6.0)
	_immortal = true
	await wait(2.5)                   # 等陪练靠过来
	var n := 0
	var n_old := 0
	var n_tgt := 0
	var n_bar := 0
	var shot_done := false
	var foe_name := ""
	for i in 48:
		if int(duel.get("phase")) != int(ph["FIGHT"]):
			break
		var foe: Variant = duel.get("foe")
		if is_instance_valid(foe):
			var d: Vector3 = (foe as Node3D).global_position - p.global_position
			p.call("face_now", atan2(-d.x, -d.z))
			foe_name = str(foe.get("display_name"))
		if int(p.get("st")) == st_air:
			(p.get("air") as Object).call("press_attack")
		else:
			(p.get("melee") as Object).call("press_attack")
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 250:
			await process_frame
			n += 1
			var old := _old_cond(hud, p, st_air)
			if old:
				n_old += 1
			if tgt.visible:
				n_tgt += 1
			if bar.visible:
				n_bar += 1
			if old and not shot_done and n_old >= 20:
				shot_done = true
				await shot("2_fight")
	check("对决中按老规矩该出目标面板的帧数 > 0（说明真打上了）", n_old > 0, "采样 %d 帧，其中进了战斗且目标有效 %d 帧（对手「%s」）" % [n, n_old, foe_name])
	check("对决中右上角目标面板不出", n_tgt == 0, "面板出现的帧数 %d / %d" % [n_tgt, n])
	check("对决中服丹条不出", n_bar == 0, "服丹条出现的帧数 %d / %d" % [n_bar, n])
	if not shot_done:
		await shot("2_fight")

	# 对决中按 H（一键服丹的键）也不该有反应
	var eating_before := bool(pills.get("_eating"))
	pills.call("eat_all")
	check("对决中一键服丹不生效", not bool(pills.get("_eating")) and not eating_before, "服丹中=%s" % pills.get("_eating"))

	# 5) 把陪练打倒：结算阶段也收着
	var k := 0
	while is_instance_valid(duel.get("foe")) and int(duel.get("phase")) == int(ph["FIGHT"]) and k < 60:
		var f: Node = duel.get("foe")
		f.set("_iframe", 0.0)
		f.call("receive_hit", p, {"dmg": float(f.get("hp_max")) * 0.2, "dir": Vector3.RIGHT, "kb": 2.0, "heavy": true})
		k += 1
		await wait(0.15)
	var r := await wait_until(func() -> bool: return int(duel.get("phase")) == int(ph["RESULT"]), 4.0)
	await wait(0.4)
	check("结算时服丹条、目标面板都收着", r and not bar.visible and not tgt.visible, "进了结算=%s 结果=%s 服丹条=%s 目标面板=%s" % [r, duel.get("last_result"), bar.visible, tgt.visible])
	await shot("3_result")
	_immortal = false

	# 6) 收场回到空闲：服丹条回来
	var idle := await wait_until(func() -> bool: return int(duel.get("phase")) == int(ph["IDLE"]), 10.0)
	await wait(0.5)
	check("收场后服丹条回来", idle and bar.visible and not bool(hud.call("_in_duel")), "回到空闲=%s 服丹条=%s 对决中=%s" % [idle, bar.visible, hud.call("_in_duel")])
	await shot("4_after")
	say("结论：%s" % ("全部通过" if fails == 0 else "%d 条不通过" % fails))
	quit(1 if fails > 0 else 0)
