extends MultiMeshInstance3D
## 死亡碎裂 + 消融：把角色按当前姿势拆成一块块小方块（体素角色直接取体素格，2x2x2 合成一块；
## 木人桩这类基本体网格按体积采样），先从命中点向外扫一道"裂纹光"，扫到哪块哪块就崩开、受重力落地弹跳，
## 随后逐块消融——方块被噪声边缘一点点吃掉，边缘烧成亮色，残块褪成灰烬并微微上飘，最后整堆消失。
## CPU 逐块模拟（几百块），用真实时间推进（同 voxel_debris.gd）。
## 故意不写 class_name：用 preload 引用。

const SHADER := preload("res://shaders/voxel_dissolve.gdshader")
const Sfx := preload("res://scripts/sfx.gd")
const GRAV := 20.0
const MAX_DT := 1.0 / 30.0
const WAVE := 0.11          # 裂纹波每米的延迟（秒）

static var _mesh: BoxMesh
static var _active := 0     # 同时存在的碎裂数：太多时调用方用更粗的块

var floor_y := 0.0
var edge := Color(1.0, 0.45, 0.2)

var _rest: Array[Transform3D] = []
var _col := PackedColorArray()
var _p := PackedVector3Array()
var _v := PackedVector3Array()
var _w := PackedVector3Array()
var _q: Array[Basis] = []
var _s := PackedFloat32Array()
var _delay := PackedFloat32Array()
var _melt := PackedFloat32Array()
var _mdur := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _landed := PackedByteArray()
var _t := 0.0
var _chips := 0
var _embers := 0
var _melt_at := 0.0
var _center := Vector3.ZERO


static func active() -> int:
	return _active


static func cube_mesh() -> BoxMesh:
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3.ONE
	return _mesh


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-2000.0, -50.0, -2000.0), Vector3(4000.0, 200.0, 4000.0))
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = cube_mesh()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	material_override = m


func _enter_tree() -> void:
	_active += 1


func _exit_tree() -> void:
	_active -= 1


func add_cube(xf: Transform3D, size: float, color: Color) -> void:
	_rest.append(Transform3D(xf.basis.orthonormalized(), xf.origin))
	_s.append(size)
	_col.append(color)


## 体素角色：src 下所有带 vox_cells 元数据（见 voxel_hero.gd 的 _part）的可见网格，按 group^3 合块
func collect_voxels(src: Node3D, group := 2) -> void:
	for n in src.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.has_meta("vox_cells") or not mi.is_visible_in_tree():
			continue
		var cells: Dictionary = mi.get_meta("vox_cells")
		var unit: float = mi.get_meta("vox_unit")
		var pivot: Vector3 = mi.get_meta("vox_pivot")
		var xf := mi.global_transform
		var sc := xf.basis.get_scale().x
		var chunks := {}
		for k: Vector3i in cells:
			var ck := Vector3i(floori(k.x / float(group)), floori(k.y / float(group)), floori(k.z / float(group)))
			if not chunks.has(ck):
				chunks[ck] = [Vector3.ZERO, 0, cells[k]]
			var e: Array = chunks[ck]
			e[0] += Vector3(k) + Vector3(0.5, 0.5, 0.5)
			e[1] += 1
		var full := float(group * group * group)
		for ck: Vector3i in chunks:
			var e: Array = chunks[ck]
			var cnt: int = e[1]
			var local: Vector3 = (e[0] as Vector3) / float(cnt) - pivot
			var size := unit * group * sc * clampf(pow(float(cnt) / full, 0.33), 0.55, 1.0) * 0.93
			add_cube(Transform3D(xf.basis, xf * (local * unit)), size, e[2])


## 基本体网格（胶囊 / 球 / 圆柱 / 圆环 / 其它按包围盒）：在体积内按 cell 网格采样
func collect_volume(mi: MeshInstance3D, color: Color, cell: float) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	var box := mesh.get_aabb()
	var xf := mi.global_transform
	var nx := maxi(int(ceil(box.size.x / cell)), 1)
	var ny := maxi(int(ceil(box.size.y / cell)), 1)
	var nz := maxi(int(ceil(box.size.z / cell)), 1)
	for ix in nx:
		for iy in ny:
			for iz in nz:
				var p := box.position + Vector3(ix + 0.5, iy + 0.5, iz + 0.5) * cell
				if _inside(mesh, p):
					add_cube(Transform3D(xf.basis, xf * p), cell * 0.92, color)


static func _inside(mesh: Mesh, p: Vector3) -> bool:
	if mesh is CapsuleMesh:
		var c := mesh as CapsuleMesh
		var hy := maxf(c.height * 0.5 - c.radius, 0.0)
		var q := Vector3(p.x, clampf(p.y, -hy, hy), p.z)
		return p.distance_to(q) <= c.radius
	if mesh is SphereMesh:
		var s := mesh as SphereMesh
		return Vector3(p.x / s.radius, p.y / (s.height * 0.5), p.z / s.radius).length() <= 1.0
	if mesh is CylinderMesh:
		var cy := mesh as CylinderMesh
		var u := clampf(p.y / cy.height + 0.5, 0.0, 1.0)
		return Vector2(p.x, p.z).length() <= lerpf(cy.bottom_radius, cy.top_radius, u)
	if mesh is TorusMesh:
		var t := mesh as TorusMesh
		var mid := (t.inner_radius + t.outer_radius) * 0.5
		var r := (t.outer_radius - t.inner_radius) * 0.5
		return Vector2(Vector2(p.x, p.z).length() - mid, p.y).length() <= r
	return true


## 开始碎裂：hit 为命中点（裂纹波从这里扫开），dir 为冲击方向，power 冲击强度
func start(hit: Vector3, dir: Vector3, power := 1.0) -> void:
	var n := _rest.size()
	multimesh.instance_count = n
	_p.resize(n)
	_v.resize(n)
	_w.resize(n)
	_q.resize(n)
	_delay.resize(n)
	_melt.resize(n)
	_mdur.resize(n)
	_seed.resize(n)
	_landed.resize(n)
	_center = Vector3.ZERO
	for i in n:
		_center += _rest[i].origin
	_center /= maxf(float(n), 1.0)
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 1e-4 else Vector3.ZERO
	_melt_at = INF
	for i in n:
		var p := _rest[i].origin
		_p[i] = p
		_q[i] = _rest[i].basis
		var hd := p.distance_to(hit)
		_delay[i] = hd * WAVE + randf() * 0.03
		var out := Vector3(p.x - _center.x, 0.0, p.z - _center.z)
		out = out.normalized() if out.length_squared() > 1e-4 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var near := 1.0 / (1.0 + hd * 1.5)
		_v[i] = (out * randf_range(0.6, 2.4) + d * randf_range(0.8, 3.2) * (0.6 + near)) * power \
				+ Vector3.UP * randf_range(0.3, 2.6) * power
		_w[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(3.0, 11.0)
		_melt[i] = _delay[i] + randf_range(0.6, 1.15) + clampf(p.y - floor_y, 0.0, 2.5) * 0.12
		_mdur[i] = randf_range(0.5, 0.85)
		_melt_at = minf(_melt_at, _melt[i])
		_seed[i] = randf()
		_landed[i] = 0
		multimesh.set_instance_color(i, _col[i].srgb_to_linear())
	mat_edge(edge)
	_step(0.0)


func mat_edge(c: Color) -> void:
	(material_override as ShaderMaterial).set_shader_parameter("edge_color", c)


func _process(dt: float) -> void:
	_step(minf(dt, MAX_DT))


func _step(dt: float) -> void:
	_t += dt
	var alive := false
	for i in _p.size():
		var m := clampf((_t - _melt[i]) / _mdur[i], 0.0, 1.0)
		if m >= 1.0:
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), _p[i]))
			continue
		alive = true
		var size := _s[i]
		var crack := 0.0
		var since := _t - _delay[i]
		if since < 0.0:
			# 还没崩开：原位不动，裂纹光快到时先亮起来
			crack = smoothstep(-0.12, 0.0, since)
			multimesh.set_instance_transform(i, Transform3D(_q[i].scaled(Vector3.ONE * size), _p[i]))
			multimesh.set_instance_custom_data(i, Color(0.0, _seed[i], crack, 0.0))
			continue
		crack = 1.0 - smoothstep(0.0, 0.25, since)
		var v := _v[i]
		var w := _w[i]
		v.y -= GRAV * dt * (1.0 - m)
		if m > 0.0:
			# 消融中：速度散掉，往上飘一点
			var f := exp(-6.0 * dt)
			v = Vector3(v.x * f, lerpf(v.y, 0.7, 1.0 - exp(-5.0 * dt)), v.z * f)
		var p := _p[i] + v * dt
		var half := size * 0.5
		if p.y < floor_y + half:
			p.y = floor_y + half
			if v.y < -1.5 and _landed[i] < 2:
				v = Vector3(v.x * 0.55, -v.y * 0.32, v.z * 0.55)
				w *= 0.5
				_landed[i] += 1
				if _chips < 3:
					_chips += 1
					Sfx.play("chip", -11.0 - 3.0 * _chips, randf_range(0.8, 1.15))
			else:
				var f2 := exp(-10.0 * dt)
				v = Vector3(v.x * f2, maxf(v.y, 0.0), v.z * f2)
				w *= exp(-12.0 * dt)
		_p[i] = p
		_v[i] = v
		_w[i] = w
		var q := _q[i]
		var wl := w.length()
		if wl > 0.01 and dt > 0.0:
			q = q.rotated(w / wl, wl * dt).orthonormalized()
			_q[i] = q
		var k := 1.0 - 0.45 * m * m
		multimesh.set_instance_transform(i, Transform3D(q.scaled(Vector3.ONE * size * k), p))
		multimesh.set_instance_custom_data(i, Color(m, _seed[i], crack, 0.0))
	# 消融开始后，碎块堆上方飘起两拨余烬细丝
	if _embers < 2 and _t >= _melt_at + 0.15 + 0.35 * _embers:
		_embers += 1
		var c := Vector3(_center.x, floor_y + 0.35, _center.z)
		Vfx.ribbon_burst(c, Vector3.UP, edge, 7, 3.5, 55.0, 0.9, Vector3(0, 1.5, 0))
	if not alive:
		queue_free()
