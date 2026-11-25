extends SceneTree
## 语法 / 类型自检：把场景破坏改到的脚本挨个载入一遍（警告当错误的工程里，载不进来就是有错）
func _init() -> void:
	var bad := 0
	for p: String in ["res://scripts/destruct_fx.gd", "res://scripts/destruct.gd", "res://scripts/ex/grid_world.gd", "res://scripts/ex/ex_level.gd",
			"res://scripts/net.gd", "res://scripts/arena_net.gd", "res://scripts/meadow_level.gd", "res://scripts/block_world.gd",
			"res://scripts/arena_floor.gd", "res://scripts/hub_arena.gd", "res://scripts/hub_hall.gd", "res://scripts/arena_duel.gd"]:
		var s: Variant = load(p)
		var ok: bool = s != null and (s as GDScript).can_instantiate()
		print("[check] ", p, " ", "ok" if ok else "FAILED")
		if not ok:
			bad += 1
	quit(1 if bad > 0 else 0)
