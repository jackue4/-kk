extends Node3D
## 别人名下的 AI 道友在我这边的木偶（2026-11-20）。
## AI 道友只在本队编号最小的那位真人机器上算（ally_team.gd），他每秒十次把每个道友的
## [第几个, 名字, 装束, 等级, 气劲色, 位置, 朝向, 速度, 血量比例, 招式名, 招式序号, 状态位, 说的话, 说了几句] 发给房间里所有人（net.gd 的 _allies），
## 这边照着摆：朝同步来的位置追（带一点速度外推）、招式序号变了就播那一招、说的话变了就在头顶冒泡、重伤离场时藏起来。
## 打不到它、锁不到它（不进索敌分组）；它打怪的伤害在主人那边算（打到我名下的怪时由主人发 send_mob_hit 过来）。
## 三秒没消息就自己消失（主人撤离 / 掉线 / 真人补位把它换下去了）。
## 故意不写 class_name：用 preload 引用。

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const Brain := preload("res://scripts/ally_brain.gd")

var owner_id := 0
var slot := 0
var display_name := "道友"
var mate := false
var lv := 1
var look_i := 0
var qi := Color(0.5, 0.95, 0.8)
var hp_r := 1.0
var mode := 0
var down := false
var pushes := 0               # 收到过几次状态（自检看）
var says := 0                 # 冒过几句话（自检看）

var visual: Node3D
var hero: VoxelHero
var rig: Rig
var _tag: Label3D
var _bar: MeshInstance3D
var _bubble: Label3D
var _bubble_t := 0.0
var _to := Vector3.ZERO
var _yaw := 0.0
var _vel := Vector3.ZERO
var _got := false
var _pose_n := -1
var _say_n := -1
var _stale := 0.0
var _phase := 0.0


func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	hero = VoxelHero.new({}, true, false, look_i)
	visual.add_child(hero)
	rig = Rig.new(hero, Node3D.new(), 1.0, 0.0, 0.5)
	rig.cur = Poses.get_pose("f_idle")
	rig.play("f_idle")
	rig.w_up = 1.0
	rig.w_leg = 1.0
	rig.w_up_target = 1.0
	rig.w_leg_target = 1.0
	_bar = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 0.08)
	_bar.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.3, 0.75, 0.6)
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.billboard_keep_scale = true
	bm.no_depth_test = true
	_bar.material_override = bm
	_bar.position.y = 2.3
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	_tag = Label3D.new()
	_tag.font = Vfx.font
	_tag.font_size = 40
	_tag.pixel_size = 0.006
	_tag.outline_size = 10
	_tag.outline_modulate = Color(0.08, 0.08, 0.1, 0.9)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.position.y = 2.6
	add_child(_tag)
	_bubble = Brain.make_bubble(self)
	visible = false
	_refresh()


func _refresh() -> void:
	if _tag == null:
		return
	_tag.text = "%s%s  Lv.%d" % ["【队友】" if mate else "【道友】", display_name, lv]
	_tag.modulate = UiStyle.JADE.lightened(0.2) if mate else Color(0.85, 1.0, 0.9)


## 主人发来的一条状态（ally_team.gd 的 apply 调；pos 已经换成离我最近的那个像）
func push(pos: Vector3, yaw: float, vel: Vector3, hp_ratio: float, pose: String, pose_n: int, flag_bits: int, say_i: int, say_n: int, level: int) -> void:
	pushes += 1
	_to = pos
	_yaw = yaw
	_vel = vel
	hp_r = hp_ratio
	down = (flag_bits & 1) != 0
	mode = flag_bits >> 1
	_stale = 0.0
	if level != lv:
		lv = level
		_refresh()
	if not _got:
		_got = true
		global_position = pos
		_say_n = say_n          # 进视野之前说过的话不补
		_pose_n = pose_n
	if pose_n != _pose_n:
		_pose_n = pose_n
		if pose != "" and Poses.SEQ.has(pose):
			rig.play(pose)
	if say_n != _say_n:
		_say_n = say_n
		if say_i >= 0 and say_i < Brain.SAY.size():
			says += 1
			_bubble.text = Brain.SAY[say_i]
			_bubble.visible = true
			_bubble_t = 2.6


func _process(dt: float) -> void:
	if not _got:
		return
	_stale += dt
	if _stale > 3.0:
		queue_free()
		return
	visible = not down
	if _bubble_t > 0.0:
		_bubble_t -= dt
		if _bubble_t <= 0.0:
			_bubble.visible = false
	var want := _to + _vel * minf(_stale, 0.15)
	global_position = global_position.lerp(want, 1.0 - exp(-14.0 * dt)) if global_position.distance_to(want) < 30.0 else want
	visual.rotation.y = lerp_angle(visual.rotation.y, _yaw, 1.0 - exp(-12.0 * dt))
	_phase += dt * Vector2(_vel.x, _vel.z).length() * 1.4
	hero.stream_add = clampf(_vel.length() / 20.0, 0.0, 1.0)
	hero.animate(dt, 0.0, 0.0, false, true)
	rig.update(dt)
	rig.apply(dt)
	_bar.scale.x = maxf(hp_r, 0.001)
	_bar.visible = hp_r < 0.999


func center() -> Vector3:
	return global_position + Vector3(0.0, 0.95, 0.0)
