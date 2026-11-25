extends SceneTree
## 主场景这会儿起不起得来（主线 / 别的分支同时在改脚本）：Godot --headless --path . -s res://_tasks/destruct/main_ok.gd
func _init() -> void:
	var ms: Variant = load("res://scripts/main.gd")
	var ok: bool = ms != null and (ms as GDScript).can_instantiate()
	print("[main_ok] ", "ok" if ok else "FAILED")
	quit(0 if ok else 1)
