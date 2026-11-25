extends SceneTree
## 一辈子的修为成长模拟（2026-11-20）：直接调游戏里的真代码——修为曲线 / 心得 / 打坐 / 突破价格（scripts/progression.gd）、
## 掉落表（raid_items.gd 的 roll / rpill / overlord / key / herb）、品阶运气（raid_data.gd 的 roll_tier）、搜点出货规则（照抄 raid_search.gd 的 _finish）。
## 杀怪速度、怪的种类比例、心得系数用 raid_pace_test.gd 在真实大世界里量出来的数（pace.json；没有就用下面 PACE_DEFAULT）。
## 跑法（headless，几秒到几十秒）：
##   godot --headless --path . -s res://_tasks/numbers_sim/life_sim.gd -- [--runs=60] [--prof=casual,normal,hardcore] [--pace=res://…json] [--json=res://…json]
##   --real：真人的杀怪速度是探针（无敌、不躲、直线飞过去一直打）的几成，默认 0.7
##   --o=ins:1.2,kb:8.4,kg:1.19,capn:480,pill:1.0,pillg:1.0,ovl:1.0,ovp:1.0,drop:0.2,med:1.0,medg:1.0,brk:1.0：试数用的倍率
##       kb / kg / capn / drop 是直接替换；ins（心得）/ pill（本境丹药力）/ pillg（本境丹药力每高一个境界再乘）/ ovl（霸主精魄掉率 OVERLORD_P）/
##       ovp（霸主精魄药力，即 OVERLORD_PCT）/ med / medg（打坐）/ brk（突破灵石）是乘数。试好了要写回 progression.gd / raid_manager.gd 再不带 --o 跑一遍确认
##       pdep：玩家画像的落脚深度偏好（画像的 depth − 普通的 0.35）乘几成加到深度上，夹在本境界那一档里（默认 0 = 照规格只按 REALM_MOB_LV；
##       改版前肝帝往深处走、休闲走得浅，心得 / 丹的品质差一截，三种人的差距主要来自这里）
## 打印每种玩家：到每个境界的「实际在玩的小时数」（局内 + 局间在洞府里）、第几天、第几局，修为来源占比，各境界卡在哪。
## 2026-11-23 数值重构（对标 Hammer，规格 numbers_spec.md v2 的 J 节）：
##   · 杀怪速度按境界读：pace 文件里有 "by": "realm" 的行（raid_pace_test.gd 的 --pace-byrealm 量的）就按（境界, 境内第几级）取，否则照旧按区域（老文件）；
##     按境界的行，心得系数用实测的每只心得 ÷ 本境界常打的怪一只的心得（含打到低一档怪的折扣）
##   · 每个境界去 Prog.REALM_REGION 的区域、打 Prog.REALM_MOB_LV 那一档的怪：深度按它反推（± 0.06），怪的境界档必须 = 自己的境界
##   · 心得直接调 Prog.insight（带区域；kb / kg 覆盖按比例乘上去）；巢穴 / 游荡首领只在打得动（Prog.lair_tag ≤ 境界）时算
##   · 修为丹是字典列表（本境丹 realm / 霸主精魄 min_realm / 品质 / 卖价），服丹按 Prog.pill_use_err 过滤，从大到小吃；溢出存满了就不再吃（不扣丹）
##   · 没有丹毒、打坐服丹不加成；到瓶颈照收修为（溢出），渡劫成功按 Prog.carry_over 结转、失败扣一半需求（不低于 0）
##   · 巢穴首领遗藏按 Prog.OVERLORD_P[档] 多掉一颗霸主精魄；遗藏里的丹按首领自己的档出（Items.roll 的 pill_realm），搜点按点的位置出
##   · 修为来源占比按「改版前的单位」（÷ Prog.XP_SCALE[境界]）合计，和老基线（心得 36% / 丹 44% / 打坐 + 离线 20%）可比

const Prog := preload("res://scripts/progression.gd")
const Items := preload("res://scripts/raid_items.gd")
const Data := preload("res://scripts/raid_data.gd")
const RM := preload("res://scripts/raid_manager.gd")
const PILL_PREF := 3.0      # 挑背包时修为丹（现在或以后能服的）按卖价的几倍算（真人更想要修为丹）

const NAMES := ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"]
const SITE_KINDS := ["jar", "herb", "grave", "vault"]
const SITE := {"jar": [1, 2, 0.0], "herb": [2, 3, 0.0], "grave": [2, 3, 0.5], "vault": [4, 5, 1.4], "urn": [3, 4, 1.0]}
const COUNTS := [[9, 6, 3, 1], [4, 6, 5, 3], [4, 6, 5, 3], [4, 6, 5, 3], [4, 6, 5, 3]]
const BAG := 12
const TRIB_OK := 0.85
const DEPTH_JITTER := 0.06  # 每局落脚的深度在「常打的怪那一档」上下浮动多少
## 量不到时的兜底（2026-11-20 第一次量之前的假设，和 sim2.js 一样：每分钟 4 只、一成精英）
const PACE_DEFAULT := {"kpm": 4.0, "elite_frac": 0.08, "boss_pm": 0.15, "avg_k": 1.6}

## 玩家画像：每天几局、一局几分钟、局间在洞府待几分钟（打坐 + 服丹）、陨落率、一局搜几个点、打掉巢穴的几率、游荡首领打得过的几率、杀怪快慢
## （depth 是落脚深度的偏好：2026-11-23 起深度按 REALM_MOB_LV 反推，只有 --o=pdep:N 时才把「画像 depth − 0.35」× N 加上去、夹在本境界那一档里，见 _raid）
const PROFILES := {
	"casual": {"name": "休闲（每天 2 局）", "per_day": 2, "raid_min": 12.0, "hub_min": 2.0, "death": 0.25, "sites": 5, "lair": 0.15, "depth": 0.2, "boss": 0.5, "kill_k": 0.8},
	"normal": {"name": "普通（每天 4 局）", "per_day": 4, "raid_min": 14.0, "hub_min": 2.0, "death": 0.15, "sites": 7, "lair": 0.35, "depth": 0.35, "boss": 0.7, "kill_k": 1.0},
	"hardcore": {"name": "肝帝（每天 12 局）", "per_day": 12, "raid_min": 18.0, "hub_min": 1.5, "death": 0.1, "sites": 9, "lair": 0.6, "depth": 0.5, "boss": 0.9, "kill_k": 1.15},
}

var pace: Array = []            # 按区域（老文件、兜底）
var pace_realm := {}            # 境界 -> {境内第几级 1..3: 行}（"by": "realm" 的行）
var rng := RandomNumberGenerator.new()
var kpm_k := 0.7
var json_out := {}
var O := {"ins": 1.0, "kb": -1.0, "kg": -1.0, "capn": -1.0, "pill": 1.0, "pillg": 1.0, "ovl": 1.0, "ovp": 1.0, "drop": -1.0, "med": 1.0, "medg": 1.0, "brk": 1.0, "pdep": 1.0}
var _band_cache := {}           # 境界 -> [深度下限, 上限]：在这段深度里当地怪正好是本境界那一档
var _tag_warned := false


func _init() -> void:
	var runs := 60
	var profs: Array = ["casual", "normal", "hardcore"]
	var pace_path := "res://_tasks/numbers_sim/pace.json"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.get_slice("=", 1))
		elif a.begins_with("--prof="):
			profs = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--real="):
			kpm_k = float(a.get_slice("=", 1))
		elif a.begins_with("--o="):
			for kv: String in a.get_slice("=", 1).split(","):
				O[kv.get_slice(":", 0)] = float(kv.get_slice(":", 1))
		elif a.begins_with("--pace="):
			pace_path = a.get_slice("=", 1)
		elif a.begins_with("--json="):
			json_out["_path"] = a.get_slice("=", 1)
	_load_pace(pace_path)
	if float(O["kb"]) < 0.0:
		O["kb"] = Prog.KILL_BASE
	if float(O["kg"]) < 0.0:
		O["kg"] = Prog.KILL_G
	if float(O["capn"]) < 0.0:
		O["capn"] = Prog.KILL_CAP_N
	if float(O["drop"]) < 0.0:
		O["drop"] = RM.KILL_DROP
	print("[life] 真人杀怪 = 探针的 %d%%；试数倍率 %s" % [roundi(kpm_k * 100.0), str(O)])
	for i in 5:
		var pc: Dictionary = pace[i]
		print("[life] 杀怪输入 %s：每分钟 %.1f 只，精英 %d%%，首领 %.2f 只/分，心得系数 %.2f%s" % [Data.REGIONS[i]["name"], float(pc["kpm"]), roundi(100.0 * float(pc["elite_frac"])),
				float(pc["boss_pm"]), float(pc["avg_k"]), "（实测）" if bool(pc.get("measured", false)) else "（假设）"])
	var rks: Array = pace_realm.keys()
	rks.sort()
	for r: Variant in rks:
		var rows: Dictionary = pace_realm[r]
		var cells: Array = []
		var js: Array = rows.keys()
		js.sort()
		for j: Variant in js:
			var pc2: Dictionary = rows[j]
			cells.append("第 %d 级 %.1f 只/分（精英 %d%%、心得系数 %.2f、%.1f 下一只）" % [int(j), float(pc2["kpm"]), roundi(100.0 * float(pc2["elite_frac"])), float(pc2["avg_k"]), float(pc2.get("hpk", 0.0))])
		print("[life] 杀怪输入（按境界）%s：%s" % [NAMES[int(r)], "；".join(cells)])
	for r in 7:
		var ri: int = Prog.REALM_REGION[r]
		print("[life] %s：去%s、深度 %.3f（%d 级怪，%s档），巢穴首领 %d 级（%s档）" % [NAMES[r], Data.REGIONS[ri]["name"], _realm_depth(r), Prog.REALM_MOB_LV[r],
				NAMES[Prog.mob_tag(ri, Prog.REALM_MOB_LV[r])], _lair_lv(ri), NAMES[Prog.lair_tag(ri)]])
	print("[life] 修为曲线：各境界总修为 " + " / ".join(range(8).map(func(r: int) -> String: return "%s %s" % [NAMES[r], Prog.short_num(Prog.realm_total(r))])))
	json_out["profiles"] = {}
	json_out["real"] = kpm_k
	json_out["runs"] = runs
	json_out["pace"] = pace
	json_out["pace_realm"] = pace_realm
	json_out["realm_total"] = range(8).map(func(r: int) -> float: return Prog.realm_total(r))
	# PILL_EXP 留着（pace.html 读它 .join()）：2026-11-23 起丹按境界，真正用的是 PILL_BASE × XP_SCALE × 品质
	json_out["params"] = {"KILL_BASE": Prog.KILL_BASE, "KILL_G": Prog.KILL_G, "KILL_CAP_N": Prog.KILL_CAP_N, "PILL_EXP": Prog.PILL_EXP, "MED_RATE": Prog.MED_RATE,
			"BREAK_COST": Prog.BREAK_COST, "KILL_DROP": RM.KILL_DROP, "MOB_CAP": RM.MOB_CAP, "MOB_CAP_MOBILE": RM.MOB_CAP_MOBILE, "O": O,
			"PILL_BASE": Prog.PILL_BASE, "XP_SCALE": Prog.XP_SCALE, "OVERLORD_P": Prog.OVERLORD_P, "OVERLORD_PCT": Prog.OVERLORD_PCT, "REALM_MOB_LV": Prog.REALM_MOB_LV}
	for pk: String in profs:
		_report(pk, runs)
	if json_out.has("_path"):
		var path := str(json_out["_path"])
		json_out.erase("_path")
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(json_out, " "))
		f.close()
		print("[life] 写出 " + path)
	quit()


## pace 文件的一行 → 模拟要用的几个数
func _pace_row(o: Dictionary) -> Dictionary:
	var kills := float(o["mob"]) + float(o["elite"]) + float(o["boss"])
	var mins := maxf(float(o["minutes"]), 0.01)
	var kpm := float(o["kpm"])
	# 每只的平均经验系数：新探针直接记了 avg_k；老的只有每分钟心得，按当时的公式（16.5 × 1.14^(等级-1)）反推
	var unit := 16.5 * pow(1.14, float(int(o.get("mob_lv", 1)) - 1))
	var typed := kills > 0.0      # 第一版探针没记下种类：精英 / 首领比例用兜底
	return {"kpm": kpm, "elite_frac": float(o["elite"]) / maxf(kills, 1.0) if typed else float(PACE_DEFAULT["elite_frac"]),
			# 游荡首领：探针把它排在小怪后面、一个区域只跑几分钟，基本碰不到；按导演 240 ~ 360 秒一只算
			"boss_pm": maxf(float(o["boss"]) / mins, float(PACE_DEFAULT["boss_pm"])),
			"avg_k": float(o["avg_k"]) if o.has("avg_k") else float(o.get("insight_pm", 0.0)) / maxf(kpm, 0.01) / unit,
			"hpk": float(o.get("hits_per_kill", 0.0)), "measured": true}


func _load_pace(path: String) -> void:
	pace = []
	pace_realm = {}
	for i in 5:
		var d := PACE_DEFAULT.duplicate()
		d["measured"] = false
		pace.append(d)
	if not FileAccess.file_exists(path):
		return
	var txt := FileAccess.get_file_as_string(path)
	var arr: Variant = JSON.parse_string(txt)
	if not (arr is Array):
		return
	for o: Variant in arr:
		if not (o is Dictionary):
			continue
		var od: Dictionary = o
		if str(od.get("by", "")) == "realm":
			# 2026-11-23：--pace-byrealm 的行：按（境界, 境内第几级）存。老文件里也有 realm 字段（那是区域的入门境界），不按它分
			var r := clampi(int(od["realm"]), 0, 7)
			var j := clampi(int(od["lv"]) - r * Prog.LV_PER_REALM, 1, Prog.LV_PER_REALM)
			if not pace_realm.has(r):
				pace_realm[r] = {}
			var row := _pace_row(od)
			# 心得系数按实测的每只心得反推（÷ 本境界常打的怪一只的心得）：探针 200 米内也会打到低一档的怪（草原筑基），按经验系数平均会多算
			if od.has("insight_pm") and float(od["kpm"]) > 0.0:
				row["avg_k_raw"] = row["avg_k"]
				# 实测的每分钟心得是按「量的时候的 KILL_BASE」算的（探针记在 kill_base 里；没记的是 8.4）：换算到现在的 KILL_BASE，免得调 KILL_BASE 被反推抵消掉
				var kb_meas := float(od.get("kill_base", 8.4))
				row["avg_k"] = float(od["insight_pm"]) * (Prog.KILL_BASE / kb_meas) / float(od["kpm"]) / Prog.insight(Prog.REALM_MOB_LV[r], 1.0, Prog.REALM_REGION[r])
			(pace_realm[r] as Dictionary)[j] = row
		else:
			pace[clampi(int(od["region"]), 0, 4)] = _pace_row(od)


## 这一局的杀怪输入：有按境界量的就按（境界, 境内第几级）取（没量那一级就取最近的一级），否则按区域
func _pace_for(realm: int, lv: int) -> Dictionary:
	if pace_realm.has(realm):
		var rows: Dictionary = pace_realm[realm]
		var j := clampi(lv - realm * Prog.LV_PER_REALM, 1, Prog.LV_PER_REALM)
		if rows.has(j):
			return rows[j]
		var best := -1
		var bd := 99
		for k: Variant in rows.keys():
			if absi(int(k) - j) < bd:
				bd = absi(int(k) - j)
				best = int(k)
		return rows[best]
	return pace[Prog.REALM_REGION[clampi(realm, 0, 7)]]


## 境界 r 常打的怪所在的深度（Prog.REALM_MOB_LV 反推；同 raid_pace_test.gd 的 --pace-byrealm）
func _realm_depth(r: int) -> float:
	var ri: int = Prog.REALM_REGION[r]
	return clampf(float(Prog.REALM_MOB_LV[r] - int(Data.REGIONS[ri]["lv"])) / float(Prog.DEPTH_LV[ri]), 0.0, 1.0)


## 区域 ri 的巢穴：[深度, 首领等级]（真实巢穴位置的当地等级 + 2，再夹进巢穴的境界档 Prog.lair_tag）
func _lair(ri: int) -> Array:
	for p: Dictionary in Data.pois():
		if str(p["kind"]) == "boss" and int(p["region"]) == ri:
			var pos: Vector2 = p["pos"]
			var dep := Prog.depth_at(ri, pos.x, pos.y)
			return [dep, Prog.boss_level(Prog.lair_tag(ri), Prog.mob_level(ri, dep) + 2)]
	return [1.0, Prog.boss_level(Prog.lair_tag(ri), Prog.mob_level(ri, 1.0) + 2)]


## 境界 r 在它的区域里「当地怪正好是本境界那一档」的深度范围（按 0.005 一格扫）
func _tag_band(r: int) -> Array:
	if _band_cache.has(r):
		return _band_cache[r]
	var ri: int = Prog.REALM_REGION[r]
	var lo := 2.0
	var hi := -1.0
	for i in 201:
		var d := float(i) * 0.005
		if Prog.mob_tag(ri, Prog.mob_level(ri, d)) == r:
			lo = minf(lo, d)
			hi = maxf(hi, d)
	var out: Array = [lo, hi] if hi >= 0.0 else [0.0, 1.0]
	_band_cache[r] = out
	return out


func _lair_lv(ri: int) -> int:
	return int(_lair(ri)[1])


# ---------- 一个玩家 ----------

func _new_state() -> Dictionary:
	var z8 := func() -> Array: return [0, 0, 0, 0, 0, 0, 0, 0]
	var f8 := func() -> Array: return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	return {"realm": 0, "lv": 1, "xp": 0.0, "ls": 300.0, "pills": [], "keys": [], "frags": {}, "raids": 0, "act_s": 0.0, "day": 1,
			"src": {"kill": 0.0, "pill": 0.0, "med": 0.0, "off": 0.0}, "waste": {"cap": 0.0, "bottle": 0.0}, "at": {0: [0.0, 0, 1]},
			"stuck_key": z8.call(), "stuck_ls": z8.call(), "raids_in": z8.call(), "fails_in": z8.call(),
			"hours_in": f8.call(), "ls_in": f8.call(), "carry_in": f8.call(),
			"by": [{}, {}, {}, {}, {}, {}, {}, {}], "items_in": z8.call(), "kills_in": z8.call(),
			"eat_in": z8.call(), "ovl_in": z8.call(), "lair_in": z8.call(), "dead_sold_in": f8.call()}


## 修为 +v（按 Prog.add_xp：小级满了自动升，到瓶颈照收到溢出上限）。返回实际用上的。
## 来源合计按改版前的单位（÷ XP_SCALE[境界]）记，各境界的分项（by）按本境界单位记
func _add(S: Dictionary, v: float, tag: String) -> float:
	if v <= 0.0:
		return 0.0
	var realm := int(S["realm"])
	var res := Prog.add_xp(int(S["lv"]), float(S["xp"]), realm, v)
	S["lv"] = int(res[0])
	S["xp"] = float(res[1])
	var used := float(res[2])
	var k := 1.0 / Prog.XP_SCALE[realm]
	S["src"][tag] = float(S["src"][tag]) + used * k
	var by: Dictionary = S["by"][realm]
	by[tag] = float(by.get(tag, 0.0)) + used
	S["waste"]["bottle"] = float(S["waste"]["bottle"]) + (v - used) * k
	return used


func _cap(S: Dictionary) -> bool:
	return Prog.at_cap(int(S["lv"]), float(S["xp"]), int(S["realm"]))


## 溢出存满了（瓶颈那一级 + 一整个下一境界，见 Prog.overflow_cap）：再服丹也加不上，游戏里不扣丹
func _full(S: Dictionary) -> bool:
	var realm := int(S["realm"])
	return realm < 7 and int(S["lv"]) >= Prog.top_lv(realm) and float(S["xp"]) >= Prog.overflow_cap(realm) - 0.01


func _poisson(lam: float) -> int:
	var l := exp(-lam)
	var k := -1
	var p := 1.0
	while p > l:
		p *= rng.randf()
		k += 1
	return k


## 价值 × 掉落处深度的 Prog.value_mult（同 raid_manager._loot / site_loot）
func _vm(items: Array, depth: float) -> Array:
	var k := Prog.value_mult(depth)
	for it: Dictionary in items:
		it["value"] = int(roundf(float(it["value"]) * k))
	return items


## 搜点出货（照抄 raid_search.gd 的 _finish：修为丹的境界看这个点的区域、深度）
func _site_items(kind: String, ri: int, depth: float) -> Array:
	var info: Array = SITE[kind]
	var n := rng.randi_range(int(info[0]), int(info[1]))
	var pr := Prog.pill_realm_at(ri, depth)
	var items: Array = []
	match kind:
		"herb":
			for i in n:
				items.append(Items.herb(ri if rng.randf() > 0.12 or ri >= 4 else ri + 1))
			if rng.randf() < 0.2:
				items.append(Items.rpill(pr, Prog.roll_grade(depth, rng)))
		"vault":
			items = Items.roll(ri, n, rng, float(info[2]), depth, pr)
			if rng.randf() < Prog.VAULT_KEY:
				items.append(Items.key(Prog.roll_key_to(ri, rng, depth)))
		_:
			items = Items.roll(ri, n, rng, float(info[2]), depth, pr)
	return _vm(items, depth)


func _is_xp(it: Dictionary) -> bool:
	return str(it["kind"]) == "pill" and Items.is_xp_pill(it)


## 这颗修为丹现在或以后还能服（霸主精魄一直能；本境丹要境界 ≤ 丹的境界）
func _future(it: Dictionary, realm: int) -> bool:
	if it.has("min_realm"):
		return true
	return int(it.get("realm", realm)) >= realm


## 这颗丹在境界 realm 服下的药力（--o 的 pill / pillg / ovp 乘上去）
func _pexp(it: Dictionary, realm: int) -> float:
	var e := Items.pill_exp_now(it, realm)
	if it.has("min_realm"):
		return e * float(O["ovp"])
	return e * float(O["pill"]) * pow(float(O["pillg"]), float(int(it.get("realm", realm))))


func _raid(S: Dictionary, P: Dictionary) -> void:
	var realm := int(S["realm"])
	var ri: int = Prog.REALM_REGION[realm]
	var band := _tag_band(realm)
	var d0 := clampf(_realm_depth(realm) + (float(P["depth"]) - 0.35) * float(O["pdep"]), float(band[0]), float(band[1]))
	var depth := clampf(d0 + (rng.randf() - 0.5) * 2.0 * DEPTH_JITTER, float(band[0]), float(band[1]))
	var mob_lv := Prog.mob_level(ri, depth)
	var tag := Prog.mob_tag(ri, mob_lv)
	if tag != realm and not _tag_warned:
		_tag_warned = true
		push_error("[life] %s在%s深度 %.3f 打的是 %d 级、%s档的怪（应是本境界那一档）" % [NAMES[realm], Data.REGIONS[ri]["name"], depth, mob_lv, NAMES[tag]])
	var can_boss := Prog.lair_tag(ri) <= realm      # 巢穴 / 游荡首领打得动（REALM_REGION 下一直成立；留着防区域表改了）
	var dies := rng.randf() < float(P["death"])
	var T := float(P["raid_min"])
	if dies:
		T = 2.0 + rng.randf() * (T - 2.0)
	var pc := _pace_for(realm, int(S["lv"]))
	var items: Array = []
	var kills := _poisson(float(pc["kpm"]) * float(P["kill_k"]) * kpm_k * T)
	var elites := 0
	for i in kills:
		if rng.randf() < float(pc["elite_frac"]):
			elites += 1
	var unit := _ins(mob_lv, 1.0, ri)
	var ins := float(kills) * float(pc["avg_k"]) * unit * float(O["ins"])
	S["kills_in"][realm] = int(S["kills_in"][realm]) + kills
	# 怪掉的东西：丹按怪自己的档出（= 本境界）
	for i in kills - elites:
		if rng.randf() < float(O["drop"]):
			items.append_array(_vm(Items.roll(ri, 1, rng, 0.0, depth, tag), depth))
	for i in elites:
		items.append_array(_vm(Items.roll(ri, 2, rng, 0.5, depth, tag), depth))
	if can_boss:
		for i in _poisson(float(pc["boss_pm"]) * T):
			if rng.randf() < float(P["boss"]):
				# 游荡首领：当地等级 + 1 夹进当地的档（规格 v2 A），档 = 当地怪的档
				items.append_array(_vm(Items.roll(ri, 3, rng, 0.8, depth, tag), depth))
	if can_boss and T > 6.0 and rng.randf() < float(P["lair"]):
		var lt := Prog.lair_tag(ri)
		var la := _lair(ri)
		var ldep := float(la[0])
		ins += _ins(int(la[1]), 14.0, ri) * float(O["ins"])
		S["lair_in"][realm] = int(S["lair_in"][realm]) + 1
		items.append_array(_vm(Items.roll(ri, 5, rng, 1.3, ldep, lt), ldep))
		items.append(Items.frag(Prog.frag_to(ri)))
		if rng.randf() < Prog.OVERLORD_P[lt] * float(O["ovl"]):
			items.append(_vm([Items.overlord(lt)], ldep)[0])
		items.append_array(_vm(Items.roll(ri, 3, rng, 1.0, ldep), ldep))      # 巢穴边上的宗门宝罐（搜点：丹按那里的位置 Prog.pill_realm_at 出）
	var cw: Array = COUNTS[ri]
	var csum := 0.0
	for c: int in cw:
		csum += float(c)
	for i in roundi(float(P["sites"]) * T / float(P["raid_min"])):
		var x := rng.randf() * csum
		var kind := "jar"
		for k in 4:
			x -= float(cw[k])
			if x <= 0.0:
				kind = SITE_KINDS[k]
				break
		items.append_array(_site_items(kind, ri, depth))
	var cap := _ins(Prog.REALM_MOB_LV[realm], 1.0, ri) * float(O["capn"])
	S["items_in"][realm] = int(S["items_in"][realm]) + items.size()
	if ins > cap:
		S["waste"]["cap"] = float(S["waste"]["cap"]) + (ins - cap) / Prog.XP_SCALE[realm]
		ins = cap
	S["raids"] = int(S["raids"]) + 1
	S["raids_in"][realm] = int(S["raids_in"][realm]) + 1
	S["act_s"] = float(S["act_s"]) + T * 60.0
	S["hours_in"][realm] = float(S["hours_in"][realm]) + T / 60.0
	if dies:
		# 储物戒保住一件：有破境丹就保它（其余都丢）
		for it: Dictionary in items:
			if str(it["kind"]) == "key" and int(it["to"]) > realm:
				S["keys"].append(int(it["to"]))
				return
		return
	_add(S, ins, "kill")
	# 背包 12 格：破境丹、残片不占（直接记上），其余按每格值多少挑（现在或以后能服的修为丹按卖价 × PILL_PREF），和游戏里背包满了「以贵换贱」一个思路
	var all: Array = []
	for it: Dictionary in items:
		var kd := str(it["kind"])
		if _is_xp(it):
			S["xp_seen"] = int(S.get("xp_seen", 0)) + 1      # 统计用（raid_pills.gd）：这局掉了几颗修为丹（进背包挑选之前）
		if kd == "key":
			if int(it["to"]) > realm:
				S["keys"].append(int(it["to"]))
		elif kd == "frag":
			var to := int(it["to"])
			S["frags"][to] = int(S["frags"].get(to, 0)) + 1
		else:
			all.append(it)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _worth(a, realm) > _worth(b, realm))
	var used := 0
	for it: Dictionary in all:
		var s := Items.size_of(it)
		if used + s > BAG:
			continue
		used += s
		if _is_xp(it) and _future(it, realm):
			S["pills"].append(it)
		else:
			var v := float(it["value"])      # 其余（含锁在更低境界、再也服不了的丹）回去卖掉
			S["ls"] = float(S["ls"]) + v
			S["ls_in"][realm] = float(S["ls_in"][realm]) + v


## 心得：直接调 Prog.insight（带区域），--o 的 kb / kg 按比例乘上去
func _ins(lv: int, k: float, ri: int) -> float:
	var l := clampi(lv, 1, Prog.MAX_LV)
	var ratio := float(O["kb"]) / Prog.KILL_BASE * pow(float(O["kg"]) / Prog.KILL_G, float(l - 1))
	return Prog.insight(l, k, ri) * ratio


func _worth(it: Dictionary, realm: int) -> float:
	var v := float(it["value"])
	if _is_xp(it) and _future(it, realm):
		v *= PILL_PREF
	return v / float(Items.size_of(it))


func _med(realm: int) -> float:
	return Prog.med_rate(realm) * float(O["med"]) * pow(float(O["medg"]), float(realm))


## 局间在洞府：一键服丹（2026-11-23 照 Hammer：没有丹毒、打坐服丹不加成），打坐剩下的时间按打坐速度涨修为；能突破就突破
func _hub(S: Dictionary, _P: Dictionary, secs: float) -> void:
	S["act_s"] = float(S["act_s"]) + secs
	S["hours_in"][int(S["realm"])] = float(S["hours_in"][int(S["realm"])]) + secs / 3600.0
	_sell_for_break(S)
	_eat(S)
	_add(S, _med(int(S["realm"])) * secs, "med")
	_break(S)
	_eat(S)


## 一键服丹：仓库里所有能服的修为丹（Prog.pill_use_err）从大到小一摞吃完；瓶颈时照样吃（溢出结转），溢出存满了就停（不扣丹）
func _eat(S: Dictionary) -> void:
	var realm := int(S["realm"])
	var pills: Array = S["pills"]
	pills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _pexp(a, realm) > _pexp(b, realm))
	var left: Array = []
	for it: Dictionary in pills:
		if Prog.pill_use_err(it, realm) != "" or _full(S):
			left.append(it)
			continue
		S["pill_exp_now"] = float(S.get("pill_exp_now", 0.0)) + _pexp(it, realm)      # 统计用（raid_pills.gd）
		_add(S, _pexp(it, realm), "pill")
		S["eat_in"][realm] = int(S["eat_in"][realm]) + 1
		if it.has("min_realm"):
			S["ovl_in"][realm] = int(S["ovl_in"][realm]) + 1
	S["pills"] = left


## 2026-11-23：卡在瓶颈、灵石又不够布阵的时候，真人会先卖几颗丹凑灵石再把剩下的吃掉（改版前丹在瓶颈吃不下、留着卖，现在溢出照收，
## 不先卖就会一颗不剩全吃掉、一直卡灵石）。只在瓶颈、且突破只差灵石的时候卖，便宜的先卖
func _sell_for_break(S: Dictionary) -> void:
	var realm := int(S["realm"])
	if realm >= Prog.REALMS - 1 or not Prog.at_cap(int(S["lv"]), float(S["xp"]), realm):
		return
	var cost := floorf(float(Prog.break_cost(realm + 1)) * float(O["brk"]))
	if float(S["ls"]) >= cost:
		return
	var pills: Array = S["pills"]
	pills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := _sell_rank(a, realm)
		var rb := _sell_rank(b, realm)
		return ra < rb if ra != rb else float(a["value"]) < float(b["value"]))
	while float(S["ls"]) < cost and not pills.is_empty():
		var it: Dictionary = pills.pop_front()
		S["ls"] = float(S["ls"]) + float(it["value"])


## 卖丹的先后（灵石不够布阵时）：再也服不了的 → 本境界的（还在手里说明溢出存满了，突破后就作废）→ 以后的本境丹 → 霸主精魄；同档里便宜的先卖
func _sell_rank(it: Dictionary, realm: int) -> int:
	if it.has("min_realm"):
		return 3
	var r := int(it.get("realm", realm))
	return 0 if r < realm else (1 if r == realm else 2)


## 突破以后：锁在更低境界的本境丹再也服不了，卖掉
func _sell_dead(S: Dictionary) -> void:
	var realm := int(S["realm"])
	var left: Array = []
	for it: Dictionary in S["pills"]:
		if _future(it, realm):
			left.append(it)
		else:
			S["ls"] = float(S["ls"]) + float(it["value"])
			S["dead_sold_in"][realm] = float(S["dead_sold_in"][realm]) + float(it["value"])
	S["pills"] = left


func _break(S: Dictionary) -> void:
	while _cap(S) and int(S["realm"]) < 7:
		var realm := int(S["realm"])
		var to := realm + 1
		var keys: Array = S["keys"]
		var ki := keys.find(to)
		if ki < 0:
			var fr := int(S["frags"].get(to, 0))
			if fr >= Prog.FRAG_N and float(S["ls"]) >= float(Prog.KEY_CRAFT_COST[to]):
				S["frags"][to] = fr - Prog.FRAG_N
				S["ls"] = float(S["ls"]) - float(Prog.KEY_CRAFT_COST[to])
				keys.append(to)
				continue
			if Prog.SHOP_KEY.has(to) and float(S["ls"]) >= float(Prog.SHOP_KEY[to]):
				S["ls"] = float(S["ls"]) - float(Prog.SHOP_KEY[to])
				keys.append(to)
				continue
			S["stuck_key"][realm] = int(S["stuck_key"][realm]) + 1
			return
		var cost := floorf(float(Prog.break_cost(to)) * float(O["brk"]))
		if float(S["ls"]) < cost:
			# 灵石不够：先卖用不上的修为丹（见 _sell_rank）
			var pills: Array = S["pills"]
			pills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ra := _sell_rank(a, realm)
				var rb := _sell_rank(b, realm)
				return ra < rb if ra != rb else float(a["value"]) < float(b["value"]))
			while float(S["ls"]) < cost and not pills.is_empty():
				S["ls"] = float(S["ls"]) + float((pills.pop_front() as Dictionary)["value"])
			if float(S["ls"]) < cost:
				S["stuck_ls"][realm] = int(S["stuck_ls"][realm]) + 1
				return
		S["ls"] = float(S["ls"]) - cost
		if rng.randf() < TRIB_OK:
			keys.remove_at(ki)
			# 2026-11-23 照 Hammer：瓶颈那一级之外攒下的修为按 carry_k 换算、带进新境界（已经在来源里记过，这里不再记来源）
			var carry := Prog.carry_over(int(S["lv"]), float(S["xp"]), realm)
			S["realm"] = to
			S["lv"] = maxi(int(S["lv"]) + 1, to * Prog.LV_PER_REALM + 1)
			S["xp"] = 0.0
			S["at"][to] = [float(S["act_s"]) / 3600.0, int(S["raids"]), int(S["day"])]
			if carry > 0.0:
				var res := Prog.add_xp(int(S["lv"]), 0.0, to, carry)
				S["lv"] = int(res[0])
				S["xp"] = float(res[1])
				var by: Dictionary = S["by"][to]
				by["carry"] = float(by.get("carry", 0.0)) + float(res[2])
				S["carry_in"][to] = float(S["carry_in"][to]) + float(res[2])
				S["waste"]["bottle"] = float(S["waste"]["bottle"]) + (carry - float(res[2])) / Prog.XP_SCALE[to]
			_sell_dead(S)
		else:
			# 失败：扣一半需求（不低于 0），不再直接覆盖成一半；还在瓶颈上的话下次回洞府再渡
			S["xp"] = maxf(float(S["xp"]) - Prog.xp_need(int(S["lv"])) * 0.5, 0.0)
			S["fails_in"][realm] = int(S["fails_in"][realm]) + 1
			return


func _life(P: Dictionary, seed_v: int) -> Dictionary:
	rng.seed = seed_v
	var S := _new_state()
	var per_day := int(P["per_day"])
	while int(S["realm"]) < 7 and int(S["day"]) < 400:
		for i in per_day:
			if int(S["realm"]) >= 7:
				break
			_raid(S, P)
			_hub(S, P, float(P["hub_min"]) * 60.0)
		# 下线：离线打坐 min(剩下的时间, 8 小时) × 一半
		var session_h := float(per_day) * (float(P["raid_min"]) + float(P["hub_min"])) / 60.0
		var off_h := minf(Prog.OFFLINE_CAP_H, 24.0 - session_h)
		_add(S, _med(int(S["realm"])) * 3600.0 * off_h * Prog.OFFLINE_RATE, "off")
		_eat(S)
		_break(S)
		S["day"] = int(S["day"]) + 1
	return S


func _q(a: Array, p: float) -> float:
	if a.is_empty():
		return -1.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(p * float(s.size())))])


func _report(pk: String, runs: int) -> void:
	var P: Dictionary = PROFILES[pk]
	var lives: Array = []
	for i in runs:
		lives.append(_life(P, 1000 + i * 7919))
	print("\n[life] ===== %s：一局 %.0f 分钟 + 局间洞府 %.1f 分钟，陨落 %d%%，%d 局里取中位数 =====" % [P["name"], float(P["raid_min"]), float(P["hub_min"]),
			roundi(100.0 * float(P["death"])), runs])
	var row: Array = []
	for r in range(1, 8):
		var hs: Array = []
		var ds: Array = []
		var rs: Array = []
		for S: Dictionary in lives:
			if (S["at"] as Dictionary).has(r):
				var a: Array = S["at"][r]
				hs.append(float(a[0]))
				rs.append(float(a[1]))
				ds.append(float(a[2]))
		if hs.is_empty():
			row.append("%s 没到" % NAMES[r])
		else:
			row.append("%s %.1f 小时（第 %d 局 / 第 %d 天）" % [NAMES[r], _q(hs, 0.5), int(_q(rs, 0.5)), int(_q(ds, 0.5))])
	print("[life] 到达：" + " → ".join(row))
	var J := {"name": P["name"], "per_day": P["per_day"], "raid_min": P["raid_min"], "reach": [], "realms": []}
	for r in range(1, 8):
		var hs2: Array = []
		var rs2: Array = []
		var ds2: Array = []
		for S: Dictionary in lives:
			if (S["at"] as Dictionary).has(r):
				hs2.append(float(S["at"][r][0]))
				rs2.append(float(S["at"][r][1]))
				ds2.append(float(S["at"][r][2]))
		J["reach"].append({"realm": r, "h50": _q(hs2, 0.5), "h10": _q(hs2, 0.1), "h90": _q(hs2, 0.9), "raid": _q(rs2, 0.5), "day": _q(ds2, 0.5)})
	json_out["profiles"][pk] = J
	var hs7: Array = []
	for S: Dictionary in lives:
		if (S["at"] as Dictionary).has(7):
			hs7.append(float(S["at"][7][0]))
	if not hs7.is_empty():
		print("[life] 大乘：实际在玩 %.1f 小时（快的一成 %.1f / 慢的一成 %.1f）" % [_q(hs7, 0.5), _q(hs7, 0.1), _q(hs7, 0.9)])
	var src := {"kill": 0.0, "pill": 0.0, "med": 0.0, "off": 0.0}
	var waste := {"cap": 0.0, "bottle": 0.0}
	for S: Dictionary in lives:
		for k: String in src.keys():
			src[k] = float(src[k]) + float(S["src"][k]) / float(runs)
		for k: String in waste.keys():
			waste[k] = float(waste[k]) + float(S["waste"][k]) / float(runs)
	var tot := float(src["kill"]) + float(src["pill"]) + float(src["med"]) + float(src["off"])
	J["src"] = {"kill": float(src["kill"]) / tot, "pill": float(src["pill"]) / tot, "med": float(src["med"]) / tot, "off": float(src["off"]) / tot}
	print("[life] 修为来源（按改版前的单位合计）：心得 %d%% / 修为丹 %d%% / 洞府打坐 %d%% / 离线 %d%%；被本局上限截掉的心得 = 实得心得的 %d%%，结转存满浪费 = 总修为的 %d%%" % [
			roundi(100.0 * float(src["kill"]) / tot), roundi(100.0 * float(src["pill"]) / tot), roundi(100.0 * float(src["med"]) / tot), roundi(100.0 * float(src["off"]) / tot),
			roundi(100.0 * float(waste["cap"]) / maxf(float(src["kill"]), 1e-9)), roundi(100.0 * float(waste["bottle"]) / tot)])
	for r in 7:
		var ra := 0.0
		var hr := 0.0
		var sk := 0.0
		var sl := 0.0
		var li := 0.0
		var it_n := 0.0
		var k_n := 0.0
		var eat_n := 0.0
		var ovl_n := 0.0
		var lair_n := 0.0
		var fail_n := 0.0
		var dead_ls := 0.0
		var by := {"kill": 0.0, "pill": 0.0, "med": 0.0, "off": 0.0, "carry": 0.0}
		for S: Dictionary in lives:
			it_n += float(S["items_in"][r]) / float(runs)
			k_n += float(S["kills_in"][r]) / float(runs)
			eat_n += float(S["eat_in"][r]) / float(runs)
			ovl_n += float(S["ovl_in"][r]) / float(runs)
			lair_n += float(S["lair_in"][r]) / float(runs)
			fail_n += float(S["fails_in"][r]) / float(runs)
			dead_ls += float(S["dead_sold_in"][r]) / float(runs)
			var b: Dictionary = S["by"][r]
			for kk: String in by.keys():
				by[kk] = float(by[kk]) + float(b.get(kk, 0.0)) / float(runs)
			ra += float(S["raids_in"][r]) / float(runs)
			hr += float(S["hours_in"][r]) / float(runs)
			sk += float(S["stuck_key"][r]) / float(runs)
			sl += float(S["stuck_ls"][r]) / float(runs)
			li += float(S["ls_in"][r]) / float(runs)
		var bt := maxf(float(by["kill"]) + float(by["pill"]) + float(by["med"]) + float(by["off"]) + float(by["carry"]), 1.0)
		J["realms"].append({"realm": r, "raids": ra, "hours": hr, "kills": k_n / maxf(ra, 0.01), "items": it_n / maxf(ra, 0.01), "stuck_key": sk, "stuck_ls": sl,
				"ls_in": li, "break": float(Prog.break_cost(r + 1)), "kill": float(by["kill"]) / bt, "pill": float(by["pill"]) / bt, "med": float(by["med"]) / bt,
				"off": float(by["off"]) / bt, "carry": float(by["carry"]) / bt, "pills_eaten": eat_n, "overlord_eaten": ovl_n, "lairs": lair_n, "trib_fails": fail_n})
		print("[life]   %s：%.1f 局 / %.1f 小时（每局杀 %.0f 只、掉 %.0f 件），来源 杀%d%% 丹%d%% 坐%d%% 离%d%% 结转%d%%；服丹 %.0f 颗（霸主精魄 %.1f，巢穴 %.1f 次），渡劫失败 %.1f 次，卡破境丹 %.1f 次、卡灵石 %.1f 次，带出灵石 %s（突破要 %s，作废的丹卖了 %s）" % [
				NAMES[r], ra, hr, k_n / maxf(ra, 0.01), it_n / maxf(ra, 0.01), roundi(100.0 * float(by["kill"]) / bt), roundi(100.0 * float(by["pill"]) / bt),
				roundi(100.0 * float(by["med"]) / bt), roundi(100.0 * float(by["off"]) / bt), roundi(100.0 * float(by["carry"]) / bt), eat_n, ovl_n, lair_n, fail_n, sk, sl,
				Prog.short_num(li), Prog.short_num(floorf(float(Prog.break_cost(r + 1)) * float(O["brk"]))), Prog.short_num(dead_ls)])
