extends SceneTree
## 境界光环特效（第二版，realm_halo.gd）的定妆：每档拍两张 —— 左：从正面看（光环在人身后，和原画的构图一个意思）；
## 右：游戏里的镜头（在人身后 8 米、略高），这时光环在镜头和人之间，看人有没有被盖住。
## 用法：python _tasks/trailer/run_hidden.py . <日志前缀> --resolution 1600x900 [--rendering-method gl_compatibility]
##        -s res://_tasks/realm_halo/halo_fx_gallery.gd [-- --tiers=1,2,…] [--bg=sky|dark|pink|grass] [--tag=前缀] [--unfold]
## --unfold：拍展开到一半的样子。输出 _tasks/realm_halo/shots/<tag>_<n>.jpg 和 <tag>_sheet.jpg（python 另拼）。

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const RealmHalo := preload("res://scripts/realm_halo.gd")

const BGS := {"sky": Color(0.5, 0.62, 0.82), "dark": Color(0.1, 0.11, 0.17), "pink": Color(0.9, 0.7, 0.74), "grass": Color(0.42, 0.62, 0.36)}

var _cam: Camera3D
var _out := "res://_tasks/realm_halo/shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tiers: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	var bg := "sky"
	var tag := "fx"
	var unfold := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tiers="):
			tiers = []
			for x in a.substr(8).split(","):
				tiers.append(int(x))
		elif a.begins_with("--bg="):
			bg = a.substr(5)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a == "--unfold":
			unfold = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BGS.get(bg, BGS["sky"])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.97, 0.98)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true            # 桌面档游戏里是开着泛光的
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 2.4, 0)
	sun.light_energy = 0.7
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = (BGS.get(bg, BGS["sky"]) as Color).darkened(0.35)
	floor_mi.material_override = fm
	world.add_child(floor_mi)
	# 背景用一个翻面的大球：兼容渲染器开着泛光时，纯色背景会被读成白的，用几何体垫着两档才可比
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 90.0
	sm.height = 180.0
	sm.flip_faces = true
	dome.mesh = sm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = BGS.get(bg, BGS["sky"])
	dome.material_override = dm
	world.add_child(dome)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	world.add_child(_cam)
	_cam.make_current()
	print("[halo-fx] 渲染器 ", RenderingServer.get_current_rendering_method(), " 底色 ", bg)
	for t: int in tiers:
		var slot := Node3D.new()
		world.add_child(slot)
		var h: VoxelHero = VoxelHero.new({}, true, false, t - 1, HeroSkin.player_key())
		slot.add_child(h)
		var halo: Node3D = RealmHalo.make(t - 1)
		var pl: Dictionary = RealmHalo.place(t - 1)
		slot.add_child(halo)
		halo.position = Vector3(0.0, float(pl["cy"]), float(pl["dist"]))      # 人朝 -Z，背后是 +Z
		halo.call("set_power", 1.0)
		if unfold:
			halo.call("play_in")
		for f in (28 if unfold else 70):
			h.animate(1.0 / 60.0, 0.0, 0.0, false, true)
			await process_frame
		var cy := float(pl["cy"])
		# 正面：镜头在人前方，略低一点往上看
		var a := await _shot(Vector3(0.5, cy * 0.85, -2.6 - cy * 1.55), Vector3(0.0, cy * 0.9, 0.6))
		# 游戏镜头：人身后 8 米、高 3.2 米
		var b := await _shot(Vector3(0.0, 3.4, 8.2), Vector3(0.0, 1.5, 0.0))
		var out := Image.create(a.get_width() * 2, a.get_height(), false, Image.FORMAT_RGB8)
		out.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
		out.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width(), 0))
		out.save_jpg("%s/%s_%d.jpg" % [_out, tag, t], 0.9)
		print("[halo-fx] 第 %d 档：中心高 %.2f 米、离背后 %.2f 米，%d 个节点" % [t, cy, float(pl["dist"]), halo.get_child_count()])
		slot.queue_free()
		await process_frame
	quit()


func _shot(eye: Vector3, target: Vector3) -> Image:
	_cam.position = eye
	_cam.look_at(target)
	for f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	# 中间裁一个方块
	var s := img.get_height()
	var sq := img.get_region(Rect2i((img.get_width() - s) / 2, 0, s, s))
	sq.resize(700, 700, Image.INTERPOLATE_LANCZOS)
	return sq
