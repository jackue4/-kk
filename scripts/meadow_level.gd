extends Node3D
## 木兰草原：开放世界草原关卡（先搭场景，暂无敌人）。美术参考 Europa 的吉卜力风（见 ghibli_kit.gd）。
## · 地形：MeadowGen 噪声（大片缓坡 / 平川 / 圆润高地 / 外圈群山）+ MeadowTerrain 流式加载（预测前方、粗到细、远景托底）
## · 植被：MeadowGrass（WindGrass 草环 + 吉卜力配色的花 + 蝴蝶），地块上的伞形树、灌木、白石
## · 村子：MeadowVillage（灰泥木屋、瓦顶、井、栅栏、风车），一条土路从出生点蜿蜒过去
## · 天空 / 光照：手绘积云天空、暖色太阳从出生点右后方照过来、青蓝色阴影、地上飘云影
## · 出生点：一块小平台，面朝村子（vista），背后一扇回大厅的传送门（门心看得到大厅），旁边一块题名石碑
## · 主角：飞行高度上限按脚下地面抬高（Player.ground_ref）；镜头不钻地（CameraRig.floor_fn）；
##   兜底：地块还在算、没有碰撞的地方，不让主角掉到地面以下；飞出 BOUND_R 被推回（外圈群山也挡着）
## · 远处更大：镜头远裁到 16 公里、远景虚化推远；离开时还原
## · F3：屏幕左下显示流式加载统计
## 搜打撤（raid_enabled，正式玩法）走另一套场景：方块世界 block_world.gd（《我的世界：地下城》式的方块地形 + 灯火氛围，
## 五个区域各一套配色），不再建草叶 / 花 / 村子 / 流式草原；老的吉卜力草原只在 --meadow-shot 自检里保留。
## 故意不写 class_name：用 preload 引用。
signal exit_requested

const MeadowGen := preload("res://scripts/meadow_gen.gd")
const MeadowTerrain := preload("res://scripts/meadow_terrain.gd")
const MeadowGrass := preload("res://scripts/meadow_grass.gd")
const LevelPortal := preload("res://scripts/level_portal.gd")
const MeadowVillage := preload("res://scripts/meadow_village.gd")
const Kit := preload("res://scripts/ghibli_kit.gd")
const RaidManager := preload("res://scripts/raid_manager.gd")
const BlockWorld := preload("res://scripts/block_world.gd")
const RaidData := preload("res://scripts/raid_data.gd")
const Sfx := preload("res://scripts/sfx.gd")

const BOUND_R := 11000.0
const EXIT_BACK := 18.0

var player: Player
var cam: CameraRig
var font: Font
var gen := MeadowGen.new()
var terrain: MeadowTerrain
var grass: MeadowGrass
var exit_portal: LevelPortal
var vista := Vector3.FORWARD
var worst_frame_ms := 0.0   # 自检用：最长一帧（毫秒）
## 搜打撤（见 raid_manager.gd）：开着时不放回大厅的门，只能从亮着的传送阵撤离；老的 --meadow-shot 自检关掉它
var raid_enabled := true
var mobile := false         # 手机：关掉抗锯齿 / SSAO / 辉光，缩短阴影和远裁距离
var net: Node = null        # 联机（net.gd），单机为 null
var raid: RaidManager
var env: Environment
var sun: DirectionalLight3D
var world: BlockWorld       # 搜打撤的方块世界（raid_enabled 时才有；此时 terrain / grass 为空）
## 方块世界里主角脚下的地板：一块跟着主角走的碰撞板，顶面摆在脚下那格的高度（地形本身不建碰撞体）
const CLIMB_SPD := 15.0     # 在地上走着撞到高崖：贴着崖壁自己升上去的速度
const DIG_R := 4.4          # 结丹以上飞进山体：破开的通道半径
var dug_total := 0          # 一共破开了多少格（自检看）
var _dig_fx := 0.0
const STEP_UP := 2.25       # 两格以内直接迈上去 / 走下去；再高算墙，要跳或飞
var _floor: StaticBody3D
var _last_xz := Vector2.ZERO
var motes: CPUParticles3D   # 跟着主角的空中飘浮物（萤火 / 落叶 / 火星 / 鬼火 / 魔尘）

var _stats: Label
var _old_far := 4000.0
var _old_dof := Vector2(260.0, 500.0)


static func make_environment() -> Environment:
	return Kit.environment()


## 太阳从出生点（面朝村子）的右后方斜照过来：村子朝出生点的这一面受光，影子往左前方落
static func make_sun(v: Vector3) -> DirectionalLight3D:
	var side := v.cross(Vector3.UP).normalized()
	return Kit.sun(v * 0.5 - side * 0.65 + Vector3.DOWN * 1.1)


## 出生点面朝的方向：村子
static func vista_dir(g: MeadowGen) -> Vector3:
	return g.village_dir


## 回大厅的门：出生点背后 EXIT_BACK 米、门口朝草原（预览门心也用这个当"那一头的门"）
static func exit_xf(g: MeadowGen, v: Vector3) -> Transform3D:
	var p := -v * EXIT_BACK
	p.y = g.height(p.x, p.z)
	return Transform3D(Basis.looking_at(-v, Vector3.UP), p)


## 地面高度：方块世界是纯函数，草原问流式地形
func ground(x: float, z: float) -> float:
	if world != null:
		return world.height(x, z)
	return terrain.height_at(x, z) if terrain != null else gen.height(x, z)


func spawn_point() -> Vector3:
	if world != null:
		return Vector3(0.0, ground(0.0, 0.0) + 0.05, 0.0)
	return Vector3(0.0, gen.height(0.0, 0.0) + 0.05, 0.0)


func spawn_yaw() -> float:
	return atan2(-vista.x, -vista.z)


func _ready() -> void:
	process_physics_priority = 50   # 在主角移动之后兜底
	vista = vista_dir(gen)
	if raid_enabled:
		_ready_block()
		return
	var we := WorldEnvironment.new()
	env = make_environment()
	we.environment = env
	add_child(we)
	sun = make_sun(vista)
	add_child(sun)
	if mobile:
		env.ssao_enabled = false
		env.glow_enabled = false
		sun.directional_shadow_max_distance = 90.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	terrain = MeadowTerrain.new()
	terrain.name = "Terrain"
	terrain.gen = gen
	terrain.target = player
	add_child(terrain)
	MeadowGrass.low = mobile
	grass = MeadowGrass.new()
	grass.name = "Grass"
	grass.terrain = terrain
	grass.target = player
	add_child(grass)
	var village := MeadowVillage.new()
	village.name = "Village"
	village.gen = gen
	add_child(village)
	_build_spawn()
	_build_stats()
	_old_far = cam.cam.far
	cam.cam.far = 7000.0 if mobile else 16000.0
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		_old_dof = Vector2(attr.dof_blur_far_distance, attr.dof_blur_far_transition)
		attr.dof_blur_far_distance = 900.0
		attr.dof_blur_far_transition = 2500.0
	cam.floor_fn = terrain.height_at
	player.bound = BOUND_R
	player.ground_ref = spawn_point().y
	if raid_enabled:
		raid = RaidManager.new()
		raid.name = "Raid"
		raid.level = self
		raid.player = player
		raid.cam = cam
		raid.font = font
		raid.mobile = mobile
		add_child(raid)


## 搜打撤：方块世界
func _ready_block() -> void:
	var we := WorldEnvironment.new()
	env = BlockWorld.make_environment()
	we.environment = env
	add_child(we)
	sun = BlockWorld.make_sun()
	add_child(sun)
	if mobile:
		# 手机档：阴影只管近处 80 米、两级级联，再远交给烘焙日影；不开屏幕空间环境光遮蔽和景深
		sun.directional_shadow_max_distance = 80.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.shadow_blur = 1.8
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	else:
		env.ssao_enabled = true
		env.ssao_radius = 1.6
		env.ssao_intensity = 1.3
		env.ssao_power = 1.4
	world = BlockWorld.new()
	world.name = "World"
	world.target = player
	world.mobile = mobile
	add_child(world)
	_floor = StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(6.0, 2.0, 6.0)
	fcs.shape = fsh
	_floor.add_child(fcs)
	add_child(_floor)
	_build_motes()
	_build_stele()
	_build_stats()
	_old_far = cam.cam.far
	cam.cam.far = 900.0 if mobile else 1300.0
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		_old_dof = Vector2(attr.dof_blur_far_distance, attr.dof_blur_far_transition)
		# 远处虚掉一点（桌面档）；手机上景深太贵，只靠雾
		attr.dof_blur_far_enabled = not mobile
		attr.dof_blur_far_distance = 150.0
		attr.dof_blur_far_transition = 420.0
	cam.floor_fn = ground
	player.bound = RaidData.BOUND_R
	player.ground_ref = spawn_point().y
	raid = RaidManager.new()
	raid.name = "Raid"
	raid.level = self
	raid.player = player
	raid.cam = cam
	raid.font = font
	raid.mobile = mobile
	raid.net = net
	add_child(raid)


## 空中飘浮物：一个 CPU 粒子发射器跟着主角，小方块慢慢飘，颜色跟区域走（raid_manager.gd 里改）
func _build_motes() -> void:
	motes = CPUParticles3D.new()
	motes.amount = 40 if mobile else 80
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(34.0, 9.0, 34.0)
	motes.direction = Vector3(0.4, 0.5, 0.2)
	motes.spread = 60.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.3
	motes.initial_velocity_max = 1.4
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.0))
	sc.add_point(Vector2(0.15, 1.0))
	sc.add_point(Vector2(0.8, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	motes.scale_amount_curve = sc
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.16
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(2.4, 2.4, 2.4)
	mm.vertex_color_use_as_albedo = true
	bm.material = mm
	motes.mesh = bm
	motes.color = RaidData.REGIONS[0]["mote"]
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)


func _exit_tree() -> void:
	cam.floor_fn = Callable()
	cam.cam.far = _old_far
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		attr.dof_blur_far_enabled = true
		attr.dof_blur_far_distance = _old_dof.x
		attr.dof_blur_far_transition = _old_dof.y
	player.ground_ref = 0.0
	player.bound = Player.BOUND


## 载入：等出生点周围的地形（含碰撞）和草都建好，最多等 timeout 秒
func prewarm(timeout := 10.0) -> float:
	var t := 0.0
	while t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
		var p := player.global_position
		if world != null:
			if world.ready_near(p):
				break
		elif terrain.ready_near(p) and grass.ready_near(p):
			break
	return t


func _build_spawn() -> void:
	var xf := exit_xf(gen, vista)
	if raid_enabled:
		_build_stele()
		return
	exit_portal = LevelPortal.new()
	exit_portal.name = "ExitPortal"
	exit_portal.font = font
	exit_portal.title = "归 · 试剑大厅"
	exit_portal.stone = Color(0.48, 0.46, 0.42)
	exit_portal.transform = xf
	exit_portal.preview_eye = TestHall.preview_eye()
	exit_portal.preview_builder = func(vp: SubViewport) -> void: vp.add_child(TestHall.make_preview())
	exit_portal.entered.connect(func() -> void: exit_requested.emit())
	add_child(exit_portal)
	_build_stele()


func _build_stele() -> void:
	# 题名石碑：出生点右前方，碑面朝出生点
	var side := vista.cross(Vector3.UP).normalized()
	var sp := side * 9.0 + vista * 3.0
	sp.y = ground(sp.x, sp.z) if world != null else gen.height(sp.x, sp.z)
	var face := -side
	var yaw := atan2(face.x, face.z)
	var m: Material = Kit.prop_mat(Color(0.62, 0.6, 0.55), Kit.PAT_PLASTER, 0.15)
	if world != null:
		m = MeshLib.std_mat(Color(0.5, 0.52, 0.56), 0.95)
	var stele := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 5.4, 0.7)
	stele.mesh = bm
	stele.material_override = m
	stele.position = sp + Vector3.UP * 2.3
	stele.rotation.y = yaw
	add_child(stele)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	body.add_child(cs)
	stele.add_child(body)
	if font != null:
		var l := Label3D.new()
		l.text = "木\n兰\n草\n原"
		l.font = font
		l.font_size = 128
		l.pixel_size = 0.0085
		l.line_spacing = -8.0
		l.modulate = Color(0.12, 0.1, 0.08)
		l.outline_size = 0
		l.position = Vector3(0.0, 0.35, 0.36)
		stele.add_child(l)
		var s2 := Label3D.new()
		s2.text = "搜 · 打 · 撤" if world != null else "万里草海 · 御剑遁光任行"
		s2.font = font
		s2.font_size = 64
		s2.pixel_size = 0.004
		s2.modulate = Color(0.16, 0.14, 0.1)
		s2.outline_size = 0
		s2.position = Vector3(0.0, -2.2, 0.36)
		stele.add_child(s2)


func _build_stats() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 16)
	_stats.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_stats.add_theme_constant_override("outline_size", 4)
	if font != null:
		_stats.add_theme_font_override("font", font)
	_stats.visible = false
	layer.add_child(_stats)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_F3:
		_stats.visible = not _stats.visible


func stats_text() -> String:
	if world != null:
		return "方块世界：地块 %d  累计生成 %d  最长帧 %.1f ms" % [world.chunk_count(), world.built, worst_frame_ms]
	var s := terrain.stats()
	var c: Array = s["lod"]
	return "地块 LOD0 %d · LOD1 %d · LOD2 %d · LOD3 %d   生成中 %d  排队 %d\n" % [c[0], c[1], c[2], c[3], s["jobs"], s["queue"]] \
			+ "速度 %.0f m/s  预测 %.0f m  前方覆盖 %.0f%%  脚下 LOD%d\n" % [s["speed"], s["look"], float(s["ahead"]) * 100.0, s["under"]] \
			+ "主线程落地 %.1f ms  草地块 %d  最长帧 %.1f ms" % [s["ms"], grass.tile_count(), worst_frame_ms]


func _process(dt: float) -> void:
	if terrain != null:
		terrain.view_dir = cam.flat_forward()
	if motes != null:
		motes.global_position = player.global_position + Vector3(0.0, 5.0, 0.0) + player.velocity * 1.5
	worst_frame_ms = maxf(worst_frame_ms, dt * 1000.0)
	if _stats.visible:
		_stats.text = stats_text()
		_stats.position = Vector2(18.0, get_viewport().get_visible_rect().size.y - 92.0)


## 破开身前的山体（结丹以上飞行 / 空战 / 遁光时）：削出一条通道，碎石飞溅；联机时告诉别人
func _dig_through(p: Vector3, dt: float) -> void:
	var n := world.dig(p, DIG_R, p.y - 1.0)
	if n <= 0:
		return
	dug_total += n
	if net != null and bool(net.active):
		net.send_dig(p, DIG_R, p.y - 1.0)
	_dig_fx -= dt
	if _dig_fx <= 0.0:
		_dig_fx = 0.12
		var dir := player.velocity.normalized() if player.velocity.length_squared() > 1.0 else Vector3.FORWARD
		var ri := RaidData.region_at(p.x, p.z)
		var stone: Color = RaidData.REGIONS[ri]["stone"]
		var dirt: Color = RaidData.REGIONS[ri]["dirt"]
		var c := p + Vector3.UP * 0.9 + dir * 1.5
		Vfx.debris(c, -dir + Vector3.UP * 0.5, [stone.lightened(0.25), stone, dirt, dirt.lightened(0.2)], 12, 9.0, 1.6)
		Vfx.dust(c, 8, 5.0, 1.4)
		Vfx.shockwave(c, dir, Color.WHITE.lerp(Realm.line_color(player.realm), 0.5), 0.9)
		Sfx.play("slam", -10.0, 1.5)
		cam.add_trauma(0.12)


## 方块世界的落脚（返回脚下地面高度）：
##   · 在地上走：高 / 低两格以内直接贴上去；更高的崖壁——贴着它自己升上去（所有境界），升到顶再往前走
##   · 飞行 / 空战 / 遁光时撞进山体：结丹以上直接破开一条通道穿过去；筑基的御器飞行被地形托着往上升
## 最后把脚下的地板摆到这一格的高度。
func _block_floor(p: Vector3, h: float, dt: float) -> float:
	if player.st != Player.St.GROUND and player.st != Player.St.DIVE and h - p.y > 0.3 and player.is_light_mode():
		# 飞着撞上地形：前面是座山（8 米外的地面比自己高出 4 米以上，或者眼前就是高崖）才破开；缓坡就顺着托上去
		var fv := Vector3(player.velocity.x, 0.0, player.velocity.z)
		var ahead := p + (fv.normalized() * 8.0 if fv.length_squared() > 1.0 else Vector3.ZERO)
		if h - p.y > STEP_UP or ground(ahead.x, ahead.z) - p.y > 4.0:
			_dig_through(p, dt)
			h = ground(p.x, p.z)
	if player.st == Player.St.GROUND:
		var rise := h - p.y
		if rise > STEP_UP:
			var hb := ground(_last_xz.x, _last_xz.y)
			if hb - p.y <= STEP_UP or hb < h:
				# 崖壁：水平位置退回去，人贴着崖往上升
				player.global_position.x = _last_xz.x
				player.global_position.z = _last_xz.y
				player.global_position.y = p.y + CLIMB_SPD * dt
				player.velocity.y = 0.0
				_floor.global_position = Vector3(_last_xz.x, player.global_position.y - 1.0, _last_xz.y)
				return maxf(hb, player.global_position.y)
		if rise > 0.02 and rise <= STEP_UP:
			player.global_position.y = h
			if player.velocity.y < 0.0:
				player.velocity.y = 0.0
		elif rise < -0.02 and rise >= -STEP_UP and player.is_on_floor() and player.velocity.y <= 0.01:
			player.global_position.y = h
	_last_xz = Vector2(player.global_position.x, player.global_position.z)
	_floor.global_position = Vector3(_last_xz.x, h - 1.0, _last_xz.y)
	return h


func _physics_process(dt: float) -> void:
	var p := player.global_position
	var h := ground(p.x, p.z)
	if world != null:
		h = _block_floor(p, h, dt)
		p = player.global_position
	player.ground_ref = lerpf(player.ground_ref, h, 1.0 - exp(-3.0 * dt))
	if p.y < h - 0.05:
		player.global_position.y = h
		if player.velocity.y < 0.0:
			player.velocity.y = 0.0
	var r := Vector2(p.x, p.z).length()
	var lim: float = RaidData.BOUND_R if world != null else BOUND_R
	if r > lim:
		var rd := Vector3(p.x, 0.0, p.z) / r
		player.global_position -= rd * (r - lim)
		var vr := player.velocity.dot(rd)
		if vr > 0.0:
			player.velocity -= rd * vr
