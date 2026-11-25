extends SceneTree
## 主城「元界面」（scripts/ex/meta_ui.gd + 备战 / 坊市 / 境界三张页）的小样 + 自检：不起主场景，搭一片假场景当「要被虚化的背景」，
## 自检档（raid_profile.gd）里塞一堆东西，真把界面建出来，一项项操作并截图。2026-11-25 主干解耦后改成修仙版：
##   备战：选中 → 佩戴 / 取下法宝（战力滚数）→ 服下 / 服下这一摞（和一键服丹同一份逻辑）→ 随身带上 / 放回 → 收进储物戒 / 取回 → 扩储物戒 → 点空法宝格筛选 → 卖出（古宝要确认）
##   坊市：丹药买 10 → 法宝买 1 → 破境丹 → 丹房炼制（回春丹、残片合破境丹）→ 储物戒扩格 → 出售栏单卖、一键出售（确认）
##   境界：境界 / 层 / 八境 / 六张战绩；瓶颈时写渡劫要什么；老编号 _set_tab(0 / 1 / 2)、英雄、关掉后恢复
## 跑法（要真窗口，走 run_hidden）：
##   python _tasks/trailer/run_hidden.py . _shots/metaui --resolution 1701x900 -s res://_tasks/ui_kit/meta_ui_test.gd -- <输出目录> --meta-ui-test [--touch] [--lite] [--web-fonts] [--tag=xxx]
## 必须带 --meta-ui-test（存档走自检档，不碰玩家的档）。每条输出以 [metaui] 开头，最后一行「结论」；有不通过的退出码是 1。

const UI := "res://scripts/ex/meta_ui.gd"
const Profile := preload("res://scripts/raid_profile.gd")
const Items := preload("res://scripts/raid_items.gd")
const Prog := preload("res://scripts/progression.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const MetaKit := preload("res://scripts/ex/meta_kit.gd")
const Abode := preload("res://scripts/abode_ui.gd")

var ui: Control
var layer: CanvasLayer
var fails := 0
var _dir := ""
var _tag := ""
var _closed := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--meta-ui-test"):
		push_error("要带 --meta-ui-test（否则会读写玩家自己的存档）")
		quit(1)
		return
	for a: String in args:
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif not a.begins_with("--") and _dir == "":
			_dir = a
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://_shots/preview")
	if args.has("--web-fonts"):
		UiStyle.force_bundled = true
	for a: String in args:
		if a.begins_with("--brush-font="):
			# 预览：正文 / 题字都换成这个字体文件（缺字落到随包正文字体上）；要先于任何界面建出来
			UiStyle.force_bundled = true
			var ff := FontFile.new()
			if ff.load_dynamic_font(a.get_slice("=", 1)) == OK:
				var chain: Array[Font] = [UiStyle.bundled(UiStyle.BODY_FILE)]
				ff.fallbacks = chain
				UiStyle._kai = ff
				UiStyle._brush = ff
				print("[font] 预览字体 ", a.get_slice("=", 1))
	if args.has("--lite"):
		Vfx.lite = true
	_build_scene.call_deferred()


func _build_scene() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.66, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.4, -0.8, -0.5).normalized(), Vector3.UP)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(200, 200)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.5, 0.62, 0.42)
	ground.material_override = gmat
	world.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cols := [Color(0.95, 0.62, 0.7), Color(0.55, 0.42, 0.75), Color(0.9, 0.82, 0.6), Color(0.35, 0.6, 0.8), Color(0.8, 0.35, 0.3), Color(0.92, 0.9, 0.86)]
	for i in 60:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var h := rng.randf_range(1.5, 9.0)
		bm.size = Vector3(rng.randf_range(1.5, 4.0), h, rng.randf_range(1.5, 4.0))
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[i % cols.size()]
		b.material_override = m
		b.position = Vector3(rng.randf_range(-45.0, 45.0), h * 0.5, rng.randf_range(-70.0, -8.0))
		world.add_child(b)
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.12, -1.0).normalized(), Vector3.UP), Vector3(0.0, 4.0, 10.0))
	cam.current = true
	layer = CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	_run.call_deferred()


func say(s: String) -> void:
	print("[metaui] " + s)


func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		fails += 1
	print("[metaui] %s %s%s" % ["通过" if ok else "不通过", what, ("｜" + detail) if detail != "" else ""])


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
	var path := _dir.path_join("metaui%s_%s.jpg" % [_tag, name])
	img.save_jpg(path, 0.9)
	print("[metaui] saved ", path, " ", img.get_size())


func page() -> Control:
	return ui.get("page")


## 仓库里第一件名字是 nm 的下标（没有 -1）
func stash_i(nm: String) -> int:
	var s := Profile.stash()
	for i in s.size():
		if str(s[i].get("name", "")) == nm:
			return i
	return -1


func power_now() -> int:
	var r := Profile.realm()
	return MetaKit.power(r, int(Profile.cult(r)[0]), Profile.gear())


## 自检档摆成：元婴期第 2 层、两万灵石，仓库里各品阶的法宝、能服 / 服不了的本境丹、破境丹和残片、灵草灵材、符箓；身上一件法宝、随身一颗回春丹
func seed_profile() -> void:
	var d := Profile.data()
	var fresh: Dictionary = Profile._fresh()
	for k: String in fresh:
		d[k] = fresh[k]
	d["lingshi"] = 20000
	d["realm"] = 3
	d["lv"] = 3 * Prog.LV_PER_REALM + 2
	d["xp"] = Prog.xp_need(3 * Prog.LV_PER_REALM + 2) * 0.35
	var st: Array = d["stash"]
	st.append(Items.gear(3, 0))
	st.append(Items.gear(3, 1))
	st.append(Items.gear(2, 2))
	st.append(Items.gear(0, 3))
	st.append(Items.gear(0, 0))
	for _i in 5:
		st.append(Items.rpill(3, 0))
	for _i in 2:
		st.append(Items.rpill(2, 1))      # 结丹丹：元婴期服不了（一键出售会卖掉）
	for _i in 3:
		st.append(Items.heal_pill())
	st.append(Items.key(4))
	for _i in 3:
		st.append(Items.frag(4))
	for _i in 4:
		st.append(Items.herb(0))
	st.append(Items.herb(3))
	for _i in 2:
		st.append(Items.mat(2))
	st.append(Items.tool("rune"))
	st.append(Items.tool("reveal"))
	(d["gear"] as Array).append(Items.gear(1, 0))
	(d["carry"] as Array).append(Items.heal_pill())
	var stats: Dictionary = d["stats"]
	stats["raids"] = 14
	stats["out"] = 9
	stats["dead"] = 5
	stats["best"] = 1850
	stats["kills"] = 126
	stats["arena_wins"] = 3
	d["hero"] = "canghong"
	Profile.save()


func _run() -> void:
	await frames(3)
	var vs := root.get_visible_rect().size
	say("画面 %s，渲染 %s，存档 %s（自检档 %s），手机画质档 %s，随包字体 %s" % [vs, RenderingServer.get_current_rendering_method(), Profile._path(),
			Profile.test_mode(), Vfx.lite, UiStyle.force_bundled])
	check("存档走自检档", Profile.test_mode())
	if not Profile.test_mode():
		quit(1)
		return
	seed_profile()
	var t0 := Time.get_ticks_msec()
	ui = (load(UI) as GDScript).call("open", layer, "prep")
	ui.connect("closed", func() -> void: _closed += 1)
	await frames(1)
	say("建界面 %d 毫秒" % (Time.get_ticks_msec() - t0))
	check("打开时游戏暂停", paused)
	var tw := Time.get_ticks_msec()
	while not bool(ui.get("_bg_ready")) and Time.get_ticks_msec() - tw < 8000:
		await process_frame
	await wait(0.25)
	await shot("0_prep_enter")
	await wait(0.9)
	check("背景拍到了场景、主视口的 3D 关了", bool(ui.get("_bg_ready")) and root.disable_3d and (ui.get("_bg") as TextureRect).texture is ImageTexture)
	check("开的是备战页、停在仓库", str(ui.call("tab_key")) == "prep" and str(page().call("list_key")) == "stash")
	check("一进来自动选中第一件（右边不空着）", str(page().call("detail_name")) != "" and (page().get("_detail") as Control).visible, str(page().call("detail_name")))
	check("没有题头", not (ui.get("_title") as Control).visible and not (ui.get("_subtitle") as Control).visible)
	check("顶栏：灵石 + 境界小牌（没有仙玉）", (ui.get("_ls") as Label).text == "20,000" or (ui.get("_ls") as Label).text.begins_with("2"),
			"灵石「%s」境界「%s」" % [(ui.get("_ls") as Label).text, (ui.get("_xy") as Label).text])
	check("境界小牌写元婴期第 2 层", (ui.get("_xy") as Label).text == "元婴期 · 2 层", (ui.get("_xy") as Label).text)
	var pw0 := int(page().call("power_shown"))
	check("战力 = CS.power(境界, 等级, 佩戴法宝)", pw0 == power_now() and pw0 > 0, "%d，显示「%s」" % [pw0, (page().get("_pw_num") as Label).text])
	check("人物脚下写境界和层", (page().get("_rl") as Label).text == "元婴期 · 第 2 层", (page().get("_rl") as Label).text)
	await shot("1_prep_stash")

	# ---------- 备战 ----------
	var p := page()
	var gi := stash_i(str(Items.gear(3, 0)["name"]))
	p.call("select", "stash", gi)
	await wait(0.4)
	say("选中仓库里的 %s：按钮 %s" % [p.call("detail_name"), str(p.call("action_texts"))])
	await shot("2_prep_selected")
	var ok := bool(p.call("press_action", "佩戴"))
	await wait(0.16)
	await shot("3_prep_equip_fly")
	await wait(0.7)
	var pw1 := int(p.call("power_shown"))
	check("佩戴古宝法宝：身上两件、战力涨、数字滚到位", ok and Profile.gear().size() == 2 and pw1 > pw0 and pw1 == power_now()
			and (p.get("_pw_num") as Label).text == MetaKit.fmt_int(pw1), "%d → %d，显示「%s」" % [pw0, pw1, (p.get("_pw_num") as Label).text])
	p.call("select", "gear", 1)
	await wait(0.3)
	await shot("4_prep_gear_selected")
	say("选中身上的法宝：按钮 %s" % str(p.call("action_texts")))
	ok = bool(p.call("press_action", "取下"))
	await wait(0.7)
	check("取下法宝回仓库、战力回落", ok and Profile.gear().size() == 1 and stash_i(str(Items.gear(3, 0)["name"])) >= 0 and int(p.call("power_shown")) == pw0)
	# 服丹：和 hall_pills 同一份逻辑
	var pill_nm := str(Items.rpill(3, 0)["name"])
	var n0 := Profile.count(pill_nm)
	var cu0 := Profile.cult(3)
	p.call("select", "stash", stash_i(pill_nm))
	await frames(3)
	say("选中 %s ×%d：按钮 %s" % [pill_nm, n0, str(p.call("action_texts"))])
	await shot("5_prep_pill")
	ok = bool(p.call("press_action", "服下"))
	await wait(0.5)
	var cu1 := Profile.cult(3)
	check("服下一颗：仓库少一颗、修为涨", ok and Profile.count(pill_nm) == n0 - 1 and (int(cu1[0]) > int(cu0[0]) or float(cu1[1]) > float(cu0[1])),
			"%d → %d 颗，修为 Lv.%d %.0f → Lv.%d %.0f" % [n0, Profile.count(pill_nm), int(cu0[0]), float(cu0[1]), int(cu1[0]), float(cu1[1])])
	check("服完接着选这一摞", str(p.call("detail_name")) == pill_nm, str(p.call("detail_name")))
	ok = bool(p.call("press_action", "服下这一摞"))
	await wait(0.5)
	check("服下这一摞：本境丹吃完（或存满停下）", ok and (Profile.count(pill_nm) == 0 or Prog.profile_at_cap()), "还剩 %d 颗" % Profile.count(pill_nm))
	var dead_nm := str(Items.rpill(2, 1)["name"])
	p.call("select", "stash", stash_i(dead_nm))
	await frames(3)
	var at: Array = p.call("action_texts")
	check("境界不符的丹没有「服下」", not at.any(func(t: String) -> bool: return t.begins_with("服下")), str(at))
	# 随身 / 储物戒
	p.call("select", "stash", stash_i("化神丹"))
	await frames(3)
	ok = bool(p.call("press_action", "随身带上"))
	await wait(0.6)
	check("破境丹随身带上", ok and Profile.carry().size() == 2 and str((Profile.carry()[1] as Dictionary).get("name", "")) == "化神丹")
	p.call("select", "carry", 1)
	await frames(3)
	ok = bool(p.call("press_action", "放回仓库"))
	await wait(0.6)
	check("随身的放回仓库", ok and Profile.carry().size() == 1 and stash_i("化神丹") >= 0)
	var herb_nm := str(Items.herb(3)["name"])
	p.call("select", "stash", stash_i(herb_nm))
	await frames(3)
	ok = bool(p.call("press_action", "收进储物戒"))
	await wait(0.6)
	check("收进储物戒", ok and Profile.ring().size() == 1 and stash_i(herb_nm) < 0)
	p.call("goto", "ring")
	await wait(0.5)
	await shot("6_prep_ring")
	check("储物戒页：选着戒里那件、底下是扩格", str(p.call("list_key")) == "ring" and str(p.call("detail_name")) == herb_nm and str(p.call("foot_text")).begins_with("扩到"),
			"%s｜%s" % [p.call("detail_name"), p.call("foot_text")])
	ok = bool(p.call("press_action", "取回仓库"))
	await wait(0.5)
	check("从储物戒取回仓库", ok and Profile.ring().is_empty() and stash_i(herb_nm) >= 0)
	var cap0 := Profile.ring_cap()
	var ls0 := Profile.lingshi()
	ok = bool(p.call("press_foot"))
	await wait(0.5)
	check("储物戒扩一格", ok and Profile.ring_cap() == cap0 + 1 and Profile.lingshi() == ls0 - Profile.RING_PRICE[cap0 + 1], "%d → %d 格，灵石 %d → %d" % [cap0,
			Profile.ring_cap(), ls0, Profile.lingshi()])
	p.call("goto", "stash")
	await wait(0.4)
	# 点空的法宝格 → 筛出法宝
	p.call("_on_slot", "gear", 2)
	await wait(0.5)
	check("点空的法宝格筛出法宝", str(p.get("_filter")) == "gear" and (p.get("_tiles") as Array).size() >= 4, "筛选 %s，%d 件" % [p.get("_filter"), (p.get("_tiles") as Array).size()])
	await shot("7_prep_filter_gear")
	p.call("set_filter", "all")
	await wait(0.3)
	# 卖古宝：要确认
	ls0 = Profile.lingshi()
	var g2 := str(Items.gear(3, 1)["name"])
	var si := stash_i(g2)
	var v := int((Profile.stash()[si] as Dictionary).get("value", 0))
	p.call("select", "stash", si)
	await frames(3)
	say("选中仓库里的 %s（值 %d）：按钮 %s" % [p.call("detail_name"), v, str(p.call("action_texts"))])
	p.call("press_action", "卖出")
	await wait(0.35)
	check("卖古宝以上的先弹确认、还没卖", bool(ui.call("modal_open")) and Profile.lingshi() == ls0)
	await shot("8_prep_confirm")
	ok = bool(ui.call("press_confirm"))
	await wait(0.7)
	check("确认后卖出、灵石到账", ok and Profile.lingshi() == ls0 + v and stash_i(g2) < 0, "灵石 %d → %d" % [ls0, Profile.lingshi()])

	# ---------- 坊市 ----------
	ui.call("_set_tab", "shop")
	await wait(0.3)
	await shot("9_shop_enter")
	await wait(0.8)
	check("换到坊市页、停在丹药", str(ui.call("tab_key")) == "shop" and str(page().call("cat_key")) == "pill")
	p = page()
	await shot("10_shop_pill")
	p.call("select", int(p.call("find_id", Items.HEAL_PILL)))
	await frames(3)
	ls0 = Profile.lingshi()
	n0 = Profile.count(Items.HEAL_PILL)
	ok = bool(p.call("press_action", "买 10"))
	await wait(0.6)
	check("买 10 颗回春丹", ok and Profile.count(Items.HEAL_PILL) == n0 + 10 and Profile.lingshi() == ls0 - 600, "灵石 %d → %d" % [ls0, Profile.lingshi()])
	p.call("goto", "gear")
	await wait(0.6)
	await shot("11_shop_gear")
	p.call("select", 4)
	await frames(3)
	ls0 = Profile.lingshi()
	var gn := Profile.stash().size()
	ok = bool(p.call("press_action", "买 1"))
	await wait(0.6)
	check("买一件灵器法宝", ok and Profile.stash().size() == gn + 1 and Profile.lingshi() == ls0 - 900 and not (p.call("action_texts") as Array).any(func(t: String) -> bool: return t.begins_with("买 10")))
	p.call("goto", "key")
	await wait(0.5)
	check("破境丹栏有筑基丹", int(p.call("find_id", "筑基丹")) >= 0)
	p.call("goto", "alchemy")
	await wait(0.6)
	await shot("12_shop_alchemy")
	p.call("select", int(p.call("find_id", Items.HEAL_PILL)))
	await frames(3)
	var h0 := Profile.count(Items.HERBS[0])
	n0 = Profile.count(Items.HEAL_PILL)
	ok = bool(p.call("press_action", "炼制"))
	await wait(0.6)
	check("丹房炼回春丹（扣一株灵参）", ok and Profile.count(Items.HERBS[0]) == h0 - 1 and Profile.count(Items.HEAL_PILL) == n0 + 1)
	var fi := int(p.call("find_id", "化神丹"))
	p.call("select", fi)
	await frames(3)
	ok = bool(p.call("press_action", "炼制"))
	await wait(0.6)
	check("三片残片合一颗化神丹", ok and Profile.count("化神丹残片") == 0 and Profile.count("化神丹") == 2, "残片 %d，化神丹 %d" % [Profile.count("化神丹残片"), Profile.count("化神丹")])
	p.call("goto", "ring")
	await wait(0.5)
	await shot("13_shop_ring")
	cap0 = Profile.ring_cap()
	ok = bool(p.call("press_action", "扩到"))
	await wait(0.5)
	check("坊市里扩储物戒", ok and Profile.ring_cap() == cap0 + 1)
	p.call("goto", "sell")
	await wait(0.6)
	await shot("14_shop_sell")
	var goods: Array = p.get("_goods")
	check("出售栏列出仓库里值钱的（一样的叠一格）", goods.size() >= 5, "%d 格" % goods.size())
	var hi := int(p.call("find_id", Items.HERBS[0]))
	p.call("select", hi)
	await frames(3)
	ls0 = Profile.lingshi()
	var unit := int(((goods[hi] as Dictionary)["item"] as Dictionary).get("value", 0))
	h0 = Profile.count(Items.HERBS[0])
	say("出售栏选中 %s：按钮 %s" % [Items.HERBS[0], str(p.call("action_texts"))])
	ok = bool(p.call("press_action", "卖 1 个"))
	await wait(0.5)
	check("一叠里卖 1 个", ok and Profile.lingshi() == ls0 + unit and Profile.count(Items.HERBS[0]) == h0 - 1, "灵石 %d → %d（单价 %d）" % [ls0, Profile.lingshi(), unit])
	ls0 = Profile.lingshi()
	var jp: Array = p.call("_junk_preview")
	ok = bool(p.call("press_bulk"))
	await wait(0.3)
	check("一键出售先弹确认", bool(ui.call("modal_open")))
	await shot("15_shop_bulk_confirm")
	ui.call("press_confirm")
	await wait(0.8)
	check("一键出售：凡品法宝 / 灵材 / 过期丹卖光", ok and int(jp[0]) > 0 and Profile.lingshi() == ls0 + int(jp[1]) and int((p.call("_junk_preview") as Array)[0]) == 0,
			"灵石 %d → %d（应得 %d，%d 件）" % [ls0, Profile.lingshi(), int(jp[1]), int(jp[0])])
	await shot("16_shop_sold")

	# ---------- 境界 ----------
	ui.call("_set_tab", "rank")
	await wait(0.35)
	await shot("17_rank_enter")
	await wait(1.2)
	var inf: Dictionary = page().call("info")
	check("换到境界页：元婴期、八境、六张战绩", str(ui.call("tab_key")) == "rank" and int(inf["realm"]) == 3 and int(inf["nodes"]) == 8 and int(inf["cards"]) == 6, str(inf))
	await shot("18_rank")
	# 瓶颈：修为灌满本境最后一层，再开一次境界页
	Profile.set_cult(Prog.top_lv(3), Prog.xp_need(Prog.top_lv(3)))
	ui.call("_set_tab", "prep")
	await wait(0.3)
	ui.call("_set_tab", "realm")
	await wait(1.4)
	inf = page().call("info")
	check("瓶颈时写渡劫要什么", bool(inf["cap"]) and str(inf["next"]).contains("化神丹") and str(inf["next"]).contains("修炼场"), str(inf["next"]))
	await shot("19_rank_cap")

	# ---------- 老编号 / 英雄 ----------
	ui.call("_set_tab", 0)
	await wait(0.9)
	check("老编号 0 = 备战页的仓库", str(ui.call("tab_key")) == "prep" and str(page().call("list_key")) == "stash" and int(ui.get("_tab")) == 0)
	check("瓶颈时备战页左上角提示去渡劫", (page().get("_entry") as Label).visible and (page().get("_entry") as Label).text.contains("渡劫"), (page().get("_entry") as Label).text)
	ui.call("_set_tab", 1)
	await wait(0.9)
	check("老编号 1 = 坊市", str(ui.call("tab_key")) == "shop" and int(ui.get("_tab")) == 1)
	ui.call("_set_tab", 2)
	await wait(0.9)
	check("老编号 2 = 坊市的丹房", str(ui.call("tab_key")) == "shop" and str(page().call("cat_key")) == "alchemy")
	ui.call("_set_tab", "prep")
	await wait(0.9)
	await shot("20_prep_final")
	ui.call("open_heroes")          # 备战页上没有换英雄的入口：这里走壳的接口（主城「英雄」入口换完回来时也是这条路）
	await wait(1.4)
	var hs: Variant = ui.get("_hero_ui")
	check("壳的接口开英雄选择界面、这边藏起来", is_instance_valid(hs) and not ui.visible)
	if is_instance_valid(hs):
		hs.set("wheel", false)
		hs.call("goto_id", "yujian", true)
		await wait(0.4)
		var at2 := str(hs.call("current_id"))
		var picked := bool(hs.call("pick"))
		await wait(0.5)
		hs.call("close")
		await wait(0.9)
		check("换了英雄回来，备战页的人跟着换", ui.visible and Profile.hero() == "yujian" and str((page().get("_doll") as Control).get("hero_id")) == "yujian",
				"英雄界面停在 %s，pick=%s；回来后 界面可见=%s 存档=%s 小像=%s" % [at2, picked, ui.visible, Profile.hero(), (page().get("_doll") as Control).get("hero_id")])
		await shot("21_prep_yujian")

	# 量一下开着的时候每帧多久
	var n := 0
	var t1 := Time.get_ticks_usec()
	var worst := 0.0
	var last := t1
	while n < 90:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) * 0.001)
		last = now
		n += 1
	say("备战页开着时 90 帧平均 %.2f 毫秒，最长 %.2f 毫秒" % [float(Time.get_ticks_usec() - t1) * 0.001 / 90.0, worst])

	ui.call("_close")
	await wait(0.5)
	check("关掉：发了 closed、节点拆了、3D 恢复、暂停解除", _closed == 1 and not is_instance_valid(ui) and not root.disable_3d and not paused,
			"closed %d 次，3D 关=%s 暂停=%s" % [_closed, root.disable_3d, paused])
	say("结论：%s" % ("全部通过" if fails == 0 else "%d 条不通过" % fails))
	quit(1 if fails > 0 else 0)
