extends SceneTree
## 战斗数值规则表 + 自动检查（2026-11-20 夜）：直接调 scripts/combat_stats.gd、raid_data.gd、progression.gd 的真代码，
## 把各境界的攻击 / 气血 / 灵力 / 回复 / 连发 / 飞剑阵 / 剑诀目标、大世界里对常见怪 / 精英 / 巢穴首领的一来一回、PvP、剑冢首领算成表，
## 每一项对着「合理区间」检查，有不合格的就打印 FAIL 并以退出码 1 结束。
##   godot --headless --path . -s res://_tasks/numbers_sim/combat_table.gd [-- --md=<输出 markdown 路径>]
## 注意：这里算的是公式（命中率 100%、怪每 2.65 秒出一招）；剑诀全中的实际伤害要在游戏里量（raid_pace_test.gd 的 --pace-combat）。

const CS := preload("res://scripts/combat_stats.gd")
const Data := preload("res://scripts/raid_data.gd")
const Prog := preload("res://scripts/progression.gd")
const AirCaster := preload("res://scripts/air_caster.gd")

const NAMES := ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"]
const MOB_CYCLE := 2.65          # 小怪一招的周期（秒，按状态时长算的）

var fails: Array = []
var md: Array = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _row(cells: Array) -> void:
	md.append("| " + " | ".join(cells.map(func(c: Variant) -> String: return str(c))) + " |")


func _mob(idx: int, lv: int, elite: bool) -> Array:
	var d: Dictionary = Data.MOBS[idx]
	var boss: bool = d.get("boss", false)
	var sb: Array = Data.SHAPE_BASE[str(d["shape"])]
	var hp0 := (Data.BOSS_HP if boss else float(sb[0])) * float(d["hp"])
	var at0 := (Data.BOSS_DMG if boss else float(sb[1])) * float(d["atk"])
	var hpv := Data.stat(hp0, Data.MOB_HP_G, lv) * (Data.ELITE_HP if elite else 1.0)
	var atv := Data.stat(at0, 0.2, lv) * (Data.ELITE_DMG if elite else 1.0) * Data.MOB_DMG
	return [hpv, atv]


func _init() -> void:
	var md_path := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--md="):
			md_path = a.get_slice("=", 1)
	# ---------- 一、主角各境界 ----------
	md.append("### 主角各境界（等级取境界中间那级；大乘另列 40 级）")
	_row(["境界", "等级", "攻击力", "气血", "灵力（显示）", "灵力单位", "回满（秒）", "连发每柄", "连发每秒（单位）", "连发一管（秒）", "飞剑阵每柄", "飞剑阵单体每秒（单位）", "剑诀 Z/X/C 目标（单位）", "战力（无法宝）"])
	_row(["---", "---", "---", "---", "---", "---", "---", "---", "---", "---", "---", "---", "---", "---"])
	var prev_vdps := 0.0
	var prev_qdps := 0.0
	var levels := []
	for r in 8:
		levels.append([r, r * 3 + 2])
	levels.append([7, 40])
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
		_row([NAMES[r], lv, "%.1f" % CS.atk(lv), "%.0f" % CS.hp(lv), "%.0f" % CS.mp_shown(r, CS.mp_max(r)), "%.0f" % CS.mp_max(r), "%.2f" % refill,
				"%.3f" % CS.volley_k(r), ("%.2f" % vdps) if r >= 2 else "—", ("%.1f" % vbar) if r >= 2 else "—", "%.2f" % CS.q_k(r), "%.2f" % qdps,
				" / ".join(st) if r >= 2 else "—", CS.power(r, lv, {})])
		_check(absf(refill - 6.25) < 0.01, "%s 灵力回满 %.2f 秒（应 6.25）" % [NAMES[r], refill])
		if r >= 2 and lv == r * 3 + 2:
			_check(vdps >= prev_vdps - 0.001, "%s 连发每秒伤害 %.2f 比上一境界低" % [NAMES[r], vdps])
			_check(vdps <= CS.VOLLEY_DPS * 1.7, "%s 连发每秒伤害 %.2f 超过结丹的 1.7 倍" % [NAMES[r], vdps])
			prev_vdps = vdps
		if lv == r * 3 + 2:
			_check(qdps >= prev_qdps - 0.001, "%s 飞剑阵单体每秒 %.2f 比上一境界低" % [NAMES[r], qdps])
			_check(qdps <= 1.8 * 2.0, "%s 飞剑阵单体每秒 %.2f 超过炼气的 2 倍" % [NAMES[r], qdps])
			prev_qdps = qdps
	var g0 := CS.ground_k(0) * 9.0 / CS.base(0)
	var g1 := CS.ground_k(1) * 9.0 / CS.base(1)
	_check(absf(g0 - g1) < 1e-4, "地面起手斩在炼气 / 筑基的倍率不一样（%.3f / %.3f）" % [g0, g1])
	md.append("")
	md.append("地面连招（炼气 / 筑基）：起手 %.3f、二段 %.3f、三段 %.3f 单位（各境界一样；大厅里乘该境界的 base，大世界里乘攻击力）" % [9.0 / 8.0, 11.0 / 8.0, 17.0 / 8.0])
	md.append("")
	# ---------- 二、大世界：主角 vs 该境界常去区域的怪 ----------
	md.append("### 大世界：主角 vs 该境界常打的怪（命中率 100%）")
	_row(["境界（等级）", "常见怪（级）", "怪血", "普攻 1.0× 几下", "连发几秒", "怪一下掉条", "站着挨几下死", "精英几下 / 一下掉条", "巢穴首领（级）", "首领普攻 / 震地掉条", "首领连发几秒"])
	_row(["---", "---", "---", "---", "---", "---", "---", "---", "---", "---", "---"])
	var regions := [0, 0, 1, 2, 3, 4, 4, 4]
	for r in 8:
		var lv := r * 3 + 2
		var ri: int = regions[r]
		var mlv: int = Prog.REALM_MOB_LV[r]
		var pool: Array = Data.REGIONS[ri]["mobs"]
		var mi: int = int(pool[0])
		var m := _mob(mi, mlv, false)
		var el := _mob(mi, mlv, true)
		var hit := CS.atk(lv)
		var htk := float(m[0]) / hit
		var bar := CS.to_bar(float(m[1]), lv)
		var htd := 100.0 / bar
		var vsec := float(m[0]) / (hit * maxf(CS.volley_k(r) * float(Realm.LIST[r]["volley"]), 0.001))
		var blv := Prog.mob_level(ri, 0.9) + 2
		var bm := _mob(int(Data.REGIONS[ri]["boss"]), blv, false)
		var bmelee := CS.to_bar(float(bm[1]) * 1.5, lv)
		var bslam := CS.to_bar(float(bm[1]) * 2.0, lv)
		var bsec := float(bm[0]) / (hit * maxf(CS.volley_k(r) * float(Realm.LIST[r]["volley"]), 0.001))
		_row(["%s（%d）" % [NAMES[r], lv], "%s（%d）" % [Data.MOBS[mi]["name"], mlv], "%.0f" % float(m[0]), "%.1f" % htk, ("%.1f" % vsec) if r >= 2 else "—",
				"%.1f%%" % bar, "%.0f" % ceilf(htd), "%.1f / %.1f%%" % [float(el[0]) / hit, CS.to_bar(float(el[1]), lv)],
				"%s（%d）" % [Data.MOBS[int(Data.REGIONS[ri]["boss"])]["name"], blv], "%.0f%% / %.0f%%" % [bmelee, bslam], ("%.0f" % bsec) if r >= 2 else "—"])
		# 区域里两种怪各刷一半：巨汉（brute）本来就耐打、心得 ×2.4，单独放宽到 12 下；两种的平均要在 2.5 ~ 9 下
		var avg := 0.0
		for j: Variant in pool:
			var mj := _mob(int(j), mlv, false)
			var hj := float(mj[0]) / hit
			avg += hj / float(pool.size())
			var brute := str(Data.MOBS[int(j)]["shape"]) == "brute"
			_check(hj >= 1.5 and hj <= (12.0 if brute else 9.0), "%s 打 %s %.1f 下（应 1.5 ~ %d）" % [NAMES[r], Data.MOBS[int(j)]["name"], hj, 12 if brute else 9])
		_check(avg >= 2.5 and avg <= 9.0, "%s 区域两种怪平均 %.1f 下（应 2.5 ~ 9）" % [NAMES[r], avg])
		_check(bar >= 4.0 and bar <= 14.0, "%s 常见怪一下掉 %.1f%%（应 4 ~ 14）" % [NAMES[r], bar])
		_check(bmelee <= 36.0 and bslam <= 48.0, "%s 巢穴首领一下 %.0f%% / 震地 %.0f%%（应 ≤ 36 / 48，至少挨三下）" % [NAMES[r], bmelee, bslam])
	md.append("")
	# ---------- 三、PvP ----------
	md.append("### PvP：一招 1.0× 打掉对方几点气血条（上限 %.0f）" % CS.PVP_HIT_CAP)
	var hdr := ["攻 \\ 守"]
	for r in 8:
		hdr.append(NAMES[r])
	_row(hdr)
	_row(["---", "---", "---", "---", "---", "---", "---", "---", "---"])
	var worst := 0.0
	for a in 8:
		var cells := [NAMES[a]]
		for d in 8:
			var raw := CS.raid_hit(CS.base(a), a, a * 3 + 2)
			var v := minf(CS.to_bar(raw, d * 3 + 2), CS.PVP_HIT_CAP)
			worst = maxf(worst, v)
			cells.append("%.1f" % v)
		_row(cells)
	var big := minf(CS.to_bar(CS.raid_hit(CS.base(7) * 6.0, 7, 99), 1), CS.PVP_HIT_CAP)
	md.append("")
	md.append("大乘 99 级打炼气 1 级、一下 6 倍的剑诀：%.1f 点（不封顶是 %.0f 点）" % [big, CS.to_bar(CS.raid_hit(CS.base(7) * 6.0, 7, 99), 1)])
	var over := 0
	for a in 8:
		for d in 8:
			if CS.to_bar(CS.raid_hit(CS.base(a) * 6.0, a, a * 3 + 2), d * 3 + 2) > CS.PVP_HIT_CAP:
				over += 1
	var ttk := (100.0 - CS.PVP_BURST) / CS.PVP_SUSTAIN
	md.append("一下 6 倍的剑诀：64 种攻守组合里有 %d 种不封顶会超过 %.0f 点；同一个人从满血打死对方最快 %.1f 秒（先 %.0f 点余量、之后每秒 %.0f 点）" % [over, CS.PVP_HIT_CAP, ttk, CS.PVP_BURST, CS.PVP_SUSTAIN])
	_check(ttk >= 2.5, "PvP 最快 %.1f 秒打死（应 ≥ 2.5）" % ttk)
	md.append("")
	# ---------- 四、剑冢首领 ----------
	md.append("### 剑冢首领（大厅，原始伤害）")
	_row(["境界", "首领血", "连发每秒（原始）", "只靠连发要几秒"])
	_row(["---", "---", "---", "---"])
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
