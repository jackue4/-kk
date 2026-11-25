extends SceneTree
## 体块小样：把 hero_fx.gd 的拳印从几个角度摆出来截一张（不起主场景）。
## 用法：python -I _tasks/trailer/run_hidden.py . <日志> --resolution 1280x720 -s res://_tasks/tsb/fx_gallery.gd [-- --gl]
const HeroFx := preload("res://scripts/hero_fx.gd")

func _init() -> void:
	var root3 := Node3D.new()
	get_root().add_child(root3)
	Vfx.root = root3
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	env.environment = e
	root3.add_child(env)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 2.2, 10.0), Vector3(0.0, 0.9, 0.0))
	cam.fov = 50.0
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40.0, 40.0)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.4, 0.42, 0.45)
	floor.material_override = fm
	floor.position.y = -1.2
	root3.add_child(floor)
	var gold := Color(1.0, 0.74, 0.28)
	var line := Color(0.42, 0.24, 0.06, 0.85)
	# 四个朝向：朝左、朝镜头、背对镜头、朝右上
	var dirs := [Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3(1.0, 0.5, 0.2), Vector3.DOWN]
	for i in dirs.size():
		var p := Vector3(-6.0 + 3.0 * float(i), 0.4, 0.0)
		HeroFx.block(HeroFx.fist_mesh(), p, dirs[i], Color.WHITE.lerp(gold, 0.8), 1.6, 0.85, false, line)
	HeroFx.block(HeroFx.cube_mesh(), Vector3(-6.0, 2.6, 0.0), Vector3.FORWARD, Color(0.5, 0.47, 0.42), 1.0, 1.0)
	HeroFx.block(HeroFx.fist_mesh(), Vector3(0.0, 3.0, -2.0), Vector3.LEFT, Color.WHITE.lerp(gold, 0.8), 2.6, 0.56, false, line)
	cam.make_current()
	_shoot.call_deferred()


func _shoot() -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var gl := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	img.save_jpg("res://_shots/preview/tsb_fx_gallery%s.jpg" % ("_gl" if gl else ""), 0.9)
	print("[shot] tsb_fx_gallery")
	quit()
