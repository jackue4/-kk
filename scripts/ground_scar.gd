extends Node3D
## 贴地遁光的地面痕迹（player.gd 的 _dun_scrape 一路喂点）：光剑的锋芒把地皮犁开——
## 沿着飞行路线一道断断续续的黑色地裂、往两边岔出细纹，两侧翻起半埋的碎石块，同时溅起一把小碎块；过几秒石块沉回地里、裂纹淡掉。
## 样子照搬 Vfx.ground_break（砸地那一圈地裂 + 翻起的石块）和受击碎块（voxel_debris.gd），材质也是同一种，不用新编着色器。
## 但这里是一路连着出的，不能像 ground_break 那样每块石头一个节点 + 一条补间：
##   · 所有石块共用一个 MultiMesh（环形缓冲，满了顶掉最老的）= 一个绘制调用，只有正在冒出来 / 沉下去的那几块每帧要动
##   · 地裂按段攒成几张网格轮流用（一张几截），加一截才重建一次那一张
##   · 手机档（lite）石块、地裂、碎块都减量
## 没有痕迹的时候自己停掉 _process。故意不写 class_name：用 preload 引用。

const Debris := preload("res://scripts/voxel_debris.gd")

const ROCK_COLS: Array[Color] = [Color(0.5, 0.46, 0.41), Color(0.4, 0.37, 0.34), Color(0.6, 0.56, 0.5), Color(0.33, 0.31, 0.3)]
const HOLD := 4.5          # 石块 / 地裂留多久（秒）
const POP := 0.14          # 石块冒出来用多久
const SINK := 0.9          # 沉回去用多久
const FADE := 1.2          # 地裂淡掉用多久
const CHUNK_SEGS := 7      # 一张地裂网格攒几截
const CRACK_A := 0.9

var lite := false
var rocks_on_screen := 0   # 自检用：此刻还在的石块数

var _mm: MultiMeshInstance3D
var _n := 0
var _next := 0
var _born := PackedFloat32Array()      # < 0 = 空位
var _life := PackedFloat32Array()
var _rest := PackedVector3Array()
var _size := PackedVector3Array()
var _rot: Array[Basis] = []
var _still := PackedByteArray()        # 1 = 已经摆稳了（不用每帧动）
var _clock := 0.0
var _chunks: Array = []                # 每张地裂：[节点, 材质, 顶点, 截数, 最后添加的时刻]
var _cur := -1
var _last := Vector3.INF               # 上一个落点；INF = 断开了
var _chip_at := -10.0
var _chip_n := 0


func _ready() -> void:
	_n = 40 if lite else 72
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = MultiMesh.new()
	_mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_mm.multimesh.use_colors = true
	_mm.multimesh.mesh = Debris.cube_mesh()
	_mm.multimesh.instance_count = _n
	_mm.custom_aabb = AABB(Vector3(-4000.0, -300.0, -4000.0), Vector3(8000.0, 900.0, 8000.0))
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lite else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mm.top_level = true
	add_child(_mm)
	_born.resize(_n)
	_life.resize(_n)
	_rest.resize(_n)
	_size.resize(_n)
	_rot.resize(_n)
	_still.resize(_n)
	for i in _n:
		_born[i] = -1.0
		_rot[i] = Basis.IDENTITY
		_mm.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO))
		_mm.multimesh.set_instance_color(i, Color.WHITE)
	for c in (4 if lite else 6):
		var cm := StandardMaterial3D.new()
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		cm.albedo_color = Color(0.03, 0.03, 0.05, CRACK_A)
		var mi := MeshInstance3D.new()
		mi.mesh = ArrayMesh.new()
		mi.material_override = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_chunks.append([mi, cm, PackedVector3Array(), 0, 0.0])
	set_process(false)


## 这一道断了（飞高了 / 停下了）：下一个点另起一道
func cut() -> void:
	_last = Vector3.INF


## 落一个点。at = 地面上的点，dir = 飞行方向，k = 0~1 贴得有多近（越近石块越多越大、裂纹越宽）
func add(at: Vector3, dir: Vector3, k: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 1e-4 else Vector3.FORWARD
	var s := Vector3(-d.z, 0.0, d.x)
	k = clampf(k, 0.0, 1.0)
	# ---- 地裂 ----
	if _cur < 0 or int(_chunks[_cur][3]) >= CHUNK_SEGS or _clock - float(_chunks[_cur][4]) > 1.0:
		_cur = (_cur + 1) % _chunks.size()
		var fresh: Array = _chunks[_cur]
		(fresh[2] as PackedVector3Array).clear()
		fresh[3] = 0
		(fresh[1] as StandardMaterial3D).albedo_color.a = CRACK_A
	var ch: Array = _chunks[_cur]
	var verts: PackedVector3Array = ch[2]
	var lift := Vector3(0.0, 0.04, 0.0)
	var w := 0.2 + 0.2 * k
	if _last != Vector3.INF and _last.distance_to(at) < 12.0 and absf(_last.y - at.y) < 1.2:
		# 主沟：从上一个点折两折连过来，中间鼓、两头收
		var mid := _last.lerp(at, randf_range(0.4, 0.6)) + s * randf_range(-0.45, 0.45)
		_strip(verts, _last + lift, mid + lift, w * 0.7, w)
		_strip(verts, mid + lift, at + lift, w, w * 0.7)
	# 往两边岔出去的细纹
	for i in (1 if lite else 2):
		var sgn := 1.0 if (i + _chip_n) % 2 == 0 else -1.0
		var ang := atan2(d.z, d.x) + sgn * randf_range(0.55, 1.2)
		_crack(verts, at + lift, ang, randf_range(1.2, 2.4) * (0.6 + 0.6 * k), w * 0.8, 0 if lite else 1)
	ch[3] = int(ch[3]) + 1
	ch[4] = _clock
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := (ch[0] as MeshInstance3D).mesh as ArrayMesh
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	(ch[0] as MeshInstance3D).visible = true
	_last = at
	# ---- 翻起的石块 ----
	var cnt := (1 if lite else 2) + (1 if k > 0.5 else 0)
	for i in cnt:
		var side := (1.0 if (i + _next) % 2 == 0 else -1.0) * randf_range(0.4, 1.3)
		var sz := lerpf(0.26, 0.6, k) * randf_range(0.7, 1.25)
		var j := _next
		_next = (_next + 1) % _n
		_size[j] = Vector3(sz * randf_range(0.8, 1.4), sz * randf_range(0.5, 0.9), sz * randf_range(0.8, 1.3))
		_rest[j] = at + s * side + d * randf_range(-0.9, 0.9) + Vector3(0.0, sz * randf_range(0.05, 0.28), 0.0)
		_rot[j] = Basis.from_euler(Vector3(randf_range(-0.7, 0.7), randf() * TAU, randf_range(-0.7, 0.7)))
		_born[j] = _clock
		_life[j] = HOLD + randf_range(-0.6, 0.6)
		_still[j] = 0
		_mm.multimesh.set_instance_color(j, MeshLib.vcol(ROCK_COLS[randi() % ROCK_COLS.size()]))
	# ---- 溅起来的小碎块（隔一会儿才来一把）----
	if _clock - _chip_at >= (0.34 if lite else 0.2):
		_chip_at = _clock
		_chip_n += 1
		var db := Debris.new()
		db.floor_y = at.y
		db._sound = _chip_n % 3 == 0
		db.top_level = true
		add_child(db)
		db.burst(at + Vector3(0.0, 0.15, 0.0), -d * 0.5 + Vector3.UP, ROCK_COLS, 3 if lite else 5, 4.5 + 3.5 * k, 1.3 + 0.5 * k)
	set_process(true)


func _process(dt: float) -> void:
	_clock += minf(dt, 0.1)
	var busy := false
	var count := 0
	for i in _n:
		var b := _born[i]
		if b < 0.0:
			continue
		busy = true
		count += 1
		var age := _clock - b
		var sz := _size[i]
		if age < POP:
			var e := age / POP
			var p := _rest[i] + Vector3(0.0, -sz.y * (1.0 - e) + sz.y * 0.4 * sin(e * PI), 0.0)
			_mm.multimesh.set_instance_transform(i, Transform3D(_rot[i] * Basis.from_scale(sz * lerpf(0.3, 1.0, e)), p))
		elif age > _life[i]:
			var u := (age - _life[i]) / SINK
			if u >= 1.0:
				_born[i] = -1.0
				_mm.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), _rest[i]))
			else:
				_mm.multimesh.set_instance_transform(i, Transform3D(_rot[i] * Basis.from_scale(sz), _rest[i] - Vector3(0.0, sz.y * 1.7 * u * u, 0.0)))
		elif _still[i] == 0:
			_still[i] = 1
			_mm.multimesh.set_instance_transform(i, Transform3D(_rot[i] * Basis.from_scale(sz), _rest[i]))
	rocks_on_screen = count
	for ci in _chunks.size():
		var ch: Array = _chunks[ci]
		if int(ch[3]) <= 0:
			continue
		busy = true
		var age := _clock - float(ch[4])
		if age > HOLD:
			var a := 1.0 - (age - HOLD) / FADE
			if a <= 0.0:
				ch[3] = 0
				(ch[0] as MeshInstance3D).visible = false
				if ci == _cur:
					_cur = -1
			else:
				(ch[1] as StandardMaterial3D).albedo_color.a = CRACK_A * a
	if not busy:
		_last = Vector3.INF
		set_process(false)


## 一截沟：a → b，两头的宽度各给
static func _strip(verts: PackedVector3Array, a: Vector3, b: Vector3, wa: float, wb: float) -> void:
	var d := b - a
	d.y = 0.0
	if d.length_squared() < 1e-6:
		return
	d = d.normalized()
	var s := Vector3(-d.z, 0.0, d.x)
	verts.append(a - s * wa * 0.5)
	verts.append(a + s * wa * 0.5)
	verts.append(b + s * wb * 0.5)
	verts.append(a - s * wa * 0.5)
	verts.append(b + s * wb * 0.5)
	verts.append(b - s * wb * 0.5)


## 一条裂纹：从 from 沿 ang 走 length，分几段左右摆、越走越细；depth > 0 时中途分一个叉（同 Vfx._crack 的走法）
static func _crack(verts: PackedVector3Array, from: Vector3, ang: float, length: float, width: float, depth: int) -> void:
	var segs := 3
	var p := from
	var a := ang
	for i in segs:
		var w0 := width * (1.0 - float(i) / float(segs))
		var w1 := width * (1.0 - float(i + 1) / float(segs))
		a += randf_range(-0.5, 0.5)
		var q := p + Vector3(cos(a), 0.0, sin(a)) * length / float(segs)
		_strip(verts, p, q, w0, w1)
		if depth > 0 and i == 0:
			_crack(verts, q, a + randf_range(0.5, 0.9) * (1.0 if randf() < 0.5 else -1.0), length * 0.5, w1 * 0.8, depth - 1)
		p = q
