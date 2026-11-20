extends SceneTree
## 各区域、各深度掉出来的修为丹平均药力 / 品阶分布（直接调 raid_items.gd 的 roll）：
##   godot --headless --path . -s res://_tasks/numbers_sim/pill_table.gd

const Prog := preload("res://scripts/progression.gd")
const Items := preload("res://scripts/raid_items.gd")
const Data := preload("res://scripts/raid_data.gd")


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for ri in 5:
		for depth: float in [0.0, 0.35, 0.8, 1.0]:
			var n := 0
			var sum := 0.0
			var tiers := [0, 0, 0, 0, 0]
			for i in 40000:
				for it: Dictionary in Items.roll(ri, 1, rng, 0.0, depth):
					if str(it["kind"]) == "pill" and Items.is_xp_pill(it):
						n += 1
						sum += float(it["exp"])
						tiers[int(it["tier"])] += 1
			var pct: Array = tiers.map(func(c: int) -> String: return "%d%%" % roundi(100.0 * float(c) / maxf(float(n), 1.0)))
			print("[pill] %s 深度 %.2f：每件掉落是修为丹 %.1f%%，平均药力 %.0f，品阶 %s" % [Data.REGIONS[ri]["name"], depth, 100.0 * float(n) / 40000.0, sum / maxf(float(n), 1.0), " / ".join(pct)])
	quit()
