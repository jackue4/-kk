extends SceneTree
## 模型自带动画的定格连拍：每段动画一排，从左到右是这一段里均匀取的几个时刻；正面 / 侧面各拍一张。
## 用来看原生动画本身长什么样（原地不原地、离不离地、手臂开不开），不经过游戏里的骨架。
## 用法：python _tasks/trailer/run_hidden.py . <日志前缀> --resolution 1600x900 -s res://_tasks/hero_skin/anim_preview.gd [-- --out=<目录>] [--model=<模型名，默认 aladeng>]
## 图片名：anim_<模型名>_<动画>_front / side / back.jpg（阿拉灯沿用老名字，不带模型名）

const N := 7

var _out := "res://_tasks/hero_skin/shots"
var _model := "aladeng"
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a.begins_with("--model="):
			_model = a.substr(8)
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
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.36, 0.3)
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	world.add_child(_cam)
	var ps := load("res://assets/hero/%s.glb" % _model) as PackedScene
	var tag := "" if _model == "aladeng" else _model + "_"
	var names: Array = []
	var probe := ps.instantiate()
	for ap: AnimationPlayer in probe.find_children("*", "AnimationPlayer", true, false):
		names = Array(ap.get_animation_list())
	probe.free()
	_cam.fov = 38.0
	for nm: String in names:
		var holder := Node3D.new()
		world.add_child(holder)
		var models: Array = []
		for i in N:
			var m := ps.instantiate() as Node3D
			holder.add_child(m)
			m.position = Vector3((float(i) - float(N - 1) * 0.5) * -1.7, 0.0, 0.0)
			var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			var len := ap.get_animation(nm).length
			ap.play(nm)
			ap.seek(len * float(i) / float(N), true)
			ap.pause()
			models.append(m)
		for f in 4:
			await process_frame
		await _shot("anim_%s%s_front" % [tag, nm], Vector3(0.0, 1.7, -9.0), Vector3(0.0, 0.85, 0.0))
		for m: Node3D in models:
			m.rotation.y = -PI * 0.5      # 转成侧面对着镜头（脸朝画面左边）
		await _shot("anim_%s%s_side" % [tag, nm], Vector3(0.0, 1.7, -9.0), Vector3(0.0, 0.85, 0.0))
		for m: Node3D in models:
			m.rotation.y = PI
		await _shot("anim_%s%s_back" % [tag, nm], Vector3(0.0, 2.6, -9.0), Vector3(0.0, 0.85, 0.0))
		holder.queue_free()
		await process_frame
	quit()


func _shot(name: String, eye: Vector3, target: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(target)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(1500, int(1500.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_jpg("%s/%s.jpg" % [_out, name], 0.9)
	print("[shot] ", name)
