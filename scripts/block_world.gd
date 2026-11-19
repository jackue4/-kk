extends Node3D
## 方块世界：搜打撤大世界的场景（替掉原来的草叶 / 花 / 流式草原）。美术参考《我的世界：地下城》：
## 方块台阶地形、压暗的青蓝底色配暖色灯火、发光的水 / 血池 / 晶体靠辉光出氛围，各区域一套配色（见 raid_data.gd 的 REGIONS）。
## · 地形：2 米一格、1 米一级台阶（主角身高约 1.8 米：一格到腰、能自己迈上去）；每格顶面 + 比邻格高出来的侧面。颜色全烘在顶点色里：
##   格子明暗抖动、高低夹角压暗（假 AO）、灯火 / 晶体在地上照亮的一圈（假点光，不用真灯）
## · 点缀物（树、石、灯、骨刺、墓碑、晶簇、浮岛…）直接并进所在地块的网格：一块地 = 一个网格、一次绘制调用
## · 96 米一块，主角周围 near_r 圈细（2 米格、投影），再往外到 view_r 圈粗（4 米格、不投影），更远交给雾
## · 网格在工作线程里算（job_pool.gd），主线程只负责落地；height() 是纯函数，怪 / 掉落 / 镜头都直接问它
## · 不建地形碰撞体：关卡在主角脚下垫一块跟着走的地板，按 height() 摆高度；高一格直接迈上去，
##   高两格以上算墙、要跳或飞（见 meadow_level.gd）
## · 起伏：草原是缓坡；四个外圈区域各有成片的山体 / 台地（高出四五十米），峭壁是一级级的方块
## · 破坏：dig() 把一片格子的高度削到指定高度以下（结丹以上的修士飞进山体时破开一条通道），改过的地块重新生成；
##   改动记在 _dug 里（2 米格 → 高度上限），联机时由 net.gd 同步
## · 光照：近处靠实时阴影；远景（粗地块）没有实时阴影，生成时顺着日光方向探几步、被山挡住的格子直接压暗烘进顶点色
## 故意不写 class_name：用 preload 引用。

const Data := preload("res://scripts/raid_data.gd")
const JobPool := preload("res://scripts/job_pool.gd")
const SHADER := preload("res://shaders/block_world.gdshader")
const SKY_SHADER := preload("res://shaders/block_sky.gdshader")

const CELL := 2.0
const STEP := 1.0
const CHUNK := 96.0
const N := 48
const WATER_H: Array[float] = [3.0, 5.0, 4.0, 3.0, -9.0]   # 各区域水面高度（= Data.REGIONS 的 water_h，热路径上不查字典）
const AO: Array[float] = [1.0, 0.74, 0.58, 0.48]
const MAX_JOBS := 2          # 同时在算的地块数：留出核心给主线程和渲染

var target: Node3D
var mobile := false
var view_r := 5
var near_r := 1
var mat: ShaderMaterial
var pool := JobPool.new()
var built := 0

var _hills := FastNoiseLite.new()
var _mid := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _peaks := FastNoiseLite.new()   # 外圈区域的山体 / 台地
## 被破开的格子：2 米格坐标 → 高度上限。只在主线程换（整表替换，不原地改），工作线程开工时取一份快照
var _dug := {}
var _dug_lock := Mutex.new()
var _dirty := {}               # 高度被改过、要重新生成的地块
const SUN_TO := Vector3(0.62, 0.42, 0.66)   # 指向太阳的方向（和 make_sun 的光线方向相反）
var _pois: Array = []          # {kind, region, pos, r, blend, h}
## 地标的紧凑副本（生成时每格都要查，字典太慢）：x, z, 压平半径, 过渡外径, 高度
var _px := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _pr := PackedFloat32Array()
var _po := PackedFloat32Array()
var _ph := PackedFloat32Array()
var _pal: Array = []           # 每个区域的线性色：[top, top2, dirt, stone, water, light]
var _chunks := {}              # Vector2i -> {node, lod}
var _pending := {}             # Vector2i -> 正在建的精度
var _jobs := {}                # job -> [key, lod]
var _queue: Array = []
var _last_key := Vector2i(1 << 20, 0)
var _replan := 0.0


# ---------- 天空 / 光照 ----------

static func make_environment() -> Environment:
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Data.REGIONS[0]["amb"]
	env.ambient_light_energy = Data.REGIONS[0]["amb_e"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 3.0
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_luminance_cap = 3.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Data.REGIONS[0]["fog"]
	env.fog_density = Data.REGIONS[0]["fog_d"]
	env.fog_aerial_perspective = 0.6     # 远处的东西往天色里融，层层淡下去
	env.fog_sky_affect = 0.45
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.08
	return env


## 主光压得很低（约 24°）：台阶和树拖出长影子
static func make_sun() -> DirectionalLight3D:
	var s := DirectionalLight3D.new()
	s.transform = Transform3D(Basis.looking_at(Vector3(-0.62, -0.42, -0.66).normalized(), Vector3.UP), Vector3.ZERO)
	s.light_color = Data.REGIONS[0]["sun"]
	s.light_energy = Data.REGIONS[0]["sun_e"]
	s.shadow_enabled = true
	s.shadow_blur = 1.4
	s.shadow_opacity = 0.86                       # 影子里留一点底色，不死黑
	s.shadow_bias = 0.06
	s.shadow_normal_bias = 1.4
	s.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	s.directional_shadow_blend_splits = true      # 级联之间过渡，不出现一条硬边
	s.directional_shadow_max_distance = 170.0
	s.directional_shadow_fade_start = 0.82        # 快到头时淡出，接上远景的烘焙日影
	return s


# ---------- 初始化 ----------

func _init() -> void:
	_hills.seed = 9107
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 1.0 / 300.0
	_hills.fractal_octaves = 2
	_mid.seed = 311
	_mid.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mid.frequency = 1.0 / 76.0
	_mid.fractal_octaves = 1
	_ridge.seed = 5501
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 1.0 / 210.0
	_ridge.fractal_octaves = 1
	_peaks.seed = 7717
	_peaks.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_peaks.frequency = 1.0 / 520.0
	_peaks.fractal_octaves = 2
	for r: Dictionary in Data.REGIONS:
		var row: Array = []
		for k: String in ["top", "top2", "dirt", "stone", "water", "light"]:
			row.append(r[k] as Color)   # 顶点色存 sRGB（8 位存线性色暗部会断层），着色器里再转线性
		_pal.append(row)
	for p: Dictionary in Data.pois():
		var d := p.duplicate()
		var pos: Vector2 = d["pos"]
		var wl: float = Data.REGIONS[int(d["region"])]["water_h"]
		d["h"] = maxf(floorf(_raw(pos.x, pos.y) / STEP) * STEP, wl + STEP * 2.0)
		_pois.append(d)
		_px.append(pos.x)
		_pz.append(pos.y)
		_pr.append(float(d["r"]))
		_po.append(float(d["r"]) + float(d["blend"]))
		_ph.append(float(d["h"]))


func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	if mobile:
		view_r = 4
		near_r = 1
	set_process(true)


func _exit_tree() -> void:
	pool.drain()


# ---------- 高度 ----------

## 不含地标压平的原始高度：每个区域一种地貌，按权重混（扇区权重和 Data.region_weights 同一套算法）
func _raw(x: float, z: float) -> float:
	var n1 := _hills.get_noise_2d(x, z)
	var n2 := _mid.get_noise_2d(x, z)
	var h := 7.5 + n1 * 6.5 + n2 * 2.0                      # 草原：缓坡，洼处有水
	var r := sqrt(x * x + z * z)
	var outer := smoothstep(Data.R0 - Data.BLEND, Data.R0 + Data.BLEND, r)
	if outer > 0.0:
		var dx := x / maxf(r, 1.0)
		var dz := z / maxf(r, 1.0)
		var s0 := smoothstep(0.55, 0.85, -dz)
		var s1 := smoothstep(0.55, 0.85, dx)
		var s2 := smoothstep(0.55, 0.85, dz)
		var s3 := smoothstep(0.55, 0.85, -dx)
		var rg := 1.0 - absf(_ridge.get_noise_2d(x, z))
		var pk := _peaks.get_noise_2d(x, z) * 0.5 + 0.5     # 山体 / 台地的分布
		var ho := 0.0
		if s0 > 0.0:
			# 黄枫谷：山岭起伏，谷底有湖；成片的枫山
			ho += s0 * (13.0 + n1 * 13.0 + rg * rg * 9.0 + n2 * 3.0 + smoothstep(0.5, 0.72, pk) * 42.0)
		if s1 > 0.0:
			# 血色禁地：尖脊 + 血池洼地；暗红的高崖
			ho += s1 * (5.5 + n1 * 7.0 + rg * rg * rg * rg * 26.0 + n2 * 3.0 + smoothstep(0.52, 0.7, pk) * 36.0)
		if s2 > 0.0:
			# 阴冥之地：一片沼泽，零星立着陡峭的石台
			ho += s2 * (5.4 + n1 * 4.0 + n2 * 2.0 + smoothstep(0.6, 0.66, pk) * 30.0)
		if s3 > 0.0:
			# 坠魔谷：高台地被深裂谷切开
			ho += s3 * (11.0 + n1 * 9.0 + n2 * 3.0 - smoothstep(0.9, 0.975, rg) * 34.0 + smoothstep(0.45, 0.7, pk) * 48.0)
		h = lerpf(h, ho / (s0 + s1 + s2 + s3 + 1e-4), outer)
	if r > Data.PLAY_R:
		h += smoothstep(Data.PLAY_R, Data.PLAY_R + 240.0, r) * (80.0 + n2 * 30.0)
	return h


func _shaped(x: float, z: float) -> float:
	var h := _raw(x, z)
	for i in _px.size():
		var dx := x - _px[i]
		var dz := z - _pz[i]
		var rr := _po[i]
		if absf(dx) < rr and absf(dz) < rr:
			h = lerpf(h, _ph[i], 1.0 - smoothstep(_pr[i], rr, sqrt(dx * dx + dz * dz)))
	return h


static func _hash(ix: int, iz: int) -> float:
	var n := (ix * 374761393 + iz * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


## (x, z) 归哪个区域：边界按格子抖一抖，过渡带是犬牙交错的方块而不是一条直线
func _region(x: float, z: float, jit: float) -> int:
	var j := (jit - 0.5) * 70.0
	x += j
	z -= j
	var r := sqrt(x * x + z * z)
	if r < Data.R0:      # smoothstep 在 R0 处正好是 0.5
		return 0
	var dx := x / r
	var dz := z / r
	# 四个扇区的权重是同一个单调函数，比方向分量就行
	var best := 1
	var bv := -dz
	if dx > bv:
		bv = dx
		best = 2
	if dz > bv:
		bv = dz
		best = 3
	if -dx > bv:
		best = 4
	return best


## 一格的信息（cs = 格子边长）：[顶面高度, 区域, 是不是水面, 是不是地标的石板地]
func _cell(ix: int, iz: int, cs: float, dug: Dictionary) -> Array:
	var x := (float(ix) + 0.5) * cs
	var z := (float(iz) + 0.5) * cs
	var q := floorf(_shaped(x, z) / STEP) * STEP
	if not dug.is_empty():
		var dk := Vector2i(int(floorf(x / CELL)), int(floorf(z / CELL)))
		if dug.has(dk):
			q = minf(q, float(dug[dk]))
	var ri := _region(x, z, _hash(ix * 3 + 1, iz * 3 + 2))
	var wl: float = WATER_H[ri]
	if q < wl:
		return [wl - 0.5, ri, true, false]
	var paved := false
	for i in _px.size():
		var dx := x - _px[i]
		var dz := z - _pz[i]
		if dx * dx + dz * dz < _pr[i] * _pr[i]:
			paved = true
	return [q, ri, false, paved]


## 地面高度（玩法用）：水里能蹚，水面下 1 米算底
func height(x: float, z: float) -> float:
	var ix := int(floorf(x / CELL))
	var iz := int(floorf(z / CELL))
	var cx := (float(ix) + 0.5) * CELL
	var cz := (float(iz) + 0.5) * CELL
	var q := floorf(_shaped(cx, cz) / STEP) * STEP
	if not _dug.is_empty():
		var dk := Vector2i(ix, iz)
		if _dug.has(dk):
			q = minf(q, float(_dug[dk]))
	var wl: float = WATER_H[_region(cx, cz, _hash(ix * 3 + 1, iz * 3 + 2))]
	return maxf(q, wl - 0.9)


## 破开地形：把 center 周围 radius 米内的格子削到 floor_y 以下（只降不升）。返回削了几格。
## 改过的地块会重新生成（工作线程，稍后落地）；height() 立刻就按新高度算。
func dig(center: Vector3, radius: float, floor_y: float) -> int:
	var fy := floorf(floor_y / STEP) * STEP
	var n := int(ceilf(radius / CELL))
	var cx := int(floorf(center.x / CELL))
	var cz := int(floorf(center.z / CELL))
	var changes := {}
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			var ix := cx + dx
			var iz := cz + dz
			var px := (float(ix) + 0.5) * CELL
			var pz := (float(iz) + 0.5) * CELL
			if Vector2(px - center.x, pz - center.z).length() > radius:
				continue
			if height(px, pz) > fy + 0.01:
				changes[Vector2i(ix, iz)] = fy
	if changes.is_empty():
		return 0
	apply_dug(changes)
	return changes.size()


## 把一批「格子 → 高度上限」并进破坏表（联机同步也走这里）。整表替换，保证工作线程手里的快照不被改
func apply_dug(changes: Dictionary) -> void:
	var nd := _dug.duplicate()
	for k: Vector2i in changes.keys():
		var v := float(changes[k])
		if not nd.has(k) or float(nd[k]) > v:
			nd[k] = v
		# 所在地块、以及贴着边界时的邻块都要重建
		var wx := (float(k.x) + 0.5) * CELL
		var wz := (float(k.y) + 0.5) * CELL
		for ox: float in [-CELL, 0.0, CELL]:
			for oz: float in [-CELL, 0.0, CELL]:
				_dirty[Vector2i(int(floorf((wx + ox) / CHUNK)), int(floorf((wz + oz) / CHUNK)))] = true
	_dug_lock.lock()
	_dug = nd
	_dug_lock.unlock()


## 整张破坏表（联机：房主发给中途加入的人）
func dug_table() -> Dictionary:
	return _dug


func poi_height(pos: Vector2) -> float:
	return height(pos.x, pos.y)


# ---------- 分块调度 ----------

func key_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floorf(p.x / CHUNK)), int(floorf(p.z / CHUNK)))


func ready_near(p: Vector3) -> bool:
	var k := key_of(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c: Variant = _chunks.get(k + Vector2i(dx, dz))
			if c == null or int((c as Dictionary)["lod"]) != 0:
				return false
	return true


func chunk_count() -> int:
	return _chunks.size()


func _process(dt: float) -> void:
	if target == null:
		return
	var k := key_of(target.global_position)
	_replan -= dt
	if k != _last_key or _replan <= 0.0:
		_last_key = k
		_replan = 0.5
		_plan(k)
	# 被破开的地块优先重建（保持原来的精度）
	for dk: Vector2i in _dirty.keys():
		if pool.busy() >= MAX_JOBS + 1:
			break
		if _pending.has(dk):
			continue
		_dirty.erase(dk)
		var dc: Variant = _chunks.get(dk)
		if dc != null:
			var dl := int((dc as Dictionary)["lod"])
			_pending[dk] = dl
			_jobs[pool.submit(_build.bind(dk, dl))] = [dk, dl]
	while pool.busy() < MAX_JOBS and not _queue.is_empty():
		var e: Array = _queue.pop_front()
		var key: Vector2i = e[1]
		var lod: int = e[2]
		_pending[key] = lod
		_jobs[pool.submit(_build.bind(key, lod))] = [key, lod]
	for r: Array in pool.collect():
		var info: Array = _jobs[r[0]]
		_jobs.erase(r[0])
		_pending.erase(info[0])
		_apply(info[0], info[1], r[1])


func _plan(k: Vector2i) -> void:
	_queue.clear()
	for dx in range(-view_r, view_r + 1):
		for dz in range(-view_r, view_r + 1):
			if dx * dx + dz * dz > view_r * view_r + 2:
				continue
			var key := k + Vector2i(dx, dz)
			var lod := 0 if maxi(absi(dx), absi(dz)) <= near_r else 1
			if _pending.has(key):
				continue
			var c: Variant = _chunks.get(key)
			if c != null:
				var cl := int((c as Dictionary)["lod"])
				# 已经是细的就留着（走远一圈再降），免得在边界上来回重建
				if cl == lod or (cl == 0 and maxi(absi(dx), absi(dz)) <= near_r + 1):
					continue
			_queue.append([dx * dx + dz * dz + (0 if lod == 0 else 4), key, lod])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for key: Vector2i in _chunks.keys():
		var d := key - k
		if d.x * d.x + d.y * d.y > (view_r + 1) * (view_r + 1) + 2:
			((_chunks[key] as Dictionary)["node"] as Node).queue_free()
			_chunks.erase(key)


func _apply(key: Vector2i, lod: int, r: Dictionary) -> void:
	var old: Variant = _chunks.get(key)
	if old != null:
		((old as Dictionary)["node"] as Node).queue_free()
	var d := key - _last_key
	if d.x * d.x + d.y * d.y > (view_r + 1) * (view_r + 1) + 2:
		_chunks.erase(key)
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r["v"]
	arrays[Mesh.ARRAY_NORMAL] = r["n"]
	arrays[Mesh.ARRAY_COLOR] = r["c"]
	arrays[Mesh.ARRAY_INDEX] = r["i"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_chunks[key] = {"node": mi, "lod": lod}
	built += 1


# ---------- 生成（工作线程） ----------

## 这块地里的灯火 / 发光物：[位置, 区域, 种类]；种类 0 灯 1 晶体 / 蘑菇。邻块也要问（把光烘到自己的地面上）
func _lights(key: Vector2i, dug: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x51ed
	var out: Array = []
	for i in 3:
		var x := (float(key.x) + rng.randf()) * CHUNK
		var z := (float(key.y) + rng.randf()) * CHUNK
		var kind := 0 if i == 0 else 1
		if rng.randf() > (0.75 if i == 0 else 0.6):
			continue
		var ix := int(floorf(x / CELL))
		var iz := int(floorf(z / CELL))
		var c := _cell(ix, iz, CELL, dug)
		if c[2] or c[3]:
			continue
		out.append([Vector3((float(ix) + 0.5) * CELL, float(c[0]), (float(iz) + 0.5) * CELL), int(c[1]), kind])
	return out


## 远景的烘焙日影：顺着日光方向探四步，前面有比光线还高的地形就算在阴影里
func _sun_blocked(x: float, y: float, z: float) -> bool:
	for t: float in [5.0, 12.0, 24.0, 44.0]:
		if _shaped(x + SUN_TO.x * t, z + SUN_TO.z * t) > y + SUN_TO.y * t + 1.5:
			return true
	return false


func _build(key: Vector2i, lod: int) -> Dictionary:
	_dug_lock.lock()
	var dug := _dug
	_dug_lock.unlock()
	var cs := CELL if lod == 0 else 6.0     # 远景 6 米一格
	var n := N if lod == 0 else 16
	var m := n + 2
	var bx := key.x * n
	var bz := key.y * n
	var hs := PackedFloat32Array()
	var rg := PackedInt32Array()
	var fl := PackedInt32Array()     # 1 水面 2 石板地
	hs.resize(m * m)
	rg.resize(m * m)
	fl.resize(m * m)
	for j in m:
		for i in m:
			var c := _cell(bx + i - 1, bz + j - 1, cs, dug)
			hs[j * m + i] = c[0]
			rg[j * m + i] = c[1]
			fl[j * m + i] = 1 if c[2] else (2 if c[3] else 0)
	# 灯火：自己的 + 八个邻块的
	var lights: Array = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			lights.append_array(_lights(key + Vector2i(dx, dz), dug))
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var cl := PackedColorArray()
	var ix := PackedInt32Array()
	var skirt := 0.0 if lod == 0 else 3.0
	var offs := PackedInt32Array([-1, 1, -m, m])
	for j in range(1, n + 1):
		for i in range(1, n + 1):
			var k := j * m + i
			var y := hs[k]
			var ri := rg[k]
			var pal: Array = _pal[ri]
			var gx := bx + i - 1
			var gz := bz + j - 1
			var x0 := float(gx) * cs
			var z0 := float(gz) * cs
			var hsh := _hash(gx, gz)
			var water := fl[k] == 1
			var top: Color
			var em := 0.0
			if water:
				top = (pal[4] as Color) * (0.82 + 0.3 * hsh)
				em = float(Data.REGIONS[ri]["water_e"]) * (0.7 + 0.5 * hsh)
			elif fl[k] == 2:
				top = (pal[3] as Color) * (1.5 if (gx + gz) % 2 == 0 else 1.2) * (0.9 + 0.2 * hsh)
			else:
				var patch := clampf(0.5 + _mid.get_noise_2d(x0 * 2.3 + 40.0, z0 * 2.3) * 1.4 + (hsh - 0.5) * 0.5, 0.0, 1.0)
				top = (pal[0] as Color).lerp(pal[1], patch) * (0.82 + 0.36 * hsh)
				# 紧挨着水的一圈是泥地；比四邻高出一大截的是裸岩
				if fl[k - 1] == 1 or fl[k + 1] == 1 or fl[k - m] == 1 or fl[k + m] == 1:
					top = top.lerp((pal[2] as Color) * 0.9, 0.7)
				var hi := maxf(maxf(y - hs[k - 1], y - hs[k + 1]), maxf(y - hs[k - m], y - hs[k + m]))
				if hi >= 4.0:
					top = (pal[3] as Color) * (1.0 + 0.5 * hsh)
			# 远景没有实时阴影：被山挡住日光的格子直接压暗、偏冷
			if lod == 1 and not water and _sun_blocked(x0 + cs * 0.5, y, z0 + cs * 0.5):
				top = Color(top.r * 0.6, top.g * 0.64, top.b * 0.76)
			# 灯火照亮
			var lit := Color(0, 0, 0)
			var c3 := Vector3(x0 + cs * 0.5, y, z0 + cs * 0.5)
			for l: Array in lights:
				var lp: Vector3 = l[0]
				var rad := 22.0 if int(l[2]) == 0 else 13.0
				var d2 := (lp.x - c3.x) * (lp.x - c3.x) + (lp.z - c3.z) * (lp.z - c3.z) + (lp.y - c3.y) * (lp.y - c3.y) * 2.0
				if d2 < rad * rad:
					var f := 1.0 - sqrt(d2) / rad
					lit += (_pal[int(l[1])][5] as Color) * (f * f * (1.0 if int(l[2]) == 0 else 0.7))
			var lum := lit.r + lit.g + lit.b
			if not water and lum > 0.0:
				top = top + lit * 0.55 + top * lit * 2.0
				em = minf(lum * 0.16, 0.3)
			# 顶面：四个角按相邻更高的格子数压暗
			var b := v.size()
			for corner in 4:
				var cx := 1 if corner == 1 or corner == 2 else 0
				var cz := 1 if corner >= 2 else 0
				var sx := cx * 2 - 1
				var sz := cz * 2 - 1
				var occ := 0
				if not water:
					if hs[k + sx] > y + 0.1:
						occ += 1
					if hs[k + sz * m] > y + 0.1:
						occ += 1
					if hs[k + sx + sz * m] > y + 0.1:
						occ += 1
				var ao := AO[occ]
				v.append(Vector3(x0 + cs * float(cx), y, z0 + cs * float(cz)))
				nr.append(Vector3.UP)
				cl.append(Color(minf(top.r * ao, 1.0), minf(top.g * ao, 1.0), minf(top.b * ao, 1.0), em))
			ix.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
			# 侧面：四邻里比自己矮的那几面
			var wt: Color = (pal[4] as Color) * 0.7 if water else (pal[2] as Color) * (0.85 + 0.3 * hsh) + lit * 0.3
			var wb: Color = (pal[4] as Color) * 0.4 if water else (pal[3] as Color) * 0.5
			var wem := em * 0.6
			for side in 4:
				var nk: int = k + offs[side]
				var ny := hs[nk]
				var edge := (side == 0 and i == 1) or (side == 1 and i == n) or (side == 2 and j == 1) or (side == 3 and j == n)
				if edge:
					ny -= skirt
				if ny >= y - 0.05:
					continue
				var p0: Vector3
				var p1: Vector3
				var nn: Vector3
				match side:
					0:
						p0 = Vector3(x0, y, z0 + cs)
						p1 = Vector3(x0, y, z0)
						nn = Vector3.LEFT
					1:
						p0 = Vector3(x0 + cs, y, z0)
						p1 = Vector3(x0 + cs, y, z0 + cs)
						nn = Vector3.RIGHT
					2:
						p0 = Vector3(x0, y, z0)
						p1 = Vector3(x0 + cs, y, z0)
						nn = Vector3.FORWARD
					_:
						p0 = Vector3(x0 + cs, y, z0 + cs)
						p1 = Vector3(x0, y, z0 + cs)
						nn = Vector3.BACK
				var wb2 := v.size()
				v.append(p0)
				v.append(p1)
				v.append(Vector3(p1.x, ny, p1.z))
				v.append(Vector3(p0.x, ny, p0.z))
				for _q in 4:
					nr.append(nn)
				var wtc := Color(minf(wt.r, 1.0), minf(wt.g, 1.0), minf(wt.b, 1.0), wem)
				cl.append(wtc)
				cl.append(wtc)
				cl.append(Color(wb.r, wb.g, wb.b, 0.0))
				cl.append(Color(wb.r, wb.g, wb.b, 0.0))
				ix.append_array([wb2, wb2 + 2, wb2 + 1, wb2, wb2 + 3, wb2 + 2])
	var a := [v, nr, cl, ix]
	_props(key, lod, a, dug)
	return {"v": a[0], "n": a[1], "c": a[2], "i": a[3]}


# ---------- 点缀物 ----------

const BOX_F := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]
const BOX_S := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]


## 一个方块：c 是线性色；底下四个角压暗一点（假 AO）；em = 自发光。不画底面。
static func _box(a: Array, size: Vector3, xf: Transform3D, c: Color, em := 0.0, shade := 0.72) -> void:
	var v: PackedVector3Array = a[0]
	var nr: PackedVector3Array = a[1]
	var cl: PackedColorArray = a[2]
	var ix: PackedInt32Array = a[3]
	var h := size * 0.5
	for fi in 6:
		if fi == 3:
			continue
		var f: Array = BOX_F[fi]
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var wn := (xf.basis * n).normalized()
		var b := v.size()
		for sg: Vector2 in BOX_S:
			var lp: Vector3 = (n + u * sg.x + w * sg.y) * h
			var k := 1.0 if lp.y > 0.0 or em > 0.0 else shade
			if fi == 2:
				k = 1.08
			v.append(xf * lp)
			nr.append(wn)
			cl.append(Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), minf(em, 1.0)))
		ix.append_array([b, b + 2, b + 1, b, b + 3, b + 2])
	a[0] = v
	a[1] = nr
	a[2] = cl
	a[3] = ix


static func _lin(c: Color) -> Color:
	return c


static func _xf(p: Vector3, yaw := 0.0, tilt := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_euler(tilt), p)


func _props(key: Vector2i, lod: int, a: Array, dug: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x9e37
	var near := lod == 0
	# 灯火 / 发光物本体（只画自己这块的）
	for l: Array in _lights(key, dug):
		var lp: Vector3 = l[0]
		var ri := int(l[1])
		var lc: Color = _pal[ri][5]
		if int(l[2]) == 0:
			_lantern(a, lp, ri, lc, rng)
		else:
			_glow_prop(a, lp, ri, lc, rng, near)
	var count := 30
	for i in count:
		var x := (float(key.x) + rng.randf()) * CHUNK
		var z := (float(key.y) + rng.randf()) * CHUNK
		var roll := rng.randf()
		var s := rng.randf_range(0.8, 1.35)
		var yaw := float(rng.randi() % 4) * PI * 0.5 + rng.randf_range(-0.2, 0.2)
		var sd := rng.randi()
		var gxi := int(floorf(x / CELL))
		var gzi := int(floorf(z / CELL))
		var c := _cell(gxi, gzi, CELL, dug)
		if c[2] or c[3]:
			continue
		if dug.has(Vector2i(gxi, gzi)):
			continue      # 被破开的地方不长东西
		var ri: int = c[1]
		var p := Vector3((float(gxi) + 0.5) * CELL, float(c[0]), (float(gzi) + 0.5) * CELL)
		# 树林有疏有密
		var grove := 0.5 + _mid.get_noise_2d(x * 0.6 + 900.0, z * 0.6 - 300.0)
		var r2 := RandomNumberGenerator.new()
		r2.seed = sd
		match ri:
			0:
				if roll < 0.34 * grove + 0.08:
					_pine(a, p, s, r2)
				elif roll < 0.62:
					if near:
						_rock(a, p, s, ri, r2)
				elif roll < 0.72:
					if near:
						_bush(a, p, s, _lin(Color(0.16, 0.44, 0.3)), r2)
				elif roll < 0.76:
					_pillar(a, p, s, ri, r2)
			1:
				if roll < 0.5 * grove + 0.12:
					_maple(a, p, s * 1.15, r2)
				elif roll < 0.72:
					if near:
						_leaf_pile(a, p, s, r2)
				elif roll < 0.84:
					if near:
						_rock(a, p, s, ri, r2)
				elif roll < 0.88:
					_pillar(a, p, s, ri, r2)
			2:
				if roll < 0.22:
					_dead_tree(a, p, s * 1.2, yaw, _lin(Color(0.1, 0.05, 0.06)))
				elif roll < 0.46:
					_bones(a, p, s, yaw)
				elif roll < 0.7:
					if near:
						_rock(a, p, s, ri, r2)
				elif roll < 0.8:
					_spike(a, p, s * 1.3, r2, _lin(Color(0.13, 0.1, 0.12)))
			3:
				if roll < 0.24:
					_dead_tree(a, p, s * 1.3, yaw, _lin(Color(0.07, 0.1, 0.13)))
				elif roll < 0.52:
					if near:
						_tomb(a, p, s, yaw)
				elif roll < 0.62:
					_pillar(a, p, s, ri, r2)
				elif roll < 0.74:
					if near:
						_rock(a, p, s, ri, r2)
			_:
				if roll < 0.2:
					_spike(a, p, s * 1.5, r2, _lin(Color(0.16, 0.12, 0.24)))
				elif roll < 0.3:
					_island(a, p, s, ri, r2)
				elif roll < 0.5:
					if near:
						_rock(a, p, s, ri, r2)
				elif roll < 0.6:
					_dead_tree(a, p, s * 1.2, yaw, _lin(Color(0.12, 0.08, 0.18)))
				elif roll < 0.66:
					_pillar(a, p, s, ri, r2)


## 石灯 / 灯笼 / 鬼灯：一根柱子顶着一块发光的方块
func _lantern(a: Array, p: Vector3, ri: int, lc: Color, rng: RandomNumberGenerator) -> void:
	var st: Color = (_pal[ri][3] as Color) * 1.3
	_box(a, Vector3(1.3, 0.5, 1.3), _xf(p + Vector3(0, 0.25, 0)), st)
	_box(a, Vector3(0.5, 2.6, 0.5), _xf(p + Vector3(0, 1.8, 0)), st * 0.8)
	_box(a, Vector3(1.0, 1.0, 1.0), _xf(p + Vector3(0, 3.6, 0)), lc, 1.0)
	_box(a, Vector3(1.5, 0.3, 1.5), _xf(p + Vector3(0, 4.25, 0)), st * 0.7)
	if rng.randf() < 0.5:
		_box(a, Vector3(0.6, 0.3, 0.6), _xf(p + Vector3(0, 4.55, 0)), st * 0.7)


## 发光的点缀：草原灵菇 / 枫谷灯笼果 / 血晶 / 鬼火 / 紫晶簇
func _glow_prop(a: Array, p: Vector3, ri: int, lc: Color, rng: RandomNumberGenerator, near: bool) -> void:
	match ri:
		0, 1:
			var stem := _lin(Color(0.8, 0.78, 0.66))
			for i in (3 if near else 1):
				var o := Vector3(rng.randf_range(-1.4, 1.4), 0.0, rng.randf_range(-1.4, 1.4)) if i > 0 else Vector3.ZERO
				var hgt := rng.randf_range(0.6, 1.6) if i > 0 else 2.0
				_box(a, Vector3(0.3, hgt, 0.3), _xf(p + o + Vector3(0, hgt * 0.5, 0)), stem)
				_box(a, Vector3(0.5 + hgt * 0.5, 0.4, 0.5 + hgt * 0.5), _xf(p + o + Vector3(0, hgt + 0.2, 0)), lc, 0.85)
		3:
			for i in 3:
				var o := Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(1.2, 4.0), rng.randf_range(-2.0, 2.0))
				_box(a, Vector3.ONE * rng.randf_range(0.3, 0.6), _xf(p + o, rng.randf() * TAU, Vector3(0.6, 0, 0.6)), lc, 1.0)
		_:
			for i in 4:
				var o := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2)) if i > 0 else Vector3.ZERO
				var hgt := rng.randf_range(1.2, 3.0) if i > 0 else rng.randf_range(3.5, 5.5)
				var tilt := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)) if i > 0 else Vector3.ZERO
				_box(a, Vector3(0.7, hgt, 0.7), _xf(p + o + Vector3(0, hgt * 0.45, 0), rng.randf() * TAU, tilt), lc * 0.85, 0.75)


## 草原的杉树：深色树干 + 四层越来越小的方块树冠
func _pine(a: Array, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var trunk := _lin(Color(0.25, 0.17, 0.13))
	var l0 := _lin(Color(0.07, 0.3, 0.27))
	var l1 := _lin(Color(0.12, 0.42, 0.3))
	var th := rng.randf_range(2.5, 4.0) * s
	_box(a, Vector3(0.9, th, 0.9) * Vector3(s, 1, s), _xf(p + Vector3(0, th * 0.5, 0)), trunk)
	var y := th
	var w := 5.0 * s
	for i in 4:
		var hh := 1.7 * s
		_box(a, Vector3(w, hh, w), _xf(p + Vector3(0, y + hh * 0.5, 0), 0.0), l0.lerp(l1, float(i) / 3.0 + rng.randf_range(-0.15, 0.15)), 0.0, 0.6)
		y += hh * 0.92
		w *= 0.68


## 黄枫谷的枫树：歪一点的树干 + 三四团红 / 橙 / 金的树冠
func _maple(a: Array, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var trunk := _lin(Color(0.2, 0.12, 0.1))
	var cols := [_lin(Color(0.86, 0.2, 0.08)), _lin(Color(0.98, 0.42, 0.08)), _lin(Color(1.0, 0.68, 0.14)), _lin(Color(0.7, 0.12, 0.08))]
	var th := rng.randf_range(4.0, 6.0) * s
	_box(a, Vector3(1.0 * s, th, 1.0 * s), _xf(p + Vector3(0, th * 0.5, 0)), trunk)
	var top := p + Vector3(0, th, 0)
	_box(a, Vector3(6.0, 2.6, 6.0) * s, _xf(top + Vector3(0, 0.8 * s, 0)), cols[rng.randi() % 4], 0.0, 0.6)
	for i in 3:
		var o := Vector3(rng.randf_range(-2.4, 2.4), rng.randf_range(1.2, 3.2), rng.randf_range(-2.4, 2.4)) * s
		var w := rng.randf_range(2.6, 4.2) * s
		_box(a, Vector3(w, w * 0.6, w), _xf(top + o), cols[rng.randi() % 4], 0.0, 0.62)


func _leaf_pile(a: Array, p: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var cols := [_lin(Color(0.9, 0.3, 0.08)), _lin(Color(1.0, 0.6, 0.12)), _lin(Color(0.74, 0.16, 0.08))]
	for i in 3:
		var o := Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
		var w := rng.randf_range(0.8, 1.8) * s
		_box(a, Vector3(w, 0.16, w), _xf(p + o + Vector3(0, 0.08, 0), rng.randf() * TAU), cols[i], 0.0, 1.0)


func _bush(a: Array, p: Vector3, s: float, c: Color, rng: RandomNumberGenerator) -> void:
	_box(a, Vector3(1.6, 1.1, 1.6) * s, _xf(p + Vector3(0, 0.55 * s, 0), rng.randf() * TAU), c, 0.0, 0.6)
	_box(a, Vector3(1.0, 0.8, 1.0) * s, _xf(p + Vector3(0.9 * s, 0.4 * s, 0.5 * s)), c * 1.2, 0.0, 0.6)


func _rock(a: Array, p: Vector3, s: float, ri: int, rng: RandomNumberGenerator) -> void:
	var st: Color = (_pal[ri][3] as Color) * 1.25
	var w := rng.randf_range(1.2, 2.6) * s
	_box(a, Vector3(w, w * 0.6, w * 0.8), _xf(p + Vector3(0, w * 0.26, 0), rng.randf() * TAU), st)
	_box(a, Vector3(w * 0.55, w * 0.45, w * 0.55), _xf(p + Vector3(w * 0.5, w * 0.2, w * 0.2), rng.randf() * TAU), st * 1.25)
	if rng.randf() < 0.5:
		_box(a, Vector3(w * 0.7, 0.2, w * 0.6), _xf(p + Vector3(0, w * 0.6, 0), rng.randf() * TAU), (_pal[ri][0] as Color) * 1.1)


## 残柱 / 断碑：上古遗迹
func _pillar(a: Array, p: Vector3, s: float, ri: int, rng: RandomNumberGenerator) -> void:
	var st: Color = (_pal[ri][3] as Color) * 1.5
	var hgt := rng.randf_range(3.0, 8.0) * s
	_box(a, Vector3(2.4, 0.7, 2.4), _xf(p + Vector3(0, 0.35, 0)), st * 0.85)
	_box(a, Vector3(1.6, hgt, 1.6), _xf(p + Vector3(0, hgt * 0.5 + 0.5, 0)), st)
	if rng.randf() < 0.45:
		_box(a, Vector3(2.2, 0.6, 2.2), _xf(p + Vector3(0, hgt + 0.7, 0), 0.0, Vector3(0.0, 0.0, 0.08)), st * 1.1)
	else:
		_box(a, Vector3(1.5, 1.4, 1.5), _xf(p + Vector3(2.2, 0.5, 0.8), rng.randf() * TAU, Vector3(1.3, 0.0, 0.2)), st * 0.9)


func _dead_tree(a: Array, p: Vector3, s: float, yaw: float, c: Color) -> void:
	_box(a, Vector3(0.8, 6.0, 0.8) * s, _xf(p + Vector3(0, 3.0 * s, 0), yaw, Vector3(0.0, 0.0, 0.06)), c)
	_box(a, Vector3(0.4, 3.0, 0.4) * s, _xf(p + Vector3(1.1, 4.6, 0) * s, yaw, Vector3(0.0, 0.0, -0.95)), c * 1.2)
	_box(a, Vector3(0.4, 2.4, 0.4) * s, _xf(p + Vector3(-0.9, 3.6, 0.3) * s, yaw, Vector3(0.3, 0.0, 0.9)), c * 1.2)
	_box(a, Vector3(0.3, 1.8, 0.3) * s, _xf(p + Vector3(0.2, 6.2, -0.6) * s, yaw, Vector3(-0.7, 0.0, 0.2)), c * 1.2)


## 血色禁地的巨兽肋骨：两排往中间弯的白骨
func _bones(a: Array, p: Vector3, s: float, yaw: float) -> void:
	var c := _lin(Color(0.82, 0.76, 0.66))
	for i in 3:
		for side: float in [-1.0, 1.0]:
			var z := (float(i) - 1.0) * 2.4 * s
			_box(a, Vector3(0.5, 3.2, 0.5) * s, _xf(p + Basis(Vector3.UP, yaw) * Vector3(side * 2.2, 1.5, z) * s, yaw, Vector3(0, 0, side * 0.25)), c)
			_box(a, Vector3(0.45, 2.2, 0.45) * s, _xf(p + Basis(Vector3.UP, yaw) * Vector3(side * 1.4, 3.6, z) * s, yaw, Vector3(0, 0, side * 0.95)), c * 0.9)


func _spike(a: Array, p: Vector3, s: float, rng: RandomNumberGenerator, c: Color) -> void:
	var w := 2.6 * s
	var y := 0.0
	for i in 4:
		var hh := rng.randf_range(2.0, 3.6) * s
		_box(a, Vector3(w, hh, w), _xf(p + Vector3(rng.randf_range(-0.3, 0.3), y + hh * 0.5, rng.randf_range(-0.3, 0.3)), rng.randf() * 0.6), c * (1.0 + 0.25 * float(i)))
		y += hh
		w *= 0.62


func _tomb(a: Array, p: Vector3, s: float, yaw: float) -> void:
	var c := _lin(Color(0.3, 0.36, 0.42))
	_box(a, Vector3(1.8, 0.35, 0.9) * s, _xf(p + Vector3(0, 0.17 * s, 0), yaw), c * 0.8)
	_box(a, Vector3(1.3, 2.2, 0.45) * s, _xf(p + Vector3(0, 1.3 * s, 0), yaw, Vector3(0.07, 0.0, 0.04)), c)
	_box(a, Vector3(0.9, 0.4, 0.5) * s, _xf(p + Vector3(0, 2.55 * s, 0), yaw, Vector3(0.07, 0.0, 0.04)), c * 1.15)


## 坠魔谷的浮岛：悬在半空的碎地，顶上长着紫晶
func _island(a: Array, p: Vector3, s: float, ri: int, rng: RandomNumberGenerator) -> void:
	var top: Color = (_pal[ri][0] as Color) * 1.3
	var st: Color = _pal[ri][3]
	var lc: Color = _pal[ri][5]
	var c := p + Vector3(0, rng.randf_range(16.0, 44.0), 0)
	var w := rng.randf_range(7.0, 13.0) * s
	_box(a, Vector3(w, 2.0, w), _xf(c), top, 0.0, 0.8)
	_box(a, Vector3(w * 0.72, 2.6, w * 0.72), _xf(c + Vector3(0.4, -2.2, -0.3)), st * 1.2, 0.0, 0.6)
	_box(a, Vector3(w * 0.42, 3.0, w * 0.42), _xf(c + Vector3(-0.3, -4.8, 0.4)), st, 0.0, 0.5)
	_box(a, Vector3(w * 0.18, 2.4, w * 0.18), _xf(c + Vector3(0.2, -7.2, 0.0)), st * 0.8, 0.0, 0.5)
	_box(a, Vector3(0.8, 3.4, 0.8), _xf(c + Vector3(w * 0.2, 2.4, w * 0.1), 0.5, Vector3(0.2, 0, 0.15)), lc * 0.85, 0.75)
	_box(a, Vector3(0.6, 2.0, 0.6), _xf(c + Vector3(w * 0.2 + 0.8, 1.8, w * 0.1 - 0.5), 0.9, Vector3(-0.3, 0, -0.3)), lc * 0.85, 0.75)
