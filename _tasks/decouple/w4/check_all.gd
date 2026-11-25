extends SceneTree
## W4（主干解耦）：把 scripts/ 下所有 .gd 挨个 load 一遍，载不进来 / 不能实例化的就是有解析或编译错误。
## 用法：Godot --headless --path . -s res://_tasks/decouple/w4/check_all.gd
## 只读，不建节点、不碰存档。

func _init() -> void:
	var files: Array = []
	var roots: Array = Array(OS.get_cmdline_user_args())      # -- res://_tasks/ui_kit ... 额外的目录
	if roots.is_empty():
		roots = ["res://scripts"]
	for r: String in roots:
		_walk(r, files)
	files.sort()
	var bad: Array = []
	for p: String in files:
		var s: Variant = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
		var ok: bool = s != null and s is GDScript and (s as GDScript).can_instantiate()
		if not ok:
			bad.append(p)
	print("[check_all] %d 个脚本，载不进来 %d 个" % [files.size(), bad.size()])
	for p: String in bad:
		print("[check_all] FAILED ", p)
	quit(1 if not bad.is_empty() else 0)


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub: String in d.get_directories():
		_walk(dir.path_join(sub), out)
