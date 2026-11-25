extends SceneTree
## 数值重构的核心公式核对（headless）：godot --headless --path . -s res://_tasks/numbers_rework_20261123/check_core.gd
const CS := preload("res://scripts/combat_stats.gd")
const Prog := preload("res://scripts/progression.gd")
const NF := preload("res://scripts/num_fmt.gd")

func _init() -> void:
	var names := ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"]
	for lv: int in [1, 3, 4, 7, 10, 13, 16, 19, 22, 24, 30, 99]:
		print("[core] lv%d %s  攻 %s 血 %s 防 %s 战力(光身) %s" % [lv, names[Prog.realm_of(lv)], NF.fmt(CS.atk(lv)), NF.fmt(CS.hp(lv)), NF.fmt(CS.def(lv)), NF.fmt(CS.power(0, lv, {}))])
	# 同级 / 跨级：兽 2960×S 血，1 单位伤害
	for c: Array in [[1, 0, 1], [3, 0, 3], [1, 0, 4], [4, 0, 4], [7, 1, 7], [9, 1, 11], [16, 4, 16], [17, 4, 19], [24, 4, 24], [22, 0, 2]]:
		var lp: int = c[0]
		var ri: int = c[1]
		var ml: int = c[2]
		var hp_m := 48.0 * CS.HP_CONV * CS.mob_s_hp(ri, ml)
		var hit := CS.raid_hit(CS.base(Prog.realm_of(lp)), Prog.realm_of(lp), lp, 0.0, CS.mob_s_atk(ri, ml))
		var raw := 12.0 * 0.8 * CS.ATK_CONV * CS.mob_s_atk(ri, ml)
		print("[core] 主角 lv%d 打 区%d lv%d（档 %d）：%.2f 下死，一下掉 %.2f%%" % [lp, ri, ml, Prog.mob_tag(ri, ml), hp_m / hit, CS.to_bar(raw, lp, 0.0, CS.mob_s_atk(ri, ml))])
	for r in 8:
		print("[core] %s 总修为 %s 下品丹 %s 极品 %s 霸主 %s 打坐每息 %s 心得上限 %s" % [names[r], NF.fmt(Prog.realm_total(r)), NF.fmt(Prog.pill_exp(r, 0)), NF.fmt(Prog.pill_exp(r, 3)),
				NF.fmt(Prog.overlord_exp(r)), NF.fmt1(Prog.med_rate(r)), NF.fmt(Prog.insight_cap(r))])
	for v: float in [0.0, 37.0, 9999.0, 12345.0, 99995000.0, 123456789.0, 6.63e12, -45678.0]:
		print("[core] fmt %s → %s" % [str(v), NF.fmt(v)])
	print("[core] PvP 同境一单位 %.1f 点，高 2 境 %.1f，低 2 境 %.1f" % [CS.pvp_hit(CS.base(3), 3, 3), CS.pvp_hit(CS.base(5), 5, 3), CS.pvp_hit(CS.base(3), 3, 5)])
	print("[core] 溢出上限 炼气 %s（瓶颈级 %s + 筑基总量 %s）" % [NF.fmt(Prog.overflow_cap(0)), NF.fmt(Prog.xp_need(3)), NF.fmt(Prog.realm_total(1))])
	quit()
