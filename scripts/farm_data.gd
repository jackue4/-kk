extends RefCounted
## 灵田种植（2026-11-23）：灵植表、数值、产出、丹方。纯数据 + 纯函数；灵田的场景 / 存档 / 界面在 farm_plots.gd。
## 和游戏玩法怎么接：
##   · 五味灵草（百年灵参 / 赤阳芝 / 血灵花 / 天山雪莲 / 幽冥彼岸花）种出来就是搜打撤里掉的那几样灵草（raid_items.gd 的 herb()），
##     进仓库 → 洞府丹房炼对应品阶的下品修为丹（灵参还能炼回春丹）→ 服丹涨修为；或者在仓库直接卖灵石
##   · 四种灵果（七彩灵莓 / 玉髓灵藕 / 炎阳灵瓜 / 冰魄灵果）是灵田独有的「辅药」：丹房里「灵草 + 对应灵果 + 灵石」炼出中品修为丹（药力是下品的两倍）
##   · 灵种按品阶分境界：高品阶的灵草要到对应境界才种得了（和修为丹的品阶、各区域的境界档对齐）；灵种拿灵石在田边直接买
##   · 生长按真实时间算，下线也照样长；品阶越高长得越久（几分钟到八小时）；灵田块数随境界开垦（一块灵田 4×4 = 16 格，一格种一株）
## 数值是第一版，要并进数值框架（_tasks/numbers_sim/life_sim.gd）里一起校准；这里的数都集中在 PLANTS / FIELD_REALM 几张表里。
## 故意不写 class_name：用 preload 引用。

const Items := preload("res://scripts/raid_items.gd")
const Data := preload("res://scripts/raid_data.gd")
const Prog := preload("res://scripts/progression.gd")

## 模型：plants/<名> = res://assets/plants/<名>.glb（_tasks/farm_plants/make_plants.py 生成）；creatures/<名> = 搜打撤掉落物用的那几株灵草
## stages：生长中的各段 [模型, 相对大小]；ripe：成熟可收的样子；size：成熟时最大边长（米，同一株的各段按它统一缩放；
##   2026-11-23 一块灵田改成 4×4 格、一格 2.4 米，成熟 2.35~3.0 米（用户嫌小，铺满一格、大的几样略探出格子）；生长中的各段另有最小尺寸，见 farm_plots.gd 的 MIN_SEEN）
## out：产出 —— "herb" = 同品阶的五味灵草，否则是灵果的名字；n：一次收几个（含两端）
const PLANTS := [
	{"id": "ginseng", "name": "百年灵参", "tier": 0, "realm": 0, "grow": 360.0, "price": 4, "out": "herb", "n": [1, 2], "size": 2.35,
	 "stages": [["plants/sprout_s0", 0.9], ["creatures/herb_ginseng", 0.6], ["creatures/herb_ginseng", 0.82]], "ripe": ["creatures/herb_ginseng", 1.0]},
	{"id": "berry", "name": "七彩灵莓", "tier": 0, "realm": 0, "grow": 720.0, "price": 6, "out": "七彩灵莓", "n": [1, 2], "size": 2.35,
	 "stages": [["plants/berry_s0", 1.0], ["plants/berry_s1", 1.0], ["plants/berry_s2", 1.0], ["plants/berry_s3", 1.0]], "ripe": ["plants/berry_ripe", 1.0]},
	{"id": "lingzhi", "name": "赤阳芝", "tier": 1, "realm": 1, "grow": 1200.0, "price": 16, "out": "herb", "n": [1, 2], "size": 2.45,
	 "stages": [["plants/sprout_s0", 0.9], ["creatures/herb_lingzhi", 0.6], ["creatures/herb_lingzhi", 0.82]], "ripe": ["creatures/herb_lingzhi", 1.0]},
	{"id": "bloodflower", "name": "血灵花", "tier": 2, "realm": 2, "grow": 3600.0, "price": 64, "out": "herb", "n": [1, 2], "size": 2.8,
	 "stages": [["plants/sprout_s0", 0.9], ["creatures/herb_bloodflower", 0.6], ["creatures/herb_bloodflower", 0.82]], "ripe": ["creatures/herb_bloodflower", 1.0]},
	{"id": "lotusroot", "name": "玉髓灵藕", "tier": 2, "realm": 2, "grow": 5400.0, "price": 80, "out": "玉髓灵藕", "n": [1, 2], "size": 2.7,
	 "stages": [["plants/lotusroot_s0", 1.0], ["plants/lotusroot_s1", 1.0], ["plants/lotusroot_s2", 1.0]], "ripe": ["plants/lotusroot_ripe", 1.0]},
	{"id": "snowlotus", "name": "天山雪莲", "tier": 3, "realm": 3, "grow": 10800.0, "price": 240, "out": "herb", "n": [1, 2], "size": 2.6,
	 "stages": [["plants/sprout_s0", 0.9], ["creatures/herb_snowlotus", 0.6], ["creatures/herb_snowlotus", 0.82]], "ripe": ["creatures/herb_snowlotus", 1.0]},
	{"id": "flamemelon", "name": "炎阳灵瓜", "tier": 3, "realm": 3, "grow": 14400.0, "price": 300, "out": "炎阳灵瓜", "n": [1, 1], "size": 2.8,
	 "stages": [["plants/flamemelon_s0", 1.0], ["plants/flamemelon_s1", 1.0], ["plants/flamemelon_s2", 1.0], ["plants/flamemelon_s3", 1.0]], "ripe": ["plants/flamemelon_ripe", 1.0]},
	{"id": "higan", "name": "幽冥彼岸花", "tier": 4, "realm": 4, "grow": 21600.0, "price": 1000, "out": "herb", "n": [1, 2], "size": 2.6,
	 "stages": [["plants/higanbud_s0", 0.75], ["creatures/herb_higan", 0.6], ["creatures/herb_higan", 0.82]], "ripe": ["creatures/herb_higan", 1.0]},
	{"id": "icefruit", "name": "冰魄灵果", "tier": 4, "realm": 4, "grow": 28800.0, "price": 1200, "out": "冰魄灵果", "n": [1, 1], "size": 3.0,
	 "stages": [["plants/icefruit_s0", 1.0], ["plants/icefruit_s1", 1.0], ["plants/icefruit_s2", 1.0], ["plants/icefruit_s3", 1.0]], "ripe": ["plants/icefruit_ripe", 1.0]},
]

## 各品阶修为丹的辅药（中品丹方用）：凡品、灵器两档都用七彩灵莓。下标 = 灵草的品阶（= 产地区域 0..4，Items.HERBS 同序）
const FRUIT_OF := ["七彩灵莓", "七彩灵莓", "玉髓灵藕", "炎阳灵瓜", "冰魄灵果"]
## 中品修为丹另收的灵石（2026-11-23 起不用了：改成按丹的境界，= 丹房下品价 Items.craft_cost × MID_COST_K）
const MID_COST := [40, 120, 320, 800, 1800]
const MID_COST_K := 2
## 一块灵田几行几列（2026-11-23 用户：「一块田地可以种 4*4 块植物」）
const GRID := 4
## 六块灵田各自要到的境界才开垦（炼气 1 块 16 格，筑基 2 块，结丹 3，元婴 4，化神 6 块 96 格）。原来是十二块单格的地（PLOT_REALM）
const FIELD_REALM := [0, 1, 2, 3, 4, 4]
const ICON_DIR := "res://assets/plants/icons/"
static var _icons := {}


static func plant(id: String) -> Dictionary:
	for p: Dictionary in PLANTS:
		if str(p["id"]) == id:
			return p
	return {}


## 选种背包、收获提示用的图标：成熟模型拍的透明底小图（_tasks/farm_plants/plant_icons.gd 拍、make_icons.py 加墨边）
static func icon(p: Dictionary) -> Texture2D:
	var id := str(p.get("id", ""))
	if not _icons.has(id):
		var path := ICON_DIR + id + ".png"
		_icons[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icons[id]


## 收到的东西叫这个名字的是哪种灵植（收获提示配图用）
static func plant_of_out(item_name: String) -> Dictionary:
	for p: Dictionary in PLANTS:
		if out_name(p) == item_name:
			return p
	return {}


## 灵果这件物品（kind 沿用 herb：仓库、坊市卖出、丹房按名字配料都不用改）
static func fruit(name: String) -> Dictionary:
	for p: Dictionary in PLANTS:
		if str(p["out"]) == name:
			var t := int(p["tier"])
			return {"kind": "herb", "name": name, "tier": t, "region": t, "value": int(float(Items.tier_value(t)) * 0.4), "fruit": true}
	return {}


## 收一次得到的物品（n 个）
static func harvest_items(p: Dictionary, rng: RandomNumberGenerator) -> Array:
	var n: Array = p["n"]
	var k := rng.randi_range(int(n[0]), int(n[1]))
	var out: Array = []
	for i in k:
		out.append(Items.herb(int(p["tier"])) if str(p["out"]) == "herb" else fruit(str(p["out"])))
	return out


## 产出叫什么（界面用）
static func out_name(p: Dictionary) -> String:
	return str(Items.HERBS[int(p["tier"])]) if str(p["out"]) == "herb" else str(p["out"])


## 第 t 味灵草（产地区域 t）现在炼出来的是哪个境界的修为丹（2026-11-23：和丹房同一张表 Prog.herb_pill_realm，按存档境界现算）
static func herb_realm(t: int, realm := -1) -> int:
	return Prog.herb_pill_realm(t, realm if realm >= 0 else Items.profile_realm())


## 这株种出来以后拿去干什么（选种界面上的一行说明）
## 2026-11-23：丹名按境界（第 t 味灵草炼的是 herb_realm(t) 那个境界的本境丹），不再拿 Items.PILLS 的下标对灵草的品阶
static func use_line(p: Dictionary) -> String:
	var t := clampi(int(p["tier"]), 0, Items.HERBS.size() - 1)
	var pr := Items.profile_realm()
	if str(p["out"]) == "herb":
		var s := "丹房炼%s" % Items.PILL_NAMES[herb_realm(t, pr)]
		if t == 0:
			s += "、回春丹"
		return s + "；可卖 %d 灵石" % int(Items.herb(t)["value"])
	var names: Array[String] = []
	for i in FRUIT_OF.size():
		if FRUIT_OF[i] == str(p["out"]):
			var nm := Items.PILL_NAMES[herb_realm(i, pr)]
			if not names.has(nm):
				names.append(nm)
	return "丹房辅药：配灵草炼中品%s（药力翻倍）；可卖 %d 灵石" % ["、".join(names), int(fruit(str(p["out"]))["value"])]


## 丹房里多出来的丹方（raid_items.gd 的 recipes() 末尾接上）：灵草 + 灵果 + 灵石 → 中品修为丹
## 2026-11-23：固定五味灵草各一条（不再按 Items.PILLS 的行数循环：它是 8 行，灵草 / 灵果只有 5 种）；
##   出的丹的境界 = herb_realm(t)（和丹房一样按存档境界现算），炼制费按丹的境界（丹房下品价 × MID_COST_K）
static func recipes() -> Array:
	var out: Array = []
	var pr := Items.profile_realm()
	for t in FRUIT_OF.size():
		var r := herb_realm(t, pr)
		var need := {}
		need[str(Items.HERBS[t])] = 1
		need[str(FRUIT_OF[t])] = 1
		out.append({"out": Items.rpill(r, 1), "need": need, "cost": Items.craft_cost(r) * MID_COST_K})
	return out


## 时长写成「5 分」「1 时 30 分」「8 时」
static func dur_text(secs: float) -> String:
	var s := maxi(int(ceilf(secs)), 0)
	if s < 60:
		return "%d 秒" % s
	var m := s / 60
	if m < 60:
		return "%d 分 %02d 秒" % [m, s % 60] if (m < 10 and s % 60 != 0) else "%d 分" % m
	var h := m / 60
	return ("%d 时" % h) if m % 60 == 0 else ("%d 时 %d 分" % [h, m % 60])
