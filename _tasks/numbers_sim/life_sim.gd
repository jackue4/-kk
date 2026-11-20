extends SceneTree
## 一辈子的修为成长模拟（2026-11-20）：直接调游戏里的真代码——修为曲线 / 心得 / 丹毒 / 打坐 / 突破价格（scripts/progression.gd）、
## 掉落表（raid_items.gd 的 roll / pill / key / herb）、品阶运气（raid_data.gd 的 roll_tier）、搜点出货规则（照抄 raid_search.gd 的 _finish）。
## 杀怪速度、怪的种类比例、心得系数用 raid_pace_test.gd 在真实大世界里量出来的数（pace.json；没有就用下面 PACE_DEFAULT）。
## 跑法（headless，几秒到几十秒）：
##   godot --headless --path . -s res://_tasks/numbers_sim/life_sim.gd -- [--runs=60] [--prof=casual,normal,hardcore] [--kpm=1.0]
##   --real：真人的杀怪速度是探针（无敌、不躲、直线飞过去一直打）的几成，默认 0.7
##   --o=ins:1.2,cap:0.3,pill:1.0,drop:0.3,med:1.0,medg:1.0,brk:1.0：试数用的倍率（心得 / 本局上限 / 修为丹药力 / 小怪掉落率 / 打坐速度 /
##       打坐每高一个境界再乘 / 突破灵石），试好了要写回 progression.gd / raid_manager.gd 再不带 --o 跑一遍确认
## 打印每种玩家：到每个境界的「实际在玩的小时数」（局内 + 局间在洞府里）、第几天、第几局，修为来源占比，各境界卡在哪。

const Prog := preload("res://scripts/progression.gd")
const Items := preload("res://scripts/raid_items.gd")
const Data := preload("res://scripts/raid_data.gd")
const RM := preload("res://scripts/raid_manager.gd")
const PILL_PREF := 3.0      # 挑背包时修为丹按卖价的几倍算（真人更想要修为丹）

const ENTRY_REALM := [0, 2, 3, 4, 5]
const NAMES := ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"]
const SITE_KINDS := ["jar", "herb", "grave", "vault"]
const SITE := {"jar": [1, 2, 0.0], "herb": [2, 3, 0.0], "grave": [2, 3, 0.5], "vault": [4, 5, 1.4], "urn": [3, 4, 1.0]}
const COUNTS := [[9, 6, 3, 1], [4, 6, 5, 3], [4, 6, 5, 3], [4, 6, 5, 3], [4, 6, 5, 3]]
const BAG := 12
const TRIB_OK := 0.85
## 量不到时的兜底（2026-11-20 第一次量之前的假设，和 sim2.js 一样：每分钟 4 只、一成精英）
const PACE_DEFAULT := {"kpm": 4.0, "elite_frac": 0.08, "boss_pm": 0.15, "avg_k": 1.6}

## 玩家画像：每天几局、一局几分钟、局间在洞府待几分钟（打坐 + 服丹）、陨落率、一局搜几个点、打掉巢穴的几率、平均深度、游荡首领打得过的几率
const PROFILES := {
	"casual": {"name": "休闲（每天 2 局）", "per_day": 2, "raid_min": 12.0, "hub_min": 2.0, "death": 0.25, "sites": 5, "lair": 0.15, "depth": 0.2, "boss": 0.5, "kill_k": 0.8},
	"normal": {"name": "普通（每天 4 局）", "per_day": 4, "raid_min": 14.0, "hub_min": 2.0, "death": 0.15, "sites": 7, "lair": 0.35, "depth": 0.35, "boss": 0.7, "kill_k": 1.0},
	"hardcore": {"name": "肝帝（每天 12 局）", "per_day": 12, "raid_min": 18.0, "hub_min": 1.5, "death": 0.1, "sites": 9, "lair": 0.6, "depth": 0.5, "boss": 0.9, "kill_k": 1.15},
}

var pace: Array = []
var rng := RandomNumberGenerator.new()
var kpm_k := 0.7
var json_out := {}
var O := {"ins": 1.0, "kb": -1.0, "kg": -1.0, "capn": -1.0, "pill": 1.0, "pillg": 1.0, "drop": -1.0, "med": 1.0, "medg": 1.0, "brk": 1.0}


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
	print("[life] 修为曲线：各境界总修为 " + " / ".join(range(8).map(func(r: int) -> String: return "%s %s" % [NAMES[r], Prog.short_num(Prog.realm_total(r))])))
	json_out["profiles"] = {}
	json_out["real"] = kpm_k
	json_out["runs"] = runs
	json_out["pace"] = pace
	json_out["realm_total"] = range(8).map(func(r: int) -> float: return Prog.realm_total(r))
	json_out["params"] = {"KILL_BASE": Prog.KILL_BASE, "KILL_G": Prog.KILL_G, "KILL_CAP_N": Prog.KILL_CAP_N, "PILL_EXP": Prog.PILL_EXP, "MED_RATE": Prog.MED_RATE,
			"BREAK_COST": Prog.BREAK_COST, "KILL_DROP": RM.KILL_DROP, "MOB_CAP": RM.MOB_CAP, "MOB_CAP_MOBILE": RM.MOB_CAP_MOBILE, "O": O}
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


func _load_pace(path: String) -> void:
	pace = []
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
		var ri := int(o["region"])
		var kills := float(o["mob"]) + float(o["elite"]) + float(o["boss"])
		var mins := maxf(float(o["minutes"]), 0.01)
		var kpm := float(o["kpm"])
		# 每只的平均经验系数：新探针直接记了 avg_k；老的只有每分钟心得，按当时的公式（16.5 × 1.14^(等级-1)）反推
		var unit := 16.5 * pow(1.14, float(int(o["mob_lv"]) - 1))
		var typed := kills > 0.0      # 第一版探针没记下种类：精英 / 首领比例用兜底
		pace[ri] = {"kpm": kpm, "elite_frac": float(o["elite"]) / maxf(kills, 1.0) if typed else float(PACE_DEFAULT["elite_frac"]),
				# 游荡首领：探针把它排在小怪后面、一个区域只跑 5 分钟，基本碰不到；按导演 240 ~ 360 秒一只算
				"boss_pm": maxf(float(o["boss"]) / mins, float(PACE_DEFAULT["boss_pm"])),
				"avg_k": float(o["avg_k"]) if o.has("avg_k") else float(o["insight_pm"]) / maxf(kpm, 0.01) / unit, "measured": true}


# ---------- 一个玩家 ----------

func _new_state() -> Dictionary:
	return {"realm": 0, "lv": 1, "xp": 0.0, "ls": 300.0, "tox": 0.0, "pills": [], "keys": [], "frags": {}, "raids": 0, "act_s": 0.0, "day": 1,
			"src": {"kill": 0.0, "pill": 0.0, "med": 0.0, "off": 0.0}, "waste": {"cap": 0.0, "bottle": 0.0}, "at": {0: [0.0, 0, 1]},
			"stuck_key": [0, 0, 0, 0, 0, 0, 0, 0], "stuck_ls": [0, 0, 0, 0, 0, 0, 0, 0], "raids_in": [0, 0, 0, 0, 0, 0, 0, 0],
			"hours_in": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "ls_in": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
			"by": [{}, {}, {}, {}, {}, {}, {}, {}], "items_in": [0, 0, 0, 0, 0, 0, 0, 0], "kills_in": [0, 0, 0, 0, 0, 0, 0, 0]}


func _add(S: Dictionary, v: float, tag: String) -> void:
	if v <= 0.0:
		return
	var res := Prog.add_xp(int(S["lv"]), float(S["xp"]), int(S["realm"]), v)
	S["lv"] = int(res[0])
	S["xp"] = float(res[1])
	S["src"][tag] = float(S["src"][tag]) + float(res[2])
	var by: Dictionary = S["by"][int(S["realm"])]
	by[tag] = float(by.get(tag, 0.0)) + float(res[2])
	S["waste"]["bottle"] = float(S["waste"]["bottle"]) + v - float(res[2])


func _cap(S: Dictionary) -> bool:
	return Prog.at_cap(int(S["lv"]), float(S["xp"]), int(S["realm"]))


func _region(realm: int) -> int:
	var b := 0
	for i in 5:
		if ENTRY_REALM[i] <= realm:
			b = i
	return b


func _poisson(lam: float) -> int:
	var l := exp(-lam)
	var k := -1
	var p := 1.0
	while p > l:
		p *= rng.randf()
		k += 1
	return k


func _site_items(kind: String, ri: int, depth: float) -> Array:
	var info: Array = SITE[kind]
	var n := rng.randi_range(int(info[0]), int(info[1]))
	var items: Array = []
	match kind:
		"herb":
			for i in n:
				items.append(Items.herb(ri if rng.randf() > 0.12 or ri >= 4 else ri + 1))
			if rng.randf() < 0.2:
				items.append(Items.pill(Data.roll_tier(ri, rng, depth * Prog.DEPTH_LUCK), Prog.roll_grade(depth, rng)))
		"vault":
			items = Items.roll(ri, n, rng, float(info[2]), depth)
			if rng.randf() < Prog.VAULT_KEY:
				items.append(Items.key(Prog.roll_key_to(ri, rng, depth)))
		_:
			items = Items.roll(ri, n, rng, float(info[2]), depth)
	return items


func _raid(S: Dictionary, P: Dictionary) -> void:
	var realm := int(S["realm"])
	var ri := _region(realm)
	var depth := clampf(float(P["depth"]) + 0.45 * float(realm - ENTRY_REALM[ri]) + (rng.randf() - 0.5) * 0.3, 0.0, 1.0)
	var mob_lv := Prog.mob_level(ri, depth)
	var dies := rng.randf() < float(P["death"])
	var T := float(P["raid_min"])
	if dies:
		T = 2.0 + rng.randf() * (T - 2.0)
	var pc: Dictionary = pace[ri]
	var items: Array = []
	var kills := _poisson(float(pc["kpm"]) * float(P["kill_k"]) * kpm_k * T)
	var elites := 0
	for i in kills:
		if rng.randf() < float(pc["elite_frac"]):
			elites += 1
	var unit := _ins(mob_lv, 1.0)
	var ins := float(kills) * float(pc["avg_k"]) * unit * float(O["ins"])
	S["kills_in"][realm] = int(S["kills_in"][realm]) + kills
	for i in kills - elites:
		if rng.randf() < float(O["drop"]):
			items.append_array(Items.roll(ri, 1, rng, 0.0, depth))
	for i in elites:
		items.append_array(Items.roll(ri, 2, rng, 0.5, depth))
	var bosses := 0
	for i in _poisson(float(pc["boss_pm"]) * T):
		if rng.randf() < float(P["boss"]):
			bosses += 1
			items.append_array(Items.roll(ri, 3, rng, 0.8, depth))
	if T > 6.0 and rng.randf() < float(P["lair"]):
		ins += _ins(mob_lv + 2, 14.0) * float(O["ins"])
		items.append_array(Items.roll(ri, 5, rng, 1.3, depth))
		items.append(Items.frag(Prog.frag_to(ri)))
		items.append_array(Items.roll(ri, 3, rng, 1.0, depth))      # 巢穴边上的宗门宝罐
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
	var vk := Prog.value_mult(depth)
	var cap := _ins(Prog.REALM_MOB_LV[realm], 1.0) * float(O["capn"])
	S["items_in"][realm] = int(S["items_in"][realm]) + items.size()
	if ins > cap:
		S["waste"]["cap"] = float(S["waste"]["cap"]) + ins - cap
		ins = cap
	S["raids"] = int(S["raids"]) + 1
	S["raids_in"][realm] = int(S["raids_in"][realm]) + 1
	S["act_s"] = float(S["act_s"]) + T * 60.0
	S["hours_in"][realm] = float(S["hours_in"][realm]) + T / 60.0
	S["tox"] = maxf(float(S["tox"]) - T * Prog.TOX_DECAY, 0.0)
	if dies:
		# 储物戒保住一件：有破境丹 / 残片保那个，否则保最好的修为丹
		for it: Dictionary in items:
			if str(it["kind"]) == "key" and int(it["to"]) > realm:
				S["keys"].append(int(it["to"]))
				return
		return
	_add(S, ins, "kill")
	# 背包 12 格：破境丹、残片、修为丹优先（药力高的先），其余按每格的价值
	var keep: Array = []
	var rest: Array = []
	for it: Dictionary in items:
		var kd := str(it["kind"])
		if kd == "key":
			if int(it["to"]) > realm:
				S["keys"].append(int(it["to"]))
		elif kd == "frag":
			var to := int(it["to"])
			S["frags"][to] = int(S["frags"].get(to, 0)) + 1
		elif kd == "pill" and Items.is_xp_pill(it):
			keep.append(it)
		else:
			rest.append(it)
	# 挑法：按每格值多少（修为丹按卖价 × PILL_PREF），和游戏里背包满了「以贵换贱」一个思路
	var all: Array = keep + rest
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _worth(a) > _worth(b))
	var used := 0
	for it: Dictionary in all:
		var s := Items.size_of(it)
		if used + s > BAG:
			continue
		used += s
		if str(it["kind"]) == "pill" and Items.is_xp_pill(it):
			S["pills"].append(float(it["exp"]) * float(O["pill"]) * pow(float(O["pillg"]), float(int(it["tier"]))))
		else:
			var v := floorf(float(it["value"]) * vk)
			S["ls"] = float(S["ls"]) + v
			S["ls_in"][realm] = float(S["ls_in"][realm]) + v


## 心得公式（和 progression.gd 的 insight 一样，参数可以用 --o 换）
func _ins(lv: int, k: float) -> float:
	return float(O["kb"]) * pow(float(O["kg"]), float(maxi(lv, 1) - 1)) * k


func _worth(it: Dictionary) -> float:
	var v := float(it["value"])
	if str(it["kind"]) == "pill" and Items.is_xp_pill(it):
		v *= PILL_PREF
	return v / float(Items.size_of(it))


func _med(realm: int) -> float:
	return Prog.med_rate(realm) * float(O["med"]) * pow(float(O["medg"]), float(realm))


## 局间在洞府：边打坐边服丹（药力 ×MED_PILL），打坐剩下的时间按打坐速度涨修为；能突破就突破
func _hub(S: Dictionary, P: Dictionary, secs: float) -> void:
	S["act_s"] = float(S["act_s"]) + secs
	S["hours_in"][int(S["realm"])] = float(S["hours_in"][int(S["realm"])]) + secs / 3600.0
	_eat(S, true)
	_add(S, _med(int(S["realm"])) * secs, "med")
	S["tox"] = maxf(float(S["tox"]) - secs / 60.0 * Prog.TOX_DECAY * Prog.TOX_MED, 0.0)
	_break(S)
	_eat(S, true)


func _eat(S: Dictionary, med: bool) -> void:
	var pills: Array = S["pills"]
	pills.sort()
	pills.reverse()
	var left: Array = []
	for e: float in pills:
		if _cap(S):
			left.append(e)
			continue
		var eff := Prog.pill_eff(float(S["tox"])) * (Prog.MED_PILL if med else 1.0)
		_add(S, e * eff, "pill")
		S["tox"] = float(S["tox"]) + 1.0
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
			# 灵石不够：卖掉用不上的修为丹（卖价 = 药力对应的价值，低的先卖）
			var pills: Array = S["pills"]
			pills.sort()
			while float(S["ls"]) < cost and not pills.is_empty():
				S["ls"] = float(S["ls"]) + _pill_value(float(pills.pop_front()))
			if float(S["ls"]) < cost:
				S["stuck_ls"][realm] = int(S["stuck_ls"][realm]) + 1
				return
		S["ls"] = float(S["ls"]) - cost
		if rng.randf() < TRIB_OK:
			keys.remove_at(ki)
			S["realm"] = to
			S["lv"] = maxi(int(S["lv"]) + 1, to * Prog.LV_PER_REALM + 1)
			S["xp"] = 0.0
			S["at"][to] = [float(S["act_s"]) / 3600.0, int(S["raids"]), int(S["day"])]
		else:
			S["xp"] = Prog.xp_need(int(S["lv"])) * 0.5
			return


## 修为丹的卖价：raid_items.gd 的 pill() 里 value = 品阶价值 × 0.4 × 品质倍数，药力 = PILL_EXP × 品质倍数，按药力反推
func _pill_value(e0: float) -> float:
	for t in range(4, -1, -1):
		var e := e0 / float(O["pill"]) / pow(float(O["pillg"]), float(t))
		for g in range(3, -1, -1):
			if absf(Prog.pill_exp(t, g) - e) < 0.5:
				return floorf(float(Items.tier_value(t)) * 0.4 * Prog.GRADE_MULT[g])
	return e0 * 0.3


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
		# 下线：离线打坐 min(剩下的时间, 8 小时) × 一半；丹毒清空
		var session_h := float(per_day) * (float(P["raid_min"]) + float(P["hub_min"])) / 60.0
		var off_h := minf(Prog.OFFLINE_CAP_H, 24.0 - session_h)
		_add(S, _med(int(S["realm"])) * 3600.0 * off_h * Prog.OFFLINE_RATE, "off")
		S["tox"] = 0.0
		_eat(S, false)
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
	print("[life] 修为来源：心得 %d%% / 修为丹 %d%% / 洞府打坐 %d%% / 离线 %d%%；被本局上限截掉的心得 = 实得心得的 %d%%，卡瓶颈浪费 = 总修为的 %d%%" % [
			roundi(100.0 * float(src["kill"]) / tot), roundi(100.0 * float(src["pill"]) / tot), roundi(100.0 * float(src["med"]) / tot), roundi(100.0 * float(src["off"]) / tot),
			roundi(100.0 * float(waste["cap"]) / maxf(float(src["kill"]), 1.0)), roundi(100.0 * float(waste["bottle"]) / tot)])
	for r in 7:
		var ra := 0.0
		var hr := 0.0
		var sk := 0.0
		var sl := 0.0
		var li := 0.0
		var it_n := 0.0
		var k_n := 0.0
		var by := {"kill": 0.0, "pill": 0.0, "med": 0.0, "off": 0.0}
		for S: Dictionary in lives:
			it_n += float(S["items_in"][r]) / float(runs)
			k_n += float(S["kills_in"][r]) / float(runs)
			var b: Dictionary = S["by"][r]
			for kk: String in by.keys():
				by[kk] = float(by[kk]) + float(b.get(kk, 0.0)) / float(runs)
			ra += float(S["raids_in"][r]) / float(runs)
			hr += float(S["hours_in"][r]) / float(runs)
			sk += float(S["stuck_key"][r]) / float(runs)
			sl += float(S["stuck_ls"][r]) / float(runs)
			li += float(S["ls_in"][r]) / float(runs)
		var bt := maxf(float(by["kill"]) + float(by["pill"]) + float(by["med"]) + float(by["off"]), 1.0)
		J["realms"].append({"realm": r, "raids": ra, "hours": hr, "kills": k_n / maxf(ra, 0.01), "items": it_n / maxf(ra, 0.01), "stuck_key": sk, "stuck_ls": sl,
				"ls_in": li, "break": float(Prog.break_cost(r + 1)), "kill": float(by["kill"]) / bt, "pill": float(by["pill"]) / bt, "med": float(by["med"]) / bt, "off": float(by["off"]) / bt})
		print("[life]   %s：%.1f 局 / %.1f 小时（每局杀 %.0f 只、掉 %.0f 件），来源 杀%d%% 丹%d%% 坐%d%% 离%d%%，卡破境丹 %.1f 次、卡灵石 %.1f 次，带出灵石 %s（突破要 %s）" % [
				NAMES[r], ra, hr, k_n / maxf(ra, 0.01), it_n / maxf(ra, 0.01), roundi(100.0 * float(by["kill"]) / bt), roundi(100.0 * float(by["pill"]) / bt),
				roundi(100.0 * float(by["med"]) / bt), roundi(100.0 * float(by["off"]) / bt), sk, sl, Prog.short_num(li),
				Prog.short_num(floorf(float(Prog.break_cost(r + 1)) * float(O["brk"])))])
