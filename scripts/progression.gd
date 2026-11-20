extends RefCounted
## 修为成长的数值中枢（2026-11-20 新框架。用户定的方向：搜打撤是核心——局内杀怪攒「心得」、撤离成功才结算；
## 带出来的修为丹回洞府吃（丹毒限速）；洞府打坐挂机（含离线）；突破要 修为满 + 破境丹 + 灵石。怪和掉落看「地点」不看局内时间）。
## 数都和模拟器 _tasks/numbers_sim/sim2.js 的 P 一一对应：改这里要同步改那边，再跑
##   node _tasks/numbers_sim/try.js '{"profs":["casual","normal","hardcore"]}'
## 目标节奏（普通玩家：每天 4 局、每局 14 分钟、陨落率 15%）：第 1 局筑基、第 4 局结丹、8 局元婴、16 局化神、27 局炼虚、46 局合体、
##   80 局大乘（约第 20 天，实际在玩约 20 小时）；修为来源 心得 ~38% / 丹药 ~40% / 打坐（含离线）~21%。休闲（每天 2 局）约第 50 天，肝帝（每天 12 局）约第 5 天，
##   三种人到大乘都是实际在玩 19 ~ 21 小时。
## 2026-11-20 晚起用 _tasks/numbers_sim/life_sim.gd 校准（直接调这里和 raid_items.gd 的真代码；杀怪速度是 raid_pace_test.gd 在大世界里实测的 × 0.7）：
##   godot --headless --path . -s res://_tasks/numbers_sim/life_sim.gd -- [--prof=casual,normal,hardcore] [--real=0.7] [--o=kb:12,pill:1,...]
##   sim2.js 是更早的 JS 版，假设每分钟杀 4 只（实测是十几二十只），已经对不上了
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
## 依赖关系：这里只 preload raid_data.gd；存档 raid_profile.gd 在运行时 load（raid_profile → raid_items → 这里，preload 会成环）。
## 反过来：raid_items / raid_profile / raid_manager / hub_hall / hall_pills 都可以 preload 这里；只有 raid_data.gd 不能（它要用就运行时 load）。


static func _prof() -> GDScript:
	return load("res://scripts/raid_profile.gd")

# ---------- 修为曲线 ----------
## 升到 L 级的累计修为 = XP_BASE × (XP_GROWTH^(L-1) - 1) / (XP_GROWTH - 1)，再乘所在境界的折扣（炼气、筑基打折，新手第一局就能筑基）
const LV_PER_REALM := 3
const REALMS := 8
const MAX_LV := 99                 # 大乘以后没有瓶颈，一路涨到 99
const XP_BASE := 2000.0
const XP_GROWTH := 1.4
const REALM_XP_MULT: Array[float] = [0.3, 0.75, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]


static func realm_of(lv: int) -> int:
	return clampi(int(floorf(float(lv - 1) / float(LV_PER_REALM))), 0, REALMS - 1)


static func _raw_total(lv: int) -> float:
	return floorf(XP_BASE * (pow(XP_GROWTH, float(lv - 1)) - 1.0) / (XP_GROWTH - 1.0))


## 第 lv 级升到下一级要的修为
static func xp_need(lv: int) -> float:
	return floorf((_raw_total(lv + 1) - _raw_total(lv)) * REALM_XP_MULT[realm_of(lv)])


## 一个大境界三级加起来要的修为
static func realm_total(realm: int) -> float:
	var s := 0.0
	for l in range(realm * LV_PER_REALM + 1, realm * LV_PER_REALM + LV_PER_REALM + 1):
		s += xp_need(l)
	return s


## 这个境界能升到的最高一级（到了还要再攒满一级经验 = 瓶颈）；大乘没有上限
static func top_lv(realm: int) -> int:
	return MAX_LV if realm >= REALMS - 1 else realm * LV_PER_REALM + LV_PER_REALM


static func at_cap(lv: int, xp: float, realm: int) -> bool:
	return realm < REALMS - 1 and lv >= top_lv(realm) and xp >= xp_need(lv) - 0.01


## 修为 +v：小级满了自动升，到大境界瓶颈就卡住。返回 [lv, xp, 实际用上的, 升了几级]
static func add_xp(lv: int, xp: float, realm: int, v: float) -> Array:
	var used := 0.0
	var ups := 0
	var left := maxf(v, 0.0)
	var top := top_lv(realm)
	while left > 0.0 and lv <= top:
		var need := xp_need(lv)
		if lv >= top:
			var take := minf(maxf(need - xp, 0.0), left)
			xp += take
			used += take
			break
		if xp + left >= need:
			var t2 := need - xp
			used += t2
			left -= t2
			xp = 0.0
			lv += 1
			ups += 1
		else:
			xp += left
			used += left
			left = 0.0
	return [lv, xp, used, ups]


# ---------- 区域和深度（怪的等级、掉落品质都看地点，不看局内时间） ----------
## 区域内的深度 0（边缘）→ 1（巢穴一带及更远）。草原从出生点往外量；四个扇区从草原边上（R0）往巢穴（1020 米）量
const DEPTH_LV: Array[int] = [4, 4, 4, 4, 8]          # 深度 1 时怪比区域基础等级高几级（坠魔谷最深处是魔渊，多一倍）
const REGION_REALM_MAX: Array[int] = [1, 2, 3, 4, 7]  # 各区域「不压制」的最高境界（草原收炼气 / 筑基，坠魔谷收炼虚到大乘）
const LAIR_R := 1020.0
const MEADOW_DEPTH_R := 380.0


static func depth_at(ri: int, x: float, z: float) -> float:
	if ri <= 0:
		var wx := wrapf(x, -Data.HALF, Data.HALF)
		var wz := wrapf(z, -Data.HALF, Data.HALF)
		return clampf(sqrt(wx * wx + wz * wz) / MEADOW_DEPTH_R, 0.0, 1.0)
	return clampf((Data.land_r(x, z) - Data.R0) / (LAIR_R - Data.R0), 0.0, 1.0)


## 区域 ri、深度 depth 处的怪是几级
static func mob_level(ri: int, depth: float) -> int:
	var r := clampi(ri, 0, 4)
	return int(Data.REGIONS[r]["lv"]) + roundi(clampf(depth, 0.0, 1.0) * float(DEPTH_LV[r]))


## 越深东西越值钱
const DEPTH_VALUE := 0.8
const DEPTH_LUCK := 1.0            # 越深掉落品阶的运气越好（加在 roll_tier 的加成上）


static func value_mult(depth: float) -> float:
	return 1.0 + DEPTH_VALUE * clampf(depth, 0.0, 1.0)


# ---------- 心得（局内杀怪；撤离成功才结算成修为） ----------
## 每杀一只 = KILL_BASE × KILL_G^(怪等级-1) × 经验系数（体型：兽 1 / 浮空 0.9 / 巨汉 2.4；精英 ×3；首领 14）。
## 2026-11-20 晚按实测重调（_tasks/numbers_sim/life_sim.gd，杀怪速度用 raid_pace_test.gd 在大世界里量的）：原来 16.5 × 1.14^(等级-1)，
## 是按「每分钟杀 4 只」配的，实测加密以后每分钟十几二十只，心得一下子占了七八成。KILL_G 定 1.19：每个境界的怪高 3 级左右 → 一局心得 ×1.7，
## 和每个境界多花 1.6 倍的局数、修为丹 / 打坐各自每境界 ×1.6 ~ 1.8 对得上，越往后杀怪的分量不掉也不涨
const KILL_BASE := 8.0
const KILL_G := 1.19
## 每局心得上限：按「这个境界常打的怪」算，相当于杀 KILL_CAP_N 只那么多（普通玩家一局两百只上下，碰不到；只拦住一局刷到天荒地老的）
const KILL_CAP_N := 480.0
const REALM_MOB_LV: Array[int] = [2, 4, 8, 11, 14, 19, 22, 24]
const DEATH_KEEP := 0.0            # 陨落时心得留下几成


static func insight(mob_lv: int, k: float) -> float:
	return KILL_BASE * pow(KILL_G, float(clampi(mob_lv, 1, MAX_LV) - 1)) * k


static func insight_cap(realm: int) -> float:
	return insight(REALM_MOB_LV[clampi(realm, 0, REALMS - 1)], 1.0) * KILL_CAP_N


# ---------- 修为丹 ----------
## 五个品阶的基础药力 × 品质倍数（下品 / 中品 / 上品 / 极品）；品质看出产的深度：权重 GRADE_W[g] × (1 + GRADE_DEPTH × 深度)^g
## 2026-11-20 晚 × 0.65（原 84 / 216 / 556 / 1430 / 3678）：怪加密、心得重调以后丹药占到六成多，压回四成上下
const PILL_EXP: Array[float] = [55.0, 140.0, 360.0, 930.0, 2390.0]
const GRADE_NAMES: Array[String] = ["下品", "中品", "上品", "极品"]
const GRADE_MULT: Array[float] = [1.0, 2.0, 4.0, 8.0]
const GRADE_W: Array[float] = [1.0, 0.35, 0.1, 0.02]
const GRADE_DEPTH := 4.0
const GRADE_COLORS: Array[Color] = [Color(0.78, 0.8, 0.84), Color(0.4, 0.9, 0.5), Color(0.35, 0.65, 1.0), Color(1.0, 0.75, 0.3)]


static func pill_exp(tier: int, grade: int) -> float:
	return PILL_EXP[clampi(tier, 0, PILL_EXP.size() - 1)] * GRADE_MULT[clampi(grade, 0, GRADE_MULT.size() - 1)]


static func roll_grade(depth: float, rng: RandomNumberGenerator) -> int:
	var f := 1.0 + GRADE_DEPTH * clampf(depth, 0.0, 1.0)
	var ws: Array[float] = []
	var acc := 0.0
	for g in GRADE_W.size():
		var w := GRADE_W[g] * pow(f, float(g))
		ws.append(w)
		acc += w
	var x := rng.randf() * acc
	for g in ws.size():
		x -= ws[g]
		if x <= 0.0:
			return g
	return 0


## 丹毒：每服一颗 +1，药效 × 1 / (1 + TOX_K × 丹毒)；每分钟自己消 TOX_DECAY，打坐（含离线闭关）时 × TOX_MED
const TOX_K := 0.05
const TOX_DECAY := 0.25
const TOX_MED := 3.0


static func pill_eff(tox: float) -> float:
	return 1.0 / (1.0 + TOX_K * maxf(tox, 0.0))


# ---------- 打坐（洞府修炼场；离线按一半折算，最多 8 小时） ----------
## 每秒修为（按境界）。2026-11-20 晚 × 0.65（原 0.56 ~ 16.05）：跟着整体节奏放慢，离线 + 打坐仍占普通玩家的两成、休闲玩家的一半
const MED_RATE: Array[float] = [0.36, 0.59, 0.95, 1.53, 2.48, 4.0, 6.46, 10.43]
const OFFLINE_RATE := 0.5
const OFFLINE_CAP_H := 8.0
const OFFLINE_MIN_S := 120.0       # 离开不到两分钟不算离线


static func med_rate(realm: int) -> float:
	return MED_RATE[clampi(realm, 0, REALMS - 1)]


# ---------- 突破 ----------
## 修为满 + 对应的破境丹 + 灵石（按要去的境界）。破境丹在渡劫成功时才服下；灵石起劫时就扣（布阵的花费，失败不退）
## 2026-11-20 晚：实测一个境界带出来的灵石是突破价的七到十倍（灵石没压力），结丹往后提到约 3 倍；筑基、结丹两道留得轻，新人别卡在钱上
const BREAK_COST: Array[int] = [0, 500, 2500, 12000, 50000, 160000, 330000, 720000]
const KEY_CRAFT_COST: Array[int] = [0, 100, 400, 1500, 5000, 14000, 36000, 90000]   # 丹房用碎片合破境丹另收的灵石
const FRAG_N := 3                  # 几片碎片合一颗
const SHOP_KEY := {1: 300, 2: 1200}   # 坊市只卖筑基丹、降尘丹（新人解卡），往上的只能在禁地里拿


static func break_cost(to: int) -> int:
	return BREAK_COST[clampi(to, 0, REALMS - 1)]


# ---------- 破境丹掉落 ----------
## 每件掉落是破境丹的概率 KEY_P + KEY_PB × 加成；禁制宝库另有 VAULT_KEY 送一颗；巢穴首领必掉一片本区的碎片
const KEY_P := 0.006
const KEY_PB := 0.006
const VAULT_KEY := 0.15
## 各区域出哪几阶破境丹（通往的境界: 权重）——按「在这里刷的人下一步要什么」配
const REGION_KEYS := [{1: 0.6, 2: 0.4}, {3: 0.75, 4: 0.25}, {4: 0.75, 5: 0.25}, {5: 0.75, 6: 0.25}, {6: 0.6, 7: 0.4}]


static func roll_key_to(ri: int, rng: RandomNumberGenerator, depth := 0.0) -> int:
	var tab: Dictionary = REGION_KEYS[clampi(ri, 0, 4)]
	var keys: Array = tab.keys()
	keys.sort()
	# 越深，高一阶的那颗越常见
	var ws: Array[float] = []
	var acc := 0.0
	for i in keys.size():
		var w := float(tab[keys[i]]) * (1.0 + clampf(depth, 0.0, 1.0) * float(i))
		ws.append(w)
		acc += w
	var x := rng.randf() * acc
	for i in keys.size():
		x -= ws[i]
		if x <= 0.0:
			return int(keys[i])
	return int(keys[0])


## 巢穴首领掉的碎片通往哪一阶（本区主出的那一阶）
static func frag_to(ri: int) -> int:
	var tab: Dictionary = REGION_KEYS[clampi(ri, 0, 4)]
	var best := 0
	var bw := -1.0
	for k: Variant in tab.keys():
		if float(tab[k]) > bw:
			bw = float(tab[k])
			best = int(k)
	return best


# ---------- 天道压制（境界高出区域上限的人进低阶区域） ----------
## 每高出一个境界：打出的伤害 × SUPPRESS_DMG；心得 / 掉落品质按 SUPPRESS_GAIN 打折
const SUPPRESS_DMG := 0.55
const SUPPRESS_GAIN := 0.25


static func suppress_gap(realm: int, ri: int) -> int:
	return maxi(realm - REGION_REALM_MAX[clampi(ri, 0, 4)], 0)


# ---------- 存档里的修为 / 丹毒 / 离线（都记在 raid_profile.gd 的 data() 里） ----------
## 修为 +v（服丹、打坐、撤离结算共用）：按存档里的境界算瓶颈。返回 {used, ups, lv}
static func profile_add_xp(v: float) -> Dictionary:
	var d: Dictionary = _prof().data()
	var realm: int = _prof().realm()
	var cu: Array = _prof().cult(realm)
	var res := add_xp(int(cu[0]), float(cu[1]), realm, v)
	d["lv"] = int(res[0])
	d["xp"] = float(res[1])
	return {"used": float(res[2]), "ups": int(res[3]), "lv": int(res[0])}


static func profile_at_cap() -> bool:
	var realm: int = _prof().realm()
	var cu: Array = _prof().cult(realm)
	return at_cap(int(cu[0]), float(cu[1]), realm)


static func _now() -> float:
	return Time.get_unix_time_from_system()


## 当前丹毒（按上次记下的时间自然消退）
static func tox() -> float:
	var d: Dictionary = _prof().data()
	var t0 := float(d.get("tox_t", 0.0))
	var v := float(d.get("tox", 0.0))
	if v <= 0.0 or t0 <= 0.0:
		return maxf(v, 0.0)
	var mins := maxf(_now() - t0, 0.0) / 60.0
	return maxf(v - mins * TOX_DECAY, 0.0)


static func _set_tox(v: float) -> void:
	var d: Dictionary = _prof().data()
	d["tox"] = maxf(v, 0.0)
	d["tox_t"] = _now()


## 服一颗修为丹：按丹毒折算后加修为、丹毒 +1。meditating = 在修炼场打坐时服（炼化，药力 ×MED_PILL）。返回 {used, ups, lv, eff, gain}
const MED_PILL := 1.3


static func eat_pill(base_exp: float, meditating := false) -> Dictionary:
	var t := tox()
	var eff := pill_eff(t) * (MED_PILL if meditating else 1.0)
	var gain := base_exp * eff
	var r := profile_add_xp(gain)
	_set_tox(t + 1.0)
	r["eff"] = eff
	r["gain"] = gain
	return r


## 打坐 dt 秒：加修为、额外消丹毒（打坐时丹毒消得快 TOX_MED 倍）。返回实际涨的修为
static func meditate_tick(dt: float) -> float:
	var t := tox()
	if t > 0.0:
		_set_tox(t - dt / 60.0 * TOX_DECAY * (TOX_MED - 1.0))
	return float(profile_add_xp(med_rate(_prof().realm()) * dt)["used"])


## 记一下「最后在线」的时间（raid_profile.gd 的 save() 每次存档都会记；这里给切后台时手动记用）
static func touch_seen() -> void:
	_prof().data()["seen"] = _now()


## 结算离线打坐：从 since（unix 秒；开机时用 Profile.take_boot_seen()，手机切回前台时用切走那一刻）到现在的时长
## （最多 8 小时）× 打坐速度 × 一半，到瓶颈为止；丹毒按闭关速度消。
## 返回 {secs, gain, capped}；since <= 0（第一次开游戏）或不到两分钟返回 secs = 0
static func settle_offline(since: float) -> Dictionary:
	var d: Dictionary = _prof().data()
	var now := _now()
	if since <= 0.0 or now - since < OFFLINE_MIN_S:
		return {"secs": 0.0, "gain": 0.0, "capped": false}
	var secs := minf(now - since, OFFLINE_CAP_H * 3600.0)
	## 2026-11-20 修：从已自然消退过的丹毒算起（tox() 已含上次服丹到现在的自然消退），离线这段只再补闭关多出来的那部分；
	## 以前从存档里的原值起算、又把 tox_t 改成现在，上次服丹到离线之前那段消退被吃掉，丹毒会涨回去
	var t := tox()
	if t > 0.0:
		d["tox"] = maxf(t - secs / 60.0 * TOX_DECAY * (TOX_MED - 1.0), 0.0)
		d["tox_t"] = now
	var r := profile_add_xp(med_rate(_prof().realm()) * secs * OFFLINE_RATE)
	_prof().save()
	return {"secs": secs, "gain": float(r["used"]), "capped": profile_at_cap()}


## 「1.2万」这样的短写（界面上的大数）
static func short_num(v: float) -> String:
	var a := absf(v)
	if a >= 1.0e8:
		return "%.1f亿" % (v / 1.0e8)
	if a >= 1.0e4:
		return ("%.0f万" if a >= 1.0e5 else "%.1f万") % (v / 1.0e4)
	return str(int(roundf(v)))
