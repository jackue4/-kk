extends SceneTree
## 霜华的姿势定妆：冰雪战士模型摆出她自己的那套关键姿势（手上带冰刃），正面 / 背面各拍两张（不起主场景；整身俯仰 / 自转由 Player 的 spin 节点做，这里看不到）。
## 用法：python -I _tasks/trailer/run_hidden.py . <日志> --resolution 1600x900 -s res://_tasks/tsb/shuanghua/pose_gallery.gd
const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const Kit := preload("res://scripts/heroes/kit_shuanghua.gd")
const HeroFx := preload("res://scripts/hero_fx.gd")

const LIST := ["sh_idle", "sh_guard", "sh1_m", "sh1_e", "sh2_m", "sh2_e", "sh3_m",
		"sh4_w", "sh4_m", "sh_cast_w", "sh_cast_m", "sh_nova_w", "sh_nova_m", "sh_sm_m",
		"sh_q_w", "sh_q_m", "sh_q_e", "sh_r_w", "sh_r_m", "sh_fin_w", "sh_fin_m"]

var _world: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	Vfx.root = _world
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.5, 0.56)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 2.6, 0)
	_world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.36, 0.3)
	floor_mi.material_override = fm
	_world.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_world.add_child(_cam)
	_cam.make_current()
	var heroes: Array = []
	var per := 7
	for i in LIST.size():
		var slot := Node3D.new()
		_world.add_child(slot)
		var col := i % per
		var row := i / per
		slot.position = Vector3((float(col) - float(per - 1) * 0.5) * -1.9, 1.0, float(row) * 40.0)
		var h: VoxelHero = VoxelHero.new({}, true, false, 1, "evelyn")
		slot.add_child(h)
		var sword := MeshLib.make_sword(Color(0.4, 0.7, 1.0))
		var rig: Rig = Rig.new(h, sword, 1.0, -0.375, 0.72)
		sword.visible = false
		rig.snap(Poses.get_pose(LIST[i]))
		rig.w_up = 1.0
		rig.w_leg = 1.0
		rig.w_up_target = 1.0
		rig.w_leg_target = 1.0
		for hand: Node3D in [h.hand_r, h.hand_l]:
			var mi := MeshInstance3D.new()
			mi.mesh = Kit._claw_mesh()
			var m := HeroFx.block_mat(Color.WHITE.lerp(Kit.ICE, 0.7), 0.88)
			m.next_pass = HeroFx.outline_mat(Color(0.2, 0.44, 0.8), 0.7, 0.012)
			mi.material_override = m
			hand.add_child(mi)
		heroes.append([h, rig])
		var l := Label3D.new()
		l.text = LIST[i]
		l.font_size = 36
		l.pixel_size = 0.005
		l.outline_size = 8
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0, 2.3, 0)
		slot.add_child(l)
	for f in 40:
		for e: Array in heroes:
			(e[0] as VoxelHero).animate(1.0 / 30.0, 0.0, 0.0, false, true)
			(e[1] as Rig).apply(1.0 / 30.0)
		await process_frame
	for r in 3:
		var z := float(r) * 40.0
		await _shot("%d_front" % r, Vector3(-4.0, 2.4, z - 15.0), Vector3(0.0, 1.9, z))
		await _shot("%d_back" % r, Vector3(4.0, 2.6, z + 15.0), Vector3(0.0, 1.9, z))
	quit()


func _shot(tag: String, eye: Vector3, at: Vector3) -> void:
	_cam.look_at_from_position(eye, at)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_jpg("res://_shots/preview/tsb_shuanghua_pose_%s.jpg" % tag, 0.9)
	print("[shot] pose_", tag)
