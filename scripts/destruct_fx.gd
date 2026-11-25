extends MultiMeshInstance3D
## 场景破坏的表现（2026-11-25，scripts/destruct.gd 建一个、全程复用）：打飞的方块碎块 + 留在地上的残骸。
## · 一张 MultiMesh、一次绘制调用，池子大小固定（桌面 CAP 块，手机 CAP_LITE 块）；满了先顶掉最早落定的
## · 不用物理刚体：自己算抛物线，落地弹一下、滑停，停住后留 REST 秒再缩没
## · 落地问的是关卡的地面（floor_fn：func(x, z, y) -> 这一点脚下多高），坑炸出来以后碎块会掉进坑里；每块三帧问一次，错开
## · 材质：新图 / 老大世界用地形那张（顶点色 = sRGB 底色、alpha = 自发光，两种渲染器的颜色它自己管）；
##   没有地形材质的地方（主城 / 擂台 / 试剑台）用普通材质，颜色过 MeshLib.vcol
## 另外管「分帧的活」：犁沟（destruct.gd 的 trench）一帧只挖几段，沟是顺着拳劲一路犁过去的，不卡那一帧。
## 故意不写 class_name：用 preload 引用。

const CAP := 240
const CAP_LITE := 96
const GRAV := 26.0
const MAX_DT := 1.0 / 30.0
const REST := 12.0
const REST_LITE := 6.0
const FADE := 0.5
const JOB_US := 2500           # 分帧的活一帧最多干这么久（微秒）
const FAR := 140.0             # 离镜头这么远以外的不撒碎块

static var _cube: BoxMesh
static var _plain: StandardMaterial3D

var floor_fn := Callable()
var world_mat: Material = null
var jobs: Array = []           # [Callable(第几步) -> 还有没有下一步, 步数]
var live := 0                  # 现在池子里有几块（自检看）
var peak := 0
var spawned := 0
var sim_ms := 0.0              # 逐块模拟最慢的一帧（毫秒，自检看）

var _cap := CAP
var _st := PackedByteArray()   # 0 空 1 在飞 2 落定 3 缩没
var _p := PackedVector3Array()
var _v := PackedVector3Array()
var _w := PackedVector3Array()
var _sz := PackedVector3Array()
var _q: Array[Basis] = []
var _t := PackedFloat32Array()     # 落定后还留多久 / 缩没还剩多久
var _fy := PackedFloat32Array()    # 上次问到的地面
var _bn := PackedByteArray()
var _next := 0
var _frame := 0
var _use_world := false


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-4000.0, -200.0, -4000.0), Vector3(8000.0, 600.0, 8000.0))
	if _cube == null:
		_cube = BoxMesh.new()
		_cube.size = Vector3.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _cube


func _ready() -> void:
	name = "DestructFx"
	_cap = CAP_LITE if Vfx.lite else CAP
	multimesh.instance_count = _cap
	_st.resize(_cap)
	_p.resize(_cap)
	_v.resize(_cap)
	_w.resize(_cap)
	_sz.resize(_cap)
	_t.resize(_cap)
	_fy.resize(_cap)
	_bn.resize(_cap)
	_q.resize(_cap)
	for i in _cap:
		_st[i] = 0
		_q[i] = Basis.IDENTITY
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0.0, -500.0, 0.0)))
		multimesh.set_instance_color(i, Color(1, 1, 1, 0))
	set_material(world_mat)


## 换材质（进了新图 / 回了主城）
func set_material(m: Material) -> void:
	world_mat = m
	_use_world = m != null
	if _use_world:
		material_override = m
	else:
		if _plain == null:
			_plain = StandardMaterial3D.new()
			_plain.vertex_color_use_as_albedo = true
			_plain.roughness = 0.9
		material_override = _plain


## 全收掉（换关卡时）
func clear() -> void:
	jobs.clear()
	for i in _st.size():
		if _st[i] != 0:
			_st[i] = 0
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0.0, -500.0, 0.0)))
	live = 0


func cap() -> int:
	return _cap


func _col(c: Color) -> Color:
	# 地形材质：顶点色原样（sRGB），alpha = 自发光强度（碎块不发光）；普通材质：按渲染器转
	if _use_world:
		return Color(c.r, c.g, c.b, 0.0)
	var o := MeshLib.vcol(c)
	return Color(o.r, o.g, o.b, 1.0)


func _floor(x: float, z: float, y: float, fallback: float) -> float:
	if floor_fn.is_valid():
		return float(floor_fn.call(x, z, y))
	return fallback


func _slot() -> int:
	# 先找空的；没有就顶掉最早落定的；全在飞就顶掉轮到的那个
	for k in _cap:
		var i := (_next + k) % _cap
		if _st[i] == 0:
			_next = (i + 1) % _cap
			return i
	for k in _cap:
		var i2 := (_next + k) % _cap
		if _st[i2] >= 2:
			_next = (i2 + 1) % _cap
			return i2
	var i3 := _next
	_next = (_next + 1) % _cap
	return i3


func _near(pos: Vector3) -> bool:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	return cam == null or cam.global_position.distance_squared_to(pos) < FAR * FAR


## 放一块：pos 起点、vel 初速、size 三边长、col 颜色（sRGB）、floor_y 这一带的地面（floor_fn 问不到时用）
func chunk(pos: Vector3, vel: Vector3, size: Vector3, col: Color, floor_y: float) -> void:
	var i := _slot()
	if _st[i] == 0:
		live += 1
	_st[i] = 1
	_p[i] = pos
	_v[i] = vel
	_w[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(3.0, 11.0)
	_sz[i] = size
	_q[i] = Basis(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(), randf() * TAU)
	_t[i] = 0.0
	_fy[i] = floor_y
	_bn[i] = 0
	multimesh.set_instance_color(i, _col(col))
	multimesh.set_instance_transform(i, Transform3D(_q[i] * Basis.from_scale(size), pos))
	spawned += 1
	peak = maxi(peak, live)


## 地面炸开：从 pos（贴地）往上往外掀起 n 块（dir = 冲击的去向，ZERO = 正上方），颜色从 cols 里挑
func burst(pos: Vector3, dir: Vector3, cols: Array, n: int, speed: float, size: float, spread := 1.0) -> void:
	if n <= 0 or cols.is_empty() or not _near(pos):
		return
	var d := dir.normalized() if dir.length_squared() > 1.0e-6 else Vector3.ZERO
	for i in n:
		var a := randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		var k := randf_range(0.35, 1.0)
		var v := (out * randf_range(0.25, 0.9) + Vector3.UP * randf_range(0.7, 1.35) + d * 0.9).normalized() * speed * k
		var s := size * randf_range(0.45, 1.0)
		chunk(pos + out * randf_range(0.1, 0.9) * spread + Vector3(0.0, 0.15 + s * 0.5, 0.0), v,
				Vector3(s * randf_range(0.8, 1.3), s * randf_range(0.5, 0.95), s * randf_range(0.8, 1.3)), cols[randi() % cols.size()] as Color, pos.y)


## 打掉的方块碎成块：list = [[中心, 尺寸, 颜色], ...]（世界系的大致体块），顺着 dir 飞（ZERO = 往外散），budget = 这一次最多几块
func pieces(list: Array, from: Vector3, dir: Vector3, power: float, budget: int, floor_y: float) -> void:
	if list.is_empty() or budget <= 0:
		return
	var d := dir.normalized() if dir.length_squared() > 1.0e-6 else Vector3.ZERO
	var per := maxi(budget / list.size(), 1)
	var left := budget
	for e: Array in list:
		if left <= 0:
			break
		var c: Vector3 = e[0]
		if not _near(c):
			continue
		var sz: Vector3 = e[1]
		var col: Color = e[2]
		var vol := sz.x * sz.y * sz.z
		var n := clampi(int(vol * 0.9) + 1, 1, mini(per + 2, 9))
		n = mini(n, left)
		left -= n
		var cs := clampf(pow(vol / float(n), 1.0 / 3.0), 0.28, 1.25)
		for i in n:
			var off := Vector3(randf_range(-0.5, 0.5) * sz.x, randf_range(-0.5, 0.5) * sz.y, randf_range(-0.5, 0.5) * sz.z)
			var p := c + off * 0.8
			var away := p - from
			away = away.normalized() if away.length_squared() > 1.0e-4 else Vector3.UP
			var v := (d * 1.3 + away * 0.8 + Vector3.UP * randf_range(0.25, 0.8)).normalized() * randf_range(5.0, 12.0) * clampf(power, 0.6, 1.6)
			var s := cs * randf_range(0.6, 1.1)
			chunk(p, v, Vector3(s * randf_range(0.75, 1.25), s * randf_range(0.6, 1.1), s * randf_range(0.75, 1.25)), col.darkened(randf_range(0.0, 0.18)), floor_y)


## 没法真挖的地面（主城 / 擂台 / 试剑台）：冲击点周围翻起一圈石板（歪着插在地上，留一会儿），中间再崩起几块
func rim(pos: Vector3, radius: float, cols: Array, power: float) -> void:
	if cols.is_empty() or not _near(pos):
		return
	var n := int(clampf(radius * 2.4, 5.0, 14.0) * (0.6 if Vfx.lite else 1.0))
	var a0 := randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(n) + randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var rr := radius * randf_range(0.55, 1.0)
		var s := clampf(radius * randf_range(0.2, 0.36), 0.35, 1.3)
		var j := _slot()
		if _st[j] == 0:
			live += 1
		# 直接落定：往外歪着插在地上
		_st[j] = 2
		var fy := _floor(pos.x + out.x * rr, pos.z + out.z * rr, pos.y + 1.0, pos.y)
		_p[j] = Vector3(pos.x + out.x * rr, fy + s * 0.18, pos.z + out.z * rr)
		_v[j] = Vector3.ZERO
		_w[j] = Vector3.ZERO
		_sz[j] = Vector3(s * randf_range(0.9, 1.5), s * randf_range(0.35, 0.6), s * randf_range(0.8, 1.2))
		_q[j] = Basis(Vector3.UP, -a) * Basis(Vector3(0, 0, 1), randf_range(0.35, 0.8)) * Basis(Vector3.UP, randf_range(-0.4, 0.4))
		_t[j] = (REST_LITE if Vfx.lite else REST) * randf_range(0.8, 1.0)
		_fy[j] = fy
		_bn[j] = 9
		multimesh.set_instance_color(j, _col((cols[randi() % cols.size()] as Color).darkened(randf_range(0.0, 0.2))))
		multimesh.set_instance_transform(j, Transform3D(_q[j] * Basis.from_scale(_sz[j]), _p[j]))
		spawned += 1
	peak = maxi(peak, live)
	burst(pos, Vector3.ZERO, cols, int((5.0 if Vfx.lite else 9.0) * clampf(power, 0.6, 1.5)), 5.0 + radius, clampf(radius * 0.22, 0.3, 0.8), radius * 0.4)


## 加一件分帧的活：f(i) 做第 i 步，一共 n 步；end 做完后调一次
func add_job(f: Callable, n: int, end := Callable()) -> void:
	jobs.append([f, n, 0, end])


## 把排着的活一口气干完（联机补进度 / 自检）
func flush_jobs() -> void:
	while not jobs.is_empty():
		var j: Array = jobs.pop_front()
		for i in range(int(j[2]), int(j[1])):
			(j[0] as Callable).call(i)
		if (j[3] as Callable).is_valid():
			(j[3] as Callable).call()


func _process(dt: float) -> void:
	if not jobs.is_empty():
		var t0 := Time.get_ticks_usec()
		while not jobs.is_empty():
			var j: Array = jobs[0]
			var i := int(j[2])
			if i >= int(j[1]):
				jobs.pop_front()
				if (j[3] as Callable).is_valid():
					(j[3] as Callable).call()
				continue
			(j[0] as Callable).call(i)
			j[2] = i + 1
			if Time.get_ticks_usec() - t0 > JOB_US:
				break
	if live <= 0:
		return
	dt = minf(dt, MAX_DT)
	_frame += 1
	var sim0 := Time.get_ticks_usec()
	var rest := REST_LITE if Vfx.lite else REST
	for i in _cap:
		var st := _st[i]
		if st == 0:
			continue
		if st == 2:
			_t[i] -= dt
			if _t[i] <= 0.0:
				_st[i] = 3
				_t[i] = FADE
			continue
		if st == 3:
			_t[i] -= dt
			if _t[i] <= 0.0:
				_st[i] = 0
				live -= 1
				multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0.0, -500.0, 0.0)))
			else:
				var k := _t[i] / FADE
				multimesh.set_instance_transform(i, Transform3D(_q[i] * Basis.from_scale(_sz[i] * k), _p[i] - Vector3(0.0, (1.0 - k) * _sz[i].y * 0.5, 0.0)))
			continue
		var v := _v[i]
		v.y -= GRAV * dt
		var p := _p[i] + v * dt
		var w := _w[i]
		var half := _sz[i].y * 0.5
		if v.y < 0.0 and (i + _frame) % 3 == 0:
			_fy[i] = _floor(p.x, p.z, p.y + 0.5, _fy[i])
		var fy := _fy[i]
		if p.y < fy + half:
			p.y = fy + half
			if v.y < -4.0 and _bn[i] < 1:
				v = Vector3(v.x * 0.55, -v.y * 0.3, v.z * 0.55)
				w *= 0.45
				_bn[i] = _bn[i] + 1
			else:
				var f := exp(-8.0 * dt)
				v = Vector3(v.x * f, 0.0, v.z * f)
				w *= exp(-12.0 * dt)
				if v.length_squared() < 0.16:
					_st[i] = 2
					_t[i] = rest * randf_range(0.7, 1.0)
		elif p.y < fy - 60.0:
			_st[i] = 0
			live -= 1
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0.0, -500.0, 0.0)))
			continue
		_p[i] = p
		_v[i] = v
		_w[i] = w
		var q := _q[i]
		var wl := w.length()
		if wl > 0.01:
			q = q.rotated(w / wl, wl * dt).orthonormalized()
			_q[i] = q
		multimesh.set_instance_transform(i, Transform3D(q * Basis.from_scale(_sz[i]), p))
	sim_ms = maxf(sim_ms, float(Time.get_ticks_usec() - sim0) / 1000.0)
