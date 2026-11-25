extends SceneTree
## 现在的修为丹：每颗药力、占比、投放（headless）
const Items := preload("res://scripts/raid_items.gd")
const Prog := preload("res://scripts/progression.gd")
const Data := preload("res://scripts/raid_data.gd")
const NF := preload("res://scripts/num_fmt.gd")
func _init() -> void:
	var nm := ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"]
	for r in 8:
		var tot := Prog.realm_total(r)
		var lv1 := Prog.xp_need(3 * r + 1)
		var s := ""
		for g in 4:
			s += "%s %s(%.2f%%)  " % [Prog.GRADE_NAMES[g], NF.fmt(Prog.pill_exp(r, g)), 100.0 * Prog.pill_exp(r, g) / tot]
		print("[pill] %s %s：%s｜霸主 %s(%.1f%%) 掉率 %.0f%%｜第一级要 %s" % [nm[r], Items.PILL_NAMES[r], s, NF.fmt(Prog.overlord_exp(r)), 100.0 * Prog.overlord_exp(r) / tot, 100.0 * Prog.OVERLORD_P[r], NF.fmt(lv1)])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for d: float in [0.0, 0.35, 1.0]:
		var c := [0, 0, 0, 0]
		for i in 4000:
			c[Prog.roll_grade(d, rng)] += 1
		print("[grade] 深度 %.2f：下 %d%% 中 %d%% 上 %d%% 极 %d%%" % [d, c[0] / 40, c[1] / 40, c[2] / 40, c[3] / 40])
	for ri in 5:
		var s2 := ""
		for d: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			s2 += "深%.2f→%s  " % [d, nm[Prog.pill_realm_at(ri, d)]]
		print("[where] %s：%s" % [Data.REGIONS[ri]["name"], s2])
	var n := 0
	var p := 0
	for i in 20000:
		for it: Dictionary in Items.roll(0, 1, rng, 0.0, 0.3):
			n += 1
			if Items.is_xp_pill(it):
				p += 1
	print("[drop] 每件掉落是修为丹的概率 %.1f%%" % (100.0 * p / n))
	quit()
