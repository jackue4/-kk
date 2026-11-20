extends Node
## 主角近战（手感参考只狼）：三段连招 / 点按弹反 / 按住格挡 / 架势 / 破防处决，外加一套短循环空战。
## · 地面：J/左键 三段连招（为手机端精简：不再有"按住格挡 + 攻击"上挑、"Ctrl + 攻击"下砸这类组合键）。
## · 空中（普通跳跃）：J/左键 空中斩，每次离地最多两段；K/右键 空中也能点按弹反（窗口略宽）。
## · 起飞（御剑、遁光）立即收剑退出——遁光里不挥剑；落地后再按攻击/格挡或靠近刀客重新拔剑。
## · 攻击一旦挥出即"承诺"：只能在起手很早（early 之前）或收势之后（late 之后）用格挡/弹反取消。
## · 顿帧只冻结战斗相关对象（Combat.cdt），世界其它部分照常走；输入不冻结——顿帧里按下的攻击照样进缓冲。
## · 闪避（地面短按 Shift）：出招命中判定之后、起手很早、格挡/弹开后都能闪避取消；闪避全程无敌。
##   闪避后 1s 内的下一次攻击会瞬移到敌人身边出手，连段段数接着闪避前的往下走（一段→闪→二段→闪→三段）；
##   刀客判定帧正好落在闪避开始后的一小段里 = 完美闪避：画面骤慢再加速，下一刀瞬移到它侧后方，伤害/削架势加成。
## 由 Player 在 _process 开头调 tick()，在 hero.animate() 之后调 post_animate()，保证同帧顺序确定。

signal combat_event(kind: String, info: Dictionary)

const Rig := preload("res://scripts/fighter_rig.gd")
const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Poses := preload("res://scripts/combat_poses.gd")
const Arc := preload("res://scripts/slash_arc.gd")

enum M { SHEATHED, READY, ATTACK, GUARD, DEFLECT, BLOCKED, RECOIL, HURT, BROKEN, EXECUTE, DOWN }

const HP_MAX := 100.0
const POSTURE_MAX := 100.0
const PARRY_WIN := 0.2        # 弹反窗口（战斗时间）
const PARRY_WIN_AIR := 0.24   # 空中弹反窗口略宽
const PARRY_WIN_SPAM := 0.1   # 0.35s 内连按：窗口减半，防止无脑狂按
const ENGAGE_R := 8.0         # 刀客进入这个距离自动拔剑
const LOCK_R := 4.8           # 轻度锁定：出招/格挡时自动转向目标的距离
const SWORD_SCALE := 1.0      # 近战持剑比上一版（0.85）大一圈；飞剑巡航的剑是另外的节点，不受影响
const BUFFER := 0.22          # 攻击输入缓冲（真实时间秒）：顿帧中、出招前段按下的攻击都不会丢
const AIR_SLASH_MAX := 2      # 每次离地最多两段空中斩
const WARP_R := 9.0           # 闪避后瞬移斩能够到的最远敌人
const WARP_MIN := 1.7         # 已经贴身就不瞬移，直接出刀
const WARP_WIN := 1.0         # 闪避后多久内的攻击会瞬移（战斗时间；慢动作中自然变长）
const WARP_GAP := 1.3         # 瞬移落点离敌人的距离
const CARRY_WIN := 1.2        # 闪避取消后，这么久内再出刀接着原来的段数

## 招式表。时间都是招式内的战斗时间（秒）
## kind: ground 地面连招 / air 空中斩 | tier 反馈档位 0 轻 1 重 | next 连段下一招
## swing 挥刀声 | hit 判定 | trail 剑光区间 | open 起可预输入下一段 | chain 最早接下一段 | close 过时不候（收招）
## end 回到戒备 | early/late 允许格挡取消：起手 early 之前、收势 late 之后 | lunge (起, 止, 最大踏步距离)
## reach 判定距离 | cone 正前方夹角余弦 | vreach 上下判定高度差 | stop 命中顿帧 | kb 击退 | dmg 伤害 | pst 削架势
## trauma/push 镜头
const AIR_FIRST := 3  # 空中斩在招式表里的起始下标
const ATK := [
	{"name": "起手·斜斩", "seq": "a1", "kind": "ground", "tier": 0, "next": 1,
	 "swing": 0.075, "hit": 0.14, "trail": Vector2(0.075, 0.25),
	 "open": 0.05, "chain": 0.22, "close": 0.48, "end": 0.6, "early": 0.06, "late": 0.24,
	 "lunge": Vector3(0.04, 0.15, 0.95), "reach": 2.4, "cone": 0.25, "vreach": 1.3, "stop": 0.065, "kb": 2.0,
	 "dmg": 9.0, "pst": 10.0, "trauma": 0.24, "push": 0.04},
	{"name": "二段·回身横斩", "seq": "a2", "kind": "ground", "tier": 0, "next": 2,
	 "swing": 0.065, "hit": 0.125, "trail": Vector2(0.065, 0.24),
	 "open": 0.05, "chain": 0.22, "close": 0.48, "end": 0.64, "early": 0.05, "late": 0.24,
	 "lunge": Vector3(0.03, 0.14, 1.0), "reach": 2.45, "cone": 0.25, "vreach": 1.3, "stop": 0.075, "kb": 2.6,
	 "dmg": 11.0, "pst": 14.0, "trauma": 0.28, "push": 0.05},
	{"name": "三段·跃斩下劈", "seq": "a3", "kind": "ground", "tier": 1, "next": 0,
	 "swing": 0.32, "hit": 0.385, "trail": Vector2(0.29, 0.46),
	 "open": 0.75, "chain": 0.9, "close": 1.1, "end": 1.34, "early": 0.1, "late": 0.62,
	 "lunge": Vector3(0.16, 0.39, 1.3), "reach": 2.6, "cone": 0.2, "vreach": 1.3, "stop": 0.12, "kb": 4.5,
	 "dmg": 17.0, "pst": 24.0, "trauma": 0.42, "push": 0.085},
	{"name": "空中·横斩", "seq": "r1", "kind": "air", "tier": 0, "next": 4,
	 "swing": 0.06, "hit": 0.115, "trail": Vector2(0.06, 0.22),
	 "open": 0.04, "chain": 0.2, "close": 0.42, "end": 0.52, "early": 0.05, "late": 0.22,
	 "lunge": Vector3(0.02, 0.12, 0.9), "reach": 2.35, "cone": 0.2, "vreach": 1.7, "stop": 0.07, "kb": 1.4,
	 "dmg": 8.0, "pst": 9.0, "trauma": 0.22, "push": 0.04},
	{"name": "空中·回旋斩", "seq": "r2", "kind": "air", "tier": 0, "next": -1,
	 "swing": 0.06, "hit": 0.12, "trail": Vector2(0.06, 0.23),
	 "open": 0.04, "chain": 0.2, "close": 0.44, "end": 0.55, "early": 0.05, "late": 0.24,
	 "lunge": Vector3(0.02, 0.12, 0.9), "reach": 2.35, "cone": 0.2, "vreach": 1.7, "stop": 0.08, "kb": 1.6,
	 "dmg": 9.0, "pst": 11.0, "trauma": 0.24, "push": 0.045},
]
const DEBRIS_N := [7, 12, 16]
const DEBRIS_SPD := [4.5, 6.0, 6.5]
const DEBRIS_SIZE := [1.0, 1.15, 1.2]

var player: Player
var rig: Rig
var sword: Node3D
var state := M.SHEATHED
var hp := HP_MAX
var posture := 0.0
var target: Node3D = null      # 当前目标（刀客）
var drive_vel := Vector3.ZERO  # 出招踏步 / 受击滑退，由 Player 用来覆盖移动
var has_face := false
var face_yaw := 0.0
var guard_held := false
var step := 0
## 本帧由招式接管竖直速度（空斩悬停、空中弹反弹起），Player._ground 读取
var vy_set := false
var vy := 0.0
var grav_mul := 1.0

var _t := 0.0
var _clock := 0.0
var _atk: Dictionary = ATK[0]
var _hit_done := false
var _swung := false
var _queued := false
var _landed_hit := false
var _whiff := false
var _buf_at := -10.0
var _parry_at := -10.0
var _parry_win := PARRY_WIN
var _last_press := -10.0
var _pst_at := -10.0
var _calm := 0.0
var _state_dur := 0.0
var _lunge_dir := Vector3.FORWARD
var _lunge_spd := 0.0
var _push_v := Vector3.ZERO
var _tip_prev := Vector3.ZERO
var _tip_dir := Vector3.RIGHT
var _trails: Array[Trail3D] = []
var _arc: Arc
var _blade_mesh: Mesh
var _ghost_t := 0.0
var _victim: Node3D = null
var _exec_hit := false
var _air_slashes := 0
var _was_air := false
var _kick := false
var _pop := 0.0
var _flash := 0.0
var _warp_until := -10.0
var _warp_tgt: Node3D = null
var _warp_perfect := false
var _warp_side := 1.0
var _bonus := false            # 本招是完美闪避后的瞬移斩：伤害、削架势、反馈加成
var _carry := 0
var _carry_until := -10.0


func _ready() -> void:
	sword = MeshLib.make_sword(Realm.line_color(player.realm))
	rig = Rig.new(player.hero, sword, SWORD_SCALE, -0.375, 0.72)
	sword.visible = false
	_blade_mesh = (sword.get_child(0) as MeshInstance3D).mesh
	# 刀刃拖尾 = 一整条贴图刀光（fx/blade_trail/blade_trail.png：中间亮、两边墨色和碎点），
	# 不再叠程序画的细线拖尾（_trails 留空，相关循环照旧是空转）。
	# 弧带从剑身 0.42 铺到剑尖外 0.12：贴图的亮芯落在靠剑尖那一段，上下的碎点有地方放
	var c := _col()
	_arc = Arc.new()
	_arc.lifetime = 0.22
	_arc.inner_fn = rig.blade_point.bind(0.42)
	_arc.outer_fn = rig.blade_point.bind(1.12)
	_arc.material_override = Arc.make_tex_material(c)
	player.vfx_root.add_child(_arc)
	player.realm_changed.connect(_on_realm)


func _exit_tree() -> void:
	for t in _trails:
		if is_instance_valid(t):
			t.queue_free()
	if is_instance_valid(_arc):
		_arc.queue_free()


func _on_realm(_idx: int) -> void:
	var c := Realm.line_color(player.realm)
	(sword.get_meta("blade_mat") as StandardMaterial3D).emission = c
	for t in _trails:
		var m := t.material_override as ShaderMaterial
		m.set_shader_parameter("color_a", Color.WHITE.lerp(c, 0.25))
		m.set_shader_parameter("color_b", c)
	_arc.set_colors(Color.WHITE.lerp(c, 0.2), c)


func _col() -> Color:
	return Realm.line_color(player.realm)


# ---------- 查询 ----------

func engaged() -> bool:
	return state != M.SHEATHED


func busy() -> bool:
	return state != M.SHEATHED and state != M.READY and state != M.GUARD


## 移动倍率：出招/受击/破防/处决时完全交给 drive_vel；格挡中慢走
func move_mul() -> float:
	match state:
		M.SHEATHED, M.READY:
			return 1.0
		M.GUARD:
			return 0.45
	return 0.0


func drives_motion() -> bool:
	return busy()


## 出招 / 受击中不能起跳
func can_jump() -> bool:
	return not busy()


func on_jump() -> void:
	if state == M.ATTACK:
		_to_ready()


## 能否闪避：闪避优先级最高——出招任何阶段（起手、判定前、收势）、格挡、弹反 / 被格挡、被弹开、受击、
## 架势崩溃都能立刻闪开。只有倒地，以及处决出刀之前（对方已被锁进处决动作）不行
func can_dodge() -> bool:
	match state:
		M.DOWN:
			return false
		M.EXECUTE:
			return _exec_hit
	return true


## 闪避开始（Player.blink 调用）：收掉当前动作，记住连段段数，打开"下一刀瞬移"的窗口。
## 判定前被打断的招式不算出过：之后接回同一段；判定后打断则接下一段
func on_dodge() -> void:
	if state == M.ATTACK and _atk["kind"] == "ground":
		_carry = int(_atk["next"]) if _hit_done else step
		_carry_until = _clock + CARRY_WIN
	elif state == M.BROKEN:
		posture = POSTURE_MAX * 0.3  # 闪出架势崩溃：和自然恢复一样回落到三成，免得下一下又崩
	elif state == M.EXECUTE:
		_victim = null
	_warp_until = _clock + WARP_WIN + Player.DODGE_DIST / Player.DODGE_SPD
	_warp_tgt = null
	_warp_perfect = false
	_buf_at = -10.0
	_queued = false
	Combat.clear_hitstop()
	if busy():
		_to_ready()


## 完美闪避：锁定躲开的那个敌人，窗口从现在重新算
func arm_warp(src: Node3D, perfect: bool) -> void:
	_warp_tgt = src
	_warp_perfect = perfect
	_warp_until = _clock + WARP_WIN
	if perfect:
		combat_event.emit("perfect_dodge", {})


func hp_ratio() -> float:
	return hp / HP_MAX


func posture_ratio() -> float:
	return posture / POSTURE_MAX


func state_name() -> String:
	match state:
		M.ATTACK:
			return _atk["name"]
		M.GUARD:
			return "格挡"
		M.DEFLECT:
			return "弹反"
		M.BLOCKED:
			return "格挡"
		M.RECOIL:
			return "被弹开"
		M.HURT:
			return "受击"
		M.BROKEN:
			return "架势崩溃"
		M.EXECUTE:
			return "处决"
		M.DOWN:
			return "倒地"
		M.READY:
			return "空中戒备" if airborne() else "戒备"
	return ""


## 演示/调试：当前招式内时间
func attack_time() -> float:
	return _t if state == M.ATTACK else -1.0


## 普通跳跃离地（不含御剑、遁光）
func airborne() -> bool:
	return _grounded() and not player.is_on_floor()


## 相机用：持剑且在空中
func air_combat() -> bool:
	return state != M.SHEATHED and airborne()


func _forward() -> Vector3:
	return Basis(Vector3.UP, player.visual.rotation.y) * Vector3.FORWARD


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _now() -> float:
	return Combat.now()


func _grounded() -> bool:
	return player.st == Player.St.GROUND


func _input_dir() -> Vector3:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return Basis(Vector3.UP, player.cam.yaw) * Vector3(iv.x, 0.0, iv.y)


# ---------- 输入 ----------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return  # 这一下是用来抓鼠标的
	if player.ult.active and not e.is_action_released("guard"):
		return  # R 大罡剑阵演出中不出招（松开格挡照常处理，免得卡在格挡）
	if e.is_action_pressed("attack"):
		press_attack()
	elif e.is_action_pressed("guard"):
		press_guard()
	elif e.is_action_released("guard"):
		release_guard()


## 攻击键：先记进缓冲，能出就立刻出；不能出（顿帧中、出招前段）就留给 tick 在缓冲期内再试
## 结丹起不再用地面这套刀剑近战（它只留给炼气 / 筑基）：在地上按攻击 / 格挡，直接腾空进入空战，这一下按键交给空战处理
func _to_air_combat() -> bool:
	if not player.is_light_mode() or (player.st != Player.St.GROUND and player.st != Player.St.FLY):
		return false
	return player.enter_air_combat()


func press_attack() -> void:
	if _to_air_combat():
		player.air.press_from_ground(true)
		return
	if not _grounded():
		return
	if player.is_dashing():
		player.stop_dash()  # 闪避途中按攻击：立刻收住，直接接瞬移斩
	_buf_at = _now()
	if _consume_attack():
		_buf_at = -10.0


func _consume_attack() -> bool:
	match state:
		M.SHEATHED, M.READY, M.GUARD:
			_begin_attack()
			return true
		M.ATTACK:
			if int(_atk["next"]) >= 0 and _t >= float(_atk["open"]) and _t < float(_atk["close"]):
				_queued = true
				return true
		M.DEFLECT, M.BLOCKED:
			if _t >= 0.05:
				_begin_attack()
				return true
	return false


## 起手选招：空中 → 空斩（每次离地最多两段）；地面 → 处决 > 一段（闪避取消后接原段数）
func _begin_attack() -> void:
	if airborne():
		if _air_slashes < AIR_SLASH_MAX:
			_start_attack(AIR_FIRST + _air_slashes)
		return
	var warped := _try_warp()
	if _try_execute():
		return
	var s := 0
	if _clock < _carry_until:
		s = _carry
	_carry_until = -10.0
	_start_attack(s)
	_bonus = warped and _warp_perfect
	_warp_perfect = false


## 闪避窗口内出刀：瞬移到敌人身边（完美闪避绕到侧后方），返回是否瞬移了
func _try_warp() -> bool:
	if _clock > _warp_until:
		return false
	_warp_until = -10.0
	var e := _warp_tgt
	if e == null or not is_instance_valid(e) or not e.is_alive():
		e = null
		var bd := WARP_R
		for n in get_tree().get_nodes_in_group("swordsmen"):
			var c := n as Node3D
			if not c.is_alive():
				continue
			var dd := _flat(c.global_position - player.global_position).length()
			if dd < bd:
				bd = dd
				e = c
	if e == null or e.is_airborne():
		return false
	var d := _flat(player.global_position - e.global_position)
	var dl := d.length()
	if dl > WARP_R + 2.0:
		return false
	if dl < WARP_MIN:
		target = e
		return _warp_perfect  # 贴身完美闪避：不用挪，也照样算反击
	var away := d / dl if dl > 0.01 else -_forward()
	_warp_side = -_warp_side
	var ang := (2.0 if _warp_perfect else 0.55) * _warp_side
	var spot := _free_spot(e.global_position, [away.rotated(Vector3.UP, ang), away.rotated(Vector3.UP, -ang), away])
	var to_e := _flat(e.global_position - spot)
	player.warp_to(spot, atan2(-to_e.x, -to_e.z))
	face_yaw = atan2(-to_e.x, -to_e.z)
	has_face = true
	target = e
	Combat.slowmo_release(0.2)
	combat_event.emit("warp", {"perfect": _warp_perfect})
	return true


## 敌人身边按候选方向依次找一个不和场景重叠的落点（胶囊体检测），都不行就退回正对的方向
func _free_spot(center_pos: Vector3, dirs: Array) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	q.shape = cap
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	for dv: Vector3 in dirs:
		var p := Vector3(center_pos.x, player.global_position.y, center_pos.z) + dv * WARP_GAP
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.9, 0.0))
		if space.intersect_shape(q, 1).is_empty():
			return p
	return Vector3(center_pos.x, player.global_position.y, center_pos.z) + (dirs[dirs.size() - 1] as Vector3) * WARP_GAP


func press_guard() -> void:
	if _to_air_combat():
		player.air.press_from_ground(false)
		return
	guard_held = true
	if not _grounded():
		return
	var ok := false
	match state:
		M.SHEATHED, M.READY, M.GUARD, M.DEFLECT, M.BLOCKED:
			ok = true
		M.ATTACK:
			ok = _cancelable()
		M.RECOIL:
			ok = _t >= 0.2
	if not ok:
		return
	if _clock - _last_press < 0.35:
		_parry_win = PARRY_WIN_SPAM
	else:
		_parry_win = PARRY_WIN_AIR if airborne() else PARRY_WIN
	_last_press = _clock
	_parry_at = _clock
	_engage(false)
	if state != M.DEFLECT and state != M.BLOCKED:
		_enter(M.GUARD)
		rig.play("guard")


func release_guard() -> void:
	guard_held = false
	if state == M.GUARD:
		_to_ready()


func _cancelable() -> bool:
	return _t < float(_atk["early"]) or _t >= float(_atk["late"])


# ---------- 状态 ----------

func _enter(s: M) -> void:
	state = s
	_t = 0.0


func _to_ready() -> void:
	if guard_held and _grounded():
		_enter(M.GUARD)
		rig.play("guard")
		return
	_enter(M.READY)
	rig.play("air_idle" if airborne() else "stance")


func _engage(with_draw := true) -> void:
	if state != M.SHEATHED:
		return
	_enter(M.READY)
	_calm = 0.0
	sword.visible = true
	sword.scale = Vector3.ONE * SWORD_SCALE
	if with_draw:
		rig.play("draw")
	Vfx.glint(rig.tip_pos(), Color.WHITE.lerp(_col(), 0.4), 0.5)


## 复活（Player.revive 调）：气血、架势回满，从倒地里起来
func revive() -> void:
	hp = HP_MAX
	posture = 0.0
	if state == M.DOWN:
		Vfx.reappear(player.center(), _col())
		_to_ready()


func sheathe() -> void:
	if state == M.SHEATHED:
		return
	_enter(M.SHEATHED)
	sword.visible = false
	has_face = false
	drive_vel = Vector3.ZERO
	_push_v = Vector3.ZERO
	guard_held = false
	for t in _trails:
		t.emitting = false
		t.clear()
	_arc.emitting = false
	_arc.clear()


## 空战（air_melee.gd）借用手中剑：掣剑横斩那一下亮出剑身和刀光，收招即隐去
func air_blade(on: bool) -> void:
	if sword.visible == on:
		return
	sword.visible = on
	sword.scale = Vector3.ONE * SWORD_SCALE
	_arc.emitting = on
	if on:
		_arc.clear()


func _start_attack(s: int) -> void:
	_engage(false)
	step = s
	_atk = ATK[s]
	_enter(M.ATTACK)
	_bonus = false
	_hit_done = false
	_swung = false
	_queued = false
	_landed_hit = false
	_whiff = false
	_ghost_t = 0.0
	var kind: String = _atk["kind"]
	if kind == "air":
		_air_slashes += 1
	_kick = kind == "air"
	rig.play(_atk["seq"])
	# 轻度锁定：近处有目标就转向它，并按距离决定踏步长度；没有目标就按输入方向出招
	var fwd := _forward()
	var go := 0.35
	var lg: Vector3 = _atk["lunge"]
	var tg := _lock_target(LOCK_R)
	if tg != null:
		var d := _flat(tg.global_position - player.global_position)
		var dl := d.length()
		if dl > 0.05:
			fwd = d / dl
		go = clampf(dl - 1.45, 0.0, lg.z)
	else:
		var idir := _input_dir()
		if idir.length() > 0.3:
			fwd = idir.normalized()
	face_yaw = atan2(-fwd.x, -fwd.z)
	has_face = true
	_lunge_dir = fwd
	_lunge_spd = go / maxf(lg.y - lg.x, 0.01)


func _lock_target(r: float) -> Node3D:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return null
	if _flat(target.global_position - player.global_position).length() > r:
		return null
	return target


## 索敌：先找最近 3 秒内打中过自己的（正在打我的），再找最近的
func _pick_target() -> void:
	var best: Node3D = null
	var bd := INF
	var best_hot := false
	var now := Combat.now()
	for n in get_tree().get_nodes_in_group("swordsmen"):
		var e := n as Node3D
		if not e.is_alive():
			continue
		var hot: bool = player.threat.has(e) and now - float(player.threat[e]) <= 3.0
		var d := _flat(e.global_position - player.global_position).length()
		if d > (ENGAGE_R + 3.0) * (1.3 if hot else 1.0):
			continue
		if e == target:
			d -= 1.0  # 粘一点，避免两个目标间来回跳
		if (hot and not best_hot) or (hot == best_hot and d < bd):
			bd = d
			best = e
			best_hot = hot
	target = best


# ---------- 每帧 ----------

func tick(dt: float) -> void:
	vy_set = false
	grav_mul = 1.0
	var cdt := Combat.cdt(dt)
	_clock += cdt
	if not _grounded():
		if state != M.SHEATHED:
			sheathe()
		rig.w_up_target = 0.0
		rig.w_leg_target = 0.0
		_was_air = false
		_t += cdt
		_arc.time_scale = Combat.time_scale()  # 空战借剑时（air_blade）刀光照样跟顿帧
		return
	var air := airborne()
	if not air:
		_air_slashes = 0
	if air != _was_air and state == M.READY:
		rig.play("air_idle" if air else "stance")
	_was_air = air
	# 招式节奏：命中后多停一拍把力传出去；挥空则更快收回
	if state == M.ATTACK and _hit_done:
		var since := _t - float(_atk["hit"])
		if _landed_hit and since < 0.07:
			cdt *= 0.5
		elif _whiff:
			cdt *= 1.4
	_t += cdt
	_pick_target()
	drive_vel = Vector3.ZERO
	_push_v = _push_v.move_toward(Vector3.ZERO, 10.0 * cdt)
	if _pop > 0.0:
		vy_set = true
		vy = _pop
		_pop = 0.0
	if _buf_at > 0.0:
		if _now() - _buf_at > BUFFER:
			_buf_at = -10.0
		elif _consume_attack():
			_buf_at = -10.0

	match state:
		M.SHEATHED:
			has_face = false
			var tg := _lock_target(ENGAGE_R)
			if tg != null and tg.is_hostile():
				_engage()
		M.READY:
			_tick_ready(dt)
		M.ATTACK:
			_tick_attack()
		M.GUARD:
			_face_target(6.0)
		M.DEFLECT, M.BLOCKED:
			drive_vel = _push_v
			if _t >= _state_dur:
				_to_ready()
		M.RECOIL, M.HURT:
			drive_vel = _push_v
			if _t >= _state_dur:
				_to_ready()
		M.BROKEN:
			drive_vel = _push_v
			if _t >= _state_dur:
				posture = POSTURE_MAX * 0.3
				_to_ready()
		M.EXECUTE:
			_tick_execute()
		M.DOWN:
			# 倒地 = 陨落：就这么躺着，等 Player.revive()（大厅里由 main.gd 送回出生点时调）
			if not player.dead and _t >= 0.3:
				revive()

	# 架势自然回复：一段时间没有新的架势伤害后开始回落，格挡姿态下回得更快
	if state != M.BROKEN and state != M.DOWN and _clock - _pst_at > 0.9:
		posture = maxf(posture - (24.0 if state == M.GUARD else 14.0) * cdt, 0.0)

	rig.update(cdt)
	var moving := _flat(player.velocity).length() > 0.8
	var loose := (state == M.READY or state == M.GUARD) and (moving or airborne())
	rig.w_up_target = 1.0 if state != M.SHEATHED else 0.0
	rig.w_leg_target = 0.0 if state == M.SHEATHED or loose else 1.0

	var on := false
	if state == M.ATTACK:
		var tr: Vector2 = _atk["trail"]
		on = _t >= tr.x and _t <= tr.y
	elif state == M.EXECUTE:
		on = (_t >= 0.12 and _t <= 0.3) or (_t >= 0.6 and _t <= 0.82)
	for t in _trails:
		t.emitting = on
		t.time_scale = Combat.time_scale()
	_arc.emitting = on
	_arc.time_scale = Combat.time_scale()
	# 挥砍途中每隔一小段留一道很淡的剑身残影（顿帧时 cdt≈0，自然不再生成）
	if on and sword.visible:
		_ghost_t += cdt
		if _ghost_t >= 0.028:
			_ghost_t = 0.0
			Vfx.blade_ghost((sword.get_child(0) as Node3D).global_transform, _blade_mesh, Color.WHITE.lerp(_col(), 0.45))
	_flash = maxf(_flash - dt * 7.0, 0.0)
	player.hero.set_flash(_flash)


func _tick_ready(dt: float) -> void:
	var tg := _lock_target(ENGAGE_R)
	_calm = 0.0 if tg != null else _calm + dt
	if _calm > 4.0:
		sheathe()
		return
	has_face = false
	if _input_dir().length() < 0.2:
		_face_target(LOCK_R)


func _face_target(r: float) -> void:
	var tg := _lock_target(r)
	if tg == null:
		has_face = false
		return
	var d := _flat(tg.global_position - player.global_position)
	if d.length_squared() > 0.01:
		face_yaw = atan2(-d.x, -d.z)
		has_face = true


func _tick_attack() -> void:
	var a := _atk
	var kind: String = a["kind"]
	if kind == "air" and not airborne() and _t > 0.05:
		_to_ready()  # 空斩中落地：直接收招
		return
	var lg: Vector3 = a["lunge"]
	if _t >= lg.x and _t < lg.y:
		drive_vel = _lunge_dir * _lunge_spd
	if not _hit_done:
		var tg := _lock_target(LOCK_R)
		if tg != null:
			var d := _flat(tg.global_position - player.global_position)
			if d.length_squared() > 0.01:
				face_yaw = atan2(-d.x, -d.z)
	if kind == "air":
		_air_hold()
	if not _swung and _t >= float(a["swing"]):
		_swung = true
		var heavy := int(a["tier"]) >= 1
		var pitch := 1.0 + 0.07 * step
		if kind == "air":
			pitch = 1.12 + 0.06 * (step - AIR_FIRST)
		Sfx.play("swing_heavy" if heavy else "swing", -5.0, pitch)
	if not _hit_done and _t >= float(a["hit"]):
		_hit_done = true
		_resolve_hit()
		if state != M.ATTACK:
			return
	var nx := int(a["next"])
	if _queued and nx >= 0 and _t >= float(a["chain"]):
		_start_attack(nx)
	elif _t >= float(a["end"]):
		_to_ready()


## 空斩：起手抵消下落、短暂悬停；目标浮空时把高度往它身上吸，目标在地面而自己太高时往下扑，保证刀能接上
func _air_hold() -> void:
	if _kick:
		_kick = false
		vy_set = true
		vy = maxf(player.velocity.y * 0.25, 1.0)
		return
	if _t < float(_atk["hit"]) + 0.12:
		var tg := _lock_target(LOCK_R)
		var dy := 0.0
		if tg != null:
			dy = tg.global_position.y + (0.0 if tg.is_airborne() else 0.8) - player.global_position.y
		if tg != null and (tg.is_airborne() or dy < -0.3):
			vy_set = true
			vy = clampf(dy * 7.0, -8.0, 4.0)
		else:
			grav_mul = 0.12
	else:
		grav_mul = 0.55


func _tick_execute() -> void:
	if _victim == null or not is_instance_valid(_victim):
		_to_ready()
		return
	var d := _flat(_victim.global_position - player.global_position)
	var dl := maxf(d.length(), 0.01)
	var dir := d / dl
	face_yaw = atan2(-dir.x, -dir.z)
	has_face = true
	if _t < 0.2:
		drive_vel = dir * clampf((dl - 1.0) / 0.12, 0.0, 14.0)
	if not _exec_hit and _t >= 0.2:
		_exec_hit = true
		var c := _victim.global_position + Vector3(0.0, 1.0, 0.0) - dir * 0.15
		_victim.deathblow_hit(dir)
		Vfx.deathblow(c, dir)
		Vfx.impact(c, dir.cross(Vector3.UP), Color(0.95, 0.2, 0.16), 3)
		Vfx.debris(c, dir + Vector3.UP * 0.3, _victim.chip_colors(), 20, 6.5, 1.25)
		Combat.hitstop(0.18, 0.02)
		Sfx.play("execute", 1.0)
		player.cam.add_trauma(0.5)
		player.cam.push_in(0.12)
		combat_event.emit("execute", {"pos": c})
	if _t >= 1.45:
		_victim = null
		_to_ready()


func post_animate(dt: float) -> void:
	rig.apply(dt)
	if not sword.visible:
		return
	var tip := rig.tip_pos()
	var mv := tip - _tip_prev
	if mv.length_squared() > 1e-6:
		_tip_dir = mv.normalized()
	_tip_prev = tip


# ---------- 出招结算 ----------

func _hit_info(e: Node3D, dir: Vector3) -> Dictionary:
	var a := _atk
	var k := 1.6 if _bonus else 1.0
	return {"dmg": float(a["dmg"]) * k, "pst": float(a["pst"]) * (2.0 if _bonus else 1.0), "kb": a["kb"], "dir": dir,
			"step": step, "heavy": int(a["tier"]) >= 1 or _bonus, "contact": _contact_on(e),
			"air": a["kind"] == "air", "swing": _tip_dir,
			"stop": float(a["stop"]), "unblockable": _bonus}


func _resolve_hit() -> void:
	var a := _atk
	var fwd := _forward()
	var any := false
	for n in get_tree().get_nodes_in_group("swordsmen"):
		var e := n as Node3D
		if not e.is_alive():
			continue
		var d := _flat(e.global_position - player.global_position)
		var dl := d.length()
		if dl > float(a["reach"]) + 0.35:
			continue
		if dl > 0.3 and fwd.dot(d / dl) < float(a["cone"]):
			continue
		if absf(e.global_position.y - player.global_position.y) > float(a["vreach"]):
			continue
		var info := _hit_info(e, fwd)
		var c: Vector3 = info["contact"]
		var res: int = e.receive_hit(player, info)
		match res:
			0:
				_fx_hit(c, e)
			1:
				_fx_enemy_block(c, fwd)
			2:
				_fx_enemy_deflect(c, fwd)
		if res >= 0:
			any = true
	if not any:
		_whiff = true  # 挥空：没有顿帧、没有火星，只有剑光，收招更快
		combat_event.emit("whiff", {"step": step})


## 剑刃与对方身体（竖直轴）最近处，作为命中点
func _contact_on(e: Node3D) -> Vector3:
	var hand := rig.hand_pos()
	var tip := rig.tip_pos()
	var a0 := e.global_position + Vector3(0.0, 0.5, 0.0)
	var a1 := e.global_position + Vector3(0.0, 1.55, 0.0)
	var pts := Geometry3D.get_closest_points_between_segments(hand, tip, a0, a1)
	var on_blade: Vector3 = pts[0]
	var on_body: Vector3 = pts[1]
	var off := on_blade - on_body
	if off.length() > 0.35:
		return on_body + off.normalized() * 0.3
	return on_blade.lerp(on_body, 0.4)


## 命中反馈，按顺序叠：顿帧 → 命中音 →（对方自己闪白、摆受击姿势）→ 刀光/冲击/火星 → 碎块 → 镜头
func _fx_hit(c: Vector3, e: Node3D) -> void:
	var a := _atk
	var heavy := int(a["tier"]) >= 1 or _bonus
	Combat.hitstop(float(a["stop"]) + (0.06 if _bonus else 0.0), 0.02 if heavy else 0.04)
	Sfx.play("hit_heavy" if heavy else "hit", 0.0 if heavy else -1.0)
	_fx_layers(c, e, maxi(int(a["tier"]), 1) if _bonus else int(a["tier"]))
	player.cam.add_trauma(float(a["trauma"]) + (0.15 if _bonus else 0.0))
	player.cam.push_in(float(a["push"]) + (0.04 if _bonus else 0.0))
	if _bonus:
		Vfx.ribbon_burst(c, _forward(), Color.WHITE.lerp(_col(), 0.3), 10, 11.0, 50.0, 0.4, Vector3.ZERO)
	var kind: String = a["kind"]
	if step == 2:
		var g := rig.tip_pos()
		Vfx.ground_slam(Vector3(g.x, 0.0, g.z), _col())
	if kind == "air":
		combat_event.emit("air_hit", {"step": step})
	combat_event.emit("hit", {"step": step, "kind": kind, "tier": int(a["tier"])})


## 视觉层：冲击特效 + 从命中点喷出的方块碎块（颜色取被打中的角色）
func _fx_layers(c: Vector3, e: Node3D, tier: int) -> void:
	_landed_hit = true
	Vfx.impact(c, _tip_dir, _col(), [0, 1, 4][tier])
	var out := (_forward() * 0.7 + _tip_dir * 0.6).normalized()
	Vfx.debris(c, out, e.chip_colors(), DEBRIS_N[tier], DEBRIS_SPD[tier], DEBRIS_SIZE[tier])


func _fx_enemy_block(c: Vector3, fwd: Vector3) -> void:
	Vfx.blade_clash(c, -fwd, 0.75)
	Combat.hitstop(0.06)
	player.cam.add_trauma(0.15)
	Sfx.play("block", -3.0, 1.1)
	combat_event.emit("enemy_block", {"step": step})


func _fx_enemy_deflect(c: Vector3, fwd: Vector3) -> void:
	Vfx.blade_clash(c, -fwd, 1.1)
	Combat.hitstop(0.1)
	player.cam.add_trauma(0.25)
	Sfx.play("clash", -1.0, 1.1)
	_add_posture(10.0)
	if state == M.BROKEN:
		return
	_enter(M.RECOIL)
	_state_dur = 0.55
	rig.play("recoil")
	_push_v = -fwd * 2.4
	combat_event.emit("recoiled", {})


func _try_execute() -> bool:
	var tg := _lock_target(3.4)
	if tg == null or not tg.is_broken():
		return false
	_engage(false)
	_victim = tg
	_exec_hit = false
	_enter(M.EXECUTE)
	rig.play("exec")
	tg.begin_deathblow()
	Sfx.play("swing_heavy", -4.0, 0.9)
	return true


# ---------- 受到攻击（由刀客在判定时刻调用） ----------

## 返回 2 弹反 / 1 格挡 / 0 受击 / -1 无效（倒地、处决中、御剑/遁光、闪避无敌中）
func receive_attack(src: Node3D, info: Dictionary) -> int:
	if state == M.DOWN or state == M.EXECUTE or not _grounded():
		return -1
	if player.dodge_iframes():
		return -1
	player.note_attacker(src)
	_engage(false)
	var d := _flat(src.global_position - player.global_position)
	var dir := d.normalized() if d.length_squared() > 1e-4 else _forward()
	var front := _forward().dot(dir) > -0.2
	var can := state != M.HURT and state != M.BROKEN and state != M.RECOIL
	if state == M.ATTACK and not _cancelable():
		can = false
	if can and front and _clock - _parry_at <= _parry_win:
		_on_parry(src, info, dir)
		return 2
	if can and front and guard_held and (state == M.GUARD or state == M.DEFLECT or state == M.BLOCKED):
		_on_block(src, info, dir)
		return 1
	_on_hurt(src, info, dir)
	return 0


## 面向来者（当帧生效，保证对刃姿势按新朝向摆）
func _snap_face(dir: Vector3) -> void:
	face_yaw = atan2(-dir.x, -dir.z)
	has_face = true
	player.face_now(face_yaw)


## 对方刃上离我胸口最近的点；太远就拉回到身前，保证两刃在画面里真的磕在一起
func _clash_point(src: Node3D) -> Vector3:
	var hand: Vector3 = src.blade_hand()
	var tip: Vector3 = src.blade_tip()
	var base_y := player.global_position.y
	var chest := player.global_position + Vector3(0.0, 1.1, 0.0) + _forward() * 0.3
	var c := Geometry3D.get_closest_point_to_segment(chest, hand, tip)
	var off := c - chest
	if off.length() > 0.7:
		c = chest + off.normalized() * 0.7
	c.y = clampf(c.y, base_y + 0.75, base_y + 1.65)
	return c


func _on_parry(src: Node3D, info: Dictionary, dir: Vector3) -> void:
	_snap_face(dir)
	var heavy: bool = info.get("heavy", false)
	var c := _clash_point(src)
	var p := rig.aim_pose(Poses.get_pose("guard"), c)
	rig.snap(p, [[0.15, p, 0], [0.36, Poses.get_pose("guard"), 2]])
	rig.apply(0.0)
	_enter(M.DEFLECT)
	_state_dur = 0.36
	_push_v = -dir * 1.6
	var air := airborne()
	if air:
		# 空中弹反：被磕开的力把自己往上托一下，空斩次数重置，给反击留出时间
		_pop = 4.0
		_air_slashes = 0
	_add_posture(float(info.get("parry_self", 3.0)))
	Vfx.blade_clash(c, -dir, 1.25 if heavy or air else 1.0)
	Combat.hitstop(0.12 if heavy or air else 0.1, 0.0)
	Sfx.play("clash", 0.0, 0.85 if heavy else 1.0)
	player.cam.add_trauma(0.28)
	player.cam.push_in(0.06)
	combat_event.emit("parry", {"heavy": heavy, "contact": c, "air": air})


func _on_block(src: Node3D, info: Dictionary, dir: Vector3) -> void:
	_snap_face(dir)
	var c := _clash_point(src)
	var p := rig.aim_pose(Poses.get_pose("guard"), c)
	p["ln"] = -0.08
	rig.snap(p, [[0.12, p, 0], [0.26, Poses.get_pose("guard"), 2]])
	rig.apply(0.0)
	_enter(M.BLOCKED)
	_state_dur = 0.24
	_push_v = -dir * 2.6
	Vfx.blade_clash(c, -dir, 0.65)
	Combat.hitstop(0.06)
	Sfx.play("block", -1.0)
	player.cam.add_trauma(0.18)
	combat_event.emit("block", {"contact": c})
	_add_posture(float(info.get("block_pst", 20.0)))


func _on_hurt(src: Node3D, info: Dictionary, dir: Vector3) -> void:
	_snap_face(dir)
	hp = maxf(hp - float(info.get("dmg", 15.0)), 0.0)
	var chest := player.global_position + Vector3(0.0, 1.1, 0.0) + dir * 0.15
	var sdir: Vector3 = src.blade_tip() - src.blade_hand()
	var swing := sdir.cross(Vector3.UP).normalized() if sdir.length() > 0.01 else Vector3.RIGHT
	var heavy: bool = info.get("heavy", false)
	# 顿帧 → 受击音 → 闪白/抖动/受击姿势当帧摆出 → 冲击特效 → 自己身上的碎块 → 镜头
	Combat.hitstop(0.1 if heavy else 0.075)
	Sfx.play("hit_heavy" if heavy else "hit", 0.0, 0.85)
	_flash = 1.0
	player.hit_shake(0.1)
	Vfx.impact(chest, swing, Color(0.95, 0.25, 0.2), 1 if heavy else 0)
	Vfx.debris(chest, -dir + Vector3.UP * 0.2, player.hero.chip_colors(), 12 if heavy else 9, 5.0)
	player.cam.add_trauma(0.35)
	combat_event.emit("hurt", {})
	if airborne():
		_pop = 3.0
	if hp <= 0.0:
		# 气血归零：当场陨落（倒地后不再受击，见 receive_attack）
		_enter(M.DOWN)
		rig.play("down")
		_push_v = -dir * 3.0
		player.dead = true
		Combat.slowmo(0.2, 0.3, 0.5)
		combat_event.emit("player_dead", {"pos": chest, "air": false})
		return
	_enter(M.HURT)
	_state_dur = 0.42
	var hp_pose := Poses.get_pose("hurt")
	rig.snap(Poses.lerp_pose(rig.cur, hp_pose, 0.7), [[0.05, hp_pose, 1], [0.2, hp_pose, 0],
			[0.42, Poses.get_pose("stance"), 2]])
	rig.apply(0.0)
	_push_v = -dir * 3.0
	_add_posture(float(info.get("hit_pst", 12.0)))


func _add_posture(v: float) -> void:
	posture = minf(posture + v, POSTURE_MAX)
	_pst_at = _clock
	if posture >= POSTURE_MAX and state != M.BROKEN and state != M.DOWN:
		_enter(M.BROKEN)
		_state_dur = 1.2
		rig.play("broken")
		Sfx.play("block", 0.0, 0.6)
		Combat.hitstop(0.08)
		player.cam.add_trauma(0.3)
		combat_event.emit("self_broken", {})
