extends SceneTree
## 模型定妆：把 assets/creatures 里的模型排成几排拍下来（_shots/preview/gal_<页>.jpg），看朝向、大小、贴图。
## 每个模型缩到 2 米高、脚踩地，脚前（-Z，游戏里的正面）放一个红色小块；镜头在 -Z 一侧，看到的应该是正脸。
## 用法：godot --path . -s res://_tasks/creature_gallery.gd [-- 模型名 …]

const Models := preload("res://scripts/creature_model.gd")
const PER := 6


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots/preview"))
	var keys: Array = []
	for a in OS.get_cmdline_user_args():
		keys.append(a)
	var role := "idle"
	if not keys.is_empty() and str(keys[0]).begins_with("@"):
		role = str(keys.pop_front()).substr(1)
	if keys.is_empty():
		var d := DirAccess.open(Models.DIR)
		for f in d.get_files():
			if f.ends_with(".glb"):
				keys.append(f.get_basename())
		keys.sort()
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.5, 0.56)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 2.6, 0)
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.36, 0.3)
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.position = Vector3(0, 3.2, -15.5)
	cam.look_at(Vector3(0, 1.1, 0))
	var page := 0
	var i := 0
	while i < keys.size():
		var holder := Node3D.new()
		world.add_child(holder)
		var n := mini(PER, keys.size() - i)
		for j in n:
			var key := str(keys[i + j])
			var slot := Node3D.new()
			holder.add_child(slot)
			slot.position = Vector3((float(j) - float(n - 1) * 0.5) * -3.4, 0, 0)
			slot.rotation.y = -0.5   # 稍微侧一点，看得出体型
			var body := Node3D.new()
			slot.add_child(body)
			var info := Models.place(key, body, true)
			var txt := key
			if not info.is_empty():
				var bb: AABB = info["aabb"]
				var k := 2.0 / maxf(bb.size.y, 0.001)
				k = minf(k, 2.8 / maxf(maxf(bb.size.x, bb.size.z), 0.001))
				body.scale = Vector3.ONE * k
				body.position.y = -bb.position.y * k
				var clips: Dictionary = info["clips"]
				txt += "\n%.1f×%.1f×%.1f\n%s" % [bb.size.x, bb.size.y, bb.size.z, " ".join(clips.keys())]
				if role != "idle" and clips.has(role):
					(info["anim"] as AnimationPlayer).play(str(clips[role]))
				print("[gal] %s 尺寸 %s 动画 %s 时长 %s" % [key, bb.size, clips, _lens(info)])
			var mark := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.25, 0.1, 0.25)
			mark.mesh = bm
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(1, 0.15, 0.1)
			mark.material_override = mm
			mark.position = Vector3(0, 0.05, -1.7)
			slot.add_child(mark)
			var l := Label3D.new()
			l.text = txt
			l.font_size = 36
			l.pixel_size = 0.008
			l.outline_size = 8
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.position = Vector3(0, 3.6, 0)
			slot.add_child(l)
		await create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(1000, int(1000.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
		img.save_jpg("res://_shots/preview/gal_%s_%d.jpg" % [role, page], 0.88)
		print("[shot] gal_%s_%d" % [role, page])
		holder.queue_free()
		await process_frame
		i += n
		page += 1
	quit()


func _lens(info: Dictionary) -> Dictionary:
	var out := {}
	var anim := info["anim"] as AnimationPlayer
	if anim == null:
		return out
	var clips: Dictionary = info["clips"]
	for r: String in clips:
		out[r] = snappedf(anim.get_animation(str(clips[r])).length, 0.01)
	return out
