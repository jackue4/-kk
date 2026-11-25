extends SceneTree
## 姿势小样（苍鸿重构用）：把若干个关键姿势各摆一个持剑的人，上排从正前斜侧看、下排从背后斜侧看（游戏里镜头在背后）。
## 用法：python -I _tasks/trailer/run_hidden.py . <日志> --resolution 1600x900 -s res://_tasks/tsb/canghong/pose_gallery.gd -- --poses=a,b,c [--tag=x] [--hero=canghong]
## 姿势名是 combat_poses.gd / 姿势包里 DEF 的名字（关键姿势，不是时间轴）。
const HeroDefs := preload("res://scripts/hero_defs.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")

var names: Array = []
var tag := "a"
var hid := "canghong"
var rigs: Array = []
var heroes: Array = []


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--poses="):
			names = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--tag="):
			tag = a.get_slice("=", 1)
		elif a.begins_with("--hero="):
			hid = a.get_slice("=", 1)
	var root3 := Node3D.new()
	get_root().add_child(root3)
	Vfx.root = root3
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.8
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0.0)
	sun.light_energy = 0.8
	root3.add_child(sun)
	var n := names.size()
	var gap := 2.3
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(gap * float(n) * 9.0 / 16.0, 6.4)
	cam.look_at_from_position(Vector3(0.0, 2.4, 20.0), Vector3(0.0, 2.4, 0.0))
	cam.make_current()
	var def := HeroDefs.def_of(hid)
	for row in 2:
		for i in n:
			var slot := Node3D.new()
			root3.add_child(slot)
			slot.position = Vector3((float(i) - float(n - 1) * 0.5) * gap, 3.3 if row == 0 else 0.3, 0.0)
			slot.rotation.y = 2.55 if row == 0 else 0.55
			var spin := Node3D.new()
			spin.position.y = 0.9
			slot.add_child(spin)
			var hero := VoxelHero.new({}, true, false, HeroDefs.TIER, HeroSkin.hero_key(str(def.get("skin", ""))))
			hero.position.y = -0.9
			var hold := Node3D.new()
			hold.position.y = -0.9
			spin.add_child(hold)
			hold.add_child(hero)
			var weapon: Node3D
			if bool(def.get("blade_always", false)):
				weapon = MeshLib.make_sword(def.get("sword_glow", Color(0.5, 0.8, 1.0)) as Color)
				var bmat := weapon.get_meta("blade_mat") as StandardMaterial3D
				if bmat != null:
					bmat.albedo_color = def.get("sword_col", Color(0.86, 0.9, 0.95)) as Color
			else:
				weapon = Node3D.new()
			var rig := Rig.new(hero, weapon, float(def.get("sword_scale", 1.0)), -0.375, 0.72)
			var p := Poses.get_pose(str(names[i]))
			rig.snap(p)
			rig.w_up = 1.0
			rig.w_leg = 1.0
			rig.w_up_target = 1.0
			rig.w_leg_target = 1.0
			spin.rotation = Vector3(-float(p["bp"]), float(p["by"]), float(p["br"]))
			rigs.append(rig)
			heroes.append(hero)
			if row == 1:
				var lab := Label3D.new()
				lab.text = str(names[i])
				lab.font_size = 40
				lab.pixel_size = 0.006
				lab.position = Vector3(slot.position.x, -0.25, 1.0)
				lab.modulate = Color(1, 1, 0.8)
				root3.add_child(lab)
	_shoot.call_deferred()


func _shoot() -> void:
	for f in 14:
		for i in rigs.size():
			(heroes[i] as VoxelHero).animate(0.016, 0.0, 0.0, false, true)
			(rigs[i] as Rig).update(0.016)
			(rigs[i] as Rig).apply(0.016)
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_jpg("res://_shots/preview/tsb_cg_pose_%s.jpg" % tag, 0.9)
	print("[shot] tsb_cg_pose_", tag)
	quit()
