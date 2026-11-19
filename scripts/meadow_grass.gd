extends Node3D
## 木兰草原的草：GDQuest WindGrass 原版草叶（grass_triangle.obj + wind_grass 着色器）按 32 米一块拼成围着主角的一圈草环。
## 吉卜力风：一个实例是 4 片收窄的原版草叶攒成的一丛（clump_mesh），草色从根部深绿渐变到草尖的亮黄绿，受光、吃树影和云影。
## 每丛草的 y 取 LOD0 地块网格上的高度（和画出来的地面贴合），陡坡、土路、村中空地、房子里不长，路边逐渐长高；
## 摆放模板只有 4 份，每块草地只是换高度，工作线程里几毫秒一块。原版的角色推草照旧（character_position 每帧给主角位置）。
## 花：flower_field 的花和长草簇换成吉卜力调色（红 / 白 / 淡紫 / 蓝 / 粉），一小撮一小撮同色点缀，偶尔一整丛原版花丛；
## 离主角近的花丛上方飞几群原版蝴蝶。草环外缘在着色器里压矮淡出；离地太高（MAX_ALT）整片不画、也不再建。
## 故意不写 class_name：用 preload 引用。

const MeadowGen := preload("res://scripts/meadow_gen.gd")
const MeadowTerrain := preload("res://scripts/meadow_terrain.gd")
const JobPool := preload("res://scripts/job_pool.gd")
const ObjMesh := preload("res://scripts/obj_mesh.gd")
const Kit := preload("res://scripts/ghibli_kit.gd")
const GRASS_MAT := preload("res://fx/meadow/wind_grass.tres")
const FLOWER_MAT := preload("res://fx/meadow/flower_mat.tres")
const BUTTERFLY_SHADER := preload("res://fx/meadow/butterfly.gdshader")
## 模型走 ObjMesh（导入过用导入的，没导入就现场解析）
const BLADE := "res://fx/meadow/grass_triangle.obj"
const FLOWER_MESH := "res://fx/meadow/flower_1.obj"
const TALL_MESH := "res://fx/meadow/tall_grass_group.obj"
const BUTTERFLY_MESH := "res://fx/meadow/butterfly.obj"
const TILE := MeadowGen.TILE
const RADIUS := 100.0
## 手机档（MeadowLevel.mobile 时打开）：草环半径缩到六成，近处只画不到一半的草丛、远处四分之一 —— 草是这个关卡最大的开销
static var low := false


static func radius() -> float:
	return RADIUS * (0.6 if low else 1.0)

const FULL_R := 56.0         # 这个距离内满密度，外面只画一半
const DENSITY := 3.5         # 每平方米草丛数（一丛 4 片草叶）
const BLADES := 4
const MAX_JOBS := 3
const MAX_ALT := 170.0
const FLIES := 6
const FLY_R := 70.0

static var _patterns: Array[PackedFloat32Array] = []
static var _fly_proc: ParticleProcessMaterial
static var _fly_mat: ShaderMaterial
static var _clump: ArrayMesh
static var _flower_mat: ShaderMaterial

var terrain: MeadowTerrain
var target: Node3D
var grass_mat: ShaderMaterial
var pool := JobPool.new()
var _tiles := {}       # Vector2i -> Node3D；null = 正在算
var _jobs := {}        # job -> Vector2i
var _patch_at := {}    # Vector2i -> PackedVector3Array（花丛中心）
var _flies: Array[GPUParticles3D] = []
var _replan_t := 0.0
var _fly_t := 0.0


static func patterns() -> Array[PackedFloat32Array]:
	if _patterns.is_empty():
		var n := int(TILE * TILE * DENSITY)
		for i in 4:
			_patterns.append(MeadowGen.make_pattern(n, 101 + i))
	return _patterns


static func make_grass_material() -> ShaderMaterial:
	var m := GRASS_MAT.duplicate() as ShaderMaterial
	m.set_shader_parameter("tint_noise", MeadowTerrain.tint_noise())
	m.set_shader_parameter("tint", Color(1.0, 1.0, 1.0))
	m.set_shader_parameter("fade_far", radius() - 6.0)
	m.set_shader_parameter("fade_len", 34.0)
	m.set_shader_parameter("wind_strength", 1.1)
	m.set_shader_parameter("character_push_strength", 2.2)
	# 根部深绿 → 中段草绿 → 草尖亮黄绿（参考 Europa 草地取色）
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.19, 0.38, 0.08), Color(0.40, 0.63, 0.13), Color(0.60, 0.80, 0.22),
			Color(0.80, 0.91, 0.40)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 64
	m.set_shader_parameter("color_ramp", gt)
	Kit.setup_light(m)
	return m


## 一丛草：4 片原版草叶（grass_triangle.obj）收窄、错开、各自往外斜一点，高矮不一
static func clump_mesh() -> ArrayMesh:
	if _clump != null:
		return _clump
	var src := ObjMesh.get_mesh(BLADE)
	var arr := src.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var ids := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		ids = arr[Mesh.ARRAY_INDEX]
	if ids.is_empty():
		for i in vs.size():
			ids.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in BLADES:
		var a := TAU * b / BLADES + rng.randf_range(-0.6, 0.6)
		var off := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.1, 0.55)
		var lean := Basis(Vector3(-sin(a), 0.0, cos(a)), rng.randf_range(0.08, 0.32))
		var bs := lean * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(0.45, rng.randf_range(0.7, 1.15), 0.45))
		for i in ids:
			if not uvs.is_empty():
				st.set_uv(uvs[i])
			if not ns.is_empty():
				st.set_normal((bs * ns[i]).normalized())
			st.add_vertex(bs * vs[i] + off)
	_clump = st.commit()
	return _clump


## flower_field 的 flower_mat 换一张吉卜力调色的颜色表：前半段（茎叶）几种草绿，后半段（花瓣）按 COLOR.x 分档：
## 红 / 珊瑚 / 粉 / 白 / 淡紫 / 蓝 / 黄（分档位置和 MeadowGen.PETALS 对应）
static func flower_mat() -> ShaderMaterial:
	if _flower_mat != null:
		return _flower_mat
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.25, 0.37, 0.5, 0.6, 0.68, 0.76, 0.84, 0.92, 0.97])
	g.colors = PackedColorArray([Color(0.30, 0.52, 0.14), Color(0.38, 0.60, 0.16), Color(0.34, 0.56, 0.18),
			Color(0.44, 0.64, 0.20), Color(0.93, 0.25, 0.24), Color(0.98, 0.47, 0.36), Color(0.96, 0.64, 0.78),
			Color(0.97, 0.96, 0.92), Color(0.64, 0.63, 0.95), Color(0.47, 0.57, 0.93), Color(1.0, 0.85, 0.32)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 256
	_flower_mat = FLOWER_MAT.duplicate() as ShaderMaterial
	_flower_mat.set_shader_parameter("albedo_sampler", gt)
	return _flower_mat


static func _mmi(mesh: Mesh, buf: PackedFloat32Array, stride: int, m: Material, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = int(buf.size() / float(stride))
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 用 MeadowGen.build_tile 的结果搭一块草地（第一个子节点是草叶，后面是花丛两种植株）
static func make_tile_node(tile: Vector2i, r: Dictionary, gmat: Material) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(tile.x * TILE, 0.0, tile.y * TILE)
	var g: PackedFloat32Array = r["grass"]
	root.add_child(_mmi(clump_mesh(), g, 12, gmat, false))
	var t: PackedFloat32Array = r["tall"]
	if not t.is_empty():
		root.add_child(_mmi(ObjMesh.get_mesh(TALL_MESH), t, 16, flower_mat(), true))
	var f: PackedFloat32Array = r["flowers"]
	if not f.is_empty():
		root.add_child(_mmi(ObjMesh.get_mesh(FLOWER_MESH), f, 16, flower_mat(), true))
	return root


## flower_field 原版的蝴蝶粒子（butterfly.obj + butterfly.gdshader + 原版 ParticleProcessMaterial 参数），
## 颜色渐变从原版的单一橙色扩成几种常见蝶色（着色器按 INSTANCE_CUSTOM.z 取色）
static func make_butterflies(amount := 10) -> GPUParticles3D:
	if _fly_proc == null:
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.0))
		curve.add_point(Vector2(0.5, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		var ct := CurveTexture.new()
		ct.curve = curve
		var pm := ParticleProcessMaterial.new()
		pm.particle_flag_align_y = true
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 2.0
		pm.initial_velocity_min = 0.25
		pm.initial_velocity_max = 1.5
		pm.gravity = Vector3.ZERO
		pm.linear_accel_min = 0.5
		pm.linear_accel_max = 1.0
		pm.scale_min = 0.4
		pm.scale_max = 0.6
		pm.scale_curve = ct
		pm.anim_offset_max = 1.0
		pm.turbulence_enabled = true
		pm.turbulence_noise_scale = 4.0
		pm.turbulence_influence_min = 0.05
		pm.turbulence_initial_displacement_min = 2.0
		pm.turbulence_initial_displacement_max = 10.0
		_fly_proc = pm
		var grad := Gradient.new()
		grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		grad.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 0.8])
		grad.colors = PackedColorArray([Color(1, 0.745098, 0.356863), Color(0.98, 0.96, 0.86),
				Color(1.0, 0.86, 0.3), Color(0.55, 0.72, 1.0)])
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		_fly_mat = ShaderMaterial.new()
		_fly_mat.shader = BUTTERFLY_SHADER
		_fly_mat.set_shader_parameter("gradient_sampler", gt)
	var gp := GPUParticles3D.new()
	gp.amount = amount
	gp.lifetime = 10.0
	gp.process_material = _fly_proc
	gp.draw_pass_1 = ObjMesh.get_mesh(BUTTERFLY_MESH)
	gp.material_override = _fly_mat
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-14.0, -4.0, -14.0), Vector3(28.0, 12.0, 28.0))
	return gp


func _ready() -> void:
	grass_mat = make_grass_material()
	patterns()
	for i in FLIES:
		var gp := make_butterflies()
		gp.emitting = false
		gp.visible = false
		add_child(gp)
		_flies.append(gp)


func _exit_tree() -> void:
	pool.drain()


## 出生 / 载入：主角 40 米内的草地块都建好了
func ready_near(p: Vector3) -> bool:
	var pt := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var t := pt + Vector2i(dx, dz)
			var c := Vector2((t.x + 0.5) * TILE - p.x, (t.y + 0.5) * TILE - p.z)
			if c.length() < 40.0 and _tiles.get(t) == null:
				return false
	return true


func tile_count() -> int:
	return _tiles.size()


func _process(dt: float) -> void:
	if target == null or terrain == null:
		return
	var p := target.global_position
	grass_mat.set_shader_parameter("character_position", p)
	var alt := p.y - terrain.height_at(p.x, p.z)
	visible = alt < MAX_ALT
	_replan_t -= dt
	if _replan_t <= 0.0:
		_replan_t = 0.15
		if visible:
			_replan(p)
		elif alt > MAX_ALT + 60.0:
			_drop_all()
	for r: Array in pool.collect():
		var tile: Vector2i = _jobs.get(r[0], Vector2i.ZERO)
		_jobs.erase(r[0])
		if not _tiles.has(tile):
			continue
		var res: Dictionary = r[1]
		var node := make_tile_node(tile, res, grass_mat)
		add_child(node)
		_tiles[tile] = node
		var pc: PackedVector3Array = res["patches"]
		if not pc.is_empty():
			_patch_at[tile] = pc
		_density(node, p)
	_fly_t -= dt
	if _fly_t <= 0.0:
		_fly_t = 0.5
		_update_flies(p)


func _density(node: Node3D, p: Vector3) -> void:
	var c := Vector2(node.position.x + TILE * 0.5 - p.x, node.position.z + TILE * 0.5 - p.z)
	var mi := node.get_child(0) as MultiMeshInstance3D
	var mm := mi.multimesh
	if low:
		mm.visible_instance_count = int(mm.instance_count * (0.42 if c.length() < FULL_R * 0.6 else 0.22))
	else:
		mm.visible_instance_count = -1 if c.length() < FULL_R else int(mm.instance_count * 0.5)


func _replan(p: Vector3) -> void:
	var pt := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	var rt := ceili(radius() / TILE) + 1
	var want: Array = []
	for t: Vector2i in _tiles.keys():
		var node: Node3D = _tiles[t]
		var c := Vector2((t.x + 0.5) * TILE - p.x, (t.y + 0.5) * TILE - p.z)
		if c.length() - TILE * 0.71 > radius() + TILE:
			if node != null:
				node.queue_free()
				_tiles.erase(t)
				_patch_at.erase(t)
		elif node != null:
			_density(node, p)
	for dz in range(-rt, rt + 1):
		for dx in range(-rt, rt + 1):
			var t := pt + Vector2i(dx, dz)
			if _tiles.has(t):
				continue
			var d := Vector2((t.x + 0.5) * TILE - p.x, (t.y + 0.5) * TILE - p.z).length() - TILE * 0.71
			if d <= radius():
				want.append([d, t])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var pats := patterns()
	var n: int = MeadowGen.CELLS[0] + 1
	var sp := MeadowGen.CHUNK / MeadowGen.CELLS[0]
	for w: Array in want:
		if pool.busy() >= MAX_JOBS:
			break
		var t: Vector2i = w[1]
		var key := MeadowGen.key_of(t.x * TILE, t.y * TILE)
		var grid := terrain.lod0_grid(key)
		if grid.is_empty():
			continue  # 脚下这块 LOD0 还没好，下一轮再说
		var gx := key.x * MeadowGen.CHUNK
		var gz := key.y * MeadowGen.CHUNK
		var pat := pats[absi(hash(t)) % pats.size()]
		var g := terrain.gen
		_tiles[t] = null
		var job := pool.submit(func() -> Dictionary: return g.build_tile(t, grid, n, sp, gx, gz, pat))
		_jobs[job] = t


func _drop_all() -> void:
	for t: Vector2i in _tiles.keys():
		var node: Node3D = _tiles[t]
		if node != null:
			node.queue_free()
			_tiles.erase(t)
	_patch_at.clear()


func _update_flies(p: Vector3) -> void:
	var near: Array = []
	if visible:
		for t: Vector2i in _patch_at:
			var pc: PackedVector3Array = _patch_at[t]
			for c: Vector3 in pc:
				var d := c.distance_to(p)
				if d < FLY_R:
					near.append([d, c])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in _flies.size():
		var gp := _flies[i]
		if i < near.size():
			var at: Vector3 = near[i][1] + Vector3.UP * 1.3
			if not gp.emitting or gp.global_position.distance_to(at) > 1.0:
				gp.global_position = at
				gp.visible = true
				gp.emitting = true
		elif gp.emitting:
			gp.emitting = false
			gp.visible = false
