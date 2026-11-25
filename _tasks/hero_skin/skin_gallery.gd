extends SceneTree
## 主角皮肤定妆：同一组姿势，前排皮肤模型、后排方块人，拍几张对照（看比例、朝向、手里的剑、关节有没有拧）。
## 用法（要真渲染）：python _tasks/trailer/run_hidden.py . <日志前缀> --resolution 1600x900 -s res://_tasks/hero_skin/skin_gallery.gd [-- 选项]
##   --out=<目录>   截图放哪（默认 res://_shots/preview）   --tag=<前缀>   文件名前缀（默认 skin）
##   --fx           再拍一组：受击闪白 / 化光 / 觉醒描边 / 锁定描边
##   --ghost        再拍一组：身法残影（Vfx.body_ghost，挪到旁边看）和陨落碎裂（Vfx.shatter）
##   --skin=<名字>  拍哪个皮肤（hero_skin.gd 的 SKINS：aladeng / moyan / bage / evelyn，默认主角用的那个）
##   --run          只拍地面移动：一排皮肤模型在跑（各自错开半步）、两个站着、两个持剑戒备着跑（上身招式 + 腿原生），正 / 侧 / 背三面
## 截图：<tag>_poses_front / _side / _back、<tag>_close、<tag>_fx

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")

## [说明, 基础动作（phase, move, airborne, floating）, 战斗姿势名（空 = 不叠）, 持剑]
const ROWS := [
	["站立", [0.0, 0.0, false, false], "", false],
	["走路", [1.3, 1.0, false, false], "", false],
	["腾空", [0.0, 0.0, true, false], "", false],
	["御空", [0.0, 0.0, false, true], "", false],
	["持剑戒备", [0.0, 0.0, false, false], "stance", true],
	["横斩", [0.0, 0.0, false, false], "a1_m", true],
	["举剑", [0.0, 0.0, false, false], "a3_top", true],
	["格挡", [0.0, 0.0, false, false], "guard", true],
	["空战待机", [0.0, 0.0, false, true], "air_idle", true],
	["受击", [0.0, 0.0, false, false], "hurt", true],
]

var _out := "res://_shots/preview"
var _tag := "skin"
var _cam: Camera3D
var _world: Node3D


var _skin := HeroSkin.PLAYER_SKIN


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fx := false
	var ghost := false
	var run_only := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--skin="):
			_skin = a.substr(7)
		if a == "--run":
			run_only = true
		if a == "--ghost":
			ghost = true
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a == "--fx":
			fx = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_world = Node3D.new()
	root.add_child(_world)
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
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.36, 0.3)
	floor_mi.material_override = fm
	_world.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.fov = 36.0
	_world.add_child(_cam)

	if run_only:
		await _run_strip()
		quit()
		return
	var p := HeroSkin.profile(_skin)
	print("[skin] 比例：", p)
	var heroes: Array = []
	var n := ROWS.size()
	for i in n:
		var row: Array = ROWS[i]
		for kind in 2:
			var slot := Node3D.new()
			_world.add_child(slot)
			slot.position = Vector3((float(i) - float(n - 1) * 0.5) * -1.9, 0.0, 2.6 if kind == 1 else 0.0)
			var h: VoxelHero = VoxelHero.new({}, true, false, 1, _skin) if kind == 0 else VoxelHero.new({}, true, false, 1)
			slot.add_child(h)
			var rig: Rig = null
			if str(row[2]) != "":
				var sword := MeshLib.make_sword(Color(0.4, 0.7, 1.0))
				rig = Rig.new(h, sword, 1.0, -0.375, 0.72)
				sword.visible = bool(row[3])
				rig.snap(Poses.get_pose(str(row[2])))
				rig.w_up = 1.0
				rig.w_leg = 1.0
				rig.w_up_target = 1.0
				rig.w_leg_target = 1.0
			heroes.append([h, rig, row[1]])
			if kind == 0:
				var l := Label3D.new()
				l.text = str(row[0])
				l.font_size = 40
				l.pixel_size = 0.006
				l.outline_size = 8
				l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				l.position = Vector3(0, 2.35, 0)
				slot.add_child(l)
	# 姿势摆 40 帧稳下来（animate 里有缓动）
	for f in 40:
		for e: Array in heroes:
			var b: Array = e[2]
			(e[0] as VoxelHero).animate(1.0 / 30.0, float(b[0]), float(b[1]), bool(b[2]), bool(b[3]))
			if e[1] != null:
				(e[1] as Rig).apply(1.0 / 30.0)
		await process_frame
	var first: VoxelHero = heroes[0][0]
	if first.skin != null:
		var ph: Vector3 = first.hand_r.global_position
		print("[skin] 站立：右手关节 %s  右脚关节 %s  头关节 %s" % [ph, first.foot_r.global_position, first.head.global_position])
	await _shot("poses_front", Vector3(0.0, 2.4, -17.0), Vector3(0.0, 1.0, 1.0))
	await _shot("poses_side", Vector3(-16.0, 3.4, -9.0), Vector3(0.0, 0.9, 1.0))
	# 背面（游戏里大多数时候看到的是这一面）：方块人那一排先挪开，别挡着
	for i in heroes.size():
		if i % 2 == 1:
			((heroes[i][0] as VoxelHero).get_parent() as Node3D).position.z = -2.6
	await _shot("poses_back", Vector3(0.0, 2.4, 17.0), Vector3(0.0, 1.0, -1.0))
	# 近看：站立 / 持剑戒备 / 横斩 三个皮肤模型
	var x_of := func(i: int) -> float:
		return (float(i) - float(n - 1) * 0.5) * -1.9
	_cam.fov = 30.0
	await _shot("close_a", Vector3(float(x_of.call(0)) - 1.0, 1.5, -4.6), Vector3(float(x_of.call(0)) - 0.9, 0.95, 0.0))
	await _shot("close_b", Vector3(float(x_of.call(5)) + 0.9, 1.6, -4.8), Vector3(float(x_of.call(5)) + 0.9, 0.95, 0.0))
	await _shot("close_back", Vector3(float(x_of.call(0)) - 1.0, 1.7, 4.6), Vector3(float(x_of.call(0)) - 0.9, 0.95, 0.0))
	await _shot("close_back2", Vector3(float(x_of.call(5)) + 0.9, 1.9, 5.0), Vector3(float(x_of.call(5)) + 0.9, 0.95, 0.0))
	for i in heroes.size():
		if i % 2 == 1:
			((heroes[i][0] as VoxelHero).get_parent() as Node3D).position.z = 2.6
	if fx:
		# 受击闪白 / 化光 / 觉醒描边 / 锁定描边：依次套在前四个皮肤模型和它们身后的方块人上
		for kind in 2:
			(heroes[0 + kind][0] as VoxelHero).set_flash(1.0)
			(heroes[2 + kind][0] as VoxelHero).set_glow(0.6, Color(0.4, 0.7, 1.0))
			(heroes[4 + kind][0] as VoxelHero).set_outline(1.0, Color(0.5, 0.9, 1.0))
			(heroes[6 + kind][0] as VoxelHero).set_lock_outline(1.0)
		for f in 6:
			await process_frame
		_cam.fov = 34.0
		var cx := (float(x_of.call(0)) + float(x_of.call(3))) * 0.5
		await _shot("fx", Vector3(cx, 2.6, -9.5), Vector3(cx, 1.0, 1.0))
		print("[skin] 描边：皮肤 %s 方块人 %s" % [(heroes[4][0] as VoxelHero).skin.line_on(), (heroes[5][0] as VoxelHero).outline_state()])
	if ghost:
		# 残影：横斩的皮肤模型和它身后的方块人各留一道，往右挪 1 米好看清；碎裂：举剑的那两个
		Vfx.root = _world
		for kind in 2:
			var src := (heroes[5 * 2 + kind][0] as VoxelHero).get_parent() as Node3D
			var g := Vfx._ghost_node(src, Color(0.6, 0.85, 1.0), 0.75, src.global_position)
			g.global_position += Vector3(-0.95, 0.0, 0.0)
		for f in 3:
			await process_frame
		_cam.fov = 30.0
		var gx := float(x_of.call(5)) - 0.5
		await _shot("ghost", Vector3(gx, 1.7, -6.5), Vector3(gx, 0.95, 1.2))
		for kind in 2:
			var src2 := (heroes[6 * 2 + kind][0] as VoxelHero).get_parent() as Node3D
			Vfx.shatter(src2, src2.global_position + Vector3(0.0, 1.0, -0.3), Vector3(0.0, 0.3, 1.0), Color(1.0, 0.8, 0.6), 1.0)
			src2.visible = false
		await create_timer(0.22).timeout
		var sx := float(x_of.call(6))
		await _shot("shatter", Vector3(sx, 1.9, -7.5), Vector3(sx, 0.9, 1.2))
		await create_timer(0.5).timeout
		await _shot("shatter_b", Vector3(sx, 1.9, -7.5), Vector3(sx, 0.9, 1.2))
	quit()


## 地面移动的连拍：0~5 在跑（错开）、6~7 站着、8~9 持剑戒备着跑
func _run_strip() -> void:
	var heroes: Array = []
	var n := 10
	for i in n:
		var slot := Node3D.new()
		_world.add_child(slot)
		slot.position = Vector3((float(i) - float(n - 1) * 0.5) * -1.75, 0.0, 0.0)
		var h: VoxelHero = VoxelHero.new({}, true, false, 1, _skin)
		slot.add_child(h)
		var rig: Rig = null
		if i >= 8:
			var sword := MeshLib.make_sword(Color(0.4, 0.7, 1.0))
			rig = Rig.new(h, sword, 1.0, -0.375, 0.72)
			rig.snap(Poses.get_pose("stance"))
			rig.w_up = 1.0
			rig.w_up_target = 1.0
		heroes.append([h, rig, 0.0 if i == 6 or i == 7 else 1.0, slot])
	var phase := 0.0
	for f in 60:
		phase += (1.0 / 30.0) * 7.0 * 1.6
		for i in n:
			var e: Array = heroes[i]
			(e[0] as VoxelHero).animate(1.0 / 30.0, phase, float(e[2]), false, false)
			if e[1] != null:
				(e[1] as Rig).apply(1.0 / 30.0)
			if f == 30 and i < 6:
				# 错开：各自的跑步片段拨到一圈里不同的位置
				(e[0] as VoxelHero).skin.set("_run_t", 0.3667 * float(i) / 6.0)
		await process_frame
	var sk0: Node = (heroes[0][0] as VoxelHero).skin
	print("[skin] 跑：上身原生 %.2f 腿原生 %.2f 跑步占比 %.2f；站：上身 %.2f 腿 %.2f；戒备着跑：上身 %.2f 腿 %.2f" % [
			float(sk0.get("_w_up")), float(sk0.get("_w_leg")), float(sk0.get("_run_k")),
			float((heroes[6][0] as VoxelHero).skin.get("_w_up")), float((heroes[6][0] as VoxelHero).skin.get("_w_leg")),
			float((heroes[8][0] as VoxelHero).skin.get("_w_up")), float((heroes[8][0] as VoxelHero).skin.get("_w_leg"))])
	# 定格：之后不再推进（不调 animate，原生动画的钟就停了），但权重要留住 → 直接停掉皮肤节点的处理
	for e: Array in heroes:
		(e[0] as VoxelHero).skin.set_process(false)
		(e[0] as VoxelHero).set_process(false)
	_cam.fov = 38.0
	await _shot("run_front", Vector3(0.0, 1.9, -12.5), Vector3(0.0, 0.9, 0.0))
	for e: Array in heroes:
		(e[3] as Node3D).rotation.y = -PI * 0.5
	await _shot("run_side", Vector3(0.0, 1.9, -12.5), Vector3(0.0, 0.9, 0.0))
	for e: Array in heroes:
		(e[3] as Node3D).rotation.y = PI
	await _shot("run_back", Vector3(0.0, 2.8, -12.5), Vector3(0.0, 0.9, 0.0))


func _shot(name: String, eye: Vector3, target: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(target)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(1400, int(1400.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	var path := "%s/%s_%s.jpg" % [_out, _tag, name]
	img.save_jpg(path, 0.9)
	print("[shot] ", path)
