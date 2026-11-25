extends RefCounted
## 搜打撤 PvP 的两张新图（2026-11-24，_tasks/extraction_refactor/SPEC.md 第 5 节）：布局数据。
##   沙海古墟（desert，对标 DarkArea 沙漠行动）：地面（沙丘 + 戈壁 + 遗迹 + 正中阶梯金字塔「黄金神塔」）+ 地下洞窟（另一片坐标）
##   天工秘所（lab，对标 DarkArea 研究所）：被尸傀占领的机关坊园区 + 主楼下的地下室「尸傀密窟」（另一片坐标）
## 坐标换算（DarkArea 1 格 = 1 米，DarkArea +Z 是北，本作 -Z 是北）：
##   沙漠地面 ds()：x' = (x − 231) × 2，z' = (499 − z) × 2，y' = y − 50（DarkArea 地面 y70 → 20）
##   沙漠洞窟 dc()：同上再 x' + D_CAV，y'' = y + 7（DarkArea 地下 y3..27 → 10..34）
##   研究所园区 ls()：x' = (x + 1022) × 1.5，z' = (528 − z) × 1.5，y' = y − 40（DarkArea 园区 y90 → 50）
##   研究所地下室 lb()：同上再 x' + L_CAV，y'' = y − 21（DarkArea 凌影 y31 → 10，不能低于 0：方块世界 0 以下是水 / 云海）
## DarkArea 原图（levels.json）给的点全部按上式换算（每条带 da_* 原值备查）；DarkArea 没有的（箱子点、刷怪点、楼、遗迹、洞窟网、
## 边界、夜里尸潮）在这里补。钥匙房的「区域盒」在 DarkArea 里只是复原箱子的判定框，本作在框里摆一间实际的房间，门放在离原门最近的那面墙上。
## 数据形状见 points()（ex_level.gd 原样转给 extract_manager.gd 用；交付报告 reports/W_maps.md 里有完整清单）。
## 故意不写 class_name：用 preload 引用。

const D_CAV := 1000.0          # 沙漠洞窟放在 x' + 1000
const L_CAV := 900.0           # 研究所地下室放在 x' + 900
const DESERT_Y := 20.0         # 沙漠地面基准
const LAB_Y := 50.0            # 研究所园区地面
const DAY_LEN := 600.0         # 昼夜（SPEC 4.9）：白天 600 秒、黑夜 600 秒，过渡 6 秒
const NIGHT_LEN := 600.0
const DUSK := 6.0

static var _cache := {}


## 一张图的全部数据（第一次调用时生成，之后缓存；只读，别改里面的东西）
static func map(id: String) -> Dictionary:
	if not _cache.has(id):
		var m: Dictionary = _lab() if id == "lab" else _desert()
		_finish(m)
		_cache[id] = m
	return _cache[id]


# ---------- 坐标换算 ----------

static func ds(x: float, y: float, z: float) -> Vector3:
	return Vector3((x - 231.0) * 2.0, y - 50.0, (499.0 - z) * 2.0)


static func dc(x: float, y: float, z: float) -> Vector3:
	return Vector3((x - 231.0) * 2.0 + D_CAV, y + 7.0, (499.0 - z) * 2.0)


static func ls(x: float, y: float, z: float) -> Vector3:
	return Vector3((x + 1022.0) * 1.5, y - 40.0, (528.0 - z) * 1.5)


static func lb(x: float, y: float, z: float) -> Vector3:
	return Vector3((x + 1022.0) * 1.5 + L_CAV, y - 21.0, (528.0 - z) * 1.5)


## DarkArea 的一个盒子（最小角 / 最大角）换成本作的 AABB（Z 翻转，所以两角要重新取最小）
static func cbox(f: Callable, mn: Vector3, mx: Vector3) -> AABB:
	var a: Vector3 = f.call(mn.x, mn.y, mn.z)
	var b: Vector3 = f.call(mx.x, mx.y, mx.z)
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	return AABB(lo, hi - lo)


## 朝向 dir（水平）的偏航角：本作 yaw 0 朝 -Z（北），前方 = (-sin yaw, -cos yaw)
static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## 两点之间：站在 from、面朝 to 的偏航角
static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(from.x - to.x, from.z - to.z)


# ---------- 沙海古墟 ----------

static func _desert() -> Dictionary:
	var m := {"id": "desert", "name": "沙海古墟", "sub": "黄沙古迹 · 地下洞窟", "base_y": DESERT_Y,
			"death_drop_stacks": 2, "box_quality": "senior"}
	# 层：grid = 烘地形表的范围（2 米一格）；play = DarkArea 战区换算过来的范围；bound = 硬夹钳（藏在沙暴最浓处 / 洞窟岩壁里）
	m["layers"] = {
		"surface": {"grid": Rect2(-432, -512, 864, 1024), "play": Rect2(-270, -346, 540, 692),
				"bound": Rect2(-380, -456, 760, 912), "fly_cap": DESERT_Y + 45.0, "ceil": 1.0e9, "center": Vector3(12, 20, 40)},
		"cavern": {"grid": Rect2(720, -256, 576, 576), "play": Rect2(728, -250, 560, 562),
				"bound": Rect2(724, -252, 568, 568), "fly_cap": 40.0, "ceil": 36.0, "center": Vector3(1010, 16, 60)},
	}
	# 外圈赤岩台崖：R0（play）外扩 8 ~ 48 米一圈，高 30 ~ 50 米；每边留缺口（缺口 / 崖外是沙暴带，硬夹钳在 bound）
	m["cliff"] = {"inner": 8.0, "outer": 48.0, "h_min": 30.0, "h_max": 50.0,
			"gaps": [["n", -150.0, 18.0], ["n", 150.0, 16.0], ["s", -120.0, 18.0], ["s", 170.0, 16.0],
					["w", -60.0, 18.0], ["w", 240.0, 16.0], ["e", 20.0, 18.0], ["e", -250.0, 16.0]]}
	# 沙暴：离 play 矩形外沿 storm_in 米起刮，到 storm_full 米最浓（推力 + 每秒掉 3 点，SPEC 5.2）
	m["storm"] = {"in": 30.0, "full": 100.0, "dps": 3.0, "push": 34.0}
	m["spawns"] = [
		{"id": "S1", "pos": ds(132, 70, 565), "layer": "surface", "da": Vector3(132, 70, 565)},
		{"id": "S2", "pos": ds(336, 70, 566), "layer": "surface", "da": Vector3(336, 69, 566)},
		{"id": "S3", "pos": ds(338, 70, 361), "layer": "surface", "da": Vector3(338, 70, 361)},
		{"id": "S4", "pos": ds(119, 70, 338), "layer": "surface", "da": Vector3(119, 70, 338)},
		{"id": "s5", "pos": dc(140, 9, 563), "layer": "cavern", "da": Vector3(140, 9, 563)},
		{"id": "s6", "pos": dc(354, 6, 534), "layer": "cavern", "da": Vector3(354, 6, 534)},
		{"id": "s7", "pos": dc(340, 7, 358), "layer": "cavern", "da": Vector3(340, 7, 358)},
		{"id": "s8", "pos": dc(211, 11, 373), "layer": "cavern", "da": Vector3(211, 11, 373)},
	]
	# 撤离区：DarkArea 12×6×12 的盒子 → 24×6×24；台面比地面高 1 米（撤离台）
	var ex: Array = []
	for e: Array in [["E1", 122.0, 457.0], ["E2", 237.0, 576.0], ["E3", 237.0, 340.0], ["E4", 353.0, 457.0]]:
		var p := ds(float(e[1]), 70.0, float(e[2]))
		ex.append({"id": e[0], "pos": Vector3(p.x, DESERT_Y + 1.0, p.z), "size": Vector3(24, 6, 24), "layer": "surface",
				"da": Vector3(float(e[1]), 73.0, float(e[2]))})
	m["extracts"] = ex
	# 金字塔「黄金神塔」：塔顶 = 凌幽的战斗区（DarkArea X225..249 Z447..469 y88 → 48×44，台面 38）
	m["pyramid"] = {"c": Vector2(12, 82), "top": Vector2(24, 22), "top_y": 38.0, "tiers": 6, "tier_h": 3.0, "tier_in": 6.0, "stair_w": 5.0}
	# 戈壁方山（掩体；中心、半径、比地面高多少）
	m["mesas"] = [[Vector2(-110, -250), 16.0, 10.0], [Vector2(120, -262), 18.0, 12.0], [Vector2(-170, 250), 14.0, 8.0],
			[Vector2(110, 252), 16.0, 9.0], [Vector2(-132, -56), 12.0, 7.0], [Vector2(152, -36), 12.0, 8.0],
			[Vector2(-64, 214), 10.0, 6.0], [Vector2(196, -4), 10.0, 6.0], [Vector2(-232, -292), 12.0, 9.0],
			[Vector2(232, -300), 14.0, 10.0], [Vector2(-100, 120), 9.0, 5.0], [Vector2(-10, -230), 11.0, 7.0]]
	# 北峡 C：一道下行的峡谷，尽头的崖壁上是洞口（DarkArea 峡谷图标 (237,549)）
	m["canyon"] = {"pts": [Vector2(-74, -78), Vector2(-34, -91), Vector2(12, -100)], "floor": [20.0, 14.0, 8.0], "w": 18.0}
	# 洞口（地面一侧）：一个下沉坑 + 坑底崖壁上的洞口；d = 坡道朝哪边上去（从哪边走下来）
	m["pits"] = [{"id": "U1", "c": Vector2(48, -138), "d": Vector3(0, 0, 1)}, {"id": "U2", "c": Vector2(-228, 24), "d": Vector3(1, 0, 0)},
			{"id": "U3", "c": Vector2(-232, 198), "d": Vector3(1, 0, 0)}, {"id": "U4", "c": Vector2(238, 158), "d": Vector3(-1, 0, 0)}]
	# 洞窟网：隧道（折线、每点的地板高、宽）+ 洞厅（圆 / 矩形）。洞顶 36（大场地 40），岩体顶 41
	var C := D_CAV
	m["cave"] = {
		"rock_y": 41.0, "ceil": 36.0,
		"tunnels": [
			[[Vector2(800, 26), Vector2(806, -40), Vector2(818, -128)], [15.0, 16.0, 16.0], 16.0],
			[[Vector2(800, 26), Vector2(830, 34), Vector2(850, 36)], [15.0, 15.0, 15.0], 16.0],
			[[Vector2(860, 66), Vector2(842, 112), Vector2(800, 162), Vector2(768, 198)], [15.0, 16.0, 16.0, 16.0], 16.0],
			[[Vector2(768, 198), Vector2(850, 240), Vector2(960, 252)], [16.0, 17.0, 18.0], 16.0],
			[[Vector2(960, 252), Vector2(1080, 292), Vector2(1218, 282)], [18.0, 16.0, 14.0], 16.0],
			[[Vector2(1218, 282), Vector2(1242, 220), Vector2(1238, 158)], [14.0, 15.0, 15.0], 16.0],
			[[Vector2(1238, 158), Vector2(1226, 80), Vector2(1196, 10)], [15.0, 13.0, 11.0], 16.0],
			[[Vector2(1196, -40), Vector2(1204, -62), Vector2(1246, -70)], [11.0, 12.0, 13.0], 14.0],
			[[Vector2(1246, -70), Vector2(1244, -118), Vector2(1222, -150)], [13.0, 14.0, 14.0], 16.0],
			[[Vector2(1146, -172), Vector2(1090, -150), Vector2(1048, -138)], [14.0, 15.0, 16.0], 16.0],
			[[Vector2(1048, -138), Vector2(1030, -118), Vector2(1012, -100)], [16.0, 16.0, 16.0], 14.0],
			[[Vector2(1012, -100), Vector2(920, -110), Vector2(818, -128)], [16.0, 16.0, 16.0], 16.0],
		],
		# 洞厅：["disc", 中心, 半径, 地板] / ["rect", Rect2, 地板, 洞顶]
		"halls": [
			["disc", Vector2(818, -128), 20.0, 16.0], ["disc", Vector2(1246, -70), 16.0, 13.0],
			["disc", Vector2(1218, 282), 18.0, 14.0], ["disc", Vector2(960, 252), 18.0, 18.0],
			["disc", Vector2(768, 198), 12.0, 16.0], ["disc", Vector2(1238, 158), 12.0, 15.0],
			["disc", Vector2(1048, -138), 12.0, 16.0], ["disc", Vector2(1012, -100), 11.0, 16.0],
			["rect", Rect2(828, 4, 64, 64), 15.0, 40.0],          # 绛罗场地（DarkArea X145..177 Z465..497）
			["rect", Rect2(1142, -228, 88, 88), 14.0, 40.0],      # 沙虫竞技场（DarkArea X302..346 Z569..613）
			["rect", Rect2(764, 16, 42, 20), 14.0, 36.0],         # 钥匙房 11 前厅（U2 下来的地方）
			["rect", Rect2(778, -12, 28, 28), 14.0, 36.0],
			["rect", Rect2(760, -6, 18, 20), 14.0, 36.0],         # 钥匙房 11（房间本身）
			["rect", Rect2(1186, -40, 20, 44), 11.0, 36.0],       # 钥匙房 12 前厅
			["rect", Rect2(1206, -36, 26, 30), 11.0, 36.0],       # 钥匙房 12（房间本身）
		],
		# 洞里的石柱（掩体）：中心、半径
		"pillars": [[Vector2(846, 22), 3.0], [Vector2(874, 50), 3.0], [Vector2(846, 52), 2.0], [Vector2(876, 20), 2.0],
				[Vector2(1160, -210), 3.0], [Vector2(1212, -158), 3.0], [Vector2(972, 262), 3.0], [Vector2(830, -116), 2.5]],
	}
	m["bosses"] = [
		{"id": "B1", "key": "lingyou", "name": "凌幽", "title": "金塔守灵", "layer": "surface", "pos": Vector3(12, 38, 82),
		 "arena": AABB(Vector3(-12, 38, 60), Vector3(48, 12, 44)), "respawn": 600.0, "model": "sand_lord",
		 "drops": "superBossDrops", "draws": 16, "summon": false, "altar": null, "da": Vector3(237, 88, 458)},
		{"id": "b2", "key": "jiangluo", "name": "绛罗", "title": "幽洞泣主", "layer": "cavern", "pos": dc(161, 8, 481),
		 "arena": cbox(dc, Vector3(145, 8, 465), Vector3(177, 27, 497)), "respawn": 500.0, "model": "ghost",
		 "drops": "superBossDrops1", "draws": 16, "summon": false, "altar": null, "da": Vector3(161, 8, 481)},
		{"id": "W", "key": "worm", "name": "沙渊巨虫", "title": "沙虫竞技场", "layer": "cavern", "pos": dc(324, 8, 591),
		 "arena": cbox(dc, Vector3(302, 7, 569), Vector3(346, 27, 613)), "respawn": 600.0, "model": "worm",
		 "drops": "sandWormBossDrop", "draws": 16, "summon": true, "cooldown": 600.0, "altar": dc(324, 9, 576),
		 "cages": [dc(305, 8, 572), dc(343, 8, 572), dc(343, 8, 610), dc(305, 8, 610)], "da": Vector3(324, 8, 591)},
	]
	m["key_rooms"] = [
		{"id": "k11", "num": 11, "layer": "cavern", "kind": "cave", "room": AABB(Vector3(760, 14, -6), Vector3(18, 22, 20)),
		 "door": Vector3(778, 14, 4), "dir": Vector3(1, 0, 0), "door_w": 4.4, "door_h": 5.0, "wall_top": 36.0,
		 "tables": {"supply": "desertLockedSupplyBox", "weapon": "desertLockedSWeaponBox"},
		 "da_door": Vector3(120, 11, 497), "da_box": cbox(dc, Vector3(110, 7, 490), Vector3(125, 21, 505)),
		 "slots": [[Vector3(763, 14, -3), "supply"], [Vector3(763, 14, 11), "supply"], [Vector3(770, 14, -3), "weapon"]]},
		{"id": "k12", "num": 12, "layer": "cavern", "kind": "cave", "room": AABB(Vector3(1206, 11, -36), Vector3(26, 25, 30)),
		 "door": Vector3(1206, 11, -16), "dir": Vector3(-1, 0, 0), "door_w": 4.4, "door_h": 5.0, "wall_top": 36.0,
		 "tables": {"supply": "desertLockedSupplyBox", "weapon": "desertLockedSWeaponBox"},
		 "da_door": Vector3(332, 4, 507), "da_box": cbox(dc, Vector3(325, 3, 497), Vector3(350, 17, 520)),
		 "slots": [[Vector3(1229, 11, -33), "supply"], [Vector3(1229, 11, -9), "supply"], [Vector3(1220, 11, -33), "weapon"],
				[Vector3(1220, 11, -9), "supply"]]},
	]
	# 进出洞窟：a = 地面一侧的触发点（坑底洞口前）、b = 洞里的光井（站进去传上地面）；*_out = 传过去后落在哪
	var links: Array = []
	var cav_nodes := {"C": [Vector2(C + 12.0, -100.0), Vector2(-0.98, -0.2)], "U1": [Vector2(C + 48.0, -138.0), Vector2(0.4, -0.92)],
			"U2": [Vector2(C - 228.0, 26.0), Vector2(0.95, 0.0)], "U3": [Vector2(C - 232.0, 198.0), Vector2(0.9, 0.45)],
			"U4": [Vector2(C + 238.0, 158.0), Vector2(-0.15, -0.99)]}
	for pt: Dictionary in m["pits"]:
		var c: Vector2 = pt["c"]
		var d: Vector3 = pt["d"]
		var a := Vector3(c.x, DESERT_Y - 7.0, c.y) - d * 8.0
		var a_out := Vector3(c.x, DESERT_Y - 3.0, c.y) + d * 5.0
		links.append(_link(str(pt["id"]), a, a_out, yaw_of(d), cav_nodes[pt["id"]]))
	var cy: Dictionary = m["canyon"]
	var cpts: Array = cy["pts"]
	var cend: Vector2 = cpts[cpts.size() - 1]
	var cback := Vector3((cpts[cpts.size() - 2] as Vector2).x - cend.x, 0.0, (cpts[cpts.size() - 2] as Vector2).y - cend.y).normalized()
	links.append(_link("C", Vector3(cend.x, 8.0, cend.y) + cback * 3.5, Vector3(cend.x, 8.0, cend.y) + cback * 13.0, yaw_of(cback), cav_nodes["C"]))
	m["links"] = links
	# 遗迹群（随机但固定：种子 7711）
	m["ruins"] = _desert_ruins(m)
	m["camps"] = _desert_camps(m)
	m["boxes"] = _desert_boxes(m)
	m["pois"] = [
		{"id": "P", "name": "黄金神塔", "pos": Vector3(12, 38, 82), "kind": "boss", "layer": "surface"},
		{"id": "C", "name": "北峡", "pos": Vector3(-30, 14, -91), "kind": "cave", "layer": "surface"},
		{"id": "W", "name": "西洞", "pos": Vector3(800, 15, 40), "kind": "area", "layer": "cavern"},
		{"id": "E", "name": "东洞", "pos": Vector3(1215, 13, 60), "kind": "area", "layer": "cavern"},
	]
	m["buildings"] = []          # 沙漠没有能进的楼（遗迹都是露天的）
	# 夜里加刷（2026-11-24 F_maps，review gap-desert-night）：DarkArea 入夜后每 90 秒给战区里每个真人刷怪（OnTurnToNight → RandomSpawnMonster），
	# 沙漠也算；SPEC 4.9 原写「沙漠只有光照变化」，这里补上，形状同研究所的尸潮（extract_manager._horde 读 points("horde")[0]）：
	# 每 90 秒在真人 20 ~ 40 米外刷 2 ~ 3 只毒尾蝎 / 沙漠狼，夜里加刷的同时在场最多 10 只；掉落照普通小怪（desertmonsterDrops）。
	# 人在洞窟里也照刷（find_spawn_near 按人所在那一层找落点；DarkArea 的地下也算战区）
	m["horde"] = {"interval": 90.0, "r_min": 20.0, "r_max": 40.0, "n_min": 2, "n_max": 3, "kinds": ["scorpion", "wolf_sand"], "cap": 10}
	return m


static func _link(id: String, a: Vector3, a_out: Vector3, a_yaw: float, node: Array) -> Dictionary:
	var c: Vector2 = node[0]
	var d: Vector2 = (node[1] as Vector2).normalized()
	var fl := 16.0
	var b := Vector3(c.x, fl, c.y)
	var b_out := Vector3(c.x + d.x * 7.0, fl, c.y + d.y * 7.0)
	return {"id": id, "a": a, "a_out": a_out, "a_yaw": a_yaw, "b": b, "b_out": b_out,
			"b_yaw": yaw_of(Vector3(d.x, 0.0, d.y)), "r": 2.8}


## 避让：离这些点太近的地方不放遗迹 / 刷怪点 / 箱子
static func _desert_clear(m: Dictionary, p: Vector2, r: float) -> bool:
	var py: Dictionary = m["pyramid"]
	var pc: Vector2 = py["c"]
	if absf(p.x - pc.x) < 72.0 + r and absf(p.y - pc.y) < 70.0 + r:
		return false
	for s: Dictionary in m["spawns"]:
		if str(s["layer"]) == "surface" and Vector2((s["pos"] as Vector3).x, (s["pos"] as Vector3).z).distance_to(p) < 26.0 + r:
			return false
	for e: Dictionary in m["extracts"]:
		if Vector2((e["pos"] as Vector3).x, (e["pos"] as Vector3).z).distance_to(p) < 30.0 + r:
			return false
	for pt: Dictionary in m["pits"]:
		if (pt["c"] as Vector2).distance_to(p) < 22.0 + r:
			return false
	for ms: Array in m["mesas"]:
		if (ms[0] as Vector2).distance_to(p) < float(ms[1]) + 8.0 + r:
			return false
	var cpts: Array = (m["canyon"] as Dictionary)["pts"]
	for i in cpts.size() - 1:
		if Geometry2D.get_closest_point_to_segment(p, cpts[i], cpts[i + 1]).distance_to(p) < 16.0 + r:
			return false
	var pl: Rect2 = (m["layers"]["surface"] as Dictionary)["play"]
	return pl.grow(-24.0 - r).has_point(p)


## 遗迹：0 石柱圈 1 断墙 2 图腾 + 断像 3 石拱门 4 倒伏的巨像 5 小神龛（带顶的三面墙）
static func _desert_ruins(m: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	var out: Array = []
	var tries := 0
	while out.size() < 30 and tries < 2000:
		tries += 1
		var pl: Rect2 = (m["layers"]["surface"] as Dictionary)["play"]
		var p := Vector2(rng.randf_range(pl.position.x, pl.end.x), rng.randf_range(pl.position.y, pl.end.y))
		if not _desert_clear(m, p, 6.0):
			continue
		var ok := true
		for r: Dictionary in out:
			if (r["c"] as Vector2).distance_to(p) < 46.0:
				ok = false
				break
		if not ok:
			continue
		out.append({"c": p, "type": out.size() % 6, "yaw": float(rng.randi() % 4) * PI * 0.5 + rng.randf_range(-0.25, 0.25), "seed": rng.randi()})
	# 金字塔四面的神道：两排石柱
	var py: Dictionary = m["pyramid"]
	var pc: Vector2 = py["c"]
	for d: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		out.append({"c": pc + d * 86.0, "type": 6, "yaw": atan2(-d.x, -d.y), "seed": int(d.x * 7.0 + d.y * 13.0) + 99})
	return out


static func _desert_camps(m: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var out: Array = []
	var kinds_n := [["wolf_sand", "scorpion"], ["scorpion"], ["wolf_sand"], ["sand_guard", "scorpion"], ["sand_raider"]]
	var ruins: Array = m["ruins"]
	# 一半刷在遗迹旁（守着箱子），一半刷在开阔地
	for i in ruins.size():
		if i % 2 == 1 or (ruins[i] as Dictionary)["type"] == 6:
			continue
		var c: Vector2 = (ruins[i] as Dictionary)["c"]
		var p := c + Vector2.from_angle(rng.randf() * TAU) * 12.0
		var ks: Array = kinds_n[(i / 2) % kinds_n.size()]
		out.append({"pos": Vector3(p.x, DESERT_Y, p.y), "kinds": ks, "n": 3 + rng.randi() % 3, "r": 9.0, "layer": "surface", "elite": false})
	var tries := 0
	var open_n := 0
	while open_n < 8 and tries < 1500:
		tries += 1
		var pl: Rect2 = (m["layers"]["surface"] as Dictionary)["play"]
		var p := Vector2(rng.randf_range(pl.position.x, pl.end.x), rng.randf_range(pl.position.y, pl.end.y))
		if not _desert_clear(m, p, 14.0):
			continue
		var ok := true
		for c: Dictionary in out:
			if Vector2((c["pos"] as Vector3).x, (c["pos"] as Vector3).z).distance_to(p) < 60.0:
				ok = false
				break
		if not ok:
			continue
		var ks2: Array = kinds_n[open_n % 4]
		out.append({"pos": Vector3(p.x, DESERT_Y, p.y), "kinds": ks2, "n": 3 + rng.randi() % 3, "r": 11.0, "layer": "surface", "elite": open_n % 4 == 3})
		open_n += 1
	# 金字塔脚下两处沙灵守卫（精英）
	out.append({"pos": Vector3(12 - 70, DESERT_Y, 82 + 30), "kinds": ["sand_guard"], "n": 3, "r": 8.0, "layer": "surface", "elite": true})
	out.append({"pos": Vector3(12 + 70, DESERT_Y, 82 - 30), "kinds": ["sand_guard"], "n": 3, "r": 8.0, "layer": "surface", "elite": true})
	# 洞窟：隧道中段 + 洞厅边上（出生点和 Boss 场地里不刷）
	for cp: Array in [[Vector2(842, 112), 16.0], [Vector2(850, 240), 17.0], [Vector2(1080, 292), 16.0], [Vector2(1226, 80), 13.0],
			[Vector2(1244, -118), 14.0], [Vector2(1090, -150), 15.0], [Vector2(920, -110), 16.0], [Vector2(790, -60), 16.0], [Vector2(796, 0), 14.0]]:
		var q: Vector2 = cp[0]
		out.append({"pos": Vector3(q.x, float(cp[1]), q.y), "kinds": ["scorpion", "sand_guard"] if out.size() % 2 == 0 else ["scorpion"],
				"n": 3 + out.size() % 3, "r": 6.0, "layer": "cavern", "elite": out.size() % 4 == 0})
	return out


## 箱子：kind 武器 / 物资 / 医疗（约 3 : 5 : 2）。沙漠约 60 个 + 钥匙房里的
static func _desert_boxes(m: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var out: Array = []
	var roll := func() -> String:
		var r := rng.randf()
		return "weapon" if r < 0.3 else ("supply" if r < 0.8 else "med")
	for r: Dictionary in m["ruins"]:
		var c: Vector2 = r["c"]
		var n := 1 if int(r["type"]) == 6 else (2 if int(r["seed"]) % 3 == 0 else 1)
		for i in n:
			var o := Vector2.from_angle(float(r["yaw"]) + float(i) * 2.4 + 0.7) * (4.5 + float(i) * 2.0)
			out.append({"pos": Vector3(c.x + o.x, DESERT_Y, c.y + o.y), "kind": roll.call(), "layer": "surface", "room": ""})
	# 金字塔各层的转角（爬上去有东西）
	var py: Dictionary = m["pyramid"]
	var pc: Vector2 = py["c"]
	for k: Array in [[2, Vector2(1, 1)], [3, Vector2(-1, -1)], [4, Vector2(1, -1)], [1, Vector2(-1, 1)]]:
		var tier := int(k[0])
		var hx := 24.0 + 6.0 * float(tier) - 3.0
		var hz := 22.0 + 6.0 * float(tier) - 3.0
		var s: Vector2 = k[1]
		out.append({"pos": Vector3(pc.x + s.x * hx, 38.0 - 3.0 * float(tier), pc.y + s.y * hz), "kind": roll.call(), "layer": "surface", "room": ""})
	# 峡谷里、四个洞口坑底
	out.append({"pos": Vector3(-30, 14, -96), "kind": "supply", "layer": "surface", "room": ""})
	out.append({"pos": Vector3(2, 9, -94), "kind": "weapon", "layer": "surface", "room": ""})
	for pt: Dictionary in m["pits"]:
		var c2: Vector2 = pt["c"]
		var d: Vector3 = pt["d"]
		var side := Vector3(-d.z, 0.0, d.x)
		var bp := Vector3(c2.x, DESERT_Y - 7.0, c2.y) - d * 5.0 + side * 4.5
		out.append({"pos": bp, "kind": "med" if out.size() % 2 == 0 else "supply", "layer": "surface", "room": ""})
	# 洞窟：出生洞厅边上、隧道转角、两个 Boss 场地的角上
	for cb: Array in [[Vector2(806, -140), 16.0], [Vector2(830, -116), 16.0], [Vector2(1256, -60), 13.0], [Vector2(1234, -80), 13.0],
			[Vector2(1206, 294), 14.0], [Vector2(1230, 272), 14.0], [Vector2(948, 262), 18.0], [Vector2(972, 242), 18.0],
			[Vector2(832, 8), 15.0], [Vector2(888, 64), 15.0], [Vector2(1146, -224), 14.0], [Vector2(1226, -144), 14.0],
			[Vector2(776, 206), 16.0], [Vector2(1020, -92), 16.0], [Vector2(800, 30), 14.0]]:
		var q: Vector2 = cb[0]
		out.append({"pos": Vector3(q.x, float(cb[1]), q.y), "kind": roll.call(), "layer": "cavern", "room": ""})
	return out


# ---------- 天工秘所 ----------

static func _lab() -> Dictionary:
	var m := {"id": "lab", "name": "天工秘所", "sub": "尸傀所据 · 机关古坊", "base_y": LAB_Y,
			"death_drop_stacks": 2, "box_quality": "lab"}
	m["layers"] = {
		"surface": {"grid": Rect2(-464, -464, 928, 928), "play": Rect2(-388, -388, 776, 776),
				"bound": Rect2(-401, -401, 802, 802), "fly_cap": LAB_Y + 35.0, "ceil": 1.0e9, "center": Vector3(0, 50, 0)},
		"cavern": {"grid": Rect2(776, -144, 256, 272), "play": Rect2(780, -140, 248, 264),
				"bound": Rect2(780, -140, 248, 264), "fly_cap": 27.0, "ceil": 28.0, "center": Vector3(901, 10, -2)},
	}
	# 外圈：围墙（离中心 396 ~ 404 米，墙顶 66）→ 墙外深谷（404 ~ 444，谷底 6）→ 远处崖壁（444 ~ 464，顶 60）；墙顶上方一圈禁制光幕
	m["wall"] = {"in": 396.0, "out": 404.0, "top": 66.0, "chasm": 444.0, "chasm_y": 6.0, "rim_y": 60.0, "barrier": 398.0}
	m["spawns"] = [
		{"id": "S1", "pos": ls(-1145, 90, 775), "layer": "surface", "da": Vector3(-1145, 93, 775)},
		{"id": "S2", "pos": ls(-1226, 90, 595), "layer": "surface", "da": Vector3(-1226, 91, 595)},
		{"id": "S3", "pos": ls(-1268, 90, 514), "layer": "surface", "da": Vector3(-1268, 90, 514)},
		{"id": "S4", "pos": ls(-1227, 90, 463), "layer": "surface", "da": Vector3(-1227, 91, 463)},
		{"id": "S5", "pos": ls(-1234, 90, 301), "layer": "surface", "da": Vector3(-1234, 91, 301)},
	]
	# 撤离区：DarkArea 的盒子横向 ×1.5；E2 / E5 原图在高出路面的台子上（y96 / y95），这里做成 5 米高的台子
	var ex: Array = []
	for e: Array in [["E1", -963.0, 281.0, 30.0, 18.0, 0.0], ["E2", -813.0, 282.0, 30.0, 18.0, 5.0], ["E3", -774.0, 392.0, 18.0, 30.0, 0.0],
			["E4", -809.0, 669.0, 30.0, 18.0, 0.0], ["E5", -858.0, 768.0, 30.0, 18.0, 5.0], ["E6", -1003.0, 777.0, 30.0, 18.0, 0.0],
			["E7", -1269.0, 720.0, 18.0, 30.0, 0.0], ["E8", -1269.0, 384.0, 18.0, 30.0, 0.0]]:
		var p := ls(float(e[1]), 90.0, float(e[2]))
		ex.append({"id": e[0], "pos": Vector3(p.x, LAB_Y + 1.0 + float(e[5]), p.z), "size": Vector3(float(e[3]), 7, float(e[4])),
				"raised": float(e[5]), "layer": "surface", "da": Vector3(float(e[1]), 94.5, float(e[2]))})
	m["extracts"] = ex
	m["doctor"] = {"pos": Vector3(1.5, 55.5, 3.0), "layer": "surface", "da": Vector3(-1021, 94, 526)}
	m["bosses"] = [
		{"id": "B1", "key": "lingying", "name": "凌影", "title": "尸傀密窟", "layer": "cavern", "pos": lb(-1021, 31, 529),
		 "arena": AABB(Vector3(870, 10, -33), Vector3(63, 18, 63)), "respawn": 600.0, "model": "gel_mutant",
		 "drops": "yanjiuBossDrops1", "drops_night": "yanjiuBossDrops2", "draws": 16, "summon": false, "altar": null, "da": Vector3(-1021, 32, 529)},
		{"id": "B2", "key": "dianbian", "name": "电鞭铁卫", "title": "百炼坊", "layer": "surface", "pos": Vector3(-7.5, 54, 318),
		 "arena": AABB(Vector3(-36, 54, 290), Vector3(56, 10, 56)), "respawn": 500.0, "model": "mech_hunter",
		 "drops": "yanjiuBossputong1", "draws": 16, "summon": false, "altar": null, "da": Vector3(-1027, 90, 316)},
		{"id": "B3", "key": "bingjiang", "name": "冰僵铁卫", "title": "镇尸营", "layer": "surface", "pos": Vector3(-57, 60, -326),
		 "arena": AABB(Vector3(-86, 60, -354), Vector3(56, 8, 58)), "respawn": 500.0, "model": "mech_colossus",
		 "drops": "yanjiuBossputong2", "draws": 16, "summon": false, "altar": null, "da": Vector3(-1060, 100, 745)},
		{"id": "L", "key": "twin", "name": "铁穹双卫", "title": "双子斗场", "layer": "surface", "pos": Vector3(312, 34, 31.5), "pos2": Vector3(312, 34, 9),
		 "arena": AABB(Vector3(286, 34, -5), Vector3(52, 16, 52)), "respawn": 600.0, "model": "mech_hunter", "model2": "mech_welder",
		 "drops": "lvBuDiaoChanBossDrop", "draws": 48, "summon": true, "cooldown": 600.0, "altar": Vector3(312, 34, -1),
		 "da": Vector3(-814, 77, 507)},
	]
	# 双子斗场：下沉 16 米的圆形斗场（台阶看台）
	m["bowl"] = {"c": Vector2(312, 21), "r": 26.0, "floor": 34.0, "outer": 44.0}
	# 镇尸营高台（冰僵铁卫）：顶 60；K7 嵌在台子南边的台下
	m["platforms"] = [{"rect": Rect2(-86, -354, 56, 58), "top": 60.0, "stairs": "e"}, {"rect": Rect2(-36, 290, 56, 56), "top": 54.0, "stairs": "n"}]
	# 钥匙房（kind: pit = 下沉坑里的房间，盖板与地面齐平；floor = 二层；hut = 地面上的小屋；deck = 嵌在高台下面）
	var T := {"supply": "labLockedSupplyBox", "weapon": "labLockedSWeaponBox"}
	m["key_rooms"] = [
		_kr(1, "pit", AABB(Vector3(78, 40, -42), Vector3(26, 10, 34)), Vector3(78, 40, -24), Vector3(-1, 0, 0), ls(-974, 74, 544),
				cbox(ls, Vector3(-977, 73, 532), Vector3(-950, 88, 557)), T, 3),
		_kr(2, "pit", AABB(Vector3(40, 40, 34), Vector3(28, 10, 28)), Vector3(54, 40, 34), Vector3(0, 0, -1), ls(-986, 74, 509),
				cbox(ls, Vector3(-1004, 70, 485), Vector3(-975, 79, 514)), T, 3),
		_kr(3, "pit", AABB(Vector3(-94, 38, -6), Vector3(28, 12, 36)), Vector3(-66, 38, 19.5), Vector3(1, 0, 0), ls(-1063, 73, 515),
				cbox(ls, Vector3(-1086, 57, 503), Vector3(-1059, 82, 534)), T, 4),
		_kr(4, "floor", AABB(Vector3(-44, 55.5, 246), Vector3(38, 5.5, 28)), Vector3(-6, 55.5, 256.5), Vector3(1, 0, 0), ls(-1026, 97, 357),
				cbox(ls, Vector3(-1048, 95, 345), Vector3(-1017, 107, 365)), T, 3),
		_kr(5, "pit", AABB(Vector3(112, 38, 104), Vector3(56, 12, 56)), Vector3(112, 38, 132), Vector3(-1, 0, 0), ls(-947, 83, 440),
				cbox(ls, Vector3(-955, 57, 410), Vector3(-905, 87, 467)), T, 4),
		_kr(6, "pit", AABB(Vector3(40, 40, -362), Vector3(40, 10, 30)), Vector3(70.5, 40, -332), Vector3(0, 0, 1), ls(-975, 71, 742),
				cbox(ls, Vector3(-1007, 67, 725), Vector3(-964, 81, 771)), T, 3),
		_kr(7, "deck", AABB(Vector3(-78, 50, -322), Vector3(34, 10, 26)), Vector3(-66, 50, -296), Vector3(0, 0, 1), ls(-1066, 76, 726),
				cbox(ls, Vector3(-1075, 74, 714), Vector3(-1047, 81, 745)), T, 3),
		_kr(8, "pit", AABB(Vector3(-226, 44, -136), Vector3(28, 6, 24)), Vector3(-198, 44, -127.5), Vector3(1, 0, 0), ls(-1151, 84, 613),
				cbox(ls, Vector3(-1175, 82, 595), Vector3(-1135, 87, 620)), T, 2),
		_kr(9, "pit", AABB(Vector3(-292, 44, 42), Vector3(26, 6, 28)), Vector3(-279, 44, 70), Vector3(0, 0, 1), ls(-1208, 84, 486),
				cbox(ls, Vector3(-1218, 82, 475), Vector3(-1197, 90, 501)), T, 2),
		_kr(10, "hut", AABB(Vector3(192, 50, -102), Vector3(22, 6, 34)), Vector3(192, 50, -85.5), Vector3(-1, 0, 0), ls(-895, 91, 585),
				cbox(ls, Vector3(-900, 90, 572), Vector3(-879, 97, 597)), T, 3),
	]
	# 能进的楼：rect = 外墙占地；storeys 层数（一层 5.5 米）；doors = [朝向, 沿墙偏移, 宽]；upper = 二层平台（顶 55.5）；stairs = [起点, 方向, 宽]
	m["buildings"] = [
		{"id": "hall", "name": "天工楼", "rect": Rect2(-30, -20, 64, 48), "storeys": 2, "style": "hall",
		 "doors": [["s", 2.0, 6.0], ["n", 2.0, 5.0], ["w", 14.0, 4.5], ["e", 14.0, 4.5]],
		 "upper": Rect2(-30, -20, 64, 28), "stairs": [Vector2(22, 18), Vector2(0, -1), 3.4]},
		{"id": "factory", "name": "百炼坊", "rect": Rect2(-48, 222, 108, 58), "storeys": 2, "style": "factory",
		 "doors": [["n", 32.0, 6.0], ["e", 6.0, 6.0], ["s", -4.0, 6.0]],
		 "upper": Rect2(-48, 222, 52, 58), "stairs": [Vector2(14.5, 224.8), Vector2(-1, 0), 3.4]},
		{"id": "K10", "name": "东区小屋", "rect": Rect2(191.2, -102.8, 23.6, 35.6), "storeys": 1, "style": "hut", "doors": [], "key_room": "K10"},
		{"id": "u3", "name": "梯亭", "rect": Rect2(-104.5, 94.5, 14, 14), "storeys": 1, "style": "kiosk", "doors": [["n", 0.0, 5.0]], "well": "u3"},
		{"id": "u4", "name": "梯亭", "rect": Rect2(-73, -103, 14, 14), "storeys": 1, "style": "kiosk", "doors": [["s", 0.0, 5.0]], "well": "u4"},
		{"id": "u5", "name": "梯亭", "rect": Rect2(92, -116.5, 14, 14), "storeys": 1, "style": "kiosk", "doors": [["s", 0.0, 5.0]], "well": "u5"},
		{"id": "W1", "name": "西坊", "rect": Rect2(-320, -246, 30, 22), "storeys": 1, "style": "shop", "doors": [["e", 0.0, 5.0], ["s", 6.0, 4.5]]},
		{"id": "W2", "name": "料仓", "rect": Rect2(-262, -50, 24, 16), "storeys": 1, "style": "shed", "doors": [["s", 0.0, 5.0], ["e", 0.0, 4.5]]},
		{"id": "W3", "name": "西库", "rect": Rect2(-250, 170, 32, 20), "storeys": 1, "style": "store", "doors": [["e", 0.0, 5.0], ["n", -6.0, 4.5]]},
		{"id": "W4", "name": "棚屋", "rect": Rect2(-306, 250, 22, 16), "storeys": 1, "style": "shed", "doors": [["e", 0.0, 4.5]]},
		{"id": "C1", "name": "北库", "rect": Rect2(-170, -272, 36, 24), "storeys": 1, "style": "store", "doors": [["s", 0.0, 6.0], ["e", 0.0, 4.5]]},
		{"id": "C2", "name": "炼器坊", "rect": Rect2(-170, 112, 30, 22), "storeys": 1, "style": "shop", "doors": [["e", 0.0, 5.0], ["w", 0.0, 4.5]]},
		{"id": "C3", "name": "匠舍", "rect": Rect2(-180, 300, 30, 18), "storeys": 1, "style": "dorm", "doors": [["n", 0.0, 4.5]]},
		{"id": "C4", "name": "东南坊", "rect": Rect2(170, 250, 32, 22), "storeys": 1, "style": "shop", "doors": [["n", 0.0, 5.0], ["w", 0.0, 4.5]]},
		{"id": "N1", "name": "镇尸营房", "rect": Rect2(4, -262, 34, 18), "storeys": 1, "style": "dorm", "doors": [["s", 0.0, 5.0]]},
		{"id": "N2", "name": "营房", "rect": Rect2(100, -286, 26, 16), "storeys": 1, "style": "dorm", "doors": [["s", 0.0, 4.5], ["w", 0.0, 4.5]]},
		{"id": "N3", "name": "北仓", "rect": Rect2(160, -350, 30, 20), "storeys": 1, "style": "store", "doors": [["s", 0.0, 5.0]]},
		{"id": "E_1", "name": "机枢坊", "rect": Rect2(214, -166, 34, 24), "storeys": 1, "style": "shop", "doors": [["w", 0.0, 5.0], ["s", 4.0, 4.5]]},
		{"id": "E_2", "name": "铸铜坊", "rect": Rect2(232, 112, 30, 22), "storeys": 1, "style": "shop", "doors": [["w", 0.0, 5.0], ["n", 0.0, 4.5]]},
		{"id": "E_3", "name": "东库", "rect": Rect2(300, -312, 26, 18), "storeys": 1, "style": "store", "doors": [["w", 0.0, 5.0]]},
		{"id": "S_1", "name": "南坊", "rect": Rect2(-130, 290, 28, 20), "storeys": 1, "style": "shop", "doors": [["e", 0.0, 5.0], ["n", 0.0, 4.5]]},
		{"id": "S_2", "name": "南棚", "rect": Rect2(150, 330, 24, 16), "storeys": 1, "style": "shed", "doors": [["n", 0.0, 4.5]]},
		{"id": "A1", "name": "器库", "rect": Rect2(-60, -140, 30, 20), "storeys": 1, "style": "store", "doors": [["s", 0.0, 5.0]]},
		{"id": "A2", "name": "匠坊", "rect": Rect2(40, -150, 32, 22), "storeys": 1, "style": "shop", "doors": [["w", 0.0, 5.0], ["s", 6.0, 4.5]]},
		{"id": "A3", "name": "料场棚", "rect": Rect2(140, -60, 26, 18), "storeys": 1, "style": "shed", "doors": [["w", 0.0, 5.0]]},
		{"id": "A4", "name": "西料库", "rect": Rect2(-340, -160, 28, 18), "storeys": 1, "style": "store", "doors": [["e", 0.0, 5.0]]},
		{"id": "A5", "name": "西匠舍", "rect": Rect2(-280, 120, 24, 16), "storeys": 1, "style": "dorm", "doors": [["n", 0.0, 4.5]]},
		{"id": "A6", "name": "南库", "rect": Rect2(-100, 350, 28, 18), "storeys": 1, "style": "store", "doors": [["n", 0.0, 5.0]]},
		{"id": "A7", "name": "东南仓", "rect": Rect2(250, 240, 28, 20), "storeys": 1, "style": "store", "doors": [["w", 0.0, 5.0]]},
		{"id": "A8", "name": "东北坊", "rect": Rect2(270, -60, 30, 22), "storeys": 1, "style": "shop", "doors": [["w", 0.0, 5.0], ["n", 0.0, 4.5]]},
	]
	# 主楼院墙（4.5 米，带四道院门）
	m["compound"] = {"rect": Rect2(-102, -48, 210, 120), "h": 4.6, "gates": [["n", -1.0, 12.0], ["s", -1.0, 12.0], ["w", 38.0, 10.0], ["e", -12.0, 10.0]]}
	# 地下室：凌影的场地 + 三条隧道通到三处楼梯口的落点
	m["cave"] = {
		"rock_y": 29.0, "ceil": 28.0,
		"tunnels": [
			[[Vector2(802.5, 100.5), Vector2(840, 60), Vector2(878, 24)], [10.0, 10.0, 10.0], 14.0],
			[[Vector2(834, -96), Vector2(852, -58), Vector2(878, -28)], [10.0, 10.0, 10.0], 14.0],
			[[Vector2(999, -109.5), Vector2(978, -60), Vector2(928, -28)], [10.0, 10.0, 10.0], 14.0],
		],
		"halls": [["rect", Rect2(870, -33, 63, 63), 10.0, 28.0], ["disc", Vector2(802.5, 100.5), 12.0, 10.0],
				["disc", Vector2(834, -96), 12.0, 10.0], ["disc", Vector2(999, -109.5), 12.0, 10.0]],
		"pillars": [[Vector2(884, -18), 2.5], [Vector2(918, -18), 2.5], [Vector2(884, 16), 2.5], [Vector2(918, 16), 2.5]],
	}
	# 楼梯口 u3 / u4 / u5（主楼外三座梯亭，井底传到地下室）；u1 / u2 / u6 只是图标（贴着钥匙房 5 / 7）
	var links: Array = []
	for w: Array in [["u3", -1087.0, 461.0, Vector2(0.6, -0.8)], ["u4", -1066.0, 592.0, Vector2(0.55, 0.83)], ["u5", -956.0, 601.0, Vector2(-0.4, 0.92)]]:
		var c := ls(float(w[1]), 90.0, float(w[2]))
		var b := lb(float(w[1]), 31.0, float(w[2]))
		var bd: Vector2 = (w[3] as Vector2).normalized()
		var bld: Dictionary = {}
		for bb: Dictionary in m["buildings"]:
			if str(bb.get("well", "")) == str(w[0]):
				bld = bb
		var r: Rect2 = bld["rect"]
		var door_side: String = (bld["doors"] as Array)[0][0]
		var f := Vector3(0, 0, -1) if door_side == "n" else Vector3(0, 0, 1)
		var cc := Vector3(r.get_center().x, LAB_Y, r.get_center().y)
		links.append({"id": w[0], "a": cc - f * 4.5 + Vector3(0, -5.0, 0), "a_out": cc + f * 3.5, "a_yaw": yaw_of(f),
				"b": Vector3(b.x, 10.0, b.z), "b_out": Vector3(b.x + bd.x * 7.0, 10.0, b.z + bd.y * 7.0), "b_yaw": yaw_of(Vector3(bd.x, 0, bd.y)),
				"r": 2.6, "da": Vector2(float(w[1]), float(w[2])), "center": cc, "f": f})
	m["links"] = links
	m["roads"] = [[Vector2(-388, 160), Vector2(388, 160), 10.0], [Vector2(-388, -180), Vector2(388, -180), 10.0],
			[Vector2(-220, -388), Vector2(-220, 388), 10.0], [Vector2(200, -388), Vector2(200, 388), 10.0],
			[Vector2(-120, -60), Vector2(124, -60), 8.0], [Vector2(-120, 84), Vector2(124, 84), 8.0],
			[Vector2(-114, -60), Vector2(-114, 84), 8.0], [Vector2(120, -60), Vector2(120, 84), 8.0],
			[Vector2(4, -60), Vector2(4, -180), 8.0], [Vector2(4, 84), Vector2(4, 222), 8.0], [Vector2(120, 12), Vector2(200, 12), 8.0],
			[Vector2(-114, 12), Vector2(-220, 12), 8.0], [Vector2(200, 21), Vector2(268, 21), 8.0]]
	m["camps"] = _lab_camps()
	m["boxes"] = _lab_boxes(m)
	# 夜里尸潮（SPEC 4.5）：每 90 秒在每个真人 20 ~ 40 米外刷 3 ~ 5 只尸傀；horde_points = 夜里亮起来的「尸傀召唤柱」（地标）
	m["horde"] = {"interval": 90.0, "r_min": 20.0, "r_max": 40.0, "n_min": 3, "n_max": 5, "kinds": ["zombie"], "cap": 15}
	m["horde_points"] = [Vector3(-150, 50, -120), Vector3(150, 50, -230), Vector3(-260, 50, 100), Vector3(130, 50, 300),
			Vector3(-60, 50, 190), Vector3(260, 50, -60)]
	m["pois"] = [
		{"id": "R", "name": "天工楼", "pos": Vector3(2, 50, 4), "kind": "area", "layer": "surface"},
		{"id": "F", "name": "百炼坊", "pos": Vector3(6, 50, 250), "kind": "area", "layer": "surface"},
		{"id": "H", "name": "镇尸营", "pos": Vector3(-40, 50, -300), "kind": "area", "layer": "surface"},
		{"id": "L", "name": "双子斗场", "pos": Vector3(312, 34, 21), "kind": "boss", "layer": "surface"},
		{"id": "B", "name": "尸傀密窟", "pos": Vector3(901, 10, -2), "kind": "boss", "layer": "cavern"},
	]
	return m


static func _kr(num: int, kind: String, room: AABB, door: Vector3, dir: Vector3, da_door: Vector3, da_box: AABB, tables: Dictionary, nbox: int) -> Dictionary:
	var slots: Array = []
	var inner := room.grow(-2.2)
	var corners := [Vector3(inner.position.x, room.position.y, inner.position.z), Vector3(inner.end.x, room.position.y, inner.end.z),
			Vector3(inner.end.x, room.position.y, inner.position.z), Vector3(inner.position.x, room.position.y, inner.end.z)]
	var kinds := ["supply", "weapon", "supply", "supply"]
	# 离门最远的角先放（进门一眼看得到，又不堵门）
	corners.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(door) > b.distance_squared_to(door))
	for i in nbox:
		slots.append([corners[i], kinds[i]])
	return {"id": "K%d" % num, "num": num, "kind": kind, "layer": "surface", "room": room, "door": door, "dir": dir,
			"door_w": 4.4, "door_h": 4.6, "wall_top": room.end.y,
			"tables": tables.duplicate(), "da_door": da_door, "da_box": da_box, "slots": slots}


static func _lab_camps() -> Array:
	var out: Array = []
	var Z := ["zombie"]
	var MC := ["mech_claw", "zombie"]
	var MG := ["mech_gunner", "mech_claw"]
	var GEL := ["gel_mutant"]
	for c: Array in [
			[Vector3(-250, 50, -130), Z, 4], [Vector3(-300, 50, -10), Z, 3], [Vector3(-210, 50, 250), Z, 4], [Vector3(-260, 50, 330), MC, 3],
			[Vector3(-150, 50, -200), MC, 4], [Vector3(-150, 50, 60), Z, 4], [Vector3(-60, 50, -30), Z, 3], [Vector3(80, 50, 60), Z, 3],
			[Vector3(60, 50, -110), MG, 3], [Vector3(-40, 50, -240), MC, 4], [Vector3(130, 50, -250), MG, 3], [Vector3(250, 50, -260), Z, 4],
			[Vector3(250, 50, -100), MC, 4], [Vector3(330, 50, 120), MG, 3], [Vector3(200, 50, 190), Z, 4], [Vector3(90, 50, 200), MC, 3],
			[Vector3(-90, 50, 250), Z, 4], [Vector3(40, 50, 300), MG, 3], [Vector3(250, 50, 320), Z, 3], [Vector3(-90, 50, 380 - 40), Z, 3],
			[Vector3(90, 50, 112), GEL, 2, true], [Vector3(-10, 50, 210), GEL, 2, true], [Vector3(312, 50, 80), GEL, 2, true],
			[Vector3(840, 10, 60), Z, 4], [Vector3(852, 10, -58), Z, 4], [Vector3(978, 10, -60), MC, 3],
			# 2026-11-24 I_int：园区比沙漠稀一半（箱子边 100 米内常只有 0 ~ 4 只，用户两次嫌怪稀），在院子里的空地上补 10 处（离出生点都在 90 米外）
			[Vector3(-60, 50, -150), Z, 3], [Vector3(360, 50, -60), MC, 3], [Vector3(-60, 50, 120), Z, 3], [Vector3(180, 50, -30), MG, 3],
			[Vector3(-180, 50, -60), Z, 3], [Vector3(330, 50, -330), Z, 4], [Vector3(-30, 50, -330), MC, 3], [Vector3(255, 50, -20), Z, 3],
			[Vector3(-120, 50, -300), Z, 3], [Vector3(-300, 50, 200), MC, 3]]:
		out.append({"pos": c[0], "kinds": c[1], "n": int(c[2]), "r": 9.0 if (c[0] as Vector3).x < 600.0 else 6.0,
				"layer": "cavern" if (c[0] as Vector3).x > 600.0 else "surface", "elite": c.size() > 3})
	return out


## 研究所的箱子：楼里（贴墙角）+ 院子里 + 地下室 ≈ 90 个，另加钥匙房里的
static func _lab_boxes(m: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9090
	var out: Array = []
	var roll := func() -> String:
		var r := rng.randf()
		return "weapon" if r < 0.3 else ("supply" if r < 0.78 else "med")
	for b: Dictionary in m["buildings"]:
		if b.has("key_room") or b.has("well"):
			continue
		var r: Rect2 = b["rect"]
		var inner := r.grow(-2.4)
		var cs := [inner.position, inner.end, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y)]
		var n := 4 if str(b["id"]) in ["hall", "factory"] else (3 if r.get_area() > 600.0 else 2)
		for i in n:
			var q: Vector2 = cs[posmod(i * 3 + int(r.position.x), 4) if n < 4 else i]
			out.append({"pos": Vector3(q.x, LAB_Y, q.y), "kind": roll.call(), "layer": "surface", "room": "", "bld": b["id"]})
	# 两座二层楼的楼上
	for q2: Vector2 in [Vector2(-26, -16), Vector2(30, -16), Vector2(-44, 226), Vector2(0, 276)]:
		out.append({"pos": Vector3(q2.x, 55.5, q2.y), "kind": roll.call(), "layer": "surface", "room": ""})
	# 院子里 / 路边的货堆旁
	var yard := [Vector2(-90, -40), Vector2(96, 64), Vector2(-90, 64), Vector2(40, -40), Vector2(-280, -200), Vector2(-330, 120),
			Vector2(-200, -330), Vector2(-60, -150), Vector2(70, -200), Vector2(180, -300), Vector2(300, -150), Vector2(360, -60),
			Vector2(340, 60), Vector2(240, 200), Vector2(120, 250), Vector2(-200, 200), Vector2(-280, 300), Vector2(40, 340),
			Vector2(-150, 360), Vector2(250, 360), Vector2(-60, 120), Vector2(160, 60), Vector2(170, -40), Vector2(-180, -60),
			Vector2(-340, -340), Vector2(330, -330), Vector2(-30, -330), Vector2(110, 180), Vector2(-250, 50), Vector2(150, 140),
			Vector2(60, 190), Vector2(-120, 200), Vector2(280, -10), Vector2(-40, 120), Vector2(230, -230), Vector2(-120, -300),
			Vector2(-300, 200), Vector2(310, 270), Vector2(-350, 40), Vector2(20, -120)]
	for q3: Vector2 in yard.slice(0, 24):
		out.append({"pos": Vector3(q3.x, LAB_Y, q3.y), "kind": roll.call(), "layer": "surface", "room": ""})
	# 双子斗场看台边、K5 坑口
	out.append({"pos": Vector3(312, 34, 44), "kind": "weapon", "layer": "surface", "room": ""})
	out.append({"pos": Vector3(100, 38 + 0.0, 150), "kind": "supply", "layer": "surface", "room": ""})
	# 地下室
	for cb: Vector2 in [Vector2(806, 92), Vector2(840, -100), Vector2(1004, -100), Vector2(874, -29), Vector2(930, 26)]:
		out.append({"pos": Vector3(cb.x, 10, cb.y), "kind": roll.call(), "layer": "cavern", "room": ""})
	return out


# ---------- 收尾：编号、钥匙房的箱子、出生朝向 ----------

static func _finish(m: Dictionary) -> void:
	var boxes: Array = m["boxes"]
	for kr: Dictionary in m["key_rooms"]:
		var ids: Array = []
		for s: Array in kr["slots"]:
			boxes.append({"pos": s[0], "kind": s[1], "layer": kr["layer"], "room": kr["id"]})
		kr["boxes"] = ids
	var n := 0
	for b: Dictionary in boxes:
		b["id"] = "b%d" % n
		b["yaw"] = float(n % 4) * PI * 0.5
		n += 1
		if str(b["room"]) != "":
			for kr2: Dictionary in m["key_rooms"]:
				if kr2["id"] == b["room"]:
					(kr2["boxes"] as Array).append(b["id"])
	var ci := 0
	for c: Dictionary in m["camps"]:
		c["id"] = "c%d" % ci
		c["set"] = (c["kinds"] as Array)[0]
		ci += 1
	for kr3: Dictionary in m["key_rooms"]:
		var d: Vector3 = kr3["dir"]
		kr3["door_yaw"] = yaw_of(d)
		kr3["door_id"] = kr3["id"]
		kr3["open_at"] = (kr3["door"] as Vector3) + d * 2.2
	var lay: Dictionary = m["layers"]
	for s: Dictionary in m["spawns"]:
		var cen: Vector3 = (lay[s["layer"]] as Dictionary)["center"]
		s["yaw"] = yaw_to(s["pos"], cen)
	if not m.has("doctor"):
		m["doctor"] = {}


## 一个点在哪一层（两张图的洞窟 / 地下室都放在 x > 600 的另一片坐标）
static func layer_at(p: Vector3) -> String:
	return "cavern" if p.x > 600.0 else "surface"
