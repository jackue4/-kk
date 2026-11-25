extends Node
## 空战剑诀（结丹起）。攻击键现在归近身拳脚（air_melee.gd），这里的三段法术改成三个技能：
## Z / X / C 各放一式（cast_skill，灵力消耗和冷却由 air_melee.gd 管），E 长按是「连发」。
## press_attack()（三段连按）只留给演示脚本用，不再接输入。
## 三式的招式和连发的队形按境界的法相档位（Realm.ARTS）整套更换：
##   结丹 金丹剑气：御剑·三连刺 / 火球 / 剑火齐发；连发 = 身后扇面随机点射
##   元婴 紫霄雷法：雷剑·折光（折线雷闪弹道）/ 掌心雷（雷球命中劈雷 + 电弧跳三个）/ 九霄雷引（五道天雷落阵）；
##        连发 = 双剑成对螺旋绞进
##   化神 焚天火法：焚天剑轮（六剑圆盘飞旋）/ 三昧火莲（八瓣火莲绽开）/ 金乌坠（天外巨火球斜坠 + 背后光轮飞出翻滚火剑）
##   炼虚 五行遁法：五行剑阵 / 五行轮转 / 五行归一
##   合体 裂空神通：裂空剑 / 空间裂隙 / 乾坤挪移斩
##   大乘 万剑归宗：天剑 / 天门 / 万剑归宗
## 连发的队形（_form）：化神起一律是「阵位齐射」——剑从身后固定的阵位上一柄接一柄地出、沿直线射向目标，
##   不翻滚、不绕弧、不乱序，两个人对着发时两股剑流正好迎头对撞：
##   化神 焚天剑轮：背后光轮上八个阵位顺时针轮转 | 炼虚 五行剑列：五角阵位按五芒星笔顺 |
##   合体 裂空剑列：左右各一列三道裂隙、交替出剑 | 大乘 万剑朝宗：背后三排七列的剑墙蛇形扫射，头顶定时落巨剑
## 飞剑对波：对着一个也在连发飞剑的对手连发（或反过来），两股剑流在中间对撞、相持，见 air_melee.gd 的「飞剑对波」。
##   相持期间这里只管出剑（clash_mode）：剑飞到交汇点就撞碎，不耗灵力。
## 出招中再按攻击即预输入下一段；收招后的短窗口内按也能接上，否则从一段重新起。
## 长按攻击（超过 HOLD_T）=「连发」：每秒柄数随境界（境界表 volley）；
## 释放期间每秒消耗 MP_DRAIN 灵力，灵力用尽即停；松手停止。灵力不释放时缓慢回复。
## 目标：先取正在打自己的敌人，再取最近的（Proj.pick_target），没有就朝准星方向打。
## 故意不写 class_name：用 preload 引用。

const Proj := preload("res://scripts/spell_projectile.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Combat := preload("res://scripts/combat.gd")
const CS := preload("res://scripts/combat_stats.gd")      # 战斗数值中枢（2026-11-20 夜）

## dur 全长 | cast 出手时刻 | chain 最早可接下一段的时刻（都按秒）。招式名按法相档位取（Realm.ARTS stages）
const STAGES := [
	{"name": "御剑·三连刺", "dur": 0.5, "cast": 0.06, "chain": 0.3},
	{"name": "火球", "dur": 0.55, "cast": 0.12, "chain": 0.32},
	{"name": "剑火齐发", "dur": 0.95, "cast": 0.34, "chain": 99.0},
]
const GRACE := 0.35      # 收招后这么久内再按，仍接下一段
const HOLD_T := 0.28     # 攻击键按住超过这么久转为连发
const MP_DRAIN := 30.0   # 连发每秒消耗的灵力
const MP_START := 12.0   # 灵力至少这么多才能开始连发（用尽后要回一点才能再放）
const MP_REGEN := 16.0   # 不连发时每秒回复的灵力
const MP_REGEN_DELAY := 0.8  # 停止连发后这么久才开始回复
const VOLLEY_SPEED := 72.0
const VOLLEY_SPREAD := 0.05  # 连发散布：瞄准点按距离的这个比例随机偏移
const VOLLEY_DMG := 0.3      # 连发每柄的伤害系数
const AIM_RANGE := 45.0
const LOCK_RANGE := 70.0 # 镜头锁定的 Boss：这么远内自动索敌
const GOLDEN := 2.39996  # 黄金角：万剑归宗的门在身后铺开用
## 大乘空间门里射出的金色剑束配色
const GOLDS: Array[Color] = [Color(1.0, 0.8, 0.34), Color(1.0, 0.9, 0.56), Color(1.0, 0.66, 0.2)]

var player: Player
var step := -1
var face_yaw := 0.0
var _t := 0.0
var _cast := false
var _queued := false
var _last_step := -1
var _last_end := -10.0
var _pose := 0.0
var channeling := false  # 连发中
var demo_hold_attack := false  # 演示脚本：按住攻击键也算连发（老的 --air-shot / 宣传片）
var _held := 0.0         # 攻击键已按住的时长（空战中）
var _emit_acc := 0.0
var _emit_n := 0
var _regen_wait := 0.0
var _ch_t := 0.0         # 本次连发已持续的时长
var _pulse := 0.0        # 连发附带的光环 / 五芒星脉冲计时
var _giant := 0.0        # 大乘暴雨梨花的巨剑计时
var _gate_n := 0
var clash_mode := false  # 飞剑对波相持中（air_melee.gd 开关）：不看按键、不耗灵力，剑都射向交汇点
var _notify_t := 0.0
## 连发时身后常驻的法相光环（只有化神）：随连发展开、松手收拢
var _halos: Array[MeshInstance3D] = []
var _halo_k := 0.0
var _halo_spin := 0.0
var _aim_pt := Vector3.ZERO


func busy() -> bool:
	return step >= 0 or channeling


func _art() -> int:
	return Realm.art(player.realm)


func stage_name() -> String:
	var info := Realm.art_info(player.realm)
	if channeling:
		return "%s · %d 柄/秒" % [info["volley"], int(player.realm["volley"])]
	return (info["stages"] as Array)[step] if step >= 0 else ""


## 准星当前锁定的目标（没有则 null），HUD 用
func aim_target() -> Node3D:
	return _pick()[0]


static func _now() -> float:
	return Combat.now()


## 技能键：直接放第 i 式（0~2），不走连段
func cast_skill(i: int) -> void:
	if player.st != Player.St.AIR or channeling:
		return
	_last_step = -1
	_last_end = -10.0
	_start(i)


## 刚用过灵力（飞剑点射、瞬身追击、护体）：回复延后一会儿
func hold_regen() -> void:
	_regen_wait = maxf(_regen_wait, MP_REGEN_DELAY)


## 演示脚本用的三段连按（不接输入）
func press_attack() -> void:
	if player.st != Player.St.AIR or player.is_dashing() or channeling:
		return
	if step >= 0:
		_queued = true
		return
	var nxt := _last_step + 1 if _now() - _last_end <= GRACE and _last_step < STAGES.size() - 1 else 0
	_start(nxt)


func cancel() -> void:
	if step >= 0:
		_last_step = -1
		_last_end = -10.0
	step = -1
	_queued = false
	_held = 0.0
	clash_mode = false
	_stop_channel()


## 对波结束（air_melee.gd 调）
func end_clash() -> void:
	if clash_mode:
		clash_mode = false
		_stop_channel()


func _start(i: int) -> void:
	step = i
	_t = 0.0
	_cast = false
	_queued = false
	var aim := _pick()
	face_yaw = _yaw_to(aim[1])
	if i == 2:
		Vfx.cast_charge(_hand(), Realm.line_color(player.realm), float(STAGES[2]["cast"]))
		Sfx.play("swing_heavy", -6.0, 0.8)


func tick(dt: float) -> void:
	_tick_mana(dt)
	_tick_halo(dt)
	_pose = move_toward(_pose, 0.0, dt * 3.0)
	if player.st != Player.St.AIR:
		if step >= 0 or channeling:
			cancel()
		_held = 0.0
		return
	if clash_mode:
		_tick_clash_channel(dt)
		return
	# 连发：E 长按（演示脚本仍可以按住攻击键触发）
	if demo_hold_attack:
		_held = _held + dt if Input.is_action_pressed("attack") and not player.is_dashing() else 0.0
	else:
		_held = player.air.shot_hold()
	if channeling:
		_tick_channel(dt)
		return
	# 长按：等当前段出手后转入连发（连段就此打住，下次按从一段起）
	if _held >= HOLD_T and (step < 0 or _cast) and player.mp >= MP_START:
		_start_channel()
		return
	if step < 0:
		return
	_t += dt
	var s: Dictionary = STAGES[step]
	var cast_t: float = s["cast"]
	if not _cast:
		_pose = maxf(_pose, clampf(_t / maxf(cast_t, 0.01), 0.0, 1.0))
		if _t >= cast_t:
			_cast = true
			_do_cast(step)
	elif _t < cast_t + 0.15:
		_pose = 1.0
	if _queued and step < STAGES.size() - 1 and _t >= float(s["chain"]):
		_start(step + 1)
		return
	if _t >= float(s["dur"]):
		_last_step = step
		_last_end = _now()
		step = -1


# ---------- 连发 / 灵力 ----------

func _tick_mana(dt: float) -> void:
	if channeling:
		return
	if player.mp_busy or player.ult.active:
		_regen_wait = MP_REGEN_DELAY  # Q 飞剑阵开着 / R 大罡剑阵演出中：不回复
		return
	if _regen_wait > 0.0:
		_regen_wait -= dt
		return
	player.mp = minf(player.mp + MP_REGEN * CS.mp_regen_k(player.realm_idx) * dt, player.mp_max())      # 回复按池子大小折：每个境界都是 6.25 秒回满


func _start_channel() -> void:
	step = -1
	_queued = false
	_last_step = -1
	_last_end = -10.0
	channeling = true
	_aim_pt = _pick()[1]
	_emit_acc = float(_per_emit())  # 当帧就先出一发
	_ch_t = 0.0
	_pulse = 0.0
	_giant = 0.3
	_notify_t = 0.0
	Sfx.play("swing_heavy", -7.0, 1.3)


func _stop_channel() -> void:
	if not channeling:
		return
	channeling = false
	_regen_wait = MP_REGEN_DELAY


## 一发几柄：元婴双剑成对出
func _per_emit() -> int:
	return 2 if _art() == 2 else 1


func _tick_channel(dt: float) -> void:
	if _held <= 0.0:
		_stop_channel()
		return
	player.mp = maxf(player.mp - MP_DRAIN * dt, 0.0)
	_pose = 1.0
	_ch_t += dt
	var aim := _pick()
	face_yaw = _yaw_to(aim[1])
	_aim_pt = aim[1]
	# 对着别的修士连发：告诉他一声（真人式的会回敬一轮飞剑）；他也在连发 → 两股剑流对上，进入飞剑对波
	var foe: Node3D = aim[0]
	if foe != null and foe.has_method("is_volleying"):
		_notify_t -= dt
		if _notify_t <= 0.0:
			_notify_t = 1.0
			foe.call("on_volley_incoming", player)
		if bool(foe.call("is_volleying")) and player.air.start_clash(foe):
			return
	var per := _per_emit()
	_emit_acc += dt * float(player.realm["volley"])
	while _emit_acc >= float(per):
		_emit_acc -= float(per)
		_emit_volley(aim[0], aim[1])
	_volley_extra(dt, aim[0], aim[1])
	if player.mp <= 0.0:
		_stop_channel()
		_held = -INF  # 灵力用尽：这次按住作废，松手再按才算
		player.air._shot_held = -INF
		Vfx.cast_flash(_hand(), Color(0.55, 0.6, 0.7), 0.6)
		Sfx.play("block", -10.0, 0.7)


## 连发一发：结丹 / 元婴沿用原来的扇面点射、双剑螺旋；化神起走阵位齐射（_form）
func _emit_volley(tgt: Node3D, pt: Vector3) -> void:
	_emit_n += 1
	match _art():
		2: _volley_helix(tgt, pt)
		3, 4, 5, 6: _volley_form(tgt, pt)
		_: _volley_fan(tgt, pt)
	player.cam.add_trauma(0.006)


## 连发附带的持续表现：炼虚身后五芒星阵图、大乘头顶正中定时落一柄巨剑（化神的身后光环见 _tick_halo）
func _volley_extra(dt: float, tgt: Node3D, pt: Vector3) -> void:
	var art := _art()
	_pulse -= dt
	if _pulse <= 0.0:
		if art == 4:
			_pulse = 0.55
			var c4 := _back_center(2.0, 1.1)
			Vfx.pentagram(c4, (pt - c4).normalized(), 2.3, 0.5)
		else:
			_pulse = 99.0
	if art == 6 and not clash_mode:
		_giant -= dt
		if _giant <= 0.0:
			_giant = 0.5
			var c := _back_center(5.4, 0.8)
			Proj.launch(player, Proj.K.SWORD, c, tgt, pt,
					{"dmg": float(player.realm["dmg"]) * 0.3, "color": GOLDS[0], "speed": 80.0, "hold": 0.24, "turn": 8.0,      # 2026-11-20 夜 1.2 → 0.3：连发折算以后巨剑只是点缀（每秒约 0.6 单位）
					 "straight": tgt == null, "scale": 4.6, "radius": 3.0, "light": true, "style": 4, "tw": 0.34,
					 "tl": 0.4, "art": 6, "trauma": 0.05, "life": 1.84, "ramp": 0.12})
			Vfx.glint(c, Color(1.0, 0.92, 0.65), 1.4)


## 化神常驻身后光环：连发开始由内向外展开（0.22s），每帧摆到身后、盘面朝准星，各层按 spin 反向旋转；
## 连发结束（松手 / 灵力尽 / 闪现打断 / 落地 / 换境界）收拢淡出后释放。大乘改用空间门，不再有光环
func _tick_halo(dt: float) -> void:
	var want := channeling and _art() == 3
	if want and _halos.is_empty():
		_halos.append(Vfx.halo_disc(Realm.line_color(player.realm), 1.0, 0.0))
		_halo_k = 0.0
	if _halos.is_empty():
		return
	_halo_k = move_toward(_halo_k, 1.0 if want else 0.0, dt / (0.22 if want else 0.3))
	_halo_spin += dt * (0.8 + 0.6 * _halo_k)
	var e := 1.0 - (1.0 - _halo_k) * (1.0 - _halo_k)
	var c := _back_center(1.9, 1.1)
	var f := _aim_pt - c
	f = f.normalized() if f.length_squared() > 1e-4 else Basis(Vector3.UP, face_yaw) * Vector3.FORWARD
	for h in _halos:
		var m := h.material_override as ShaderMaterial
		Vfx.orient_disc(h, c, f, 2.1 * lerpf(0.7, 1.0, e))
		m.set_shader_parameter("open", e)
		m.set_shader_parameter("alpha", 0.95 * smoothstep(0.0, 0.35, _halo_k))
		m.set_shader_parameter("spin", _halo_spin)
	if not want and _halo_k <= 0.0:
		for h in _halos:
			h.queue_free()
		_halos.clear()


## 结丹：身后一片扇面里随机亮出，悬停一瞬后射出；锁定了目标就追它，否则沿准星方向直飞
func _volley_fan(tgt: Node3D, pt: Vector3) -> void:
	var fb := Basis(Vector3.UP, face_yaw)
	var off := Vector3(randf_range(-1.4, 1.4), randf_range(1.35, 2.5), randf_range(0.75, 1.3))
	var from: Vector3 = player.global_position + fb * off
	var lc := Realm.line_color(player.realm)
	var dist := from.distance_to(pt)
	var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * dist * VOLLEY_SPREAD
	var homing := tgt != null
	Proj.launch(player, Proj.K.SWORD, from, tgt, pt + (spread * 0.3 if homing else spread),
			_vopts(lc, {"hold": randf_range(0.07, 0.11), "straight": not homing, "art": _art(), "tw": 0.09}))
	Vfx.glint(from, Color.WHITE.lerp(lc, 0.4), 0.4)


## 元婴：左右肩交替，一次两柄紫电光剑互为反相，绕着同一条弹道螺旋绞进，弹道本身还折线雷闪
func _volley_helix(tgt: Node3D, pt: Vector3) -> void:
	var fb := Basis(Vector3.UP, face_yaw)
	var s := -1.0 if _emit_n % 2 == 0 else 1.0
	var from: Vector3 = player.global_position + fb * Vector3(0.75 * s + randf_range(-0.2, 0.2), randf_range(1.7, 2.3), 0.9)
	var cols := Realm.lines(player.realm)
	var homing := tgt != null
	var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * from.distance_to(pt) * 0.025
	for k in 2:
		Proj.launch(player, Proj.K.SWORD, from, tgt, pt + spread,
				_vopts(cols[k % cols.size()], {"hold": 0.06, "straight": not homing, "art": 2, "path": Proj.P.HELIX,
				 "helix_r": 0.8, "phase": PI * k, "light": true, "style": 2, "tw": 0.09, "speed": 70.0,
				 "sfx": _emit_n % 3 == 0 and k == 0}))
	Vfx.lightning(_hand(), from, cols[0], 0.04, 0.1, 3)


## 阵位：第 n 柄剑从哪儿出、什么颜色、带什么参数。返回 [出剑点, 颜色, 附加参数]。
## 阵位都在身后一个朝着瞄准点的竖直平面上（[右, 上] 两根轴），所以剑流是一束整齐的平行线、往目标收束。
func _form(n: int, pt: Vector3) -> Array:
	var cols := Realm.lines(player.realm)
	var c := _back_center(2.0, 1.1)
	var ax := _aim_axes(c, pt)
	var f: Vector3 = ax[0]
	var r: Vector3 = ax[1]
	var u: Vector3 = ax[2]
	match _art():
		3:
			# 焚天剑轮：光轮上八个阵位，顺时针一柄接一柄
			var a := TAU * float(n % 8) / 8.0
			return [c + (r * cos(a) + u * sin(a)) * 1.9, cols[n % cols.size()], {"art": 3, "style": 1, "tw": 0.11, "speed": 84.0}]
		4:
			# 五行剑列：五角阵位，按五芒星的笔顺（隔一个跳一个）
			var k := (n * 2) % 5
			var a4 := TAU * float(k) / 5.0 + PI * 0.5
			return [c + (r * cos(a4) + u * sin(a4)) * 2.3, Vfx.FIVE_ELEM[k], {"art": 4, "tw": 0.09, "speed": 88.0}]
		5:
			# 裂空剑列：左右各一列三道裂隙，左右交替、自下而上
			var side := -1.0 if n % 2 == 0 else 1.0
			var row := (n >> 1) % 3
			return [c + r * side * 2.6 + u * (float(row) - 1.0) * 1.25, cols[n % cols.size()],
					{"art": 5, "style": 5, "tw": 0.09, "speed": 92.0, "rift": true}]
		6:
			# 万剑朝宗：三排七列的剑墙，一排排蛇形扫过去（两翼略往前收成一道弧）
			var row6 := int(floorf(float(n) / 7.0)) % 3
			var colm := n % 7
			if row6 % 2 == 1:
				colm = 6 - colm
			var x := float(colm) - 3.0
			return [c + r * x * 0.95 + u * (float(row6) - 0.5) * 1.15 + f * absf(x) * 0.3, GOLDS[n % GOLDS.size()],
					{"art": 6, "style": 4, "tw": 0.13, "tl": 0.36, "scale": 2.3, "speed": 96.0}]
		2:
			# 元婴：左右肩交替
			var s2 := -1.0 if n % 2 == 0 else 1.0
			return [player.global_position + Basis(Vector3.UP, face_yaw) * Vector3(0.75 * s2, 2.0, 0.9), cols[n % cols.size()],
					{"art": 2, "style": 2, "tw": 0.09, "speed": 78.0}]
	# 结丹：肩后一道五柄的弧
	var k1 := n % 5
	return [player.global_position + Basis(Vector3.UP, face_yaw) * Vector3((float(k1) - 2.0) * 0.7, 2.5 - absf(float(k1) - 2.0) * 0.3, 1.0),
			Realm.line_color(player.realm), {"art": _art(), "tw": 0.09, "speed": 74.0}]


## 化神起的连发：阵位齐射。锁定了目标就追它（转向很紧，轨迹基本是直线），否则沿准星方向直飞
func _volley_form(tgt: Node3D, pt: Vector3) -> void:
	var fm := _form(_emit_n, pt)
	var from: Vector3 = fm[0]
	var col: Color = fm[1]
	var o: Dictionary = fm[2]
	if o.has("rift"):
		o.erase("rift")
		if _emit_n % 3 == 0:
			Vfx.rift(from, pt - from, col, 0.6, 0.26)
	o.merge({"hold": 0.1, "straight": tgt == null, "light": true, "turn": 16.0, "life": 1.3}, false)
	Proj.launch(player, Proj.K.SWORD, from, tgt, pt, _vopts(col, o))
	Vfx.glint(from, Color.WHITE.lerp(col, 0.4), 0.45)


## 飞剑对波相持中：照着阵位不停出剑，剑飞到交汇点就撞碎（只是画面，胜负在 air_melee.gd 里算）
func _tick_clash_channel(dt: float) -> void:
	channeling = true
	_pose = 1.0
	_ch_t += dt
	var pt: Vector3 = player.air.clash_point()
	face_yaw = _yaw_to(pt)
	_aim_pt = pt
	# 大量飞剑对轰：出剑密（占上风时更密、被压时稀；手机画质档减四成），每柄都放大（CLASH_SWORD），
	# 出手处和落点都散开一些 —— 一大片剑撞向交汇点周围，而不是全挤在一条线上
	var adv: float = player.air.clash_adv()
	# 出剑数、剑的大小、剑阵铺多宽都按境界档位（Realm.COMBAT：结丹 26 柄/秒 → 大乘 62 柄/秒；手机画质档另有一列）
	var pf := Realm.combat(player.realm_idx)
	var wide: float = pf["clash_wide"]
	var big: float = pf["clash_sz"]
	_emit_acc += dt * float(pf["clash_n"] if Vfx.lights else pf["clash_lite"]) * (1.0 + 0.4 * adv)
	var axis := pt - player.center()
	axis = axis.normalized() if axis.length_squared() > 1e-4 else Vector3.FORWARD
	var sx := axis.cross(Vector3.UP)
	sx = sx.normalized() if sx.length_squared() > 1e-4 else Vector3.RIGHT
	var sy := sx.cross(axis)
	while _emit_acc >= 1.0:
		_emit_acc -= 1.0
		_emit_n += 1
		var fm := _form(_emit_n, pt)
		var o: Dictionary = fm[2]
		o.erase("rift")
		var from: Vector3 = (fm[0] as Vector3) + (sx * randf_range(-0.8, 0.8) + sy * randf_range(-0.4, 0.7)) * wide
		var end := pt + (sx * randf_range(-1.1, 1.1) + sy * randf_range(-0.9, 0.9)) * lerpf(1.0, wide, 0.6)
		# 飞得比平时慢（CLASH_SWORD_SPD）：同一时刻半空里的剑才多，一柄柄也看得清
		o.merge({"hold": 0.06, "straight": true, "light": true, "ghost": true, "end": end, "dmg": 0.0, "life": 1.6,
				"scale": Proj.SWORD_SCALE * big, "tw": 0.17 * big / player.air.Moves.CLASH_SWORD, "speed": player.air.Moves.CLASH_SWORD_SPD}, true)
		Proj.launch(player, Proj.K.SWORD, from, null, end, _vopts(fm[1], o))
	_volley_extra(dt, null, pt)


## 连发飞剑的公共参数，extra 覆盖
func _vopts(col: Color, extra: Dictionary) -> Dictionary:
	# 每柄的伤害按境界的出剑速度折（CS.volley_k；结丹正好是原来的 0.3）：剑越多越快是观感，每秒伤害只按 CS.skill_g 慢慢涨
	var o := {"dmg": float(player.realm["dmg"]) * CS.volley_k(player.realm_idx), "color": col, "speed": VOLLEY_SPEED,
			"turn": 9.0, "sfx": _emit_n % 4 == 0, "trauma": 0.012, "life": 1.3, "lite": true}
	o.merge(extra, true)
	return o


# ---------- 瞄准 ----------

## 返回 [目标或 null, 瞄准点]
func _pick() -> Array:
	var cam := player.cam
	# Boss 空战：镜头锁定的 Boss 在 LOCK_RANGE 内就直接打它，不必把准星压上去（见 boss_arena.gd）
	if Proj.alive(cam.lock) and Proj.aim_of(cam.lock).distance_to(player.center()) <= LOCK_RANGE:
		return [cam.lock, Proj.aim_of(cam.lock)]
	# 统一索敌：先找正在打我的，再找最近的（Proj.pick_target）；都没有就朝准星方向打
	var best := Proj.pick_target(player, AIM_RANGE, player.air.target)
	var cp := cam.global_position
	var fwd := -cam.global_basis.z
	if best != null:
		return [best, Proj.aim_of(best)]
	var far := cp + fwd * 60.0
	var q := PhysicsRayQueryParameters3D.create(cp, far, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return [null, hit["position"] if not hit.is_empty() else cp + fwd * 45.0]


func _yaw_to(p: Vector3) -> float:
	var d := p - player.global_position
	if Vector2(d.x, d.z).length() < 0.2:
		return player.cam.yaw
	return atan2(-d.x, -d.z)


func _hand() -> Vector3:
	var fb := Basis(Vector3.UP, face_yaw)
	return player.global_position + fb * Vector3(0.3, 1.25, -0.55)


## 身后高 h、离背 back 米处（光轮 / 光环的圆心）
func _back_center(h: float, back: float) -> Vector3:
	return player.global_position + Basis(Vector3.UP, face_yaw) * Vector3(0.0, h, back)


## 以 from→to 为前方的一组正交轴 [前, 右, 上]
static func _aim_axes(from: Vector3, to: Vector3) -> Array:
	var f := to - from
	f = f.normalized() if f.length_squared() > 1e-4 else Vector3.FORWARD
	var r := f.cross(Vector3.UP)
	r = r.normalized() if r.length_squared() > 1e-4 else Vector3.RIGHT
	return [f, r, r.cross(f)]


## 水平圆盘内均匀随机一点
static func _disk(rad: float) -> Vector3:
	var a := randf() * TAU
	var r := rad * sqrt(randf())
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


## 瞄准点脚下的地面（往下打射线，打不到就按 1 米算）
func _ground_below(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 30.0, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3) + Vector3.UP * 0.08 if not hit.is_empty() else p - Vector3.UP


## delay 秒后执行（法术里的分批落点）；施法者是常驻节点，不怕回调时已释放
func _later(delay: float, fn: Callable) -> void:
	get_tree().create_timer(delay).timeout.connect(fn)


# ---------- 出手 ----------

func _do_cast(i: int) -> void:
	var aim := _pick()
	var tgt: Node3D = aim[0]
	var pt: Vector3 = aim[1]
	face_yaw = _yaw_to(pt)
	player.face_now(face_yaw)
	match _art():
		2: _cast_thunder(i, tgt, pt)
		3: _cast_fire(i, tgt, pt)
		4: _cast_five(i, tgt, pt)
		5: _cast_rift(i, tgt, pt)
		6: _cast_heaven(i, tgt, pt)
		_: _cast_core(i, tgt, pt)


## 结丹：御剑·三连刺 / 火球 / 剑火齐发
func _cast_core(i: int, tgt: Node3D, pt: Vector3) -> void:
	var lc := Realm.line_color(player.realm)
	var base: float = float(player.realm["dmg"]) * CS.skill_k(player.realm_idx, i)      # 各境界剑诀按实测折到 2 / 3 / 6 × 成长（combat_stats.gd）
	var fb := Basis(Vector3.UP, face_yaw)
	var pc := player.global_position
	var art := _art()
	match i:
		0:
			# 身后左上 → 头顶后 → 右上依次亮出，悬停一瞬再依次射出
			var offs := [Vector3(-0.9, 1.85, 0.95), Vector3(0.0, 2.3, 1.1), Vector3(0.9, 1.85, 0.95)]
			for k in offs.size():
				var from: Vector3 = pc + fb * offs[k]
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.6, "color": lc, "speed": 58.0, "hold": 0.12 + 0.07 * k, "turn": 12.0,
						 "art": art, "tw": 0.1})
				Vfx.cast_flash(from, lc, 0.7)
			Sfx.play("swing", -6.0, 1.4)
			player.cam.add_trauma(0.04)
		1:
			var h := _hand()
			Proj.launch(player, Proj.K.FIRE, h, tgt, pt, {"dmg": base * 1.5, "speed": 36.0, "turn": 6.0})
			Vfx.cast_flash(h, Proj.FIRE_COLOR, 1.0)
			Sfx.play("swing_heavy", -5.0, 1.25)
			player.cam.add_trauma(0.07)
			player.cam.fov_punch(3.0)
		2:
			var h := _hand()
			Proj.launch(player, Proj.K.BIG_FIRE, h, tgt, pt, {"dmg": base * 2.6, "speed": 30.0, "turn": 5.0})
			Vfx.cast_flash(h, Proj.FIRE_COLOR, 1.6)
			# 身后一圈六柄飞剑，围着出手方向张开，错开一点先后射出
			var n := 6
			for k in n:
				var a := TAU * float(k) / float(n)
				var off := Vector3(cos(a) * 1.5, 1.45 + sin(a) * 1.1, 1.05)
				var from: Vector3 = pc + fb * off
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.5, "color": lc, "speed": 62.0, "hold": 0.05 + 0.035 * k, "turn": 10.0,
						 "art": art, "tw": 0.1})
				Vfx.cast_flash(from, lc, 0.6)
			Sfx.play("swing_heavy", -3.0, 1.0)
			player.cam.add_trauma(0.18)
			player.cam.fov_punch(6.0)


## 元婴 紫霄雷法
func _cast_thunder(i: int, tgt: Node3D, pt: Vector3) -> void:
	var lc := Realm.line_color(player.realm)
	var base: float = float(player.realm["dmg"]) * CS.skill_k(player.realm_idx, i)      # 各境界剑诀按实测折到 2 / 3 / 6 × 成长（combat_stats.gd）
	var fb := Basis(Vector3.UP, face_yaw)
	var pc := player.global_position
	match i:
		0:
			# 雷剑·折光：三柄紫电光剑亮出，掌心各引一道电弧连上，射出后一路折线雷闪
			var offs := [Vector3(-1.0, 1.9, 0.9), Vector3(0.0, 2.45, 1.05), Vector3(1.0, 1.9, 0.9)]
			for k in offs.size():
				var from: Vector3 = pc + fb * offs[k]
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.65, "color": lc, "speed": 66.0, "hold": 0.1 + 0.06 * k, "turn": 12.0,
						 "path": Proj.P.ZIG, "light": true, "style": 2, "tw": 0.11, "art": 2})
				Vfx.lightning(_hand(), from, lc, 0.05, 0.18, 4)
				Vfx.cast_flash(from, lc, 0.7)
			Sfx.play("swing", -6.0, 1.6)
			player.cam.add_trauma(0.05)
		1:
			# 掌心雷：一颗电光雷球，命中劈下天雷，电弧再跳向附近三个敌人
			var h := _hand()
			Proj.launch(player, Proj.K.ORB, h, tgt, pt,
					{"dmg": base * 1.6, "color": lc, "speed": 40.0, "turn": 7.0, "fx": "thunder", "radius": 2.8, "chain": 3})
			Vfx.cast_flash(h, lc, 1.1)
			Vfx.lightning(h, h + (pt - h).normalized() * 2.0, Color.WHITE.lerp(lc, 0.4), 0.06, 0.15, 4)
			Sfx.play("swing_heavy", -5.0, 1.5)
			player.cam.add_trauma(0.08)
			player.cam.fov_punch(3.0)
		2:
			# 九霄雷引：目标处先后劈下五道天雷（中心最重），身后六柄雷剑折线齐射
			var c := pt
			var a0 := randf() * TAU
			for k in 5:
				var p := c
				if k > 0:
					var a := a0 + TAU * float(k) / 4.0
					p = c + Vector3(cos(a), 0.0, sin(a)) * 2.6
				var center := k == 0
				_later(0.06 + 0.08 * k, func() -> void:
					Vfx.thunder(p, lc, 1.3 if center else 0.9)
					Proj.hurt_area(player, p, 2.6 if center else 2.0, base * (1.4 if center else 0.7), Vector3.DOWN, lc, center)
					Sfx.play("hit_heavy", -4.0, 1.6 + 0.08 * k)
					player.cam.add_trauma(0.12 if center else 0.06))
			for k in 6:
				var a := TAU * float(k) / 6.0
				var from: Vector3 = pc + fb * Vector3(cos(a) * 1.5, 1.5 + sin(a) * 1.1, 1.05)
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.5, "color": lc, "speed": 68.0, "hold": 0.05 + 0.035 * k, "turn": 10.0,
						 "path": Proj.P.ZIG, "light": true, "style": 2, "tw": 0.1, "art": 2})
			Vfx.lightning(pt + Vector3.UP * 14.0, _hand() + Vector3.UP * 0.6, lc, 0.1, 0.3, 8)
			Sfx.play("swing_heavy", -3.0, 1.2)
			player.cam.add_trauma(0.2)
			player.cam.fov_punch(6.0)


## 化神 焚天火法
func _cast_fire(i: int, tgt: Node3D, pt: Vector3) -> void:
	var lc := Realm.line_color(player.realm)
	var base: float = float(player.realm["dmg"]) * CS.skill_k(player.realm_idx, i)      # 各境界剑诀按实测折到 2 / 3 / 6 × 成长（combat_stats.gd）
	var pc := player.global_position
	match i:
		0:
			# 焚天剑轮：掌前六剑合成一面飞旋的剑轮，命中炸开、六剑剑影四散
			var from := pc + Basis(Vector3.UP, face_yaw) * Vector3(0.0, 1.5, -0.9)
			Proj.launch(player, Proj.K.WHEEL, from, tgt, pt,
					{"dmg": base * 1.9, "color": lc, "speed": 36.0, "turn": 6.0, "radius": 3.2, "scale": 1.4, "hold": 0.1})
			var c := _back_center(1.8, 1.0)
			Vfx.halo(c, pt - c, lc, 1.8, 0.3)
			Vfx.cast_flash(from, lc, 1.2)
			Sfx.play("swing_heavy", -5.0, 1.1)
			player.cam.add_trauma(0.08)
		1:
			# 三昧火莲：大火球命中后八瓣火莲贴地绽开
			var h := _hand()
			Proj.launch(player, Proj.K.BIG_FIRE, h, tgt, pt,
					{"dmg": base * 1.8, "speed": 34.0, "turn": 5.0, "fx": "lotus", "radius": 4.5, "px": 0.05})
			Vfx.cast_flash(h, Proj.FIRE_COLOR, 1.4)
			Sfx.play("swing_heavy", -4.0, 1.0)
			player.cam.add_trauma(0.1)
			player.cam.fov_punch(4.0)
		2:
			# 金乌坠：天外一颗巨大的火球斜坠而下；背后光轮同时旋出八柄翻滚火剑包抄
			var back := pc - pt
			back.y = 0.0
			back = back.normalized() if back.length_squared() > 1e-4 else Vector3.BACK
			var sky := pt + Vector3.UP * 18.0 + back * 8.0
			Proj.launch(player, Proj.K.BIG_FIRE, sky, tgt, pt,
					{"dmg": base * 3.2, "speed": 36.0, "turn": 3.0, "hold": 0.25, "fx": "sun", "radius": 6.5, "px": 0.09})
			Vfx.sky_ring(sky, Proj.FIRE_COLOR, 3.5, 0.6)
			var c := _back_center(1.9, 1.1)
			var ax := _aim_axes(c, pt)
			Vfx.halo(c, pt - c, lc, 1.9, 0.5)
			for k in 8:
				var a := TAU * float(k) / 8.0
				var radial: Vector3 = (ax[1] as Vector3) * cos(a) + (ax[2] as Vector3) * sin(a)
				var tang: Vector3 = -(ax[1] as Vector3) * sin(a) + (ax[2] as Vector3) * cos(a)
				Proj.launch(player, Proj.K.SWORD, c + radial * 1.9, tgt, pt,
						{"dmg": base * 0.4, "color": lc, "speed": 52.0, "hold": 0.06 + 0.03 * k, "turn": 5.0,
						 "path": Proj.P.SPIN, "light": true, "style": 1, "tw": 0.12, "art": 3,
						 "dir0": tang + (ax[0] as Vector3) * 0.4})
			Sfx.play("swing_heavy", -3.0, 0.8)
			player.cam.add_trauma(0.2)
			player.cam.fov_punch(6.0)


## 炼虚 五行遁法
func _cast_five(i: int, tgt: Node3D, pt: Vector3) -> void:
	var base: float = float(player.realm["dmg"]) * CS.skill_k(player.realm_idx, i)      # 各境界剑诀按实测折到 2 / 3 / 6 × 成长（combat_stats.gd）
	var pc := player.global_position
	match i:
		0:
			# 五行剑阵：身前竖起一面五角，五色剑先向外张开、再从五个方向包抄合击
			var c := pc + Basis(Vector3.UP, face_yaw) * Vector3(0.0, 1.8, -0.2)
			var ax := _aim_axes(c, pt)
			for k in 5:
				var a := PI * 0.5 + TAU * float(k) / 5.0
				var radial: Vector3 = (ax[1] as Vector3) * cos(a) + (ax[2] as Vector3) * sin(a)
				var from := c + radial * 1.3
				var col: Color = Vfx.FIVE_ELEM[k]
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.65, "color": col, "speed": 60.0, "hold": 0.14, "turn": 5.0, "light": true,
						 "tw": 0.1, "art": 4, "dir0": radial + (ax[0] as Vector3) * 0.5})
				Vfx.cast_flash(from, col, 0.7)
			Vfx.pentagram(c, ax[0], 1.3, 0.35)
			Sfx.play("swing", -6.0, 1.3)
			player.cam.add_trauma(0.05)
		1:
			# 五行轮转：五颗五色法珠绕出手方向螺旋收拢，落点结一面五芒星
			var h := _hand()
			var ax := _aim_axes(h, pt)
			for k in 5:
				var a := TAU * float(k) / 5.0
				var radial: Vector3 = (ax[1] as Vector3) * cos(a) + (ax[2] as Vector3) * sin(a)
				var tang: Vector3 = -(ax[1] as Vector3) * sin(a) + (ax[2] as Vector3) * cos(a)
				Proj.launch(player, Proj.K.ORB, h + radial * 0.9, tgt, pt,
						{"dmg": base * 0.45, "color": Vfx.FIVE_ELEM[k], "speed": 38.0, "turn": 4.0, "fx": "five",
						 "radius": 2.2, "hold": 0.04 * k, "dir0": tang + (ax[0] as Vector3) * 0.6})
			var eta := h.distance_to(pt) / 38.0 + 0.45
			_later(eta, func() -> void:
				var p := pt
				if is_instance_valid(tgt) and Proj.alive(tgt):
					p = Proj.aim_of(tgt)
				Vfx.pentagram(p, Vector3.UP, 3.2, 0.6)
				Proj.hurt_area(player, p, 3.2, base * 0.9, Vector3.UP, Vfx.FIVE_ELEM[0], true)
				Sfx.play("hit_heavy", -4.0, 1.2)
				player.cam.add_trauma(0.14))
			Vfx.cast_flash(h, Vfx.FIVE_ELEM[2], 1.1)
			Sfx.play("swing_heavy", -5.0, 1.3)
			player.cam.add_trauma(0.07)
		2:
			# 五行归一：目标脚下铺开一面大五芒星，五个星角上空各落一柱三柄五色剑，中央再贯下一柄五色巨剑
			var g := _ground_below(pt)
			Vfx.pentagram(g, Vector3.UP, 3.6, 1.1)
			var a0 := randf() * TAU
			for k in 5:
				var a := a0 + TAU * float(k) / 5.0
				var corner := Vector3(cos(a), 0.0, sin(a)) * 3.6
				var col: Color = Vfx.FIVE_ELEM[k]
				for j in 3:
					Proj.launch(player, Proj.K.SWORD, pt + corner + Vector3.UP * (11.0 + 2.2 * j), tgt, pt + corner * 0.25,
							{"dmg": base * 0.4, "color": col, "speed": 72.0, "hold": 0.22 + 0.06 * j + 0.02 * k,
							 "turn": 9.0, "light": true, "tw": 0.1, "art": 4, "lite": j > 0})
			Proj.launch(player, Proj.K.SWORD, pt + Vector3.UP * 16.0, tgt, pt,
					{"dmg": base * 2.0, "color": Color(1.0, 0.9, 0.6), "speed": 64.0, "hold": 0.5, "turn": 14.0,
					 "scale": 3.0, "radius": 3.6, "light": true, "style": 4, "tw": 0.3, "tl": 0.3, "art": 6})
			Vfx.sky_ring(pt + Vector3.UP * 16.0, Vfx.FIVE_ELEM[0], 3.6, 0.7)
			Sfx.play("swing_heavy", -3.0, 0.9)
			player.cam.add_trauma(0.16)
			player.cam.fov_punch(5.0)


## 合体 裂空神通
func _cast_rift(i: int, tgt: Node3D, pt: Vector3) -> void:
	var lc := Realm.line_color(player.realm)
	var cols := Realm.lines(player.realm)
	var base: float = float(player.realm["dmg"]) * CS.skill_k(player.realm_idx, i)      # 各境界剑诀按实测折到 2 / 3 / 6 × 成长（combat_stats.gd）
	var pc := player.global_position
	var me := pc - pt
	me.y = 0.0
	me = me.normalized() if me.length_squared() > 1e-4 else Vector3.BACK
	match i:
		0:
			# 裂空剑：剑指一划开出裂隙，目标两侧与背后各裂开一道，飞剑从裂隙里刺出
			Vfx.rift(_hand(), pt - _hand(), lc, 0.9, 0.35)
			var angs := [1.25, -1.25, PI]
			for k in angs.size():
				var d := me.rotated(Vector3.UP, float(angs[k])) + Vector3.UP * randf_range(0.2, 0.5)
				var from := pt + d.normalized() * 4.5
				from.y = maxf(from.y, 0.6)
				Vfx.rift(from, pt - from, lc, 1.0, 0.3 + 0.08 * k)
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.7, "color": cols[k % cols.size()], "speed": 75.0, "hold": 0.16 + 0.08 * k,
						 "turn": 14.0, "light": true, "style": 5, "tw": 0.11, "art": 5})
			Sfx.play("swing", -6.0, 0.9)
			player.cam.add_trauma(0.05)
		1:
			# 空间裂隙：一颗裂隙球，命中坍缩、半秒内连吃数下
			var h := _hand()
			Proj.launch(player, Proj.K.ORB, h, tgt, pt,
					{"dmg": base * 2.2, "color": lc, "speed": 32.0, "turn": 6.0, "fx": "rift", "radius": 3.6})
			Vfx.rift(h, pt - h, lc, 0.8, 0.3)
			Sfx.play("swing_heavy", -5.0, 0.8)
			player.cam.add_trauma(0.08)
			player.cam.fov_punch(3.0)
		2:
			# 乾坤挪移斩：目标处凭空一道巨型新月斩，随即八方裂隙齐开、飞剑合刺
			_later(0.05, func() -> void:
				Vfx.crescent(pt, pt - pc, lc, 4.2)
				Proj.hurt_area(player, pt, 4.2, base * 2.0, (pt - pc).normalized(), lc, true)
				Combat.hitstop(0.05)
				Sfx.play("slam", -5.0, 1.2)
				player.cam.add_trauma(0.28))
			for k in 8:
				var a := TAU * float(k) / 8.0
				var d := Vector3(cos(a), 0.35 + 0.25 * float(k % 2), sin(a)).normalized()
				var from := pt + d * 5.2
				from.y = maxf(from.y, 0.6)
				Vfx.rift(from, pt - from, cols[k % cols.size()], 0.9, 0.4)
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.45, "color": cols[k % cols.size()], "speed": 80.0, "hold": 0.2 + 0.035 * k,
						 "turn": 14.0, "light": true, "style": 5, "tw": 0.1, "art": 5, "lite": k % 2 == 1})
			Sfx.play("swing_heavy", -3.0, 0.9)
			player.cam.fov_punch(6.0)


## 大乘 万剑归宗（金色剑束；不开空间门，旋涡门只给 R 大罡剑阵用）
func _cast_heaven(i: int, tgt: Node3D, pt: Vector3) -> void:
	var base: float = float(player.realm["dmg"]) * CS.skill_k(player.realm_idx, i)      # 各境界剑诀按实测折到 2 / 3 / 6 × 成长（combat_stats.gd）
	var pc := player.global_position
	var me := pc - pt
	me.y = 0.0
	me = me.normalized() if me.length_squared() > 1e-4 else Vector3.BACK
	match i:
		0:
			# 天剑：目标上空一点金光、一圈细环，巨剑悬停一瞬后下贯
			var sky := pt + Vector3.UP * 20.0 + me * 4.0
			Proj.launch(player, Proj.K.SWORD, sky, tgt, pt,
					{"dmg": base * 2.4, "color": GOLDS[0], "speed": 62.0, "hold": 0.36, "turn": 20.0, "scale": 5.0,
					 "radius": 4.5, "light": true, "style": 4, "tw": 0.45, "tl": 0.35, "art": 6, "trauma": 0.1,
					 "life": 2.76})
			Vfx.sky_ring(sky, GOLDS[0], 3.0, 0.5)
			Vfx.glint(sky, Color(1.0, 0.92, 0.65), 2.4)
			Vfx.cast_flash(_hand(), GOLDS[0], 1.0)
			Sfx.play("swing_heavy", -4.0, 0.7)
			player.cam.add_trauma(0.06)
		1:
			# 天门：目标上空一圈十六柄剑依次亮出，一柄接一柄落下
			var ring_c := pt + Vector3.UP * 11.0
			for k in 16:
				var a := TAU * float(k) / 16.0
				var from := ring_c + Vector3(cos(a), 0.0, sin(a)) * 4.5
				var hold := 0.18 + 0.025 * k
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.35, "color": GOLDS[k % GOLDS.size()], "speed": 74.0, "hold": hold,
						 "turn": 12.0, "light": true, "style": 4, "tw": 0.12, "tl": 0.3, "art": 6, "lite": k % 4 != 0,
						 "scale": 1.6, "ramp": 0.1, "life": hold + 2.4})
				Vfx.glint(from, Color(1.0, 0.92, 0.65), 0.8)
			Vfx.sky_ring(ring_c, GOLDS[0], 4.5, 0.6)
			Vfx.cast_flash(_hand(), GOLDS[0], 1.2)
			Sfx.play("swing_heavy", -4.0, 1.1)
			player.cam.add_trauma(0.08)
			player.cam.fov_punch(3.0)
		2:
			# 万剑归宗：身后按黄金角铺开二十四柄剑，由内向外依次射出；天上再贯下一柄巨剑
			var c := _back_center(2.6, 1.2)
			var ax := _aim_axes(c, pt)
			for k in 24:
				var r := 3.4 * sqrt((float(k) + 0.5) / 24.0)
				var a := float(k) * GOLDEN
				var radial: Vector3 = (ax[1] as Vector3) * cos(a) + (ax[2] as Vector3) * sin(a)
				var from: Vector3 = c + radial * r + (ax[0] as Vector3) * (0.04 * r * r)
				var hold := 0.16 + 0.016 * k
				Proj.launch(player, Proj.K.SWORD, from, tgt, pt,
						{"dmg": base * 0.35, "color": GOLDS[k % GOLDS.size()], "speed": 86.0, "hold": hold,
						 "turn": 6.5, "light": true, "style": 4, "tw": 0.13, "tl": 0.32, "art": 6, "lite": true,
						 "scale": 1.75, "ramp": 0.1, "life": hold + 2.4, "sfx": k % 4 == 0})
				if k % 3 == 0:
					Vfx.glint(from, Color(1.0, 0.92, 0.65), 0.7)
			var sky := pt + Vector3.UP * 18.0 + me * 3.0
			Proj.launch(player, Proj.K.SWORD, sky, tgt, pt,
					{"dmg": base * 2.0, "color": GOLDS[0], "speed": 62.0, "hold": 0.5, "turn": 20.0, "scale": 4.5,
					 "radius": 4.5, "light": true, "style": 4, "tw": 0.4, "tl": 0.35, "art": 6, "life": 2.9})
			Vfx.sky_ring(sky, GOLDS[0], 3.0, 0.6)
			Sfx.play("swing_heavy", -2.0, 0.8)
			player.cam.add_trauma(0.22)
			player.cam.fov_punch(7.0)


# ---------- 施法手势 ----------

## 在 hero.animate 之后叠上去：一段剑指上扬、二段推掌、三段双手前推；连发剑指前方
func apply_pose(hero: Node3D) -> void:
	var k := _pose * _pose * (3.0 - 2.0 * _pose)
	if k <= 0.001:
		return
	var s := 1 if channeling else (step if step >= 0 else _last_step)
	var ar: Node3D = hero.arm_r
	var al: Node3D = hero.arm_l
	var up: Node3D = hero.upper
	match s:
		0:
			ar.rotation.x = lerpf(ar.rotation.x, 2.5, k)
			ar.rotation.z = lerpf(ar.rotation.z, 0.15, k)
		1:
			ar.rotation.x = lerpf(ar.rotation.x, 1.55, k)
			up.rotation.y = lerpf(up.rotation.y, -0.35, k)
		_:
			ar.rotation.x = lerpf(ar.rotation.x, 1.45, k)
			al.rotation.x = lerpf(al.rotation.x, 1.45, k)
			ar.rotation.z = lerpf(ar.rotation.z, -0.2, k)
			al.rotation.z = lerpf(al.rotation.z, 0.2, k)
