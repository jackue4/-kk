extends SceneTree
## AI 的四种样式排一排（魔炎 / 霸哥 / 方块小人 / 冰雪战士 伊芙琳），最右边放主角（阿拉灯）比个头。
## 前排是 AI 平时的样子（御空 + 空战待机、持剑），后排是同一个人出拳的姿势。正面 / 背面各一张。
## 用法：python _tasks/trailer/run_hidden.py . <日志前缀> --resolution 1600x900 -s res://_tasks/hero_skin/ai_lineup.gd [-- --out=<目录>]

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")

const NAMES := {"moyan": "魔炎", "bage": "霸哥", "": "方块小人", "evelyn": "冰雪战士 伊芙琳", "aladeng": "主角（阿拉灯）"}

var _out := "res://_tasks/hero_skin/shots"
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
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

	var keys: Array = HeroSkin.AI_SKINS.duplicate()
	keys.append(HeroSkin.PLAYER_SKIN)
	var heroes: Array = []
	var n := keys.size()
	for i in n:
		for kind in 2:
			var slot := Node3D.new()
			world.add_child(slot)
			slot.position = Vector3((float(i) - float(n - 1) * 0.5) * -2.2, 0.0, 2.8 if kind == 1 else 0.0)
			var h: VoxelHero = VoxelHero.new({}, true, false, 2, str(keys[i]))
			slot.add_child(h)
			var sword := MeshLib.make_sword(Color(0.4, 0.7, 1.0))
			var rig := Rig.new(h, sword, 1.0, -0.375, 0.72)
			sword.visible = kind == 0
			rig.snap(Poses.get_pose("air_idle" if kind == 0 else "r1_m"))
			rig.w_up = 1.0
			rig.w_leg = 1.0
			rig.w_up_target = 1.0
			rig.w_leg_target = 1.0
			heroes.append([h, rig])
			if kind == 0:
				var l := Label3D.new()
				l.text = str(NAMES.get(str(keys[i]), keys[i]))
				l.font_size = 40
				l.pixel_size = 0.006
				l.outline_size = 8
				l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				l.position = Vector3(0, 2.5, 0)
				slot.add_child(l)
	for f in 40:
		for e: Array in heroes:
			(e[0] as VoxelHero).animate(1.0 / 30.0, 0.0, 0.0, false, true)
			(e[1] as Rig).apply(1.0 / 30.0)
		await process_frame
	await _shot("ai_lineup_front", Vector3(0.0, 2.2, -13.5), Vector3(0.0, 1.05, 1.0))
	await _shot("ai_lineup_side", Vector3(-9.5, 2.6, -9.5), Vector3(0.0, 1.0, 1.0))
	await _shot("ai_lineup_back", Vector3(0.0, 2.6, 15.0), Vector3(0.0, 1.0, 0.5))
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
