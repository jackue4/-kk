extends Node3D
## 对波的光柱：外层染色的粗柱 + 白色细芯，都是加色发光的圆柱；起点一团掌前的光球，终点一团顶在前头的光球。
## 调用方每帧 place(from, to)；fade_out() 收束后自己释放。空战对波（air_melee.gd）和对手（air_foe.gd）共用。
## 故意不写 class_name：用 preload 引用。

var color := Color(1.0, 0.6, 0.2)
var radius := 0.6
var head_k := 1.0      # 终点光球的放大倍数（对波相持时调大）

var _outer: MeshInstance3D
var _core: MeshInstance3D
var _muzzle: MeshInstance3D
var _head: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0
var _k := 0.0
var _dying := false


static func _mat(c: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, alpha)
	return m


func _ready() -> void:
	top_level = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	_outer = _mk(cyl, _mat(color, 0.8, 0.4))
	_core = _mk(cyl, _mat(Color.WHITE.lerp(color, 0.3), 1.0, 0.75))
	_muzzle = _mk(sph, _mat(Color.WHITE.lerp(color, 0.5), 0.9, 0.6))
	_head = _mk(sph, _mat(Color.WHITE.lerp(color, 0.45), 0.9, 0.6))
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 12.0
	_light.light_energy = 2.0
	_light.shadow_enabled = false
	add_child(_light)


func _mk(mesh: Mesh, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _process(dt: float) -> void:
	_t += dt
	if _dying:
		_k = move_toward(_k, 0.0, dt * 6.0)
		if _k <= 0.0:
			queue_free()
	else:
		_k = move_toward(_k, 1.0, dt * 9.0)


## 光柱从 from 伸到 to
func place(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var l := maxf(d.length(), 0.05)
	var y := d / l
	var x := y.cross(Vector3.UP)
	x = x.normalized() if x.length_squared() > 1e-4 else Vector3.RIGHT
	var z := x.cross(y)
	var pulse := 1.0 + 0.12 * sin(_t * 46.0) + 0.06 * sin(_t * 71.0)
	var r := radius * _k * pulse
	var mid := from + d * 0.5
	_outer.global_transform = Transform3D(Basis(x * r, y * l, z * r), mid)
	_core.global_transform = Transform3D(Basis(x * r * 0.45, y * l, z * r * 0.45), mid)
	_muzzle.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * r * 1.15), from)
	_head.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * r * 1.4 * head_k), to)
	_light.global_position = to
	_light.light_energy = 1.2 * _k


func fade_out() -> void:
	_dying = true
