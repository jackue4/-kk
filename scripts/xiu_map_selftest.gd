extends Node
## 新两关跑修仙玩法的整局自检（2026-11-25 主干解耦，W2a，_tasks/decouple/CONTRACT.md 第 4 节「自检」）：
##   `-- --level-test desert|lab`（或 --level-test=desert；可加 --headless，不截图）。main.gd 见到参数就 load 这个脚本、设 m（main）和 arg（图 id）。
## 正常开机到主城 → 单人进图，用测试存档（raid_profile 的 selftest 档，每次清空，正式存档不碰）。逐项：
##   0 境界守卫：境界设成结丹（2）进图 → 关卡不建管理器、提示后退回主城
##   1 境界设成元婴（3）进图：挂的是 raid_manager、geo 是新图那份、刷怪点是点表模式、搜点 / 传送阵 / 巢穴按点表建好，亮的传送阵数对得上
##   2 帧耗：进图后几秒的平均 / 最长帧
##   3 刷怪点：地面、地下各走近一处，建出来的怪的区域档 / 等级 / 血量 / 攻击和第 3 节的表、老公式对得上；打死一只，心得按倍率记上
##   4 搜点：站上一个搜点读条，搜出来的是老物品（raid_items），拾进背包
##   5 首领：走近巢穴自动刷出（挂了 ExBoss 大脑），打死后巢穴记空、遗藏里有破境丹残片、镇守阵亮了
##   6 撤离：站进亮着的传送阵读条，撤离成功 → 背包进仓库，回到主城
##   7 陨落：再进一次，带着法宝和背包里的东西被打死 → 背包、法宝丢了，储物戒留着，陨落次数 +1，回到主城
## 每步打一行「[xiu] 名字 PASS/FAIL · 细节」，最后「[xiu] 总计 失败 N 项」。故意不写 class_name。

const Data := preload("res://scripts/raid_data.gd")
const Prog := preload("res://scripts/progression.gd")
const CS := preload("res://scripts/combat_stats.gd")
const Items := preload("res://scripts/raid_items.gd")
const Profile := preload("res://scripts/raid_profile.gd")
const MapDef := preload("res://scripts/ex/map_def.gd")

const LIMIT := 600.0

var m: Node                    # main.gd
var arg := ""
var map_id := "desert"
var fails := 0
var passes := 0
var level: Node3D
var mgr: Node3D
var player: Player
var cam: CameraRig
var keep := false              # 每帧把气血拉满
var _t0 := 0


func _ready() -> void:
	var c: Node = m.get("cam")
	if c != null:
		c.set("capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	map_id = arg if arg == "lab" else "desert"
	_t0 = Time.get_ticks_msec()
	_run()


func _process(_dt: float) -> void:
	if keep and player != null and is_instance_valid(player) and not player.dead:
		player.melee.hp = player.melee.HP_MAX
	if Time.get_ticks_msec() - _t0 > int(LIMIT * 1000.0):
		say("超时 %.0f 秒：退出" % LIMIT)
		print("[xiu] 总计 失败 %d 项（超时）" % (fails + 1))
		get_tree().quit(1)


func say(s: String) -> void:
	print("[xiu] " + s)


func check(name: String, ok: bool, detail := "") -> bool:
	if ok:
		passes += 1
	else:
		fails += 1
	say("%s %s · %s" % [name, "PASS" if ok else "FAIL", detail])
	return ok


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await wait(1.5)
	player = m.get("player")
	cam = m.get("cam")
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--xiu-lan="):
			await run_lan(a.get_slice("=", 1))
			say("总计 失败 %d 项（通过 %d 项，用时 %.0f 秒）" % [fails, passes, float(Time.get_ticks_msec() - _t0) / 1000.0])
			await wait(1.0)
			get_tree().quit(0 if fails == 0 else 1)
			return
	if arg == "mulan":
		await run_mulan()
		say("总计 失败 %d 项（通过 %d 项，用时 %.0f 秒）" % [fails, passes, float(Time.get_ticks_msec() - _t0) / 1000.0])
		await wait(0.5)
		get_tree().quit(0 if fails == 0 else 1)
		return
	say("自检开始：%s 测试存档 %s" % [map_id, Profile.test_mode()])
	await step_guard()
	if await enter(3):
		await step_setup()
		await step_frame_cost()
		await step_camps()
		await step_search()
		await step_boss()
		await step_extract()
	if await enter(3):
		await step_death()
	say("总计 失败 %d 项（通过 %d 项，用时 %.0f 秒）" % [fails, passes, float(Time.get_ticks_msec() - _t0) / 1000.0])
	await wait(0.5)
	get_tree().quit(0 if fails == 0 else 1)


## 设境界（存档 + 主角）：测试模式下 main 进图时保留主角现在的境界（_apply_combat_mode）
func set_realm(r: int) -> void:
	Profile.data()["realm"] = r
	player.set_realm(r, false)
	var cu := Profile.cult(r)
	Profile.set_cult(int(cu[0]), float(cu[1]))


func enter(realm: int) -> bool:
	set_realm(realm)
	m.get("level_ui").set("mode", "solo")
	var t0 := Time.get_ticks_msec()
	await m.call("_enter_level", "mulan" if arg == "mulan" else map_id)
	while bool(m.get("_switching")):
		await get_tree().process_frame
	level = m.get("level")
	if level == null:
		check("进图（境界 %d）" % realm, false, "进不了 " + map_id)
		return false
	mgr = level.get("raid")
	if mgr == null:
		check("进图（境界 %d）" % realm, false, "关卡没有建管理器")
		return false
	var ok := str((mgr.get_script() as Script).resource_path).ends_with("scripts/raid_manager.gd") and bool(mgr.get("running"))
	return check("进图（境界 %d）" % realm, ok, "%s 用时 %d ms 出生 %s 境界 %s 管理器 %s" % ["mulan" if arg == "mulan" else map_id, Time.get_ticks_msec() - t0,
			str(player.global_position.snapped(Vector3.ONE)), str(player.realm.get("name", "")), str((mgr.get_script() as Script).resource_path)])


## 等关卡退出、回到主城
func wait_hub(limit := 25.0) -> bool:
	var tw := 0.0
	while m.get("level") != null and tw < limit:
		await get_tree().process_frame
		tw += get_process_delta_time()
	while bool(m.get("_switching")) and tw < limit + 10.0:
		await get_tree().process_frame
		tw += get_process_delta_time()
	await wait(0.5)
	return m.get("level") == null


# ---------- 局域网双开（`--level-test desert --xiu-lan=host` + `… --xiu-lan=join`，同一台机器、测试端口 +100，可 --headless） ----------
## 两人进同一张图（net.map_id 分房）、站到同一座巢穴边：首领只有一只（房主仲裁：先到的房主刷真身，加入方建木偶）；
## 加入方站到房主建着的刷怪点边上：不自己再建、看到的是房主那份的木偶

func _lan_wait(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if bool(cond.call()):
			return true
		await wait(0.2)
		t += 0.2
	return bool(cond.call())


func run_lan(role: String) -> void:
	var net: Node = m.get("net")
	var host := role == "host"
	var tag := "lan-" + role
	await wait(0.5 if host else 10.0)
	say("%s 开始：%s 端口偏移 %d" % [tag, map_id, int(net.get("port_off"))])
	net.set("my_name", "房主甲" if host else "加入乙")
	var ui: Node = m.get("level_ui")
	var entered := false
	set_realm(3)
	for attempt in (1 if host else 5):
		ui.set("team_size", 2)
		ui.set("mode", "host" if host else "join")
		ui.set("join_ip", "127.0.0.1")
		await m.call("_enter_level", map_id)
		while bool(m.get("_switching")):
			await get_tree().process_frame
		if m.get("level") != null:
			entered = true
			break
		say("%s 第 %d 次没连上，4 秒后再试" % [tag, attempt + 1])
		await wait(4.0)
	level = m.get("level")
	mgr = level.get("raid") if level != null else null
	if not check(tag + " 进图", entered and mgr != null and bool(net.get("active")) and str(net.get("map_id")) == map_id,
			"联机 %s 房主 %s 我是 %d 房间图 %s" % [net.get("active"), net.get("is_host"), int(net.get("my_id")), str(net.get("map_id"))]):
		return
	keep = true
	var seen := await _lan_wait(func() -> bool: return (net.get("remotes") as Dictionary).size() >= 1, 60.0)
	check(tag + " 看见对方", seen, "remotes %d" % (net.get("remotes") as Dictionary).size())
	if not seen:
		return
	# 巢穴：凌幽（地面第一座）
	var b: Dictionary = {}
	for e: Dictionary in mgr.get("_bosses"):
		if str(e["layer"]) == "surface" and str(e.get("key2", "")) == "":
			b = e
			break
	var bp: Vector3 = b["pos"]
	var stand := Vector3(bp.x + (14.0 if host else 18.0), bp.y, bp.z + 4.0)
	if not host:
		await _lan_wait(func() -> bool: return int(b["state"]) == 1, 6.0)      # 先别走近：等房主那只的消息到
	await put(stand)
	await _lan_wait(func() -> bool: return int(b["state"]) == 1 and b.get("node") != null and is_instance_valid(b["node"]), 12.0)
	await wait(3.0)
	var n: Variant = b.get("node")
	var real := n != null and is_instance_valid(n) and not bool(n.get("puppet"))
	var pup := n != null and is_instance_valid(n) and bool(n.get("puppet"))
	var reals := 0
	for mb: Variant in mgr.call("_my_mobs"):
		if is_instance_valid(mb) and bool(mb.get("boss")):
			reals += 1
	check(tag + " 首领只有一只（房主仲裁）", (real and reals == 1) if host else (pup and reals == 0),
			"巢穴状态 %d 真身 %s 木偶 %s 我名下首领 %d 主人 %d" % [int(b["state"]), str(real), str(pup), reals, int(b.get("owner", 0))])
	if not host:
		# 刷怪点：房主身边建着的点，我这边只建木偶
		var my_camp := 0
		var pup_camp := 0
		for mb2: Variant in mgr.get("_mobs"):
			if is_instance_valid(mb2) and mb2.has_meta("camp"):
				my_camp += 1
		for pp2: Variant in (mgr.get("_puppets") as Dictionary).values():
			if is_instance_valid(pp2) and pp2.has_meta("camp"):
				pup_camp += 1
		say("%s 刷怪点：我名下 %d 只、别人名下的木偶 %d 只" % [tag, my_camp, pup_camp])
		await wait(2.0)
	else:
		await wait(20.0)      # 等加入方测完再走
	keep = false


# ---------- 大世界回归（`--level-test mulan`）：geo 转接之后木兰草原照旧 ----------

func run_mulan() -> void:
	say("大世界回归开始：测试存档 %s" % Profile.test_mode())
	if not await enter(0):
		return
	var geo: Variant = mgr.get("geo")
	check("大世界 geo", geo != null and not bool(geo.fixed) and bool(geo.loop) and not bool(geo.own_atmo)
			and str((geo.get_script() as Script).resource_path).ends_with("scripts/raid_geo.gd"), "loop %s fixed %s" % [str(geo.loop), str(geo.fixed)])
	var bosses: Array = mgr.get("_bosses")
	var lid_ok := bosses.size() == 5
	for b: Dictionary in bosses:
		if int(b["lid"]) != int(b["region"]):
			lid_ok = false
	check("巢穴编号 = 区域", lid_ok, "巢穴 %d" % bosses.size())
	var gates := 0
	var lit := 0
	var paid := 0
	var bg := 0
	for e: Dictionary in mgr.get("_extracts"):
		if e.has("base"):
			gates += 1
			if bool(e["active"]):
				lit += 1
				paid += 1 if str(e["kind"]) == "paid" else 0
		elif str(e.get("kind", "")) == "boss":
			bg += 1
			if int(e.get("lair", -1)) != int(e.get("region", -2)):
				lid_ok = false
	check("传送阵轮换照旧（亮 2 + 1 灵石阵）", gates == 5 and lit == 3 and paid == 1 and bg == 5 and lid_ok, "阵 %d 亮 %d 灵石阵 %d 镇守阵 %d" % [gates, lit, paid, bg])
	var camps: Variant = mgr.get("camps")
	check("刷怪点网格模式", not bool(camps.list_mode) and bool(camps.on) == OS.get_cmdline_user_args().has("--camps"),
			"list_mode %s on %s" % [str(camps.list_mode), str(camps.on)])
	var search: Node = mgr.get("search")
	var nfix := 0
	for s: Dictionary in search.get("sites"):
		if bool(s.get("fixed_y", false)):
			nfix += 1
	check("搜点照旧（固定种子撒点）", (search.get("sites") as Array).size() > 80 and nfix == 0, "搜点 %d 个" % (search.get("sites") as Array).size())
	check("地名", str(mgr.call("where_name")) == str(Data.REGIONS[int(mgr.get("region"))]["name"]), str(mgr.call("where_name")))
	# 草原巢穴：走近 200 米刷出首领（区域 0 的狼王），meta lair = 0，打掉后巢穴空、镇守阵亮
	keep = true
	var b0: Dictionary = {}
	for b2: Dictionary in bosses:
		if int(b2["region"]) == 0:
			b0 = b2
	var bp: Vector3 = b0["pos"]
	player.force_ground()
	player.global_position = Vector3(bp.x + 120.0, float(level.call("ground", bp.x + 120.0, bp.z)) + 0.5, bp.z)
	var tw := 0.0
	while int(b0["state"]) != 1 and tw < 8.0:
		await wait(0.2)
		tw += 0.2
	var bm: Variant = b0["node"]
	var alive := bm != null and is_instance_valid(bm) and bool(bm.is_alive())
	var d: Dictionary = Data.MOBS[int(Data.REGIONS[0]["boss"])]
	var hp_w := Data.BOSS_HP * float(d["hp"]) * CS.HP_CONV * CS.mob_s_hp(0, int(bm.get("lv")) if alive else 1)
	check("草原巢穴首领", alive and int(bm.get_meta("lair", -1)) == 0 and int(bm.get_meta("def_idx", -1)) == int(Data.REGIONS[0]["boss"])
			and absf(float(bm.get("hp_max")) - hp_w) < hp_w * 1e-4 and not (bm.get("block_fn") as Callable).is_valid(),
			"%s Lv.%d 血 %.0f（应 %.0f）" % [str(bm.get("display_name")) if alive else "无", int(bm.get("lv")) if alive else -1,
			float(bm.get("hp_max")) if alive else 0.0, hp_w])
	if alive:
		await _kill(bm)
		await wait(0.5)
		var lit0 := false
		for e2: Dictionary in mgr.get("_extracts"):
			if str(e2.get("kind", "")) == "boss" and int(e2.get("region", -1)) == 0 and bool(e2["active"]):
				lit0 = true
		check("草原巢穴打空 → 镇守阵亮", int(b0["state"]) == 2 and lit0, "状态 %d 镇守阵 %s" % [int(b0["state"]), str(lit0)])
	# 怪：网格刷怪点（--camps）或老导演，种类都是老表（编号 < EX_BASE）、不挂挡墙
	var tw2 := 0.0
	var mobs: Array = []
	while tw2 < 10.0:
		await wait(0.5)
		tw2 += 0.5
		mobs = []
		for mb: Variant in mgr.get("_mobs"):
			if is_instance_valid(mb) and not bool(mb.get("boss")):
				mobs.append(mb)
		if mobs.size() >= 3:
			break
	var old_ok := not mobs.is_empty()
	var n_camp := 0
	for mb2: Node3D in mobs:
		if int(mb2.get_meta("def_idx", -1)) >= Data.EX_BASE or (mb2.get("block_fn") as Callable).is_valid():
			old_ok = false
		if mb2.has_meta("camp"):
			n_camp += 1
	check("大世界的怪照旧", old_ok and (n_camp > 0) == bool(camps.on), "%d 只（刷怪点的 %d）用时 %.1f 秒" % [mobs.size(), n_camp, tw2])
	keep = false


# ---------- 0 境界守卫 ----------

func step_guard() -> void:
	set_realm(2)
	m.get("level_ui").set("mode", "solo")
	await m.call("_enter_level", map_id)
	while bool(m.get("_switching")):
		await get_tree().process_frame
	var lv: Variant = m.get("level")
	var blocked := lv == null or bool(lv.get("realm_blocked"))
	var raid_null := lv == null or lv.get("raid") == null
	var back := await wait_hub()
	check("境界守卫（结丹进不去）", blocked and raid_null and back, "关卡 %s 拦下 %s 管理器 %s 回主城 %s" % [str(lv != null), str(blocked),
			"无" if raid_null else "有", str(back)])


# ---------- 1 挂载 / 点表 ----------

func step_setup() -> void:
	var geo: Variant = mgr.get("geo")
	var camps: Variant = mgr.get("camps")
	var search: Variant = mgr.get("search")
	var md: Dictionary = MapDef.map(map_id)
	check("geo 是新图那份", geo != null and bool(geo.fixed) and not bool(geo.loop) and bool(geo.own_atmo) and str(geo.map_id) == map_id,
			"fixed %s loop %s" % [str(geo.fixed), str(geo.loop)])
	check("没有重伤 / 不回血钩子", not player.lethal_fn.is_valid() and player.regen_k > 0.0, "regen_k %.2f lethal %s" % [player.regen_k, str(player.lethal_fn.is_valid())])
	var n_camps := (md["camps"] as Array).size()
	check("刷怪点点表模式", camps != null and bool(camps.list_mode) and bool(camps.on) and (camps._cache as Dictionary).size() == n_camps,
			"点 %d / 图上 %d" % [(camps._cache as Dictionary).size(), n_camps])
	var kinds := {}
	for s: Dictionary in search.sites:
		kinds[str(s["kind"])] = int(kinds.get(str(s["kind"]), 0)) + 1
	var want: Dictionary = (md["xiu"] as Dictionary)["sites"]
	check("搜点按箱子换成老搜点", int(kinds.get("vault", 0)) == (md["key_rooms"] as Array).size() and int(kinds.get("urn", 0)) == (md["bosses"] as Array).size()
			and int(kinds.get("jar", 0)) > 0 and int(kinds.get("jar", 0)) <= int(want["supply"]) and int(kinds.get("grave", 0)) > 0 and int(kinds.get("herb", 0)) > 0,
			str(kinds))
	var gates := 0
	var lit := 0
	var paid := 0
	var bossg := 0
	for e: Dictionary in mgr.get("_extracts"):
		if e.has("base"):
			gates += 1
			if bool(e["active"]):
				lit += 1
				if str(e["kind"]) == "paid":
					paid += 1
		elif str(e.get("kind", "")) == "boss":
			bossg += 1
	var free_n := int((md["xiu"] as Dictionary)["gates_free"])
	check("古传送阵轮换", gates == (md["extracts"] as Array).size() and lit == free_n + 1 and paid == 1,
			"阵 %d 亮 %d（灵石阵 %d）应亮 %d+1 镇守阵 %d" % [gates, lit, paid, free_n, bossg])
	check("巢穴 = 点表首领", (mgr.get("_bosses") as Array).size() == (md["bosses"] as Array).size() and bossg == (md["bosses"] as Array).size(),
			"巢穴 %d" % (mgr.get("_bosses") as Array).size())
	var depth_ok := true
	var dd: Array = []
	for s2: Dictionary in search.sites:
		var dep := float(s2["depth"])
		if dep < 0.0 or dep > 1.0:
			depth_ok = false
		if str(s2["kind"]) == "vault" and dep < 0.99:
			depth_ok = false
		dd.append(snappedf(dep, 0.01))
	check("搜点深度（钥匙房 = 1）", depth_ok, "前几个 %s" % str(dd.slice(0, 8)))


# ---------- 2 帧耗 ----------

func step_frame_cost() -> void:
	var n := 0
	var tot := 0.0
	var worst := 0.0
	var t := 0.0
	while t < 4.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		n += 1
		tot += dt
		worst = maxf(worst, dt)
	say("帧耗（进图后 4 秒）：平均 %.1f ms 最长 %.1f ms 帧数 %d 怪 %d 木偶 %d 搜点节点 %d（%s）" % [tot / maxf(float(n), 1.0) * 1000.0, worst * 1000.0, n,
			(mgr.get("_mobs") as Array).size(), (mgr.get("_puppets") as Dictionary).size(), _site_nodes(), DisplayServer.get_name()])
	check("帧耗记录", n > 0, "平均 %.1f ms" % (tot / maxf(float(n), 1.0) * 1000.0))


func _site_nodes() -> int:
	var k := 0
	for s: Dictionary in (mgr.get("search") as Node).get("sites"):
		if is_instance_valid(s["node"]):
			k += 1
	return k


# ---------- 3 刷怪点 ----------

## 把主角摆到 p（落脚处），等脚下地块
func put(p: Vector3) -> void:
	player.force_ground()
	var y: float = level.call("floor_at", p.x, p.z, p.y + 1.0)
	player.global_position = Vector3(p.x, y + 0.05, p.z)
	player.velocity = Vector3.ZERO
	await frames(2)
	var world: Node = level.get("world")
	var t := 0.0
	while t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if bool(world.call("ready_near", player.global_position)) and t > 0.25:
			break
	player.global_position = Vector3(p.x, float(level.call("floor_at", p.x, p.z, p.y + 1.0)) + 0.05, p.z)
	player.velocity = Vector3.ZERO
	await frames(2)


func _camp_of(layer: String) -> Dictionary:
	var camps: Variant = mgr.get("camps")
	for id: int in camps._list_ids:
		var c: Dictionary = camps._cache[id]
		if str(c["layer"]) == layer and not ((c["elite"] as Array).has(true)):
			return c
	return {}


func step_camps() -> void:
	keep = true
	for layer: String in ["surface", "cavern"]:
		var c := _camp_of(layer)
		if c.is_empty():
			check("刷怪点 %s" % layer, false, "图上没有")
			continue
		var b: Vector2 = c["base"]
		# 站在点外 50 米（刚进图 6 秒内 32 米内的点先不建），同一层同一高度
		var stand: Vector3 = level.call("find_spawn_near", Vector3(b.x, float(c["y"]), b.y), 45.0, 60.0, null)
		await put(stand)
		var built: Array = []
		var tw := 0.0
		while tw < 8.0:
			await wait(0.2)
			tw += 0.2
			built = _camp_mobs(int(c["id"]))
			if built.size() >= (c["defs"] as Array).size():
				break
		var geo: Variant = mgr.get("geo")
		var zk: Dictionary = geo.zone_k(Vector3(b.x, float(c["y"]), b.y))
		var want_ri := int(((MapDef.map(map_id)["zone"] as Dictionary)[layer] as Dictionary)["ri"])
		var ok := not built.is_empty()
		var det: Array = []
		for mb: Node3D in built:
			var d: Dictionary = mb.get("def")
			var ri := int(mb.get("region"))
			var lv := int(mb.get("lv"))
			var base: Array = Data.SHAPE_BASE[str(d["shape"])]
			var el := bool(mb.get("elite"))
			var hp_w := float(base[0]) * float(d["hp"]) * CS.HP_CONV * CS.mob_s_hp(ri, lv) * (Data.ELITE_HP if el else 1.0) * float(zk["hp"])
			var at_w := float(base[1]) * float(d["atk"]) * Data.MOB_DMG * CS.ATK_CONV * CS.mob_s_atk(ri, lv) * (Data.ELITE_DMG if el else 1.0) * float(zk["atk"])
			var lv_lo := Prog.mob_level(ri, 0.0)
			var lv_hi := Prog.mob_level(ri, 1.0)
			var row_ok := ri == want_ri and lv >= lv_lo and lv <= lv_hi and absf(float(mb.get("hp_max")) - hp_w) < hp_w * 1e-4 + 0.01 \
					and absf(float(mb.get("atk")) - at_w) < at_w * 1e-4 + 0.001 and int(mb.get_meta("def_idx", 0)) >= Data.EX_BASE \
					and (mb.get("block_fn") as Callable).is_valid()
			if not row_ok:
				ok = false
			if det.size() < 3:
				det.append("%s 档%d Lv.%d（%d~%d）血 %.0f/%.0f 攻 %.1f/%.1f" % [str(d["name"]), ri, lv, lv_lo, lv_hi, float(mb.get("hp_max")), hp_w,
						float(mb.get("atk")), at_w])
		check("刷怪点 %s（档 %d ×%.2f）" % [layer, want_ri, float(zk["hp"])], ok, "建了 %d / %d 只：%s" % [built.size(), (c["defs"] as Array).size(), "；".join(det)])
		if layer == "surface":
			# 神识：点一下扫出去，身边的怪 / 搜点 / 撤离点被揭示
			var ss: Node = mgr.get("shenshi")
			var n0 := int(ss.get("scans"))
			var fired := bool(ss.call("scan"))
			await wait(3.0)
			check("神识一扫", fired and int(ss.get("scans")) == n0 + 1 and not (ss.get("marks") as Array).is_empty(),
					"扫了 %s 揭示 %d 个" % [str(fired), (ss.get("marks") as Array).size()])
		if layer == "surface" and not built.is_empty():
			# 打死一只：心得按（区域档 × 心得倍率）记上；刷怪点记它死了（75 秒后复活）
			var mb2: Node3D = built[0]
			var ins0 := float(mgr.get("insight"))
			var want_ins := float(mgr.call("kill_exp", int(mb2.get("lv")), float(mb2.get("xp_k")), int(mb2.get("region")))) * float(zk["xp"])
			var cd := int(mb2.get_meta("camp", -1))
			await _kill(mb2)
			await wait(0.5)
			var got := float(mgr.get("insight")) - ins0
			var dead_mark := ((mgr.get("camps")._dead as Dictionary).get(cd / 8, {}) as Dictionary).has(cd % 8)
			check("杀怪心得 ×倍率", absf(got - want_ins) < maxf(want_ins * 0.01, 0.01) and dead_mark, "心得 +%.1f（应 %.1f）刷怪点记死 %s" % [got, want_ins, str(dead_mark)])
	keep = false


func _camp_mobs(id: int) -> Array:
	var out: Array = []
	for mb: Variant in mgr.get("_mobs"):
		if is_instance_valid(mb) and bool(mb.is_alive()) and int(mb.get_meta("camp", -1)) / 8 == id and int(mb.get_meta("camp", -1)) >= 0:
			out.append(mb)
	return out


## 打死一只怪（走 net_damage → _take_raw：首领的 ExBoss.filter_damage 照样过）
func _kill(mb: Node3D, limit := 6.0) -> bool:
	var t := 0.0
	while is_instance_valid(mb) and bool(mb.is_alive()) and t < limit:
		mb.call("net_damage", float(mb.get("hp")) + 1.0, Vector3.FORWARD, true, "", 2.0)
		await wait(0.1)
		t += 0.1
	return not is_instance_valid(mb) or not bool(mb.is_alive())


## 自检要清场：收掉身边所有怪、压住刷怪（点数压成负的）
func hush() -> void:
	mgr.set("_credits", -1.0e9)
	for mb: Variant in (mgr.get("_mobs") as Array).duplicate():
		if is_instance_valid(mb):
			(mgr.get("_mobs") as Array).erase(mb)
			(mb as Node).queue_free()
	for f: Variant in (mgr.get("_rivals") as Array):
		if is_instance_valid(f):
			(f as Node).queue_free()
	(mgr.get("_rivals") as Array).clear()
	mgr.set("_rival_t", 1.0e9)
	await frames(2)


# ---------- 4 搜点 ----------

func step_search() -> void:
	keep = true
	await hush()
	var search: Node = mgr.get("search")
	var best: Dictionary = {}
	var bd := INF
	var pp := player.global_position
	for s: Dictionary in search.get("sites"):
		if str(s["kind"]) == "jar" and not bool(s["done"]) and MapDef.layer_at(s["pos"]) == MapDef.layer_at(pp):
			var d := (s["pos"] as Vector3).distance_to(pp)
			if d < bd:
				bd = d
				best = s
	if best.is_empty():
		check("搜点", false, "找不到藏物陶罐")
		return
	var sp: Vector3 = best["pos"]
	await put(sp + Vector3(0.8, 0.0, 0.0))
	var bag0 := (mgr.get("bag") as Array).size()
	var tw := 0.0
	while not bool(best["done"]) and tw < 12.0:
		await wait(0.2)
		tw += 0.2
		player.global_position = Vector3(sp.x + 0.8, float(level.call("floor_at", sp.x + 0.8, sp.z, sp.y + 1.0)) + 0.05, sp.z)
	var chest: Node3D = null
	for pk: Variant in mgr.get("_pickups"):
		if is_instance_valid(pk) and bool(pk.is_chest()) and str(pk.get("title")).ends_with("搜得") and (pk as Node3D).global_position.distance_to(sp) < 4.0:
			chest = pk
	var items: Array = chest.get("items").duplicate() if chest != null else []
	var old_ok := not items.is_empty()
	var names: Array = []
	for it: Dictionary in items:
		names.append("%s(%s)" % [str(it.get("name", "?")), str(it.get("kind", "?"))])
		if not it.has("tier") or not it.has("value") or not (str(it.get("kind", "")) in ["gear", "pill", "key", "herb", "mat", "tool", "frag"]):
			old_ok = false
	var dy := absf(sp.y - float(level.call("floor_at", sp.x, sp.z, sp.y + 0.5)))
	check("搜点出老物品", bool(best["done"]) and old_ok and dy < 0.6, "%s 深度 %.2f y %.1f 用时 %.1f 秒：%s" % [str(best["kind"]), float(best["depth"]), sp.y, tw, "、".join(names)])
	if chest != null:
		mgr.call("pick_up", chest, -1)
		await frames(2)
	check("搜得的东西拾进背包", (mgr.get("bag") as Array).size() > bag0, "背包 %d → %d 件" % [bag0, (mgr.get("bag") as Array).size()])
	keep = false


# ---------- 5 首领 ----------

func step_boss() -> void:
	keep = true
	await hush()
	var bosses: Array = mgr.get("_bosses")
	var b: Dictionary = {}
	for e: Dictionary in bosses:
		if str(e.get("key2", "")) == "" and str(e["layer"]) == "surface":
			b = e
			break
	if b.is_empty():
		b = bosses[0]
	var bp: Vector3 = b["pos"]
	var stand: Vector3 = level.call("find_spawn_near", bp, 30.0, 60.0, null)
	await put(stand)
	var tw := 0.0
	while int(b["state"]) != 1 and tw < 6.0:
		await wait(0.2)
		tw += 0.2
	var bm: Variant = b.get("node")
	var alive := bm != null and is_instance_valid(bm) and bool(bm.is_alive())
	var brain: Node = (bm as Node).get_node_or_null("ExBoss") if alive else null
	var ri := int(b["region"])
	var lv := int(bm.get("lv")) if alive else -1
	check("首领走近自动刷出", alive and brain != null and lv == Prog.boss_level(Prog.lair_tag(ri), int(mgr.call("_level_in", ri, bp)) + 2),
			"%s 档 %d Lv.%d 血 %.0f 攻 %.1f 大脑 %s pts_k %.2f 用时 %.1f 秒" % [str(b["name"]), ri, lv, float(bm.get("hp_max")) if alive else 0.0,
			float(bm.get("atk")) if alive else 0.0, str(brain != null), float(brain.get("pts_k")) if brain != null else 0.0, tw])
	if not alive:
		keep = false
		return
	var lid := int(b["lid"])
	var killed := await _kill(bm, 10.0)
	await wait(0.6)
	var chest: Node3D = null
	for pk: Variant in mgr.get("_pickups"):
		if is_instance_valid(pk) and bool(pk.is_chest()) and str(pk.get("title")).ends_with("的遗藏"):
			chest = pk
	var frag := false
	var n_items := 0
	if chest != null:
		n_items = (chest.get("items") as Array).size()
		for it: Dictionary in chest.get("items"):
			if str(it.get("kind", "")) == "frag":
				frag = true
	var gate_lit := false
	for e2: Dictionary in mgr.get("_extracts"):
		if str(e2.get("kind", "")) == "boss" and int(e2.get("lair", -1)) == lid and bool(e2["active"]):
			gate_lit = true
	check("首领能被打死、掉老巢穴遗藏", killed and int(b["state"]) == 2 and chest != null and frag and gate_lit,
			"巢穴 %d 状态 %d 遗藏 %d 件（残片 %s）镇守阵亮 %s 重生 %.0f 秒后" % [lid, int(b["state"]), n_items, str(frag), str(gate_lit),
			float(b["back"]) - float(mgr.call("world_t"))])
	keep = false


# ---------- 6 撤离 ----------

func step_extract() -> void:
	keep = true
	await hush()
	# 背包里至少有点东西（搜点 / 首领的）；首领的遗藏也拾进来（装不下的不管）
	for pk: Variant in (mgr.get("_pickups") as Array).duplicate():
		if is_instance_valid(pk) and (pk as Node3D).global_position.distance_to(player.global_position) < 40.0:
			mgr.call("pick_up", pk, -1)
	await frames(2)
	if (mgr.get("bag") as Array).is_empty():
		(mgr.get("bag") as Array).append(Items.herb(2))
	var bag: Array = (mgr.get("bag") as Array).duplicate()
	var stash0 := Profile.stash().size()
	var ls0 := Profile.lingshi()
	var out0 := int(Profile.stats().get("out", 0))
	var gate: Dictionary = {}
	for e: Dictionary in mgr.get("_extracts"):
		if bool(e["active"]) and str(e.get("kind", "")) == "gate":
			gate = e
			break
	if gate.is_empty():
		check("撤离", false, "没有亮着的古传送阵")
		keep = false
		return
	var gp: Vector3 = gate["pos"]
	await put(gp)
	var tw := 0.0
	while bool(mgr.get("running")) and tw < 15.0:
		await wait(0.2)
		tw += 0.2
		player.global_position = Vector3(gp.x, float(level.call("floor_at", gp.x, gp.z, gp.y + 1.0)) + 0.05, gp.z)
	var ok := not bool(mgr.get("running"))
	var stashed := Profile.stash().size() - stash0
	var sold := Profile.lingshi() - ls0
	keep = false
	var back := await wait_hub()
	check("撤离成功 → 背包进仓库", ok and int(Profile.stats().get("out", 0)) == out0 + 1 and (stashed > 0 or sold > 0) and back,
			"%s（%s）读条 %.1f 秒 背包 %d 件 → 仓库 +%d 件 灵石 +%d 回主城 %s" % [str(gate["name"]), str(gate["kind"]), tw, bag.size(), stashed, sold, str(back)])


# ---------- 7 陨落 ----------

func step_death() -> void:
	keep = true
	await hush()
	# 背包里放几件、身上一件法宝、储物戒一件
	var bag: Array = mgr.get("bag")
	bag.append(Items.herb(2))
	bag.append(Items.herb(3))
	var gear: Array = mgr.get("gear")
	gear.append(Data.make_gear(1, RandomNumberGenerator.new()))
	var ring: Array = mgr.get("ring")
	ring.append(Items.herb(1))
	var stash0 := Profile.stash().size()
	var dead0 := int(Profile.stats().get("dead", 0))
	var ring_n := ring.size()
	mgr.set("insight", 50.0)
	keep = false
	await frames(2)
	player.melee.hp = 0.0
	var tw := 0.0
	while bool(mgr.get("running")) and tw < 5.0:
		await get_tree().process_frame
		tw += get_process_delta_time()
	var ended := not bool(mgr.get("running"))
	var d: Dictionary = Profile.data()
	var lost_ok := Profile.stash().size() == stash0 and (d["gear"] as Array).is_empty()
	var ring_ok := (d["ring"] as Array).size() == ring_n
	var back := await wait_hub()
	check("陨落 → 背包法宝丢、储物戒留", ended and lost_ok and ring_ok and int(Profile.stats().get("dead", 0)) == dead0 + 1 and back,
			"结算 %s 仓库 %d → %d 法宝 %d 件 储物戒 %d 件（应 %d）陨落次数 %d → %d 回主城 %s" % [str(ended), stash0, Profile.stash().size(),
			(d["gear"] as Array).size(), (d["ring"] as Array).size(), ring_n, dead0, int(Profile.stats().get("dead", 0)), str(back)])
