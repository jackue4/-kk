extends SceneTree
## 载入 scripts/ 和 _tasks/numbers_sim/ 下所有脚本，报告编不过的
func _init() -> void:
	var bad := 0
	var n := 0
	for dir: String in ["res://scripts/", "res://_tasks/numbers_sim/", "res://_tasks/numbers_rework_20261123/"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f: String in d.get_files():
			if not f.ends_with(".gd") or f == "check_all.gd":
				continue
			n += 1
			var s: Variant = load(dir + f)
			if s == null or not (s as GDScript).can_instantiate():
				bad += 1
				print("[all] FAILED ", dir + f)
	print("[all] %d 个脚本，%d 个编不过" % [n, bad])
	quit(1 if bad > 0 else 0)
