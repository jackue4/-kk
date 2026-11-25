extends "res://scripts/xiu_map_selftest.gd"
## T_maps 额外自检（2026-11-25，不进包）：在 xiu_map_selftest 之外补测
##   A 境界守卫：炼气（0）也拦；化神（4）放行
##   B 每个刷怪点都走一遍：各层的点数 / 怪数 / 精英 / 区域档 / 等级段，怪落在点自己的高度上、不在实心里、挡墙函数有
##   C 刷怪点复活：清空一个点，没到 75 秒不复活，过了 75 秒复活；精英位要 150 秒
##   D 搜点：所有搜点的 y 贴着那一层的地面、不在实心里；每种搜点各搜一个，出老物品
##   E 传送阵轮换：房间时间推 300 秒一轮，连推 6 轮：每轮亮 free+1、灵石阵 1 座，轮换会换座次；小地图画的撤离点 = 亮着的同层那几座
##   F 首领：每座巢穴走近刷出、能打死、遗藏有残片；第一座反复刷 / 打 N 次，统计霸主精魄的掉率和 OVERLORD_P 对照
## 输出「[xiu] …」行，最后「[xiu] 总计 失败 N 项」。

const Minimap := preload("res://scripts/minimap.gd")
const ExMobs := preload("res://scripts/ex/ex_mobs.gd")


class Rec extends "res://scripts/minimap.gd".Painter:
	var circles: Array = []
	var texts: Array = []
	var last_c: Array = []
	var last_t: Array = []
	var draws := 0

	func circle(c: Vector2, r: float, col: Color) -> void:
		circles.append([c, r, col])

	func arc(_c: Vector2, _r: float, _a0: float, _a1: float, _n: int, _col: Color, _w: float) -> void:
		pass

	func rect(_r: Rect2, _col: Color, _filled := true, _w := -1.0) -> void:
		pass

	func line(_a: Vector2, _b: Vector2, _col: Color, _w: float) -> void:
		pass

	func poly(_p: PackedVector2Array, _col: Color) -> void:
		pass

	func text(_f: Font, _pos: Vector2, s: String, _al: HorizontalAlignment, _w: float, _sz: int, _col: Color) -> void:
		texts.append(s)

	func text_outline(_f: Font, _pos: Vector2, _s: String, _al: HorizontalAlignment, _w: float, _sz: int, _osz: int, _col: Color) -> void:
		pass

	func flush() -> void:
		last_c = circles
		last_t = texts
		circles = []
		texts = []
		draws += 1


func _run() -> void:
	await wait(1.5)
	player = m.get("player")
	cam = m.get("cam")
	say("T_maps 额外自检开始：%s 测试存档 %s" % [map_id, Profile.test_mode()])
	await x_guard(0, false)
	await x_guard(4, true)
	if await enter(3):
		mgr.set("lv", 99)      # 扫点 / 搜点时别被一下打死（伤害换成血条按 mgr.lv 算；怪的数值不看它）
		for b: Dictionary in mgr.get("_bosses"):      # 扫刷怪点时别让巢穴首领刷出来（扫完 F 节再放开）
			b["state"] = 2
			b["back"] = 1.0e9
		await x_camps_all()
		await x_respawn()
		await x_sites()
		await x_rotation()
		await x_bosses()
	say("总计 失败 %d 项（通过 %d 项，用时 %.0f 秒）" % [fails, passes, float(Time.get_ticks_msec() - _t0) / 1000.0])
	await wait(0.5)
	get_tree().quit(0 if fails == 0 else 1)


# ---------- A ----------

func x_guard(r: int, pass_ok: bool) -> void:
	set_realm(r)
	m.get("level_ui").set("mode", "solo")
	await m.call("_enter_level", map_id)
	while bool(m.get("_switching")):
		await get_tree().process_frame
	var lv: Variant = m.get("level")
	var has_mgr := lv != null and lv.get("raid") != null
	var blocked := lv == null or bool(lv.get("realm_blocked"))
	if pass_ok:
		check("境界守卫放行（境界 %d）" % r, has_mgr and not blocked, "管理器 %s" % str(has_mgr))
		if has_mgr:
			mgr = lv.get("raid")
			mgr.call("_finish", true)
	else:
		check("境界守卫拦下（境界 %d）" % r, blocked and not has_mgr, "拦下 %s" % str(blocked))
	var back := await wait_hub()
	check("境界 %d 回到主城" % r, back, "")


# ---------- B ----------

func x_camps_all() -> void:
	keep = true
	var camps: Variant = mgr.get("camps")
	var md: Dictionary = MapDef.map(map_id)
	var stat := {}
	var bad: Array = []
	var miss: Array = []
	var max_mobs := 0
	for id: int in camps._list_ids:
		var c: Dictionary = camps._cache[id]
		var lay := str(c["layer"])
		var st: Dictionary = stat.get(lay, {"camps": 0, "slots": 0, "elite": 0, "built": 0, "kinds": {}, "lv": [999, -1], "ri": {}})
		stat[lay] = st
		st["camps"] = int(st["camps"]) + 1
		st["slots"] = int(st["slots"]) + (c["defs"] as Array).size()
		for e: bool in c["elite"]:
			if e:
				st["elite"] = int(st["elite"]) + 1
		var b: Vector2 = c["base"]
		var stand: Vector3 = level.call("find_spawn_near", Vector3(b.x, float(c["y"]), b.y), 42.0, 70.0, null)
		if not stand.is_finite():
			miss.append("%s(找不到站位)" % str(c["name"]))
			continue
		var built: Array = []
		for attempt in 2:
			if attempt == 1:
				stand = level.call("find_spawn_near", Vector3(b.x, float(c["y"]), b.y), 25.0, 45.0, null)
			await put(stand)
			var tw := 0.0
			while tw < 6.0:
				await wait(0.2)
				tw += 0.2
				built = _camp_mobs(id)
				if built.size() >= (c["defs"] as Array).size():
					break
			if not built.is_empty():
				break
			var pp0 := player.global_position
			say("  %s 第 %d 次没建：站 %s 离点 %.1f 米 高差 %.1f 跑了 %.1f 秒 别人名下 %s 我名下活着 %d 怪总数 %d" % [str(c["name"]), attempt + 1, str(pp0.snapped(Vector3.ONE * 0.1)),
					Vector2(pp0.x - b.x, pp0.z - b.y).length(), pp0.y - float(c["y"]), float(mgr.get("run_t")), str(camps._owned_by_other(id)),
					(camps._live.get(id, []) as Array).size(), (mgr.get("_mobs") as Array).size()])
		await wait(0.3)
		built = _camp_mobs(id)
		max_mobs = maxi(max_mobs, (mgr.get("_mobs") as Array).size())
		if built.size() < (c["defs"] as Array).size():
			miss.append("%s %d/%d" % [str(c["name"]), built.size(), (c["defs"] as Array).size()])
		st["built"] = int(st["built"]) + built.size()
		var want_ri := int(((md["zone"] as Dictionary)[lay] as Dictionary)["ri"])
		for mb: Node3D in built:
			var mp := mb.global_position
			var fl := float(level.call("floor_at", mp.x, mp.z, float(c["y"]) + 2.0))
			var d: Dictionary = mb.get("def")
			(st["kinds"] as Dictionary)[str(d["name"])] = int((st["kinds"] as Dictionary).get(str(d["name"]), 0)) + 1
			(st["ri"] as Dictionary)[int(mb.get("region"))] = true
			var lvv := int(mb.get("lv"))
			st["lv"] = [mini(int(st["lv"][0]), lvv), maxi(int(st["lv"][1]), lvv)]
			var why := ""
			if int(mb.get("region")) != want_ri:
				why += " 档%d≠%d" % [int(mb.get("region")), want_ri]
			if absf(mp.y - fl) > 2.5 or absf(mp.y - float(c["y"])) > 12.0:
				why += " y %.1f 地面 %.1f 点 %.1f" % [mp.y, fl, float(c["y"])]
			if bool(level.call("solid_at", mp + Vector3(0, 0.4, 0))) and await _still_solid(mb):
				var wd: Node = level.get("world")
				why += " 在实心里(地形 %.1f 盒子 %s 洞顶 %.1f y %.1f)" % [float(wd.call("height", mp.x, mp.z)), str(wd.call("solid_box_at", mp + Vector3(0, 0.4, 0))),
						float(wd.call("ceil_at", mp.x, mp.z)), mp.y]
			if not (mb.get("block_fn") as Callable).is_valid():
				why += " 没挡墙"
			if int(mb.get_meta("def_idx", 0)) < Data.EX_BASE:
				why += " 老编号"
			if why != "" and bad.size() < 8:
				bad.append("%s/%s%s" % [str(c["name"]), str(d["name"]), why])
	for lay: String in stat:
		var st2: Dictionary = stat[lay]
		say("刷怪点统计 %s：点 %d 个 怪位 %d（精英 %d）建出 %d 区域档 %s 等级 %d~%d 种类 %s" % [lay, int(st2["camps"]), int(st2["slots"]), int(st2["elite"]),
				int(st2["built"]), str((st2["ri"] as Dictionary).keys()), int(st2["lv"][0]), int(st2["lv"][1]), str(st2["kinds"])])
	check("每个刷怪点都建得出来", miss.is_empty(), "没建全 %s" % str(miss))
	check("刷怪点的怪：区域档 / 落脚 / 挡墙", bad.is_empty(), "问题 %s；同时在场最多 %d 只（上限 %d）" % [str(bad), max_mobs, int(mgr.call("mob_cap"))])
	keep = false


## 走台阶时贴地是插值过去的（8/秒），刚好那一帧会低半格：隔 0.6 秒再看一次还在实心里才算
func _still_solid(mb: Node3D) -> bool:
	await wait(0.6)
	return is_instance_valid(mb) and bool(level.call("solid_at", mb.global_position + Vector3(0, 0.4, 0)))


# ---------- C ----------

func x_respawn() -> void:
	keep = true
	var camps: Variant = mgr.get("camps")
	for want_elite: bool in [false, true]:
		var c: Dictionary = {}
		for id: int in camps._list_ids:
			var cc: Dictionary = camps._cache[id]
			if str(cc["layer"]) == "surface" and (cc["elite"] as Array).has(true) == want_elite:
				c = cc
				break
		if c.is_empty():
			say("刷怪点复活：没有%s点，跳过" % ("精英" if want_elite else "普通"))
			continue
		var id2 := int(c["id"])
		var b: Vector2 = c["base"]
		await put(level.call("find_spawn_near", Vector3(b.x, float(c["y"]), b.y), 42.0, 70.0, null))
		var tw := 0.0
		while _camp_mobs(id2).size() < (c["defs"] as Array).size() and tw < 6.0:
			await wait(0.2)
			tw += 0.2
		var n0 := _camp_mobs(id2).size()
		for mb: Node3D in _camp_mobs(id2):
			await _kill(mb)
		await wait(2.0)
		var n_after := _camp_mobs(id2).size()
		mgr.set("_solo_t", float(mgr.get("_solo_t")) + 76.0)
		tw = 0.0
		var n_el := (c["elite"] as Array).count(true)
		while _camp_mobs(id2).size() < (c["defs"] as Array).size() - n_el and tw < 4.0:
			await wait(0.2)
			tw += 0.2
		var n76 := _camp_mobs(id2).size()
		var el_back := true
		if want_elite:
			var el_alive_76 := false
			for mb2: Node3D in _camp_mobs(id2):
				if bool(mb2.get("elite")):
					el_alive_76 = true
			mgr.set("_solo_t", float(mgr.get("_solo_t")) + 76.0)
			tw = 0.0
			while _camp_mobs(id2).size() < (c["defs"] as Array).size() and tw < 4.0:
				await wait(0.2)
				tw += 0.2
			var el_alive_152 := false
			for mb3: Node3D in _camp_mobs(id2):
				if bool(mb3.get("elite")):
					el_alive_152 = true
			el_back = not el_alive_76 and el_alive_152
			say("精英位：76 秒时 %s 152 秒时 %s" % [str(el_alive_76), str(el_alive_152)])
		var full := (c["defs"] as Array).size()
		check("刷怪点复活（%s点 %s）" % ["精英" if want_elite else "普通", str(c["name"])],
				n0 == full and n_after == 0 and n76 == full - n_el and el_back,
				"建 %d / %d → 清空后 2 秒 %d → 推 76 秒 %d%s" % [n0, full, n_after, n76, "（精英位要 150 秒）" if want_elite else ""])
	keep = false


# ---------- D ----------

func x_sites() -> void:
	keep = true
	await hush()
	var search: Node = mgr.get("search")
	var bad: Array = []
	for s: Dictionary in search.get("sites"):
		var sp: Vector3 = s["pos"]
		var fl := float(level.call("floor_at", sp.x, sp.z, sp.y + 0.5))
		if absf(sp.y - fl) > 0.6 or bool(level.call("solid_at", sp + Vector3(0, 0.5, 0))):
			if bad.size() < 8:
				bad.append("%s#%d y %.1f 地面 %.1f" % [str(s["kind"]), int(s["id"]), sp.y, fl])
	check("所有搜点贴地、不在实心里", bad.is_empty(), "%d 个搜点 问题 %s" % [(search.get("sites") as Array).size(), str(bad)])
	for kind: String in ["herb", "grave", "vault", "urn"]:
		var best: Dictionary = {}
		var bd := INF
		var pp := player.global_position
		for s2: Dictionary in search.get("sites"):
			if str(s2["kind"]) == kind and not bool(s2["done"]):
				var d := (s2["pos"] as Vector3).distance_to(pp)
				if d < bd:
					bd = d
					best = s2
		if best.is_empty():
			check("搜点 %s" % kind, false, "没有")
			continue
		var sp2: Vector3 = best["pos"]
		await put(sp2 + Vector3(0.3, 0.0, 0.0))
		var tw := 0.0
		while not bool(best["done"]) and tw < 16.0:
			await wait(0.2)
			tw += 0.2
			for mb: Variant in (mgr.get("_mobs") as Array).duplicate():      # 宝库破禁引来的守卫：清掉（不然挨打读条倒退）
				if is_instance_valid(mb) and not bool(mb.get("boss")):
					(mgr.get("_mobs") as Array).erase(mb)
					(mb as Node).queue_free()
			player.global_position = Vector3(sp2.x + 0.3, float(level.call("floor_at", sp2.x + 0.3, sp2.z, sp2.y + 1.0)) + 0.05, sp2.z)
		await wait(0.3)
		var chest: Node3D = null
		for pk: Variant in mgr.get("_pickups"):
			if is_instance_valid(pk) and bool(pk.is_chest()) and str(pk.get("title")).ends_with("搜得") and (pk as Node3D).global_position.distance_to(sp2) < 5.0:
				chest = pk
		var names: Array = []
		var ok := chest != null
		if chest != null:
			for it: Dictionary in chest.get("items"):
				names.append("%s(%s)" % [str(it.get("name", "?")), str(it.get("kind", "?"))])
				if not it.has("tier") or not it.has("value"):
					ok = false
			if (chest.get("items") as Array).is_empty():
				ok = false
			(mgr.get("_pickups") as Array).erase(chest)
			chest.queue_free()
		var pp2 := player.global_position
		check("搜点 %s 出老物品" % kind, bool(best["done"]) and ok, "#%d 深度 %.2f 档 %d 用时 %.1f 秒：%s（节点 %s 读条 %.1f 点 %s 人 %s）" % [int(best["id"]), float(best["depth"]), int(best["region"]), tw, "、".join(names),
				str(is_instance_valid(best["node"])), float(best["prog"]), str(sp2.snapped(Vector3.ONE * 0.01)), str(pp2.snapped(Vector3.ONE * 0.01))])
	keep = false


# ---------- E ----------

func _lit() -> Array:
	var out: Array = []
	for e: Dictionary in mgr.get("_extracts"):
		if e.has("base") and bool(e["active"]):
			out.append("%s:%s" % [str(e["base"]), str(e["kind"])])
	out.sort()
	return out


func _minimap_check(tag: String) -> void:
	var hud: Variant = mgr.get("hud")
	var mm: Variant = hud.get("minimap") if hud != null else null
	if mm == null:
		check("小地图（%s）" % tag, false, "没有小地图")
		return
	var rec := Rec.new(mm)
	mm.set("_pt", rec)
	(mm as CanvasItem).queue_redraw()
	await frames(3)
	if rec.draws == 0:
		(mm as Object).call("_draw")      # headless 下没走 NOTIFICATION_DRAW 时直接调（enso 那一笔会报「只能在 draw 里画」，不影响数）
	var n_ex := 0
	for c: Array in rec.last_c:
		if absf(float(c[1]) - 7.0) < 0.01 and (c[2] as Color).is_equal_approx(Color(0.03, 0.05, 0.08, 0.85)):
			n_ex += 1
	var pp := player.global_position
	var lay := MapDef.layer_at(pp)
	var want := 0
	var near := INF
	for e: Dictionary in mgr.get("_extracts"):
		if bool(e.get("active", true)) and MapDef.layer_at(e["pos"]) == lay:
			want += 1
			near = minf(near, Vector2(e["pos"].x, e["pos"].z).distance_to(Vector2(pp.x, pp.z)))
	var want_txt := ("撤离点 %dm" % int(near)) if near < INF else "此层无撤离点"
	var got_txt := ""
	for t: String in rec.last_t:
		if t.begins_with("撤离点") or t.begins_with("此层"):
			got_txt = t
	check("小地图撤离点（%s）" % tag, bool(mm.get("_fixed")) and n_ex == want and got_txt == want_txt,
			"画了 %d 座（应 %d：亮着的同层）文字「%s」（应「%s」）" % [n_ex, want, got_txt, want_txt])
	mm.set("_pt", null)


func x_rotation() -> void:
	keep = true
	var md: Dictionary = MapDef.map(map_id)
	var free_n := int((md["xiu"] as Dictionary)["gates_free"])
	await put(level.call("spawn_point"))
	await _minimap_check("进图")
	var seen := {}
	var all_ok := true
	var det: Array = []
	var cur := _lit()
	seen[str(cur)] = true
	det.append(str(cur))
	for k in 6:
		mgr.set("_solo_t", (floorf(float(mgr.get("_solo_t")) / 300.0) + 1.0) * 300.0 + 1.0)
		await wait(0.6)
		var lit := _lit()
		var paid := 0
		for s: String in lit:
			if s.ends_with(":paid"):
				paid += 1
		if lit.size() != free_n + 1 or paid != 1:
			all_ok = false
		seen[str(lit)] = true
		det.append(str(lit))
		# 节点是亮着的造型
		for e: Dictionary in mgr.get("_extracts"):
			if e.has("base") and not is_instance_valid(e.get("node")):
				all_ok = false
	check("传送阵每 300 秒轮换", all_ok and seen.size() >= 3, "7 轮里出现 %d 种组合：%s" % [seen.size(), " | ".join(det)])
	await _minimap_check("轮换 6 次后")
	keep = false


# ---------- F ----------

func _chests() -> Array:
	var out: Array = []
	for pk: Variant in mgr.get("_pickups"):
		if is_instance_valid(pk) and bool(pk.is_chest()) and str(pk.get("title")).ends_with("的遗藏"):
			out.append(pk)
	return out


func _boss_round(b: Dictionary) -> Dictionary:
	var tw := 0.0
	while int(b["state"]) != 1 and tw < 8.0:
		await wait(0.2)
		tw += 0.2
	var res := {"spawned": false, "killed": false, "frag": false, "overlord": false, "n": 0, "lv": -1, "hp": 0.0}
	var bm: Variant = b.get("node")
	if bm == null or not is_instance_valid(bm) or not bool(bm.is_alive()):
		return res
	res["spawned"] = (bm as Node).get_node_or_null("ExBoss") != null
	res["lv"] = int(bm.get("lv"))
	res["hp"] = float(bm.get("hp_max"))
	if str(b.get("key2", "")) != "":
		var b2: Variant = b.get("node2")
		res["spawned"] = bool(res["spawned"]) and b2 != null and is_instance_valid(b2) and (b2 as Node).get_node_or_null("ExBoss") != null
	var before := _chests()
	var k1 := await _kill(bm, 10.0)
	if str(b.get("key2", "")) != "":
		await wait(0.4)
		var mid_chest := _chests().size() > before.size()
		res["duo_early"] = mid_chest
		var b2b: Variant = b.get("node2")
		if b2b != null and is_instance_valid(b2b):
			k1 = k1 and await _kill(b2b, 10.0)
	await wait(0.6)
	res["killed"] = k1 and int(b["state"]) == 2
	res["chests"] = 0
	res["ov_n"] = 0
	for ch: Variant in _chests():
		if before.has(ch):
			continue
		res["chests"] = int(res["chests"]) + 1
		for it2: Dictionary in ch.get("items"):
			if str(it2.get("name", "")).contains("霸主精魄"):
				res["ov_n"] = int(res["ov_n"]) + 1
		res["n"] = (ch.get("items") as Array).size()
		for it: Dictionary in ch.get("items"):
			if str(it.get("kind", "")) == "frag":
				res["frag"] = true
			if str(it.get("name", "")).contains("霸主精魄"):
				res["overlord"] = true
		(mgr.get("_pickups") as Array).erase(ch)
		(ch as Node).queue_free()
	return res


func _physics_process(_dt: float) -> void:
	if keep and player != null and is_instance_valid(player) and not player.dead:
		player.melee.hp = player.melee.HP_MAX


func x_bosses() -> void:
	keep = true
	await hush()
	var bosses: Array = mgr.get("_bosses")
	for b: Dictionary in bosses:
		b["back"] = float(mgr.call("world_t")) - 1.0
	for b: Dictionary in bosses:
		var bp: Vector3 = b["pos"]
		await put(level.call("find_spawn_near", bp, 20.0, 45.0, null))
		var r: Dictionary = await _boss_round(b)
		var ri := int(b["region"])
		check("首领 %s（%s 档 %d%s）" % [str(b["name"]), str(b["layer"]), ri, " 双卫" if str(b.get("key2", "")) != "" else ""],
				bool(r["spawned"]) and bool(r["killed"]) and bool(r["frag"]) and not bool(r.get("duo_early", false)),
				"Lv.%d 血 %.0f 遗藏 %d 件 残片 %s 精魄 %s%s" % [int(r["lv"]), float(r["hp"]), int(r["n"]), str(r["frag"]), str(r["overlord"]),
				"（双卫只倒一只就掉了！）" if bool(r.get("duo_early", false)) else ""])
	# 第一座反复刷 / 打：霸主精魄掉率
	var b0: Dictionary = bosses[0]
	await put(level.call("find_spawn_near", b0["pos"], 20.0, 45.0, null))
	var n := 16
	var got := 0
	var done := 0
	for i in n:
		b0["back"] = float(mgr.call("world_t")) - 1.0
		var r2: Dictionary = await _boss_round(b0)
		if not bool(r2["killed"]):
			continue
		done += 1
		say("  第 %d 次：新遗藏 %d 只 精魄 %d 颗 件数 %d 夜 %s" % [i + 1, int(r2["chests"]), int(r2["ov_n"]), int(r2["n"]), str(level.call("is_night"))])
		if bool(r2["overlord"]):
			got += 1
	var lt := Prog.lair_tag(int(b0["region"]))
	var p := float(Prog.OVERLORD_P[clampi(lt, 0, Prog.OVERLORD_P.size() - 1)])
	# 二项分布：n=16 时 p=0.6 → 期望 9.6，3σ 约 ±5.9
	var sd := sqrt(float(done) * p * (1.0 - p))
	check("霸主精魄掉率（%s 档 %d → 霸主档 %d）" % [str(b0["name"]), int(b0["region"]), lt], done >= n - 2 and absf(float(got) - float(done) * p) <= 3.0 * sd + 0.5,
			"打死 %d 次 掉 %d 颗（期望 %.1f，P = %.2f）" % [done, got, float(done) * p, p])
	keep = false
