extends RefCounted
## 搜打撤新图（沙海古墟 desert / 天工秘所 lab）的怪物表：小怪 / 精英 / 首领 / 首领召唤物，SPEC 第 4.5 / 8 节。
## 每一项是 raid_mob.gd 直接吃的 def 字典（name / shape / spd / size / ranged / cols / model / elite_model …），
## 外加新图自己的字段（都不影响 raid_mob）：
##   id      表里的键；map  "desert" / "lab" / ""（召唤物两边都可能用）；kind  "mob" / "boss" / "add"
##   big     巨汉（血 ×BRUTE_HP）；elite_only  只以精英身份出现（凝胶怪）；loot  false = 死了不掉东西（首领召唤的小怪）
##   首领另有：boss_hp（DarkArea 原血量）、drop / draws（掉落表 / 抽数）、respawn（重生秒）或 summon_cd（召唤冷却）、summon（要祭台召唤）
## 数值全是「点数」，不看境界（SPEC 4.5）：
##   主角打怪 = 招式单位 u × HIT_PER_UNIT × 兵刃 PvE × (1 + 破军 PvE)（管理器的 dmg_in 里算，这里只给常量）；
##   怪的 hp_max = 点数；怪的 atk = 打在主角 100 点气血条上的点数（管理器的 atk_out 再乘 1 − 法衣 PvE 减伤）。
##   raid_mob 自己出手时还会乘：扑击 ×1（首领 ×1.5）、吐弹 ×0.7、震地 ×2。
## 用法见 _tasks/extraction_refactor/reports/B_mobs.md。故意不写 class_name：用 preload 引用。

## 主角打怪：每个招式单位折多少点（SPEC 4.5）
const HIT_PER_UNIT := 10.0
## 小怪血量（点）：沙漠 40、研究所 80；精英 ×3；巨汉 ×2（两者叠乘）
const HP_DESERT := 40.0
const HP_LAB := 80.0
const ELITE_HP := 3.0
const BRUTE_HP := 2.0
## 小怪攻击（打在条上的点数）：沙漠 5、研究所 12（DarkArea 10 / 35 按 ÷2 再压一点）；精英 ×1.5
const ATK_DESERT := 5.0
const ATK_LAB := 12.0
const ELITE_ATK := 1.5
## 首领血量 = DarkArea 血量 × BOSS_HP_K，再按战斗区里的真人数 × (0.6 + 0.4·min(人数,4)/4)
const BOSS_HP_K := 0.04
## 首领单下打在主角条上的封顶（点）
const BOSS_HIT_CAP := 35.0
## 召唤型首领（沙渊巨虫 / 铁穹双卫）要战斗区里至少几个真人才能召唤（DarkArea 4；本作单机也要能打）
const SUMMON_MIN := 1
## 刷怪点：每处几只（SPEC 4.5：3~5）、精英点的概率（一只精英 + 两只随从）
const CAMP_MIN := 3
const CAMP_MAX := 5
const CAMP_ELITE_P := 0.12

## 体色：[主色, 副色, 发光色]（raid_mob 的方块造型 / 法阵 / 轮廓光用）
const MOBS := {
	# ---------- 沙海古墟：小怪 ----------
	"scorpion": {"name": "毒尾蝎", "map": "desert", "kind": "mob", "shape": "beast", "spd": 8.0, "size": 1.0, "ranged": false,
		"model": "scorpion", "elite_model": "crystal_scorpion", "elite_name": "晶甲天蝎", "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.62, 0.42, 0.22), Color(0.32, 0.2, 0.12), Color(1.0, 0.62, 0.25)]},
	"wolf_sand": {"name": "沙漠狼", "map": "desert", "kind": "mob", "shape": "beast", "spd": 9.0, "size": 1.0, "ranged": false,
		"model": "wolf_sand", "elite_model": "wolf_void", "elite_name": "虚空沙狼", "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.78, 0.62, 0.4), Color(0.45, 0.34, 0.22), Color(1.0, 0.8, 0.4)]},
	"sand_guard": {"name": "沙灵守卫", "map": "desert", "kind": "mob", "shape": "brute", "big": true, "spd": 5.0, "size": 1.05, "ranged": false,
		"model": "sand_guard", "elite_model": "stone_giant", "elite_name": "沙灵巨像", "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.72, 0.56, 0.32), Color(0.46, 0.34, 0.2), Color(1.0, 0.72, 0.3)]},
	"sand_raider": {"name": "沙匪", "map": "desert", "kind": "mob", "shape": "brute", "spd": 6.5, "size": 1.0, "ranged": true,
		"model": "sand_raider", "mk": 0.82, "elite_name": "沙匪头目", "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.62, 0.22, 0.18), Color(0.3, 0.16, 0.12), Color(1.0, 0.5, 0.3)]},
	# ---------- 天工秘所：小怪 ----------
	"zombie": {"name": "尸傀", "map": "lab", "kind": "mob", "shape": "brute", "spd": 5.5, "size": 1.0, "ranged": false,
		"model": "zombie", "mk": 0.86, "elite_name": "尸傀统领", "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.42, 0.56, 0.3), Color(0.26, 0.3, 0.2), Color(0.7, 1.0, 0.4)]},
	"mech_claw": {"name": "机关钳击兵", "map": "lab", "kind": "mob", "shape": "brute", "spd": 5.0, "size": 1.0, "ranged": false,
		"model": "mech_claw", "mk": 0.86, "elite_name": "精钢钳击兵", "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.5, 0.36, 0.26), Color(0.28, 0.22, 0.18), Color(1.0, 0.55, 0.25)]},
	"mech_gunner": {"name": "机关炮击兵", "map": "lab", "kind": "mob", "shape": "brute", "spd": 4.5, "size": 1.0, "ranged": true,
		"model": "mech_gunner", "mk": 0.86, "elite_name": "精钢炮击兵", "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.52, 0.34, 0.22), Color(0.3, 0.2, 0.14), Color(1.0, 0.35, 0.25)]},
	"gel_mutant": {"name": "凝胶怪", "map": "lab", "kind": "mob", "elite_only": true, "shape": "beast", "spd": 6.0, "size": 1.0, "ranged": false,
		"model": "gel_mutant", "elite_name": "凝胶怪", "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.35, 0.85, 0.85), Color(0.2, 0.5, 0.55), Color(0.5, 1.0, 1.0)]},
	# ---------- 首领召唤物（不掉东西） ----------
	"wraith": {"name": "幽冥泣", "map": "desert", "kind": "add", "loot": false, "shape": "floater", "spd": 7.0, "size": 1.0, "ranged": true,
		"model": "eye_small", "add_hp": 4500.0, "atk_pts": 7.0, "hp": 1.0, "atk": 1.0,
		"cols": [Color(0.55, 0.4, 0.75), Color(0.3, 0.2, 0.45), Color(0.85, 0.55, 1.0)]},
	# ---------- 首领 ----------
	"lingyou": {"name": "凌幽", "title": "金塔守灵", "map": "desert", "kind": "boss", "boss": true, "shape": "brute", "spd": 0.0, "size": 4.0,
		"ranged": true, "model": "sand_lord", "hp": 1.0, "atk": 1.0, "boss_hp": 80000.0, "atk_pts": 10.0,
		"drop": "superBossDrops", "draws": 16, "respawn": 600.0,
		"cols": [Color(0.78, 0.32, 0.2), Color(0.45, 0.16, 0.12), Color(1.0, 0.7, 0.3)]},
	"jiangluo": {"name": "绛罗", "title": "幽洞泣魂", "map": "desert", "kind": "boss", "boss": true, "shape": "floater", "fly": true, "spd": 9.0,
		"size": 3.6, "ranged": true, "model": "void_apostle", "hp": 1.0, "atk": 1.0, "boss_hp": 90000.0, "atk_pts": 7.0,
		"drop": "superBossDrops1", "draws": 16, "respawn": 500.0,
		"cols": [Color(0.5, 0.36, 0.62), Color(0.26, 0.18, 0.34), Color(0.9, 0.5, 1.0)]},
	"sandworm": {"name": "沙渊巨虫", "title": "地下竞技场", "map": "desert", "kind": "boss", "boss": true, "shape": "beast", "spd": 0.0, "size": 2.0,
		"ranged": false, "model": "-", "hp": 1.0, "atk": 1.0, "boss_hp": 160000.0, "atk_pts": 14.0,
		"drop": "sandWormBossDrop", "draws": 16, "summon": true, "summon_cd": 600.0,
		"cols": [Color(0.8, 0.62, 0.38), Color(0.55, 0.38, 0.22), Color(1.0, 0.55, 0.2)]},
	"lingying": {"name": "凌影", "title": "尸傀密窟", "map": "lab", "kind": "boss", "boss": true, "shape": "beast", "spd": 6.0, "size": 4.0,
		"ranged": false, "model": "gel_mutant", "hp": 1.0, "atk": 1.0, "boss_hp": 80000.0, "atk_pts": 10.0,
		"night_name": "狂潮霸主·凌影", "night_hp_k": 1.9, "night_drop": "yanjiuBossDrops2",
		"drop": "yanjiuBossDrops1", "draws": 16, "respawn": 600.0,
		"cols": [Color(0.35, 0.85, 0.85), Color(0.2, 0.5, 0.55), Color(0.5, 1.0, 0.9)]},
	"dianbian": {"name": "电鞭铁卫", "title": "百炼坊", "map": "lab", "kind": "boss", "boss": true, "shape": "brute", "spd": 0.0, "size": 3.0,
		"ranged": true, "model": "mech_hunter", "hp": 1.0, "atk": 1.0, "boss_hp": 50000.0, "atk_pts": 10.0,
		"tint": Color(0.62, 0.78, 1.0), "drop": "yanjiuBossputong1", "draws": 16, "respawn": 500.0,
		"cols": [Color(0.3, 0.45, 0.7), Color(0.16, 0.22, 0.36), Color(0.45, 0.85, 1.0)]},
	"bingjiang": {"name": "冰僵铁卫", "title": "镇尸营", "map": "lab", "kind": "boss", "boss": true, "shape": "brute", "spd": 6.0, "size": 3.2,
		"ranged": false, "model": "stone_giant", "hp": 1.0, "atk": 1.0, "boss_hp": 50000.0, "atk_pts": 11.0,
		"tint": Color(0.72, 0.9, 1.0), "drop": "yanjiuBossputong2", "draws": 16, "respawn": 500.0,
		"cols": [Color(0.6, 0.78, 0.9), Color(0.32, 0.44, 0.55), Color(0.7, 0.95, 1.0)]},
	"duo_hunter": {"name": "铁穹猎杀卫", "title": "双子斗场", "map": "lab", "kind": "boss", "boss": true, "shape": "brute", "spd": 7.5, "size": 2.8,
		"ranged": false, "model": "mech_hunter", "hp": 1.0, "atk": 1.0, "boss_hp": 200000.0, "atk_pts": 10.0,
		"drop": "lvBuDiaoChanBossDrop", "draws": 48, "summon": true, "summon_cd": 600.0, "pair": "duo_welder",
		"cols": [Color(0.4, 0.5, 0.62), Color(0.2, 0.26, 0.34), Color(0.5, 0.8, 1.0)]},
	"duo_welder": {"name": "铁穹焊愈卫", "title": "双子斗场", "map": "lab", "kind": "boss", "boss": true, "shape": "brute", "spd": 6.0, "size": 2.6,
		"ranged": true, "model": "mech_welder", "hp": 1.0, "atk": 1.0, "boss_hp": 200000.0, "atk_pts": 9.0,
		"drop": "lvBuDiaoChanBossDrop", "draws": 48, "summon": true, "summon_cd": 600.0, "pair": "duo_hunter",
		"cols": [Color(0.42, 0.46, 0.38), Color(0.22, 0.24, 0.2), Color(0.6, 1.0, 0.5)]},
}

## 联机用的种类编号（net_mob_batch 的 def_idx）= 在这个表里的下标。只往后加，别插队 / 删项（新旧包混房会认错怪）
const IDS := ["scorpion", "wolf_sand", "sand_guard", "sand_raider", "zombie", "mech_claw", "mech_gunner", "gel_mutant", "wraith",
		"lingyou", "jiangluo", "sandworm", "lingying", "dianbian", "bingjiang", "duo_hunter", "duo_welder"]

## 每张图刷怪点的种类和权重（沙匪少一点；研究所的凝胶怪只当精英，见 roll_camp）
const CAMP_POOL := {
	"desert": [["scorpion", 3.0], ["wolf_sand", 3.0], ["sand_guard", 2.0], ["sand_raider", 1.5]],
	"lab": [["zombie", 4.0], ["mech_claw", 2.0], ["mech_gunner", 2.0]],
}
## 每张图的首领（召唤型的沙渊巨虫 / 铁穹双卫也在里面，用 is_summoned 区分；首领召唤出来的小怪不在）
const MAP_BOSSES := {
	"desert": ["lingyou", "jiangluo", "sandworm"],
	"lab": ["lingying", "dianbian", "bingjiang", "duo_hunter", "duo_welder"],
}


static func has(id: String) -> bool:
	return MOBS.has(id)


static func def(id: String) -> Dictionary:
	return MOBS.get(id, MOBS["scorpion"])


static func idx(id: String) -> int:
	return IDS.find(id)


static func by_idx(i: int) -> Dictionary:
	return MOBS[IDS[clampi(i, 0, IDS.size() - 1)]]


static func id_of(i: int) -> String:
	return String(IDS[clampi(i, 0, IDS.size() - 1)])


static func is_boss(id: String) -> bool:
	return bool(def(id).get("boss", false))


static func boss_name(id: String) -> String:
	return String(def(id)["name"])


## 名牌 / 播报用的全名：精英「精英·X」（或专门的精英名），首领「名 · 称号」
static func display_name(id: String, elite := false) -> String:
	var d := def(id)
	if bool(d.get("boss", false)):
		return String(d["name"])
	if elite or bool(d.get("elite_only", false)):
		return "精英·" + String(d.get("elite_name", d["name"]))
	return String(d["name"])


## 小怪 / 精英 / 召唤物的血量（点）。首领走 boss_hp
static func hp_of(id: String, elite := false) -> float:
	var d := def(id)
	if bool(d.get("boss", false)):
		return boss_hp(id, 1)
	if d.has("add_hp"):
		return float(d["add_hp"]) * BOSS_HP_K
	var base := HP_LAB if String(d.get("map", "")) == "lab" else HP_DESERT
	if bool(d.get("big", false)):
		base *= BRUTE_HP
	if elite or bool(d.get("elite_only", false)):
		base *= ELITE_HP
	return base


## 攻击（打在主角条上的点数，法衣减伤前）
static func atk_of(id: String, elite := false) -> float:
	var d := def(id)
	if d.has("atk_pts"):
		return float(d["atk_pts"])
	var base := ATK_LAB if String(d.get("map", "")) == "lab" else ATK_DESERT
	if elite or bool(d.get("elite_only", false)):
		base *= ELITE_ATK
	return base


## 首领人数系数：0.6 + 0.4·min(人数,4)/4（人数按战斗区里的真人算，至少 1）
static func players_k(players: int) -> float:
	return 0.6 + 0.4 * float(clampi(players, 1, 4)) / 4.0


## 首领血量（点）= DarkArea 血量 × 0.04 × 人数系数
static func boss_hp(id: String, players := 1) -> float:
	return float(def(id).get("boss_hp", 50000.0)) * BOSS_HP_K * players_k(players)


static func boss_drop(id: String) -> String:
	return String(def(id).get("drop", ""))


static func boss_draws(id: String) -> int:
	return int(def(id).get("draws", 16))


## 首领死后多久重生（秒）；召唤型返回召唤冷却
static func boss_respawn(id: String) -> float:
	var d := def(id)
	return float(d.get("respawn", d.get("summon_cd", 600.0)))


static func is_summoned(id: String) -> bool:
	return bool(def(id).get("summon", false))


## 召唤型首领能不能召唤：战斗区里的真人够数
static func can_summon(id: String, players_in_arena: int) -> bool:
	return is_summoned(id) and players_in_arena >= SUMMON_MIN


## 掉不掉东西（首领召唤的小怪不掉）
static func drops_loot(id: String) -> bool:
	return bool(def(id).get("loot", true))


## 给一只刚 new() 出来、还没进树的 raid_mob 填好新图的种类 / 数值 / 造型。进树（add_child）之前调。
## 首领的 hp 按 players（战斗区真人数）缩放；之后人数变了由 ex_boss.gd 自己按比例改。
## 不设 dmg_in / atk_out / floor_fn / block_fn / player / position / net_id —— 这些是管理器的事（见报告里的配方）
static func setup(m: Node3D, id: String, elite := false, players := 1) -> void:
	var d := def(id)
	var is_b := bool(d.get("boss", false))
	elite = (elite or bool(d.get("elite_only", false))) and not is_b
	m.set("def", d)
	m.set("elite", elite)
	m.set("lv", 1)
	m.set("region", 0)
	m.set("hp_max", boss_hp(id, players) if is_b else hp_of(id, elite))
	m.set("atk", atk_of(id, elite))
	m.set("xp_k", 0.0)
	if is_b or elite:
		m.set("tag_text", display_name(id, elite))
	m.set_meta("ex_id", id)
	m.set_meta("def_idx", idx(id))


## 一个刷怪点刷什么：[[id, elite], …]，3~5 只；一成多是「精英 + 两只随从」（研究所的精英一半是凝胶怪）
static func roll_camp(map_id: String, rng: RandomNumberGenerator) -> Array:
	var pool: Array = CAMP_POOL.get(map_id, CAMP_POOL["desert"])
	var out: Array = []
	if rng.randf() < CAMP_ELITE_P:
		var eid := _pick(pool, rng)
		if map_id == "lab" and rng.randf() < 0.5:
			eid = "gel_mutant"
		out.append([eid, true])
		var mate := _pick(pool, rng)
		out.append([mate, false])
		out.append([mate, false])
		return out
	var n := rng.randi_range(CAMP_MIN, CAMP_MAX)
	var main := _pick(pool, rng)
	for i in n:
		# 一个点大多是同一种（一群狼 / 一窝蝎），偶尔混一只别的
		out.append([main if rng.randf() < 0.75 else _pick(pool, rng), false])
	return out


static func _pick(pool: Array, rng: RandomNumberGenerator) -> String:
	var tot := 0.0
	for e: Array in pool:
		tot += float(e[1])
	var r := rng.randf() * tot
	for e: Array in pool:
		r -= float(e[1])
		if r <= 0.0:
			return String(e[0])
	return String((pool.back() as Array)[0])
