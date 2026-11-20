extends RefCounted
## 搜打撤的物品表和局外经济（2026-11-20 搜打撤三档改造）。纯数据 + 纯函数。
## 物品就是一个能直接存进 JSON 的字典：{kind, name, tier, value, ...}
##   gear 法宝：另有 fx（攻 atk / 守 guard / 识 seek / 养 vital）、amt（百分数）。只有「佩戴」的法宝生效（局外装上、或局内从背包里戴上），最多 3 件，死了全丢
##   pill 丹药：exp（修为）、heal（气血）。背包里点一下服用
##   key  破境丹：to（通往第几个大境界）。修为到了瓶颈，背包 / 储物戒里有对应的丹才能渡劫，渡劫时自动服下
##   herb 灵草：region。卖钱，或者在洞府丹房里炼丹
##   mat  妖兽灵材：region。笨重，占 2 格；卖钱或炼丹
##   tool 符箓：use = rune（破界符：原地起阵撤离）/ reveal（寻宝符：小地图标出附近的搜点）
## 价格单位是灵石（局外的钱，存在 raid_profile.gd）。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")

const KIND_NAMES := {"gear": "法宝", "pill": "丹药", "key": "破境丹", "herb": "灵草", "mat": "灵材", "tool": "符箓"}

# ---------- 法宝 ----------
const FX_NAMES := {"atk": "攻", "guard": "守", "seek": "识", "vital": "养"}
## 各品阶的数值（百分数）
const FX_AMT := {"atk": [6, 12, 20, 30, 45], "guard": [6, 11, 17, 24, 32], "seek": [25, 40, 60, 85, 120], "vital": [25, 40, 60, 85, 120]}
## [名字, 被动]：每个品阶四件，各管一种
const GEAR := [
	[["铁木剑", "atk"], ["青钢盾", "guard"], ["寻灵罗盘", "seek"], ["温玉佩", "vital"]],
	[["金蚨子母刃", "atk"], ["青蛟旗", "guard"], ["照妖镜", "seek"], ["神风舟", "vital"]],
	[["青竹蜂云剑", "atk"], ["玄龟甲", "guard"], ["天目灵珠", "seek"], ["风雷翅", "vital"]],
	[["血魔剑", "atk"], ["八灵尺", "guard"], ["虚天鼎残片", "seek"], ["养魂木", "vital"]],
	[["玄天斩灵剑", "atk"], ["元磁神山", "guard"], ["虚天鼎", "seek"], ["掌天瓶", "vital"]],
]

# ---------- 丹药 ----------
## [名字, 修为相当于第几级升级所需的一半, 气血]
const PILLS := [["黄龙丹", 2, 25], ["聚灵丹", 5, 25], ["养元丹", 9, 30], ["凝魂丹", 13, 30], ["培婴丹", 17, 35]]
const HEAL_PILL := "回春丹"      # 只回气血（60），坊市常年有卖
## 破境丹：下标 = 通往的境界（1 筑基 … 7 大乘）
const KEYS := ["", "筑基丹", "降尘丹", "定灵丹", "化神丹", "炼虚丹", "合体丹", "大乘丹"]

# ---------- 灵草 / 灵材（按区域）----------
const HERBS := ["百年灵参", "赤阳芝", "血灵花", "天山雪莲", "幽冥彼岸花"]
const HERB_MODELS := ["herb_ginseng", "herb_lingzhi", "herb_bloodflower", "herb_snowlotus", "herb_higan"]
const MATS := ["妖狼内丹", "枫木灵芯", "蛟血晶", "阴冥石", "古魔残骨"]

# ---------- 符箓 ----------
const TOOLS := {"rune": ["破界符", 1, 220], "reveal": ["寻宝符", 0, 70]}      # [名字, 品阶, 价值]


static func size_of(it: Dictionary) -> int:
	return 2 if str(it.get("kind", "")) == "mat" else 1


static func slots_used(list: Array) -> int:
	var n := 0
	for it: Dictionary in list:
		n += size_of(it)
	return n


static func tier_value(t: int) -> int:
	return int(Data.TIER_VALUE[clampi(t, 0, 4)])


# ---------- 造物品 ----------

static func gear(tier: int, idx: int, value := -1) -> Dictionary:
	var t := clampi(tier, 0, 4)
	var row: Array = GEAR[t][clampi(idx, 0, 3)]
	var fx := str(row[1])
	return {"kind": "gear", "name": str(row[0]), "tier": t, "fx": fx, "amt": int(FX_AMT[fx][t]),
			"value": value if value >= 0 else tier_value(t)}


static func rand_gear(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var t := clampi(tier, 0, 4)
	return gear(t, rng.randi() % 4, int(float(tier_value(t)) * rng.randf_range(0.8, 1.3)))


static func pill(tier: int) -> Dictionary:
	var t := clampi(tier, 0, 4)
	var p: Array = PILLS[t]
	return {"kind": "pill", "name": str(p[0]), "tier": t, "exp": Data.xp_need(int(p[1])) * 0.5, "heal": int(p[2]),
			"value": int(tier_value(t) * 0.4)}


static func heal_pill() -> Dictionary:
	return {"kind": "pill", "name": HEAL_PILL, "tier": 0, "exp": 0.0, "heal": 60, "value": 24}


static func key(to: int) -> Dictionary:
	var r := clampi(to, 1, KEYS.size() - 1)
	return {"kind": "key", "name": str(KEYS[r]), "tier": clampi(r - 1, 0, 4), "to": r, "value": int(160.0 * pow(2.1, float(r - 1)))}


static func herb(region: int) -> Dictionary:
	var r := clampi(region, 0, 4)
	return {"kind": "herb", "name": str(HERBS[r]), "tier": r, "region": r, "value": int(tier_value(r) * 0.35)}


static func mat(region: int) -> Dictionary:
	var r := clampi(region, 0, 4)
	return {"kind": "mat", "name": str(MATS[r]), "tier": r, "region": r, "value": int(tier_value(r) * 0.6)}


static func tool(use: String) -> Dictionary:
	var t: Array = TOOLS[use]
	return {"kind": "tool", "name": str(t[0]), "tier": int(t[1]), "use": use, "value": int(t[2])}


## 一次掉落：n 件。level = 区域序号（越深越好），bonus = 箱子 / 搜点的加成（也抬高出破境丹的机会）
static func roll(level: int, n: int, rng: RandomNumberGenerator, bonus := 0.0) -> Array:
	var out: Array = []
	var key_p := 0.035 + 0.03 * bonus
	for i in n:
		var k := rng.randf()
		if k < key_p:
			out.append(key(clampi(level + 1 + (1 if rng.randf() < 0.25 else 0), 1, KEYS.size() - 1)))
		elif k < key_p + 0.07:
			out.append(tool("rune" if rng.randf() < 0.35 else "reveal"))
		elif k < 0.34:
			out.append(heal_pill() if rng.randf() < 0.3 else pill(Data.roll_tier(level, rng, bonus)))
		elif k < 0.66:
			out.append(rand_gear(Data.roll_tier(level, rng, bonus), rng))
		elif k < 0.84:
			out.append(mat(level))
		else:
			out.append(herb(level))
	return out


# ---------- 法宝的被动 ----------

## 佩戴的法宝加起来：{atk, guard, seek, vital}，都是比例（0.2 = 20%）；同种叠加，守最多 60%
static func fx_total(gear_list: Array) -> Dictionary:
	var out := {"atk": 0.0, "guard": 0.0, "seek": 0.0, "vital": 0.0}
	for it: Dictionary in gear_list:
		var fx := str(it.get("fx", ""))
		if out.has(fx):
			out[fx] = float(out[fx]) + float(it.get("amt", 0)) / 100.0
	out["guard"] = minf(float(out["guard"]), 0.6)
	return out


static func fx_line(fx: String, amt: int) -> String:
	match fx:
		"atk":
			return "伤害 +%d%%" % amt
		"guard":
			return "受到的伤害 -%d%%" % amt
		"seek":
			return "搜索、开箱快 %d%%，小地图探得更远" % amt
		"vital":
			return "脱战回血、撤离读条快 %d%%" % amt
	return ""


## 一句话说明（背包 / 洞府里点中物品时显示）
static func desc(it: Dictionary) -> String:
	match str(it.get("kind", "")):
		"gear":
			return "佩戴：%s" % fx_line(str(it.get("fx", "")), int(it.get("amt", 0)))
		"pill":
			if float(it.get("exp", 0.0)) <= 0.0:
				return "服用：气血 +%d" % int(it.get("heal", 0))
			return "服用：修为 +%d、气血 +%d" % [int(it.get("exp", 0.0)), int(it.get("heal", 0))]
		"key":
			return "冲击%s期的雷劫必备；修为到瓶颈时自动服下" % Realm.LIST[int(it.get("to", 1))]["name"]
		"herb":
			return "灵草，洞府丹房炼丹用"
		"mat":
			return "妖兽灵材，炼丹用；笨重，占 2 格"
		"tool":
			if str(it.get("use", "")) == "rune":
				return "使用：原地起阵撤离（读条 14 秒，会暴露位置）"
			return "使用：小地图标出方圆 400 米的搜点"
	return ""


## 格子右下角那行小字
static func badge(it: Dictionary) -> String:
	match str(it.get("kind", "")):
		"gear":
			return "%s +%d%%" % [FX_NAMES.get(str(it.get("fx", "")), ""), int(it.get("amt", 0))]
		"pill":
			if float(it.get("exp", 0.0)) <= 0.0:
				return "气血 +%d" % int(it.get("heal", 0))
			return "修为 +%d" % int(it.get("exp", 0.0))
		"key":
			return "%s用" % Realm.LIST[int(it.get("to", 1))]["name"]
	return "%d 灵石" % int(it.get("value", 0))


## 图标名（assets/ui/icon_*.png）
static func icon_name(it: Dictionary) -> String:
	var k := str(it.get("kind", ""))
	if k == "gear":
		var fx := str(it.get("fx", "atk"))
		return "gear" if fx == "atk" else fx
	return k


# ---------- 局外：坊市 / 丹房 ----------

## 坊市的货：{item: 买到的物品, price: 灵石}
static func shop() -> Array:
	var out: Array = []
	out.append({"item": heal_pill(), "price": 60})
	out.append({"item": pill(0), "price": 120})
	out.append({"item": pill(1), "price": 380})
	out.append({"item": tool("reveal"), "price": 160})
	out.append({"item": tool("rune"), "price": 520})
	for i in 4:
		out.append({"item": gear(0, i, tier_value(0)), "price": 180})
	for i in 4:
		out.append({"item": gear(1, i, tier_value(1)), "price": 900})
	for r in range(1, 5):
		out.append({"item": key(r), "price": int(420.0 * pow(2.6, float(r - 1)))})
	return out


## 丹方：{out: 物品, herbs: {名字: 数量}, mats: {名字: 数量}, cost: 灵石}
static func recipes() -> Array:
	var out: Array = []
	out.append({"out": heal_pill(), "need": {HERBS[0]: 1}, "cost": 10})
	for t in 5:
		out.append({"out": pill(t), "need": {HERBS[t]: 1}, "cost": [20, 60, 160, 400, 900][t]})
	var plan := [[0, 2, 1, 60], [1, 2, 1, 200], [2, 2, 1, 600], [3, 2, 1, 1500], [4, 2, 1, 3500], [4, 3, 2, 7000], [4, 4, 3, 14000]]
	for r in range(1, KEYS.size()):
		var p: Array = plan[r - 1]
		var need := {}
		need[HERBS[int(p[0])]] = int(p[1])
		need[MATS[int(p[0])]] = int(p[2])
		out.append({"out": key(r), "need": need, "cost": int(p[3])})
	return out
