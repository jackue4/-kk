extends Control
## 一位英雄的 3D 小像（备战界面左边那个人）：自己的 World3D，石台上站着当前出战的英雄，手指左右拖能转着看，
## 点一下发 tapped（备战界面拿它开英雄选择）；flourish() 让他亮个相（换装备时用）。
## 模型 / 兵器 / 配色读 hero_defs.gd，搭法和 hero_select_ui.gd 的展台一样（那边是一排人 + 转盘，这里只有一位）。
## 故意不写 class_name：const HeroDoll := preload("res://scripts/ex/hero_doll.gd")。

signal tapped

const HeroDefs := preload("res://scripts/hero_defs.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const UiStyle := preload("res://scripts/ui_style.gd")

const CAM_FOV := 30.0
const VIEW_H := 3.05                         # 画面竖直方向装得下多少米（人大约占六成）
const LOOK_Y := 0.98
const BASE_YAW := 0.32
const LIFT := 0.3
const TAP_PX := 12.0

var hero_id := ""
var col := Color(0.6, 0.8, 1.0)
var yaw := 0.0                   # 手指转出来的角度（松手后慢慢回正）

var _vp: SubViewport
var _cam: Camera3D
var _rim: DirectionalLight3D
var _slot: Node3D
var _turn: Node3D
var _lift: Node3D
var _hero: VoxelHero
var _rig: Rig
var _blade := false
var _ring: StandardMaterial3D
var _rest_q := Quaternion.IDENTITY
var _queue: Array = []
var _demo := false
var _demo_t := 0.0
var _lift_k := 0.0
var _pulse := 0.0
var _t := 0.0
var _drag := false
var _drag_x := 0.0
var _drag_far := 0.0
var _idle := 0.0                 # 松手多久了


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rest_q = Poses.blade_quat(Vector3(0.3, -0.9, -0.32).normalized(), Vector3(0.1, -1.0, 0.0).normalized())
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED if Vfx.lite else Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(16, 16)
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.98, 0.96)
	env.ambient_light_energy = 0.62
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(0.5, -0.72, -1.0).normalized(), Vector3.UP)
	key.light_energy = 0.95
	_vp.add_child(key)
	_rim = DirectionalLight3D.new()
	_rim.basis = Basis.looking_at(Vector3(-0.7, -0.25, 1.0).normalized(), Vector3.UP)
	_rim.light_energy = 0.9
	_vp.add_child(_rim)
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.near = 0.2
	_cam.far = 40.0
	_vp.add_child(_cam)
	var dist := VIEW_H * 0.5 / tan(deg_to_rad(CAM_FOV) * 0.5)
	var eye := Vector3(0.0, LOOK_Y + 0.5, dist)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, LOOK_Y, 0.0) - eye, Vector3.UP), eye)
	_cam.current = true
	var view := TextureRect.new()
	view.texture = _vp.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	resized.connect(_fit)
	_fit()
	if hero_id != "":
		_build(hero_id)


func _fit() -> void:
	if _vp == null or size.x < 8.0 or size.y < 8.0:
		return
	var win := get_window()
	var vr := get_viewport_rect().size
	var k := clampf(float(win.size.y) / maxf(vr.y, 1.0) if win != null else 1.0, 0.5, 0.8 if Vfx.lite else 1.4)
	var want := Vector2i(maxi(int(roundf(size.x * k)), 16), maxi(int(roundf(size.y * k)), 16))
	if _vp.size != want:
		_vp.size = want


static func hero_color(def: Dictionary) -> Color:
	var rl: Variant = def.get("realm", {})
	if rl is Dictionary:
		var lines: Variant = (rl as Dictionary).get("lines", [])
		if lines is Array and not (lines as Array).is_empty() and (lines as Array)[0] is Color:
			return (lines as Array)[0]
	return Color(0.55, 0.8, 1.0)


## 换成哪位英雄（同一位不重建）
func set_hero(id: String) -> void:
	if id == hero_id and _slot != null:
		return
	hero_id = id
	if _vp != null:
		_build(id)


func _flat(c: Color, tex: Texture2D, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.albedo_texture = tex
	m.render_priority = prio
	return m


func _build(id: String) -> void:
	if _slot != null:
		_slot.queue_free()
		_slot = null
	var def := HeroDefs.def_of(id)
	if def.is_empty():
		def = HeroDefs.def_of(HeroDefs.DEFAULT)
	col = hero_color(def)
	_slot = Node3D.new()
	_vp.add_child(_slot)
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.12
	cm.height = 0.16
	cm.radial_segments = 40
	cm.rings = 1
	base.mesh = cm
	base.position.y = -0.08
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.17, 0.16, 0.17)
	bm.roughness = 0.9
	base.material_override = bm
	_slot.add_child(base)
	var ring := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(2.24, 2.24)
	ring.mesh = rp
	ring.position.y = 0.006
	_ring = _flat(Color(col, 0.8), UiStyle.tex("enso"), 0)
	ring.material_override = _ring
	_slot.add_child(ring)
	var blob := MeshInstance3D.new()
	var bp := PlaneMesh.new()
	bp.size = Vector2(1.5, 1.5)
	blob.mesh = bp
	blob.position.y = 0.012
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.22), Color(0, 0, 0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	blob.material_override = _flat(Color.WHITE, gt, 1)
	_slot.add_child(blob)
	_turn = Node3D.new()
	_slot.add_child(_turn)
	_lift = Node3D.new()
	_turn.add_child(_lift)
	_hero = VoxelHero.new({}, true, false, HeroDefs.TIER, HeroSkin.hero_key(str(def.get("skin", ""))))
	_lift.add_child(_hero)
	_blade = bool(def.get("blade_always", false))
	var weapon: Node3D
	if _blade:
		weapon = MeshLib.make_sword(def.get("sword_glow", col) as Color)
		var bmat := weapon.get_meta("blade_mat") as StandardMaterial3D
		if bmat != null:
			bmat.albedo_color = def.get("sword_col", Color(0.86, 0.9, 0.95)) as Color
			bmat.emission_energy_multiplier = 0.9
	else:
		weapon = Node3D.new()
	_rig = Rig.new(_hero, weapon, 1.0, -0.375, 0.72)
	var pm: Variant = def.get("pose_map", {})
	if pm is Dictionary:
		_rig.remap = pm
	var idle := str(_rig.remap.get("f_idle", "f_idle"))
	if Poses.has_def(idle):
		_rig.snap(Poses.get_pose(idle))
	_queue.clear()
	_demo = false
	_pulse = 1.0
	_tick(0.0)


## 亮个相：names = combat_poses.gd 的 SEQ 名（没有的跳过）；不给就石台亮一下
func flourish(names: Array = []) -> void:
	_pulse = 1.0
	if _rig == null:
		return
	var q: Array = []
	for n: Variant in names:
		if Poses.has_seq(str(n)):
			q.append(str(n))
	if q.is_empty():
		return
	_queue = q
	_demo = true
	_next()


func _next() -> void:
	var n := str(_queue.pop_front())
	_rig.play(n)
	var keys: Array = Poses.raw_seq(n)
	var last := float((keys[keys.size() - 1] as Array)[0])
	_demo_t = maxf(last + 0.14, 0.3) + (0.5 if _queue.is_empty() else 0.0)


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	dt = minf(dt, 0.05)
	_t += dt
	if not _drag:
		_idle += dt
		if _idle > 1.6:
			yaw = lerpf(yaw, 0.0, 1.0 - exp(-2.2 * dt))       # 放着不动一会儿就慢慢转回正面
	_tick(dt)


func _tick(dt: float) -> void:
	if _hero == null:
		return
	_turn.rotation.y = PI + BASE_YAW + yaw + sin(_t * 0.7) * 0.05
	if _demo:
		_demo_t -= dt
		if _demo_t <= 0.0:
			if _queue.is_empty():
				_demo = false
			else:
				_next()
	_hero.animate(dt, 0.0, 0.0, false, _demo)
	_rig.w_up_target = 1.0 if _demo else 0.0
	_rig.w_leg_target = 1.0 if _demo else 0.0
	_rig.update(dt)
	_rig.apply(dt)
	_lift_k = lerpf(_lift_k, 1.0 if _demo else 0.0, 1.0 - exp(-7.0 * dt))
	_lift.position.y = LIFT * _lift_k + sin(_t * 2.1) * 0.03 * _lift_k
	if _blade:
		var want := (_hero.global_basis.orthonormalized() * Basis(_rest_q)).get_rotation_quaternion()
		var now := _rig.holder.global_basis.orthonormalized().get_rotation_quaternion()
		_rig.holder.global_basis = Basis(now.slerp(want, clampf(1.0 - _rig.w_up * 1.5, 0.0, 1.0)))
	_pulse = maxf(_pulse - dt * 1.6, 0.0)
	_ring.albedo_color = Color(col.lerp(Color.WHITE, _pulse * 0.6), (0.72 + 0.08 * sin(_t * 2.4)) * (1.0 + _pulse * 0.35))
	_rim.light_color = col.lerp(Color.WHITE, 0.25)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_drag = true
			_drag_x = mb.position.x
			_drag_far = 0.0
		elif _drag:
			_drag = false
			_idle = 0.0
			if _drag_far < TAP_PX:
				tapped.emit()
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		var dx := mm.position.x - _drag_x
		_drag_x = mm.position.x
		_drag_far += absf(dx)
		yaw = wrapf(yaw + dx / maxf(size.x, 1.0) * 5.0, -PI, PI)
		accept_event()
