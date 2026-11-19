extends Node3D
## 修仙刀客：可对打的近战敌人（斗笠、玄衣、赤缨弯刀），与主角共用体素骨架和关键帧姿势系统。
## 三种可读的攻击，前摇都有明确的蓄势姿势 + 刃尖一闪：
##   横斩（大幅右拧蓄力，金色刃光）、刺击（收刀沉身后突进，金色刃光）、延迟重击（举刀过顶悬停，红色刃光在落刀前才亮）。
## 状态：待机 / 追击 / 对峙 / 出招 / 格挡 / 受击 / 被弹开 / 破防（可处决）/ 被处决 / 死亡（延时复活）。
## 节奏：玩家连砍三刀后它开始格挡；连续格挡第三刀会弹开玩家并反击——逼玩家进入"读招弹反 → 削架势 → 破防"的循环。
## 空战：被上挑击飞后进入浮空（有重力、最多被追打 3 次续空、超时加速下落），被下砸砸回地面会弹一下再倒地，
## 起身后回到对峙；浮空中架势打满不会悬在空中，落地那一刻才破防。玩家跳到空中时它会用"上撩"防空，可在空中弹反。

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const Arc := preload("res://scripts/slash_arc.gd")

enum S { IDLE, CHASE, STANCE, ATTACK, GUARD, HURT, DEFLECTED, BROKEN, EXECUTED, DEAD, AIR, DOWNED }
enum A { SWEEP, THRUST, HEAVY, RISE }

const HP_MAX := 120.0
const POSTURE_MAX := 110.0
const AGGRO := 9.0
const LEASH := 16.0
const GOLD := Color(1.0, 0.82, 0.45)
const RED := Color(1.0, 0.22, 0.16)
const SABER_SCALE := 0.98    # 比上一版（0.9）稍大
const G_AIR := 17.0          # 浮空重力（比主角轻一点，留出追击时间）
const AIR_MAX := 1.9         # 浮空超过这么久就不再续空、加速落地
const JUGGLE_MAX := 3
const EMBER := Color(1.0, 0.42, 0.18)  # 死亡消融的亮边
const SHATTER_AT := 0.42               # 被处决后多久碎裂（战斗时间，对上主角处决的收刀）

## glint 刃光 | swing 挥刀声 | hit 判定 | trail 刀光区间 | lunge (起, 止, 最大速度) | reach 判定距离 | cone 夹角余弦
## vreach 能打到比自己高多少的主角（默认 1.25：跳起来能躲横斩，但躲不过上撩）
## dmg 伤害 | hit_pst 打中玩家时玩家涨架势 | block_pst 被格挡时玩家涨架势 | parry_pst 被弹反时自己涨架势 | parry_self 弹反时玩家涨架势
const ATK := [
	{"name": "横斩", "seq": "e_sweep", "glint": 0.4, "swing": 0.58, "hit": 0.645, "trail": Vector2(0.59, 0.8),
	 "lunge": Vector3(0.55, 0.68, 5.0), "reach": 2.45, "cone": 0.3, "end": 1.3, "heavy": false,
	 "dmg": 16.0, "hit_pst": 12.0, "block_pst": 20.0, "parry_pst": 30.0, "parry_self": 3.0},
	{"name": "刺击", "seq": "e_thrust", "glint": 0.44, "swing": 0.66, "hit": 0.72, "trail": Vector2(0.66, 0.86),
	 "lunge": Vector3(0.64, 0.76, 10.0), "reach": 3.2, "cone": 0.5, "end": 1.35, "heavy": false,
	 "dmg": 18.0, "hit_pst": 12.0, "block_pst": 22.0, "parry_pst": 30.0, "parry_self": 3.0},
	{"name": "延迟重击", "seq": "e_heavy", "glint": 0.9, "swing": 1.02, "hit": 1.095, "trail": Vector2(1.02, 1.22),
	 "lunge": Vector3(0.98, 1.1, 5.0), "reach": 2.6, "cone": 0.3, "end": 1.8, "heavy": true,
	 "dmg": 28.0, "hit_pst": 18.0, "block_pst": 34.0, "parry_pst": 42.0, "parry_self": 6.0},
	{"name": "上撩", "seq": "e_rise", "glint": 0.3, "swing": 0.52, "hit": 0.58, "trail": Vector2(0.53, 0.76),
	 "lunge": Vector3(0.46, 0.58, 4.0), "reach": 2.7, "cone": 0.3, "vreach": 3.4, "end": 1.2, "heavy": false,
	 "dmg": 15.0, "hit_pst": 12.0, "block_pst": 20.0, "parry_pst": 34.0, "parry_self": 3.0},
]

var player: Player
var display_name := "刀客"
var ai_enabled := true
var block_chance := 0.25
var hp := HP_MAX
var posture := 0.0
var state := S.IDLE
var home := Vector3.ZERO
var home_yaw := 0.0

var visual: Node3D
var hero: VoxelHero
var rig: Rig
var blade: Node3D

var _t := 0.0
var _clock := 0.0
var _dur := 0.0
var _facing := 0.0
var _vel := Vector3.ZERO
var _phase := 0.0
var _cd := 1.0
var _atk: Dictionary = ATK[0]
var _kind := 0
var _last_kind := -1
var _hit_done := false
var _glinted := false
var _swung := false
var _lunge_spd := 0.0
var _lunge_set := false
var _hits_in_row := 0
var _blocks_in_row := 0
var _hit_at := -10.0
var _pst_at := -10.0
var _counter := false
var _flash := 0.0
var _strafe := 1.0
var _trail: Trail3D
var _arc: Arc
var _marker: MeshInstance3D
var _marker_dot: MeshInstance3D
var _gone := false
var _death_dir := Vector3.FORWARD
var _vy := 0.0
var _air_t := 0.0
var _juggles := 0
var _spiked := false
var _bounced := false
var _pending_break := false
var _shake := 0.0


func _ready() -> void:
	add_to_group("swordsmen")
	home = global_position
	_facing = home_yaw
	visual = Node3D.new()
	add_child(visual)
	hero = VoxelHero.new(_palette(), true, true)
	visual.add_child(hero)
	blade = MeshLib.make_saber(Color(0.9, 0.25, 0.15))
	rig = Rig.new(hero, blade, SABER_SCALE, -0.42, 0.8)
	rig.cur = Poses.get_pose("e_stance")
	rig.play("e_stance")
	rig.w_up = 1.0
	rig.w_leg = 1.0
	rig.w_up_target = 1.0
	rig.w_leg_target = 1.0

	_trail = Trail3D.new()
	_trail.width = 0.05
	_trail.lifetime = 0.16
	_trail.min_px = 2.0
	_trail.min_step = 0.015
	_trail.taper = 1.3
	_trail.point_fn = rig.blade_point.bind(1.0)
	_trail.material_override = MeshLib.trail_material(Color(1.0, 0.86, 0.72), Color(0.92, 0.28, 0.16), 0, 1.1)
	Vfx.root.add_child(_trail)
	_arc = Arc.new()
	_arc.lifetime = 0.2
	_arc.inner_fn = rig.blade_point.bind(0.4)
	_arc.outer_fn = rig.blade_point.bind(1.02)
	_arc.material_override = Arc.make_material(Color(1.0, 0.88, 0.75), Color(0.9, 0.3, 0.18))
	Vfx.root.add_child(_arc)
	# 破绽标记：红色细环 + 中心细星（破防后出现，提示可以处决）
	_marker = Vfx.marker_sprite(RED, 1, 0.34)
	_marker_dot = Vfx.marker_sprite(RED, 0, 0.26)
	_marker.visible = false
	_marker_dot.visible = false


func _exit_tree() -> void:
	for n: Node in [_trail, _arc, _marker, _marker_dot]:
		if is_instance_valid(n):
			n.queue_free()


static func _palette() -> Dictionary:
	return {
		VoxelHero.W: Color(0.21, 0.22, 0.26), VoxelHero.W2: Color(0.15, 0.16, 0.19),
		VoxelHero.W3: Color(0.34, 0.3, 0.3), VoxelHero.T: Color(0.62, 0.13, 0.14),
		VoxelHero.T2: Color(0.86, 0.32, 0.26), VoxelHero.G: Color(0.62, 0.48, 0.28),
		VoxelHero.J: Color(0.78, 0.22, 0.2), VoxelHero.EI: Color(0.45, 0.12, 0.08),
		VoxelHero.K2: Color(0.32, 0.3, 0.3),
	}


# ---------- 查询（供主角近战 / HUD / 演示脚本） ----------

func is_alive() -> bool:
	return state != S.DEAD and state != S.EXECUTED and not _gone


func is_hostile() -> bool:
	return is_alive() and (state != S.IDLE or not ai_enabled)


func is_broken() -> bool:
	return state == S.BROKEN


func is_airborne() -> bool:
	return state == S.AIR


func is_downed() -> bool:
	return state == S.DOWNED


func chip_colors() -> Array:
	return hero.chip_colors()


## 演示用：立刻回到地面对峙、清空架势与血量，不播任何特效
func demo_reset() -> void:
	if not is_alive():
		return
	hp = HP_MAX
	posture = 0.0
	_pending_break = false
	_vy = 0.0
	global_position.y = 0.0
	visual.rotation.x = 0.0
	_marker.visible = false
	_marker_dot.visible = false
	_hits_in_row = 0
	_blocks_in_row = 0
	_enter(S.STANCE)
	rig.play("e_stance")
	_cd = 1.0


func hp_ratio() -> float:
	return hp / HP_MAX


func posture_ratio() -> float:
	return posture / POSTURE_MAX


func state_name() -> String:
	match state:
		S.ATTACK:
			return _atk["name"]
		S.GUARD:
			return "格挡"
		S.HURT:
			return "受击"
		S.DEFLECTED:
			return "被弹开"
		S.BROKEN:
			return "破防"
		S.EXECUTED, S.DEAD:
			return "斩杀"
		S.CHASE:
			return "追击"
		S.AIR:
			return "浮空"
		S.DOWNED:
			return "倒地"
	return "对峙"


func attack_time() -> float:
	return _t if state == S.ATTACK else -1.0


## 距离本次出刀判定还有多久（战斗时间）；不在出招中返回 INF
func time_to_hit() -> float:
	if state != S.ATTACK or _hit_done:
		return INF
	return float(_atk["hit"]) - _t


func blade_hand() -> Vector3:
	return rig.hand_pos()


func blade_tip() -> Vector3:
	return rig.tip_pos()


func center() -> Vector3:
	return global_position + Vector3(0.0, 1.05, 0.0)


func _fwd() -> Vector3:
	return Basis(Vector3.UP, _facing) * Vector3.FORWARD


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _enter(s: S, dur := 0.0) -> void:
	state = s
	_t = 0.0
	_dur = dur


# ---------- 出招 ----------

## 直接摆到某处（演示截图用）
func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	_facing = yaw
	visual.rotation.y = yaw
	_vel = Vector3.ZERO


func force_attack(kind: int) -> void:
	if is_alive() and state != S.BROKEN and state != S.AIR and state != S.DOWNED:
		_start_attack(kind)


func _start_attack(kind: int) -> void:
	_kind = kind
	_last_kind = kind
	_atk = ATK[kind]
	_enter(S.ATTACK)
	_hit_done = false
	_glinted = false
	_swung = false
	_lunge_set = false
	_hits_in_row = 0
	_blocks_in_row = 0
	_counter = false
	rig.play(_atk["seq"])


func _choose_attack(dist: float) -> void:
	var k := A.SWEEP
	if dist > 2.6:
		k = A.THRUST
	else:
		var r := randf()
		if r < 0.42:
			k = A.SWEEP
		elif r < 0.72 and _last_kind != A.HEAVY:
			k = A.HEAVY
		else:
			k = A.THRUST
	_start_attack(k)


func _tick_attack(dirp: Vector3, dist: float) -> Vector3:
	var a := _atk
	var move := Vector3.ZERO
	if _t < float(a["hit"]) - 0.14:
		_face(dirp, 9.0)
	var lg: Vector3 = a["lunge"]
	if _t >= lg.x and _t < lg.y:
		if not _lunge_set:
			_lunge_set = true
			var go := clampf(dist - 1.35, 0.0, lg.z * (lg.y - lg.x))
			_lunge_spd = go / (lg.y - lg.x)
			if go > 0.3:
				Vfx.step_ring(global_position, Color(0.9, 0.85, 0.8))
		move = _fwd() * _lunge_spd
	if not _glinted and _t >= float(a["glint"]):
		_glinted = true
		var heavy: bool = a["heavy"]
		Vfx.glint(rig.blade_point(0.92), RED if heavy else GOLD, 1.0 if heavy else 0.8)
		Sfx.play("block", -16.0, 2.4 if not heavy else 1.6)
	if not _swung and _t >= float(a["swing"]):
		_swung = true
		Sfx.play("swing_heavy" if bool(a["heavy"]) else "swing", -6.0, 0.8)
	if not _hit_done and _t >= float(a["hit"]):
		_hit_done = true
		_resolve()
		if state != S.ATTACK:
			return Vector3.ZERO
	var tr: Vector2 = a["trail"]
	_trail.emitting = _t >= tr.x and _t <= tr.y
	_arc.emitting = _trail.emitting
	if _t >= float(a["end"]):
		_trail.emitting = false
		_arc.emitting = false
		_enter(S.STANCE)
		rig.play("e_stance")
		_cd = randf_range(0.8, 1.5)
		# 横斩后有一定概率直接接刺击（连招）
		if ai_enabled and _kind == A.SWEEP and randf() < 0.3:
			_cd = 0.05
	return move


func _resolve() -> void:
	if player.st == Player.St.GROUND and player.in_perfect_window() and _would_hit(player.dodge_origin(), 0.6):
		# 完美闪避：判定帧落在主角闪避刚开始的那一小段里，而闪避前站的位置本来会被砍中
		player.perfect_dodge(self)
		return
	var d := _flat(player.global_position - global_position)
	var dist := d.length()
	var dirp := d / dist if dist > 0.01 else _fwd()
	if player.st != Player.St.GROUND or dist > float(_atk["reach"]) + 0.3 or _fwd().dot(dirp) < float(_atk["cone"]):
		return
	# 主角跳得够高就躲过去了（横斩、刺击、重击）；上撩专门打空中
	if player.global_position.y - global_position.y > float(_atk.get("vreach", 1.25)):
		return
	var res: int = player.melee.receive_attack(self, _atk)
	if res == 2:
		_on_parried()


## 站在 p 的人会不会被这一刀砍中（slack：放宽的距离，闪避判定宽容一点）
func _would_hit(p: Vector3, slack: float) -> bool:
	var d := _flat(p - global_position)
	var dist := d.length()
	if dist > float(_atk["reach"]) + 0.3 + slack:
		return false
	if dist > 0.3 and _fwd().dot(d / dist) < float(_atk["cone"]) - 0.25:
		return false
	return p.y - global_position.y <= float(_atk.get("vreach", 1.25))


## 被主角弹反：刀被磕开，架势大涨；顿帧期间停在对刃那一刻，之后才向后弹开
func _on_parried() -> void:
	_trail.emitting = false
	_arc.emitting = false
	_add_posture(float(_atk["parry_pst"]))
	if state == S.BROKEN:
		return
	_enter(S.DEFLECTED, 0.62)
	rig.play("e_deflected")
	_vel = -_fwd() * 2.2


# ---------- 挨打 ----------

## 主角出刀判定时调用。返回 0 命中 / 1 格挡 / 2 弹开主角 / -1 无效
func receive_hit(_attacker: Node3D, info: Dictionary) -> int:
	if not is_alive() or state == S.BROKEN or state == S.DOWNED:
		return -1
	if _clock - _hit_at > 1.5:
		_hits_in_row = 0
	var dir: Vector3 = info["dir"]
	var heavy: bool = info["heavy"]
	if state == S.AIR:
		return _air_hit(info, dir)
	var block := false
	match state:
		S.GUARD:
			block = true
		S.IDLE, S.CHASE, S.STANCE:
			block = _hits_in_row >= 3 or randf() < block_chance
		S.HURT:
			block = _hits_in_row >= 3
	if info.get("unblockable", false):
		block = false  # 完美闪避后的瞬移斩：来不及格挡
	_face(-dir, 0.0)
	if block:
		_blocks_in_row += 1
		var c: Vector3 = info["contact"]
		var p := rig.aim_pose(Poses.get_pose("e_block"), c)
		rig.snap(p, [[0.14, p, 0], [0.4, Poses.get_pose("e_stance"), 2]])
		rig.apply(0.0)
		if _blocks_in_row >= 3:
			# 弹开主角，随即反击
			_blocks_in_row = 0
			_add_posture(4.0)
			_enter(S.GUARD, 0.22)
			_counter = true
			return 2
		_add_posture(float(info["pst"]) * (0.8 if heavy else 0.6))
		if state != S.BROKEN:
			_enter(S.GUARD, 0.45)
			_vel = dir * 1.6
			_counter = _counter or randf() < 0.3
		return 1
	# 命中：闪白 + 顿帧期间原地抖动 + 受击姿势当帧摆出（不等顿帧结束）
	_blocks_in_row = 0
	_hits_in_row += 1
	_hit_at = _clock
	_take_damage(info)
	if state == S.BROKEN:
		return 0
	if hp <= 0.0:
		_break()
		return 0
	_vel = dir * float(info["kb"])
	if state == S.ATTACK:
		return 0  # 出招中霸体：吃伤害、闪白，但不被打断（只能靠弹反破招）
	var launch := float(info.get("launch", 0.0))
	if launch > 0.0:
		_launch(launch, dir)
		return 0
	if info.get("slam", false):
		# 下砸砸中地面上的人：先被震得弹起一点，落地即倒
		_launch(4.5, dir)
		_spiked = true
		_bounced = true
		_juggles = JUGGLE_MAX
		return 0
	_enter(S.HURT, 0.55 if heavy else 0.32)
	var sw: Vector3 = info.get("swing", Vector3.RIGHT)
	var side := sw.dot(Basis(Vector3.UP, _facing) * Vector3.RIGHT)
	var pose := "e_hurt_h" if heavy else ("e_hurt2" if side > 0.0 else "e_hurt")
	_snap_pose(pose, 0.32 if heavy else 0.16, 0.6 if heavy else 0.38)
	return 0


func _take_damage(info: Dictionary) -> void:
	hp = maxf(hp - float(info["dmg"]), 0.0)
	_flash = 1.0
	_shake = float(info.get("stop", 0.08)) + 0.03
	Vfx.damage_number(center() + Vector3(0, 0.5, 0), float(info["dmg"]), Color(1.0, 0.5, 0.4))
	_add_posture(float(info["pst"]))


## 受击姿势：当帧先摆到七成，再按时间轴走完、回到戒备
func _snap_pose(pose_name: String, hold: float, back: float) -> void:
	var p := Poses.get_pose(pose_name)
	rig.snap(Poses.lerp_pose(rig.cur, p, 0.7), [[0.05, p, 1], [hold, p, 0], [back, Poses.get_pose("e_stance"), 2]])
	rig.apply(0.0)


## 浮空中挨打：不能格挡、不霸体；每次命中托高一点（有次数和时间上限），下砸则直接往下砸
func _air_hit(info: Dictionary, dir: Vector3) -> int:
	_hits_in_row += 1
	_hit_at = _clock
	_take_damage(info)
	_vel = dir * float(info["kb"]) * 0.35
	if info.get("spike", false):
		_vy = -18.0
		_spiked = true
		_juggles = JUGGLE_MAX
	elif _juggles < JUGGLE_MAX and _air_t < AIR_MAX - 0.3:
		_vy = maxf(_vy, 3.4)
		_juggles += 1
	else:
		_vy = minf(_vy, 0.0)
	var p := Poses.get_pose("e_air2")
	rig.snap(Poses.lerp_pose(rig.cur, p, 0.75), [[0.05, p, 1], [0.25, p, 0], [0.45, Poses.get_pose("e_air"), 2]])
	rig.apply(0.0)
	return 0


func _launch(v: float, dir: Vector3) -> void:
	_enter(S.AIR)
	_vy = v
	_air_t = 0.0
	_juggles = 0
	_spiked = false
	_bounced = false
	_vel = dir * 1.2
	_trail.emitting = false
	_arc.emitting = false
	var p := Poses.get_pose("e_air")
	rig.snap(Poses.lerp_pose(rig.cur, Poses.get_pose("e_hurt_h"), 0.8), [[0.08, p, 1]])
	rig.apply(0.0)


## 落地：被砸下来的先弹一下；之后倒地（或者在空中攒满的架势这时才破防）
func _land() -> void:
	var hard := _spiked or _vy < -10.0
	global_position.y = 0.0
	Vfx.dust(global_position, 10 if hard else 6, 3.5 if hard else 2.5)
	Sfx.play("thud", -2.0 if hard else -6.0, 0.9)
	if hard and not _bounced:
		_bounced = true
		_vy = 3.2
		Vfx.debris(center() - Vector3(0, 0.6, 0), Vector3.UP, chip_colors(), 6, 3.5)
		return
	_vy = 0.0
	if _pending_break or hp <= 0.0:
		_pending_break = false
		_break()
		return
	_enter(S.DOWNED, 0.95 if hard else 0.6)
	rig.play("e_down")
	_vel *= 0.3
	player.melee.combat_event.emit("enemy_down", {"hard": hard})


func _add_posture(v: float) -> void:
	posture = minf(posture + v, POSTURE_MAX)
	_pst_at = _clock
	if posture >= POSTURE_MAX and state != S.BROKEN:
		if state == S.AIR:
			_pending_break = true  # 不悬在空中破防，落地再说
		else:
			_break()


func _break() -> void:
	posture = POSTURE_MAX
	global_position.y = 0.0
	_vy = 0.0
	_enter(S.BROKEN, 3.2)
	_trail.emitting = false
	_arc.emitting = false
	rig.play("e_broken")
	_vel = -_fwd() * 1.5
	_marker.visible = true
	_marker_dot.visible = true
	Sfx.play("clash", -2.0, 0.7)
	Vfx.ribbon_burst(center(), Vector3.UP, RED, 8, 6.0, 70.0, 0.4)
	player.melee.combat_event.emit("enemy_break", {"pos": center()})


func begin_deathblow() -> void:
	_enter(S.EXECUTED)
	_marker.visible = false
	_marker_dot.visible = false


func deathblow_hit(dir: Vector3) -> void:
	hp = 0.0
	_flash = 1.0
	_enter(S.DEAD)
	rig.play("e_dead")
	_vel = dir * 1.2
	_death_dir = dir


## 碎裂：按当前姿势把身体（连同弯刀）拆成方块，从胸口被斩处向外崩开，随后消融
func _shatter() -> void:
	_gone = true
	_trail.emitting = false
	_arc.emitting = false
	var hit := center() + Vector3(0.0, 0.1, 0.0) - _death_dir * 0.2
	# 弯刀碎成一串金属块，沿刀身摆开（刀柄两块是赤缨色）
	var h := blade_hand()
	var tip := blade_tip()
	var bd := tip - h
	var up := Vector3.UP if absf(bd.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var bb := Basis.looking_at(bd.normalized(), up) if bd.length() > 0.05 else Basis.IDENTITY
	var extra := []
	for i in 7:
		extra.append([Transform3D(bb, h.lerp(tip, (float(i) + 0.5) / 7.0)), 0.07,
				Color(0.78, 0.8, 0.84) if i > 1 else Color(0.62, 0.13, 0.14)])
	Vfx.shatter(visual, hit, _death_dir, EMBER, 1.0, [], 0.11, extra)
	visual.visible = false
	Sfx.play("shatter", 0.0)
	Sfx.play("execute", -10.0, 1.4)
	Vfx.ribbon_burst(hit, Vector3.UP, RED, 8, 6.0, 120.0, 0.45)


func _respawn() -> void:
	_gone = false
	hp = HP_MAX
	posture = 0.0
	global_position = home
	_facing = home_yaw
	_vel = Vector3.ZERO
	visual.visible = true
	visual.rotation.x = 0.0
	visual.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Vfx.reappear(center(), RED)
	rig.cur = Poses.get_pose("e_stance")
	rig.play("e_stance")
	_enter(S.IDLE)


# ---------- 每帧 ----------

func _face(dir: Vector3, rate: float) -> void:
	if dir.length_squared() < 1e-4:
		return
	var want := atan2(-dir.x, -dir.z)
	if rate <= 0.0:
		_facing = want
		visual.rotation.y = want  # 当帧生效：格挡姿势按新朝向摆
	else:
		_facing = lerp_angle(_facing, want, 1.0 - exp(-rate * Combat.cdt(get_process_delta_time())))


func _process(dt: float) -> void:
	var cdt := Combat.cdt(dt)
	_clock += cdt
	_t += cdt
	_vel = _vel.move_toward(Vector3.ZERO, 9.0 * cdt)
	var to_p := _flat(player.global_position - global_position)
	var dist := to_p.length()
	var dirp := to_p / dist if dist > 0.01 else _fwd()
	var p_down := player.melee.state == Player.PlayerMelee.M.DOWN
	var reachable := player.st == Player.St.GROUND and not p_down \
			and (player.global_position - home).length() < LEASH
	var move := Vector3.ZERO

	match state:
		S.IDLE:
			if reachable and (dist < AGGRO or not ai_enabled):
				_enter(S.CHASE if ai_enabled else S.STANCE)
			else:
				var hd := _flat(home - global_position)
				if hd.length() > 0.4:
					move = hd.normalized() * 2.5
					_face(hd, 6.0)
				else:
					_facing = lerp_angle(_facing, home_yaw, 1.0 - exp(-3.0 * cdt))
		S.CHASE:
			_face(dirp, 8.0)
			if not reachable:
				_enter(S.IDLE)
			elif dist > 2.2:
				move = dirp * 3.4
			else:
				_enter(S.STANCE)
				_cd = randf_range(0.5, 1.1)
		S.STANCE:
			_face(dirp, 10.0)
			if not reachable:
				if ai_enabled:
					_enter(S.IDLE)
			elif ai_enabled:
				if dist > 2.7:
					move = dirp * 2.4
				elif dist < 1.5:
					move = -dirp * 1.6
				else:
					if randf() < 0.01:
						_strafe = -_strafe
					move = dirp.cross(Vector3.UP) * 0.7 * _strafe
				_cd -= cdt
				if _counter:
					_counter = false
					_cd = minf(_cd, 0.12)
				# 防空：主角跳到头顶附近，就用上撩迎上去
				var p_air := player.global_position.y - global_position.y > 0.8
				if p_air and dist < 3.0 and _cd < 0.45 and not p_down:
					_start_attack(A.RISE)
				elif _cd <= 0.0 and not p_down:
					_choose_attack(dist)
		S.ATTACK:
			move = _tick_attack(dirp, dist)
		S.GUARD, S.HURT, S.DEFLECTED:
			if state == S.GUARD:
				_face(dirp, 10.0)
			if _t >= _dur:
				_enter(S.STANCE)
				rig.play("e_stance")
				_cd = randf_range(0.6, 1.2)
				if _counter and ai_enabled:
					_counter = false
					_start_attack(A.SWEEP if randf() < 0.6 else A.THRUST)
		S.BROKEN:
			_marker_pulse()
			if _t >= _dur:
				posture = POSTURE_MAX * 0.5
				_marker.visible = false
				_marker_dot.visible = false
				if hp <= 0.0:
					hp = HP_MAX * 0.2
				_enter(S.STANCE)
				rig.play("e_stance")
				_cd = 0.6
		S.AIR:
			_air_t += cdt
			_vy -= G_AIR * (1.8 if _air_t > AIR_MAX else 1.0) * cdt
		S.DOWNED:
			if _t >= _dur:
				_enter(S.STANCE)
				rig.play("e_stance")
				_cd = randf_range(0.5, 0.9)
		S.EXECUTED:
			pass
		S.DEAD:
			# 被斩后僵住一拍、身上渐亮，对上主角处决的收刀时整个人碎成方块，随后消融
			if not _gone:
				_flash = maxf(_flash, 0.55 * smoothstep(SHATTER_AT - 0.2, SHATTER_AT, _t))
				if _t >= SHATTER_AT:
					_shatter()
			if _t >= 4.5:
				_respawn()

	# 架势回复：一段时间没被削后回落，血越少回得越慢（只狼）
	if state != S.BROKEN and state != S.DEAD and state != S.EXECUTED and _clock - _pst_at > 1.4:
		posture = maxf(posture - 7.0 * (0.3 + 0.7 * hp / HP_MAX) * cdt, 0.0)

	global_position += (move + _vel) * cdt
	if state == S.AIR:
		global_position.y += _vy * cdt
		if global_position.y <= 0.0 and _vy <= 0.0:
			_land()
	else:
		global_position.y = 0.0
	var same_level := absf(player.global_position.y - global_position.y) < 1.0
	if is_alive() and same_level and state != S.AIR and dist < 0.95 and dist > 0.001:
		global_position -= dirp * (0.95 - dist)
	var off := _flat(global_position - home)
	if off.length() > LEASH:
		global_position = home + off.limit_length(LEASH)

	visual.rotation.y = _facing
	# 浮空后仰、倒地扑倒、起身复原（死亡另有自己的倒下过程）
	if state != S.DEAD:
		var tilt := 0.0
		if state == S.AIR:
			tilt = 0.45
		elif state == S.DOWNED:
			tilt = -1.3 if _t < _dur - 0.3 else 0.0
		visual.rotation.x = lerpf(visual.rotation.x, tilt, 1.0 - exp(-10.0 * cdt))
	# 受击抖动：顿帧期间原地小幅乱抖（真实时间衰减）
	if _shake > 0.0:
		_shake -= minf(dt, Combat.MAX_DT)
		var a := 0.04 * clampf(_shake / 0.08, 0.0, 1.0)
		visual.position = Vector3(randf_range(-a, a), 0.0, randf_range(-a, a))
	else:
		visual.position = Vector3.ZERO
	var walk := clampf(move.length() / 3.0, 0.0, 1.0) if state == S.IDLE or state == S.CHASE or state == S.STANCE else 0.0
	_phase += cdt * move.length() * 1.6
	hero.animate(cdt, _phase, walk, false, false)
	rig.w_leg_target = 0.0 if walk > 0.15 else 1.0
	rig.update(cdt)
	rig.apply(cdt)

	_flash = maxf(_flash - cdt * 7.0, 0.0)
	hero.set_flash(_flash)
	if state != S.ATTACK:
		_trail.emitting = false
		_arc.emitting = false
	_trail.time_scale = Combat.time_scale()
	_arc.time_scale = Combat.time_scale()


func _marker_pulse() -> void:
	var p := center() + Vector3(0.0, 0.15, 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		p += (cam.global_position - p).normalized() * 0.45
	var s := 1.0 + 0.12 * sin(_clock * 9.0)
	_marker.global_position = p
	_marker.scale = Vector3.ONE * 0.34 * s
	_marker_dot.global_position = p
	_marker_dot.scale = Vector3.ONE * 0.26 * s
