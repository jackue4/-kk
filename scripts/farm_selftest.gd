extends RefCounted
## 灵田种植自检（2026-11-23；hub_hall.gd 的 farm_plant_selftest 转过来）：`-- --hub-shot --farm-plant [--touch]`，约 1 分钟，截图存 _shots/plant_*.png（手机档加 m_ 前缀）。
## 走一遍：境界开垦 / 灵种门槛 → 不在灵田上按钮是「整备」、按下去右侧开灵种背包 → 选一种 → 站上空灵田按钮变「播种」、点一下种一格、按住连种满 16 格、扣灵石
## → 拨时间到成熟、按钮变「收获」、一下收一整块、头顶小条、进仓库 → 化神六块全开、九种混种、各生长阶段同屏（截图 + 帧耗时）
## → 丹房「灵草 + 灵果」炼中品 → 老存档（十二块单格地）挪进新格子 → 仓库满了收到哪算哪 → 存档字段 → 触屏「攻」的字和农场里收起的按钮 → 出农场复原
## 故意不写 class_name：hub_hall.gd 运行时 load。

const FarmData := preload("res://scripts/farm_data.gd")
const FarmPlots := preload("res://scripts/farm_plots.gd")
const HubFarm := preload("res://scripts/hub_farm.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const Items := preload("res://scripts/raid_items.gd")


static func run(hub: Node) -> void:
	var tree := hub.get_tree()
	var tag := "m_" if bool(hub.get("mobile")) else ""
	var cam: Variant = hub.get("cam")
	var player: Variant = hub.get("player")
	var P: Variant = hub.get("farm").get("plots")
	var O := HubFarm.ORIGIN
	var touch: Variant = hub.get("main").get("touch") if hub.get("main") != null else null
	var shot := func(nm: String) -> void:
		await RenderingServer.frame_post_draw
		hub.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_shots/plant_%s%s.png" % [tag, nm]))
	var wait := func(sec: float) -> void:
		await tree.create_timer(sec).timeout
	var view := func(eye: Vector3, at: Vector3, fov: float) -> void:
		cam.cine_xf = Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)
		cam.cine_fov = fov
		cam.cine_k = 1.0
	var go := func(pos: Vector3, yaw: float) -> void:
		player.force_ground()
		player.global_position = pos
		player.velocity = Vector3.ZERO
		player.face_now(yaw)
		cam.cine_k = 0.0
		cam.snap(yaw, CameraRig.PITCH_DEFAULT, CameraRig.ZOOM_DEFAULT)
		hub.set("_last_xz", Vector2(pos.x, pos.z))
		hub.set("_prev_p", pos)
	## 按一下（或按住 hold 秒）种植按钮：和触屏「攻」/ J 一样发 attack 动作
	var press := func(hold: float) -> void:
		var ev := InputEventAction.new()
		ev.action = "attack"
		ev.pressed = true
		ev.strength = 1.0
		Input.parse_input_event(ev)
		await tree.create_timer(hold).timeout
		var ev2 := InputEventAction.new()
		ev2.action = "attack"
		ev2.pressed = false
		Input.parse_input_event(ev2)
		await tree.process_frame
		await tree.process_frame
	## 现在种植按钮上写的字（触屏看「攻」，桌面看底部按钮）
	var label := func() -> String:
		if is_instance_valid(touch):
			return str(touch.get("attack_text"))
		var ub: Button = hub.get("_use_btn")
		return ub.text.replace(" ", "") if ub.visible else "（没出按钮）"
	var filled := func(f: int) -> int:
		var n := 0
		for k in 16:
			if not FarmPlots.cell_state(f * 16 + k).is_empty():
				n += 1
		return n
	var res: Array[String] = []
	await wait.call(1.2)
	# 0 干净的开局：炼气、灵石够、灵田全空、手里没灵种
	Profile.data()["realm"] = 0
	player.set_realm(0, false)
	Profile.data()["lingshi"] = 60000
	var cs := FarmPlots.cells()
	for c in cs.size():
		cs[c] = {}
	FarmPlots.data()["seed"] = ""
	FarmPlots.time_offset = 0.0
	hub.set("area", "farm")
	hub.call("_apply_area")
	go.call(hub.get("farm").call("spawn_point"), 0.0)
	await wait.call(0.8)
	# 1 境界开垦、灵种门槛
	var n_open := 0
	for f in FarmPlots.FIELDS.size():
		if FarmPlots.field_unlocked(f):
			n_open += 1
	res.append("炼气期开垦 %d 块（应 1）、共 %d 块 %d 格；炼气种血灵花：%s；在筑基才开的地上种：%s" % [n_open, FarmPlots.FIELDS.size(), FarmPlots.cell_count(),
			P.sow(0, "bloodflower"), P.sow(16, "ginseng")])
	# 2 不在灵田上：按钮「整备」，按下去开灵种背包
	var l0: String = label.call()
	await press.call(0.1)
	await wait.call(0.3)
	var bag0: bool = P.bag_open()
	await shot.call("0_bag")
	P.set_tab(1)
	await wait.call(0.2)
	await shot.call("0_bag_fruit")
	P.pick("ginseng")
	P.set_tab(0)
	var e_choose: String = P.choose("ginseng")
	res.append("出生点：按钮「%s」（应 整备）；按下去背包开了=%s；选百年灵参：%s，手里=%s、背包关了=%s" % [l0, bag0, e_choose if e_choose != "" else "成",
			FarmPlots.seed_id(), not P.bag_open()])
	# 3 站上第一块灵田：「播种」，点一下种一格，按住连种
	var f0: Vector3 = O + FarmPlots.FIELDS[0]
	go.call(f0 + Vector3(0.0, 0.1, 3.0), 0.0)
	await wait.call(0.5)
	var l1: String = label.call()
	var ls0 := Profile.lingshi()
	await press.call(0.08)
	await wait.call(0.2)
	var n_tap: int = filled.call(0)
	await shot.call("1_sow_tap")
	await press.call(2.7)
	await wait.call(0.3)
	var n_hold: int = filled.call(0)
	var l2: String = label.call()
	await shot.call("2_sown")
	res.append("站上第一块灵田：按钮「%s」（应 播种）；点一下种了 %d 格（应 1）；按住 2.7 秒共 %d 格（应 16）；扣灵石 %d（应 %d）；种满以后按钮「%s」（应 整备）" % [
			l1, n_tap, n_hold, ls0 - Profile.lingshi(), 16 * int(FarmData.plant("ginseng")["price"]), l2])
	# 4 拨时间到成熟：「收获」，一下收一整块
	FarmPlots.time_offset += 400.0
	P.refresh_all()
	await wait.call(0.6)
	var l3: String = label.call()
	await shot.call("3_ripe")
	var st0 := Profile.stash().size()
	await press.call(0.08)
	await wait.call(0.25)
	await shot.call("4_gain")
	var got := Profile.stash().size() - st0
	await wait.call(0.6)
	await shot.call("4_gain_b")
	res.append("拨时间 400 秒：按钮「%s」（应 收获）；按一下仓库多了 %d 件（16 株 × 1~2）、地里剩 %d 株（应 0）、头顶小条 %d 张" % [l3, got, filled.call(0), (P.get("_gains") as Array).size()])
	# 5 化神：六块全开，九种混种，每块地从南往北四排是四个生长进度
	Profile.data()["realm"] = 4
	player.set_realm(4, false)
	FarmPlots.time_offset = 0.0
	P.refresh_all()
	go.call(f0 + Vector3(0.0, 0.1, 5.0), 0.0)
	await wait.call(0.8)
	var perf_empty: String = await hub.call("_perf_probe", 2.0)       # 同一个机位：灵田全空 vs 96 株（同一次运行里比才可信）
	var errs: Array[String] = []
	for c in FarmPlots.cell_count():
		var pd: Dictionary = FarmData.PLANTS[c % FarmData.PLANTS.size()]
		var e: String = P.sow(c, str(pd["id"]), true)
		if e != "":
			errs.append(e)
		var row := (c % 16) / 4
		var frac: float = [1.0, 0.72, 0.42, 0.12][row]
		(FarmPlots.cells()[c] as Dictionary)["t0"] = FarmPlots.now() - float(pd["grow"]) * frac - (1.0 if frac >= 1.0 else 0.0)
	P.refresh_all()
	var n_unlock := 0
	for f in FarmPlots.FIELDS.size():
		if FarmPlots.field_unlocked(f):
			n_unlock += 1
	res.append("化神期开垦 %d 块（应 6）；96 格九种混种出错 %s；熟了的 %d 株（应 24）" % [n_unlock, str(errs), FarmPlots.ripe_count()])
	view.call(O + Vector3(34.0, 24.0, 46.0), O + Vector3(34.0, 0.0, 11.0), 52.0)
	await wait.call(0.8)
	await shot.call("5_overview")
	view.call(O + Vector3(24.0, 10.0, 17.5), O + Vector3(24.0, 0.6, 2.0), 58.0)
	await wait.call(0.5)
	await shot.call("5_field_w")
	view.call(O + Vector3(47.0, 9.0, 15.5), O + Vector3(47.0, 0.6, 2.0), 56.0)
	await wait.call(0.5)
	await shot.call("5_field_e")
	cam.cine_k = 0.0
	go.call(f0 + Vector3(0.0, 0.1, 5.0), 0.0)
	await wait.call(0.6)
	var perf_full: String = await hub.call("_perf_probe", 2.0)
	var groups := 0
	for g: Dictionary in (P.get("_groups") as Dictionary).values():
		if not (g["cells"] as Array).is_empty():
			groups += (g["mmis"] as Array).size()
	res.append("站在第一块地南边，灵田全空：%s；96 株同屏：%s；合批后植株一共 %d 个 MultiMesh" % [perf_empty, perf_full, groups])
	# 6 丹房：灵草 + 灵果 → 中品
	var mid: Dictionary = {}
	for r: Dictionary in Items.recipes():
		if str(r["out"].get("kind", "")) == "pill" and int(r["out"].get("grade", 0)) == 1 and int(r["out"].get("tier", -1)) == 0:
			mid = r
	if not mid.is_empty() and not Profile.can_craft(mid):
		Profile.stash().append(Items.herb(0))
		Profile.stash().append(FarmData.fruit("七彩灵莓"))
	var err_c: String = Profile.craft(mid) if not mid.is_empty() else "没有丹方"
	res.append("丹房中品丹方 %d 条；炼「%s」：%s" % [FarmData.recipes().size(), str(mid.get("out", {}).get("name", "?")), "成" if err_c == "" else err_c])
	# 7 老存档：上午那版十二块单格地里种着的挪进前几格
	var farm_bak: Dictionary = (Profile.data()["farm"] as Dictionary).duplicate(true)
	var t_old := FarmPlots.now() - 50.0
	Profile.data()["farm"] = {"plots": [{"id": "ginseng", "t0": t_old}, {}, {"id": "higan", "t0": t_old - 5.0}, {}], "seed": "berry"}
	var mig := FarmPlots.data()
	var mc: Array = mig["cells"]
	res.append("老存档挪进新格子：第 1 格 %s、第 2 格 %s（应 ginseng / higan）、种下时刻保留=%s、plots 删了=%s、格数 %d" % [str(mc[0].get("id", "空")), str(mc[1].get("id", "空")),
			is_equal_approx(float(mc[0].get("t0", 0.0)), t_old), not mig.has("plots"), mc.size()])
	Profile.data()["farm"] = farm_bak
	P.refresh_all()
	# 8 仓库按格算（2026-11-23）：灵草 / 灵果同样的叠成一格（一格最多 99 件），别的一件一格；满了收到哪算哪，余下的留在地里
	var stash_bak: Array = Profile.stash().duplicate(true)
	var ripe16 := func() -> void:
		for k in 16:
			FarmPlots.cells()[k] = {"id": "ginseng", "t0": FarmPlots.now() - 999.0}
		P.refresh_all()
	var mats := func(n: int) -> void:
		var s0: Array = Profile.stash()
		s0.clear()
		for q in n:
			s0.append(Items.mat(q % 3))
	go.call(f0 + Vector3(0.0, 0.1, 3.0), 0.0)
	await wait.call(0.4)
	mats.call(58)
	ripe16.call()
	var hv: Dictionary = P.harvest_field(0)
	var herbs_in := Profile.stash().size() - 58
	res.append("仓库 58 格放着灵材（不叠）、收一整块熟灵参：收了 %d 株（应 16）、%d 件灵参叠成一格、仓库 %d/%d 格（应 59）、留在地里 %d 株（应 0）" % [
			int(hv["cells"]), herbs_in, Profile.stash_slots(), Profile.STASH_CAP, int(hv["left"])])
	mats.call(60)
	ripe16.call()
	hv = P.harvest_field(0)
	res.append("仓库 60 格占满、地里 16 株熟了：收了 %d 株（应 0）、留在地里 %d 株（应 16）" % [int(hv["cells"]), int(hv["left"])])
	mats.call(59)
	for q in Profile.STACK_MAX - 1:
		Profile.stash().append(Items.herb(0))
	res.append("59 格灵材 + 98 件灵参（共 %d 格）：再放 1 件灵参=%s（应 true，叠进那一格）、再放 2 件=%s（应 false，要开第 61 格）、放 1 件灵材=%s（应 false）" % [
			Profile.stash_slots(), Profile.stash_fits(Items.herb(0), 1), Profile.stash_fits(Items.herb(0), 2), Profile.stash_fits(Items.mat(0), 1)])
	Profile.data()["stash"] = stash_bak
	for k in 16:
		FarmPlots.cells()[k] = {}
	P.refresh_all()
	# 9 存档字段
	Profile.save()
	var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(Profile._path()))
	var sf: Dictionary = (js as Dictionary).get("farm", {}) if js is Dictionary else {}
	res.append("存档 farm 字段：cells %d 格、seed「%s」、没有老的 plots=%s、_fresh 有 farm=%s" % [(sf.get("cells", []) as Array).size(), str(sf.get("seed", "")),
			not sf.has("plots"), Profile._fresh().has("farm")])
	# 10 触屏：农场里「攻」的字、收起的按钮；出农场复原
	if is_instance_valid(touch):
		var hidden: Array[String] = []
		for b: Dictionary in (touch.get_script() as Script).get_script_constant_map()["BUTTONS"]:
			if not touch.call("_btn_on", b):
				hidden.append(str(b["text"]))
		res.append("触屏在农场：peace=%s、收起的按钮 %s、「攻」上写「%s」" % [str(touch.get("peace")), str(hidden), str(touch.get("attack_text"))])
	hub.set("area", "town")
	hub.call("_apply_area")
	await wait.call(0.3)
	var back := "出农场：plots.on=%s" % str(P.get("on"))
	if is_instance_valid(touch):
		back += "、peace=%s、「攻」的字「%s」（应空）" % [str(touch.get("peace")), str(touch.get("attack_text"))]
	res.append(back)
	FarmPlots.time_offset = 0.0
	for r2: String in res:
		print("[plant] " + r2)
	print("[plant] done")
