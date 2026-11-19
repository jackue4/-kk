extends Node3D
## 空战对手（魔修 / 陪练木人）：和主角同一套 R15 体素骨架，悬在半空，能被拳脚打出硬直、被重击击飞、
## 撞上地面 / 建筑砸出坑，也会追上来连打、远处放剑气。主角的空战近战见 air_melee.gd。
## · air_hit(attacker, info)：主角拳脚 / 重击的结算入口。返回 0 命中 / 1 被格挡 / 2 破防命中 / -1 无效。
##   info: dmg | dir 击退方向（三维）| kb 击退速度 | stun 硬直 | launch ""/"fwd"/"up"/"down" | heavy | contact
## · receive_hit(attacker, info)：法术 / 飞剑的结算入口（spell_projectile.gd 的 hurt 调用），只给轻硬直。
## · 被击飞（BLOWN）期间沿速度方向打射线：撞到地面 → 砸坑、倒地、再飘起；撞到墙柱 → 弹开。
## ai_enabled = false 的是陪练木人：只悬着挨打，不还手。
## pro = true 的是「真人陪练」：打法照着真人玩家来 —— 四拳一重击的连段、把主角击飞后瞬身追到头顶往地面砸、
## 挨第一下时有几率瞬身绕到背后反打、冲过来时护体、远处放光柱；主角放光柱时它会回一道，进入对波相持。
## 头顶有名牌和血条。
## 故意不写 class_name：用 preload 引用。

signal died(foe: Node3D)

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const Rig := preload("res://scripts/fighter_rig.gd")
const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const AirBeam := preload("res://scripts/air_beam.gd")

enum S { IDLE, CHASE, WINDUP, STRIKE, RECOVER, SHOOT, GUARD, STUN, BLOWN, DOWN, RISE, DEAD, BEAM, CLASH }

const QI := Color(0.95, 0.22, 0.32)
const BODY_Y := 0.95          # 身体中心离脚底
const AGGRO := 30.0
const LEASH := 90.0
const FLY_SPD := 14.0
const STRIKE_R := 2.6         # 出手那一下主角在这个距离内才算打中
const BOLT_SPD := 34.0
const BLOWN_DRAG := 0.55
const BLOWN_G := 5.0
const CRASH_MIN := 12.0       # 撞击速度超过这个才算砸实
const RESPAWN := 5.0

var player: Player
var display_name := "魔修"
var ai_enabled := true
var style := 0                # 0 魔修（黑衣白发） 1 陪练木人（草色） 2 真人陪练（青衣）
## 搜打撤里的「其他修士」（raid_manager.gd 生成）：主角在地面也照打不误、不复活、死后由管理器掉箱子
var raid := false
var dmg_mul := 1.0
var floor_fn := Callable()    # func(x, z) -> 地面高度
var pro := false              # 真人式打法（见文件头）
var qi := QI                  # 气劲 / 光柱颜色
## 搜打撤里自由活动（raid_manager.gd 填）：四处游荡、找附近的怪打；hostile 的见到主角就动手，
## 不 hostile 的各刷各的怪，被主角打了才翻脸。engage_ok 由管理器限流（同时围攻主角的不超过两个）。
var roam := false
var hostile := true
var lv := 1
var prey_dmg := 12.0
var dmg_in := Callable()      # func(主角打出的伤害) -> 实际扣的血
var prey_fn := Callable()     # func(自己) -> 附近的一只怪（没有则 null）
var engage_ok := Callable()   # func(自己) -> 现在能不能去打主角
var _prey: Node3D = null
var _prey_cd := 0.0
var _swing_cd := 0.0
var _swung := false
var _roam_t := 0.0
var _roam_to := Vector3.ZERO
var _ci := 0                  # 连段打到第几下
var _hit_t := 0.085
var _strike_dir := Vector3.ZERO   # 非零：这一下的击飞方向（追击下砸）
var _chase_at := -1.0         # 把主角击飞后，这么久后瞬身追击
var _vanish_cd := 3.0
var _beam: Node3D = null
var _beam_cd := 7.0
var _beam_wind := 0.6
var _beam_fired := false
var _beam_dir := Vector3.FORWARD
var _beam_tick := 0.0
var _tag: Label3D
var hp_max := 900.0
var hp := 900.0
var state := S.IDLE
var home := Vector3.ZERO

var visual: Node3D
var spin: Node3D
var hero: VoxelHero
var rig: Rig

var _t := 0.0
var _dur := 0.0
var _facing := 0.0
var _vel := Vector3.ZERO
var _cd := 1.5
var _shoot_cd := 4.0
var _string := 0              # 这一串还剩几下
var _heavy := false
var _hit_done := false
var _flash := 0.0
var _shake := 0.0
var _tumble := 0.0
var _tumble_v := 0.0
var _pitch := 0.0
var _alt := false
var _doomed := false
var _death_dir := Vector3.FORWARD
var _bolts: Array = []        # [面片, 位置, 速度, 寿命]
var _shots := 0
var _bar: MeshInstance3D
var _trail: Trail3D
var _guard_roll := false
var _crashed := false


func _ready() -> void:
	add_to_group("air_foes")
	if raid:
		add_to_group("swordsmen")   # 地面近战也能锁它、砍它
	home = global_position
	hp = hp_max
	visual = Node3D.new()
	add_child(visual)
	spin = Node3D.new()
	spin.position.y = BODY_Y
	visual.add_child(spin)
	var holder := Node3D.new()
	holder.position.y = -BODY_Y
	spin.add_child(holder)
	hero = VoxelHero.new(_palette(), true)
	holder.add_child(hero)
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
	bm.albedo_color = Color(0.95, 0.3, 0.25)
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.billboard_keep_scale = true
	bm.no_depth_test = true
	_bar.material_override = bm
	_bar.position.y = 2.3
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	# 头顶名牌
	_tag = Label3D.new()
	_tag.text = ("%s  Lv.%d" % [display_name, lv]) if raid else display_name
	_tag.font = Vfx.font
	_tag.font_size = 40
	_tag.pixel_size = 0.006
	_tag.outline_size = 10
	_tag.modulate = Color.WHITE.lerp(qi, 0.45)
	_tag.outline_modulate = Color(0.08, 0.08, 0.1, 0.9)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.position.y = 2.6
	add_child(_tag)
	_refresh_tag()

	# 被击飞时身后拖一道气浪
	_trail = Trail3D.new()
	_trail.width = 0.5
	_trail.lifetime = 0.35
	_trail.min_px = 3.0
	_trail.point_fn = center
	_trail.emitting = false
	_trail.material_override = MeshLib.trail_material(Color(1.0, 1.0, 1.0), Color(0.8, 0.85, 0.95), 0, 0.9)
	Vfx.root.add_child(_trail)


func _exit_tree() -> void:
	if is_instance_valid(_trail):
		_trail.queue_free()
	for b: Array in _bolts:
		if is_instance_valid(b[0]):
			(b[0] as Node).queue_free()
	_bolts.clear()


func _palette() -> Dictionary:
	if style == 2:
		return {
			VoxelHero.W: Color(0.16, 0.6, 0.58), VoxelHero.W2: Color(0.86, 0.87, 0.9),
			VoxelHero.W3: Color(0.3, 0.7, 0.66), VoxelHero.T: Color(0.1, 0.32, 0.36),
			VoxelHero.T2: Color(0.4, 0.8, 0.76), VoxelHero.H: Color(0.36, 0.24, 0.16),
			VoxelHero.H2: Color(0.5, 0.36, 0.24), VoxelHero.G: Color(0.95, 0.92, 0.85),
			VoxelHero.J: Color(0.95, 0.8, 0.85), VoxelHero.K: Color(0.82, 0.83, 0.86),
			VoxelHero.K2: Color(0.6, 0.62, 0.66),
		}
	if style == 1:
		return {
			VoxelHero.W: Color(0.78, 0.66, 0.45), VoxelHero.W2: Color(0.66, 0.54, 0.36),
			VoxelHero.W3: Color(0.55, 0.45, 0.3), VoxelHero.T: Color(0.45, 0.32, 0.2),
			VoxelHero.T2: Color(0.6, 0.45, 0.28), VoxelHero.S: Color(0.86, 0.76, 0.56),
			VoxelHero.S2: Color(0.8, 0.68, 0.48), VoxelHero.H: Color(0.5, 0.38, 0.24),
			VoxelHero.H2: Color(0.6, 0.47, 0.3), VoxelHero.K: Color(0.4, 0.3, 0.2),
			VoxelHero.K2: Color(0.5, 0.4, 0.28), VoxelHero.G: Color(0.7, 0.2, 0.18),
			VoxelHero.J: Color(0.7, 0.2, 0.18), VoxelHero.M: Color(0.5, 0.3, 0.2),
		}
	return {
		VoxelHero.W: Color(0.17, 0.14, 0.22), VoxelHero.W2: Color(0.11, 0.09, 0.16),
		VoxelHero.W3: Color(0.32, 0.2, 0.3), VoxelHero.T: Color(0.62, 0.1, 0.2),
		VoxelHero.T2: Color(0.92, 0.3, 0.36), VoxelHero.G: Color(0.72, 0.56, 0.3),
		VoxelHero.J: Color(0.85, 0.2, 0.3), VoxelHero.H: Color(0.86, 0.86, 0.92),
		VoxelHero.H2: Color(0.66, 0.69, 0.8), VoxelHero.EI: Color(0.85, 0.15, 0.1),
		VoxelHero.K: Color(0.1, 0.08, 0.13), VoxelHero.K2: Color(0.36, 0.3, 0.36),
		VoxelHero.S: Color(0.9, 0.86, 0.86), VoxelHero.S2: Color(0.8, 0.7, 0.76),
	}


# ---------- 查询 ----------

func is_alive() -> bool:
	return state != S.DEAD


func is_launched() -> bool:
	return state == S.BLOWN


func is_broken() -> bool:
	return false


## ---- 地面近战（PlayerMelee）要的接口 ----
func is_hostile() -> bool:
	return ai_enabled and state != S.IDLE and state != S.DEAD


func is_airborne() -> bool:
	return false


func is_downed() -> bool:
	return state == S.DOWN


func blade_hand() -> Vector3:
	return center()


func blade_tip() -> Vector3:
	return center() + Basis(Vector3.UP, _facing) * Vector3(0.0, 0.2, -1.0)


func begin_deathblow() -> void:
	pass


func deathblow_hit(_dir: Vector3) -> void:
	pass


## 打主角：空战走 AirMelee，地面（仅搜打撤）走 PlayerMelee
func _hit_player(info: Dictionary) -> int:
	info["dmg"] = float(info.get("dmg", 6.0)) * dmg_mul
	if player.st == Player.St.GROUND and raid:
		return player.melee.receive_attack(self, info)
	return player.air.receive_attack(self, info)


func is_beaming() -> bool:
	return state == S.BEAM or state == S.CLASH


## 光柱的出波点（双掌前）
func beam_origin() -> Vector3:
	return center() + _beam_dir * 0.95 + Vector3.UP * 0.2


## 对波时每秒把交汇点往主角那边顶多少（全程为 1）
func clash_power() -> float:
	return 0.2 if pro else 0.13


func velocity() -> Vector3:
	return _vel


func center() -> Vector3:
	return global_position + Vector3(0.0, BODY_Y, 0.0)


func aim_point() -> Vector3:
	return center()


func chip_colors() -> Array:
	return hero.chip_colors()


func hp_ratio() -> float:
	return hp / hp_max


func posture_ratio() -> float:
	return 0.0


func state_name() -> String:
	match state:
		S.WINDUP:
			return "蓄势·重击" if _heavy else "蓄势"
		S.STRIKE:
			return "出手"
		S.SHOOT:
			return "剑气"
		S.GUARD:
			return "护体"
		S.STUN:
			return "硬直"
		S.BLOWN:
			return "击飞"
		S.DOWN:
			return "坠地"
		S.RECOVER:
			return "破绽"
		S.DEAD:
			return "溃散"
		S.BEAM:
			return "光柱"
		S.CLASH:
			return "对波"
	return "悬停" if not ai_enabled else "对峙"


func _enter(s: S, dur := 0.0) -> void:
	if (state == S.BEAM or state == S.CLASH) and s != S.BEAM and s != S.CLASH:
		_end_beam()
	state = s
	_t = 0.0
	_dur = dur


## 演示用：回到原位、满血、清掉动量
func demo_reset(pos: Vector3) -> void:
	home = pos
	global_position = pos
	hp = hp_max
	_vel = Vector3.ZERO
	_doomed = false
	_tumble = 0.0
	_pitch = 0.0
	visual.visible = true
	_bar.visible = true
	_tag.visible = true
	_trail.emitting = false
	_enter(S.IDLE)
	rig.play("f_idle")


## 演示用：立刻起手一下（heavy：红光重击）
func force_attack(heavy: bool) -> void:
	_string = 1
	_begin_windup(0.42, heavy)


# ---------- 受击 ----------

func _frontal(dir: Vector3) -> bool:
	var f := Basis(Vector3.UP, _facing) * Vector3.FORWARD
	return f.dot(Vector3(dir.x, 0.0, dir.z).normalized()) < 0.2


func _refresh_tag() -> void:
	if roam and _tag != null:
		_tag.modulate = Color(1.0, 0.45, 0.4) if hostile else Color(0.85, 1.0, 0.9)


## 被怪打中（游荡刷怪时）：掉点血做做样子，不会被怪打死
func mob_hit(dmg: float, _dir: Vector3) -> void:
	if state == S.DEAD:
		return
	hp = maxf(hp - dmg * 0.25, hp_max * 0.2)
	_flash = 0.7


func _take(dmg: float, dir: Vector3, heavy: bool) -> void:
	if dmg_in.is_valid():
		dmg = float(dmg_in.call(dmg))
	if roam and not hostile:
		hostile = true
		_refresh_tag()
	_prey = null
	hp = maxf(hp - dmg, 0.0)
	_flash = 1.0
	_shake = 0.1
	_death_dir = dir
	Vfx.damage_number(center() + Vector3(0, 0.9, 0), dmg, Color(1.0, 0.85, 0.5) if heavy else Color.WHITE)


func air_hit(_attacker: Node3D, info: Dictionary) -> int:
	if state == S.DEAD:
		return -1
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var heavy: bool = info.get("heavy", false)
	var launch: String = info.get("launch", "")
	var kb: float = info.get("kb", 3.0)
	# 真人式：还没被打住时，有几率瞬身绕到主角背后反打
	if pro and ai_enabled and launch == "" and _vanish_cd <= 0.0 and (state == S.IDLE or state == S.CHASE) and randf() < 0.3:
		_vanish_behind()
		return -1
	if state == S.GUARD and _frontal(dir) and launch == "":
		_vel = dir * 2.5
		_t = maxf(_t - 0.25, 0.0)  # 被压着打：护体再撑一会儿
		return 1
	var broke := state == S.GUARD
	_take(float(info.get("dmg", 10.0)), dir, heavy)
	if launch != "":
		_launch(dir * kb)
		if hp <= 0.0:
			_doomed = true
		return 2 if broke else 0
	if hp <= 0.0:
		_die(info.get("contact", center()) as Vector3)
		return 0
	if state == S.DOWN:
		_dur += 0.15
		return 0
	_enter(S.STUN, float(info.get("stun", 0.45)) + (0.5 if broke else 0.0))
	_vel = dir * kb
	_alt = not _alt
	rig.snap(Poses.lerp_pose(rig.cur, Poses.get_pose("f_hurt2" if _alt else "f_hurt"), 0.75),
			[[0.05, Poses.get_pose("f_hurt2" if _alt else "f_hurt"), 1]])
	return 2 if broke else 0


## 飞剑 / 法术打中
func receive_hit(_attacker: Node3D, info: Dictionary) -> int:
	if state == S.DEAD:
		return -1
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var heavy: bool = info.get("heavy", false)
	if state == S.GUARD and _frontal(dir) and not heavy:
		return 1
	_take(float(info.get("dmg", 10.0)), dir, heavy)
	if hp <= 0.0:
		if state == S.BLOWN:
			_doomed = true
		else:
			_die(center())
		return 0
	if state == S.BLOWN or state == S.DOWN or state == S.RISE:
		return 0
	var kb: float = info.get("kb", 1.5)
	if state == S.STUN:
		_dur = maxf(_dur, _t + 0.22)
		_vel += dir * kb * 0.5
	else:
		_enter(S.STUN, 0.32 if heavy else 0.22)
		_vel = dir * kb
		_alt = not _alt
		rig.play("f_hurt2" if _alt else "f_hurt")
	return 0


## 瞬身到主角背后，紧接着起手两下
func _vanish_behind() -> void:
	_vanish_cd = randf_range(5.0, 8.0)
	var pc := player.center()
	var away := pc - center()
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 1e-4 else Vector3.FORWARD
	Vfx.vanish(center(), qi)
	var old := center()
	global_position = pc + away * 1.8 - Vector3(0.0, BODY_Y, 0.0)
	global_position.y = maxf(global_position.y, 0.0)
	Vfx.warp_line(old, center(), qi)
	_facing = atan2(away.x, away.z)
	_vel = Vector3.ZERO
	Sfx.play("warp", -4.0, 1.1)
	_string = 2
	_ci = 0
	_begin_windup(0.24, false)


## 主角开始蓄光柱：真人式对手大概率回一道，进入对波
func on_beam_incoming(_p: Node3D) -> void:
	if not pro or not ai_enabled or _beam_cd > 3.0:
		return
	if state == S.IDLE or state == S.CHASE or state == S.RECOVER or state == S.SHOOT or state == S.GUARD:
		if randf() < 0.8:
			_start_beam(0.38)


func _start_beam(wind: float) -> void:
	_enter(S.BEAM, wind + 1.1)
	_beam_wind = wind
	_beam_fired = false
	_beam_tick = 0.0
	_beam_cd = randf_range(10.0, 14.0)
	_vel = Vector3.ZERO
	_aim_beam(1.0)
	rig.play("f_beam_w")
	Vfx.cast_charge(center() + _beam_dir * 0.6, qi, wind)
	Sfx.play("ascend", -9.0, 1.4)


func _aim_beam(k: float) -> void:
	if player == null:
		return
	var d := player.center() - (center() + Vector3.UP * 0.2)
	if d.length_squared() < 0.25:
		return
	_beam_dir = _beam_dir.slerp(d.normalized(), clampf(k, 0.0, 1.0)).normalized()
	_facing = atan2(-_beam_dir.x, -_beam_dir.z)


func _make_beam() -> void:
	if is_instance_valid(_beam):
		return
	_beam_fired = true
	rig.play("f_beam")
	_beam = AirBeam.new()
	_beam.color = qi
	Vfx.root.add_child(_beam)
	Vfx.shockwave(beam_origin(), _beam_dir, qi, 1.4)
	Sfx.play("slam", -4.0, 1.3)


func _end_beam() -> void:
	if is_instance_valid(_beam):
		_beam.fade_out()
	_beam = null


## 对波开始（air_melee.gd 调）：光柱顶到交汇点，定在原地
func clash_begin() -> void:
	_aim_beam(1.0)
	_make_beam()
	_enter(S.CLASH, 99.0)
	_vel = Vector3.ZERO


## 对波结束：赢了收招喘口气；输了随后会被主角的 air_hit 轰飞
func clash_end(player_won: bool) -> void:
	_end_beam()
	if not player_won:
		_enter(S.RECOVER, 1.0)
		rig.play("f_idle")


func _tick_beam(dt: float) -> void:
	if not _beam_fired:
		_aim_beam(1.0)
		if _t >= _beam_wind:
			_make_beam()
			if player.air.foe_beam_fired(self):
				return
		return
	_aim_beam(1.4 * dt)
	var from := beam_origin()
	var far := from + _beam_dir * 70.0
	var q := PhysicsRayQueryParameters3D.create(from, far, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		far = hit["position"]
	if is_instance_valid(_beam):
		_beam.place(from, far)
	var last := _t >= _dur
	_beam_tick -= dt
	if _beam_tick <= 0.0 or last:
		_beam_tick = 0.12
		var pc := player.center()
		var cl := Geometry3D.get_closest_point_to_segment(pc, from, far)
		if cl.distance_to(pc) < 1.5:
			var res: int = _hit_player({"dmg": 12.0 if last else 4.0, "heavy": last,
					"kb": 28.0 if last else 5.0, "dir": (_beam_dir + Vector3.UP * 0.1).normalized(), "contact": pc, "ranged": true})
			if res >= 0:
				Vfx.hit(pc, _beam_dir, qi, 1.0)
	if last:
		_enter(S.RECOVER, 0.9)
		rig.play("f_idle")


## 被主角瞬身闪到背后：这一下打空，露出破绽
func on_vanished() -> void:
	if state == S.DEAD or state == S.BLOWN:
		return
	_enter(S.RECOVER, 1.0)
	_string = 0
	_vel = Vector3.ZERO


func _launch(v: Vector3) -> void:
	_enter(S.BLOWN, 1.7)
	_vel = v
	_crashed = false
	_tumble_v = 13.0 if v.y > -0.5 * v.length() else 0.0
	rig.snap(Poses.lerp_pose(rig.cur, Poses.get_pose("f_blown"), 0.8), [[0.06, Poses.get_pose("f_blown"), 1]])
	_trail.clear()
	_trail.emitting = true


func _die(hit: Vector3) -> void:
	_enter(S.DEAD, RESPAWN)
	_trail.emitting = false
	_vel = Vector3.ZERO
	Vfx.shatter(visual, hit, _death_dir, Color.WHITE.lerp(QI, 0.6), 1.2)
	Vfx.ribbon_burst(hit, Vector3.UP, QI, 10, 8.0, 170.0, 0.45)
	Sfx.play("execute", -4.0, 1.1)
	visual.visible = false
	_bar.visible = false
	_tag.visible = false
	if player != null and player.melee != null:
		player.melee.combat_event.emit("air_kill", {"pos": hit})
	died.emit(self)


func _respawn() -> void:
	global_position = home
	hp = hp_max
	_doomed = false
	_tumble = 0.0
	_pitch = 0.0
	_vel = Vector3.ZERO
	visual.visible = true
	_bar.visible = true
	_tag.visible = true
	_enter(S.IDLE)
	rig.play("f_idle")
	_cd = 2.0
	Vfx.reappear(center(), QI)


## 撞上场景：地面 / 台面砸坑倒地，墙柱弹开
func _crash(pos: Vector3, normal: Vector3) -> void:
	var spd := _vel.length()
	var ground := normal.y > 0.6
	global_position = pos + normal * 0.05
	if spd < CRASH_MIN:
		_vel = _vel.bounce(normal) * 0.3
		if ground:
			_vel.y = maxf(_vel.y, 1.5)
		return
	var power := clampf(spd / 34.0, 0.7, 1.6)
	var dmg := 26.0 * power * (1.0 + 0.012 * float(player.realm["dmg"])) if player != null else 26.0
	_take(dmg, -normal, true)
	Combat.hitstop(0.09, 0.0)
	Sfx.play("slam", -1.0, 0.8)
	Sfx.play("thud", -2.0, 0.6)
	if ground:
		Vfx.dun_slam(pos, QI.lerp(Color.WHITE, 0.5), power)
		Vfx.crater(pos, power)
	else:
		Vfx.impact(pos, normal.cross(Vector3.UP), Color.WHITE, 4)
		Vfx.wall_crash(pos, normal, power)
	if player != null and player.air != null:
		player.air.on_crash(self, pos, spd, ground)
	_trail.emitting = false
	if hp <= 0.0 or _doomed:
		_die(pos + Vector3.UP * 0.5)
		return
	if ground:
		_enter(S.DOWN, 1.0)
		_vel = Vector3.ZERO
		_tumble_v = 0.0
		_crashed = true
	else:
		_vel = _vel.bounce(normal) * 0.28
		_dur = minf(_dur, _t + 0.5)


# ---------- 每帧 ----------

func _process(dt: float) -> void:
	var cdt := Combat.cdt(dt)
	_t += cdt
	_cd -= cdt
	_shoot_cd -= cdt
	_beam_cd -= cdt
	_vanish_cd -= cdt
	if _chase_at >= 0.0:
		_chase_at -= cdt
		if _chase_at < 0.0:
			_chase_strike()
	_tick_bolts(dt)
	if state == S.DEAD:
		if _t >= _dur:
			if raid:
				queue_free()
			else:
				_respawn()
		return
	var pc := player.center() if player != null else center() + Vector3.FORWARD
	var to := pc - center()
	var dist := to.length()
	var flat := Vector3(to.x, 0.0, to.z)
	var want_yaw := atan2(-flat.x, -flat.z) if flat.length_squared() > 0.01 else _facing
	var in_air := player != null and (player.st == Player.St.AIR or (raid and player.st == Player.St.GROUND))
	var turn := 0.0
	var want_pitch := 0.0

	match state:
		S.BEAM:
			_tick_beam(dt)
		S.CLASH:
			_aim_beam(1.0)
			if is_instance_valid(_beam) and player != null:
				_beam.head_k = 1.7
				_beam.place(beam_origin(), player.air.clash_point())
			if player == null or not player.air.in_clash():
				_enter(S.RECOVER, 0.6)
				rig.play("f_idle")
		S.IDLE:
			if roam:
				want_yaw = _tick_roam(cdt, want_yaw)
				turn = 7.0
				if ai_enabled and hostile and in_air and dist < AGGRO and not player.dun_active 						and (not engage_ok.is_valid() or bool(engage_ok.call(self))):
					_prey = null
					home = global_position
					_enter(S.CHASE)
					rig.play("f_idle")
					_guard_roll = false
			else:
				var bob := home + Vector3(0.0, sin(Time.get_ticks_msec() * 0.0012 + home.x) * 0.5, 0.0)
				_vel = (bob - global_position).limit_length(1.0) * 4.0
				if global_position.distance_to(home) > 3.0:
					_vel = (home - global_position).normalized() * FLY_SPD
				if dist < 30.0:
					turn = 5.0
				if ai_enabled and in_air and dist < AGGRO and global_position.distance_to(home) < 4.0:
					_enter(S.CHASE)
					_guard_roll = false
		S.CHASE:
			turn = 8.0
			if roam:
				home = global_position
			if not in_air or dist > AGGRO * 1.4 or global_position.distance_to(home) > LEASH:
				_enter(S.IDLE)
			else:
				_tick_chase(to, dist)
		S.WINDUP:
			turn = 10.0
			_vel = _vel.move_toward(Vector3.ZERO, 40.0 * cdt)
			if _t >= _dur:
				_start_strike(to, dist)
		S.STRIKE:
			turn = 4.0
			if not _hit_done and _t >= _hit_t:
				_hit_done = true
				_resolve_strike(dist)
			if _t >= _hit_t:
				_vel = _vel.move_toward(Vector3.ZERO, 120.0 * cdt)
			if _t >= _dur and state == S.STRIKE:
				_string -= 1
				if _string > 0 and dist < 7.0:
					_begin_windup(0.12 if pro else 0.2, _string == 1 and (pro or randf() < 0.5))
				else:
					_enter(S.RECOVER, 0.85)
					rig.play("f_idle")
					_cd = randf_range(1.4, 2.2)
		S.RECOVER:
			_vel = _vel.move_toward(Vector3.ZERO, 30.0 * cdt)
			if _t >= _dur:
				_enter(S.CHASE if ai_enabled else S.IDLE)
				rig.play("f_idle")
		S.SHOOT:
			turn = 10.0
			_vel = _vel.move_toward(Vector3.ZERO, 30.0 * cdt)
			if _shots > 0 and _t >= 0.35 + 0.22 * float(3 - _shots):
				_shots -= 1
				_fire_bolt(pc)
			if _t >= _dur:
				_enter(S.CHASE)
				rig.play("f_idle")
		S.GUARD:
			turn = 10.0
			_vel = _vel.move_toward(Vector3.ZERO, 20.0 * cdt)
			if _t >= _dur:
				_enter(S.CHASE if ai_enabled else S.IDLE)
				rig.play("f_idle")
		S.STUN:
			_vel = _vel.move_toward(Vector3.ZERO, maxf(_vel.length() * 5.0, 6.0) * cdt)
			if _t >= _dur:
				_enter(S.CHASE if ai_enabled and in_air else S.IDLE)
				rig.play("f_idle")
				_cd = maxf(_cd, 0.5)
		S.BLOWN:
			_tick_blown(cdt)
		S.DOWN:
			want_pitch = -1.45
			if _t >= _dur:
				_enter(S.RISE, 0.55)
				rig.play("f_idle")
				Vfx.takeoff_burst(global_position, QI, 0.5)
		S.RISE:
			var up_to := maxf(home.y, global_position.y + 4.0) if global_position.y < 3.0 else global_position.y
			_vel = Vector3(0.0, clampf((up_to - global_position.y) * 4.0, 0.0, 14.0), 0.0)
			if _t >= _dur:
				_enter(S.CHASE if ai_enabled and in_air else S.IDLE)
				_cd = 0.8

	if not Combat.frozen():
		global_position += _vel * cdt
	var fy := float(floor_fn.call(global_position.x, global_position.z)) if floor_fn.is_valid() else 0.0
	if global_position.y < fy and state != S.BLOWN:
		global_position.y = fy
	if turn > 0.0:
		_facing = lerp_angle(_facing, want_yaw, 1.0 - exp(-turn * cdt))
	visual.rotation.y = _facing

	# 整身姿态：招式里的俯仰 / 自转 + 击飞翻滚 + 倒地平躺
	if state == S.BLOWN:
		_tumble += _tumble_v * cdt
		if _tumble_v == 0.0:
			want_pitch = -1.2
	elif state != S.DOWN:
		_tumble = lerp_angle(_tumble, 0.0, 1.0 - exp(-14.0 * cdt))
	_pitch = lerpf(_pitch, want_pitch, 1.0 - exp(-16.0 * cdt))
	var p := rig.cur
	spin.rotation = Vector3(-float(p["bp"]) + _pitch - _tumble, float(p["by"]), float(p["br"]))
	if state == S.DOWN:
		spin.position.y = lerpf(spin.position.y, 0.3, 1.0 - exp(-20.0 * cdt))
	else:
		spin.position.y = lerpf(spin.position.y, BODY_Y, 1.0 - exp(-10.0 * cdt))

	hero.stream_add = clampf(_vel.length() / 20.0, 0.0, 1.0)
	hero.animate(cdt, 0.0, 0.0, false, true)
	rig.update(cdt)
	rig.apply(cdt)
	_flash = maxf(_flash - dt * 7.0, 0.0)
	hero.set_flash(_flash)
	if _shake > 0.0:
		_shake -= minf(dt, Combat.MAX_DT)
		visual.position = Vector3(randf_range(-0.05, 0.05), 0.0, randf_range(-0.05, 0.05))
	else:
		visual.position = Vector3.ZERO
	_bar.scale.x = maxf(hp / hp_max, 0.001)
	_trail.time_scale = Combat.time_scale()


## 游荡：有怪就飞过去打（招式用主角那套连段），没怪就在主角周围 / 自己附近换地方转。返回想朝向的角度。
func _tick_roam(cdt: float, yaw: float) -> float:
	_roam_t -= cdt
	_prey_cd -= cdt
	_swing_cd -= cdt
	if _prey != null and not (is_instance_valid(_prey) and bool(_prey.call("is_alive"))):
		_prey = null
	if _prey == null and _prey_cd <= 0.0 and prey_fn.is_valid():
		_prey_cd = 1.2
		_prey = prey_fn.call(self)
	if _swung and _swing_cd <= 0.22:
		_swung = false
		rig.play("f_idle")
	if _prey != null:
		var pc: Vector3 = _prey.call("center")
		var to := pc - center()
		var d := to.length() - float(_prey.call("hit_radius"))
		yaw = atan2(-to.x, -to.z)
		if d > 2.3:
			_vel = _vel.move_toward(to.normalized() * minf(FLY_SPD, (d - 1.6) * 4.0 + 3.0), 50.0 * cdt)
		else:
			_vel = _vel.move_toward(Vector3.ZERO, 50.0 * cdt)
			if _swing_cd <= 0.0:
				_swing_cd = 0.5
				_swung = true
				rig.play(["f1", "f2", "f3", "f4"][_ci % 4])
				_ci += 1
				var dir := to.normalized()
				var near := player != null and player.global_position.distance_to(global_position) < 70.0
				if near:
					Vfx.hit(pc, dir, qi, 0.7)
					Sfx.play("swing", -14.0, 1.1)
				_prey.call("sim_damage", prey_dmg, dir, self)
		return yaw
	var p := global_position
	var to2 := _roam_to - p
	if _roam_t <= 0.0 or to2.length() < 2.0:
		_roam_t = randf_range(4.0, 9.0)
		var a := randf() * TAU
		var c := p
		var rr := randf_range(25.0, 60.0)
		if player != null and randf() < 0.55:
			c = player.global_position
			rr = randf_range(18.0, 50.0)
		_roam_to = c + Vector3(cos(a), 0.0, sin(a)) * rr
		var fy := float(floor_fn.call(_roam_to.x, _roam_to.z)) if floor_fn.is_valid() else 0.0
		_roam_to.y = fy + 1.4
		to2 = _roam_to - p
	_vel = _vel.move_toward(to2.normalized() * 7.5, 20.0 * cdt)
	if Vector2(to2.x, to2.z).length() > 1.0:
		yaw = atan2(-to2.x, -to2.z)
	return yaw


func _tick_chase(to: Vector3, dist: float) -> void:
	# 主角正冲过来：掷一次骰子决定要不要护体硬接
	var rushing: bool = player.air.rushing_at(self)
	if rushing and not _guard_roll:
		_guard_roll = true
		if randf() < 0.3:
			_enter(S.GUARD, 1.0)
			rig.play("f_guard")
			return
	elif not rushing:
		_guard_roll = false
	if pro and dist > 10.0 and dist < 45.0 and _beam_cd <= 0.0:
		_start_beam(0.6)
		return
	if dist > 11.0 and dist < 34.0 and _shoot_cd <= 0.0:
		_shoot_cd = randf_range(5.0, 8.0)
		_shots = 3
		_enter(S.SHOOT, 1.25)
		rig.play("f_point", 0.4)
		Vfx.cast_charge(center() + Vector3.UP * 0.4, QI, 0.3)
		return
	if dist > 2.3:
		# 贴上去：和主角拉平高度，绕着一点切进来
		var dir := to.normalized()
		var side := dir.cross(Vector3.UP)
		side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
		var want := (dir + side * 0.25 * sin(Time.get_ticks_msec() * 0.0015)).normalized() * FLY_SPD
		_vel = _vel.move_toward(want * clampf((dist - 1.8) / 3.0, 0.25, 1.0), 40.0 * Combat.cdt(get_process_delta_time()))
	else:
		_vel = _vel.move_toward(Vector3.ZERO, 50.0 * Combat.cdt(get_process_delta_time()))
	if dist < 3.2 and _cd <= 0.0:
		_string = 5 if pro else randi_range(2, 3)
		_ci = 0
		_begin_windup(0.36 if pro else 0.42, false)


func _begin_windup(dur: float, heavy: bool) -> void:
	_heavy = heavy
	_enter(S.WINDUP, dur + (0.3 if heavy else 0.0))
	var w := "f_chg" if heavy else ("f2_w" if _alt else "f1_w")
	rig.play_keys([[minf(dur, 0.16), Poses.get_pose(w), 2]])
	# 出手前的一点寒光：重击是红的（挡不住，只能闪）
	Vfx.glint(rig.hand_pos() if not _alt or heavy else rig.left_hand_pos(), Color(1.0, 0.25, 0.2) if heavy else Color(1.0, 0.9, 0.8),
			1.3 if heavy else 0.8)
	if heavy:
		Sfx.play("swing_heavy", -8.0, 0.7)


func _start_strike(to: Vector3, dist: float) -> void:
	_enter(S.STRIKE, 0.34)
	_hit_done = false
	_hit_t = 0.085
	var seq := "f_sm" if _heavy else ("f2" if _alt else "f1")
	_alt = not _alt
	if pro and not _heavy:
		# 真人式连段：冲拳 → 摆拳 → 蹬踢 → 回旋踢，用的就是主角那套招
		seq = ["f1", "f2", "f3", "f4"][_ci % 4]
		_hit_t = [0.085, 0.085, 0.1, 0.14][_ci % 4]
		_dur = _hit_t + 0.2
		_ci += 1
		rig.play(seq)
	elif _heavy:
		rig.play(seq)
	else:
		rig.play_keys([[0.085, Poses.get_pose(seq + "_m"), 3]])
	# 踏空一步贴到身前
	var go := clampf(dist - 1.5, 0.0, 6.0 if _heavy else 4.0)
	_vel = to.normalized() * (go / 0.085)
	Sfx.play("swing_heavy" if _heavy else "swing", -7.0, 0.9)


func _resolve_strike(dist: float) -> void:
	if player == null or dist > STRIKE_R + 0.8:
		return
	var dir := player.center() - center()
	dir = dir.normalized() if dir.length_squared() > 1e-4 else Basis(Vector3.UP, _facing) * Vector3.FORWARD
	var kd := dir
	if _strike_dir != Vector3.ZERO:
		kd = _strike_dir
		_strike_dir = Vector3.ZERO
	elif _heavy and pro:
		# 重击收尾：前 / 上 两种去向
		kd = (dir + Vector3.UP * (0.9 if randf() < 0.45 else 0.15)).normalized()
	var res: int = _hit_player({"dmg": 15.0 if _heavy else (5.0 if pro else 7.0), "heavy": _heavy,
			"kb": 26.0 if _heavy else 6.0, "dir": kd, "contact": center() + dir * 0.9})
	if res == 1:
		_vel = -dir * 3.0
	elif res == 0 and _heavy and pro and kd.y > -0.5 and randf() < 0.75:
		_chase_at = 0.3  # 把人打飞了：瞬身追上去往下砸
	elif res == 0 and _heavy:
		Vfx.shockwave(center() + dir * 0.9, kd, qi, 1.6)


## 瞬身追击：出现在被击飞的主角上方，一记下砸把人砸向地面
func _chase_strike() -> void:
	if player == null or state == S.DEAD or state == S.BLOWN or state == S.STUN or not player.air.is_blown():
		return
	var pc := player.center()
	Vfx.vanish(center(), qi)
	var old := center()
	global_position = pc + Vector3(0.0, 1.7 - BODY_Y, 0.0) + player.velocity * 0.08
	Vfx.warp_line(old, center(), qi)
	Sfx.play("warp", -4.0, 0.9)
	_heavy = true
	_string = 1
	_enter(S.STRIKE, 0.5)
	_hit_done = false
	_hit_t = 0.12
	_strike_dir = Vector3(0.0, -1.0, 0.0)
	var flat := pc - old
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		_strike_dir = (flat.normalized() * 0.25 + Vector3.DOWN).normalized()
	rig.play("f_dn")
	_vel = Vector3.ZERO
	Sfx.play("swing_heavy", -5.0, 0.8)


func _fire_bolt(pc: Vector3) -> void:
	var from := center() + Basis(Vector3.UP, _facing) * Vector3(0.3, 0.35, -0.7)
	var lead := pc + (player.velocity * 0.25 if player != null else Vector3.ZERO)
	var d := (lead - from).normalized()
	var mi := Vfx.persistent_sprite(QI, 2)
	_bolts.append([mi, from, d * BOLT_SPD, 2.2])
	Vfx.cast_flash(from, QI, 0.7)
	Sfx.play("swing", -8.0, 1.5)
	rig.play("f_point")


func _tick_bolts(dt: float) -> void:
	var i := _bolts.size() - 1
	while i >= 0:
		var b: Array = _bolts[i]
		var mi := b[0] as MeshInstance3D
		var pos: Vector3 = b[1]
		var v: Vector3 = b[2]
		var life: float = float(b[3]) - dt
		var np := pos + v * dt
		var done := life <= 0.0
		if not done and player != null and player.st == Player.St.AIR:
			var c := player.center()
			var cl := Geometry3D.get_closest_point_to_segment(c, pos, np)
			if cl.distance_to(c) < 0.9:
				var res: int = _hit_player({"dmg": 6.0, "heavy": false, "kb": 4.0,
						"dir": v.normalized(), "contact": cl, "ranged": true})
				if res != -1:
					Vfx.hit(cl, v.normalized(), QI, 0.8)
					done = true
		if done:
			mi.queue_free()
			_bolts.remove_at(i)
		else:
			b[1] = np
			b[3] = life
			Vfx.place_streak(mi, np, v.normalized(), 1.6, 0.22)
		i -= 1


func _tick_blown(cdt: float) -> void:
	if cdt <= 0.0:
		return
	_vel -= _vel * BLOWN_DRAG * cdt
	_vel.y -= BLOWN_G * cdt
	# 沿这一帧的位移打射线：撞到场景就砸上去
	var from := center()
	var step := _vel * cdt
	var q := PhysicsRayQueryParameters3D.create(from, from + step + step.normalized() * 0.5, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_crash((hit["position"] as Vector3) - Vector3(0.0, BODY_Y * 0.3, 0.0), hit["normal"] as Vector3)
		return
	var fy := float(floor_fn.call(global_position.x, global_position.z)) if floor_fn.is_valid() else 0.0
	if global_position.y + step.y <= fy:
		_crash(Vector3(global_position.x, fy, global_position.z), Vector3.UP)
		return
	if _t >= _dur or _vel.length() < 7.0:
		_trail.emitting = false
		if _doomed:
			_die(center())
			return
		_enter(S.RISE, 0.35)
		_vel *= 0.3
		rig.play("f_idle")
