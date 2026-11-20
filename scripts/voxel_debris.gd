extends MultiMeshInstance3D
## 受击碎块 / 方块尘土：一把小方块从命中点迸出，受重力落地、轻弹一下、在地上滑停后缩小消失。
## 颜色取自被打中的体素角色；尘土同样是小方块（不用白色粒子团）。
## CPU 逐块模拟（每次十几块），用真实时间推进——顿刀那一下碎块照样飞出去，不会被冻住。
## 故意不写 class_name：用 preload 引用。

const Sfx := preload("res://scripts/sfx.gd")
const GRAV := 22.0
const MAX_DT := 1.0 / 30.0

static var _mesh: BoxMesh

var floor_y := 0.0
var _p := PackedVector3Array()
var _v := PackedVector3Array()
var _w := PackedVector3Array()   # 角速度：轴 * 弧度/秒
var _q: Array[Basis] = []
var _s := PackedFloat32Array()
var _life := PackedFloat32Array()
var _bounce := PackedInt32Array()
var _t := 0.0
var _sound := true


static func cube_mesh() -> BoxMesh:
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3.ONE
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.85
		_mesh.material = m
	return _mesh


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-2000.0, -50.0, -2000.0), Vector3(4000.0, 200.0, 4000.0))
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = cube_mesh()


func _alloc(n: int) -> void:
	multimesh.instance_count = n
	_p.resize(n)
	_v.resize(n)
	_w.resize(n)
	_s.resize(n)
	_life.resize(n)
	_bounce.resize(n)
	_q.resize(n)
	for i in n:
		_bounce[i] = 0
		_q[i] = Basis(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(), randf() * TAU)


## 命中碎块：沿 dir 向外喷，带一点向上的初速度
func burst(pos: Vector3, dir: Vector3, colors: Array, n: int, speed: float, size := 1.0) -> void:
	_alloc(n)
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.UP
	for i in n:
		var r := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		_p[i] = pos + r * 0.07
		_v[i] = (d * 0.8 + r * 0.6 + Vector3.UP * 0.55).normalized() * speed * randf_range(0.45, 1.0)
		_w[i] = r.normalized() * randf_range(8.0, 22.0)
		_s[i] = randf_range(0.04, 0.075) * size
		_life[i] = randf_range(0.75, 1.1)
		multimesh.set_instance_color(i, MeshLib.vcol(colors[randi() % colors.size()] as Color))
	_place_all()


## 方块尘土：贴地向四周滚开，弹得低、消失得快
func dust(pos: Vector3, n: int, speed: float, size := 1.0) -> void:
	_alloc(n)
	_sound = false
	var cols := [Color(0.66, 0.64, 0.6), Color(0.52, 0.5, 0.47), Color(0.76, 0.74, 0.7), Color(0.6, 0.55, 0.48)]
	for i in n:
		var a := TAU * float(i) / float(n) + randf_range(-0.25, 0.25)
		var h := Vector3(cos(a), 0.0, sin(a))
		_p[i] = Vector3(pos.x, floor_y, pos.z) + h * randf_range(0.15, 0.45) + Vector3(0.0, 0.05, 0.0)
		_v[i] = h * speed * randf_range(0.5, 1.0) + Vector3.UP * randf_range(1.5, 4.5)
		_w[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(5.0, 14.0)
		_s[i] = randf_range(0.05, 0.09) * size
		_life[i] = randf_range(0.45, 0.75)
		multimesh.set_instance_color(i, MeshLib.vcol(cols[randi() % cols.size()] as Color))
	_place_all()


func _place_all() -> void:
	for i in _p.size():
		multimesh.set_instance_transform(i, Transform3D(_q[i].scaled(Vector3.ONE * _s[i]), _p[i]))


func _process(dt: float) -> void:
	dt = minf(dt, MAX_DT)
	_t += dt
	var alive := false
	for i in _p.size():
		var life := _life[i]
		if _t >= life:
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), _p[i]))
			continue
		alive = true
		var v := _v[i]
		v.y -= GRAV * dt
		var p := _p[i] + v * dt
		var half := _s[i] * 0.5
		var w := _w[i]
		if p.y < floor_y + half:
			p.y = floor_y + half
			if v.y < -1.2 and _bounce[i] < 1:
				# 触地轻跳一下
				v = Vector3(v.x * 0.6, -v.y * 0.36, v.z * 0.6)
				w *= 0.5
				_bounce[i] += 1
				if _sound:
					_sound = false
					Sfx.play("chip", -13.0, randf_range(0.9, 1.2))
			else:
				var f := exp(-9.0 * dt)
				v = Vector3(v.x * f, 0.0, v.z * f)
				w *= exp(-10.0 * dt)
		_p[i] = p
		_v[i] = v
		_w[i] = w
		var q := _q[i]
		var wl := w.length()
		if wl > 0.01:
			q = q.rotated(w / wl, wl * dt).orthonormalized()
			_q[i] = q
		var k := 1.0 - smoothstep(life - 0.22, life, _t)
		multimesh.set_instance_transform(i, Transform3D(q.scaled(Vector3.ONE * _s[i] * k), p))
	if not alive:
		queue_free()
