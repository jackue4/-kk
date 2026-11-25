extends SceneTree
## 灵草候选小样（2026-11-23）：把 H:\游戏资源\miniw_assets 里挑出来的植物 / 作物 / 道具 GLB 运行时读进来，一个模型拍一格。
## 用法：run_hidden.py <proj> <log> --resolution 480x480 -s res://_tasks/herb_gallery.gd -- <herb_list.json> <输出目录>
## 输出 <页>_<序号>.png 和 tiles.tsv（页、名字、原始包围盒尺寸），拼图和写字交给 Python。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var out_dir := args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var holder := Node3D.new()
	root.add_child(holder)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.88, 0.89, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.8
	env.environment = e
	holder.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.light_energy = 1.1
	holder.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 2.2, 5.0)
	cam.rotation = Vector3(-0.42, 0.0, 0.0)
	holder.add_child(cam)
	cam.current = true
	var log_lines: Array[String] = []
	for page: String in ["A", "B", "I"]:
		var items: Array = data[page]
		for i in items.size():
			var it: Array = items[i]
			var node := _load(str(it[1]))
			var info := "%s\t%03d\t%s\t" % [page, i, str(it[0])]
			if node == null:
				log_lines.append(info + "fail")
				continue
			holder.add_child(node)
			var ab := _aabb(node)
			var s := 1.6 / maxf(maxf(ab.size.x, ab.size.z), maxf(ab.size.y, 0.001))
			node.scale = Vector3.ONE * s
			var c := ab.get_center() * s
			node.position = Vector3(-c.x, -ab.position.y * s - 0.75, -c.z)
			for k in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir + "/%s_%03d.png" % [page, i])
			log_lines.append(info + "%.2f x %.2f x %.2f" % [ab.size.x, ab.size.y, ab.size.z])
			node.queue_free()
			await process_frame
	var f := FileAccess.open(out_dir + "/tiles.tsv", FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	print("[herb] tiles %d" % log_lines.size())
	quit()


func _load(p: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(p, st) != OK:
		return null
	return doc.generate_scene(st) as Node3D


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = vi
		while p != null and p != n.get_parent():
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * vi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
