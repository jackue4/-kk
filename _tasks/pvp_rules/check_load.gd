extends SceneTree
## 语法 / 类型自检：把这次改到的脚本挨个载入一遍（警告当错误的工程里，载不进来就是有错）
func _init() -> void:
	var bad := 0
	for f: String in ["air_moves", "air_melee", "remote_player", "net", "arena_net", "raid_manager", "arena_duel", "arena_selftest", "touch_controls", "pvp_rules_selftest"]:
		var p := "res://scripts/%s.gd" % f
		if not FileAccess.file_exists(p):
			print("[check] 没有 ", p)
			continue
		var s: Variant = load(p)
		var ok: bool = s != null and (s as GDScript).can_instantiate()
		print("[check] ", f, " ", "ok" if ok else "FAILED")
		if not ok:
			bad += 1
	quit(1 if bad > 0 else 0)
