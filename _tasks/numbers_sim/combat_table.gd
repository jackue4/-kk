extends SceneTree
## 战斗数值规则表 + 自动检查（2026-11-20 夜）：直接调 scripts/combat_stats.gd、raid_data.gd、progression.gd 的真代码，
## 把各境界的攻击 / 气血 / 灵力 / 回复 / 连发 / 飞剑阵 / 剑诀目标、大世界里对常见怪 / 精英 / 巢穴首领的一来一回、PvP、剑冢首领算成表，
## 每一项对着「合理区间」检查，有不合格的就打印 FAIL 并以退出码 1 结束。
##   godot --headless --path . -s res://_tasks/numbers_sim/combat_table.gd [-- --md=<输出 markdown 路径>]
## 注意：这里算的是公式（命中率 100%、怪每 2.65 秒出一招）；剑诀全中的实际伤害要在游戏里量（raid_pace_test.gd 的 --pace-combat）。
## 2026-11-23 数值重构（对标 Hammer，规格 numbers_spec.md v2）：
##   · 伤害一律调 CS 的函数（raid_hit 带怪的防量级、to_bar 带怪的攻量级），不再自己抄公式；怪的血 / 攻 = 旧的 hp0 / at0 × CS.HP_CONV / ATK_CONV × CS.mob_s_hp / mob_s_atk
##   · 每个境界的三级各列一行（境内每级 ×1.374 再加防御项，同一只怪每升一级快 1.45 ~ 1.48 倍；第一级最难、第三级最容易）：
##     上限类（几下打死、一下掉条、巢穴首领）看第 1 级；「至少 1.5 下 / 平均 2.5 ~ 9 下 / 一下 4 ~ 14%」照旧看第 2 级（筑基打草原 4 级怪放宽到 1.0 / 1.5 下）；
##     第 3 级只查「普攻 1.0× 不一下秒掉本档的怪」（≥ 0.8 下）和「挨一下至少 2.5%」
##   · 巢穴首领按真实巢穴位置定等级（Data.pois → Prog.depth_at → mob_level + 2 → Prog.boss_level(Prog.lair_tag)）
##   · PvP 段重写：CS.pvp_hit（只看招式单位、境界差 ×PVP_REALM_ADV^差）+ 三道封顶按 CS.pvp_cap_k 放宽 / 收紧 + 「守」在封顶之后乘
##   · 新加「跨境」一节：高境界回低区割草、低境界进高一档的区

const CS := preload("res://scripts/combat_stats.gd")
const Data := preload("res://scripts/raid_data.gd")
const Prog := preload("res://scripts/progression.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")
const AirCaster := preload("res://scripts/air_caster.gd")

const NAMES := ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"]
const MOB_CYCLE := 2.65          # 小怪一招的周期（秒，按状态时长算的）
const PVP_UPS := 4.0             # PvP 持续输出：每秒约 4 个招式单位（空中普攻连段 + 技能，pace-combat 实测 3.6 ~ 4.9）

var fails: Array = []
var md: Array = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _row(cells: Array) -> void:
	md.append("| " + " | ".join(cells.map(func(c: Variant) -> String: return str(c))) + " |")


func _sep(n: int) -> void:
	var c: Array = []
	for i in n:
		c.append("---")
	_row(c)


## 怪（区域 ri、等级 lv）的 [血, 原始攻击]：照 raid_manager._spawn_mob（规格 §3）——旧的 hp0 / at0 × 换算常数 × 档内量级 × 精英；hp_k = 首领 / 游荡首领的血量折扣
func _mob(idx: int, ri: int, lv: int, elite: bool, hp_k := 1.0) -> Array:
	var d: Dictionary = Data.MOBS[idx]
	var boss: bool = d.get("boss", false)
	var sb: Array = Data.SHAPE_BASE[str(d["shape"])]
	var hp0 := (Data.BOSS_HP if boss else float(sb[0])) * float(d["hp"])
	var at0 := (Data.BOSS_DMG if boss else float(sb[1])) * float(d["atk"])
	var hpv := hp0 * CS.HP_CONV * CS.mob_s_hp(ri, lv) * (Data.ELITE_HP if elite else 1.0) * hp_k
	var atv := at0 * Data.MOB_DMG * CS.ATK_CONV * CS.mob_s_atk(ri, lv) * (Data.ELITE_DMG if elite else 1.0)
	return [hpv, atv]


## 主角（境界 r、等级 lv、不带法宝）一个招式单位打区域 ri、lv 级的怪掉多少血（怪的防量级 = mob_scale(…, 0.2) = mob_s_atk）
func _unit_vs(r: int, lv: int, ri: int, mlv: int) -> float:
	return CS.raid_hit(CS.base(r), r, lv, 0.0, CS.mob_s_atk(ri, mlv))


## 怪的原始伤害 raw 打 lv 级主角（不带「守」）掉几点气血条
func _bar_vs(raw: float, lv: int, ri: int, mlv: int) -> float:
	return CS.to_bar(raw, lv, 0.0, CS.mob_s_atk(ri, mlv))


## 区域 ri 的巢穴首领等级（真实巢穴位置的当地等级 + 2，再夹进巢穴的境界档）
func _lair_lv(ri: int) -> int:
	for p: Dictionary in Data.pois():
		if str(p["kind"]) == "boss" and int(p["region"]) == ri:
			var pos: Vector2 = p["pos"]
			return Prog.boss_level(Prog.lair_tag(ri), Prog.mob_level(ri, Prog.depth_at(ri, pos.x, pos.y)) + 2)
	return Prog.boss_level(Prog.lair_tag(ri), Prog.mob_level(ri, 1.0) + 2)


## PvP：attacker 境界 a 打 defender 境界 d（每秒 ups 个招式单位，d 带「守」g）从满血打到 0 要几秒
## 封顶：先有 PVP_BURST × k 的余量、之后每秒 PVP_SUSTAIN × k（k = CS.pvp_cap_k），「守」在封顶之后乘
func _pvp_ttk(a: int, d: int, ups: float, g := 0.0, gear_atk := 0.0) -> float:
	var dps := ups * CS.pvp_hit(CS.base(a), a, d, gear_atk)
	var k := CS.pvp_cap_k(a, d)
	var keep := 1.0 - clampf(g, 0.0, CS.PVP_GUARD_CAP)
	var need := 100.0 / maxf(keep, 0.01)       # 封顶前要打出的点数
	return maxf(need / maxf(dps, 0.001), (need - CS.PVP_BURST * k) / (CS.PVP_SUSTAIN * k))


func _init() -> void:
	var md_path := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--md="):
			md_path = a.get_slice("=", 1)
	# ---------- 一、主角各境界 ----------
	md.append("### 主角各境界（光身：攻 / 血 / 防 = %.0f / %.0f / %.0f × G(等级)；每个境界列第 1 / 2 / 3 级，大乘另列 30 级）" % [CS.ATK_K, CS.HP_K, CS.DEF_K])
	_row(["境界", "等级", "G", "攻击力", "气血", "防御", "灵力（显示）", "灵力单位", "回满（秒）", "连发每柄", "连发每秒（单位）", "连发一管（秒）", "飞剑阵每柄", "飞剑阵单体每秒（单位）", "剑诀 Z/X/C 目标（单位）", "战力（光身）", "战力（满装）"])
	_sep(17)
	var prev_vdps := 0.0
	var prev_qdps := 0.0
	var prev_pw := 0.0
	var levels := []
	for r in 8:
		for j in range(1, 4):
			levels.append([r, r * 3 + j])
	levels.append([7, 30])
	var full_fx := {"atk": CS.GEAR_ATK_CAP, "guard": 0.6, "vital": 1.2, "seek": 1.2}
	for e: Array in levels:
		var r: int = e[0]
		var lv: int = e[1]
		var rl: Dictionary = Realm.LIST[r]
		var refill := CS.mp_max(r) / (AirCaster.MP_REGEN * CS.mp_regen_k(r))      # 用游戏里真正的回复常数（air_caster.gd）
		var vrate := float(rl["volley"])
		var vdps := CS.volley_k(r) * vrate
		var vbar := CS.mp_max(r) / 30.0
		var qdps := CS.q_k(r) / float(rl["atk_cd"])
		var st: Array = []
		for i in 3:
			st.append("%.1f" % (CS.SKILL_TARGET[i] * CS.skill_g(r)))
		var pw := CS.power(r, lv, {})
		var pw_full := CS.power(r, lv, full_fx)
		_row([NAMES[r], lv, "%.2f" % CS.G(lv), NumFmt.fmt(CS.atk(lv)), NumFmt.fmt(CS.hp(lv)), NumFmt.fmt(CS.def(lv)), "%.0f" % CS.mp_shown(r, CS.mp_max(r)), "%.0f" % CS.mp_max(r), "%.2f" % refill,
				"%.3f" % CS.volley_k(r), ("%.2f" % vdps) if r >= 2 else "—", ("%.1f" % vbar) if r >= 2 else "—", "%.2f" % CS.q_k(r), "%.2f" % qdps,
				" / ".join(st) if r >= 2 else "—", NumFmt.fmt(pw), NumFmt.fmt(pw_full)])
		_check(absf(refill - 6.25) < 0.01, "%s 灵力回满 %.2f 秒（应 6.25）" % [NAMES[r], refill])
		_check(pw > prev_pw, "%s %d 级战力 %s 没比上一行高" % [NAMES[r], lv, NumFmt.fmt(pw)])
		_check(pw_full / pw < 6.0, "%s %d 级满装战力是光身的 %.1f 倍（应 < 6：法宝只是加成）" % [NAMES[r], lv, pw_full / pw])
		prev_pw = pw
		if lv == r * 3 + 2:
			if r >= 2:
				_check(vdps >= prev_vdps - 0.001, "%s 连发每秒伤害 %.2f 比上一境界低" % [NAMES[r], vdps])
				_check(vdps <= CS.VOLLEY_DPS * 1.7, "%s 连发每秒伤害 %.2f 超过结丹的 1.7 倍" % [NAMES[r], vdps])
				prev_vdps = vdps
			_check(qdps >= prev_qdps - 0.001, "%s 飞剑阵单体每秒 %.2f 比上一境界低" % [NAMES[r], qdps])
			_check(qdps <= 1.8 * 2.0, "%s 飞剑阵单体每秒 %.2f 超过炼气的 2 倍" % [NAMES[r], qdps])
			prev_qdps = qdps
	var g0 := CS.ground_k(0) * 9.0 / CS.base(0)
	var g1 := CS.ground_k(1) * 9.0 / CS.base(1)
	_check(absf(g0 - g1) < 1e-4, "地面起手斩在炼气 / 筑基的倍率不一样（%.3f / %.3f）" % [g0, g1])
	md.append("")
	md.append("地面连招（炼气 / 筑基）：起手 %.3f、二段 %.3f、三段 %.3f 单位（各境界一样；大厅里乘该境界的 base，大世界里 × 攻击力 × 防御系数）" % [9.0 / 8.0, 11.0 / 8.0, 17.0 / 8.0])
	md.append("战力满装 = 攻 +%d%%、守 60%%、养 120%%、识 120%%（法宝会丢，只是加成）" % roundi(CS.GEAR_ATK_CAP * 100.0))
	md.append("")
	# ---------- 二、大世界：主角 vs 该境界常打的怪 ----------
	md.append("### 大世界：主角 vs 该境界常打的怪（命中率 100%；怪的等级 = Prog.REALM_MOB_LV，区域 = Prog.REALM_REGION）")
	md.append("检查：几下打死 / 一下掉条的上限、巢穴首领看境内第 1 级；下限照旧看第 2 级（筑基对草原 4 级怪放宽到 1.0 / 1.5 下）；第 3 级只查不被普攻一下秒（≥ 0.8 下）、挨一下 ≥ 2.5%。")
	_row(["境界（等级）", "常见怪（级 / 档）", "怪血", "普攻 1.0× 几下", "两种怪平均", "连发几秒", "怪一下掉条", "站着挨几下死", "精英几下 / 一下掉条", "巢穴首领（级 / 档）", "首领几下", "首领普攻 / 震地掉条", "首领连发几秒"])
	_sep(13)
	for r in 8:
		var ri: int = Prog.REALM_REGION[r]
		var mlv: int = Prog.REALM_MOB_LV[r]
		var mtag := Prog.mob_tag(ri, mlv)
		_check(mtag == r, "%s 常打的怪 %d 级在%s是 %s 档（应是本境界）" % [NAMES[r], mlv, Data.REGIONS[ri]["name"], NAMES[mtag]])
		var pool: Array = Data.REGIONS[ri]["mobs"]
		var mi: int = int(pool[0])
		var bi := int(Data.REGIONS[ri]["boss"])
		var blv := _lair_lv(ri)
		var btag := Prog.mob_tag(ri, blv)
		_check(btag == Prog.lair_tag(ri), "%s巢穴首领 %d 级的档 %d ≠ lair_tag %d" % [Data.REGIONS[ri]["name"], blv, btag, Prog.lair_tag(ri)])
		for j in range(1, 4):
			var lv := r * 3 + j
			var m := _mob(mi, ri, mlv, false)
			var el := _mob(mi, ri, mlv, true)
			var hit := _unit_vs(r, lv, ri, mlv)
			var htk := float(m[0]) / hit
			var bar := _bar_vs(float(m[1]), lv, ri, mlv)
			var htd := 100.0 / bar
			var vps := maxf(CS.volley_k(r) * float(Realm.LIST[r]["volley"]), 0.001)
			var vsec := float(m[0]) / (hit * vps)
			var bm := _mob(bi, ri, blv, false)
			var bhit := _unit_vs(r, lv, ri, blv)
			var bmelee := _bar_vs(float(bm[1]) * 1.5, lv, ri, blv)
			var bslam := _bar_vs(float(bm[1]) * 2.0, lv, ri, blv)
			var bsec := float(bm[0]) / (bhit * vps)
			# 区域里两种怪各刷一半：巨汉（brute）本来就耐打、心得 ×2.4，单独放宽到 12 下；两种的平均要在 2.5 ~ 9 下
			var avg := 0.0
			var lo := 1.5 if r != 1 else 1.0      # 筑基 5 级打草原 4 级的噬金虫只要 1.2 下（4 级已经是筑基档的第一级，境内每级 ×1.374 + 防御项），放宽
			var lo_avg := 2.5 if r != 1 else 1.5
			for jj: Variant in pool:
				var mj := _mob(int(jj), ri, mlv, false)
				var hj := float(mj[0]) / hit
				avg += hj / float(pool.size())
				var brute := str(Data.MOBS[int(jj)]["shape"]) == "brute"
				var mn: String = Data.MOBS[int(jj)]["name"]
				if j == 1:
					_check(hj <= (12.0 if brute else 9.0), "%s %d 级打 %s %.1f 下（应 ≤ %d）" % [NAMES[r], lv, mn, hj, 12 if brute else 9])
				elif j == 2:
					_check(hj >= lo, "%s %d 级打 %s %.2f 下（应 ≥ %.1f）" % [NAMES[r], lv, mn, hj, lo])
				else:
					_check(hj >= 0.8, "%s %d 级打 %s %.2f 下（应 ≥ 0.8：普攻 1.0× 不一下秒掉本档的怪）" % [NAMES[r], lv, mn, hj])
			if j == 1:
				_check(avg <= 9.0, "%s %d 级打区域两种怪平均 %.1f 下（应 ≤ 9）" % [NAMES[r], lv, avg])
				_check(bar <= 15.0, "%s %d 级挨常见怪一下 %.1f%%（应 ≤ 15）" % [NAMES[r], lv, bar])
				_check(bmelee <= 36.0 and bslam <= 48.0, "%s %d 级挨巢穴首领一下 %.0f%% / 震地 %.0f%%（应 ≤ 36 / 48，至少挨三下）" % [NAMES[r], lv, bmelee, bslam])
			elif j == 2:
				_check(avg >= lo_avg and avg <= 9.0, "%s %d 级打区域两种怪平均 %.2f 下（应 %.1f ~ 9）" % [NAMES[r], lv, avg, lo_avg])
				_check(bar >= 4.0 and bar <= 14.0, "%s %d 级挨常见怪一下 %.1f%%（应 4 ~ 14）" % [NAMES[r], lv, bar])
			else:
				_check(bar >= 2.5, "%s %d 级挨常见怪一下 %.1f%%（应 ≥ 2.5，别完全不疼）" % [NAMES[r], lv, bar])
			_row(["%s（%d）" % [NAMES[r], lv], "%s（%d / %s）" % [Data.MOBS[mi]["name"], mlv, NAMES[mtag]], NumFmt.fmt(float(m[0])), "%.2f" % htk, "%.2f" % avg,
					("%.1f" % vsec) if r >= 2 else "—", "%.1f%%" % bar, "%.0f" % ceilf(htd), "%.1f / %.1f%%" % [float(el[0]) / hit, _bar_vs(float(el[1]), lv, ri, mlv)],
					"%s（%d / %s）" % [Data.MOBS[bi]["name"], blv, NAMES[btag]], "%.0f" % (float(bm[0]) / bhit), "%.0f%% / %.0f%%" % [bmelee, bslam], ("%.0f" % bsec) if r >= 2 else "—"])
	md.append("")
	# ---------- 二b、跨境：高境界回低区 / 低境界进高一档的区 ----------
	md.append("### 跨境：境界 A（第 2 级）打境界 B 常打的怪（区域两种怪平均几下 / 常见怪一下掉条）")
	md.append("天道压制不再压伤害（只把心得打成 ×%d%%）：高一境以上打低区应该是割草（≤ 1 下），低一境进高一档的区一下掉一大截（Hammer 式的区域门槛）。" % roundi(Prog.SUPPRESS_GAIN * 100.0))
	var hdr2 := ["A \\ B"]
	for b in 8:
		hdr2.append("%s（%s %d 级）" % [NAMES[b], Data.REGIONS[Prog.REALM_REGION[b]]["name"], Prog.REALM_MOB_LV[b]])
	_row(hdr2)
	_sep(9)
	for a in 8:
		var lv := a * 3 + 2
		var cells := [NAMES[a]]
		for b in 8:
			var ri: int = Prog.REALM_REGION[b]
			var mlv: int = Prog.REALM_MOB_LV[b]
			var pool: Array = Data.REGIONS[ri]["mobs"]
			var hit := _unit_vs(a, lv, ri, mlv)
			var avg := 0.0
			for jj: Variant in pool:
				avg += float(_mob(int(jj), ri, mlv, false)[0]) / hit / float(pool.size())
			var bar := _bar_vs(float(_mob(int(pool[0]), ri, mlv, false)[1]), lv, ri, mlv)
			cells.append("%s 下 / %s%%" % [("%.2f" % avg) if avg < 100.0 else NumFmt.fmt(avg), ("%.2f" % bar) if bar < 100.0 else NumFmt.fmt(bar)])
			if a >= b + 1:
				_check(avg <= 1.0, "%s 打%s常打的怪平均 %.2f 下（高一境以上应 ≤ 1，割草）" % [NAMES[a], NAMES[b], avg])
				_check(bar <= 1.0, "%s 挨%s常打的怪一下 %.2f%%（高一境以上应 ≤ 1%%）" % [NAMES[a], NAMES[b], bar])
			if b == a + 1 and Prog.REALM_REGION[b] != Prog.REALM_REGION[a]:
				_check(avg >= 9.0, "%s 进%s的区打怪平均 %.1f 下（低一境应 ≥ 9：区域门槛）" % [NAMES[a], NAMES[b], avg])
		_row(cells)
	md.append("")
	# ---------- 三、PvP ----------
	md.append("### PvP（大世界真人互殴）：一招 1.0× 打掉对方几点气血条（封顶 %.0f × 境界差倍数；「守」在封顶之后乘）" % CS.PVP_HIT_CAP)
	md.append("CS.pvp_hit = 招式单位 × %.1f × %.2f^(攻方境界 − 守方境界，最多 ±%d)；法宝「攻」在 PvP 里最多 +%d%%、「守」最多 %d%%；三道封顶（单下 %.0f / 余量 %.0f / 每秒 %.0f）× CS.pvp_cap_k" % [
			CS.PVP_UNIT, CS.PVP_REALM_ADV, CS.PVP_REALM_CLAMP, roundi(CS.PVP_GEAR_ATK_CAP * 100.0), roundi(CS.PVP_GUARD_CAP * 100.0), CS.PVP_HIT_CAP, CS.PVP_BURST, CS.PVP_SUSTAIN])
	var hdr := ["攻 \\ 守"]
	for r in 8:
		hdr.append(NAMES[r])
	_row(hdr)
	_sep(9)
	for a in 8:
		var cells := [NAMES[a]]
		for d in 8:
			var raw := CS.pvp_hit(CS.base(a), a, d)
			var v := minf(raw, CS.PVP_HIT_CAP * CS.pvp_cap_k(a, d))
			cells.append("%.1f" % v)
			if a == d:
				_check(absf(raw - CS.PVP_UNIT) < 1e-6, "PvP 同境界（%s）一个单位 %.2f 点（应 = PVP_UNIT %.1f）" % [NAMES[a], raw, CS.PVP_UNIT])
		_row(cells)
	md.append("")
	md.append("从满血打死对方要几秒（每秒 %.0f 个招式单位持续输出；同境界 / 攻方高 1 / 2 / 4 境 / 低 1 / 2 / 4 境）：" % PVP_UPS)
	_row(["守方「守」", "同境界", "高 1 境", "高 2 境", "高 4 境", "低 1 境", "低 2 境", "低 4 境", "低打高 / 高打低（差 1 / 2 / 4 境）"])
	_sep(9)
	var base_r := 3
	for g: float in [0.0, CS.PVP_GUARD_CAP]:
		var c := ["%d%%" % roundi(g * 100.0)]
		var tt := {}
		for dr: int in [0, 1, 2, 4, -1, -2, -4]:
			var a := clampi(base_r + dr, 0, 7)
			tt[dr] = _pvp_ttk(a, base_r, PVP_UPS, g)
			c.append("%.2f 秒" % float(tt[dr]))
		c.append("%.2f / %.2f / %.2f" % [float(tt[-1]) / float(tt[1]), float(tt[-2]) / float(tt[2]), float(tt[-4]) / float(tt[4])])
		_row(c)
		if g == 0.0:
			_check(float(tt[0]) >= 2.5, "PvP 同境界最快 %.2f 秒打死（应 ≥ 2.5）" % float(tt[0]))
			_check(float(tt[4]) >= 1.5, "PvP 高 4 境最快 %.2f 秒打死（应 ≥ 1.5，别一照面就倒）" % float(tt[4]))
			var adv1 := float(tt[-1]) / float(tt[1])
			_check(adv1 >= 1.12 and adv1 <= 1.32, "PvP 差 1 境双方打死对方的时间比 %.2f（应 1.12 ~ 1.32：每高一境多一点优势）" % adv1)
			_check(float(tt[-4]) / float(tt[4]) <= 3.0, "PvP 差 4 境时间比 %.2f（应 ≤ 3，境界差再大也不碾压）" % (float(tt[-4]) / float(tt[4])))
	var gear_k := CS.pvp_hit(CS.base(base_r), base_r, base_r, CS.GEAR_ATK_CAP) / CS.pvp_hit(CS.base(base_r), base_r, base_r, 0.0)
	_check(gear_k <= 1.0 + CS.PVP_GEAR_ATK_CAP + 1e-6, "PvP 法宝「攻」%d%% 打出 ×%.2f（应封顶 ×%.2f）" % [roundi(CS.GEAR_ATK_CAP * 100.0), gear_k, 1.0 + CS.PVP_GEAR_ATK_CAP])
	var big := CS.pvp_hit(CS.base(7) * 6.0, 7, 0)
	md.append("")
	md.append("大乘打炼气、一下 6 倍的剑诀：封顶后 %.1f 点（不封顶 %.1f 点）；满装「攻」%d%% 在 PvP 里只算 ×%.2f；出手方飘字（CS.pvp_shown，结丹 8 级打一个单位）%s" % [
			minf(big, CS.PVP_HIT_CAP * CS.pvp_cap_k(7, 0)), big, roundi(CS.GEAR_ATK_CAP * 100.0), gear_k, NumFmt.fmt(CS.pvp_shown(CS.PVP_UNIT, 8))])
	md.append("")
	# ---------- 四、剑冢首领 ----------
	md.append("### 剑冢首领（大厅，原始伤害）")
	_row(["境界", "首领血", "连发每秒（原始）", "只靠连发要几秒"])
	_sep(4)
	var secs: Array = []
	# 打法按实测混着来（不和 boss_k 用同一个公式，检查才有意义）：空中普攻每秒约 3.8 单位（只随 base 涨）+ 飞剑阵 + 连发一半时间（实测命中约六成）
	for r in range(2, 8):
		var bhp := 12000.0 * CS.boss_k(r)
		var vraw := CS.volley_k(r) * float(Realm.LIST[r]["volley"]) * CS.base(r)
		var mix := (3.8 + CS.q_k(r) / float(Realm.LIST[r]["atk_cd"]) + 0.5 * 0.6 * CS.volley_k(r) * float(Realm.LIST[r]["volley"])) * CS.base(r)
		secs.append(bhp / mix)
		_row([NAMES[r], "%.0f" % bhp, "%.0f" % vraw, "%.0f（混着打 %.0f 秒）" % [bhp / vraw, bhp / mix]])
	var smin: float = secs.min()
	var smax: float = secs.max()
	_check(smax / smin < 1.6, "剑冢首领在各境界混着打的时长差太多（%.0f ~ %.0f 秒）" % [smin, smax])
	md.append("")
	md.append("检查：%s" % ("全部通过" if fails.is_empty() else "；".join(fails)))
	for l: String in md:
		print(l)
	if md_path != "":
		var f := FileAccess.open(md_path, FileAccess.WRITE)
		f.store_string("\n".join(md) + "\n")
		f.close()
	print("[combat-table] %s" % ("PASS" if fails.is_empty() else "FAIL " + "；".join(fails)))
	quit(0 if fails.is_empty() else 1)
