class_name Player
extends CharacterBody3D
## 角色控制：地面移动/跳跃、境界切换、飞行状态机。
## 炼气/筑基：御剑（脚踏飞剑）；结丹起：化作遁光——先冲天而起，再向前破空。
## 遁光期间（dun_active）主角化作一柄光剑：身形先收细、染光（_morph 0→1），光剑从剑心长出，
## 随后人形隐去，画面上只留光剑 + 1~3 条细丝线 + 少量伴飞的微型剑影；飞剑本体随之隐藏。收遁/落地时反向现形。
## 飞行方向完全跟随镜头：W 朝镜头所看方向飞，低头下降、抬头上升，没有单独的升降键。
## Shift：短按闪现、长按疾行 / 疾遁。闪现沿移动方向冲过境界的闪现距离，地面与空中都可用：
## 炼气/筑基人形冲刺、沿途留角色残影；结丹起化作光剑冲刺。
## 空战中长按 Shift 疾行（空战本就要结丹起）：化作遁光光剑（同光遁飞行的光剑 + 丝线 + 剑影），速度仍是 AIR_SPEED × AIR_SPRINT，
## 镜头按曲线拉远（见 _air_boost_tick）；施法中不化光，保持人形压低侧倾、双臂后掠、留淡残影和细风丝。
## 空战（结丹起）：地面按空格直接腾空（光遁悬停时按空格也能切入），人形可见、跟随镜头飞，
## 攻击键是近身拳脚 + 飞剑随击、长按蓄力重击击飞、击飞后再按瞬身追击（见 air_melee.gd）；
## 飞剑 / 法术改成技能键：E 飞剑点射 / 长按连发，Z X C 三式剑诀（air_caster.gd）；飞到地面 / 平台上即落地，回到地面状态。
## R 大罡剑阵（大乘专属，见 gate_array.gd）：演出期间原地定身、不接受移动 / 攻击 / 闪现 / 起飞输入。
## 遁光落地（光遁飞行中按 F）：DIVE 状态——空中一顿蓄势，光剑剑尖朝下急坠（越落越快），砸地那一下全屏顿帧、
## 镜头压近下沉再弹回（CameraRig.slam），地面炸开冲击环 / 尘土（Vfx.dun_slam），人形蹲伏现身、片刻后才能走。
## 移动放在 _process 里做，和相机/拖尾同帧更新，高速下不抖。

signal realm_changed(idx: int)
signal dun_changed(active: bool)
signal realm_ascended(idx: int)  # 升阶（境界往上走）时才发：HUD 右侧题字

enum St { GROUND, TAKEOFF, FLY, AIR, DIVE }

const VoxelHero := preload("res://scripts/voxel_hero.gd")
const PlayerMelee := preload("res://scripts/player_melee.gd")
const AirCaster := preload("res://scripts/air_caster.gd")
const AirMelee := preload("res://scripts/air_melee.gd")
const GateArray := preload("res://scripts/gate_array.gd")
const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const SHIFT_TAP := 0.2     # Shift 按下不到这么久就松开算短按（闪现），否则是长按疾行
const BLINK_BUF := 0.25    # 闪现输入缓冲：冷却 / 上一次闪现还没冲完时按下，这么久内一可用就立刻闪
const BLINK_CD_AIR := 0.18 # 飞行 / 空战闪现冲完后的冷却
const AIR_SPEED := 11.0    # 空战巡航速度
const AIR_SPRINT := 1.8    # 空战中长按 Shift 的加速倍率
const BOOST_GHOST := 0.07  # 空战疾行：每隔这么久留一道淡残影
const AIR_ACC := 40.0
const AIR_RISE := 0.5      # 空格腾空：这段时间内向上托起（约 3.7m）
const AIR_RISE_V := 15.0
const GHOST_STEP := 0.9    # 低境界闪现每冲过这么远留一道残影
## 地面闪避：比飞行闪现短得多，只是一个侧身滑步；全程无敌，判定帧落在闪避开始后 PERFECT_WIN 内即为完美闪避
const DODGE_DIST := 3.0
const DODGE_SPD := 30.0
const DODGE_IFRAME_TAIL := 0.08  # 闪避结束后再多无敌这么久（游戏时间）
const PERFECT_WIN := 0.3
const ASCEND_BURST := 0.45  # 升阶：聚气多久后破境（与 Vfx.realm_ascend 对齐）
const ASCEND_DUR := 1.5
const DODGE_CD := 0.12           # 地面闪避收尾后的冷却：短，方便与攻击穿插
const GRAVITY := 24.0
const BOUND := 1150.0   # 试剑大厅的活动范围
const MORPH_IN := 0.16    # 化作光剑
const MORPH_OUT := 0.22   # 由光剑现形
const MORPH_DASH := 0.05  # 闪现时几乎瞬间化剑
const LSWORD_LEN := 2.4   # 光剑全长（米），远镜头下另有像素下限
const SPIN_Y := 0.95      # 整身翻转的轴心高度（身体中心）
## 遁光砸地
const DIVE_WIND := 0.08   # 下坠前在空中一顿（微微上提蓄势）
const DIVE_V0 := 24.0
const DIVE_ACC := 340.0
const DIVE_VMAX := 95.0
const DIVE_TMAX := 0.55   # 再高也大约在这么久内砸到地面（遁速上限随高度抬）
const DIVE_MIN_H := 1.2   # 离地不到这么高就不俯冲，直接落下
const SLAM_LOCK := 0.26   # 砸地后蹲伏、不接受移动的时长
const SLAM_RECOVER := 0.5 # 蹲伏回弹到站直的总时长
const FIVE: Array[Color] = [
	Color(1.0, 0.86, 0.4), Color(0.25, 1.0, 0.45), Color(0.25, 0.55, 1.0),
	Color(1.0, 0.28, 0.15), Color(0.85, 0.62, 0.3),
]

var realm_idx := 0
var realm: Dictionary = Realm.LIST[0]
var st := St.GROUND
var cam: CameraRig
var vfx_root: Node3D
var dun_active := false  # 遁光中：人与剑都不可见
var melee: PlayerMelee   # 地面近战（见 player_melee.gd）
var melee_k := 0.0       # 近战投入程度 0~1：飞剑阵据此收拢到背后
var caster: AirCaster    # 空战剑诀 / 飞剑连发（见 air_caster.gd）
var air: AirMelee        # 空战拳脚：连击 / 重击击飞 / 瞬身追击 / 护体（见 air_melee.gd）
var ult: GateArray       # R 大罡剑阵（大乘专属，见 gate_array.gd）
var mp := 0.0            # 灵力（蓝量）：空战长按连发飞剑、Q 飞剑阵开着时消耗，上限见境界表 mp
## 最近打中过我的敌人 → 时刻（Combat.now）。索敌优先找它们，见 spell_projectile.gd 的 pick_target
var threat := {}
var mp_busy := false     # 有持续耗灵力的技能开着（Q 飞剑阵）：期间灵力不回复
var bound := BOUND       # 当前关卡的活动范围（开放世界关卡会放大，见 meadow_level.gd）
var ground_ref := 0.0    # 境界飞行高度上限（ceiling）的起算高度：大厅为 0，木兰草原每帧给脚下地面高度

var _takeoff_t := 0.0
var _takeoff_dur := 0.55
var _burst_hold := 0.0
var _blink_cd := 0.0
var _facing := 0.0
var _spin := 0.0
var _bob := 0.0
var _dun_dir := Vector3.UP
var _mote_ang := 0.0
var _shake := 0.0
var _morph := 0.0          # 0 人形 ~ 1 光剑
var _lsword_tail := Vector3.ZERO
var _dash_left := 0.0      # 闪现剩余距离（米）
var _dash_dir := Vector3.FORWARD
var _dash_spd := 0.0
var _shift_t := -1.0       # Shift 已按住的时长，-1 = 没按
var _shift_used := false   # 这次按下已经触发过闪现（动作中按下即闪），松手不再闪
var _blink_buf := 0.0      # 闪现输入缓冲剩余时间
var _air_t := 0.0          # 进入空战后的时长
var _boost := Vector2.ZERO # 空战疾行姿态用：x 左右平移、y 前冲，平滑过的（见 _air_boost_tick）
var _boost_on := false
var _boost_ghost := 0.0
var _ghost_d := 0.0        # 低境界闪现：距上一道残影冲过的距离
var _dodge_age := INF      # 本次地面闪避开始后经过的游戏时间（INF = 不在闪避）
var _dodge_from := Vector3.ZERO
var _dodge_perfect := false
var _ascend := -1.0        # 升阶突破已过的时间，-1 = 不在突破
var _dive_t := 0.0         # 本次俯冲已过的时间
var _dive_v := 0.0
var _dive_vmax := DIVE_VMAX
var _dive_dir := Vector3.DOWN
var _slam_t := -1.0        # 砸地后已过的时间，-1 = 不在砸地恢复中

var visual: Node3D
var body_root: Node3D
var spin: Node3D           # 身体中心处的翻转节点：空战的俯冲、回旋踢、空翻、被击飞翻滚都转它
var hero: VoxelHero
var foot_sword: Node3D
var _glow: OmniLight3D
var _wind: GPUParticles3D
var _boost_wind: GPUParticles3D  # 空战疾行：身周向后掠的细风丝
var _fila: GPUParticles3D
var _tip: MeshInstance3D   # 光剑外沿的针形光晕
var _lsword: Node3D
var _trails: Array[Trail3D] = []
var _motes: Array[MeshInstance3D] = []
var _mote_trails: Array[Trail3D] = []
var _mote_pos := PackedVector3Array()


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	_build_body()
	_build_dun_fx()
	melee = PlayerMelee.new()
	melee.player = self
	add_child(melee)
	caster = AirCaster.new()
	caster.player = self
	add_child(caster)
	air = AirMelee.new()
	air.player = self
	add_child(air)
	ult = GateArray.new()
	ult.player = self
	add_child(ult)


func center() -> Vector3:
	return global_position + Vector3(0.0, 0.95, 0.0)


## 立即转向（对刃/受击时当帧生效）
func face_now(yaw: float) -> void:
	_facing = yaw
	visual.rotation.y = yaw


func facing_basis() -> Basis:
	return Basis(Vector3.UP, _facing)


func mp_max() -> float:
	return float(realm["mp"])


## 是玩家（不是怪 / AI）：飞剑对玩家不追踪，见 spell_projectile.gd 的 launch
func is_player() -> bool:
	return true


## 联机：别人的飞剑（画面）拿本机主角当目标时要问
func is_alive() -> bool:
	return melee.hp > 0.0


func note_attacker(n: Node3D) -> void:
	if n != null and is_instance_valid(n):
		threat[n] = Combat.now()


func is_light_mode() -> bool:
	return int(realm["mode"]) == Realm.Mode.LIGHT


func speed() -> float:
	return velocity.length()


## 化剑程度：0 人形 ~ 1 光剑
func morph_k() -> float:
	return _morph


func is_dashing() -> bool:
	return _dash_left > 0.0


## 能否起手 R 大罡剑阵：地面（近战没在出招 / 受击）或空战中，且不在闪现、升阶突破
func can_ult() -> bool:
	if _dash_left > 0.0 or _ascend >= 0.0:
		return false
	if st == St.GROUND:
		return not melee.busy()
	return st == St.AIR


## 长按 Shift：疾行（地面）/ 疾遁（飞行）/ 加速（空战）
func sprinting() -> bool:
	return _shift_t >= SHIFT_TAP


func state_text() -> String:
	if ult.active:
		return GateArray.NAME
	if _dash_left > 0.0:
		return "闪现"
	match st:
		St.TAKEOFF:
			return "起飞"
		St.DIVE:
			return "遁光落地"
		St.FLY:
			if is_light_mode():
				return "遁光飞行" if dun_active else "凌空悬停"
			return "御剑飞行"
		St.AIR:
			if caster.busy():
				return "空战 · " + caster.stage_name()
			if air.busy():
				return "空战 · " + air.state_name()
			return "空战 · 遁光疾行" if dun_active else "空战"
	var s := "地面" if is_on_floor() else "腾空"
	if melee != null and melee.engaged():
		s += " · " + melee.state_name()
	return s


# ---------- 构建 ----------

func _build_body() -> void:
	# 像素方块搭的微缩白衣修士（见 voxel_hero.gd），脚底在原点、面朝 -Z
	visual = Node3D.new()
	add_child(visual)
	body_root = Node3D.new()
	visual.add_child(body_root)
	spin = Node3D.new()
	spin.position.y = SPIN_Y
	body_root.add_child(spin)
	var holder := Node3D.new()
	holder.position.y = -SPIN_Y
	spin.add_child(holder)
	hero = VoxelHero.new({}, true, false, realm_idx)  # 独立材质：受击时可以单独闪白；装束按境界换
	holder.add_child(hero)

	# 脚下飞剑（御剑时显示）
	foot_sword = MeshLib.make_sword(Color(0.4, 0.7, 1.0))
	foot_sword.rotation.x = -PI * 0.5
	foot_sword.scale = Vector3.ONE * 2.2
	foot_sword.position = Vector3(0, 0.02, -0.25)
	foot_sword.visible = false
	visual.add_child(foot_sword)

	# 筑基御风：身周向后掠过的细风丝
	_wind = Vfx.wind_stream(Color.WHITE)
	if _wind != null:
		_wind.position.y = 0.9
		add_child(_wind)
	_boost_wind = Vfx.wind_stream(Color.WHITE)
	if _boost_wind != null:
		_boost_wind.position.y = 0.9
		add_child(_boost_wind)


func _build_dun_fx() -> void:
	# 遁光本体：主角化成的光剑，外沿一层针形光晕
	_lsword = MeshLib.make_light_sword(Color.WHITE)
	_lsword.top_level = true
	_lsword.visible = false
	add_child(_lsword)
	_tip = Vfx.persistent_sprite(Color.WHITE, 2)
	_tip.visible = false

	# 只给近处地面一点染色，不承担"发光"的观感
	_glow = OmniLight3D.new()
	_glow.omni_range = 5.0
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	_glow.position.y = 0.95
	add_child(_glow)

	# 轨迹旁零星剥落的细剑光（GPU 粒子 Trails）
	_fila = Vfx.ribbon_stream(Color.WHITE, 8)
	if _fila != null:
		_fila.position.y = 0.95
		add_child(_fila)


# ---------- 境界 ----------

func set_realm(idx: int, with_fx := true) -> void:
	var prev := realm_idx
	realm_idx = clampi(idx, 0, Realm.count() - 1)
	realm = Realm.LIST[realm_idx]
	if hero != null:
		hero.set_look(realm_idx)      # 每个境界一身装束（见 voxel_hero.gd 的 LOOKS）
	# 升阶 / 初始化时灵力回满，降阶只截到新上限
	mp = mp_max() if realm_idx >= prev else minf(mp, mp_max())
	if st == St.AIR and not is_light_mode():
		# 法术空战要结丹起：空中跌回低境界就改成御器飞行，不在半空掉状态
		caster.cancel()
		st = St.FLY
	var lc := Realm.line_color(realm)
	_glow.light_color = lc
	if _wind != null:
		var wc := Color.WHITE.lerp(lc, 0.7)
		(_wind.process_material as ParticleProcessMaterial).color = Color(wc.r, wc.g, wc.b, 0.75)
	if _boost_wind != null:
		var bc := Color.WHITE.lerp(lc, 0.5)
		(_boost_wind.process_material as ParticleProcessMaterial).color = Color(bc.r, bc.g, bc.b, 0.7)
	(_tip.material_override as ShaderMaterial).set_shader_parameter("color", lc)
	MeshLib.set_light_sword_color(_lsword.get_meta("blade_mat") as StandardMaterial3D, lc)
	if _fila != null:
		(_fila.process_material as ParticleProcessMaterial).color = Color.WHITE.lerp(lc, 0.75)
	(foot_sword.get_meta("blade_mat") as StandardMaterial3D).emission = lc
	_build_trails()
	_build_motes()
	if with_fx:
		if realm_idx > prev:
			_ascend_start()
		else:
			Vfx.breakthrough(global_position, lc, float(realm["fx"]))
			if cam != null:
				cam.add_trauma(0.15 + 0.3 * float(realm["fx"]))
	realm_changed.emit(realm_idx)
	if with_fx and realm_idx > prev:
		realm_ascended.emit(realm_idx)


## 升阶突破：聚气（身形渐亮、微微离地）→ ASCEND_BURST 时破境（各境界专属特效见 Vfx.realm_ascend）→ 光芒褪去落回
func _ascend_start() -> void:
	_ascend = 0.0
	Vfx.realm_ascend(visual, realm_idx, Realm.lines(realm), float(realm["fx"]))
	Sfx.play("ascend", -3.0, 1.0 + 0.04 * realm_idx)
	if cam != null:
		cam.fov_punch(-4.0)
		cam.add_trauma(0.06)


func _update_ascend(dt: float, grounded: bool) -> void:
	if _ascend < 0.0:
		return
	var was := _ascend
	_ascend += dt
	var fx: float = realm["fx"]
	if was < ASCEND_BURST and _ascend >= ASCEND_BURST:
		cam.add_trauma(0.22 + 0.35 * fx)
		cam.fov_punch(7.0 + 8.0 * fx)
		Sfx.play("slam", -9.0, 1.5)
	var env := smoothstep(0.0, ASCEND_BURST, _ascend) * (1.0 - smoothstep(ASCEND_BURST + 0.2, ASCEND_DUR, _ascend))
	if _ascend >= ASCEND_DUR:
		_ascend = -1.0
		env = 0.0
	if not dun_active:
		var e := _morph * _morph * (3.0 - 2.0 * _morph)
		hero.set_glow(maxf(env * 0.7, minf(e * 1.6, 1.0)), Realm.line_color(realm))
		if grounded:
			body_root.position.y += 0.2 * env


func _new_trail(w: float, life: float, px: float, style: int, col: Color, fn: Callable) -> Trail3D:
	var t := Trail3D.new()
	t.width = w
	t.lifetime = life
	t.min_px = px
	t.point_fn = fn
	t.material_override = MeshLib.trail_material(Color.WHITE.lerp(col, 0.4), col, style)
	vfx_root.add_child(t)
	return t


## 主线 1 条 + 绕主线的副线 0~2 条，都是细带
func _build_trails() -> void:
	for t in _trails:
		t.queue_free()
	_trails.clear()
	var cols := Realm.lines(realm)
	var style: int = realm["style"]
	var w: float = realm["width"]
	var life: float = realm["life"]
	_trails.append(_new_trail(w, life, 4.0, style, cols[0] as Color, _main_point))
	var n := cols.size() - 1
	for i in n:
		_trails.append(_new_trail(w * 0.5, life * 0.85, 2.4, style, cols[i + 1] as Color, _ribbon_point.bind(i, n)))


## 伴飞的微型剑影：只是点缀，数量由境界表的 motes 决定（≤4）
func _build_motes() -> void:
	for m in _motes:
		m.queue_free()
	for t in _mote_trails:
		t.queue_free()
	_motes.clear()
	_mote_trails.clear()
	var n: int = realm["motes"]
	_mote_pos.resize(n)
	var cols := Realm.lines(realm)
	var five := int(realm["style"]) == 3
	for i in n:
		var c: Color = FIVE[(i + 3) % 5] if five else (cols[i % cols.size()] as Color)
		var m := Vfx.persistent_sprite(c, 3)
		m.visible = dun_active
		_motes.append(m)
		_mote_pos[i] = center()
		_mote_trails.append(_new_trail(0.03, 0.07, 1.6, 0, c, _mote_point.bind(i)))


func _main_point() -> Vector3:
	if is_light_mode():
		# 遁光：主线从光剑的剑首拖出
		return _lsword_tail if _lsword.visible else center()
	# 御剑：剑光从脚下飞剑的剑尾拖出
	return visual.global_transform * Vector3(0.0, 0.06, 0.9)


func _dun_side() -> Vector3:
	var r := _dun_dir.cross(Vector3.UP)
	return r.normalized() if r.length_squared() > 1e-4 else Vector3.RIGHT


func _ribbon_point(i: int, n: int) -> Vector3:
	var f := _dun_dir
	var r := _dun_side()
	var u := r.cross(f)
	var ang := _spin + TAU * float(i) / float(n)
	var rad := 0.26 + 0.03 * realm_idx
	return center() + (r * cos(ang) + u * sin(ang)) * rad


func _mote_point(i: int) -> Vector3:
	return _mote_pos[i] if i < _mote_pos.size() else center()


# ---------- 输入 ----------

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ult"):
		ult.try_cast()
	elif e.is_action_released("sprint"):
		if _shift_t >= 0.0 and _shift_t < SHIFT_TAP and not _shift_used and not ult.active:
			request_blink()
		_shift_t = -1.0
	elif ult.active:
		return  # 大罡剑阵演出中：不起飞、不闪现
	elif e.is_action_pressed("fly"):
		toggle_flight()
	elif e.is_action_pressed("sprint"):
		_shift_t = 0.0
		_shift_used = false
		# 闪现优先级最高：出招 / 受击 / 格挡 / 施法 / 起飞 / 闪现途中按下 Shift，不等松手立刻闪（不可用就进缓冲）
		if _acting():
			_shift_used = true
			request_blink()


## 正在做动作（按下 Shift 应立刻闪现而不是等着判断长按疾行）
func _acting() -> bool:
	if _dash_left > 0.0 or st == St.TAKEOFF:
		return true
	if st == St.AIR:
		return caster.busy() or air.busy()
	return st == St.GROUND and melee.engaged()


## 请求闪现：能闪就立刻闪，不能（冷却 / 正在冲刺）就记进缓冲，BLINK_BUF 内一可用就闪
func request_blink() -> void:
	_blink_buf = BLINK_BUF
	if blink():
		_blink_buf = 0.0


## F：地面 → 起飞（御剑 / 光遁）；空战 → 光遁赶路；飞行中 → 落下（光遁：俯冲砸地，见 _start_dive）
func toggle_flight() -> void:
	if st == St.DIVE:
		return
	_dash_left = 0.0
	if st == St.AIR:
		_air_to_fly()
		return
	if st == St.GROUND:
		st = St.TAKEOFF
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		_takeoff_t = 0.0
		_takeoff_dur = 0.55 if is_light_mode() else 0.5
		velocity = Vector3.ZERO
		var fx: float = realm["fx"]
		if is_light_mode():
			# 起飞的一瞬间人和剑就隐去，不等任何过渡
			_dun_dir = Vector3.UP
			_set_dun(true)
		Vfx.takeoff_burst(global_position, Realm.line_color(realm), 0.6 + fx * 1.8)
		cam.start_dolly(_takeoff_dur, fx)
		cam.add_trauma(0.15 + fx * 0.5)
	elif is_light_mode() and _height_above_ground() > DIVE_MIN_H:
		_start_dive()
	else:
		st = St.GROUND
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		velocity = velocity.limit_length(18.0)
		_set_dun(false)


## 脚下到地面 / 平台顶面的高度（往下打射线，最多看 400 米）
func _height_above_ground() -> float:
	var p := global_position + Vector3.UP * 0.1
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 400.0, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var h := global_position.y
	if not hit.is_empty():
		h = minf(h, global_position.y - (hit["position"] as Vector3).y)
	return maxf(h, 0.0)


## 遁光落地：先在空中一顿，再化作光剑剑尖朝下急坠，砸地见 _slam
func _start_dive() -> void:
	caster.cancel()
	st = St.DIVE
	_dive_t = 0.0
	_dive_v = DIVE_V0
	var h := _height_above_ground()
	_dive_vmax = maxf(DIVE_VMAX, h / DIVE_TMAX)
	# 主要向下，带一点原来的水平冲势，斜着扎下去
	var hv := Vector3(velocity.x, 0.0, velocity.z) / maxf(float(realm["speed"]), 1.0)
	_dive_dir = (Vector3.DOWN + hv.limit_length(1.0) * 0.35).normalized()
	_dun_dir = _dive_dir
	velocity = Vector3.ZERO
	_set_dun(true)
	var fx: float = realm["fx"]
	Sfx.play("swing_heavy", -5.0, 0.6)
	cam.fov_punch(8.0 + 10.0 * fx)
	cam.add_trauma(0.06)


func _dive(dt: float) -> void:
	_dive_t += dt
	if _dive_t < DIVE_WIND:
		# 蓄势：微微上提、悬停一拍
		velocity = Vector3.UP * 3.0
		move_and_slide()
		return
	_dive_v = minf(_dive_v + DIVE_ACC * dt, _dive_vmax)
	velocity = _dive_dir * _dive_v
	move_and_slide()
	if global_position.y < 0.0:
		global_position.y = 0.0
	if _touching_floor() or is_on_floor() or _dive_t > DIVE_WIND + 2.5:
		_slam()


## 砸地：全屏顿一下、镜头压近下沉，地面炸开冲击环 + 尘土，人形蹲伏现身
func _slam() -> void:
	var impact := _dive_v
	st = St.GROUND
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	velocity = Vector3.ZERO
	_set_dun(false)
	_slam_t = 0.0
	var power := clampf(0.6 + impact / 100.0, 0.8, 1.5)
	var lc := Realm.line_color(realm)
	Vfx.dun_slam(global_position, lc, power)
	Sfx.play("slam", -2.0, 0.85)
	Sfx.play("thud", -4.0, 0.7)
	Combat.slowmo(0.04, 0.07, 0.16)  # 顿帧：整个画面停一拍再加速回来
	cam.slam(power)


## 立刻回到地面状态（回出生点等）
func force_ground() -> void:
	_dash_left = 0.0
	_slam_t = -1.0
	ult.abort()
	caster.cancel()
	st = St.GROUND
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	velocity = Vector3.ZERO
	_set_dun(false)


func is_air_combat() -> bool:
	return st == St.AIR


## 空格腾空进入空战（结丹起）。近战出招 / 受击中不行
func take_air() -> bool:
	if st != St.GROUND or not is_light_mode() or _dash_left > 0.0:
		return false
	if not melee.can_jump():
		return false
	melee.on_jump()
	st = St.AIR
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_air_t = 0.0
	velocity = Vector3(velocity.x, AIR_RISE_V, velocity.z)
	Vfx.takeoff_burst(global_position, Realm.line_color(realm), 0.35)
	cam.add_trauma(0.08)
	return true


## Boss 空战（见 boss_arena.gd）：不管现在在走、在飞还是在近战，直接切进法术空战；地面上照常向上托起。
## 闪现中、俯冲砸地中、大罡剑阵中、低于结丹（没有空战）时不切，返回是否已在空战
func enter_air_combat() -> bool:
	if st == St.AIR:
		return true
	if not is_light_mode() or st == St.DIVE or _dash_left > 0.0 or ult.active:
		return false
	if st == St.FLY or st == St.TAKEOFF:
		_fly_to_air()
		return true
	if melee.engaged():
		melee.sheathe()
	st = St.AIR
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_air_t = 0.0
	velocity = Vector3(velocity.x, AIR_RISE_V, velocity.z)
	Vfx.takeoff_burst(global_position, Realm.line_color(realm), 0.5)
	cam.add_trauma(0.1)
	return true


## 光遁 / 悬停中按空格：原地切入空战（不再向上托起）
func _fly_to_air() -> void:
	st = St.AIR
	_air_t = AIR_RISE
	velocity = velocity.limit_length(AIR_SPEED)


## 空战中按 F：向镜头前方破空，转为光遁赶路
func _air_to_fly() -> void:
	caster.cancel()
	st = St.FLY
	var fwd := cam.flat_forward()
	velocity = fwd * float(realm["speed"])
	_burst_hold = 0.55
	var fx: float = realm["fx"]
	Vfx.launch_ring(center(), fwd, Realm.line_color(realm), 0.7 + fx * 1.6)
	cam.add_trauma(0.2 + fx * 0.4)
	cam.fov_punch(4.0 + 8.0 * fx)


## 空战中碰到地面 / 平台顶面：落地，回到地面状态
func _land() -> void:
	caster.cancel()
	st = St.GROUND
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	velocity = Vector3(velocity.x, 0.0, velocity.z).limit_length(8.0)
	Vfx.step_ring(global_position, Realm.line_color(realm))
	Vfx.dust(global_position, 8, 3.0, 0.8)
	Sfx.play("thud", -6.0)
	cam.add_trauma(0.06)


## 闪现：沿移动方向（没有方向输入时沿镜头朝向）以 blink_spd 冲过 blink 米。
## 炼气/筑基人形冲刺、沿途留残影；结丹起化作光剑。飞行 / 空战中方向含镜头俯仰；地面上只取水平方向。
## 地面上是"闪避"：距离短（DODGE_DIST）、全程无敌。闪现优先级最高：出招任何阶段、格挡、弹开、受击、
## 架势崩溃都能直接打断（只有倒地、处决出刀前不行，见 PlayerMelee.can_dodge）；空战法术三段 / 连发、起飞上升也都能打断。
## 闪避后的下一次攻击会瞬移到敌人身边出手（见 PlayerMelee 的 warp）。返回是否闪出去了
func blink() -> bool:
	var dist: float = realm["blink"]
	if dist <= 0.0 or _blink_cd > 0.0 or _dash_left > 0.0 or ult.active or st == St.DIVE:
		return false
	var ground := st == St.GROUND
	if ground and not melee.can_dodge():
		return false
	if st == St.AIR and not air.can_blink():
		return false
	if st == St.TAKEOFF:
		st = St.FLY  # 起飞上升中也能闪：直接转入飞行，带着闪现冲出去
	caster.cancel()
	if st == St.AIR:
		air.on_blink()
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var b := _fly_basis() if st == St.FLY or st == St.AIR else Basis(Vector3.UP, cam.yaw)
	var dir := b * Vector3(iv.x, 0.0, iv.y)
	if dir.length() < 0.1:
		# 地面没有方向输入：近战中向后撤步，否则沿镜头朝向
		dir = b * (Vector3.BACK if ground and melee.engaged() else Vector3.FORWARD)
	_dash_dir = dir.normalized()
	_dash_spd = realm["blink_spd"]
	if ground:
		dist = DODGE_DIST
		_dash_spd = DODGE_SPD
		_dodge_age = 0.0
		_dodge_from = global_position
		_dodge_perfect = false
		melee.on_dodge()
	_dash_left = dist
	_blink_cd = dist / _dash_spd + (DODGE_CD if ground else BLINK_CD_AIR)
	velocity = _dash_dir * _dash_spd
	var lc := Realm.line_color(realm)
	if is_light_mode():
		_dun_dir = _dash_dir
		_set_dun(true)
		var fx: float = realm["fx"]
		Vfx.dash_start(center(), _dash_dir, lc, fx * (0.5 if ground else 1.0))
		cam.fov_punch((3.0 + 4.0 * fx) if ground else (6.0 + 12.0 * fx))
		cam.add_trauma((0.06 + 0.06 * fx) if ground else (0.15 + 0.2 * fx))
	else:
		_ghost_d = 0.0
		Vfx.body_ghost(visual, _ghost_color(), 0.55, 0.3)
		Vfx.blink_start(global_position, _dash_dir, lc)
		cam.fov_punch(3.5 if ground else 5.0)
		cam.add_trauma(0.06 if ground else 0.08)
	if ground:
		Sfx.play("dodge", -7.0, 1.0)
	return true


## 地面闪避无敌中（闪避全程 + 收尾一小段）
func dodge_iframes() -> bool:
	return _dodge_age < DODGE_DIST / DODGE_SPD + DODGE_IFRAME_TAIL or (_dodge_age < INF and _dash_left > 0.0)


## 敌人判定帧落在这个窗口里就是完美闪避（每次闪避只触发一次）
func in_perfect_window() -> bool:
	return not _dodge_perfect and _dodge_age <= PERFECT_WIN


## 闪避开始时站的位置（判定"本来会不会被砍中"用）
func dodge_origin() -> Vector3:
	return _dodge_from


## 完美闪避（由刀客在判定帧调用）：画面骤慢再加速；原地留一道残影；1s 内的下一次攻击瞬移到它身边
func perfect_dodge(src: Node3D) -> void:
	_dodge_perfect = true
	var lc := Realm.line_color(realm)
	var c := Color.WHITE.lerp(lc, 0.35)
	Combat.slowmo(0.12, 0.38, 0.5)
	Vfx.body_ghost(visual, c, 0.7, 0.6)
	Vfx.perfect_dodge(center(), src.global_position + Vector3(0, 1.0, 0), lc)
	Sfx.play("perfect", -2.0)
	cam.fov_punch(-7.0)
	cam.add_trauma(0.12)
	melee.arm_warp(src, true)


## 立刻结束闪避（闪避中按攻击：直接接瞬移斩）
func stop_dash() -> void:
	if _dash_left <= 0.0:
		return
	_dash_left = 0.0
	velocity = Vector3.ZERO
	if is_light_mode() and st == St.GROUND:
		_set_dun(false)


## 瞬移到 pos（地面闪避反击）：原地留残影，沿途一道细光，落点一圈收拢的细环；镜头平滑追上去
func warp_to(pos: Vector3, yaw: float) -> void:
	var lc := Realm.line_color(realm)
	var from := center()
	Vfx.body_ghost(visual, _ghost_color(), 0.6, 0.35)
	var old := global_position
	global_position = pos
	velocity = Vector3.ZERO
	face_now(yaw)
	Vfx.warp_line(from, center(), lc)
	cam.warp_follow(old - pos)
	cam.fov_punch(6.0)
	Sfx.play("warp", -4.0)


func _ghost_color() -> Color:
	return Color.WHITE.lerp(Realm.line_color(realm), 0.6)


## 按实际位移扣减剩余距离：长帧、贴地滑动都不会让闪现变短；真被挡住（走不到预期三成）才提前结束
func _dash(dt: float) -> void:
	var want := minf(_dash_spd * dt, _dash_left)
	var from := global_position
	velocity = _dash_dir * (want / maxf(dt, 1e-4))
	move_and_slide()
	if global_position.y < 0.0:
		global_position.y = 0.0
	var moved := (global_position - from).dot(_dash_dir)
	_dash_left -= maxf(moved, 0.0)
	if not is_light_mode():
		_ghost_d += maxf(moved, 0.0)
		if _ghost_d >= GHOST_STEP:
			_ghost_d = fmod(_ghost_d, GHOST_STEP)
			Vfx.body_ghost(visual, _ghost_color(), 0.45, 0.26)
	if _dash_left <= 0.01 or moved < want * 0.3:
		_end_dash()


func _end_dash() -> void:
	_dash_left = 0.0
	if is_light_mode():
		var fx: float = realm["fx"]
		Vfx.dash_end(center() + _dash_dir * 0.6, _dash_dir, Realm.line_color(realm), fx)
	if Vector2(_dash_dir.x, _dash_dir.z).length() > 0.1:
		face_now(atan2(-_dash_dir.x, -_dash_dir.z))
	if st == St.FLY:
		# 空中：带着遁速继续飞，不在半空急停
		velocity = _dash_dir * float(realm["speed"])
		_burst_hold = 0.3
	elif st == St.AIR:
		velocity = _dash_dir * AIR_SPEED * 0.6
	else:
		velocity = Vector3(_dash_dir.x, 0.0, _dash_dir.z) * 6.0


## 遁光开关：切换光剑形态（过渡见 _update_morph），并通知飞剑阵同步隐藏
func _set_dun(on: bool) -> void:
	if dun_active == on:
		return
	dun_active = on
	for m in _motes:
		m.visible = on
	if on:
		for t in _trails:
			t.clear()
		for t in _mote_trails:
			t.clear()
		_update_dun_fx(0.0, speed())  # 当帧就把剑芒/剑影摆到位，不留一帧错位
	else:
		Vfx.reappear(center(), Realm.line_color(realm))
	dun_changed.emit(on)


# ---------- 每帧 ----------

func _process(dt: float) -> void:
	_blink_cd -= dt
	if _dodge_age < INF:
		_dodge_age += dt
		if _dodge_age > 1.0 or st != St.GROUND:
			_dodge_age = INF
	if _shift_t >= 0.0:
		_shift_t += dt
	if _blink_buf > 0.0:
		_blink_buf -= dt
		if blink():
			_blink_buf = 0.0
	melee.tick(dt)
	caster.tick(dt)
	air.tick(dt)
	ult.tick(dt)
	if ult.active:
		velocity = Vector3.ZERO  # 大罡剑阵：原地定身
	elif _dash_left > 0.0:
		_dash(dt)
	else:
		match st:
			St.GROUND:
				_ground(dt)
			St.TAKEOFF:
				_takeoff(dt)
			St.FLY:
				_fly(dt)
			St.AIR:
				_air(dt)
			St.DIVE:
				_dive(dt)
	if _slam_t >= 0.0:
		_slam_t += dt
		if _slam_t >= SLAM_RECOVER or st != St.GROUND:
			_slam_t = -1.0
	global_position.x = clampf(global_position.x, -bound, bound)
	global_position.z = clampf(global_position.z, -bound, bound)
	var fx: float = realm["fx"]
	var ratio := 0.0
	if st == St.FLY:
		ratio = speed() / float(realm["speed"])
	cam.set_speed(ratio, fx)
	_air_boost_tick(dt)
	_update_visuals(dt)


## 空战疾行（长按 Shift 加速，且有方向输入）：前冲 / 左右平移分量交给镜头（CameraRig.air_boost）和身体姿态（_boost_pose）；
## 刚按住时迸一圈破空细环；化作遁光后由光剑丝线出效果，人形（施法中）时隔 BOOST_GHOST 秒留一道淡残影、身后拖一束细风丝
func _air_boost_tick(dt: float) -> void:
	var want := Vector2.ZERO
	var iv := Vector2.ZERO
	if st == St.AIR and sprinting() and not ult.active and _dash_left <= 0.0 and not air.busy():
		iv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want = Vector2(iv.x, maxf(-iv.y, 0.0)).limit_length(1.0)
	cam.air_boost = want
	_boost = _boost.lerp(want, 1.0 - exp(-6.0 * dt))
	var on := want.length() > 0.1
	if on and not _boost_on:
		var d := _fly_basis() * Vector3(iv.x, 0.0, iv.y)
		d = d.normalized() if d.length_squared() > 1e-4 else _fly_basis() * Vector3.FORWARD
		_dun_dir = d  # 起步时速度还小，光剑先朝输入方向摆好
		Vfx.dash_start(center(), d, Realm.line_color(realm), 0.4)
		Sfx.play("swing", -10.0, 0.7)
		cam.fov_punch(3.0)
		cam.add_trauma(0.05)
		_boost_ghost = 0.0
	_boost_on = on
	var fast := on and not dun_active and speed() > AIR_SPEED * 1.15
	if fast:
		_boost_ghost -= dt
		if _boost_ghost <= 0.0:
			_boost_ghost = BOOST_GHOST
			Vfx.body_ghost(visual, _ghost_color(), 0.3, 0.22)
	if _boost_wind != null:
		_boost_wind.emitting = fast
		if fast:
			var wf := velocity.normalized()
			_boost_wind.global_basis = Basis.looking_at(wf, Vector3.UP if absf(wf.dot(Vector3.UP)) < 0.98 else Vector3.BACK)


## 空战疾行姿态：叠在 hero.animate 之后——双臂向后斜掠、两腿并拢后拖、前冲时抬头看路（前倾 / 侧倾在 body_root 上）
func _boost_pose() -> void:
	var k := clampf(_boost.length(), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	if k <= 0.001:
		return
	hero.arm_l.rotation.x = lerpf(hero.arm_l.rotation.x, -1.05, k)
	hero.arm_r.rotation.x = lerpf(hero.arm_r.rotation.x, -1.05, k)
	hero.arm_l.rotation.z = lerpf(hero.arm_l.rotation.z, -0.32, k)
	hero.arm_r.rotation.z = lerpf(hero.arm_r.rotation.z, 0.32, k)
	hero.leg_l.rotation.x = lerpf(hero.leg_l.rotation.x, -0.3, k)
	hero.leg_r.rotation.x = lerpf(hero.leg_r.rotation.x, -0.42, k)
	hero.head.rotation.x = lerpf(hero.head.rotation.x, 0.3 * _boost.y, k)


func _ground(dt: float) -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Basis(Vector3.UP, cam.yaw) * Vector3(iv.x, 0.0, iv.y)
	var spd := (10.0 if sprinting() else 6.0) + realm_idx * 0.6
	var on_floor := is_on_floor()
	# 近战：出招/受击时移动交给招式（踏步、滑退），格挡中慢走；顿帧期间战斗对象整体定格
	var mdt := dt
	var want := dir * spd
	var acc := 70.0 if on_floor else 22.0
	var slam_lock := _slam_t >= 0.0 and _slam_t < SLAM_LOCK
	if slam_lock:
		want = Vector3.ZERO  # 砸地蹲伏：先定住一拍
	if melee.engaged():
		mdt = Combat.cdt(dt)
		if sprinting() and not melee.busy():
			want = dir * (spd * 0.8)
		want *= melee.move_mul()
		if melee.drives_motion():
			want = melee.drive_vel
			acc = 160.0
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(want, acc * mdt)
	velocity.x = hv.x
	velocity.z = hv.z
	if melee.vy_set:
		velocity.y = melee.vy  # 空中招式接管竖直速度：空斩悬停、空中弹反弹起
	elif on_floor:
		if Input.is_action_just_pressed("jump") and not slam_lock:
			if is_light_mode():
				take_air()
			else:
				jump()
	else:
		velocity.y -= GRAVITY * mdt * melee.grav_mul
	if melee.engaged() and Combat.frozen():
		pass  # 顿帧：不位移
	else:
		move_and_slide()
	if melee.has_face:
		_facing = lerp_angle(_facing, melee.face_yaw, 1.0 - exp(-(30.0 if melee.busy() else 14.0) * mdt))
	elif dir.length() > 0.1 and melee.move_mul() > 0.0:
		_facing = lerp_angle(_facing, atan2(-dir.x, -dir.z), 1.0 - exp(-12.0 * dt))
	if dir.length() > 0.1 and not melee.busy():
		_bob += mdt * hv.length() * 1.6


## 地面起跳
func jump() -> bool:
	if st != St.GROUND or not is_on_floor() or not melee.can_jump():
		return false
	velocity.y = 8.5 + realm_idx * 1.2
	melee.on_jump()
	return true


## 受击抖动：顿帧期间身体原地小幅乱抖（只动 body_root 的水平偏移）
func hit_shake(sec: float) -> void:
	_shake = maxf(_shake, sec)


func _takeoff(dt: float) -> void:
	_takeoff_t += dt
	var u := clampf(_takeoff_t / _takeoff_dur, 0.0, 1.0)
	var h: float = realm["rise"]
	# 线性减速上冲，总位移 = rise，到顶时速度归零
	velocity = Vector3.UP * (2.0 * h / _takeoff_dur) * (1.0 - u)
	move_and_slide()
	if u >= 1.0:
		st = St.FLY
		if is_light_mode():
			# 到顶后向镜头前方破空而出
			var fwd := cam.flat_forward()
			velocity = fwd * float(realm["speed"])
			_burst_hold = 0.55
			var fx: float = realm["fx"]
			Vfx.launch_ring(center(), fwd, Realm.line_color(realm), 0.7 + fx * 1.6)
			cam.add_trauma(0.25 + fx * 0.5)
			cam.fov_punch(4.0 + 8.0 * fx)


## 镜头俯仰 → 飞行俯仰：默认俯视角对应平飞，低头/抬头到镜头极限时接近垂直下降/上升
func _fly_pitch() -> float:
	var p := cam.pitch - CameraRig.PITCH_DEFAULT
	var lim := (CameraRig.PITCH_MAX - CameraRig.PITCH_DEFAULT) if p > 0.0 else (CameraRig.PITCH_DEFAULT - CameraRig.PITCH_MIN)
	return clampf(p / lim, -1.0, 1.0) * PI * 0.47


func _fly_basis() -> Basis:
	return Basis.from_euler(Vector3(_fly_pitch(), cam.yaw, 0.0))


func _fly(dt: float) -> void:
	if is_light_mode() and Input.is_action_just_pressed("jump"):
		_fly_to_air()
		return
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# 飞行方向完全跟随镜头：前后沿镜头视线（含俯仰），左右水平平移
	var dir := _fly_basis() * Vector3(iv.x, 0.0, iv.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var base: float = realm["speed"]
	var top := base * (float(realm["boost"]) if sprinting() else 1.0)
	var has_input := dir.length() > 0.05
	if has_input:
		_burst_hold = 0.0
	_burst_hold -= dt
	if has_input or _burst_hold <= 0.0:
		var acc := base * (3.0 if has_input else 1.6)
		velocity = velocity.move_toward(dir * top, acc * dt)
	var ceil_h: float = realm["ceiling"]
	if ceil_h > 0.0:
		ceil_h += ground_ref
	if ceil_h > 0.0 and global_position.y > ceil_h - 3.0:
		velocity.y = minf(velocity.y, (ceil_h - global_position.y) * 2.0)
	move_and_slide()
	if global_position.y < 0.0:
		global_position.y = 0.0


## 空战：人形悬空，移动方向跟随镜头（低头下降、抬头上升），没有输入时就地悬停；
## 刚腾空的 AIR_RISE 秒内向上托起。往下飞碰到地面 / 平台顶面即落地
func _air(dt: float) -> void:
	_air_t += dt
	if air.drives():
		# 拳脚出招 / 突进 / 受击：位移交给招式；顿帧时原地定格
		if not Combat.frozen():
			velocity = air.drive_vel
			move_and_slide()
			if global_position.y < 0.0:
				global_position.y = 0.0
		return
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _fly_basis() * Vector3(iv.x, 0.0, iv.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var want := dir * AIR_SPEED * (AIR_SPRINT if sprinting() else 1.0) * air.move_mul()
	var rising := _air_t < AIR_RISE
	if rising:
		want.y = maxf(want.y, AIR_RISE_V * (1.0 - _air_t / AIR_RISE))
	velocity = velocity.move_toward(want, AIR_ACC * (3.0 if rising else 1.0) * dt)
	var ceil_h: float = realm["ceiling"]
	if ceil_h > 0.0:
		ceil_h += ground_ref
	if ceil_h > 0.0 and global_position.y > ceil_h - 3.0:
		velocity.y = minf(velocity.y, (ceil_h - global_position.y) * 2.0)
	var vy := velocity.y
	move_and_slide()
	if global_position.y < 0.0:
		global_position.y = 0.0
	if not rising and vy <= 0.5 and _touching_floor():
		_land()


func _touching_floor() -> bool:
	if global_position.y <= 0.02:
		return true
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().y > 0.7:
			return true
	return false


func _update_visuals(dt: float) -> void:
	var spd := speed()
	var base: float = realm["speed"]
	var flying := st != St.GROUND
	var light := is_light_mode()

	# 遁光判定：闪现全程 + 起飞全程 + 飞行中有速度时。进/出用不同阈值，悬停附近不闪；
	# 空战中平时保持人形，长按 Shift 疾行时化作遁光（施法中除外：要现身出手）
	var want := false
	if light and (st == St.TAKEOFF or st == St.FLY or _dash_left > 0.0):
		want = _dash_left > 0.0 or st == St.TAKEOFF or spd > base * (0.08 if dun_active else 0.2)
	elif st == St.AIR and _boost_on and not caster.busy() and not ult.active and not air.busy():
		want = true
	if st == St.DIVE:
		want = true  # 俯冲全程是光剑
	_set_dun(want)
	_update_morph(dt)

	var hspd := Vector2(velocity.x, velocity.z).length()
	if ult.active:
		_facing = lerp_angle(_facing, ult.face_yaw, 1.0 - exp(-20.0 * dt))
	elif st == St.AIR and _dash_left <= 0.0:
		# 空战：面朝镜头方向（左右是平移），施法时转向目标
		var fy := cam.yaw
		var rate := 8.0
		if caster.busy():
			fy = caster.face_yaw
			rate = 20.0
		elif air.has_face:
			fy = air.face_yaw
			rate = 30.0 if air.busy() else 12.0
		_facing = lerp_angle(_facing, fy, 1.0 - exp(-rate * dt))
	elif flying and hspd > 1.0:
		_facing = lerp_angle(_facing, atan2(-velocity.x, -velocity.z), 1.0 - exp(-10.0 * dt))
	visual.rotation.y = _facing

	# 身体姿态：地面走路起伏，御剑前倾，空战随速度微微前倾
	var grounded := not flying and is_on_floor()
	var lean := 0.0
	if st == St.AIR:
		# 疾行前冲再多压低上身，像破空俯冲
		lean = -clampf(hspd / AIR_SPEED, 0.0, 1.5) * 0.15 - 0.35 * _boost.y
		if air.busy():
			lean = 0.0  # 拳脚出招：前倾交给招式姿势（spin 节点）
	elif flying and not light:
		lean = -clampf(hspd / base, 0.0, 1.2) * 0.3
	elif not flying:
		lean = -clampf(hspd / 12.0, 0.0, 1.0) * 0.12
	var sq := _slam_squash()
	body_root.rotation.x = lerpf(body_root.rotation.x, lean, 1.0 - exp(-8.0 * dt))
	body_root.rotation.z = lerpf(body_root.rotation.z, -0.42 * _boost.x, 1.0 - exp(-8.0 * dt))  # 疾行侧移：向移动方向侧倾
	if sq > 0.0:
		body_root.rotation.x = -0.32 * sq  # 砸地蹲伏：上身前压
	# 化剑收细（_morph）× 砸地蹲伏压扁（脚底是原点，压扁不会陷进地里）
	var me := _morph * _morph * (3.0 - 2.0 * _morph)
	body_root.scale = Vector3((1.0 - 0.9 * me) * (1.0 + 0.4 * sq), (1.0 + 0.3 * me) * (1.0 - 0.34 * sq),
			(1.0 - 0.9 * me) * (1.0 + 0.4 * sq))
	body_root.position.y = absf(sin(_bob)) * 0.05 if grounded else 0.0
	if flying:
		body_root.position.y = 0.12 + sin(Time.get_ticks_msec() * 0.003) * 0.04
		body_root.position.y -= 0.72 * air.lie_k()  # 被砸到地面：躺平贴地
	if _shake > 0.0:
		_shake -= minf(dt, Combat.MAX_DT)
		var a := 0.035 * clampf(_shake / 0.1, 0.0, 1.0)
		body_root.position.x = randf_range(-a, a)
		body_root.position.z = randf_range(-a, a)
	else:
		body_root.position.x = 0.0
		body_root.position.z = 0.0
	_update_ascend(dt, grounded)
	if not dun_active:
		var move := clampf(hspd / 7.0, 0.0, 1.0) if grounded and not melee.busy() else 0.0
		var adt := Combat.cdt(dt) if melee.engaged() or air.busy() else dt
		hero.animate(adt, _bob, move, not flying and not grounded, flying)
		melee.post_animate(adt)
		spin.rotation = air.spin_euler() if st == St.AIR else Vector3.ZERO
		_boost_pose()  # 放在施法姿势之前：边疾行边施法时手臂听施法的
		caster.apply_pose(hero)
		ult.apply_pose(hero)
	melee_k = lerpf(melee_k, 1.0 if melee.engaged() else 0.0, 1.0 - exp(-6.0 * dt))

	var riding := flying and not light
	foot_sword.visible = riding
	if _wind != null:
		var wind_on := flying and int(realm["mode"]) == Realm.Mode.WIND and spd > 3.0
		_wind.emitting = wind_on
		if wind_on:
			# 风丝沿本地 +Z 喷出：让 -Z 对准飞行方向，丝就向身后掠
			var wf := velocity / spd
			_wind.global_basis = Basis.looking_at(wf, Vector3.UP if absf(wf.dot(Vector3.UP)) < 0.98 else Vector3.BACK)

	_update_dun_fx(dt, spd)

	_spin += dt * (6.0 + spd * 0.12)
	for i in _trails.size():
		if light:
			_trails[i].emitting = dun_active
		else:
			_trails[i].emitting = riding and spd > 3.0 and i == 0
	for t in _mote_trails:
		t.emitting = dun_active


## 人形 ↔ 光剑的过渡：身形收细拉长、整身染成遁光色，光剑从剑心长出并由竖直转向飞行方向；
## 完全化剑后人形隐去。反向时光剑缩回、人形由光色褪回原色
func _update_morph(dt: float) -> void:
	var goal := 1.0 if dun_active else 0.0
	if _morph == goal:
		return
	# 闪现、俯冲、砸地现身都几乎瞬间完成
	var quick := _dash_left > 0.0 or st == St.DIVE or _slam_t >= 0.0
	var dur := MORPH_DASH if quick else (MORPH_IN if dun_active else MORPH_OUT)
	var was := _morph
	_morph = move_toward(_morph, goal, dt / dur)
	var lc := Realm.line_color(realm)
	if was < 1.0 and _morph >= 1.0:
		Vfx.sword_form(center(), lc)
	var e := _morph * _morph * (3.0 - 2.0 * _morph)
	visual.visible = _morph < 1.0
	hero.set_glow(minf(e * 1.6, 1.0), lc)
	_lsword.visible = _morph > 0.0
	_tip.visible = _morph > 0.0


## 砸地蹲伏程度 0~1：触地瞬间压到底，SLAM_LOCK 后回弹站直
func _slam_squash() -> float:
	if _slam_t < 0.0:
		return 0.0
	if _slam_t < 0.04:
		return _slam_t / 0.04
	var u := clampf((_slam_t - 0.04) / (SLAM_RECOVER - 0.04), 0.0, 1.0)
	return 1.0 - u * u * (3.0 - 2.0 * u)


## 光剑摆位：剑心在身体中心，剑尖朝飞行方向，剑面朝向镜头；长度有像素下限，远镜头下仍读得出剑形
func _place_light_sword() -> void:
	var e := _morph * _morph * (3.0 - 2.0 * _morph)
	var c := center()
	var length := maxf(LSWORD_LEN, Vfx.px_size(c) * 64.0) * lerpf(0.35, 1.0, e)
	var f := Vector3.UP.lerp(_dun_dir, e)
	f = f.normalized() if f.length_squared() > 1e-4 else _dun_dir
	_lsword_tail = c - f * length * 0.5
	var to_cam := Vector3.BACK
	var vc := get_viewport().get_camera_3d()
	if vc != null:
		to_cam = (vc.global_position - c).normalized()
	var x := f.cross(to_cam)
	if x.length_squared() < 1e-5:
		x = f.cross(Vector3.FORWARD if absf(f.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	# 光剑网格从剑首 y≈-0.52 到剑尖 y=0.72，全长 1.24、中点 y=0.1
	var s := length / 1.24
	_lsword.global_transform = Transform3D(Basis(x * s, f * s, x.cross(f) * s), c - f * (0.1 * s))
	(_tip.material_override as ShaderMaterial).set_shader_parameter("alpha", e)
	Vfx.place_streak(_tip, c + f * length * 0.05, f, length * 1.35, length * 0.2)


## 光剑、伴飞剑影、剥落细丝的摆位
func _update_dun_fx(dt: float, spd: float) -> void:
	if st == St.DIVE:
		_dun_dir = _dive_dir  # 蓄势上提那一拍剑尖也朝下
	elif spd > 0.5:
		_dun_dir = velocity / spd
	_glow.light_energy = lerpf(_glow.light_energy, 0.5 if dun_active else 0.0, 1.0 - exp(-10.0 * dt))
	if _fila != null and _fila.emitting != dun_active:
		_fila.emitting = dun_active
	if dun_active or _morph > 0.0:
		_place_light_sword()
	if not dun_active:
		return
	var c := center()
	var f := _dun_dir
	var px := Vfx.px_size(c)

	if _fila != null:
		var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.98 else Vector3.BACK
		_fila.global_basis = Basis.looking_at(f, up)

	# 微型剑影：错落跟在头部后方、绕轨迹缓慢转动，剑尖朝前
	_mote_ang += dt * 1.6
	var r := _dun_side()
	var u := r.cross(f)
	var k := clampf(px * 110.0, 1.0, 2.4)
	var mlen := clampf(px * 30.0, 0.5, 2.6)
	var n := _motes.size()
	for i in n:
		var ang := _mote_ang + TAU * float(i) / float(n) + 0.6
		var rad := (0.7 + 0.2 * float(i % 2)) * k
		var back := (1.0 + 1.1 * float(i)) * k
		var p := c - f * back + (r * cos(ang) + u * sin(ang)) * rad
		Vfx.place_streak(_motes[i], p, f, mlen, mlen * 0.24)
		_mote_pos[i] = p - f * mlen * 0.5
