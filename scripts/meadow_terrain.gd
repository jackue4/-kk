extends Node3D
## 木兰草原地形的流式加载。
## · 世界切成 256 米地块，四档精度（4 / 8 / 16 / 32 米一格）；地块网格、碰撞面、石头都在 WorkerThreadPool 里算，
##   主线程每帧只花 BUDGET_MS 毫秒把算好的结果建成网格 / 碰撞，高速飞行也不卡帧。
## · 远景：开场先算一张覆盖全世界（24 公里见方、128 米一格）的粗网格，任何时候没加载到的地方都有它顶着、
##   轮廓和细地块差不多；细地块一出来，远景着色器按 cover_mask 把那一块丢弃，不重叠不打架。
## · 预测：按（平滑后的）水平速度往前看 LOOK_T 秒（最多 LOOK_MAX 米），沿"当前位置 → 预测位置"这条线段
##   每半块取一个采样点，每个采样点周围按 RING 定各地块要的精度（取最细）——飞得越快，前方要加载的越远。
## · 排队：离当前位置越近越先；同样距离，速度方向正前方的先（速度越快，前方加权越重）；
##   还没有细地块的"空洞"先补一块粗的（16 米一格，几毫秒），再按需细化；脚下 3×3 的 LOD0（碰撞）永远最先。
## · 防抖：离开所有采样点 KEEP 块以外才卸载；比需要更细的地块晚一点再降级（也顺手释放碰撞）。
## · 植被：地块数据里带着伞形树 / 灌木 / 白石的实例（见 MeadowGen._flora / _rocks），每次换精度重建一遍 MultiMesh；
##   树 1 公里内都画（LOD2 及更细），灌木只在近处两圈；LOD0 地块给树干加圆柱碰撞、大石头加球碰撞。
## 故意不写 class_name：用 preload 引用。

const MeadowGen := preload("res://scripts/meadow_gen.gd")
const JobPool := preload("res://scripts/job_pool.gd")
const Kit := preload("res://scripts/ghibli_kit.gd")
const TERRAIN_SHADER := preload("res://shaders/meadow_terrain.gdshader")
const CHUNK := MeadowGen.CHUNK
const RING: Array[int] = [1, 2, 4, 8]    # 各精度覆盖半径（地块数，切比雪夫距离）
const KEEP := 10
const MAX_JOBS := 6
const BUDGET_MS := 4.0
const LOOK_T := 1.8
const LOOK_MAX := 1400.0
const REPLAN := 0.12
const HORIZON_CELLS := 192


class Chunk:
	var key: Vector2i
	var lod := -1          # 当前显示的精度（-1 = 只有远景）
	var want := 3
	var busy := false
	var mi: MeshInstance3D
	var body: StaticBody3D
	var flora: Array[Node3D] = []
	var heights := PackedFloat32Array()
	var n := 0


static var _tint: NoiseTexture2D
static var _detail: NoiseTexture2D

var gen: MeadowGen
var target: Player
var view_dir := Vector3.FORWARD     # 几乎不动时，用镜头朝向当"前方"
var pool := JobPool.new()
var mat: ShaderMaterial
var horizon_mat: ShaderMaterial
var horizon_ready := false
## 调试 / 自检用
var finalize_ms := 0.0
var built := 0

var _chunks := {}         # Vector2i -> Chunk
var _jobs := {}           # job -> [key, lod]；远景 key = HORIZON
var _done: Array = []     # 待落地的 [key, lod, 结果]
var _queue: Array = []    # [分数, key, 要建的精度]
var _indices: Array[PackedInt32Array] = []
var _replan_t := 0.0
var _last_key := Vector2i(1 << 20, 0)
var _vel := Vector3.ZERO
var _dir := Vector3.FORWARD
var _speed := 0.0
var _look := 0.0
var _samples: Array[Vector2i] = []
var _mask_img: Image
var _mask_tex: ImageTexture
var _mask_dirty := false
var _horizon: MeshInstance3D

const HORIZON := Vector2i(-1048576, -1048576)


## 地面 / 草共用的色斑噪声（草叶着色器按同一尺度采样，色斑对得上）
static func tint_noise() -> NoiseTexture2D:
	if _tint == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.seed = 11
		fn.frequency = 0.012
		fn.fractal_octaves = 3
		_tint = NoiseTexture2D.new()
		_tint.width = 256
		_tint.height = 256
		_tint.seamless = true
		_tint.generate_mipmaps = true
		_tint.noise = fn
	return _tint


static func detail_noise() -> NoiseTexture2D:
	if _detail == null:
		var fn := FastNoiseLite.new()
		fn.seed = 23
		fn.frequency = 0.03
		fn.fractal_octaves = 2
		_detail = NoiseTexture2D.new()
		_detail.width = 256
		_detail.height = 256
		_detail.seamless = true
		_detail.generate_mipmaps = true
		_detail.noise = fn
	return _detail


static func make_material(is_horizon: bool, g: MeadowGen) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter("tint_noise", tint_noise())
	m.set_shader_parameter("detail_noise", detail_noise())
	m.set_shader_parameter("horizon", is_horizon)
	m.set_shader_parameter("path_pts", g.path_uniform())
	m.set_shader_parameter("path_n", g.path.size())
	m.set_shader_parameter("plaza", g.plaza)
	Kit.setup_light(m)
	return m


static func _flora_mmi(parent: Node3D, mesh: Mesh, buf: PackedFloat32Array, origin: Vector3, shadow: bool) -> Node3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = int(buf.size() / 12.0)
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.position = origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## 用 MeadowGen.build_chunk 的结果把树 / 灌木 / 白石挂到 parent 下（地块原点 origin），返回建出的节点
static func add_flora(parent: Node3D, r: Dictionary, origin: Vector3, lod: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var rocks: PackedFloat32Array = r.get("rocks", PackedFloat32Array())
	if not rocks.is_empty():
		out.append(_flora_mmi(parent, Kit.rock_mesh(), rocks, origin, lod <= 0))
	var trees: Array = r.get("trees", [])
	for v in trees.size():
		var buf: PackedFloat32Array = trees[v]
		if not buf.is_empty():
			out.append(_flora_mmi(parent, Kit.tree_mesh(v), buf, origin, lod <= 1))
	var bushes: Array = r.get("bushes", [])
	for v in bushes.size():
		var buf: PackedFloat32Array = bushes[v]
		if not buf.is_empty():
			out.append(_flora_mmi(parent, Kit.bush_mesh(v), buf, origin, lod <= 0))
	return out


func _ready() -> void:
	mat = make_material(false, gen)
	horizon_mat = make_material(true, gen)
	for c: int in MeadowGen.CELLS:
		_indices.append(MeadowGen.make_indices(c))
	_mask_img = Image.create(MeadowGen.GRID, MeadowGen.GRID, false, Image.FORMAT_R8)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	horizon_mat.set_shader_parameter("cover_mask", _mask_tex)
	horizon_mat.set_shader_parameter("mask_origin", Vector2(-MeadowGen.WORLD_HALF, -MeadowGen.WORLD_HALF))
	horizon_mat.set_shader_parameter("mask_span", MeadowGen.WORLD_HALF * 2.0)
	var g := gen
	var job := pool.submit(func() -> Dictionary: return g.build_horizon(HORIZON_CELLS))
	_jobs[job] = [HORIZON, -1]


func _exit_tree() -> void:
	pool.drain()


func key_of(p: Vector3) -> Vector2i:
	return MeadowGen.key_of(p.x, p.z)


## 画出来的那张地面在 (x, z) 处的高度：有地块用地块网格（和碰撞一致），没有就用噪声原值
func height_at(x: float, z: float) -> float:
	var key := MeadowGen.key_of(x, z)
	var c: Chunk = _chunks.get(key)
	if c != null and c.lod >= 0:
		return MeadowGen.sample_grid(c.heights, c.n, CHUNK / (c.n - 1), key.x * CHUNK, key.y * CHUNK, x, z)
	return gen.height(x, z)


## LOD0 高度网格（草地用）；没有就返回空
func lod0_grid(key: Vector2i) -> PackedFloat32Array:
	var c: Chunk = _chunks.get(key)
	if c != null and c.lod == 0:
		return c.heights
	return PackedFloat32Array()


func chunk_lod(key: Vector2i) -> int:
	var c: Chunk = _chunks.get(key)
	return c.lod if c != null else -1


## 出生 / 载入：远景就绪、脚下 3×3 都有 LOD0（带碰撞）、5×5 内都至少有一块地形
func ready_near(p: Vector3) -> bool:
	if not horizon_ready:
		return false
	var k := key_of(p)
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var l := chunk_lod(k + Vector2i(dx, dz))
			if l < 0 or (maxi(absi(dx), absi(dz)) <= 1 and l != 0):
				return false
	return true


func _process(dt: float) -> void:
	if target == null:
		return
	var t0 := Time.get_ticks_usec()
	var p := target.global_position
	mat.set_shader_parameter("grass_ring_center", p)
	var v := target.velocity
	_vel = _vel.lerp(Vector3(v.x, 0.0, v.z), 1.0 - exp(-dt / 0.35))
	_speed = _vel.length()
	var vd := Vector3(view_dir.x, 0.0, view_dir.z)
	if _speed > 6.0:
		_dir = _vel / _speed
	elif vd.length() > 0.01:
		_dir = vd.normalized()
	_look = clampf(_speed * LOOK_T, 0.0, LOOK_MAX)
	_replan_t -= dt
	var k := key_of(p)
	if _replan_t <= 0.0 or k != _last_key:
		_replan(p)
		_replan_t = REPLAN
		_last_key = k
	_dispatch()
	for r: Array in pool.collect():
		var meta: Array = _jobs.get(r[0], [])
		_jobs.erase(r[0])
		if not meta.is_empty():
			_done.append([meta[0], meta[1], r[1]])
	_finalize(t0)
	if _mask_dirty:
		_mask_tex.update(_mask_img)
		_mask_dirty = false


## 预测位置（调试 / 自检打印用）
func predicted() -> Vector3:
	return target.global_position + _dir * _look


func _replan(p: Vector3) -> void:
	_samples.clear()
	var steps := ceili(_look / (CHUNK * 0.5))
	for s in steps + 1:
		var q := p + _dir * (_look * float(s) / float(maxi(steps, 1)))
		var sk := key_of(q)
		if _samples.is_empty() or _samples[-1] != sk:
			_samples.append(sk)
	# 各采样点周围按距离定精度，取最细
	var r_max: int = RING[3]
	var lod_of_d := PackedInt32Array()
	for d in r_max + 1:
		var l := 3
		for i in 4:
			if d <= RING[i]:
				l = i
				break
		lod_of_d.append(l)
	var want := {}
	for s in _samples:
		for dz in range(-r_max, r_max + 1):
			for dx in range(-r_max, r_max + 1):
				var l := lod_of_d[maxi(absi(dx), absi(dz))]
				var key := Vector2i(s.x + dx, s.y + dz)
				var old: int = want.get(key, 9)
				if l < old:
					want[key] = l
	# 卸载
	for key: Vector2i in _chunks.keys():
		if want.has(key):
			continue
		var c: Chunk = _chunks[key]
		var far := true
		for s in _samples:
			if maxi(absi(key.x - s.x), absi(key.y - s.y)) <= KEEP:
				far = false
				break
		if far and not c.busy:
			_unload(c)
		else:
			c.want = 3
	# 排队
	_queue.clear()
	var pk := key_of(p)
	var speed_k := clampf(_speed / 60.0, 0.0, 1.0)
	for key: Vector2i in want:
		var w: int = want[key]
		var c: Chunk = _chunks.get(key)
		if c == null:
			c = Chunk.new()
			c.key = key
			_chunks[key] = c
		c.want = w
		if c.busy:
			continue
		var near := maxi(absi(key.x - pk.x), absi(key.y - pk.y))
		var build := w
		var score := 0.0
		var to := Vector3((key.x + 0.5) * CHUNK - p.x, 0.0, (key.y + 0.5) * CHUNK - p.z)
		var dist := to.length()
		var fwd := to.dot(_dir) / maxf(dist, 1.0)
		score = dist * (1.0 - 0.55 * fwd * speed_k)
		if c.lod < 0:
			if w < 2 and near > 1:
				build = 2      # 空洞先补粗的
		elif c.lod > w:
			score += 300.0     # 细化排在补洞之后
		elif c.lod < w and (c.lod == 0 or w - c.lod >= 2):
			score += 4000.0    # 降级（省三角面 / 释放碰撞），最后做
		else:
			continue
		if near <= 1 and w == 0 and c.lod != 0:
			build = 0
			score = -100000.0 + dist
		_queue.append([score, key, build])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))


func _dispatch() -> void:
	while pool.busy() < MAX_JOBS and not _queue.is_empty():
		var q: Array = _queue.pop_front()
		var key: Vector2i = q[1]
		var lod: int = q[2]
		var c: Chunk = _chunks.get(key)
		if c == null or c.busy:
			continue
		c.busy = true
		var g := gen
		var job := pool.submit(func() -> Dictionary: return g.build_chunk(key, lod))
		_jobs[job] = [key, lod]


func _finalize(t0: int) -> void:
	var t1 := Time.get_ticks_usec()
	while not _done.is_empty():
		var d: Array = _done.pop_front()
		var key: Vector2i = d[0]
		if key == HORIZON:
			_apply_horizon(d[2])
		else:
			_apply_chunk(key, int(d[1]), d[2])
		built += 1
		if (Time.get_ticks_usec() - t1) * 0.001 > BUDGET_MS:
			break
	finalize_ms = (Time.get_ticks_usec() - t0) * 0.001


func _apply_horizon(r: Dictionary) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r["verts"]
	arrays[Mesh.ARRAY_NORMAL] = r["norms"]
	arrays[Mesh.ARRAY_INDEX] = r["idx"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_horizon = MeshInstance3D.new()
	_horizon.name = "Horizon"
	_horizon.mesh = am
	_horizon.material_override = horizon_mat
	_horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_horizon)
	horizon_ready = true


func _apply_chunk(key: Vector2i, lod: int, r: Dictionary) -> void:
	var c: Chunk = _chunks.get(key)
	if c == null:
		return  # 等它算的时候已经被卸载
	c.busy = false
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r["verts"]
	arrays[Mesh.ARRAY_NORMAL] = r["norms"]
	arrays[Mesh.ARRAY_INDEX] = _indices[lod]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if c.mi == null:
		c.mi = MeshInstance3D.new()
		c.mi.material_override = mat
		c.mi.position = Vector3(key.x * CHUNK, 0.0, key.y * CHUNK)
		add_child(c.mi)
		_set_mask(key, true)
	c.mi.mesh = am
	c.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod <= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.heights = r["heights"]
	c.n = int(r["n"])
	c.lod = lod
	# 碰撞：只有 LOD0
	if lod == 0:
		if c.body == null:
			c.body = StaticBody3D.new()
			c.body.collision_layer = 1
			c.body.collision_mask = 0
			c.body.position = c.mi.position
			add_child(c.body)
		for ch in c.body.get_children():
			ch.free()
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(r["faces"])
		cs.shape = shape
		c.body.add_child(cs)
		var balls: PackedVector4Array = r.get("balls", PackedVector4Array())
		for b: Vector4 in balls:
			var bs := CollisionShape3D.new()
			var sph := SphereShape3D.new()
			sph.radius = b.w
			bs.shape = sph
			bs.position = Vector3(b.x, b.y, b.z)
			c.body.add_child(bs)
		var trunks: PackedVector4Array = r.get("trunks", PackedVector4Array())
		for t: Vector4 in trunks:
			var ts := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = t.w
			cy.height = 5.0
			ts.shape = cy
			ts.position = Vector3(t.x, t.y + 2.4, t.z)
			c.body.add_child(ts)
	elif c.body != null:
		c.body.queue_free()
		c.body = null
	# 树 / 灌木 / 白石：按这次的精度重建
	for f in c.flora:
		f.queue_free()
	c.flora = add_flora(self, r, c.mi.position, lod)


func _unload(c: Chunk) -> void:
	if c.mi != null:
		c.mi.queue_free()
	if c.body != null:
		c.body.queue_free()
	for f in c.flora:
		f.queue_free()
	if c.lod >= 0:
		_set_mask(c.key, false)
	_chunks.erase(c.key)


func _set_mask(key: Vector2i, on: bool) -> void:
	var x := key.x + (MeadowGen.GRID >> 1)
	var y := key.y + (MeadowGen.GRID >> 1)
	if x < 0 or y < 0 or x >= MeadowGen.GRID or y >= MeadowGen.GRID:
		return
	_mask_img.set_pixel(x, y, Color(1.0, 0.0, 0.0) if on else Color(0.0, 0.0, 0.0))
	_mask_dirty = true


## 调试 / 自检：各精度地块数、在算 / 排队数、前方覆盖率（速度方向 ±35°、1.6 公里内的地块已有细网格的比例）
func stats() -> Dictionary:
	var cnt := [0, 0, 0, 0]
	for c: Chunk in _chunks.values():
		if c.lod >= 0:
			cnt[c.lod] += 1
	var p := target.global_position
	var tot := 0
	var hit := 0
	var r := ceili(1600.0 / CHUNK)
	var pk := key_of(p)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var to := Vector3((pk.x + dx + 0.5) * CHUNK - p.x, 0.0, (pk.y + dz + 0.5) * CHUNK - p.z)
			var dl := to.length()
			if dl > 1600.0 or dl < 1.0 or to.dot(_dir) / dl < 0.82:
				continue
			tot += 1
			if chunk_lod(pk + Vector2i(dx, dz)) >= 0:
				hit += 1
	return {"lod": cnt, "jobs": pool.busy(), "queue": _queue.size(), "ahead": float(hit) / maxf(tot, 1.0),
			"under": chunk_lod(pk), "speed": _speed, "look": _look, "ms": finalize_ms}
