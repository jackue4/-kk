extends SceneTree
## 策划文档用：每级修为需求 / 吃几颗丹升级 / 杀怪心得（headless）
const Prog := preload("res://scripts/progression.gd")
const Data := preload("res://scripts/raid_data.gd")
const NF := preload("res://scripts/num_fmt.gd")
func _init() -> void:
	var nm := ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"]
	for r in 8:
		print("[realm] %d|%s|%s|%d" % [r, nm[r], NF.fmt(Prog.realm_total(r)), int(Prog.realm_total(r))])
	for lv in range(1, 31):
		var r := Prog.realm_of(lv)
		var need := Prog.xp_need(lv)
		var s := ""
		for g in 4:
			s += "|%d" % int(ceilf(need / Prog.pill_exp(r, g)))
		var ins := Prog.insight(Prog.REALM_MOB_LV[r], 1.0, Prog.REALM_REGION[r])
		print("[lv] %d|%s|%s|%d%s|%d|%s" % [lv, nm[r], NF.fmt(need), int(need), s, int(ceilf(need / ins)), NF.fmt(Prog.overlord_exp(r))])
	for ri in 5:
		var seen := {}
		for d: float in [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]:
			var lv := Prog.mob_level(ri, d)
			if seen.has(lv):
				continue
			seen[lv] = true
			var t := Prog.mob_tag(ri, lv)
			var b := Prog.insight(lv, 1.0, ri)
			print("[mob] %s|%.3f|%d|%s|%s|%s|%s|%s|%s|%s" % [Data.REGIONS[ri]["name"], d, lv, nm[t], NF.fmt(b), NF.fmt(b * 0.9), NF.fmt(b * 2.4), NF.fmt(b * 3.0), NF.fmt(b * 14.0), NF.fmt(b * 5.0)])
	for r in 8:
		var ins := Prog.insight(Prog.REALM_MOB_LV[r], 1.0, Prog.REALM_REGION[r])
		print("[cap] %s|%d|%s|%s|%s|%s|%s" % [nm[r], Prog.REALM_MOB_LV[r], Data.REGIONS[Prog.REALM_REGION[r]]["name"], NF.fmt(ins), NF.fmt(Prog.insight_cap(r)), NF.fmt(Prog.med_rate(r) * 60.0), NF.fmt(Prog.med_rate(r) * 3600.0 * Prog.OFFLINE_RATE)])
	quit()
