extends SceneTree
## 各境界常去的地方掉的东西：修为丹（能服的）/ 其它 各占多少件、多少价值（看灵石为什么不够）
const Items := preload("res://scripts/raid_items.gd")
const Prog := preload("res://scripts/progression.gd")
const Data := preload("res://scripts/raid_data.gd")
func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for r in 8:
		var ri: int = Prog.REALM_REGION[r]
		var dep := clampf(float(Prog.REALM_MOB_LV[r] - int(Data.REGIONS[ri]["lv"])) / float(Prog.DEPTH_LV[ri]), 0.0, 1.0)
		var cnt := {}
		var val := {}
		for i in 4000:
			for it: Dictionary in Items.roll(ri, 1, rng, 0.0, dep):
				var k := str(it["kind"])
				if k == "pill" and Items.is_xp_pill(it):
					k = "pill_ok" if Prog.pill_use_err(it, r) == "" else "pill_no"
				cnt[k] = int(cnt.get(k, 0)) + 1
				val[k] = float(val.get(k, 0.0)) + float(it["value"]) * Prog.value_mult(dep)
		var s := ""
		for k: String in cnt.keys():
			s += "%s %d件 均价%.0f  " % [k, cnt[k], float(val[k]) / float(cnt[k])]
		print("[mix] 境界%d 区%d 深%.2f：%s" % [r, ri, dep, s])
	quit()
