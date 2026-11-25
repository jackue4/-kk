extends SceneTree
## T_maps 额外自检的启动器（不进包）：正常开机 main.tscn，再挂 maps_probe.gd（继承 xiu_map_selftest.gd 的工具函数）。
## 用法：Godot --headless --path . -s res://_tasks/decouple/t_maps/maps_run.gd -- --qa-maps=desert|lab
## --qa-maps 不在 raid_profile.PLAY_ARGS 里 → 测试存档，正式存档不碰。

var m: Node


func _initialize() -> void:
	var map_id := "desert"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--qa-maps="):
			map_id = a.get_slice("=", 1)
	m = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(m)
	var p: Node = (load("" + _probe() + "") as GDScript).new()
	p.set("m", m)
	p.set("arg", map_id)
	root.add_child.call_deferred(p)
	_set_scene.call_deferred()


func _probe() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--qa-probe="):
			return "res://_tasks/decouple/t_maps/%s.gd" % a.get_slice("=", 1)
	return "res://_tasks/decouple/t_maps/maps_probe.gd"


func _set_scene() -> void:
	current_scene = m
