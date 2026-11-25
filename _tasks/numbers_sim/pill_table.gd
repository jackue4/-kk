extends SceneTree
## 各区域、各深度掉出来的修为丹平均药力 / 品质分布（直接调 raid_items.gd 的 roll）：
##   godot --headless --path . -s res://_tasks/numbers_sim/pill_table.gd [-- --n=40000]
## 2026-11-23 数值重构（照 Hammer 的精魄）：修为丹按境界锁（本境丹只有正处在该境界才能服，霸主精魄 ≥ min_realm 能服），药力一律按
## Items.pill_exp_now 现算。表一按境界：该境界常去的区域、常打的怪那一档深度（同 life_sim / --pace-byrealm）掉的丹，
## 有几成是自己能服的、平均药力、一颗占本境界总修为的百分比；表二按区域 × 深度，看掉的是哪个境界的丹。

const Prog := preload("res://scripts/progression.gd")
const Items := preload("res://scripts/raid_items.gd")
const Data := preload("res://scripts/raid_data.gd")
const NumFmt := preload("res://scripts/num_fmt.gd")

const NAMES := ["炼气", "筑基", "结丹", "元婴", "化神", "炼虚", "合体", "大乘"]


## 境界 r 常打的怪所在的深度（同 life_sim：Prog.REALM_MOB_LV 反推）
static func realm_depth(r: int) -> float:
	var ri: int = Prog.REALM_REGION[r]
	return clampf(float(Prog.REALM_MOB_LV[r] - int(Data.REGIONS[ri]["lv"])) / float(Prog.DEPTH_LV[ri]), 0.0, 1.0)


func _pill_realm(it: Dictionary) -> int:
	return int(it.get("min_realm", it.get("realm", -1)))


func _init() -> void:
	var n_roll := 40000
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n_roll = int(a.get_slice("=", 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# ---------- 表一：按境界 ----------
	print("[pill] —— 按境界（该境界常去的区域、常打的怪那一档深度，每次 %d 件掉落）——" % n_roll)
	for r in 8:
		var ri: int = Prog.REALM_REGION[r]
		var depth := realm_depth(r)
		var n := 0
		var usable := 0
		var sum := 0.0
		var grades := [0, 0, 0, 0]
		var by_realm := {}
		for i in n_roll:
			for it: Dictionary in Items.roll(ri, 1, rng, 0.0, depth):
				if str(it["kind"]) != "pill" or not Items.is_xp_pill(it):
					continue
				n += 1
				var pr := _pill_realm(it)
				by_realm[pr] = int(by_realm.get(pr, 0)) + 1
				if Prog.pill_use_err(it, r) == "":
					usable += 1
					sum += Items.pill_exp_now(it, r)
					grades[clampi(int(it.get("grade", 0)), 0, 3)] += 1
		var tot := Prog.realm_total(r)
		var avg := sum / maxf(float(usable), 1.0)
		var gp: Array = grades.map(func(c: int) -> String: return "%d%%" % roundi(100.0 * float(c) / maxf(float(usable), 1.0)))
		var br: Array = []
		var ks: Array = by_realm.keys()
		ks.sort()
		for k: Variant in ks:
			br.append("%s %d%%" % [NAMES[clampi(int(k), 0, 7)] if int(k) >= 0 else "老丹", roundi(100.0 * float(by_realm[k]) / maxf(float(n), 1.0))])
		print("[pill] %s（%s 深度 %.3f，怪 %d 级）：每件掉落是修为丹 %.1f%%，其中自己能服 %d%%（%s）；能服的平均药力 %s = 本境界总修为 %s 的 %.2f%%，品质 下 / 中 / 上 / 极 = %s" % [
				NAMES[r], Data.REGIONS[ri]["name"], depth, Prog.mob_level(ri, depth), 100.0 * float(n) / float(n_roll), roundi(100.0 * float(usable) / maxf(float(n), 1.0)),
				"、".join(br), NumFmt.fmt(avg), NumFmt.fmt(tot), 100.0 * avg / maxf(tot, 1.0), " / ".join(gp)])
		var ov := Items.overlord(r)
		print("[pill]   %s：下品 %s（%.2f%%）/ 极品 %s（%.2f%%）；霸主精魄「%s」%s（%.2f%%），巢穴首领遗藏里多掉一颗的几率 %d%%" % [
				NAMES[r], NumFmt.fmt(Prog.pill_exp(r, 0)), 100.0 * Prog.pill_exp(r, 0) / tot, NumFmt.fmt(Prog.pill_exp(r, 3)), 100.0 * Prog.pill_exp(r, 3) / tot,
				str(ov.get("name", "")), NumFmt.fmt(Items.pill_exp_now(ov, r)), 100.0 * Items.pill_exp_now(ov, r) / tot, roundi(100.0 * Prog.OVERLORD_P[r])])
	# ---------- 表二：按区域 × 深度 ----------
	print("[pill] —— 按区域 × 深度（掉的是哪个境界的丹；平均药力按丹自己的境界算）——")
	for ri in 5:
		for depth: float in [0.0, 0.35, 0.8, 1.0]:
			var n := 0
			var sum := 0.0
			var by_realm := {}
			for i in n_roll:
				for it: Dictionary in Items.roll(ri, 1, rng, 0.0, depth):
					if str(it["kind"]) == "pill" and Items.is_xp_pill(it):
						n += 1
						var pr := _pill_realm(it)
						by_realm[pr] = int(by_realm.get(pr, 0)) + 1
						sum += Items.pill_exp_now(it, maxi(pr, 0))
			var br: Array = []
			var ks: Array = by_realm.keys()
			ks.sort()
			for k: Variant in ks:
				br.append("%s %d%%" % [NAMES[clampi(int(k), 0, 7)] if int(k) >= 0 else "老丹", roundi(100.0 * float(by_realm[k]) / maxf(float(n), 1.0))])
			print("[pill] %s 深度 %.2f（怪 %d 级、%s档）：每件掉落是修为丹 %.1f%%，平均药力 %s，境界 %s" % [Data.REGIONS[ri]["name"], depth, Prog.mob_level(ri, depth),
					NAMES[Prog.pill_realm_at(ri, depth)], 100.0 * float(n) / float(n_roll), NumFmt.fmt(sum / maxf(float(n), 1.0)), "、".join(br)])
	quit()
