extends Node
## 空战斗法（结丹起，空战状态下）：近身拳脚 + 飞剑随击 + 重击击飞 + 瞬身追击，飞剑 / 法术改成技能键。
##
## · 攻击（J / 左键）点按：五段追身连击 —— 冲拳 → 摆拳 → 蹬踢 → 回旋踢 → 掣剑横斩（把人斩飞）。
##   每一段出手都会吸附到目标身前；目标在 RUSH_R 内而不在身边时，先「追身突进」冲过去再打。
##   每一拳命中后，身后的飞剑紧跟着刺进同一个目标（剑随拳走），连击不断、灵力回涨。
## · 攻击长按：蓄力重击。松手时按方向决定去向 —— 默认「崩拳」向前击飞；按住空格「挑飞」向上；按住 S「陨落」向下砸。
## · 目标被击飞时再按攻击：「瞬身追击」—— 瞬移到它飞行路线的前头再补一记重击（最多 CHASE_MAX 次，每次耗一点灵力），
##   默认顺序 前 → 上 → 下，最后一记把人砸进地面；从高处砸下时镜头切到落点旁的低机位看它坠地。
## · 格挡（K / 右键）按住：护体罡气，正面受击只掉一点血、耗灵力；刚按下的 PERFECT 秒内被打中 = 「瞬身」闪到对手背后，
##   画面骤慢，对手露出破绽。
## · E 点按：飞剑点射（一柄追踪飞剑，耗少量灵力）；长按：万剑连发（air_caster.gd 的连发）。
## · Z / X / C：三式剑诀（即 air_caster.gd 里各境界的三段法术），各有灵力消耗和冷却；第三式出手时给一个特写镜头。
## · T：对波「剑罡」—— 蓄势后推出一道光柱，持续灼烧并在收束时把人轰飞。对手同时放光柱就进入「对波」相持：
##   连点攻击把交汇点往对面顶，顶到头就轰穿对手；被顶回来则自己被轰飞。镜头切到侧面看两道光柱相持。
## · V 按住：聚气 —— 快速回灵力、攒觉醒槽（拳脚命中 / 挨打也攒）。槽满后继续聚气 = 「觉醒」：气浪震开身边的对手，
##   十几秒内伤害提高、瞬身追击不耗灵力、飞剑对波顶得更狠。
## · 被重击打飞后砸到地面：砸出裂纹和碎石坑（Vfx.crater），倒地片刻再起身。
## · 被打：轻击硬直，重击被击飞翻滚（可以按 Shift 闪现受身）。气血用的是 PlayerMelee 的 hp。
##
## 由 Player 在 _process 里调 tick()（在 PlayerMelee.tick 之后），用的是 PlayerMelee 的 rig 和手中剑。
## 故意不写 class_name：用 preload 引用。

const Rig := preload("res://scripts/fighter_rig.gd")
const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const Proj := preload("res://scripts/spell_projectile.gd")

enum A { IDLE, RUSH, ATTACK, CHARGE, SMASH, GUARD, HURT, BLOWN, CLASH, GATHER, DOWN }

const HOLD_T := 0.24          # 攻击键按住超过这么久转入蓄力
const CHARGE_FULL := 0.7      # 蓄满用时
const CHARGE_MAX := 1.2       # 蓄满后最多再攒这么久就自动打出去
const BUFFER := 0.25
const RUSH_R := 36.0          # 这么远内按攻击会追身突进
const RUSH_SPD := 62.0
const STICK := 1.4            # 出手时与目标中心的间距（另加目标体型半径）
const MAGNET := 4.5           # 这么近不必突进，出招时直接吸过去
const BODY_Y := 1.05          # 贴身时让自己的胸口对齐目标中心：脚底比目标中心低这么多
const CHASE_MAX := 3
const CHASE_MP := 8.0
const GUARD_MP := 6.0
const PERFECT := 0.2
const COMBO_KEEP := 2.0
const SHOT_MP := 3.0
const SHOT_CD := 0.16
const HIT_MP := 2.5           # 每一下拳脚命中回的灵力
const REGEN_WAIT := 6.0       # 这么久没挨打，气血开始缓慢回复
const REGEN := 6.0
const ENGAGE_KEEP := 5.0      # 最后一次出手 / 受击后多久还算在交战（保持架势和镜头锁定）
const CLASH_TAP := 0.045      # 飞剑对波时每点一下攻击，把交汇点往对面顶这么多（全程为 1）
const CLASH_MIN_DIST := 7.0   # 两人至少隔这么远才对得起来
const CLASH_MP := 14.0        # 对波相持每秒耗的灵力；耗尽了交汇点就一路被顶回来
const CLASH_BLAST_R := 14.0   # 相持时每隔一会儿把交汇点这么远内的旁人震开
const WARN_MS := 1000.0       # 对手起手飞剑时的预警窗口（真实时间，毫秒）：这段时间里点「剑」/「攻击」就接下来对波
const WARP_BASE := 0.008      # 交汇点的空间扭曲强度：基础 + 每高一个境界再加一点（结丹约 0.016，化神 0.024，大乘 0.036）
const WARP_STEP := 0.004
const CLASH_MAX := 6.0        # 相持最久这么多秒，到点谁占优谁赢
const GATHER_MP := 45.0       # 聚气每秒回的灵力
const AWAKE_DUR := 14.0
const AWAKE_DMG := 1.3
const SKILL_KEYS := ["Z", "X", "C"]
const SKILL_COST := [0.1, 0.18, 0.32]   # 占灵力上限的比例
const SKILL_CD := [1.2, 3.5, 8.0]

## 连击表。时间为招式内战斗时间（秒）：hit 判定 | chain 最早接下一段 | end 收招
## dmg 伤害（× 境界 dmg）| kb 击退速度 | stun 对手硬直 | stop 顿帧 | limb 用哪儿打（rh/lh 拳 rf/lf 脚 sw 剑）
## swords 命中后跟上几柄飞剑 | launch 击飞方向
const ATK := [
	{"name": "冲拳", "seq": "f1", "hit": 0.085, "chain": 0.19, "end": 0.4, "dmg": 0.45, "kb": 3.0, "stun": 0.5,
	 "stop": 0.045, "limb": "rh", "tier": 0, "trauma": 0.16, "push": 0.03, "swords": 1},
	{"name": "摆拳", "seq": "f2", "hit": 0.085, "chain": 0.19, "end": 0.42, "dmg": 0.45, "kb": 3.0, "stun": 0.5,
	 "stop": 0.05, "limb": "lh", "tier": 0, "trauma": 0.18, "push": 0.03, "swords": 1},
	{"name": "蹬踢", "seq": "f3", "hit": 0.1, "chain": 0.22, "end": 0.46, "dmg": 0.6, "kb": 5.0, "stun": 0.55,
	 "stop": 0.06, "limb": "rf", "tier": 0, "trauma": 0.2, "push": 0.04, "swords": 1},
	{"name": "回旋踢", "seq": "f4", "hit": 0.14, "chain": 0.28, "end": 0.54, "dmg": 0.8, "kb": 7.0, "stun": 0.6,
	 "stop": 0.075, "limb": "lf", "tier": 1, "trauma": 0.26, "push": 0.05, "swords": 2},
	{"name": "掣剑横斩", "seq": "f5", "hit": 0.135, "chain": 99.0, "end": 0.6, "dmg": 1.3, "kb": 27.0, "stun": 0.9,
	 "stop": 0.11, "limb": "sw", "tier": 1, "trauma": 0.38, "push": 0.08, "swords": 3, "launch": "fwd"},
]
## 重击三式：hit 判定时刻 | end 收招 | spd 击飞速度
const SMASH := {
	"fwd": {"name": "崩拳", "seq": "f_sm", "hit": 0.055, "end": 0.5, "limb": "rh", "spd": 42.0},
	"up": {"name": "挑飞", "seq": "f_up", "hit": 0.11, "end": 0.56, "limb": "rf", "spd": 36.0},
	"down": {"name": "陨落", "seq": "f_dn", "hit": 0.12, "end": 0.56, "limb": "rh", "spd": 50.0},
}

var player: Player
var rig: Rig
var state := A.IDLE
var step := 0
var target: Node3D = null
var drive_vel := Vector3.ZERO
var has_face := false
var face_yaw := 0.0
var guard_held := false
var combo := 0                # 连击数（拳脚 + 飞剑都算）
var combo_dmg := 0.0
var cds: Array[float] = [0.0, 0.0, 0.0]

var _t := 0.0
var _clock := 0.0
var _drives := false
var _atk: Dictionary = ATK[0]
var _hit_done := false
var _queued := false
var _whiff := false
var _buf_at := -10.0
var _held := 0.0              # 攻击键已按住的时长
var _hold_used := false       # 这次按住已经放过一记重击：松手前不再蓄
var _last_step := -1
var _last_end := -10.0
var _charge := 0.0
var _auto_release := -1.0     # 演示用：蓄到这么久自动松手
var _smash_kind := "fwd"
var _smash_k := 0.0
var _sm_dash := false
var _chase := false           # 这一记重击是瞬身追击
var _chase_n := 0
var _launched: Node3D = null  # 刚被击飞、可以追击的目标
var _launch_kind := ""
var _guard_at := -10.0
var _push := Vector3.ZERO
var _dur := 0.0
var _tumble := 0.0
var _iframe := 0.0
var _flash := 0.0
var _flash_on := false
var _combo_t := 0.0
var _shot_cd := 0.0
var _shot_held := 0.0
var _shot_n := 0
var _point_t := 0.0
var _engage := 0.0
var _ghost_t := 0.0
var _art_next := 0            # 「诀」下一次轮到第几式
const GUARD_GATHER_T := 0.7   # 护体按住这么久、又没人在打自己，就转入聚气
var _ground_frame := -1       # 这一帧是从地面按键升空进来的：同一个按键事件别再处理一遍
var _flurry_left := 0         # 乱舞还剩几下（合体 / 大乘的收尾）
var _flurry_cd := 0.0
var _flurry_n := 0
var _aura_t := 0.0
var _aim_pitch := 0.0
var _lock_node: Node3D = null
var _cine_t := -1.0           # 演出镜头已过时间，-1 = 没有
var _cine_dur := 0.0
var _cine_out := 0.25
var _cine_follow: Node3D = null
var _cine_eye := Vector3.ZERO
var _cine_wait_crash := false
var _stream := 0.0
var awaken := 0.0             # 觉醒槽 0~100
var awake_t := 0.0            # 觉醒剩余时间
var demo_mash := 0.0          # 演示用：对波时每秒自动点这么多下
var demo_gather := false      # 演示用：当作按住了聚气
var _beam_dir := Vector3.FORWARD     # 对波时自己 → 对手的方向
var _warn_foe: Node3D = null      # 正朝自己起手 / 连发飞剑的对手（预警、接波用）
var _warn_until := 0.0            # 预警窗口到什么时候（Time.get_ticks_msec）
## 联机对波（对手是别的玩家的木偶）：各自累计自己顶了多少（_clash_my），对方的从网络来（木偶的 clash_their），
## 交汇点 = 0.5 + 我顶的 − 他顶的；_clash_auth = 由我这边判胜负（发起的一方），否则等对方发结果（_clash_forced：1 赢 / -1 输）
var _clash_my := 0.0
var _clash_auth := true
var _clash_forced := 0
var _clash_blast := 0.0
var _clash_arc := 0.0
var _clash_ring := 0.0
var _clash_foe: Node3D = null
var _clash_u := 0.5
var _clash_t := 0.0
var _clash_fx := 0.0
var _lie := 0.0
var _cine_look := Vector3.ZERO
var _cine_use_look := false
var _since_hurt := 99.0


func _ready() -> void:
	rig = player.melee.rig


# ---------- 查询 ----------

func busy() -> bool:
	return state != A.IDLE


## 由招式接管位移（Player._air 直接用 drive_vel）
func drives() -> bool:
	return _drives


func move_mul() -> float:
	return 0.35 if state == A.GUARD else 1.0


func guarding() -> bool:
	return state == A.GUARD


## 交战中：保持凌空架势、镜头锁定
func engaged() -> bool:
	return state != A.IDLE or _engage > 0.0


func charge_k() -> float:
	return clampf(_charge / CHARGE_FULL, 0.0, 1.0) if state == A.CHARGE else 0.0


## 正朝 e 冲过去（对手据此决定要不要护体）
func rushing_at(e: Node3D) -> bool:
	return target == e and (state == A.RUSH or (state == A.SMASH and _sm_dash))


func can_blink() -> bool:
	return not (state == A.BLOWN and _t < 0.22) and state != A.CLASH and state != A.DOWN


func is_blown() -> bool:
	return state == A.BLOWN


func in_clash() -> bool:
	return state == A.CLASH


func clash_u() -> float:
	return _clash_u


func clash_point() -> Vector3:
	if is_instance_valid(_clash_foe):
		return _hand_point().lerp(_clash_foe.clash_origin(), _clash_u)
	return _hand_point()


## 倒地程度 0~1（Player 据此把身体放低贴到地面）
func lie_k() -> float:
	return _lie


## 对波时自己这一头（身前一点）
func _hand_point() -> Vector3:
	return player.center() + _beam_dir * 0.95 + Vector3.UP * 0.2


func state_name() -> String:
	match state:
		A.RUSH:
			return "追身突进"
		A.ATTACK:
			return _atk["name"]
		A.CHARGE:
			return "蓄力 %d%%" % int(charge_k() * 100.0)
		A.SMASH:
			return ("瞬身追击·" if _chase else "") + str(SMASH[_smash_kind]["name"])
		A.GUARD:
			return "护体罡气"
		A.HURT:
			return "受击"
		A.BLOWN:
			return "被击飞"
		A.CLASH:
			return "飞剑对波"
		A.GATHER:
			return "聚气"
		A.DOWN:
			return "坠地"
	return "觉醒" if awake_t > 0.0 else ""


func skill_name(i: int) -> String:
	return (Realm.art_info(player.realm)["stages"] as Array)[i]


func skill_cost(i: int) -> float:
	return player.mp_max() * float(SKILL_COST[i])


func skill_ready(i: int) -> bool:
	return cds[i] <= 0.0 and player.mp >= skill_cost(i)


## 整身姿态（Player 设到 spin 节点上）：招式里的俯仰 / 自转 / 侧滚 + 朝目标的仰俯 + 被击飞的翻滚
func spin_euler() -> Vector3:
	var p := rig.cur
	var w := rig.w_leg
	return Vector3((-float(p["bp"]) + _aim_pitch) * w - _tumble + 1.45 * _lie, float(p["by"]) * w, float(p["br"]) * w)


func _col() -> Color:
	return Realm.line_color(player.realm)


func _base() -> float:
	return float(player.realm["dmg"]) * (AWAKE_DMG if awake_t > 0.0 else 1.0)


static func _now() -> float:
	return Combat.now()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _fwd() -> Vector3:
	return Basis(Vector3.UP, face_yaw) * Vector3.FORWARD


## t 可能是已经释放的节点（搜打撤的怪死后即释放），所以不标类型、先验有效
func _alive(t: Variant) -> bool:
	return is_instance_valid(t) and Proj.alive(t)


func _is_launched(t: Node3D) -> bool:
	return _alive(t) and t.has_method("is_launched") and t.is_launched()


func _gap(t: Node3D) -> float:
	return STICK + Proj.body_r(t)


# ---------- 输入 ----------

## 境界档位（空战从结丹起）：0 结丹 · 1 元婴 · 2 化神 · 3 炼虚 · 4 合体 · 5 大乘。档位越高连段越花：
##   元婴 每一下出手都拖残影
##   化神 连段第四下前瞬步绕到对手背后；重手带一道剑气弧光和漫画冲击帧
##   炼虚 追身突进变成缩地（直接闪到身前）；第三、四下前都瞬步换位；重手时分出一道分身从另一侧补一击
##   合体 每一下都瞬步换位；两道分身；重手撕开一道空间裂隙；收尾前先来四下乱舞（绕着对手连闪连斩）
##   大乘 三道分身；乱舞七下；收尾把人打飞后天上落一圈剑雨追击
func flair() -> int:
	return clampi(player.realm_idx - 2, 0, 5)


## 从地面按键直接升空进来（player_melee.gd 调）：attack = 攻击键，否则是格挡键
func press_from_ground(attack: bool) -> void:
	_ground_frame = Engine.get_process_frames()
	if attack:
		press_attack()
	else:
		press_guard()


func _unhandled_input(e: InputEvent) -> void:
	if player.st != Player.St.AIR:
		return
	if _ground_frame == Engine.get_process_frames() and (e.is_action_pressed("attack") or e.is_action_pressed("guard")):
		return  # 这个按键刚由地面那边转交过来处理过了
	if e is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return  # 这一下是用来抓鼠标的
	if player.ult.active and not e.is_action_released("guard"):
		return
	if e.is_action_pressed("attack"):
		press_attack()
	elif e.is_action_pressed("guard"):
		press_guard()
	elif e.is_action_released("guard"):
		release_guard()
	elif e.is_action_pressed("air_shot"):
		press_shot()
	elif e.is_action_pressed("skill_next"):
		press_art()


func press_attack() -> void:
	if player.st != Player.St.AIR or player.ult.active:
		return
	if state == A.CLASH:
		_clash_tap()
		return
	if warn_k() > 0.0 and _accept_clash():
		return
	_buf_at = _now()
	_hold_used = false
	if _consume():
		_buf_at = -10.0


func _consume() -> bool:
	if player.caster.channeling or player.is_dashing():
		return false
	match state:
		A.IDLE, A.GUARD:
			if _can_chase():
				_start_chase()
			else:
				_begin_combo()
			return true
		A.RUSH:
			return true
		A.ATTACK:
			if _hit_done and _can_chase():
				_start_chase()
				return true
			if step < ATK.size() - 1 and _t >= float(_atk["hit"]) - 0.04:
				_queued = true
				return true
		A.SMASH:
			if _hit_done and _can_chase():
				_start_chase()
				return true
	return false


func press_guard() -> void:
	guard_held = true
	if player.st != Player.St.AIR or player.is_dashing():
		return
	var ok := state == A.IDLE or state == A.RUSH
	if state == A.ATTACK:
		ok = _hit_done or _t < 0.04
	if not ok or player.caster.busy():
		return
	_end_blade()
	state = A.GUARD
	_t = 0.0
	_guard_at = _clock
	_engage = ENGAGE_KEEP
	rig.play("f_guard")
	Vfx.cast_flash(player.center() + _fwd() * 0.5, _col(), 0.8)


func release_guard() -> void:
	guard_held = false
	if state == A.GUARD:
		_to_idle()


## 护体一直按着、最近 1.5 秒没人打过自己：可以顺势聚气（一挨打就回到护体）
func _guard_gather() -> bool:
	if not guard_held or player.st != Player.St.AIR:
		return false
	if state != A.GUARD and state != A.GATHER:
		return false
	if _clock - _guard_at < GUARD_GATHER_T:
		return false
	var now := Combat.now()
	for k: Variant in player.threat.keys():
		if now - float(player.threat[k]) < 1.5:
			return false
	return true


## E 点按：一柄追踪飞剑
func press_shot() -> void:
	if _accept_clash():
		return
	if player.st != Player.St.AIR or player.is_dashing() or player.caster.busy():
		return
	if state == A.HURT or state == A.BLOWN or state == A.CHARGE or state == A.SMASH:
		return
	if _shot_cd > 0.0 or player.mp < SHOT_MP:
		return
	player.mp -= SHOT_MP
	player.caster.hold_regen()
	_shot_cd = SHOT_CD
	_shot_n += 1
	_engage = ENGAGE_KEEP
	var aim := _aim()
	var tgt: Node3D = aim[0]
	var pt: Vector3 = aim[1]
	if state == A.IDLE:
		var d := pt - player.global_position
		if _flat(d).length() > 0.2:
			face_yaw = atan2(-d.x, -d.z)
			has_face = true
		rig.play("f_point")
		_point_t = 0.3
	var side := -1.0 if _shot_n % 2 == 0 else 1.0
	var from := player.global_position + Basis(Vector3.UP, face_yaw) * Vector3(0.85 * side, randf_range(1.7, 2.2), 0.7)
	var art := Realm.art(player.realm)
	Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
			{"dmg": _base() * 0.4, "color": _col(), "speed": 78.0, "hold": 0.05, "turn": 12.0,
			 "straight": tgt == null, "art": art, "tw": 0.1, "trauma": 0.02, "life": 1.4})
	Vfx.cast_flash(from, _col(), 0.6)
	player.cam.add_trauma(0.02)


## Z / X / C：三式剑诀
## 「诀」这一下会放第几式：从轮到的那一式起，按顺序找第一个冷却好、灵力够的；都不行就还是轮到的那一式
func next_skill() -> int:
	for k in 3:
		var i := (_art_next + k) % 3
		if skill_ready(i):
			return i
	return _art_next


## 「诀」（Z）：三式剑诀合成一个键，每按一次按顺序放下一式（一 → 二 → 三 → 一 …），轮到的那式还在冷却就顺延
func press_art() -> void:
	var i := next_skill()
	if press_skill(i):
		_art_next = (i + 1) % 3


## 「诀」按钮上显示的冷却比例（0 = 可用）
func art_cd() -> float:
	var i := next_skill()
	return cds[i] / float(SKILL_CD[i])


func press_skill(i: int) -> bool:
	if player.st != Player.St.AIR or player.is_dashing() or player.caster.busy():
		return false
	if state == A.HURT or state == A.BLOWN or state == A.CHARGE or state == A.SMASH or state == A.RUSH:
		return false
	if state == A.ATTACK and not _hit_done:
		return false
	if not skill_ready(i):
		Sfx.play("block", -12.0, 0.7)
		return false
	player.mp -= skill_cost(i)
	cds[i] = float(SKILL_CD[i])
	_end_blade()
	state = A.IDLE
	_engage = ENGAGE_KEEP
	rig.play("f_idle")
	player.caster.cast_skill(i)
	player.melee.combat_event.emit("air_skill", {"idx": i, "name": skill_name(i)})
	if i == 2:
		_cine_skill()
	return true


## 演示 / 自检：直接蓄一记重击（kind：fwd / up / down），hold 秒后自动打出
func demo_heavy(kind: String, hold := 0.5) -> void:
	_smash_kind = kind
	_start_charge()
	_auto_release = hold


# ---------- 目标 ----------

## [目标或 null, 瞄准点]：交战中的目标优先，否则取准星附近的
func _aim() -> Array:
	if _alive(target):
		return [target, Proj.aim_of(target)]
	return player.caster._pick()


func _pick_target() -> Node3D:
	var cam := player.cam
	if _alive(cam.lock) and Proj.aim_of(cam.lock).distance_to(player.center()) <= RUSH_R + Proj.body_r(cam.lock):
		return cam.lock
	# 统一索敌：先找正在打我的，再找最近的
	return Proj.pick_target(player, RUSH_R, target)


## 目标身前的出手位置（脚底坐标）：沿 from_dir（自己 → 目标的水平方向）退开 gap，高度对齐
func _stick_point(t: Node3D, dir: Vector3) -> Vector3:
	var tc := Proj.aim_of(t)
	var p := tc - dir * _gap(t)
	p.y = maxf(p.y - BODY_Y, 0.0)
	return p


func _dir_to(t: Node3D) -> Vector3:
	var d := _flat(Proj.aim_of(t) - player.center())
	return d.normalized() if d.length_squared() > 0.01 else _fwd()


# ---------- 起手 ----------

func _begin_combo() -> void:
	target = _pick_target()
	_engage = ENGAGE_KEEP
	var s := 0
	if _clock - _last_end <= 0.45 and _last_step >= 0 and _last_step < ATK.size() - 1:
		s = _last_step + 1
	if target == null:
		face_yaw = player.cam.yaw
		has_face = true
		_start_attack(s)
		return
	var dist := Proj.aim_of(target).distance_to(player.center()) - _gap(target)
	if dist > MAGNET:
		_start_rush()
	else:
		_start_attack(s)


func _start_rush() -> void:
	if flair() >= 3 and _alive(target):
		# 炼虚起：缩地，直接闪到对手身前出手
		_end_blade()
		_flash_step(0.0)
		player.cam.fov_punch(-3.0)
		_start_attack(0)
		return
	_end_blade()
	state = A.RUSH
	_t = 0.0
	_ghost_t = 0.0
	rig.play("f_rush")
	var d := Proj.aim_of(target) - player.center()
	Vfx.dash_start(player.center(), d.normalized(), _col(), 0.6)
	Sfx.play("dodge", -5.0, 1.15)
	player.cam.fov_punch(7.0)
	player.cam.kick_rush(0.9)


## 空间扭曲的一下脉冲（main.gd 会很快把它退掉）：k = 相对强度，实际强度还随境界涨
func _warp(pos: Vector3, k: float) -> void:
	var v := (WARP_BASE + WARP_STEP * float(player.realm_idx)) * k
	if v > Vfx.warp_k:
		Vfx.warp_pos = pos
		Vfx.warp_k = v


## 瞬步：原地留一道残影，人闪到「对手 → 自己」方向转过 ang 弧度后的那一侧（0 = 就在身前）
func _flash_step(ang: float, lift := 0.0) -> void:
	if not _alive(target):
		return
	var from := player.global_position
	var dir := _dir_to(target).rotated(Vector3.UP, ang)
	var to := _stick_point(target, dir) + Vector3.UP * lift
	var cam := player.cam
	# 别闪到贴地的位置（脚一沾地就算落地、退出空战了）
	var fy := float(cam.floor_fn.call(to.x, to.z)) if cam.floor_fn.is_valid() else 0.0
	to.y = maxf(to.y, fy + 0.7)
	var col := _col()
	var h := Vector3.UP * BODY_Y
	Vfx.vanish(from + h, col)
	Vfx.body_ghost(player.visual, Color.WHITE.lerp(col, 0.6), 0.55, 0.28)
	player.global_position = to
	player.velocity = Vector3.ZERO
	drive_vel = Vector3.ZERO
	Vfx.warp_line(from + h, to + h, col)
	face_yaw = atan2(-dir.x, -dir.z)
	has_face = true
	Sfx.play("dodge", -10.0, 1.5)
	cam.kick_rush(0.35)
	_warp(to + h, 0.6)    # 破开空间钻出来的地方微微一扭


func _start_attack(s: int, chained := false) -> void:
	state = A.ATTACK
	step = s
	_atk = ATK[s]
	_t = 0.0
	_hit_done = false
	_queued = false
	_whiff = false
	_engage = ENGAGE_KEEP
	_flurry_left = 0
	var fl := flair()
	if fl >= 1:
		Vfx.body_ghost(player.visual, Color.WHITE.lerp(_col(), 0.6), 0.35, 0.2)
	if chained and _alive(target) and not _is_launched(target):
		# 连段里瞬步换位：境界越高换得越勤
		var ang := 0.0
		match fl:
			2:
				ang = PI if s == 3 else 0.0
			3:
				ang = [0.0, 0.0, 1.9, -2.5, 0.0][s]
			4, 5:
				ang = [0.0, 2.1, -2.1, PI, 1.3][s]
		if ang != 0.0:
			_flash_step(ang)
		if s == ATK.size() - 1 and fl >= 4:
			# 合体 / 大乘：收尾前先来一轮乱舞
			_flurry_left = 4 if fl == 4 else 7
			_flurry_cd = 0.0
			_flurry_n = 0
			player.cam.impact(0.6)
	rig.play(_atk["seq"])
	var sw: bool = _atk["limb"] == "sw"
	if sw:
		player.melee.air_blade(true)
		Vfx.glint(rig.hand_pos(), Color.WHITE.lerp(_col(), 0.4), 0.9)
	else:
		_end_blade()
	Sfx.play("swing_heavy" if int(_atk["tier"]) >= 1 else "swing", -7.0, 1.15 + 0.07 * s)
	if _alive(target):
		var d := _dir_to(target)
		face_yaw = atan2(-d.x, -d.z)
		has_face = true


func _start_charge() -> void:
	_end_blade()
	state = A.CHARGE
	_t = 0.0
	_charge = 0.0
	_aura_t = 0.0
	_auto_release = -1.0
	_engage = ENGAGE_KEEP
	if target == null or not _alive(target):
		target = _pick_target()
	rig.play("f_chg")
	Vfx.cast_charge(player.center(), _col(), CHARGE_FULL)
	Sfx.play("ascend", -12.0, 1.6)
	player.cam.fov_punch(-4.0)


## 松手时读方向：空格 = 挑飞，后 = 陨落，其余 = 崩拳。触屏上没有单独的跳键：摇杆往前推 = 挑飞
func _read_kind(fallback: String) -> String:
	if Input.is_action_pressed("jump") or (player.cam.touch_mode and Input.is_action_pressed("move_forward")):
		return "up"
	if Input.is_action_pressed("move_back"):
		return "down"
	if Input.is_action_pressed("move_forward"):
		return "fwd"
	return fallback


func _release_charge() -> void:
	var k := clampf(_charge / CHARGE_FULL, 0.0, 1.0)
	var kind := _smash_kind if _auto_release >= 0.0 else _read_kind("fwd")
	_hold_used = true
	_chase = false
	_chase_n = 0
	_start_smash(kind, k, true)


func _start_smash(kind: String, k: float, dash: bool) -> void:
	state = A.SMASH
	_t = 0.0
	_smash_kind = kind
	_smash_k = k
	_hit_done = false
	_whiff = false
	_sm_dash = dash and _alive(target) and Proj.aim_of(target).distance_to(player.center()) - _gap(target) > 0.8
	_ghost_t = 0.0
	_engage = ENGAGE_KEEP
	if _sm_dash:
		var d := (Proj.aim_of(target) - player.center()).normalized()
		Vfx.launch_ring(player.center(), d, _col(), 0.6 + k)
		Sfx.play("swing_heavy", -4.0, 0.8)
		player.cam.fov_punch(8.0 + 6.0 * k)
		player.cam.kick_rush(1.0)
	else:
		_smash_swing()


func _smash_swing() -> void:
	_sm_dash = false
	_t = 0.0
	var sm: Dictionary = SMASH[_smash_kind]
	rig.play(sm["seq"])
	Sfx.play("swing_heavy", -3.0, 0.9)
	if _alive(target):
		var d := _dir_to(target)
		face_yaw = atan2(-d.x, -d.z)
		has_face = true


# ---------- 瞬身追击 ----------

func _can_chase() -> bool:
	return _is_launched(_launched) and _chase_n < CHASE_MAX and player.mp >= CHASE_MP


## 击飞方向（三维，已归一）：kind 对应 前 / 上 / 下，flat 为水平基准方向
static func _knock_dir(kind: String, flat: Vector3) -> Vector3:
	match kind:
		"up":
			return (flat * 0.22 + Vector3.UP).normalized()
		"down":
			return (flat * 0.3 + Vector3.DOWN).normalized()
	return (flat + Vector3.UP * 0.16).normalized()


func _start_chase() -> void:
	var t := _launched
	player.mp -= CHASE_MP
	player.caster.hold_regen()
	_chase_n += 1
	if awake_t > 0.0:
		player.mp = minf(player.mp + CHASE_MP, player.mp_max())  # 觉醒中追击不耗灵力
	var kind: String = {"fwd": "up", "up": "down", "down": "fwd"}.get(_launch_kind, "fwd")
	kind = _read_kind(kind)
	# 贴近地面就别再往下砸 / 往前打进地里
	if kind == "down" and Proj.aim_of(t).y < 3.0:
		kind = "up"
	target = t
	var tv: Vector3 = t.velocity() if t.has_method("velocity") else Vector3.ZERO
	var tc := Proj.aim_of(t) + tv * 0.09
	var flat := _flat(tv)
	if flat.length() < 2.0:
		flat = _flat(tc - player.center())
	flat = flat.normalized() if flat.length_squared() > 1e-4 else _fwd()
	if kind == "fwd" and _launch_kind == "fwd":
		flat = flat.rotated(Vector3.UP, 0.9 if _chase_n % 2 == 0 else -0.9)  # 连着往前打：折个方向，别一路打出场外
	var kd := _knock_dir(kind, flat)
	# 出现在击飞方向的反侧：上挑从下方、下砸从上方、前击从背后
	var spot := tc - kd * (_gap(t) + 0.2) - Vector3(0.0, BODY_Y, 0.0)
	spot.y = maxf(spot.y, 0.0)
	var look := _flat(tc - spot)
	var yaw := atan2(-look.x, -look.z) if look.length_squared() > 0.01 else atan2(-flat.x, -flat.z)
	Vfx.vanish(player.center(), _col())
	_end_blade()
	player.warp_to(spot, yaw)
	face_yaw = yaw
	has_face = true
	_chase = true
	Combat.clear_hitstop()
	_start_smash(kind, 0.55, false)
	player.cam.kick_rush(0.7)
	player.melee.combat_event.emit("air_chase", {"n": _chase_n, "kind": kind})


# ---------- 每帧 ----------

func tick(dt: float) -> void:
	var cdt := Combat.cdt(dt)
	_clock += cdt
	_shot_cd -= dt
	_iframe -= dt
	for i in 3:
		cds[i] = maxf(cds[i] - dt, 0.0)
	if state != A.CLASH and player.caster.clash_mode:
		player.caster.end_clash()   # 相持被别的事打断（挨打、落地…）：剑流收掉
	_lie = move_toward(_lie, 1.0 if state == A.DOWN else 0.0, dt * (14.0 if state == A.DOWN else 4.0))
	if awake_t > 0.0:
		awake_t -= dt
		_aura_t -= dt
		if _aura_t <= 0.0 and state != A.CHARGE and state != A.GATHER and player.st == Player.St.AIR and not player.dun_active:
			_aura_t = 0.16
			Vfx.ribbon_burst(player.global_position + Vector3(0.0, 0.3, 0.0), Vector3.UP, _col(), 4, 9.0, 30.0, 0.35, Vector3.ZERO)
		if awake_t <= 0.0:
			player.hero.set_glow(0.0, _col())
	_tick_cine(dt)
	if _flash > 0.0 or _flash_on:
		_flash = maxf(_flash - dt * 7.0, 0.0)
		_flash_on = _flash > 0.0
		player.hero.set_flash(_flash)
	if combo > 0:
		_combo_t -= dt
		if _combo_t <= 0.0:
			combo = 0
			combo_dmg = 0.0
	_drives = false
	drive_vel = Vector3.ZERO
	if player.st != Player.St.AIR:
		if state != A.IDLE or _engage > 0.0:
			_leave()
		_stream = 0.0
		return
	_engage = maxf(_engage - dt, 0.0)
	_since_hurt += dt
	if _since_hurt > REGEN_WAIT and state != A.BLOWN:
		player.melee.hp = minf(player.melee.hp + REGEN * dt, player.melee.HP_MAX)
	_t += cdt
	var holding := Input.is_action_pressed("attack") and not player.is_dashing() and not player.caster.demo_hold_attack
	_held = _held + dt if holding else 0.0
	if _held <= 0.0:
		_hold_used = false
	_tick_shot_hold(dt)
	if target != null and not _alive(target):
		target = null
	if _launched != null and not _alive(_launched):
		_launched = null
	if player.ult.active or player.dun_active:
		if state != A.IDLE:
			_to_idle()
		_upkeep(dt, cdt)
		return

	if _buf_at > 0.0:
		if _now() - _buf_at > BUFFER:
			_buf_at = -10.0
		elif _consume():
			_buf_at = -10.0
	# 长按转蓄力：空手悬停 / 一拳打完之后都可以
	if _held >= HOLD_T and not _hold_used and not player.caster.busy():
		if state == A.IDLE or state == A.RUSH or (state == A.ATTACK and _hit_done and step < ATK.size() - 1):
			_start_charge()

	# 聚气：长按护体（没人在打自己时）就转入聚气；键盘上 V 仍然可以直接聚
	var by_guard := _guard_gather()
	var gather := (Input.is_action_pressed("gather") or demo_gather or by_guard) and not player.is_dashing()
	if gather and (state == A.IDLE or (by_guard and state == A.GUARD)) and not player.caster.busy():
		state = A.GATHER
		_t = 0.0
		_aura_t = 0.0
		_engage = ENGAGE_KEEP
		rig.play("f_gather")
		Sfx.play("ascend", -12.0, 1.3)

	match state:
		A.CLASH:
			_tick_clash(dt)
		A.GATHER:
			_tick_gather(dt, gather)
		A.DOWN:
			_drives = true
			if _t >= _dur:
				if player.melee.hp <= 0.0:
					player.melee.hp = player.melee.HP_MAX
				_iframe = 0.6
				_to_idle()
				_drives = true
				drive_vel = Vector3.UP * 9.0   # 起身：这一帧仍由招式给速度，免得被判成落地
				Vfx.takeoff_burst(player.global_position, _col(), 0.5)
		A.IDLE:
			_tick_idle(dt)
		A.RUSH:
			_tick_rush(cdt)
		A.ATTACK:
			_tick_attack(cdt)
		A.CHARGE:
			_tick_charge(dt)
		A.SMASH:
			_tick_smash(cdt)
		A.GUARD:
			_face_target()
			if not guard_held:
				_to_idle()
		A.HURT, A.BLOWN:
			_drives = true
			drive_vel = _push
			_push = _push.move_toward(Vector3.ZERO, (30.0 if state == A.HURT else 14.0) * cdt)
			if state == A.BLOWN:
				_tumble += 11.0 * cdt
				if _push.y < -5.0 and _push.length() > 12.0 and _on_floor():
					_crash_ground()
					_upkeep(dt, cdt)
					return
			if _t >= _dur:
				if player.melee.hp <= 0.0:
					player.melee.hp = player.melee.HP_MAX
					Vfx.reappear(player.center(), _col())
				_to_idle()
	_upkeep(dt, cdt)


## 姿势权重、镜头锁定、整身翻滚回正、布料飘动
func _upkeep(dt: float, cdt: float) -> void:
	var on := engaged() and not player.dun_active
	rig.w_up_target = 1.0 if on else 0.0
	rig.w_leg_target = 1.0 if on else 0.0
	rig.update(cdt)
	if state != A.BLOWN:
		_tumble = lerp_angle(_tumble, 0.0, 1.0 - exp(-14.0 * dt))
	# 朝目标的仰俯：突进 / 出手时身体对准斜上斜下的目标
	var want := 0.0
	if _alive(target) and (state == A.RUSH or state == A.ATTACK or state == A.SMASH):
		var d := Proj.aim_of(target) - (player.global_position + Vector3(0.0, BODY_Y, 0.0))
		want = clampf(atan2(d.y, maxf(_flat(d).length(), 0.5)), -1.2, 1.2)
	_aim_pitch = lerpf(_aim_pitch, want, 1.0 - exp(-12.0 * dt))
	var fast := clampf(player.velocity.length() / 24.0, 0.0, 1.0)
	_stream = lerpf(_stream, fast, 1.0 - exp(-6.0 * dt))
	player.hero.stream_add = _stream
	if awake_t > 0.0 and state != A.CHARGE and not player.dun_active:
		player.hero.set_glow(0.1 + 0.03 * sin(Time.get_ticks_msec() * 0.02), _col())
	_upkeep_lock()


func _upkeep_lock() -> void:
	var cam := player.cam
	if cam.lock != null and cam.lock != _lock_node:
		_lock_node = null   # 别人（剑冢）在锁：不碰
		return
	var want: Node3D = null
	if engaged() and _alive(target) and Proj.aim_of(target).distance_to(player.center()) < 80.0:
		want = target
	if want != null:
		cam.lock = want
		_lock_node = want
		var sep := Proj.aim_of(want).distance_to(player.center())
		# 对手被打飞得再远，镜头也只拉到十来米（原来最远 26 米，主角在画面里只剩一个点）
		cam.lock_zoom = clampf(5.0 + sep * 0.2 + Proj.body_r(want) * 0.6, 6.5, 12.0)
		cam.duel = true
	elif _lock_node != null:
		cam.lock = null
		cam.duel = false
		_lock_node = null


func _tick_idle(dt: float) -> void:
	if _point_t > 0.0:
		_point_t -= dt
		if _point_t <= 0.0:
			rig.play("f_idle")
	if _alive(target) and engaged():
		_face_target()
	else:
		has_face = false


func _face_target() -> void:
	if not _alive(target):
		has_face = false
		return
	var d := _flat(Proj.aim_of(target) - player.center())
	if d.length_squared() > 0.04:
		face_yaw = atan2(-d.x, -d.z)
		has_face = true


func _tick_rush(cdt: float) -> void:
	if not _alive(target):
		_to_idle()
		return
	_drives = true
	var dir := _dir_to(target)
	var spot := _stick_point(target, dir)
	var to := spot - player.global_position
	var dl := to.length()
	face_yaw = atan2(-dir.x, -dir.z)
	has_face = true
	drive_vel = to.normalized() * minf(RUSH_SPD, dl / maxf(cdt, 1e-3))
	_trail_ghosts(cdt, 0.04)
	if dl < 1.0 or _t > 1.1:
		player.cam.fov_punch(-3.0)
		_start_attack(0)


## 突进 / 重击冲刺沿途的残影
func _trail_ghosts(cdt: float, every: float) -> void:
	_ghost_t += cdt
	if _ghost_t >= every:
		_ghost_t = 0.0
		Vfx.body_ghost(player.visual, Color.WHITE.lerp(_col(), 0.6), 0.4, 0.22)


## 乱舞的一下：闪到对手另一侧（上下也错开），一道弧光斩过去
func _flurry_hit() -> void:
	var t := target
	_flurry_n += 1
	var sgn := -1.0 if _flurry_n % 2 == 0 else 1.0
	_flash_step(sgn * randf_range(1.7, 2.6), randf_range(-0.8, 1.4))
	rig.play(["f1", "f2", "f3", "f4"][_flurry_n % 4])
	var c := Proj.aim_of(t)
	var kd := _dir_to(t)
	var dmg := _base() * 0.22
	var res := _hit_target(t, {"dmg": dmg, "dir": kd, "kb": 1.0, "stun": 0.5, "launch": "", "heavy": false,
			"contact": c, "stop": 0.02, "pst": dmg * 0.5, "step": step, "air": true, "swing": kd})
	if res >= 0:
		_add_combo(dmg)
	Vfx.crescent(c, kd, _col(), 2.6)
	Vfx.hit(c, kd, _col(), 1.0)
	if t.has_method("chip_colors"):
		Vfx.debris(c, kd + Vector3.UP * 0.2, t.chip_colors(), 5, 6.0, 1.0)
	Combat.hitstop(0.025, 0.02)
	Sfx.play("hit", -3.0, 1.1 + 0.06 * float(_flurry_n))
	player.cam.add_trauma(0.14)


func _tick_attack(cdt: float) -> void:
	var a := _atk
	var hit_t: float = a["hit"]
	_drives = true
	if _flurry_left > 0:
		# 乱舞进行中：正招的计时先按住
		_t = 0.0
		drive_vel = Vector3.ZERO
		if not _alive(target):
			_flurry_left = 0
		else:
			_flurry_cd -= cdt
			if _flurry_cd <= 0.0:
				_flurry_cd = 0.075
				_flurry_left -= 1
				_flurry_hit()
				if _flurry_left == 0:
					_flash_step(0.0)
					rig.play(a["seq"])
		return
	if _alive(target):
		var dir := _dir_to(target)
		face_yaw = atan2(-dir.x, -dir.z)
		var to := _stick_point(target, dir) - player.global_position
		if not _hit_done:
			# 出手前吸到身前：保证判定时刻刚好到位
			drive_vel = (to / maxf(hit_t - _t, 0.02)).limit_length(80.0)
		elif not _is_launched(target):
			drive_vel = (to * 8.0).limit_length(22.0)  # 打中后跟着对手被打退的势头贴住
	if not _hit_done and _t >= hit_t:
		_hit_done = true
		_resolve(a, _knock_dir(str(a.get("launch", "")), _fwd()) if a.has("launch") else _fwd(), 1.0)
		if state != A.ATTACK:
			return
	if a["limb"] == "sw" and _t > hit_t + 0.12:
		_end_blade()
	if _queued and step < ATK.size() - 1 and _t >= float(a["chain"]):
		_start_attack(step + 1, true)
		return
	var end_t: float = float(a["end"]) * (0.8 if _whiff else 1.0)
	if _t >= end_t:
		_last_step = step
		_last_end = _clock
		_to_idle()


func _tick_charge(dt: float) -> void:
	_drives = true
	_charge += dt
	_face_target()
	var k := charge_k()
	_aura_t -= dt
	if _aura_t <= 0.0:
		_aura_t = 0.11
		var c := _col()
		Vfx.ribbon_burst(player.global_position + Vector3(0.0, 0.2, 0.0), Vector3.UP, c, 3 + int(4.0 * k), 7.0 + 6.0 * k,
				35.0, 0.35, Vector3.ZERO)
		if k >= 1.0:
			Vfx.glint(rig.hand_pos(), Color.WHITE.lerp(c, 0.3), 1.0)
	player.cam.add_trauma(0.012 + 0.02 * k)
	player.hero.set_glow(0.16 * k, _col())
	var release := _held <= 0.0 if _auto_release < 0.0 else _charge >= _auto_release
	if release or _charge >= CHARGE_FULL + CHARGE_MAX:
		player.hero.set_glow(0.0, _col())
		_release_charge()


func _tick_smash(cdt: float) -> void:
	var sm: Dictionary = SMASH[_smash_kind]
	_drives = true
	var flat := _fwd()
	if _alive(target):
		flat = _dir_to(target)
	var kd := _knock_dir(_smash_kind, flat)
	if _sm_dash:
		# 冲刺段：贴到目标身前再挥拳
		if not _alive(target):
			_smash_swing()
			return
		var spot := _stick_point(target, flat)
		var to := spot - player.global_position
		var dl := to.length()
		face_yaw = atan2(-flat.x, -flat.z)
		has_face = true
		drive_vel = to.normalized() * minf(78.0, dl / maxf(cdt, 1e-3))
		_trail_ghosts(cdt, 0.03)
		if dl < 0.9 or _t > 0.3:
			_smash_swing()
		return
	var hit_t: float = sm["hit"]
	if _alive(target) and not _hit_done:
		# 追击时目标还在飞：按击飞方向的反侧贴住它
		var spot := Proj.aim_of(target) - (kd if _chase else flat) * _gap(target) - Vector3(0.0, BODY_Y, 0.0)
		spot.y = maxf(spot.y, 0.0)
		drive_vel = ((spot - player.global_position) / maxf(hit_t - _t, 0.02)).limit_length(140.0)
		face_yaw = atan2(-flat.x, -flat.z)
	if not _hit_done and _t >= hit_t:
		_hit_done = true
		var k := _smash_k
		var info := {"name": sm["name"], "dmg": 1.5 + 1.3 * k, "kb": float(sm["spd"]) * (0.85 + 0.3 * k), "stun": 1.0,
				"stop": 0.13 + 0.07 * k, "limb": sm["limb"], "tier": 1, "trauma": 0.45 + 0.2 * k, "push": 0.12 + 0.06 * k,
				"swords": 0, "launch": _smash_kind, "heavy": true}
		_resolve(info, kd, 1.0)
		if state != A.SMASH:
			return
	if _t >= float(sm["end"]) * (0.75 if _whiff else 1.0):
		_last_step = -1
		_to_idle()


func _tick_shot_hold(dt: float) -> void:
	_shot_held = _shot_held + dt if Input.is_action_pressed("air_shot") and not player.is_dashing() else 0.0


## E 是否按住到了连发的时长（air_caster.gd 读）
func shot_hold() -> float:
	if state == A.HURT or state == A.BLOWN or state == A.CHARGE or state == A.SMASH or state == A.RUSH:
		return 0.0
	return _shot_held


func _to_idle() -> void:
	_end_blade()
	player.hero.set_glow(0.0, _col())
	state = A.IDLE
	_t = 0.0
	_queued = false
	if guard_held and player.st == Player.St.AIR and not player.caster.busy():
		state = A.GUARD
		rig.play("f_guard")
		return
	rig.play("f_idle")


func _end_blade() -> void:
	player.melee.air_blade(false)


## 离开空战（落地 / 转光遁）：收招、放开镜头
func _leave() -> void:
	_end_blade()
	state = A.IDLE
	_engage = 0.0
	_queued = false
	_buf_at = -10.0
	_tumble = 0.0
	_aim_pitch = 0.0
	has_face = false
	target = null
	_launched = null
	rig.w_up_target = 0.0
	rig.w_leg_target = 0.0
	player.hero.stream_add = 0.0
	_upkeep_lock()
	_end_cine()


## 闪现打断（Player.blink 调）
func on_blink() -> void:
	if state == A.CHARGE:
		player.hero.set_glow(0.0, _col())
	_end_blade()
	state = A.IDLE
	_t = 0.0
	_queued = false
	_buf_at = -10.0
	_tumble = 0.0
	_iframe = maxf(_iframe, 0.25)
	Combat.clear_hitstop()
	rig.play("f_idle")


# ---------- 出招结算 ----------

func _limb_pos(limb: String) -> Vector3:
	match limb:
		"lh":
			return rig.left_hand_pos()
		"rf":
			return rig.foot_pos(true)
		"lf":
			return rig.foot_pos(false)
		"sw":
			return rig.blade_point(0.7)
	return rig.hand_pos()


## a：招式参数；kd：击退 / 击飞方向；mul：伤害倍率
func _resolve(a: Dictionary, kd: Vector3, mul: float) -> void:
	var t := target
	var hit := false
	if _alive(t):
		var tc := Proj.aim_of(t)
		var from := player.global_position + Vector3(0.0, BODY_Y, 0.0)
		var d := tc - from
		if d.length() <= _gap(t) + 1.7:
			var dn := d.normalized() if d.length_squared() > 1e-4 else _fwd()
			var contact := tc - dn * minf(0.3 + Proj.body_r(t), d.length())
			var heavy: bool = a.get("heavy", int(a["tier"]) >= 1)
			var launch: String = a.get("launch", "")
			var dmg := _base() * float(a["dmg"]) * mul
			var info := {"dmg": dmg, "dir": kd, "kb": a["kb"], "stun": a["stun"], "launch": launch, "heavy": heavy,
					"contact": contact, "stop": a["stop"], "pst": dmg * 0.6, "step": step, "air": true, "swing": kd}
			var res := _hit_target(t, info)
			if res == 1:
				_fx_blocked(contact, dn)
				hit = true
			elif res >= 0:
				_fx_hit(t, a, contact, kd, dmg, res == 2)
				hit = true
				if launch != "" and _is_launched(t):
					_on_launch(t, launch, contact, kd, float(a.get("stop", 0.1)))
				var n: int = a.get("swords", 0)
				if n > 0:
					_sword_follow(t, n)
	if not hit:
		_whiff = true
		player.melee.combat_event.emit("air_whiff", {})


func _hit_target(t: Node3D, info: Dictionary) -> int:
	if t.has_method("air_hit"):
		var r: int = t.air_hit(player, info)
		return r
	var kd: Vector3 = info["dir"]
	return Proj.hurt(player, t, float(info["dmg"]), kd, _col(), bool(info["heavy"]))


## 命中反馈：顿帧 → 命中音 → 冲击特效 / 碎块 → 镜头 → 连击数 / 回灵力
func _fx_hit(t: Node3D, a: Dictionary, c: Vector3, kd: Vector3, dmg: float, broke: bool) -> void:
	var tier: int = a["tier"]
	var heavy: bool = a.get("heavy", false)
	var col := _col()
	Combat.hitstop(float(a["stop"]), 0.0 if heavy else 0.03)
	Sfx.play("hit_heavy" if tier >= 1 else "hit", 0.0 if tier >= 1 else -1.0, 0.9 + 0.05 * float(step % 5))
	var swing := kd.cross(Vector3.UP)
	swing = swing.normalized() if swing.length_squared() > 1e-4 else Vector3.RIGHT
	if a["limb"] == "sw":
		swing = Basis(Vector3.UP, face_yaw) * Vector3.RIGHT
	Vfx.impact(c, swing, col, 4 if heavy else tier)
	if t.has_method("chip_colors"):
		Vfx.debris(c, kd + Vector3.UP * 0.2, t.chip_colors(), 16 if heavy else (10 if tier >= 1 else 6),
				7.5 if heavy else 5.0, 1.2 if heavy else 1.0)
	if heavy or tier >= 1:
		Vfx.shockwave(c, kd, col, 1.5 if heavy else 0.8)
	if Realm.art(player.realm) == 3 and (heavy or tier >= 1):
		Vfx.fire_explode(c, kd, heavy)  # 化神·焚天：重手带火
	var fl := flair()
	if heavy or tier >= 1:
		_warp(c, 1.0 if heavy else 0.7)     # 重手：命中点的空间震一下
		if fl >= 2:
			# 化神起：重手带一道剑气弧光，命中点的空间碎一下
			Vfx.crescent(c, kd, col, 2.6 + 0.3 * float(fl))
			player.cam.impact(0.3 + 0.06 * float(fl))
		if fl >= 4:
			Vfx.rift(c, kd, col, 1.2, 0.3)   # 合体起：撕开一道空间裂隙
		if fl >= 3:
			_phantoms(t, fl - 2, dmg)        # 炼虚起：分身协击
	player.cam.add_trauma(float(a["trauma"]))
	player.cam.push_in(float(a["push"]))
	_add_combo(dmg)
	player.mp = minf(player.mp + HIT_MP * (2.0 if heavy else 1.0), player.mp_max())
	if broke:
		player.melee.combat_event.emit("air_break", {"pos": c})
	player.melee.combat_event.emit("air_hit", {"step": step, "heavy": heavy, "pos": c})


## 分身协击：n 道分身出现在对手四周，错开一点时间各补一击
func _phantoms(t: Node3D, n: int, dmg: float) -> void:
	var col := _col()
	var tc := Proj.aim_of(t)
	for i in n:
		var a := face_yaw + PI + TAU * (float(i) + 1.0) / float(n + 1) + randf_range(-0.25, 0.25)
		var dir := Vector3(-sin(a), randf_range(-0.2, 0.3), -cos(a)).normalized()   # 分身 → 对手
		var g := Vfx._ghost_node(player.visual, Color.WHITE.lerp(col, 0.45), 0.8, player.global_position)
		var pos := tc - dir * (_gap(t) + 0.4) - Vector3(0.0, BODY_Y, 0.0)
		g.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z) - face_yaw), pos)
		Vfx.vanish(pos + Vector3.UP * BODY_Y, col)
		var tw := g.create_tween()
		tw.tween_interval(0.06 + 0.07 * float(i))
		tw.tween_callback(_phantom_hit.bind(t, dir, dmg * 0.25))
		tw.tween_property(g.get_meta("mat"), "albedo_color:a", 0.0, 0.28)
		tw.tween_callback(g.queue_free)


func _phantom_hit(t: Variant, dir: Vector3, dmg: float) -> void:
	if not _alive(t) or player.st != Player.St.AIR:
		return
	var c := Proj.aim_of(t)
	Vfx.crescent(c, dir, _col(), 2.2)
	Vfx.hit(c, dir, _col(), 0.9)
	var info := {"dmg": dmg, "dir": dir, "kb": 1.5, "stun": 0.3, "launch": "", "heavy": false,
			"contact": c, "stop": 0.0, "pst": dmg * 0.5, "step": step, "air": true, "swing": dir}
	# 对手已经被打飞：走飞剑那条受击（只扣血，不把击飞打断成硬直）
	var res: int = t.receive_hit(player, info) if _is_launched(t) and t.has_method("receive_hit") else _hit_target(t, info)
	if res >= 0:
		_add_combo(dmg)
	Sfx.play("hit", -6.0, 1.3)
	player.cam.add_trauma(0.08)


## 大乘：连段收尾把人打飞后，天上一圈金剑落下来追击
func _sword_rain(t: Node3D) -> void:
	var tc := Proj.aim_of(t)
	var cols := Realm.lines(player.realm)
	Vfx.sky_ring(tc + Vector3.UP * 9.0, _col(), 5.5, 0.9, 1.0)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var from := tc + Vector3(cos(a) * 5.5, 9.0 + randf_range(-0.6, 0.6), sin(a) * 5.5)
		Proj.launch(player, Proj.K.SWORD, from, t, tc, {"dmg": _base() * 0.18, "color": cols[i % cols.size()], "speed": 92.0,
				"hold": 0.12 + 0.03 * float(i), "turn": 14.0, "light": true, "lite": true, "scale": 2.3, "style": 4,
				"sfx": i % 4 == 0, "trauma": 0.012, "life": 1.6, "art": 6})


func _fx_blocked(c: Vector3, dn: Vector3) -> void:
	Vfx.blade_clash(c, -dn, 0.7)
	Combat.hitstop(0.05)
	Sfx.play("block", -3.0, 1.2)
	player.cam.add_trauma(0.12)
	player.melee.combat_event.emit("air_blocked", {"pos": c})


func _add_combo(dmg: float) -> void:
	combo += 1
	combo_dmg += dmg
	if awake_t <= 0.0:
		awaken = minf(awaken + 2.5, 100.0)
	_combo_t = COMBO_KEEP
	_engage = ENGAGE_KEEP


## 飞剑 / 法术命中（spell_projectile.gd 调）：计入连击
func on_spell_hit(dmg: float) -> void:
	if player.st == Player.St.AIR:
		_add_combo(dmg)


## 剑随拳走：n 柄飞剑从肩后亮出，紧跟着刺进同一个目标
func _sword_follow(t: Node3D, n: int) -> void:
	var fb := Basis(Vector3.UP, face_yaw)
	var art := Realm.art(player.realm)
	var cols := Realm.lines(player.realm)
	for k in n:
		var side := (-1.0 if (k + step) % 2 == 0 else 1.0) * (0.8 + 0.35 * float(k / 2))
		var from := player.global_position + fb * Vector3(side, 1.75 + 0.3 * float(k), 0.75)
		Proj.launch(player, Proj.K.SWORD, from, t, Proj.aim_of(t),
				{"dmg": _base() * 0.2, "color": cols[k % cols.size()], "speed": 74.0, "hold": 0.04 + 0.05 * float(k),
				 "turn": 18.0, "art": art, "tw": 0.09, "lite": true, "sfx": k == 0, "trauma": 0.012, "life": 1.0})
		Vfx.glint(from, Color.WHITE.lerp(_col(), 0.4), 0.5)


## 把人打飞的那一下：冲击帧、破空环、镜头猛推再甩开
func _on_launch(t: Node3D, kind: String, c: Vector3, kd: Vector3, stop: float) -> void:
	_launched = t
	_launch_kind = kind
	var col := _col()
	Vfx.launch_ring(c, kd, col, 1.6)
	Vfx.shockwave(c, kd, Color.WHITE.lerp(col, 0.4), 2.2)
	Sfx.play("slam", -3.0, 1.25)
	var cam := player.cam
	cam.impact(1.0)
	cam.fov_punch(11.0)
	cam.kick_rush(1.0)
	_warp(c, 1.8)       # 把人打飞的那一下：空间碎裂的同时狠狠一扭
	player.melee.combat_event.emit("air_launch", {"kind": kind, "pos": c, "chase": _chase})
	if flair() >= 5 and state == A.ATTACK:
		_sword_rain(t)
	if kind == "down" and c.y > 7.0:
		_cine_meteor(t, c, kd, stop)
	elif not _chase and _smash_k >= 0.95 and state == A.SMASH:
		Combat.slowmo(0.25, 0.05, 0.3)


## 对手撞上场景（air_foe.gd / enemy_dummy.gd 调）
func on_crash(_who: Node3D, pos: Vector3, spd: float, ground: bool) -> void:
	var near := clampf(1.0 - pos.distance_to(player.center()) / 70.0, 0.25, 1.0)
	var cam := player.cam
	_warp(pos, 1.4 * near)   # 对手砸进场景：落点一圈波动
	cam.add_trauma(0.55 * near)
	cam.impact(0.7)
	_add_combo(0.0)
	player.melee.combat_event.emit("air_crash", {"pos": pos, "ground": ground, "spd": spd})
	if _cine_wait_crash:
		_cine_wait_crash = false
		_cine_dur = _cine_t + 0.55


# ---------- 受到攻击（对手在判定时刻调用） ----------

## 返回 2 瞬身闪开 / 1 护体挡下 / 0 受击 / -1 无效（不在空战、闪现无敌中）
func receive_attack(src: Node3D, info: Dictionary) -> int:
	if player.st != Player.St.AIR or player.is_dashing() or _iframe > 0.0 or player.ult.active or player.dun_active:
		return -1
	if state == A.CLASH:
		return -1   # 飞剑对波相持中：谁也打不进来（只有对波的结果能伤到自己）
	player.note_attacker(src)
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var heavy: bool = info.get("heavy", false)
	var ranged: bool = info.get("ranged", false)
	_engage = ENGAGE_KEEP
	var front := _fwd().dot(_flat(dir).normalized()) < 0.3
	if state == A.GUARD and _clock - _guard_at <= PERFECT:
		_vanish_counter(src, ranged)
		return 2
	if state == A.GUARD and front and (not heavy or player.mp >= GUARD_MP * 2.0):
		player.mp = maxf(player.mp - GUARD_MP * (2.0 if heavy else 1.0), 0.0)
		player.caster.hold_regen()
		player.melee.hp = maxf(player.melee.hp - float(info.get("dmg", 8.0)) * 0.15, 1.0)
		var c: Vector3 = info.get("contact", player.center())
		Vfx.blade_clash(c, -dir, 1.0 if heavy else 0.65)
		Vfx.shockwave(c, -dir, _col(), 0.7)
		Combat.hitstop(0.07 if heavy else 0.04)
		Sfx.play("block", -1.0, 0.9 if heavy else 1.1)
		player.cam.add_trauma(0.25 if heavy else 0.12)
		_push = dir * (9.0 if heavy else 3.0)
		player.velocity += _push
		player.melee.combat_event.emit("air_guard", {"heavy": heavy})
		return 1
	_hurt(src, info, dir, heavy)
	return 0


## 瞬身：闪到对手背后，画面骤慢，对手这一下打空
func _vanish_counter(src: Node3D, ranged: bool) -> void:
	var sc := Proj.aim_of(src)
	var away := _flat(sc - player.center())
	away = away.normalized() if away.length_squared() > 1e-4 else _fwd()
	var spot := sc + away * 1.7 - Vector3(0.0, BODY_Y, 0.0)
	if ranged:
		# 远程剑气：就地侧闪一步
		spot = player.global_position + away.cross(Vector3.UP) * 3.0
	spot.y = maxf(spot.y, 0.0)
	var look := _flat(sc - spot)
	var yaw := atan2(-look.x, -look.z)
	Vfx.vanish(player.center(), _col())
	Vfx.perfect_dodge(player.center(), sc, _col())
	player.warp_to(spot, yaw)
	face_yaw = yaw
	has_face = true
	target = src
	_iframe = 0.5
	Combat.slowmo(0.14, 0.3, 0.4)
	Sfx.play("perfect", -2.0)
	player.cam.fov_punch(-7.0)
	player.mp = minf(player.mp + 10.0, player.mp_max())
	if not ranged and src.has_method("on_vanished"):
		src.on_vanished()
	state = A.IDLE
	_t = 0.0
	rig.play("f_idle")
	player.melee.combat_event.emit("air_vanish", {})


func _hurt(_src: Node3D, info: Dictionary, dir: Vector3, heavy: bool) -> void:
	var m := player.melee
	m.hp = maxf(m.hp - float(info.get("dmg", 8.0)), 0.0)
	_since_hurt = 0.0
	if awake_t <= 0.0:
		awaken = minf(awaken + 8.0, 100.0)
	if state == A.CHARGE:
		player.hero.set_glow(0.0, _col())
	_end_blade()
	var c: Vector3 = info.get("contact", player.center())
	var swing := dir.cross(Vector3.UP)
	swing = swing.normalized() if swing.length_squared() > 1e-4 else Vector3.RIGHT
	Combat.hitstop(0.1 if heavy else 0.06)
	Sfx.play("hit_heavy" if heavy else "hit", 0.0, 0.85)
	_flash = 1.0
	_flash_on = true
	player.hit_shake(0.1)
	Vfx.impact(c, swing, Color(0.95, 0.25, 0.2), 1 if heavy else 0)
	Vfx.debris(c, dir + Vector3.UP * 0.2, player.hero.chip_colors(), 12 if heavy else 7, 5.0)
	player.cam.add_trauma(0.4 if heavy else 0.22)
	combo = 0
	combo_dmg = 0.0
	_queued = false
	_buf_at = -10.0
	var dead := m.hp <= 0.0
	if heavy or dead:
		state = A.BLOWN
		_dur = 1.3 if dead else 0.75
		_push = dir * float(info.get("kb", 22.0))
		rig.play("f_blown")
		Vfx.shockwave(c, dir, Color(1.0, 0.5, 0.4), 1.2)
		player.cam.impact(0.6)
		if dead:
			Combat.slowmo(0.2, 0.25, 0.4)
	else:
		state = A.HURT
		_dur = 0.3
		_push = dir * float(info.get("kb", 6.0))
		rig.play("f_hurt2" if randf() < 0.5 else "f_hurt")
	_t = 0.0
	player.melee.combat_event.emit("air_hurt", {"heavy": heavy, "dead": dead})


# ---------- 演出镜头 ----------

func _tick_cine(dt: float) -> void:
	if _cine_t < 0.0:
		return
	_cine_t += dt
	var cam := player.cam
	var look := player.center()
	if _cine_use_look:
		look = _cine_look
	elif is_instance_valid(_cine_follow):
		look = Proj.aim_of(_cine_follow) if _alive(_cine_follow) else _cine_follow.global_position
	var f := look - _cine_eye
	if f.length_squared() > 0.01:
		var up := Vector3.UP if absf(f.normalized().dot(Vector3.UP)) < 0.97 else Vector3.BACK
		cam.cine_xf = Transform3D(Basis.looking_at(f, up), _cine_eye)
	var left := _cine_dur - _cine_t
	cam.cine_k = clampf(left / _cine_out, 0.0, 1.0)
	if left <= 0.0 or player.st != Player.St.AIR:
		_end_cine()


func _end_cine() -> void:
	if _cine_t < 0.0:
		return
	_cine_t = -1.0
	_cine_wait_crash = false
	_cine_follow = null
	player.cam.cine_k = 0.0


func _start_cine(eye: Vector3, follow: Node3D, dur: float, fov: float, out := 0.25) -> void:
	if player.ult.active:
		return
	_cine_eye = eye
	_cine_use_look = false
	_cine_follow = follow
	_cine_t = 0.0
	_cine_dur = dur
	_cine_out = out
	player.cam.cine_fov = fov
	player.cam.cine_k = 1.0
	_tick_cine(0.0)


## 陨落：机位切到落点旁的低处，仰看它从天上砸下来；砸地后再多留半秒
func _cine_meteor(t: Node3D, c: Vector3, kd: Vector3, _stop: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(c, c + kd * 400.0, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var g := c + kd * (c.y / maxf(-kd.y, 0.2))
	if not hit.is_empty():
		g = hit["position"]
	var side := kd.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	if side.dot(player.cam.global_position - g) < 0.0:
		side = -side
	var eye := g + side * clampf(c.y * 0.45, 7.0, 16.0) + Vector3.UP * 1.4 - _flat(kd) * 3.0
	_start_cine(eye, t, 2.2, 62.0, 0.35)
	_cine_wait_crash = true


## 第三式剑诀：出手前侧前方低机位特写，随后放回跟随机位看剑飞出去
func _cine_skill() -> void:
	var fb := Basis(Vector3.UP, player.cam.yaw)
	var eye := player.center() + fb * Vector3(1.9, -0.35, -2.6)
	_start_cine(eye, null, 0.5, 50.0, 0.22)
	Combat.slowmo(0.35, 0.12, 0.25)


# ---------- 飞剑对波 ----------
## 两个人同时朝对方连发飞剑（E 长按）时，两股剑流在中间迎头对撞、相持：
##   · 进入：自己在连发、对手也在连发（air_caster.gd 发现后调 start_clash），或对手的飞剑出手时自己正在连发（foe_volley_started）
##   · 相持：双方定在原地，剑一柄柄飞到交汇点撞碎；交汇点按双方的力道推移，连点「攻击」往对面顶，觉醒时顶得更狠
##   · 表现：侧面机位、交汇点的光球 / 冲击环 / 四溅的火星和电弧、镜头震动，以及一圈空间扭曲（境界越高扭得越厉害）
##   · 分胜负：交汇点顶到对手身上 → 剑流破阵而过，把他轰飞；被顶到自己身上 → 自己被轰飞；最久 CLASH_MAX 秒，到点看谁占优

##   · 预警：对手朝自己起手飞剑的一瞬间，画面一顿（短暂时停）、屏幕中间亮出「飞剑来袭」的提示和倒计时条，
##     这段时间里点「剑」或「攻击」就接下这一波、正式进入对波；没点到，剑流照常打过来。
##     对手已经在连发、自己正被打得僵直时点「剑」也能接（不用先摆脱僵直）。

## 对手朝自己起手飞剑（air_foe.gd 调）：时停一下、开预警窗口
func clash_warn(foe: Node3D) -> void:
	if player.st != Player.St.AIR or state == A.CLASH or state == A.BLOWN or state == A.DOWN or player.ult.active:
		return
	_warn_foe = foe
	_warn_until = float(Time.get_ticks_msec()) + WARN_MS
	Combat.slowmo(0.05, WARN_MS * 0.00065, 0.2)
	player.cam.impact(0.35)
	Sfx.play("perfect", -4.0, 0.7)
	_engage = ENGAGE_KEEP
	player.melee.combat_event.emit("air_clash_warn", {"pos": Proj.aim_of(foe)})


## 对手的剑出手了：预警窗口关上（之后只要他还在连发，点「剑」仍然能接）
func clash_warn_fired(_foe: Node3D) -> void:
	_warn_until = 0.0


## 预警窗口里，n 正是那个朝自己起手的对手（联机：这段时间他的飞剑先不算伤害，给接波留出时间）
func warned_by(n: Variant) -> bool:
	return warn_k() > 0.0 and _warn_foe == n


## 预警窗口还剩多少（0~1，0 = 没在预警），HUD / 触屏按钮用
func warn_k() -> float:
	if _warn_until <= 0.0 or not _alive(_warn_foe):
		return 0.0
	return clampf((_warn_until - float(Time.get_ticks_msec())) / WARN_MS, 0.0, 1.0)


## 有没有对手正朝自己起手 / 连发飞剑、可以接下来对波
func can_accept_clash() -> bool:
	# 预警窗口里一定能接（联机时对方「正在连发」的状态会晚一两帧才同步到）；窗口过了就看他是不是还在连发
	return state != A.CLASH and _alive(_warn_foe) and _warn_foe.has_method("volley_active") 			and (warn_k() > 0.0 or bool(_warn_foe.call("volley_active")))


## 接波：预警窗口里、或对手还在连发时点了「剑」。挨打僵直中也能接。进入了返回 true
func _accept_clash() -> bool:
	if not can_accept_clash() or player.st != Player.St.AIR or state == A.BLOWN or state == A.DOWN or player.ult.active:
		return false
	var foe := _warn_foe
	if player.center().distance_to(foe.call("center")) < 4.0:
		return false
	_warn_until = 0.0
	Combat.slowmo_release(0.1)
	player.caster.cancel()
	_end_blade()
	player.hero.set_glow(0.0, _col())
	_start_clash(foe)
	return true


## 能不能进入对波（距离够、自己没在挨打 / 倒地）。进入了返回 true
func start_clash(foe: Node3D) -> bool:
	if state == A.CLASH or state == A.HURT or state == A.BLOWN or state == A.DOWN or state == A.RUSH or state == A.SMASH:
		return false
	if not _alive(foe) or not foe.has_method("clash_origin") or player.ult.active:
		return false
	if player.center().distance_to(foe.call("center")) < CLASH_MIN_DIST:
		return false
	_end_blade()
	player.hero.set_glow(0.0, _col())
	_start_clash(foe)
	return true


## 对手的飞剑出手了（air_foe.gd 调）。自己正在连发 → 进入对波，返回 true
func foe_volley_started(foe: Node3D) -> bool:
	if not player.caster.channeling or player.caster.clash_mode:
		return false
	return start_clash(foe)


## 联机：对方那边进了对波，叫我也进（net.gd 调）。i_auth = 两边同时发起时由谁做主（编号小的）
func net_clash_begin(foe: Node3D, i_auth: bool) -> void:
	if state == A.CLASH:
		if _clash_foe == foe:
			_clash_auth = i_auth     # 两边同时发起：按编号定一个做主的
		return
	if player.st != Player.St.AIR or state == A.BLOWN or state == A.DOWN or player.ult.active:
		foe.call("net_clash_end", false)   # 我这边进不了（没在空战 / 正被打飞）：算我输，对方直接收招
		return
	_warn_until = 0.0
	Combat.slowmo_release(0.1)
	player.caster.cancel()
	_end_blade()
	player.hero.set_glow(0.0, _col())
	_start_clash(foe, false)
	_clash_auth = false


## 联机：做主的那边判了胜负
func net_clash_result(won: bool) -> void:
	if state == A.CLASH:
		_clash_forced = 1 if won else -1


func _start_clash(foe: Node3D, notify := true) -> void:
	state = A.CLASH
	_clash_my = 0.0
	_clash_auth = true
	_clash_forced = 0
	if foe.get("clash_their") != null:
		foe.set("clash_their", 0.0)
	_t = 0.0
	_clash_foe = foe
	_clash_u = 0.5
	_clash_t = 0.0
	_clash_fx = 0.0
	_clash_blast = 0.4
	_clash_arc = 0.0
	_clash_ring = 0.0
	_engage = ENGAGE_KEEP
	target = foe
	player.caster.clash_mode = true
	if notify:
		foe.clash_begin()
	rig.play("f_point")
	var a := player.center()
	var b: Vector3 = foe.clash_origin()
	_beam_dir = (b - a).normalized()
	# 侧面机位：两道光柱横贯画面
	var mid := a.lerp(b, 0.5)
	var side := _beam_dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	if side.dot(player.cam.global_position - mid) < 0.0:
		side = -side
	var eye := mid + side * (a.distance_to(b) * 0.55 + 7.0) + Vector3.UP * 2.0
	_start_cine(eye, null, CLASH_MAX + 2.0, 60.0, 0.4)
	_cine_look = mid
	_cine_use_look = true
	Combat.slowmo(0.3, 0.12, 0.3)
	player.cam.impact(0.8)
	Sfx.play("clash", 0.0, 0.7)
	player.melee.combat_event.emit("air_clash", {"pos": mid})


func _clash_tap() -> void:
	_clash_u += CLASH_TAP * (1.35 if awake_t > 0.0 else 1.0)
	_clash_my += CLASH_TAP * (1.35 if awake_t > 0.0 else 1.0)
	player.cam.add_trauma(0.05)
	Vfx.ribbon_burst(_hand_point(), _beam_dir, _col(), 3, 14.0, 25.0, 0.25, Vector3.ZERO)


func _tick_clash(dt: float) -> void:
	_drives = true
	var foe := _clash_foe
	if not _alive(foe) or not foe.has_method("clash_power"):
		player.caster.end_clash()
		_end_cine()
		_to_idle()
		return
	_face_target()
	_clash_t += dt
	# 相持持续耗灵力；耗尽就撑不住了
	player.mp = maxf(player.mp - CLASH_MP * dt, 0.0)
	player.caster.hold_regen()
	var netfoe := foe.has_method("net_clash_push")
	if netfoe:
		# 对手是真人：我这边只管累计自己顶的（底劲随境界 + 连点），交汇点两边对账
		_clash_my += 0.1 * (1.0 + 0.06 * float(player.realm_idx)) * (1.3 if awake_t > 0.0 else 1.0) * dt
		if demo_mash > 0.0:
			_clash_my += CLASH_TAP * demo_mash * dt
		if player.mp <= 0.0:
			_clash_my -= 1.2 * dt
		_clash_u = clampf(0.5 + _clash_my - float(foe.get("clash_their")), 0.0, 1.0)
		foe.call("net_clash_push", _clash_my)
	else:
		var push: float = foe.clash_power()
		_clash_u -= push * dt * (1.0 + 0.12 * _clash_t)
		if player.mp <= 0.0:
			_clash_u -= 1.2 * dt
		if demo_mash > 0.0:
			_clash_u += CLASH_TAP * demo_mash * dt
		_clash_u = clampf(_clash_u, 0.0, 1.0)
	var a := _hand_point()
	var b: Vector3 = foe.clash_origin()
	_beam_dir = (b - a).normalized() if a.distance_squared_to(b) > 0.01 else _beam_dir
	var pt := a.lerp(b, _clash_u)
	_cine_look = a.lerp(b, 0.5).lerp(pt, 0.5)
	player.cam.add_trauma(0.045)
	# 空间扭曲：境界越高越强，带一点脉动；快分胜负时再涨
	var edge := maxf(absf(_clash_u - 0.5) * 2.0 - 0.5, 0.0)
	Vfx.warp_pos = pt
	Vfx.warp_k = (WARP_BASE + WARP_STEP * float(player.realm_idx)) * (1.0 + 0.25 * sin(_clash_t * 9.0) + 0.8 * edge)
	var mine := Color.WHITE.lerp(_col(), 0.45)
	var theirs := Color.WHITE.lerp(foe.get("qi") as Color, 0.45) if foe.get("qi") != null else mine
	var side := _beam_dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	_clash_fx -= dt
	if _clash_fx <= 0.0:
		# 交汇点的光核：两色交替闪，四溅的火星
		_clash_fx = 0.06
		var flip := randf() < 0.5
		Vfx.glint(pt + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)), mine if flip else theirs, randf_range(1.6, 2.6))
		Vfx.line_sparks(pt, (side if flip else -side) + Vector3.UP * randf_range(-0.6, 0.9), mine if flip else theirs, 6, 18.0, 150.0, 0.4)
	_clash_ring -= dt
	if _clash_ring <= 0.0:
		# 一圈圈冲击环沿着剑流的垂面荡开，金铁交鸣
		_clash_ring = 0.2
		Vfx.shockwave(pt, _beam_dir if randf() < 0.6 else Vector3.UP, mine if randf() < 0.5 else theirs, 1.5 + edge)
		Vfx.blade_clash(pt, side if randf() < 0.5 else Vector3.UP, 1.0)
		Sfx.play("clash", -9.0, randf_range(0.9, 1.3))
	_clash_blast -= dt
	if _clash_blast <= 0.0:
		# 空间波动把凑过来的旁人震开（境界越高震得越远）
		_clash_blast = 0.5
		var spd := 16.0 + 2.5 * float(player.realm_idx)
		var any := false
		for e in Proj.targets(player.get_tree()):
			if e == foe or not e.has_method("blast_away"):
				continue
			if Proj.aim_of(e).distance_to(pt) < CLASH_BLAST_R or Proj.aim_of(e).distance_to(a) < CLASH_BLAST_R * 0.6:
				e.call("blast_away", pt, spd)
				any = true
		if any:
			Vfx.shockwave(pt, Vector3.UP, mine, 3.2)
			Sfx.play("slam", -8.0, 1.3)
	_clash_arc -= dt
	if _clash_arc <= 0.0:
		# 从交汇点甩出去的电弧
		_clash_arc = 0.11
		var od := (side * randf_range(-1.0, 1.0) + Vector3.UP * randf_range(-1.0, 1.0) + _beam_dir * randf_range(-0.3, 0.3)).normalized()
		Vfx.lightning(pt, pt + od * randf_range(2.5, 5.5), mine if randf() < 0.5 else theirs, 0.06, 0.12, 4)
	var win := _clash_u >= 0.97 or (_clash_t >= CLASH_MAX and _clash_u >= 0.5)
	var lose := _clash_u <= 0.03 or (_clash_t >= CLASH_MAX and _clash_u < 0.5)
	if netfoe:
		if _clash_auth:
			if win or lose:
				foe.call("net_clash_end", win)      # 我做主：把结果告诉对方
		else:
			win = _clash_forced == 1
			lose = _clash_forced == -1 or (not win and _clash_t > CLASH_MAX + 3.0)   # 一直等不到结果：按输收场
	if not (win or lose):
		return
	foe.clash_end(win)
	player.caster.end_clash()
	Vfx.warp_pos = pt
	Vfx.warp_k = (WARP_BASE + WARP_STEP * float(player.realm_idx)) * 2.6    # 分胜负的一瞬间猛地一扭
	# 分出胜负后镜头马上交还（原来还要在侧面机位停 0.7 秒再慢慢退，看着像卡住）
	_cine_dur = _cine_t + 0.15
	_cine_out = 0.15
	var cam := player.cam
	cam.impact(1.0)
	cam.add_trauma(0.7)
	Sfx.play("slam", 0.0, 0.9)
	if win:
		var dmg := _base() * 5.0
		var dir := (_beam_dir + Vector3.UP * 0.12).normalized()
		if not netfoe:      # 对手是真人时，他那边会按「输」自己结算（挨一下、被轰飞），这里不重复打
			foe.air_hit(player, {"dmg": dmg, "dir": dir, "kb": 46.0, "stun": 1.0, "launch": "fwd", "heavy": true,
					"contact": Proj.aim_of(foe)})
		_add_combo(dmg)
		Vfx.fire_explode(Proj.aim_of(foe), dir, true)
		Vfx.shockwave(Proj.aim_of(foe), dir, _col(), 3.0)
		# 破阵：剩下的剑流一拥而上
		for i in 10:
			var fm: Array = player.caster._form(i, Proj.aim_of(foe))
			Proj.launch(player, Proj.K.SWORD, fm[0], foe, Proj.aim_of(foe), {"dmg": _base() * 0.15, "color": fm[1], "speed": 110.0,
					"hold": 0.02 * float(i), "turn": 18.0, "light": true, "lite": true, "sfx": i % 4 == 0, "trauma": 0.01, "life": 1.2})
		if _is_launched(foe):
			_launched = foe
			_launch_kind = "fwd"
			_chase_n = 0
		cam.fov_punch(12.0)
		player.melee.combat_event.emit("air_clash_end", {"win": true, "pos": Proj.aim_of(foe)})
		_to_idle()
	else:
		player.melee.combat_event.emit("air_clash_end", {"win": false, "pos": player.center()})
		Vfx.fire_explode(player.center(), -_beam_dir, true)
		_hurt(foe, {"dmg": 28.0, "kb": 30.0, "contact": player.center()}, (-_beam_dir + Vector3.UP * 0.1).normalized(), true)


# ---------- 聚气 / 觉醒 ----------

func _tick_gather(dt: float, held: bool) -> void:
	_drives = true
	_face_target()
	player.mp = minf(player.mp + GATHER_MP * dt, player.mp_max())
	if awake_t <= 0.0:
		awaken = minf(awaken + 7.0 * dt, 100.0)
	_aura_t -= dt
	if _aura_t <= 0.0:
		_aura_t = 0.1
		Vfx.ribbon_burst(player.global_position + Vector3(0.0, 0.2, 0.0), Vector3.UP, _col(), 6, 11.0, 28.0, 0.4, Vector3.ZERO)
	player.cam.add_trauma(0.015)
	player.hero.set_glow(0.14, _col())
	if awaken >= 100.0 and player.mp >= player.mp_max() * 0.6 and awake_t <= 0.0:
		_awaken()
	elif not held:
		_to_idle()


## 觉醒：气浪震开身边的对手，一段时间内伤害提高、追击不耗灵力、对波更有力
func _awaken() -> void:
	awaken = 0.0
	awake_t = AWAKE_DUR
	_to_idle()
	var c := player.center()
	var col := _col()
	Combat.slowmo(0.2, 0.3, 0.45)
	Vfx.breakthrough(player.global_position, col, 1.0)
	Vfx.shockwave(c, Vector3.UP, col, 3.2)
	Vfx.shockwave(c, Vector3.FORWARD, Color.WHITE.lerp(col, 0.4), 2.4)
	Sfx.play("ascend", -2.0, 1.2)
	Sfx.play("slam", -4.0, 1.5)
	var cam := player.cam
	cam.impact(0.8)
	cam.fov_punch(10.0)
	cam.add_trauma(0.5)
	for e in Proj.targets(player.get_tree()):
		var d := Proj.aim_of(e) - c
		if d.length() < 7.0 + Proj.body_r(e) and e.has_method("air_hit"):
			e.air_hit(player, {"dmg": _base() * 0.5, "dir": d.normalized() if d.length_squared() > 0.01 else _fwd(),
					"kb": 18.0, "stun": 0.8, "launch": "", "heavy": true, "contact": Proj.aim_of(e)})
	player.melee.combat_event.emit("air_awaken", {})


# ---------- 自己被砸到地面 ----------

func _on_floor() -> bool:
	if player.global_position.y <= 0.03:
		return true
	for i in player.get_slide_collision_count():
		if player.get_slide_collision(i).get_normal().y > 0.7:
			return true
	return false


func _crash_ground() -> void:
	var pos := player.global_position
	var power := clampf(_push.length() / 30.0, 0.8, 1.5)
	var m := player.melee
	m.hp = maxf(m.hp - 8.0, 0.0)
	Vfx.dun_slam(pos, Color(1.0, 0.85, 0.7), power)
	Vfx.crater(pos, power)
	Combat.hitstop(0.1, 0.0)
	Sfx.play("slam", -1.0, 0.8)
	Sfx.play("thud", -2.0, 0.6)
	var cam := player.cam
	cam.add_trauma(0.65)
	cam.impact(0.6)
	state = A.DOWN
	_t = 0.0
	_dur = 0.8
	_push = Vector3.ZERO
	_tumble = 0.0
	player.velocity = Vector3.ZERO
	player.melee.combat_event.emit("air_crash", {"pos": pos, "ground": true, "spd": 30.0})
