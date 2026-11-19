extends Node3D
## 关卡传送门（大厅 → 择境、木兰草原 → 回大厅）。
## 原样实例化 vfx-sketchbook-3d 的 portal（res://fx/portal/portal.tscn：屏幕扭曲 Deform、外 / 内两圈旋涡边、
## 丝带粒子、补光、门心 SubViewport + portal 着色器），整体放大 SIZE 倍竖在一座石台上。
## 门心照原版 portal.gd 的做法画"门那一头"：本门变换的逆 × 那一头的门（绕 Y 翻 180°）× 主相机——
## 这里那一头是 SubViewport 里的一个独立小世界（preview_builder 往里搭：草原的地形 / 草 / 天空，或大厅的灰网格），
## 主相机离门 PREVIEW_RANGE 米内才渲染，平时零开销。
## 走进门（原版 Area3D 的盒子，只认主角所在的第 2 层）发 entered；发过一次后，主角离门 REARM 米以外才会再发。
## 故意不复用 space_gate / tornado_portal：那套旋涡门只给 R 大罡剑阵用。
## 故意不写 class_name：用 preload 引用。

signal entered

const PORTAL := preload("res://fx/portal/portal.tscn")
const SIZE := 1.6                      # 原版门心半径 1.2 米 → 约 1.9 米
const LIFT := 2.9                      # 门心离地高度：门洞下沿约 1 米，外圈旋涡边略没入石台
const PREVIEW_RANGE := 110.0
const REARM := 7.0

var preview_builder: Callable          # func(vp: SubViewport) -> void
var preview_eye := Transform3D.IDENTITY # 预览世界里"那一头的门"（+Z 是出门方向）
var preview_floor: Callable            # func(x: float, z: float) -> float：预览机位不钻地（可不给）
var preview_on := true
var title := ""
var subtitle := ""
var font: Font
var stone := Color(0.42, 0.42, 0.45)

var _fx: Area3D
var _vp: SubViewport
var _cam: Camera3D
var _armed := true
var _who: Node3D


func _ready() -> void:
	_fx = PORTAL.instantiate() as Area3D
	_fx.scale = Vector3.ONE * SIZE
	_fx.position.y = LIFT
	_fx.collision_layer = 0
	_fx.collision_mask = 2
	_vp = _fx.get_node("SubViewport") as SubViewport
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_cam = _fx.get_node("SubViewport/Camera3D") as Camera3D
	add_child(_fx)
	_fx.body_entered.connect(_on_body)
	if preview_builder.is_valid():
		preview_builder.call(_vp)
	_build_dais()


func center() -> Vector3:
	return _fx.global_position


## 门前 d 米（站位 / 出门落点）
func front(d: float) -> Vector3:
	var f := global_basis.z
	f.y = 0.0
	return global_position + f.normalized() * d


func _build_dais() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = stone
	m.roughness = 0.9
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.4 * SIZE * 0.5 + 0.6
	cm.bottom_radius = cm.top_radius + 0.5
	cm.height = 0.5
	cm.radial_segments = 40
	base.mesh = cm
	base.material_override = m
	base.position.y = 0.0
	add_child(base)
	if title != "" and font != null:
		var l := Label3D.new()
		l.text = title if subtitle == "" else title + "\n" + subtitle
		l.font = font
		l.font_size = 96
		l.pixel_size = 0.009
		l.modulate = Color(0.95, 0.93, 0.86)
		l.outline_size = 14
		l.outline_modulate = Color(0.08, 0.08, 0.12)
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.position = Vector3(0.0, LIFT + 2.25 * SIZE + 1.2, 0.0)
		add_child(l)


func _on_body(b: Node3D) -> void:
	if b is Player and _armed and is_visible_in_tree():
		_armed = false
		_who = b
		entered.emit()


## 换场景回来时重新上膛（主角已被放到门外）
func rearm() -> void:
	_armed = true


func _process(_dt: float) -> void:
	if not _armed and (_who == null or _who.global_position.distance_to(_fx.global_position) > REARM + 3.0):
		_armed = true
	var wc := get_viewport().get_camera_3d()
	var on := preview_on and is_visible_in_tree() and wc != null \
			and wc.global_position.distance_to(_fx.global_position) < PREVIEW_RANGE
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var sz := Vector2i((get_viewport().get_visible_rect().size * 0.5).round())
	if _vp.size != sz:
		_vp.size = sz
	var here := Transform3D(_fx.global_basis.orthonormalized(), _fx.global_position)
	var xf := preview_eye.scaled_local(Vector3(-1.0, 1.0, -1.0)) * here.affine_inverse() * wc.global_transform
	if preview_floor.is_valid():
		xf.origin.y = maxf(xf.origin.y, float(preview_floor.call(xf.origin.x, xf.origin.z)) + 1.0)
	_cam.global_transform = xf
	_cam.fov = wc.fov
	_cam.near = 0.1
	_cam.far = 9000.0
