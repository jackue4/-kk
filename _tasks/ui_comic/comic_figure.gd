extends Control
## 漫画人：一位英雄的 3D 模型画在透明底的小视口里，再过一遍 comic_figure.gdshader（粗墨线 / 内线 / 暗部网点 / 硬投影）。
## 搭法照 scripts/ex/hero_doll.gd（模型 / 兵器 / 姿势都读 hero_defs.gd），区别：没有石台、低机位仰一点、光打得更硬。
## bust = true 是只取头肩的小头像（选人格子用），可以设 mono 画成两色墨稿、once 画完一张就停。
## 故意不写 class_name：const Figure := preload("res://_tasks/ui_comic/comic_figure.gd")。

const HeroDefs := preload("res://scripts/hero_defs.gd")
const HeroSkin := preload("res://scripts/hero_skin.gd")
const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const SHADER := preload("res://_tasks/ui_comic/comic_figure.gdshader")

const CAM_FOV := 26.0

var hero_id := ""
var bust := false
var view_h := 2.5                # 画面竖直方向装得下多少米
var look_y := 0.99                # 镜头看着多高
var eye_drop := 0.34             # 机位比看的点低多少（仰视）
var base_yaw := 0.42
var res_scale := 1.0             # 视口分辨率再乘多少
var mat: ShaderMaterial

var _vp: SubViewport
var _cam: Camera3D
var _slot: Node3D
var _turn: Node3D
var _lift: Node3D
var _hero: VoxelHero
var _rig: Rig
var _blade := false
var _rest_q := Quaternion.IDENTITY
var _queue: Array = []
var _demo := false
var _demo_t := 0.0
var _lift_k := 0.0
var _t := 0.0
var _view: TextureRect
var _frames := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER


func _ready() -> void:
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
	env.ambient_light_energy = 0.44
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.basis = Basis.looking_at(Vector3(0.62, -0.6, -0.75).normalized(), Vector3.UP)
	key.light_energy = 0.84
	_vp.add_child(key)
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.near = 0.2
	_cam.far = 60.0
	_vp.add_child(_cam)
	_aim()
	_cam.current = true
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.material = mat
	add_child(_view)
	resized.connect(_fit)
	_fit()
	if hero_id != "":
		_build(hero_id)


func _aim() -> void:
	if _cam == null:
		return
	var dist := view_h * 0.5 / tan(deg_to_rad(CAM_FOV) * 0.5)
	var eye := Vector3(0.0, look_y - eye_drop, dist)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, look_y, 0.0) - eye, Vector3.UP), eye)


func _fit() -> void:
	if _vp == null or size.x < 8.0 or size.y < 8.0:
		return
	var win := get_window()
	var vr := get_viewport_rect().size
	var k := clampf(float(win.size.y) / maxf(vr.y, 1.0) if win != null else 1.0, 0.5, 0.8 if Vfx.lite else 1.4) * res_scale
	var want := Vector2i(maxi(int(roundf(size.x * k)), 16), maxi(int(roundf(size.y * k)), 16))
	if _vp.size != want:
		_vp.size = want
		_frames = 0
	mat.set_shader_parameter("texel", Vector2(1.0 / float(want.x), 1.0 / float(want.y)))


## 换成哪位英雄（同一位不重建）
func set_hero(id: String) -> void:
	if id == hero_id and _slot != null:
		return
	hero_id = id
	if _vp != null:
		_build(id)


func _build(id: String) -> void:
	if _slot != null:
		_slot.queue_free()
		_slot = null
	var def := HeroDefs.def_of(id)
	if def.is_empty():
		def = HeroDefs.def_of(HeroDefs.DEFAULT)
	_slot = Node3D.new()
	_vp.add_child(_slot)
	_turn = Node3D.new()
	_slot.add_child(_turn)
	_lift = Node3D.new()
	_turn.add_child(_lift)
	_hero = VoxelHero.new({}, true, false, HeroDefs.TIER, HeroSkin.hero_key(str(def.get("skin", ""))))
	_lift.add_child(_hero)
	_blade = bool(def.get("blade_always", false))
	var weapon: Node3D
	if _blade:
		var glow: Color = def.get("sword_glow", Color(0.6, 0.8, 1.0))
		weapon = MeshLib.make_sword(glow)
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
	_frames = 0
	if _vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_tick(0.0)


## 比划一遍：names = combat_poses.gd 的 SEQ 名（没有的跳过）
func flourish(names: Array = []) -> void:
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
	_tick(dt)
	_frames += 1
	if bust and _frames == 12:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED      # 小头像画好一张就停


func _tick(dt: float) -> void:
	if _hero == null:
		return
	_turn.rotation.y = PI + base_yaw + (0.0 if bust else sin(_t * 0.7) * 0.05)
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
	_lift.position.y = 0.22 * _lift_k + sin(_t * 2.1) * 0.03 * _lift_k
	if _blade:
		var want := (_hero.global_basis.orthonormalized() * Basis(_rest_q)).get_rotation_quaternion()
		var now := _rig.holder.global_basis.orthonormalized().get_rotation_quaternion()
		_rig.holder.global_basis = Basis(now.slerp(want, clampf(1.0 - _rig.w_up * 1.5, 0.0, 1.0)))


## 把这一帧的小视口存成图（生 2D 立绘时拿它当参考）
func grab() -> Image:
	return _vp.get_texture().get_image() if _vp != null else null
