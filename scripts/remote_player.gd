extends Node3D
## 联机里别的玩家在自己这边的木偶（net.gd 创建）：方块小人 + 名牌 + 血条，按对方发来的状态插值移动、播同一套动作。
## 对各套战斗来说它就是一个普通的目标（和 air_foe.gd / raid_mob.gd 同一套接口），区别在于：
##   · 队友：不进索敌分组（锁不到），打在身上也不算（air_hit / receive_hit 返回 -1）；名牌是青色
##   · 别队的：进索敌分组，能打；打中后把这一下发给对方，由对方那边按正常受击结算，这里只管表现；名牌是红色
## 血量显示的是对方同步过来的值。
## 故意不写 class_name：用 preload 引用。

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const UiStyle := preload("res://scripts/ui_style.gd")
const AwakenFx := preload("res://scripts/awaken_fx.gd")

const BODY_Y := 0.95

var net: Node
var peer_id := 0
var player: Player            # 本机的主角
var display_name := "道友"
var mate := false
var hp := 100.0
var lv := 1
var realm_idx := 0
var st := 0
var flags := 0                # 位 0 正在连发飞剑 · 位 1 对波相持中 · 位 2 渡劫中
var qi := Color(0.9, 0.95, 1.0)   # 气劲颜色（= 他那个境界的丝线色），对波特效用
var clash_their := 0.0        # 对波：对方累计顶了多少（他那边发来的）
var _push_t := 0.0

var visual: Node3D
var hero: VoxelHero
var rig: Rig
var _tag: Label3D
var _bar: MeshInstance3D
var _to := Vector3.ZERO
var _yaw := 0.0
var _vel := Vector3.ZERO
var _got := false
var _pose_n := -1
var _flash := 0.0
var _phase := 0.0
var _stale := 0.0
var _awake_fx: AwakenFx


func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	hero = VoxelHero.new({}, true, false, realm_idx)
	visual.add_child(hero)
	rig = Rig.new(hero, Node3D.new(), 1.0, 0.0, 0.5)
	rig.cur = Poses.get_pose("f_idle")
	_bar = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 0.08)
	_bar.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	visible = false
	_refresh()


## 他那边暴气觉醒了（net.gd 收到 air_awaken 时调）：这边也给他描边，元婴以上加身周的空间波动，持续 secs 秒
func awaken_fx(secs: float) -> void:
	if hero == null:
		return
	if _awake_fx == null:
		_awake_fx = AwakenFx.new()
		_awake_fx.hero = hero
		_awake_fx.body = hero
		_awake_fx.hidden_fn = func() -> bool: return not is_visible_in_tree()
		add_child(_awake_fx)
	_awake_fx.start(secs, realm_idx, qi)


## 名字 / 队伍变了：队友退出索敌分组，别队的加进去
func set_info(info: Dictionary, is_mate: bool) -> void:
	display_name = str(info.get("name", "道友"))
	mate = is_mate
	for g: String in ["air_foes", "swordsmen"]:
		if mate and is_in_group(g):
			remove_from_group(g)
		elif not mate and not is_in_group(g):
			add_to_group(g)
	_refresh()


func _refresh() -> void:
	if _tag == null:
		return
	_tag.text = "%s%s  Lv.%d" % ["【队友】" if mate else "", display_name, lv]
	_tag.modulate = UiStyle.JADE.lightened(0.2) if mate else Color(1.0, 0.45, 0.4)
	(_bar.material_override as StandardMaterial3D).albedo_color = UiStyle.JADE if mate else Color(0.95, 0.3, 0.25)


func push_state(pos: Vector3, yaw: float, state: int, realm: int, hp_v: float, pose: String, pose_n: int, level: int, vel: Vector3,
		flag_bits: int) -> void:
	flags = flag_bits
	_to = pos
	_yaw = yaw
	_vel = vel
	st = state
	hp = hp_v
	_stale = 0.0
	if level != lv or realm != realm_idx:
		lv = level
		realm_idx = realm
		qi = Realm.line_color(Realm.LIST[clampi(realm, 0, Realm.count() - 1)])
		hero.set_look(realm)
		_refresh()
	if not _got:
		_got = true
		global_position = pos
		visible = true
	if pose_n != _pose_n:
		_pose_n = pose_n
		if pose != "" and Poses.SEQ.has(pose):
			rig.play(pose)
			rig.w_up = 1.0
			rig.w_leg = 1.0
			rig.w_up_target = 1.0
			rig.w_leg_target = 1.0


func _process(dt: float) -> void:
	if not _got:
		return
	_stale += dt
	visible = _stale < 3.0   # 三秒没消息（掉线前的空档）：先藏起来
	# 朝同步来的位置追，带一点速度外推，动作不发涩
	var want := _to + _vel * minf(_stale, 0.15)
	global_position = global_position.lerp(want, 1.0 - exp(-14.0 * dt)) if global_position.distance_to(want) < 30.0 else want
	visual.rotation.y = lerp_angle(visual.rotation.y, _yaw, 1.0 - exp(-12.0 * dt))
	var flat := Vector2(_vel.x, _vel.z).length()
	var grounded := st == 0
	var flying := st == 2 or st == 3 or st == 1
	_phase += dt * flat * 1.4
	if grounded and rig.time() > 0.6:
		# 地面上没在出招：收回站姿，让走路循环接管
		rig.w_up_target = 0.0
		rig.w_leg_target = 0.0
	hero.animate(dt, _phase, clampf(flat / 6.0, 0.0, 1.0), false, flying)
	rig.update(dt)
	rig.apply(dt)
	_flash = maxf(_flash - dt * 7.0, 0.0)
	hero.set_flash(_flash)
	_bar.scale.x = maxf(hp / 100.0, 0.001)


# ---------- 被怪打 ----------

## 别人名下的怪追着这个玩家打中了（raid_mob.gd 调，怪在我这边模拟）：发给他本人结算
func mob_hit(dmg: float, dir: Vector3, mob: Node3D = null, heavy := false) -> void:
	_flash = 0.7
	if net != null and mob != null:
		net.send_mob_attack(peer_id, int(mob.get("net_id")), dmg, heavy, dir)


# ---------- 飞剑对波（和 air_foe.gd 同一套接口，结果靠网络对账） ----------

func is_volleying() -> bool:
	return not mate and (flags & 1) != 0


func volley_active() -> bool:
	return is_volleying()


## 我朝他连发飞剑：告诉他一声（他那边会亮预警，可以接波）
func on_volley_incoming(_p: Node3D) -> void:
	if not mate and net != null:
		net.send_clash(peer_id, 3, 0.0)


func clash_origin() -> Vector3:
	return center() + Basis(Vector3.UP, visual.rotation.y) * Vector3(0.0, 0.2, -0.95)


func clash_power() -> float:
	return 0.0


## 我这边进了对波：叫他也进
func clash_begin() -> void:
	clash_their = 0.0
	if net != null:
		net.send_clash(peer_id, 0, 0.0)


func clash_end(_player_won: bool) -> void:
	pass


## 我累计顶了多少（每秒发十来次）
func net_clash_push(v: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _push_t >= 0.08 and net != null:
		_push_t = now
		net.send_clash(peer_id, 1, v)


## 我这边判了胜负（只有做主的一方判）
func net_clash_end(i_won: bool) -> void:
	if net != null:
		net.send_clash(peer_id, 2, 1.0 if i_won else 0.0)


# ---------- 目标接口（三套战斗共用） ----------

## 是玩家：飞剑打过来不追踪
func is_player() -> bool:
	return true


func is_alive() -> bool:
	return _got and hp > 0.0 and visible


func is_hostile() -> bool:
	return not mate


func is_broken() -> bool:
	return false


func is_airborne() -> bool:
	return st != 0


func is_downed() -> bool:
	return false


func is_launched() -> bool:
	return false


func velocity() -> Vector3:
	return _vel


func center() -> Vector3:
	return global_position + Vector3(0.0, BODY_Y, 0.0)


func aim_point() -> Vector3:
	return center()


func hit_radius() -> float:
	return 0.0


func blade_hand() -> Vector3:
	return center()


func blade_tip() -> Vector3:
	return center() + Basis(Vector3.UP, visual.rotation.y) * Vector3(0.0, 0.0, -1.0)


func chip_colors() -> Array:
	return [VoxelHero.W, VoxelHero.W2, VoxelHero.T, VoxelHero.S]


func hp_ratio() -> float:
	return hp / 100.0


func posture_ratio() -> float:
	return 0.0


func state_name() -> String:
	return "队友" if mate else ("腾空" if st != 0 else "对峙")


func begin_deathblow() -> void:
	pass


func deathblow_hit(_dir: Vector3) -> void:
	pass


func _send(info: Dictionary) -> int:
	if mate or not is_alive() or net == null or net.raid == null:
		return -1
	_flash = 1.0
	net.raid.net_deal_hit(self, peer_id, info)
	return 0


## 空战拳脚
func air_hit(_attacker: Node3D, info: Dictionary) -> int:
	return _send(info)


## 地面近战 / 飞剑 / 法术
func receive_hit(_attacker: Node3D, info: Dictionary) -> int:
	var i := info.duplicate()
	i["ranged"] = true
	return _send(i)
