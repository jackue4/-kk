extends SceneTree
## T_hub（主干解耦测试）：正常游玩开机流程 + 自检存档，测主城里 hub-shot 没覆盖的几条：
##   ① 开机离线闭关结算（存档 seen = 3 小时前 → 修为涨、主城飘字）
##   ② 主角开机后英雄 = Profile.hero()、境界 = 存档境界
##   ③ 大厅「一键服丹」：吃掉仓库里本境丹、修为涨；境界不符的丹不吃
##   ④ main._on_hub_gate(2 / 3)：炼气不开入境页、hub 提示；元婴开入境页、英雄那一排三个按钮、点英雄换主角
##   ⑤ 门 0 卡片页 → 木兰草原入境页也有英雄那一排；入境页「备战」开的是 meta_ui
## 跑法：python _tasks/trailer/run_hidden.py . _shots/T_hub/flow --resolution 1600x900 -s res://_tasks/decouple/t_hub/hub_flow_test.gd -- <输出目录> --qa-thub --keep-profile [--touch]
## 必须带 --qa-thub（自检档）。--keep-profile 让 raid_profile 读我写进自检档的文件（离线结算要文件里的 seen）。

const Profile := preload("res://scripts/raid_profile.gd")
const Items := preload("res://scripts/raid_items.gd")
const Prog := preload("res://scripts/progression.gd")

var m: Node
var fails := 0
var _dir := ""
var _off_expect := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--qa-thub") or not args.has("--keep-profile"):
		push_error("要带 --qa-thub --keep-profile")
		quit(1)
		return
	for a: String in args:
		if not a.begins_with("--") and _dir == "":
			_dir = a
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://_shots/preview/T_hub")
	DirAccess.make_dir_recursive_absolute(_dir)
	# 自检档：炼气 Lv.1、3 小时前最后在线、仓库里 4 颗炼气丹 + 2 颗结丹丹（服不了）、出战霜华
	var d: Dictionary = Profile._fresh()
	d["realm"] = 0
	d["lv"] = 1
	d["xp"] = 0.0
	d["seen"] = Time.get_unix_time_from_system() - 3.0 * 3600.0
	d["hero"] = "shuanghua"
	var st: Array = d["stash"]
	for _i in 4:
		st.append(Items.rpill(0, 0))
	for _i in 2:
		st.append(Items.rpill(2, 0))
	var f := FileAccess.open(Profile.TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	Profile._d = {}
	Profile.data()          # 马上读进内存（别的自检同时用这份文件，窗口尽量短）
	Profile.notice = "T_hub 读档通知"      # 和离线闭关结算同一次开机出现：两句都要说完整，不能互相盖掉
	_off_expect = Prog.med_rate(0) * 3.0 * 3600.0 * Prog.OFFLINE_RATE
	m = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(m)
	set_deferred("current_scene", m)
	_run.call_deferred()


func say(s: String) -> void:
	print("[thub] " + s)


func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[thub] %s %s%s" % ["通过" if ok else "不通过", what, ("｜" + detail) if detail != "" else ""])


func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func frames(n := 2) -> void:
	for _i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGB8)
	if img.get_width() > 800:
		img.resize(800, int(img.get_height() * 800.0 / img.get_width()))
	var path := _dir.path_join("flow_%s.jpg" % name)
	img.save_jpg(path, 0.88)
	print("[thub] saved ", path)


func count_name(nm: String) -> int:
	var n := 0
	for it: Dictionary in Profile.stash():
		if str(it.get("name", "")) == nm:
			n += 1
	return n


func _run() -> void:
	var hub: Node = null
	var p: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000:
		var h: Variant = m.get("hub")
		var pl: Variant = m.get("player")
		if is_instance_valid(h) and bool(h.get("active")) and is_instance_valid(pl) and (pl as Node).process_mode != Node.PROCESS_MODE_DISABLED:
			hub = h
			p = pl
			break
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await process_frame
	if hub == null:
		check("开机", false, "300 秒内没进主城")
		quit(1)
		return
	var cam: Variant = m.get("cam")
	if cam != null:
		cam.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check("存档走自检档", Profile.test_mode() and Profile._path() == Profile.TEST_PATH)
	# ① 离线闭关
	var cu := Profile.cult(0)
	var xp_total := 0.0
	for lv in range(1, int(cu[0])):
		xp_total += Prog.xp_need(lv)
	xp_total += float(cu[1])
	check("开机结算离线闭关：修为涨了约 3 小时 × 打坐速度 × 一半", xp_total > 0.5 and absf(xp_total - _off_expect) <= maxf(_off_expect * 0.05, 2.0) or Prog.profile_at_cap(),
			"Lv.%d %.1f（合计 %.1f，应约 %.1f；到瓶颈=%s）" % [int(cu[0]), float(cu[1]), xp_total, _off_expect, Prog.profile_at_cap()])
	# 主城那一行字：记下每一句亮着（alpha > 0.5）的时长
	var shown := {}
	var tw := Time.get_ticks_msec()
	var shot_done := false
	var last_t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 14000:
		await process_frame
		var now := Time.get_ticks_msec()
		var tl: Variant = hub.get("_toast")
		if tl is Label and (tl as Label).modulate.a > 0.5:
			var tx := (tl as Label).text
			shown[tx] = float(shown.get(tx, 0.0)) + float(now - last_t) * 0.001
			if tx.begins_with("离线闭关") and not shot_done:
				shot_done = true
				await shot("1_offline_toast")
		last_t = Time.get_ticks_msec()
	var off_txt := ""
	for k: String in shown:
		if k.begins_with("离线闭关"):
			off_txt = k
	say("主城那一行字亮过：%s" % str(shown))
	check("主城飘「离线闭关 …」、亮够 2.5 秒", off_txt != "" and float(shown[off_txt]) >= 2.5, "%s %.1fs" % [off_txt, float(shown.get(off_txt, 0.0))])
	check("读档通知也说完整（没被离线闭关那句盖掉）、亮够 4 秒", float(shown.get("T_hub 读档通知", 0.0)) >= 4.0, "%.1fs" % float(shown.get("T_hub 读档通知", 0.0)))
	# ② 英雄 / 境界
	check("主角开机英雄 = 存档英雄（霜华）", str(p.get("hero_id")) == "shuanghua", str(p.get("hero_id")))
	check("主角境界 = 存档境界（炼气）", int(p.get("realm_idx")) == Profile.realm(), "%d / %d" % [int(p.get("realm_idx")), Profile.realm()])
	# ③ 一键服丹
	var pills: Node = m.get_node_or_null("HallPills")
	var nm0 := str(Items.rpill(0, 0)["name"])
	var nm2 := str(Items.rpill(2, 0)["name"])
	var n0 := count_name(nm0)
	var n2 := count_name(nm2)
	var lvx0 := xp_total
	check("一键服丹条在、数到 4 颗能服、2 颗境界不符", pills != null and bool((pills.get("_bar") as Control).visible) and int(pills.call("count")) == 4 and int(pills.call("count_locked")) == 2,
			"能服 %d，不符 %d" % [int(pills.call("count")) if pills else -1, int(pills.call("count_locked")) if pills else -1])
	await shot("2_pills_bar")
	pills.call("eat_all")
	tw = Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 8000 and bool(pills.get("_eating")):
		await process_frame
	await wait(0.4)
	await shot("3_pills_eaten")
	var cu2 := Profile.cult(0)
	var xp2 := 0.0
	for lv in range(1, int(cu2[0])):
		xp2 += Prog.xp_need(lv)
	xp2 += float(cu2[1])
	check("一键服丹：炼气丹吃完、结丹丹留着、修为涨", count_name(nm0) == 0 and count_name(nm2) == n2 and xp2 > lvx0,
			"%s %d → %d，%s %d → %d，修为合计 %.1f → %.1f（Lv.%d）" % [nm0, n0, count_name(nm0), nm2, n2, count_name(nm2), lvx0, xp2, int(cu2[0])])
	# 存盘了吗：从文件读回
	var fr := FileAccess.open(Profile.TEST_PATH, FileAccess.READ)
	var saved: Variant = JSON.parse_string(fr.get_as_text()) if fr != null else null
	check("服丹后存盘（文件里的 lv / 仓库对得上）", saved is Dictionary and int((saved as Dictionary).get("lv", -1)) == int(cu2[0]) and ((saved as Dictionary)["stash"] as Array).size() == Profile.stash().size())
	# ④ 门 2 / 3
	var ui: Node = m.get("level_ui")
	m.call("_on_hub_gate", 2)
	await wait(0.6)
	var tl2: Label = hub.get("_toast")
	check("炼气走门 2：入境页不开、主城提示境界不够", not bool(ui.call("is_open")) and tl2.text.contains("元婴期方可入内"), tl2.text)
	await shot("4_gate_locked_say")
	Profile.data()["realm"] = 3
	Profile.data()["lv"] = 3 * Prog.LV_PER_REALM + 1
	m.call("_on_hub_gate", 2)
	await wait(1.2)
	var hb: Array = ui.get("_hero_btns")
	check("元婴走门 2：直接开沙海古墟入境页、英雄那一排 3 个", bool(ui.call("is_open")) and int(ui.get("_lv")) == 1 and hb.size() == 3, "开=%s lv=%d 英雄 %d" % [ui.call("is_open"), int(ui.get("_lv")), hb.size()])
	var ll: Variant = ui.get("_loadout_lab")
	say("入境页「这次带什么」：%s" % ((ll as Label).text if ll is Label else "?"))
	check("入境页写出战英雄", ll is Label and (ll as Label).text.begins_with("出战 霜华"), (ll as Label).text if ll is Label else "")
	await shot("5_desert_entry")
	# 点「镇岳」换英雄
	var target := ""
	for e: Array in hb:
		if str(e[0]) != "shuanghua":
			target = str(e[0])
			(e[1] as Button).emit_signal("pressed")
			break
	await wait(0.4)
	check("入境页点英雄：存档和主角都换了、按钮跟着亮", Profile.hero() == target and str(p.get("hero_id")) == target
			and hb.all(func(e: Array) -> bool: return (e[1] as Button).button_pressed == (str(e[0]) == target)), "%s / 主角 %s" % [Profile.hero(), p.get("hero_id")])
	check("「这次带什么」跟着改", ll is Label and (ll as Label).text.contains(str(preload("res://scripts/hero_defs.gd").def_of(target).get("name", "?"))), (ll as Label).text if ll is Label else "")
	# 入境页里开「备战」
	ui.call("open_abode")
	await wait(0.8)
	var ab: Variant = ui.get("_abode")
	check("入境页开备战 = meta_ui", is_instance_valid(ab) and (ab.get_script() as Script).resource_path.ends_with("meta_ui.gd"))
	await shot("6_entry_prep")
	if is_instance_valid(ab):
		ab.call("_close")
	await wait(0.8)
	ui.call("close")
	await wait(0.8)
	check("关掉入境页后不再暂停", not paused, str(paused))
	# ⑤ 门 0（木兰草原卡片 → 入境页）
	m.call("_on_hub_gate", 0)
	await wait(1.0)
	check("门 0 开选关卡片页", bool(ui.call("is_open")))
	await shot("7_mulan_cards")
	ui.call("pick", 0)
	await wait(0.8)
	hb = ui.get("_hero_btns")
	check("木兰草原入境页也有英雄那一排", hb.size() == 3, "%d" % hb.size())
	await shot("8_mulan_entry")
	ui.call("close")
	await wait(0.6)
	# 门 3 在元婴下也放行
	m.call("_on_hub_gate", 3)
	await wait(1.0)
	check("元婴走门 3：开天工秘所入境页", bool(ui.call("is_open")) and int(ui.get("_lv")) == 2, "lv=%d" % int(ui.get("_lv")))
	ui.call("close")
	await wait(0.6)
	# ⑥ 手机切后台 1 小时再切回来（hub_hall._notification 的第二处离线结算）
	var r3 := Profile.realm()
	var c0 := Profile.cult(r3)
	hub.set("_paused_at", Time.get_unix_time_from_system() - 3600.0)
	hub.call("_notification", Node.NOTIFICATION_APPLICATION_RESUMED)
	var c1 := Profile.cult(r3)
	var later := str(hub.get("_later_txt"))
	check("切回前台：按离开的 1 小时结算离线闭关", (int(c1[0]) > int(c0[0]) or float(c1[1]) > float(c0[1])) and later.begins_with("离线闭关 1 小时"),
			"Lv.%d %.0f → Lv.%d %.0f，「%s」" % [int(c0[0]), float(c0[1]), int(c1[0]), float(c1[1]), later])
	await wait(2.0)
	print("[thub] 结论：%s（不通过 %d 项）" % ["全部通过" if fails == 0 else "有不通过", fails])
	quit(1 if fails > 0 else 0)
