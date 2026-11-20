extends RefCounted
## 搜打撤的物品表和局外经济（2026-11-20 搜打撤三档改造）。纯数据 + 纯函数。
## 物品就是一个能直接存进 JSON 的字典：{kind, name, tier, value, ...}
##   gear 法宝：另有 fx（攻 atk / 守 guard / 识 seek / 养 vital）、amt（百分数）。只有「佩戴」的法宝生效（局外装上、或局内从背包里戴上），最多 3 件，死了全丢
##   pill 丹药：grade（品质 0 下品 … 3 极品）、exp（修为，只做显示 / 兼容：服丹一律按 pill_exp_now 现算）、heal（气血）。背包里点一下服用
##   key  破境丹：to（通往第几个大境界）。修为到了瓶颈 + 对应的破境丹 + 灵石（Prog.break_cost）才能渡劫，渡劫成功时服下
##   frag 破境丹残片：to。巢穴首领掉；Prog.FRAG_N 片 + 灵石在丹房合一颗破境丹（2026-11-20 数值框架）
##   herb 灵草：region。卖钱，或者在洞府丹房里炼丹
##   mat  妖兽灵材：region。笨重，占 2 格；卖钱或炼丹
##   tool 符箓：use = rune（破界符：原地起阵撤离）/ reveal（寻宝符：小地图标出附近的搜点）
## 价格单位是灵石（局外的钱，存在 raid_profile.gd）。
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
## 2026-11-20 数值框架：丹药药力 / 品质、破境丹概率、坊市、丹方的数都从这里取（progression.gd 只 preload raid_data.gd，不会成环）
const Prog := preload("res://scripts/progression.gd")

const KIND_NAMES := {"gear": "法宝", "pill": "丹药", "key": "破境丹", "frag": "破境残片", "herb": "灵草", "mat": "灵材", "tool": "符箓"}

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
## [名字, 旧的修为基准（2026-11-20 起不用了：药力看 Prog.pill_exp）, 气血]
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


## 2026-11-20 数值框架：修为丹分品质（下品 / 中品 / 上品 / 极品，名字里带上，下品也写）。
## 药力 exp = Prog.pill_exp(品阶, 品质)，只做显示 / 兼容；服丹按 pill_exp_now 现算。价值 = 品阶价值 × 0.4 × 品质倍数
static func pill(tier: int, grade := 0) -> Dictionary:
	var t := clampi(tier, 0, 4)
	var g := clampi(grade, 0, Prog.GRADE_NAMES.size() - 1)
	var p: Array = PILLS[t]
	return {"kind": "pill", "name": Prog.GRADE_NAMES[g] + str(p[0]), "tier": t, "grade": g, "exp": Prog.pill_exp(t, g), "heal": int(p[2]),
			"value": int(float(tier_value(t)) * 0.4 * Prog.GRADE_MULT[g])}


static func heal_pill() -> Dictionary:
	return {"kind": "pill", "name": HEAL_PILL, "tier": 0, "exp": 0.0, "heal": 60, "value": 24}


## 是不是修为丹（丹药里除了回春丹都是）。按名字判断：旧存档里的丹没有 grade，exp 也是旧曲线的数，不能拿 exp 判断
static func is_xp_pill(it: Dictionary) -> bool:
	return str(it.get("kind", "")) == "pill" and str(it.get("name", "")) != HEAL_PILL


## 界面上跟在名字后面的品阶字（凡品 / 灵器……）。2026-11-20 修：带品质的修为丹名字里已经有「上品」这类字，再写「凡品」像是自相矛盾，返回 ""
static func tier_word(it: Dictionary) -> String:
	if is_xp_pill(it) and it.has("grade"):
		return ""
	return str(Data.TIER_NAMES[clampi(int(it.get("tier", 0)), 0, Data.TIER_NAMES.size() - 1)])


## 这颗丹现在的药力（丹毒折算之前）：按品阶 / 品质现算；旧存档的丹没有 grade 当下品。不是修为丹返回 0
static func pill_exp_now(it: Dictionary) -> float:
	if not is_xp_pill(it):
		return 0.0
	return Prog.pill_exp(int(it.get("tier", 0)), int(it.get("grade", 0)))


static func key(to: int) -> Dictionary:
	var r := clampi(to, 1, KEYS.size() - 1)
	return {"kind": "key", "name": str(KEYS[r]), "tier": clampi(r - 1, 0, 4), "to": r, "value": int(160.0 * pow(2.1, float(r - 1)))}


## 破境丹残片（2026-11-20 数值框架）：巢穴首领的遗藏里必有一片；Prog.FRAG_N 片 + 灵石在丹房合一颗。占 1 格，价值 = 破境丹的四分之一
static func frag(to: int) -> Dictionary:
	var r := clampi(to, 1, KEYS.size() - 1)
	var kv := int(key(r)["value"])
	return {"kind": "frag", "name": str(KEYS[r]) + "残片", "tier": clampi(r - 1, 0, 4), "to": r, "value": int(float(kv) / 4.0)}


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
## 2026-11-20 数值框架（和模拟器 sim2.js 的 rollItems 一致）：
##   depth = 掉落处在区域里的深度（0 边缘 → 1 巢穴一带）：品阶运气 + depth × Prog.DEPTH_LUCK，修为丹品质 Prog.roll_grade(depth)
##   破境丹概率 Prog.KEY_P + Prog.KEY_PB × bonus，通往哪阶看 Prog.roll_key_to(区域, depth)
static func roll(level: int, n: int, rng: RandomNumberGenerator, bonus := 0.0, depth := 0.0) -> Array:
	var out: Array = []
	var ri := clampi(level, 0, 4)
	var dep := clampf(depth, 0.0, 1.0)
	var key_p := Prog.KEY_P + Prog.KEY_PB * bonus
	var luck := bonus + dep * Prog.DEPTH_LUCK
	for i in n:
		var k := rng.randf()
		if k < key_p:
			out.append(key(Prog.roll_key_to(ri, rng, dep)))
		elif k < key_p + 0.07:
			out.append(tool("rune" if rng.randf() < 0.35 else "reveal"))
		elif k < 0.34:
			if rng.randf() < 0.3:
				out.append(heal_pill())
			else:
				var t := Data.roll_tier(level, rng, luck)
				out.append(pill(t, Prog.roll_grade(dep, rng)))
		elif k < 0.66:
			out.append(rand_gear(Data.roll_tier(level, rng, luck), rng))
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
	out["atk"] = minf(float(out["atk"]), 0.8)      # 2026-11-20 夜：「攻」也封顶（+80%，见 combat_stats.gd 的 GEAR_ATK_CAP）
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
			if not is_xp_pill(it):
				return "服用：气血 +%d" % int(it.get("heal", 0))
			# 2026-11-20 数值框架：药力按品阶 / 品质现算；连服积丹毒，药效递减
			return "服用：修为 +%s、气血 +%d；连服会积丹毒，药效递减" % [Prog.short_num(pill_exp_now(it)), int(it.get("heal", 0))]
		"key":
			# 2026-11-20 数值框架：突破 = 修为到瓶颈 + 这颗丹 + 灵石；洞府修炼场或禁地里都能渡劫，成功才服下
			var to := clampi(int(it.get("to", 1)), 1, KEYS.size() - 1)
			return "冲击%s期必备：修为到瓶颈后再备 %s 灵石，在洞府修炼场（或禁地里）渡劫，成功才服下" % [Realm.LIST[to]["name"],
					Prog.short_num(float(Prog.break_cost(to)))]
		"frag":
			var fto := clampi(int(it.get("to", 1)), 1, KEYS.size() - 1)
			return "凑齐 %d 片，到洞府丹房加 %s 灵石合成一颗%s" % [Prog.FRAG_N, Prog.short_num(float(Prog.KEY_CRAFT_COST[fto])), str(KEYS[fto])]
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
			if not is_xp_pill(it):
				return "气血 +%d" % int(it.get("heal", 0))
			return "修为 +%s" % Prog.short_num(pill_exp_now(it))
		"key", "frag":
			return "%s用" % Realm.LIST[clampi(int(it.get("to", 1)), 1, KEYS.size() - 1)]["name"]
	return "%d 灵石" % int(it.get("value", 0))


## 图标名（assets/ui/icon_*.png）。丹药每种一张（2026-11-20 用户要求，不再共用一张）：
##   回春丹 pill_heal、五个品阶的修为丹 pill_0..4、七种破境丹 key_1..7（原图和加工见 _tasks/ui_kit/make_ui.py 的 PILL_ICONS）。
## 图不在的话 item_view.gd 会退回去用种类的通用图标（icon_pill / icon_key）
static func icon_name(it: Dictionary) -> String:
	var k := str(it.get("kind", ""))
	if k == "gear":
		var fx := str(it.get("fx", "atk"))
		return "gear" if fx == "atk" else fx
	if k == "pill":
		return "pill_%d" % clampi(int(it.get("tier", 0)), 0, PILLS.size() - 1) if is_xp_pill(it) else "pill_heal"
	# 破境丹残片沿用对应破境丹的图（2026-11-20 数值框架）
	if k == "key" or k == "frag":
		return "key_%d" % clampi(int(it.get("to", 1)), 1, KEYS.size() - 1)
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
	# 2026-11-20 数值框架：破境丹只卖 Prog.SHOP_KEY 里的（筑基丹、降尘丹，给新人解卡）；往上的只能在禁地里拿或用残片合。
	# 顺序固定（abode_ui 按下标取货）
	var ks: Array = Prog.SHOP_KEY.keys()
	ks.sort()
	for r: Variant in ks:
		out.append({"item": key(int(r)), "price": int(Prog.SHOP_KEY[r])})
	return out


## 丹方：{out: 物品, herbs: {名字: 数量}, mats: {名字: 数量}, cost: 灵石}
static func recipes() -> Array:
	var out: Array = []
	out.append({"out": heal_pill(), "need": {HERBS[0]: 1}, "cost": 10})
	# 修为丹：灵草 + 灵石，炼出来是下品（2026-11-20 数值框架）
	for t in 5:
		out.append({"out": pill(t, 0), "need": {HERBS[t]: 1}, "cost": [20, 60, 160, 400, 900][t]})
	# 破境丹：残片 × Prog.FRAG_N + 灵石 Prog.KEY_CRAFT_COST[to]（2026-11-20 数值框架；原来是灵草 + 灵材）。
	# Profile.count / craft 按名字找配料，残片的名字是「X丹残片」，和别的东西不重名
	for r in range(1, KEYS.size()):
		var need := {}
		need[str(frag(r)["name"])] = Prog.FRAG_N
		out.append({"out": key(r), "need": need, "cost": int(Prog.KEY_CRAFT_COST[r])})
	return out
