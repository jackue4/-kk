extends SceneTree
## 主城「元界面」（scripts/ex/meta_ui.gd + 备战 / 坊市 / 段位三张页）的小样 + 自检：不起主场景，搭一片假场景当「要被虚化的背景」，
## 自检档里塞一堆各品质的东西，真把界面建出来，一项项操作并截图：
##   备战：选中 → 穿戴 / 卸下 → 存进仓库 / 带上 → 点空装备栏筛选 → 卖出（史诗要确认）→ 整理 → 扩容
##   坊市：换分类 → 买 1 / 买 10 → 黑市买玉钥 → 出售栏单卖、一键卖出（含确认）
##   段位、英雄（从备战页点人物开）、老编号 _set_tab(0 / 1)、关掉后恢复
## 跑法（要真窗口，走 run_hidden）：
##   python _tasks/trailer/run_hidden.py . _shots/metaui --resolution 1701x900 -s res://_tasks/ui_kit/meta_ui_test.gd -- <输出目录> --meta-ui-test [--touch] [--lite] [--web-fonts] [--tag=xxx]
## 必须带 --meta-ui-test（存档走自检档，不碰玩家的档）。每条输出以 [metaui] 开头，最后一行「结论」；有不通过的退出码是 1。

const UI := "res://scripts/ex/meta_ui.gd"
const ExProfile := preload("res://scripts/ex/ex_profile.gd")
const ExData := preload("res://scripts/ex/ex_data.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const MetaKit := preload("res://scripts/ex/meta_kit.gd")

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


func bag_i(id: String) -> int:
	var b := ExProfile.bag()
	for i in b.size():
		if str(b[i].get("id", "")) == id:
			return i
	return -1


func stash_i(id: String) -> int:
	var s := ExProfile.stash()
	for i in s.size():
		if str(s[i].get("id", "")) == id:
			return i
	return -1


## 自检档摆成：新号 + 仓库 / 背包里各品质的兵刃、法衣、法宝、丹符、售卖物，累计带出 600 万（筑基三阶走了一点）
func seed_profile() -> void:
	var d := ExProfile.data()
	var fresh: Dictionary = ExProfile._new_save()
	for k: String in fresh:
		d[k] = fresh[k]
	var bag: Array = d["bag"]
	for id: String in ["w_liuguang_3", "w_pojun_4", "c_regen_5", "thr_lei"]:
		ExData.add_to(bag, ExData.make(id), ExProfile.BAG_CAP)
	var stash: Array = d["stash"]
	for id: String in ["w_xuantie_2", "w_zhenyue_6", "a_1_6", "a_0_3", "c_shell_6", "c_pierce_7", "med_da", "s01", "s13", "key"]:
		ExData.add_to(stash, ExData.make(id), 12)
	for e: Array in [["s40", 3], ["s80", 1], ["med_zhong", 8]]:
		var it := ExData.make(str(e[0]))
		it["n"] = int(e[1])
		ExData.add_to(stash, it, 12)
	d["extract_total"] = 6000000
	d["rank"] = ExData.rank_of(6000000)
	d["stats"] = {"raids": 14, "out": 9, "dead": 5, "kills": 126, "best": 1850000}
	d["hero"] = "canghong"
	ExProfile.save()


func _run() -> void:
	await frames(3)
	var vs := root.get_visible_rect().size
	say("画面 %s，渲染 %s，存档 %s（自检档 %s），手机画质档 %s，随包字体 %s" % [vs, RenderingServer.get_current_rendering_method(), ExProfile._path(),
			ExProfile.test_mode(), Vfx.lite, UiStyle.force_bundled])
	check("存档走自检档", ExProfile.test_mode())
	if not ExProfile.test_mode():
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
	check("开的是备战页、停在背包", str(ui.call("tab_key")) == "prep" and str(page().call("list_key")) == "bag")
	check("一进来自动选中第一件（右边不空着）", str(page().call("detail_name")) != "" and (page().get("_detail") as Control).visible, str(page().call("detail_name")))
	check("没有题头、没有换英雄的入口", not (ui.get("_title") as Control).visible and not (ui.get("_subtitle") as Control).visible
			and not page().has_method("_open_heroes") and (page().get("_doll") as Object).get_signal_connection_list("tapped").is_empty())
	var pw0 := int(page().call("power_shown"))
	check("战力 = 按身上装备算出来的数", pw0 == int(MetaKit.power(ExProfile.equipment())) and pw0 > 0, "%d，显示「%s」" % [pw0, (page().get("_pw_num") as Label).text])
	await shot("1_prep_bag")

	# ---------- 备战 ----------
	var p := page()
	var wi := bag_i("w_pojun_4")
	p.call("select", "bag", wi)
	await wait(0.4)
	say("选中背包里的破军锤：%s，按钮 %s" % [p.call("detail_name"), str(p.call("action_texts"))])
	await shot("2_prep_selected")
	var old_w := str((ExProfile.equipment()["weapon"] as Dictionary).get("id", ""))
	var ok := bool(p.call("press_action", "穿戴"))
	await wait(0.16)
	await shot("3_prep_equip_fly")
	await wait(0.7)
	var pw1 := int(p.call("power_shown"))
	check("换了兵刃战力跟着变（史诗 → 传奇：降）", pw1 == int(MetaKit.power(ExProfile.equipment())) and pw1 < pw0 and (p.get("_pw_num") as Label).text == MetaKit.fmt_int(pw1),
			"%d → %d，显示「%s」" % [pw0, pw1, (p.get("_pw_num") as Label).text])
	check("穿戴兵刃：身上换成破军锤，原来那把回背包", ok and str((ExProfile.equipment()["weapon"] as Dictionary).get("id", "")) == "w_pojun_4" and bag_i(old_w) >= 0,
			"身上 %s，原来的 %s 在背包第 %d 格" % [(ExProfile.equipment()["weapon"] as Dictionary).get("id", ""), old_w, bag_i(old_w)])
	# 仓库：穿法宝
	p.call("goto", "stash")
	await wait(0.5)
	await shot("4_prep_stash")
	p.call("select", "stash", stash_i("c_pierce_7"))
	await wait(0.3)
	ok = bool(p.call("press_action", "穿戴"))
	await wait(0.8)
	var chips: Array = ExProfile.equipment()["chip"]
	check("从仓库直接穿法宝", ok and str((chips[0] as Dictionary).get("id", "")) == "c_pierce_7", str(chips.map(func(c: Dictionary) -> String: return str(c.get("id", "-")))))
	var pw2 := int(p.call("power_shown"))
	check("穿上法宝战力涨", pw2 > pw1 and pw2 == int(MetaKit.power(ExProfile.equipment())), "%d → %d" % [pw1, pw2])
	await shot("4b_prep_power_up")
	p.call("select", "equip", 0, "chip")
	await wait(0.3)
	await shot("5_prep_equip_selected")
	say("选中身上的法宝：按钮 %s" % str(p.call("action_texts")))
	ok = bool(p.call("press_action", "卸下"))
	await wait(0.7)
	check("卸下法宝回背包", ok and (chips[0] as Dictionary).is_empty() and bag_i("c_pierce_7") >= 0)
	# 存 / 取
	var n_bag := ExProfile.bag().size()
	p.call("goto", "bag")
	await wait(0.4)
	p.call("select", "bag", bag_i("thr_lei"))
	await frames(3)
	ok = bool(p.call("press_action", "存进仓库"))
	await wait(0.6)
	check("背包 → 仓库", ok and bag_i("thr_lei") < 0 and stash_i("thr_lei") >= 0 and ExProfile.bag().size() == n_bag - 1)
	p.call("goto", "stash")
	await wait(0.4)
	p.call("select", "stash", stash_i("med_da"))
	await frames(3)
	ok = bool(p.call("press_action", "带上"))
	await wait(0.6)
	check("仓库 → 背包", ok and bag_i("med_da") >= 0)
	# 点空的装备栏：卸下衣，再点那一格 → 筛出法衣
	p.call("select", "equip", 1, "armor")
	await frames(3)
	p.call("press_action", "卸下")
	await wait(0.6)
	p.call("_on_slot", "armor", 1)
	await wait(0.5)
	check("点空的装备栏筛出法衣", str(p.get("_filter")) == "armor" and (p.get("_tiles") as Array).size() > 0, "筛选 %s，这一边 %s，%d 件" % [p.get("_filter"),
			p.call("list_key"), (p.get("_tiles") as Array).size()])
	await shot("6_prep_filter_armor")
	p.call("set_filter", "all")
	await wait(0.3)
	# 卖史诗以上的：要确认
	p.call("goto", "stash")
	await wait(0.4)
	var ls0 := ExProfile.lingshi()
	var si := stash_i("s80")
	var v80 := ExData.value_of(ExProfile.stash()[si])
	p.call("select", "stash", si)
	await frames(3)
	say("选中仓库里的 %s（值 %d）：按钮 %s" % [p.call("detail_name"), v80, str(p.call("action_texts"))])
	p.call("press_action", "卖出")
	await wait(0.35)
	check("卖史诗以上的先弹确认、还没卖", bool(ui.call("modal_open")) and ExProfile.lingshi() == ls0)
	await shot("7_prep_confirm")
	ok = bool(ui.call("press_confirm"))
	await wait(0.7)
	check("确认后卖出、灵石到账", ok and ExProfile.lingshi() == ls0 + v80 and stash_i("s80") < 0, "灵石 %d → %d" % [ls0, ExProfile.lingshi()])
	# 整理 / 扩容
	(p.get("_sort") as Button).pressed.emit()
	await wait(0.4)
	var cap0 := ExProfile.stash_cap()
	(p.get("_grow") as Button).pressed.emit()
	await wait(0.5)
	check("仓库扩容 +6 格", ExProfile.stash_cap() == cap0 + 6, "%d → %d" % [cap0, ExProfile.stash_cap()])
	await shot("8_prep_stash_grown")

	# ---------- 坊市 ----------
	ui.call("_set_tab", "shop")
	await wait(0.3)
	await shot("9_shop_enter")
	await wait(0.8)
	check("换到坊市页", str(ui.call("tab_key")) == "shop" and str(page().call("cat_key")) == "weapon")
	p = page()
	await shot("10_shop_weapon")
	p.call("select", int(p.call("find_id", "w_panlong_5")))
	await wait(0.4)
	await shot("11_shop_selected")
	ls0 = ExProfile.lingshi()
	var price := ExData.shop_price("w_panlong_5")
	ok = bool(p.call("press_action", "买 1"))
	await wait(0.7)
	check("买史诗盘龙枪", ok and ExProfile.lingshi() == ls0 - price and bag_i("w_panlong_5") >= 0, "灵石 %d → %d（价 %d）" % [ls0, ExProfile.lingshi(), price])
	p.call("goto", "med")
	await wait(0.6)
	await shot("12_shop_med")
	p.call("select", int(p.call("find_id", "med_jinchuang")))
	await frames(3)
	ls0 = ExProfile.lingshi()
	var n0 := ExData.count_id(ExProfile.bag(), "med_jinchuang")
	ok = bool(p.call("press_action", "买 10"))
	await wait(0.6)
	check("买 10 个金疮药", ok and ExData.count_id(ExProfile.bag(), "med_jinchuang") == n0 + 10 and ExProfile.lingshi() == ls0 - ExData.shop_price("med_jinchuang") * 10)
	p.call("goto", "chip")
	await wait(0.6)
	await shot("13_shop_chip")
	p.call("goto", "black")
	await wait(0.6)
	var xy0 := ExProfile.xianyu()
	p.call("select", int(p.call("find_id", "key")))
	await wait(0.3)
	await shot("14_shop_black")
	ok = bool(p.call("press_action", "买入"))
	await wait(0.6)
	check("黑市买禁室玉钥", ok and ExProfile.xianyu() == xy0 - ExData.black_price("key"), "仙玉 %d → %d" % [xy0, ExProfile.xianyu()])
	p.call("goto", "sell")
	await wait(0.6)
	await shot("15_shop_sell")
	var goods: Array = p.get("_goods")
	check("出售栏列出背包 + 仓库里能卖的", goods.size() >= 3, "%d 件" % goods.size())
	var s40 := int(p.call("find_id", "s40"))
	p.call("select", s40)
	await frames(3)
	ls0 = ExProfile.lingshi()
	var unit := ExData.unit_value((goods[s40] as Dictionary)["item"])
	say("出售栏选中 s40：按钮 %s" % str(p.call("action_texts")))
	ok = bool(p.call("press_action", "卖 1 个"))
	await wait(0.2)
	if bool(ui.call("modal_open")):
		ui.call("press_confirm")
	await wait(0.5)
	check("一叠里卖 1 个", ok and ExProfile.lingshi() == ls0 + unit, "灵石 %d → %d（单价 %d）" % [ls0, ExProfile.lingshi(), unit])
	ls0 = ExProfile.lingshi()
	var sm: Array = ExProfile.sellable_sum("all")
	ok = bool(p.call("press_bulk", "all"))
	await wait(0.3)
	if int(sm[2]) > 0:
		check("一键卖出里有史诗以上的先弹确认", bool(ui.call("modal_open")))
		await shot("16_shop_bulk_confirm")
		ui.call("press_confirm")
	await wait(0.8)
	check("一键卖出全部售卖物", ok and ExProfile.lingshi() == ls0 + int(sm[1]) and int(ExProfile.sellable_sum("all")[0]) == 0, "灵石 %d → %d（应得 %d）" % [ls0,
			ExProfile.lingshi(), int(sm[1])])
	await shot("17_shop_sold")

	# ---------- 段位 ----------
	ui.call("_set_tab", "rank")
	await wait(0.35)
	await shot("18_rank_enter")
	await wait(1.2)
	check("换到段位页", str(ui.call("tab_key")) == "rank")
	await shot("19_rank")

	# ---------- 老编号 / 英雄 ----------
	ui.call("_set_tab", 0)
	await wait(0.9)
	check("老编号 0 = 备战页翻到仓库", str(ui.call("tab_key")) == "prep" and str(page().call("list_key")) == "stash" and int(ui.get("_tab")) == 0)
	ui.call("_set_tab", 1)
	await wait(0.9)
	check("老编号 1 = 坊市", str(ui.call("tab_key")) == "shop" and int(ui.get("_tab")) == 1)
	ui.call("_set_tab", "prep")
	await wait(0.9)
	await shot("20_prep_final")
	ui.call("open_heroes")          # 备战页上已经没有换英雄的入口：这里走壳的接口（老编号 5 / 主城「英雄」入口换完回来时也是这条路）
	await wait(1.4)
	var hs: Variant = ui.get("_hero_ui")
	check("壳的接口开英雄选择界面、这边藏起来", is_instance_valid(hs) and not ui.visible)
	if is_instance_valid(hs):
		hs.set("wheel", false)
		hs.call("goto_id", "yujian", true)
		await wait(0.4)
		var at := str(hs.call("current_id"))
		var picked := bool(hs.call("pick"))
		await wait(0.5)
		hs.call("close")
		await wait(0.9)
		check("换了英雄回来，备战页的人跟着换", ui.visible and ExProfile.hero() == "yujian" and str((page().get("_doll") as Control).get("hero_id")) == "yujian",
				"英雄界面停在 %s，pick=%s；回来后 界面可见=%s 存档=%s 小像=%s" % [at, picked, ui.visible, ExProfile.hero(), (page().get("_doll") as Control).get("hero_id")])
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
