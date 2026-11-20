class_name TestHall
extends Node3D
## 灰白测试大厅：网格地面、尺度参照物、速度参照长廊、空中环、远景方碑。
## 微缩模型风：柔和暖光 + 柔影 + SSAO + 克制的远景虚化与雾。

const GRID := preload("res://shaders/grid.gdshader")
const LevelPortal := preload("res://scripts/level_portal.gd")
const HALF := 1200.0
## Boss 空战区「血河剑冢」：出生点东侧约 170 米的一块圆形场地（练手空地、长廊都不占），见 boss_arena.gd
const BOSS_ARENA := Vector3(170.0, 0.0, 40.0)
const BOSS_R := 56.0
## 择境传送门（见 level_portal.gd / main.gd）：出生点西侧，门口朝东（+X）对着出生点
const PORTAL_POS := Vector3(-42.0, 0.0, 4.0)
## 斗法台（AI 陪练的场地，见 spar_zone.gd）：出生点西南约一百米的一块圆台，离剑冢、传送门、长廊都远
const SPAR_POS := Vector3(-36.0, 0.0, 92.0)
const SPAR_R := 36.0

var font: Font
var world_env: WorldEnvironment
var _mat_floor: ShaderMaterial
var _mat_block: ShaderMaterial
var _mat_accent: StandardMaterial3D


func _ready() -> void:
	_mat_floor = _grid_mat(Color(0.3, 0.31, 0.33), Color(0.82, 0.84, 0.87), 0.6)
	_mat_block = _grid_mat(Color(0.7, 0.71, 0.73), Color(0.42, 0.44, 0.48), 0.55)
	_mat_accent = MeshLib.std_mat(Color(0.62, 0.63, 0.65), 0.7)
	_build_env()
	_build_floor()
	_build_props()
	_build_corridor()
	_build_monoliths()
	_build_walls()
	_build_boss_arena()


static func _grid_mat(base: Color, line: Color, strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GRID
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("line_color", line)
	m.set_shader_parameter("line_strength", strength)
	return m


## 离开大厅（去别的关卡）时摘掉大厅的 WorldEnvironment，回来再挂上
func set_env_active(on: bool) -> void:
	if on and world_env.get_parent() == null:
		add_child(world_env)
	elif not on and world_env.get_parent() == self:
		remove_child(world_env)


func _exit_tree() -> void:
	if world_env != null and world_env.get_parent() == null:
		world_env.free()


func _build_env() -> void:
	var we := WorldEnvironment.new()
	we.environment = make_env()
	add_child(we)
	world_env = we
	add_child(make_sun())


static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 2.2
	sun.directional_shadow_max_distance = 220.0
	return sun


static func make_env() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.52, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.77, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Bloom 只给线芯留一点点晕，不许把轨迹和周围景物冲成白斑
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 0.85
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 1.0
	env.glow_hdr_luminance_cap = 3.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.52, 0.55)
	env.fog_density = 0.0011
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	return env


## 木兰草原回程门的门心里看到的大厅："那一头的门"就是大厅里的择境门
static func preview_eye() -> Transform3D:
	return Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), PORTAL_POS + Vector3.UP * LevelPortal.LIFT)


## 回程门门心的预览世界：同样的灰环境、网格地面、出生点圆台、尺度方块和一圈远景方碑（不带碰撞、不带敌人）
static func make_preview() -> Node3D:
	var root := Node3D.new()
	var we := WorldEnvironment.new()
	we.environment = make_env()
	root.add_child(we)
	root.add_child(make_sun())
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.0, HALF * 2.0)
	floor_mi.mesh = pm
	floor_mi.material_override = _grid_mat(Color(0.3, 0.31, 0.33), Color(0.82, 0.84, 0.87), 0.6)
	root.add_child(floor_mi)
	var block := _grid_mat(Color(0.7, 0.71, 0.73), Color(0.42, 0.44, 0.48), 0.55)
	var pad := MeshInstance3D.new()
	pad.mesh = _cyl_mesh(3.0, 0.06)
	pad.material_override = MeshLib.std_mat(Color(0.62, 0.63, 0.65), 0.7)
	pad.position.y = 0.03
	root.add_child(pad)
	var boxes: Array[AABB] = [AABB(Vector3(-22.5, 0, 13.5), Vector3.ONE), AABB(Vector3(-16.5, 0, 13.0), Vector3.ONE * 2.0),
			AABB(Vector3(-10.5, 0, 12.0), Vector3.ONE * 4.0), AABB(Vector3(-2.5, 0, 10.0), Vector3.ONE * 8.0),
			AABB(Vector3(-17.0, 0, -13.0), Vector3(6, 3, 6)), AABB(Vector3(-27.0, 0, -19.0), Vector3(6, 6, 6)),
			AABB(Vector3(-37.0, 0, -13.0), Vector3(6, 10, 6)), AABB(Vector3(17.5, 0, 16.0), Vector3(5, 3, 6))]
	for b in boxes:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh(b.size)
		mi.material_override = block
		mi.position = b.position + b.size * 0.5
		root.add_child(mi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261110
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 120
	for i in 120:
		var a := rng.randf() * TAU
		var r := rng.randf_range(90.0, HALF - 60.0)
		var h := rng.randf_range(8.0, 40.0) + (rng.randf() ** 3.0) * 140.0
		var s := Vector3(rng.randf_range(6.0, 22.0), h, rng.randf_range(6.0, 22.0))
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(s), Vector3(cos(a) * r, h * 0.5, sin(a) * r)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = block
	root.add_child(mmi)
	return root


func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.0, HALF * 2.0)
	mi.mesh = pm
	mi.material_override = _mat_floor
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)

	# 出生点圆台
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.2
	cm.height = 0.06
	cm.radial_segments = 48
	pad.mesh = cm
	pad.material_override = _mat_accent
	pad.position.y = 0.03
	add_child(pad)


func _box(pos: Vector3, size: Vector3, collide := true, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat_block
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _label(text: String, pos: Vector3, size := 1.0, flat := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 96
	l.pixel_size = 0.006 * size
	l.modulate = Color(0.15, 0.16, 0.18)
	l.outline_size = 0
	l.position = pos
	if flat:
		l.rotation_degrees = Vector3(-90, 0, 0)
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(l)


func _build_props() -> void:
	# 尺度参照方块
	var x := -22.0
	for s: float in [1.0, 2.0, 4.0, 8.0]:
		_box(Vector3(x, s * 0.5, 14.0), Vector3(s, s, s))
		_label("%dm" % int(s), Vector3(x, s + 0.6, 14.0))
		x += s * 0.5 + 6.0
	# 台阶
	for i in 10:
		_box(Vector3(20.0, 0.15 + 0.3 * i, 10.0 + 0.6 * i), Vector3(5.0, 0.3, 0.6))
	_box(Vector3(20.0, 1.5, 19.0), Vector3(5.0, 3.0, 6.0))
	# 斜坡
	_box(Vector3(28.0, 1.35, 14.0), Vector3(4.0, 0.3, 11.0), true, Vector3(-16.0, 0, 0))
	# 不同高度的平台（测试跳跃/起降）
	_box(Vector3(-14.0, 1.5, -10.0), Vector3(6.0, 3.0, 6.0))
	_box(Vector3(-24.0, 3.0, -16.0), Vector3(6.0, 6.0, 6.0))
	_box(Vector3(-34.0, 5.0, -10.0), Vector3(6.0, 10.0, 6.0))
	_box(Vector3(16.0, 6.0, -14.0), Vector3(8.0, 0.5, 8.0))
	_box(Vector3(16.0, 3.0, -14.0), Vector3(1.0, 6.0, 1.0))
	# 矮墙
	_box(Vector3(0.0, 0.6, 22.0), Vector3(14.0, 1.2, 0.6))
	_label("角色 3C 测试大厅", Vector3(0.0, 0.03, 6.5), 1.6, true)
	_label("← 择境传送门 · 选择关卡", PORTAL_POS + Vector3(16.0, 0.03, 0.0), 1.4, true)


func _build_corridor() -> void:
	# 沿 -Z 的速度参照长廊：立柱 + 门框 + 地面里程 + 空中环
	var z := 40.0
	while z <= 1100.0:
		var h := 18.0 + fmod(z, 120.0) * 0.12
		_box(Vector3(-20.0, h * 0.5, -z), Vector3(3.0, h, 3.0), false)
		_box(Vector3(20.0, h * 0.5, -z), Vector3(3.0, h, 3.0), false)
		if int(z) % 200 == 0:
			_box(Vector3(0.0, h + 1.5, -z), Vector3(43.0, 3.0, 3.0), false)
		if int(z) % 100 == 0:
			_label("%dm" % int(z), Vector3(0.0, 0.03, -z), 6.0, true)
		z += 40.0

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.95, 0.96, 0.98)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.9, 0.95, 1.0)
	ring_mat.emission_energy_multiplier = 0.35
	var tm := TorusMesh.new()
	tm.inner_radius = 9.0
	tm.outer_radius = 10.2
	tm.rings = 48
	tm.ring_segments = 12
	var rz := 120.0
	var k := 0
	while rz <= 1050.0:
		var ring := MeshInstance3D.new()
		ring.mesh = tm
		ring.material_override = ring_mat
		ring.position = Vector3(sin(k * 1.3) * 8.0, 45.0 + sin(k * 0.9) * 22.0, -rz)
		ring.rotation_degrees.x = 90.0
		add_child(ring)
		rz += 155.0
		k += 1


func _build_monoliths() -> void:
	# 远景方碑：提供高速飞行时的视差与速度参照（无碰撞）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261110
	var xf: Array[Transform3D] = []
	var tries := 0
	while xf.size() < 260 and tries < 4000:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(90.0, HALF - 60.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x) < 34.0 and p.z < 0.0:
			continue  # 留出长廊
		var w := rng.randf_range(6.0, 22.0)
		var d := rng.randf_range(6.0, 22.0)
		var h := rng.randf_range(8.0, 40.0) + (rng.randf() ** 3.0) * 140.0
		if p.distance_to(BOSS_ARENA) < BOSS_R + 100.0:
			continue  # 剑冢上空留空（放在取完随机数之后：其余方碑位置和以前一样）
		if p.distance_to(SPAR_POS) < SPAR_R + 26.0:
			continue  # 斗法台和它周围留空
		xf.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), Vector3(p.x, h * 0.5, p.z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat_block
	add_child(mmi)


## 血河剑冢：暗赤网格圆台 + 一圈赤色界线（踏进去就开打）+ 中心阵纹 + 外围十二根高柱（柱顶赤灯）
## + 插在地上的残剑；出生点东侧地面写一行指路字，沿途一串地标
func _build_boss_arena() -> void:
	var c := BOSS_ARENA
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.5, 0.08, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.18, 0.2)
	glow.emission_energy_multiplier = 1.4
	var disc := MeshInstance3D.new()
	disc.mesh = _cyl_mesh(BOSS_R, 0.04)
	disc.material_override = _grid_mat(Color(0.25, 0.2, 0.22), Color(0.66, 0.3, 0.32), 0.6)
	disc.position = c + Vector3(0, 0.02, 0)
	add_child(disc)
	for r: Vector2 in [Vector2(BOSS_R - 0.6, BOSS_R), Vector2(21.0, 21.5), Vector2(9.0, 9.35)]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r.x
		tm.outer_radius = r.y
		tm.rings = 96
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = glow
		ring.position = c + Vector3(0, 0.05, 0)
		ring.scale = Vector3(1.0, 0.2, 1.0)
		add_child(ring)
	var title := Label3D.new()
	title.text = "血河剑冢"
	title.font = font
	title.font_size = 96
	title.pixel_size = 0.06
	title.modulate = Color(0.45, 0.07, 0.09)
	title.outline_size = 0
	title.rotation_degrees = Vector3(-90, 0, 0)
	title.position = c + Vector3(0, 0.06, 30.0)
	add_child(title)
	# 外围高柱 + 柱顶赤灯：立在脱战线（boss_arena 的 LEAVE_R）外，飞出柱圈即脱战；也不会在打的时候挡镜头
	for i in 12:
		var a := TAU * float(i) / 12.0 + 0.13
		var h := 26.0 + 18.0 * absf(sin(float(i) * 2.3))
		var p := c + Vector3(cos(a), 0.0, sin(a)) * (BOSS_R + 78.0)
		_box(p + Vector3(0, h * 0.5, 0), Vector3(4.0, h, 4.0), false)
		var cap := _box(p + Vector3(0, h + 1.2, 0), Vector3(2.2, 2.4, 2.2), false)
		cap.material_override = glow
	# 残剑：十四柄巨剑斜插在剑冢里
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in 14:
		var a := TAU * float(i) / 14.0 + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(28.0, BOSS_R - 6.0)
		var s := rng.randf_range(6.0, 10.0)
		var sw := MeshLib.make_sword(Color(0.8, 0.12, 0.15))
		var bm := sw.get_meta("blade_mat") as StandardMaterial3D
		bm.albedo_color = Color(0.42, 0.4, 0.42)
		bm.emission_energy_multiplier = 0.25
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.15, 0.45))
		var b := tilt * Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI)  # 剑尖朝下
		sw.transform = Transform3D(b.scaled(Vector3.ONE * s), c + Vector3(cos(a) * r, 0.0, sin(a) * r) - b.y * 0.42 * s)
		add_child(sw)
	# 指路：出生点东侧一行地面字 + 一串地标通向剑冢
	var from := Vector3(40.0, 0.0, 6.0)
	_label("剑冢 · Boss 空战 →", from + Vector3(0, 0.03, -3.0), 2.4, true)
	var d := (c - from).normalized()
	var t := 10.0
	while from.distance_to(c) - t > BOSS_R + 4.0:
		var dash := MeshInstance3D.new()
		dash.mesh = _box_mesh(Vector3(5.0, 0.04, 0.9))
		dash.material_override = glow
		dash.position = from + d * t + Vector3(0, 0.03, 0)
		dash.rotation.y = atan2(-d.z, d.x)
		add_child(dash)
		t += 14.0
	var warn := Label3D.new()
	warn.text = "踏入赤线即开战\n血河剑魔 · 元婴初期"
	warn.font = font
	warn.font_size = 96
	warn.pixel_size = 0.035
	warn.modulate = Color(0.95, 0.3, 0.3)
	warn.outline_size = 12
	warn.outline_modulate = Color(0.08, 0.02, 0.03)
	# 平铺在赤线外的地上、字头朝剑冢：走过来时看得到，开打后不会立在镜头和 Boss 之间
	warn.rotation = Vector3(-PI * 0.5, atan2(-d.x, -d.z), 0.0)
	warn.position = c - d * (BOSS_R + 8.0) + Vector3(0, 0.05, 0)
	add_child(warn)


static func _cyl_mesh(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 96
	return m


static func _box_mesh(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


func _build_walls() -> void:
	var h := 320.0
	_box(Vector3(0, h * 0.5, -HALF), Vector3(HALF * 2.0, h, 12.0), false)
	_box(Vector3(0, h * 0.5, HALF), Vector3(HALF * 2.0, h, 12.0), false)
	_box(Vector3(-HALF, h * 0.5, 0), Vector3(12.0, h, HALF * 2.0), false)
	_box(Vector3(HALF, h * 0.5, 0), Vector3(12.0, h, HALF * 2.0), false)
