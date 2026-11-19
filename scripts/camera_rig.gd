class_name CameraRig
extends Node3D
## 第三人称跟随相机。
## 速度感：FOV 随速度加宽、镜头拉远、径向模糊强度、镜头抖动；
## 起飞：希区柯克变焦（FOV 加宽的同时推近，主体大小不变、背景被"拉走"），结束后镜头弹开拉远。
## 所有强度都乘以境界的 fx 系数，境界越高越夸张。

const BASE_FOV := 62.0
const MAX_FOV := 118.0
const SENS := 0.0025
const PITCH_MIN := -1.4
const PITCH_MAX := 1.3
const PITCH_DEFAULT := -0.26

var target: Player
var cam := Camera3D.new()
var yaw := 0.0
var pitch := PITCH_DEFAULT
var zoom := 6.5
var capture_mouse := true

## 供后处理读取
var blur_strength := 0.0

var _fov := BASE_FOV
var _dist := 6.5
var _k := 0.0          # 平滑后的速度比
var _k_target := 0.0
var _fx := 0.0
var _dolly_t := -1.0
var _dolly_dur := 0.5
var _dolly_fx := 0.0
var _dolly_f0 := BASE_FOV
var _dolly_d0 := 6.5
var _trauma := 0.0
var _punch := 0.0
var _noise := FastNoiseLite.new()
var _nt := 0.0

## 近战：镜头轻度偏向当前目标——取景中心移向两人之间；目标偏出视野较多时才缓慢转过去（有死区，不抢操作）
var focus: Node3D = null
var focus_mix := 0.35   # 取景中心向目标偏移的比例
var focus_yaw := true   # 是否自动转向目标（演示截图时关掉，用固定机位）
var _focus_k := 0.0
var _push := 0.0        # 命中时的镜头前推（0~1，按距离比例）
var _mouse_idle := 0.0
## 空战：持剑跳起时取景中心略抬高、略拉远；近战中竖直方向缓一点跟，下砸/跳斩时镜头不硬甩
var _air_k := 0.0
var _py := 0.0
## 法术空战（结丹起腾空）：过肩机位，角色让到画面左下，准星（画面中心）不被身体挡住
var _shoulder := 0.0
var _warp_off := Vector3.ZERO
## 技能演出镜头（R 大罡剑阵，见 gate_array.gd）：cine_k > 0 时把跟随机位按比例混到 cine_xf / cine_fov，
## cine_k = 1 即完全接管（硬切）；镜头抖动照旧叠在上面。跟随机位的 yaw / pitch 不受影响，演出结束后直接混回去
var cine_k := 0.0
var cine_xf := Transform3D.IDENTITY
var cine_fov := BASE_FOV
## 遁光砸地（见 Player._start_dive / _slam）：俯冲时取景中心竖直方向滞后跟随（最多 DIVE_LAG 米），光剑往画面下方坠；
## 砸地那一帧镜头立刻前推、收窄视野、往下一沉再弹回（_thump），配合全屏顿帧
const DIVE_LAG := 2.6
var _dive_k := 0.0
var _thump := -1.0      # 砸地后已过时间，-1 = 无
var _thump_a := 0.0
## 空战疾行（法术空战长按 Shift，见 Player._air_boost_tick）：前冲时镜头稍微拉远；左右平移也拉远，并往反方向落后一点；
## 视野略放宽。进出都走曲线：_boost_u 按 BOOST_IN / BOOST_OUT 匀速推进，再过 smoothstep（起步缓 → 中段快 → 到位缓），
## 前冲 / 平移之间换向时方向分量也是平滑过渡，不会一下跳过去
const BOOST_IN := 0.5       # 按住后拉远到位用时
const BOOST_OUT := 0.7      # 松开后回位用时
const BOOST_PULL_F := 0.22  # 前冲：距离加长比例
const BOOST_PULL_S := 0.16  # 左右平移：距离加长比例
const BOOST_LAG_S := 0.45   # 左右平移：镜头往反方向落后（米）
const BOOST_FOV := 6.0
var air_boost := Vector2.ZERO   # Player 每帧给：x 左右平移（-1~1，右为正），y 前冲（0~1）；不在疾行为零
var _boost_u := 0.0
var _boost_dir := Vector2.ZERO
## Boss 空战锁定（见 boss_arena.gd）：lock 有效时镜头拉远到 lock_zoom 以上、视野放宽，
## 鼠标停手 LOCK_IDLE 秒后自动把镜头转回 lock 的瞄准点（玩家照样可以随时用鼠标甩开）
const LOCK_IDLE := 0.45
const LOCK_FOV := 8.0
var lock: Node3D = null
var lock_zoom := 15.0
var _lock_k := 0.0
## 起伏地形（木兰草原，见 meadow_level.gd）：func(x, z) -> 地面高度，镜头不低于地面 FLOOR_GAP 米；空 = 平地 y=0
const FLOOR_GAP := 0.6
var floor_fn := Callable()


func _ready() -> void:
	process_priority = 20
	add_child(cam)
	cam.current = true
	cam.near = 0.1
	cam.far = 4000.0
	cam.fov = BASE_FOV
	# 微缩模型感：只虚化远景，不碰可玩区域
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 260.0
	attr.dof_blur_far_transition = 500.0
	attr.dof_blur_amount = 0.05
	cam.attributes = attr
	_noise.frequency = 1.0
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := e as InputEventMouseMotion
		_mouse_idle = 0.0
		yaw -= mm.relative.x * SENS
		pitch = clampf(pitch - mm.relative.y * SENS, PITCH_MIN, PITCH_MAX)
	elif e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(zoom - 0.6, 3.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(zoom + 0.6, 16.0)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func look_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func flat_forward() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD


## speed_ratio: 当前速度/境界遁速；fx: 境界效果系数
func set_speed(speed_ratio: float, fx: float) -> void:
	_k_target = speed_ratio
	_fx = fx


func start_dolly(dur: float, fx: float) -> void:
	_dolly_t = 0.0
	_dolly_dur = dur
	_dolly_fx = fx
	_dolly_f0 = _fov
	_dolly_d0 = _dist


## 立即切到指定机位，不走平滑（自动演示截图用；zoom 可小于滚轮下限以拍近景）
func snap(new_yaw: float, new_pitch: float, new_zoom: float) -> void:
	yaw = new_yaw
	pitch = new_pitch
	zoom = new_zoom
	_dist = new_zoom


func add_trauma(v: float) -> void:
	_trauma = minf(_trauma + v, 1.0)


## deg > 0 加宽视野（冲刺感），deg < 0 收窄（完美闪避的一下"凝视"）
func fov_punch(deg: float) -> void:
	if absf(deg) > absf(_punch):
		_punch = deg


## 主角瞬移：取景中心从旧位置平滑追到新位置（offset = 旧位置 - 新位置），不硬切
func warp_follow(offset: Vector3) -> void:
	_warp_off += offset


## 命中前推：镜头距离短促缩短 v（比例），随后弹回
func push_in(v: float) -> void:
	_push = maxf(_push, v)


## 砸地：压近 + 视野收窄 + 镜头下沉一下再弹回 + 震动
func slam(power: float) -> void:
	_push = maxf(_push, 0.3 * minf(power, 1.3))
	_punch = -8.0 * power
	add_trauma(0.45 * power)
	_thump = 0.0
	_thump_a = 0.45 * power


func _process(dt: float) -> void:
	if target == null:
		return
	_k = lerpf(_k, _k_target, 1.0 - exp(-3.5 * dt))
	var k := clampf(_k, 0.0, 1.5)
	var locked := is_instance_valid(lock) and lock.is_inside_tree()
	_lock_k = move_toward(_lock_k, 1.0 if locked else 0.0, dt * 0.8)
	var lk := _lock_k * _lock_k * (3.0 - 2.0 * _lock_k)
	var fov_t := minf(BASE_FOV + (6.0 + 44.0 * _fx) * k + LOCK_FOV * lk, MAX_FOV)
	var dist_t := zoom * (1.0 + (0.25 + 1.75 * _fx) * k)
	dist_t = lerpf(dist_t, maxf(dist_t, lock_zoom), lk)
	blur_strength = clampf(k * (0.12 + 0.88 * _fx), 0.0, 1.3)

	if _dolly_t >= 0.0:
		_dolly_t += dt
		var u := clampf(_dolly_t / _dolly_dur, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		var widen := 12.0 + 40.0 * _dolly_fx
		_fov = lerpf(_dolly_f0, minf(_dolly_f0 + widen, MAX_FOV - 2.0), e)
		# 保持主体屏占比：dist * tan(fov/2) = 常量
		_dist = _dolly_d0 * tan(deg_to_rad(_dolly_f0) * 0.5) / tan(deg_to_rad(_fov) * 0.5)
		blur_strength = maxf(blur_strength, e * (0.15 + 0.6 * _dolly_fx))
		if u >= 1.0:
			_dolly_t = -1.0
	else:
		_fov = lerpf(_fov, fov_t, 1.0 - exp(-4.0 * dt))
		_dist = lerpf(_dist, dist_t, 1.0 - exp(-2.6 * dt))

	_punch = lerpf(_punch, 0.0, 1.0 - exp(-7.0 * dt))
	_trauma = maxf(_trauma - dt * 1.7, 0.0)
	_nt += dt * 28.0
	var shake := _trauma * _trauma + blur_strength * 0.06
	var sx := _noise.get_noise_2d(_nt, 0.0) * shake * 0.035
	var sy := _noise.get_noise_2d(0.0, _nt) * shake * 0.035
	var sz := _noise.get_noise_2d(_nt, _nt) * shake * 0.02

	_mouse_idle += dt
	_push = lerpf(_push, 0.0, 1.0 - exp(-9.0 * dt))
	var fv := is_instance_valid(focus) and target.st == Player.St.GROUND
	_focus_k = lerpf(_focus_k, 1.0 if fv else 0.0, 1.0 - exp(-3.0 * dt))
	var melee_on := target.st == Player.St.GROUND and target.melee != null and target.melee.engaged()
	var air := melee_on and target.melee.air_combat()
	_air_k = lerpf(_air_k, 1.0 if air else 0.0, 1.0 - exp(-4.0 * dt))
	_warp_off = _warp_off.lerp(Vector3.ZERO, 1.0 - exp(-11.0 * dt))
	var pivot := target.global_position + _warp_off + Vector3(0.0, 1.45 + 0.35 * _air_k, 0.0)
	_dive_k = 1.0 if target.st == Player.St.DIVE else move_toward(_dive_k, 0.0, dt * 2.5)
	if melee_on:
		_py = lerpf(_py, pivot.y, 1.0 - exp(-10.0 * dt))
		pivot.y = _py
	elif _dive_k > 0.0:
		# 俯冲：竖直滞后跟随，落地后再追上去
		_py = lerpf(_py, pivot.y, 1.0 - exp(-lerpf(30.0, 8.0, _dive_k) * dt))
		_py = clampf(_py, pivot.y - 0.3, pivot.y + DIVE_LAG)
		pivot.y = _py
	else:
		_py = pivot.y
	if _thump >= 0.0:
		_thump += dt
		# 当帧沉到底，随后带一点回弹地回到原位
		pivot.y -= _thump_a * exp(-_thump * 9.0) * cos(_thump * 16.0)
		if _thump > 0.6:
			_thump = -1.0
	if _focus_k > 0.01 and is_instance_valid(focus):
		var d := focus.global_position - target.global_position
		d.y = 0.0
		var dl := d.length()
		if dl > 0.5:
			if focus_yaw and _mouse_idle > 0.6:
				var want := atan2(-d.x, -d.z)
				var diff := wrapf(want - yaw, -PI, PI)
				var over := signf(diff) * maxf(absf(diff) - 0.55, 0.0)
				yaw += over * (1.0 - exp(-2.2 * dt)) * _focus_k
			pivot += d.limit_length(3.0) * focus_mix * _focus_k
	if locked and _mouse_idle > LOCK_IDLE:
		# 锁定：转向 Boss 的瞄准点（偏航 + 俯仰都转），越久没动鼠标转得越干脆
		var lp: Vector3 = lock.call("aim_point") if lock.has_method("aim_point") else lock.global_position
		var ld := lp - pivot
		var lh := Vector2(ld.x, ld.z).length()
		if lh > 1.0:
			var w := (1.0 - exp(-2.4 * dt)) * lk * clampf((_mouse_idle - LOCK_IDLE) / 0.5, 0.0, 1.0)
			yaw += wrapf(atan2(-ld.x, -ld.z) - yaw, -PI, PI) * w
			pitch = lerpf(pitch, clampf(atan2(ld.y, lh) - 0.05, PITCH_MIN + 0.2, 0.95), w)
	_shoulder =lerpf(_shoulder, 1.0 if target.st == Player.St.AIR else 0.0, 1.0 - exp(-5.0 * dt))
	# 空战疾行：拉远 + 平移时落后 + 视野放宽，全部乘曲线后的 be
	var bon := air_boost.length() > 0.05
	_boost_u = move_toward(_boost_u, 1.0 if bon else 0.0, dt / (BOOST_IN if bon else BOOST_OUT))
	if bon:
		_boost_dir = _boost_dir.lerp(air_boost, 1.0 - exp(-5.0 * dt))  # 松开后保持最后的方向回位
	var be := _boost_u * _boost_u * (3.0 - 2.0 * _boost_u)
	var pull := be * (BOOST_PULL_F * _boost_dir.y + BOOST_PULL_S * absf(_boost_dir.x))
	var b := look_basis()
	var pos := pivot + b * Vector3(1.25 * _shoulder - be * BOOST_LAG_S * _boost_dir.x, 0.3 + 0.25 * _shoulder,
			_dist * (1.0 - _push) * (1.0 + 0.12 * _air_k) * (1.0 + pull))
	pos.y = maxf(pos.y, 0.25)
	if floor_fn.is_valid():
		pos.y = maxf(pos.y, float(floor_fn.call(pos.x, pos.z)) + FLOOR_GAP)
	global_transform = Transform3D(b, pos)
	cam.rotation = Vector3(sx, sy, sz)
	cam.fov = clampf(_fov + _punch + BOOST_FOV * be * minf(_boost_dir.length(), 1.0), 30.0, 122.0)
	blur_strength = maxf(blur_strength, 0.22 * be * minf(_boost_dir.length(), 1.0))
	if cine_k > 0.001:
		var e := clampf(cine_k, 0.0, 1.0)
		e = e * e * (3.0 - 2.0 * e)
		global_transform = global_transform.interpolate_with(cine_xf, e)
		cam.fov = clampf(lerpf(cam.fov, cine_fov + _punch, e), 30.0, 122.0)
