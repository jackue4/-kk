extends SceneTree
## 灵种背包 / 收获提示用的灵植图标（2026-11-23）：每种灵植的成熟模型，3/4 俯视、透明底，一张 512 见方。
## 用法：run_hidden.py <proj> <log> --resolution 512x512 -s res://_tasks/plant_icons.gd -- <输出目录>；之后 make_icons.py 裁边、加墨线描边、缩成 256 放进 assets/plants/icons/

const FarmData := preload("res://scripts/farm_data.gd")
const FarmPlots := preload("res://scripts/farm_plots.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.98, 0.95)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = e
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.95, 0.55, 0.0)
	sun.light_energy = 1.05
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 24.0
	vp.add_child(cam)
	cam.current = true
	var fp: Node3D = FarmPlots.new()
	for p: Dictionary in FarmData.PLANTS:
		var key := str(p["ripe"][0])
		var holder := Node3D.new()
		vp.add_child(holder)
		var node: Node3D = fp.call("_instance", key, holder)
		var boxes: Dictionary = FarmPlots._boxes
		var b: AABB = boxes.get(key, AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE))
		if node != null:
			node.position = -b.get_center()
		var r := b.size.length() * 0.5
		var dir := Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, -0.42) * Vector3(0.0, 0.0, 1.0)
		cam.position = dir * (r / sin(deg_to_rad(cam.fov * 0.5)) * 1.02)
		cam.look_at(Vector3.ZERO)
		for f in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out + "/%s.png" % str(p["id"]))
		holder.queue_free()
		await process_frame
	fp.free()
	print("[icons] %d" % FarmData.PLANTS.size())
	quit()
