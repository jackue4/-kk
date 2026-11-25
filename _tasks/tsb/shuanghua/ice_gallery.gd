extends SceneTree
## 冰的体块小样：把 kit_shuanghua.gd 的几种冰网格摆出来截一张（不起主场景）。
## 用法：python -I _tasks/trailer/run_hidden.py . <日志> --resolution 1280x720 -s res://_tasks/tsb/shuanghua/ice_gallery.gd [--rendering-method gl_compatibility]
const Kit := preload("res://scripts/heroes/kit_shuanghua.gd")

func _init() -> void:
	var root3 := Node3D.new()
	get_root().add_child(root3)
	Vfx.root = root3
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	env.environment = e
	root3.add_child(env)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 4.5, 17.0), Vector3(0.0, 2.2, 0.0))
	cam.fov = 50.0
	cam.make_current()
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80.0, 80.0)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.42, 0.4, 0.36)
	floor.material_override = fm
	root3.add_child(floor)
	# 一个人那么高的参照柱
	var man := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.75, 0.4)
	man.mesh = bm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.8, 0.3, 0.25)
	man.material_override = mm
	man.position = Vector3(-9.0, 0.875, 2.0)
	root3.add_child(man)
	Kit._ice(Kit._claw_mesh(), Vector3(-10.5, 1.5, 4.0), Vector3.FORWARD, 3.0, 0.88)
	Kit._ice(Kit._lance_mesh(), Vector3(-7.5, 2.4, 3.0), Vector3.LEFT, 1.0, 0.88)
	for i in 3:
		Kit._ice(Kit._spike_mesh(i), Vector3(-5.5 + 2.2 * float(i), 0.0, 3.0), Vector3.FORWARD, 1.0)
	Kit._ice(Kit._cage_mesh(), Vector3(-9.0, 1.05, 2.0), Vector3.FORWARD, 1.0, 0.46, 0.7)
	Kit._ice(Kit._prison_mesh(), Vector3(4.5, 0.0, 2.0), Vector3.FORWARD, 1.0, 0.6, 0.6)
	Kit._ice(Kit._lotus_mesh(), Vector3(2.0, 0.0, -10.0), Vector3.FORWARD, 1.0, 0.6, 0.55)
	_shoot.call_deferred()


func _shoot() -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var gl := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	img.save_jpg("res://_shots/preview/tsb_shuanghua_ice%s.jpg" % ("_gl" if gl else ""), 0.9)
	print("[shot] tsb_shuanghua_ice")
	quit()
