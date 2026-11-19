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
## 故意不写 class_name：用 preload 引用。
signal exit_requested

const MeadowGen := preload("res://scripts/meadow_gen.gd")
const MeadowTerrain := preload("res://scripts/meadow_terrain.gd")
const MeadowGrass := preload("res://scripts/meadow_grass.gd")
const LevelPortal := preload("res://scripts/level_portal.gd")
const MeadowVillage := preload("res://scripts/meadow_village.gd")
const Kit := preload("res://scripts/ghibli_kit.gd")

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


func spawn_point() -> Vector3:
	return Vector3(0.0, gen.height(0.0, 0.0) + 0.05, 0.0)


func spawn_yaw() -> float:
	return atan2(-vista.x, -vista.z)


func _ready() -> void:
	process_physics_priority = 50   # 在主角移动之后兜底
	vista = vista_dir(gen)
	var we := WorldEnvironment.new()
	we.environment = make_environment()
	add_child(we)
	add_child(make_sun(vista))
	terrain = MeadowTerrain.new()
	terrain.name = "Terrain"
	terrain.gen = gen
	terrain.target = player
	add_child(terrain)
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
	cam.cam.far = 16000.0
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		_old_dof = Vector2(attr.dof_blur_far_distance, attr.dof_blur_far_transition)
		attr.dof_blur_far_distance = 900.0
		attr.dof_blur_far_transition = 2500.0
	cam.floor_fn = terrain.height_at
	player.ground_ref = spawn_point().y


func _exit_tree() -> void:
	cam.floor_fn = Callable()
	cam.cam.far = _old_far
	var attr := cam.cam.attributes as CameraAttributesPractical
	if attr != null:
		attr.dof_blur_far_distance = _old_dof.x
		attr.dof_blur_far_transition = _old_dof.y
	player.ground_ref = 0.0


## 载入：等出生点周围的地形（含碰撞）和草都建好，最多等 timeout 秒
func prewarm(timeout := 10.0) -> float:
	var t := 0.0
	while t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
		var p := player.global_position
		if terrain.ready_near(p) and grass.ready_near(p):
			break
	return t


func _build_spawn() -> void:
	var xf := exit_xf(gen, vista)
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

	# 题名石碑：出生点右前方，碑面朝出生点
	var side := vista.cross(Vector3.UP).normalized()
	var sp := side * 9.0 + vista * 3.0
	sp.y = gen.height(sp.x, sp.z)
	var face := -side
	var yaw := atan2(face.x, face.z)
	var m := Kit.prop_mat(Color(0.62, 0.6, 0.55), Kit.PAT_PLASTER, 0.15)
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
		s2.text = "万里草海 · 御剑遁光任行"
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
	var s := terrain.stats()
	var c: Array = s["lod"]
	return "地块 LOD0 %d · LOD1 %d · LOD2 %d · LOD3 %d   生成中 %d  排队 %d\n" % [c[0], c[1], c[2], c[3], s["jobs"], s["queue"]] \
			+ "速度 %.0f m/s  预测 %.0f m  前方覆盖 %.0f%%  脚下 LOD%d\n" % [s["speed"], s["look"], float(s["ahead"]) * 100.0, s["under"]] \
			+ "主线程落地 %.1f ms  草地块 %d  最长帧 %.1f ms" % [s["ms"], grass.tile_count(), worst_frame_ms]


func _process(dt: float) -> void:
	terrain.view_dir = cam.flat_forward()
	worst_frame_ms = maxf(worst_frame_ms, dt * 1000.0)
	if _stats.visible:
		_stats.text = stats_text()
		_stats.position = Vector2(18.0, get_viewport().get_visible_rect().size.y - 92.0)


func _physics_process(dt: float) -> void:
	var p := player.global_position
	var h := terrain.height_at(p.x, p.z)
	player.ground_ref = lerpf(player.ground_ref, h, 1.0 - exp(-3.0 * dt))
	if p.y < h - 0.05:
		player.global_position.y = h
		if player.velocity.y < 0.0:
			player.velocity.y = 0.0
	var r := Vector2(p.x, p.z).length()
	if r > BOUND_R:
		var rd := Vector3(p.x, 0.0, p.z) / r
		player.global_position -= rd * (r - BOUND_R)
		var vr := player.velocity.dot(rd)
		if vr > 0.0:
			player.velocity -= rd * vr
