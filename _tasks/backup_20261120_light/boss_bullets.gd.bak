extends Node3D
## Boss 弹幕池：所有弹体放在两张 MultiMesh 里画（圆弹 / 针弹），材质是 shaders/boss_bullet.gdshader——
## 朝相机的发光弹：白芯 + 主色弹身 + 亮环 + 深色描边，INSTANCE_CUSTOM = (飞行方向, 半径)，针弹沿飞行方向拉长。
## 每颗弹的运动在 CPU 上推进（PackedArray 存储，swap-remove 删除），每帧整块写回 MultiMesh.buffer。
## 弹道参数：初速 vel、加速度 acc（向 vmax 靠拢）、绕轴旋转 curl（轴 × 角速度，弧线弹）、
## hold 悬停（到点后若 aim > 0 就以 aim 的速度朝"那一刻"玩家的位置射出：锁定当时的位置）、
## split 计时到点后炸成一圈 split_n 颗小弹。
## 判定：弹体这一帧扫过的线段离玩家胸口小于 (半径 × HIT_K + PLAYER_R) 即命中，回调 on_hit。
## 判定比画面小一圈（弹幕游戏惯例），擦着弹身过去不算中弹。
## 故意不写 class_name：用 preload 引用。

const SHADER := preload("res://shaders/boss_bullet.gdshader")
const CAP := 1800            # 同屏上限
const STRIDE := 20           # 每实例：变换 12 + 颜色 4 + 自定义 4
const FADE_IN := 0.12
const FADE_OUT := 0.25
const HIT_K := 0.55
const PLAYER_R := 0.42
const NEEDLE_STRETCH := 3.2
## 统一弹体尺寸（半径，米）：所有招式只用这三档，不再各写各的
const R_ROUND := 0.75        # 普通圆弹
const R_NEEDLE := 0.5        # 针弹（画面上再沿飞行方向拉长 NEEDLE_STRETCH 倍）
const R_BIG := 1.25          # 大弹：会炸裂的母弹、血莲正中那颗
## 近镜头限制：弹体投到屏幕上的半径不超过 距离 × MAX_ANG（从镜头边擦过的弹不会糊满一屏）；
## 锁定镜头约 14m 外的玩家身边不受影响，判定不变
const MAX_ANG := 0.05

enum K { ROUND, NEEDLE }

var target: Player
var on_hit: Callable        # func(pos: Vector3, dir: Vector3, dmg: float)
var can_hit: Callable       # func() -> bool：玩家此刻是否吃判定（闪现中、受击无敌中返回 false）

var _mm: Array[MultiMesh] = []
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _curl := PackedVector3Array()   # 旋转轴 × 角速度（rad/s）
var _col := PackedColorArray()
var _r := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _acc := PackedFloat32Array()
var _vmax := PackedFloat32Array()
var _hold := PackedFloat32Array()
var _aim := PackedFloat32Array()     # 悬停结束后锁定射出的速度，0 = 不锁定
var _split := PackedFloat32Array()   # 炸裂倒计时，<=0 不炸
var _split_n := PackedInt32Array()
var _kind := PackedByteArray()
var _harm := PackedByteArray()       # 0 = 已被清屏，只剩消散动画
var _dmg := PackedFloat32Array()
var _pending: Array = []


func _ready() -> void:
	for k in 2:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("stretch", 1.0 if k == K.ROUND else NEEDLE_STRETCH)
		mat.set_shader_parameter("core", 0.4 if k == K.ROUND else 0.3)
		mat.set_shader_parameter("max_ang", MAX_ANG)
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = q
		mm.instance_count = CAP
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 弹体在顶点着色器里才展开成面片：包围盒给大一点，别被视锥剔掉
		mmi.custom_aabb = AABB(Vector3(-3000, -200, -3000), Vector3(6000, 1000, 6000))
		add_child(mmi)
		_mm.append(mm)


func count() -> int:
	return _pos.size()


## 发一颗弹。opts: acc | vmax | curl (Vector3 轴×角速度) | hold | aim | split | split_n | life | dmg | harm（false = 只作声势）
func spawn(pos: Vector3, vel: Vector3, r: float, col: Color, kind := K.ROUND, opts := {}) -> void:
	if _pos.size() >= CAP:
		return
	_pos.append(pos)
	_vel.append(vel)
	_curl.append(opts.get("curl", Vector3.ZERO))
	_col.append(col)
	_r.append(r)
	_age.append(0.0)
	_life.append(float(opts.get("life", 6.0)))
	_acc.append(float(opts.get("acc", 0.0)))
	_vmax.append(float(opts.get("vmax", vel.length())))
	_hold.append(float(opts.get("hold", 0.0)))
	_aim.append(float(opts.get("aim", 0.0)))
	_split.append(float(opts.get("split", 0.0)))
	_split_n.append(int(opts.get("split_n", 0)))
	_kind.append(kind)
	_harm.append(1 if bool(opts.get("harm", true)) else 0)
	_dmg.append(float(opts.get("dmg", 10.0)))


## 清屏（转阶段 / 击败 / 玩家倒下）：所有弹立刻失去判定，放慢、胀大一点后在 dur 内淡掉
func clear_all(dur := 0.35) -> void:
	for i in _pos.size():
		_harm[i] = 0
		_vel[i] = _vel[i] * 0.15
		_hold[i] = 0.0
		_aim[i] = 0.0
		_split[i] = 0.0
		_life[i] = minf(_life[i], _age[i] + dur * randf_range(0.6, 1.0))
	_pending.clear()


## 立刻全部移除（重置用）
func wipe() -> void:
	_resize(0)
	_pending.clear()
	for mm in _mm:
		mm.visible_instance_count = 0


## Packed 数组是值类型：放进 Array 里循环改只会改到副本，所以逐个写
func _resize(n: int) -> void:
	_pos.resize(n)
	_vel.resize(n)
	_curl.resize(n)
	_col.resize(n)
	_r.resize(n)
	_age.resize(n)
	_life.resize(n)
	_acc.resize(n)
	_vmax.resize(n)
	_hold.resize(n)
	_aim.resize(n)
	_split.resize(n)
	_split_n.resize(n)
	_kind.resize(n)
	_harm.resize(n)
	_dmg.resize(n)


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_curl[i] = _curl[last]
		_col[i] = _col[last]
		_r[i] = _r[last]
		_age[i] = _age[last]
		_life[i] = _life[last]
		_acc[i] = _acc[last]
		_vmax[i] = _vmax[last]
		_hold[i] = _hold[last]
		_aim[i] = _aim[last]
		_split[i] = _split[last]
		_split_n[i] = _split_n[last]
		_kind[i] = _kind[last]
		_harm[i] = _harm[last]
		_dmg[i] = _dmg[last]
	_resize(last)


## 炸裂：球面均匀撒 n 颗（黄金角螺旋），整体随机转一下，每次炸开的花样不一样
func _burst(pos: Vector3, n: int, col: Color, dmg: float) -> void:
	var rot := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0.0))
	for k in n:
		var y := 1.0 - 2.0 * (float(k) + 0.5) / float(n)
		var rr := sqrt(maxf(1.0 - y * y, 0.0))
		var a := 2.39996 * float(k)
		var d := rot * Vector3(cos(a) * rr, y, sin(a) * rr)
		_pending.append([pos, d * 9.5, R_ROUND, col, K.ROUND, {"acc": 3.0, "vmax": 14.0, "life": 4.5, "dmg": dmg * 0.6}])


func _process(dt: float) -> void:
	dt = minf(dt, 1.0 / 20.0)
	var pc := target.center() if is_instance_valid(target) else Vector3(0, -9999, 0)
	var vulnerable: bool = can_hit.is_valid() and can_hit.call()
	var i := 0
	while i < _pos.size():
		_age[i] += dt
		if _age[i] >= _life[i]:
			_remove(i)
			continue
		var p0 := _pos[i]
		if _hold[i] > 0.0:
			_hold[i] -= dt
			if _hold[i] <= 0.0 and _aim[i] > 0.0:
				# 锁定：朝玩家"此刻"的位置射出，之后不再追
				var to := pc - p0
				_vel[i] = (to.normalized() if to.length_squared() > 1e-4 else Vector3.FORWARD) * _aim[i]
				_vmax[i] = maxf(_vmax[i], _aim[i])
			i += 1
			continue
		var v := _vel[i]
		var c := _curl[i]
		if c != Vector3.ZERO:
			var w := c.length()
			v = v.rotated(c / w, w * dt)
		if _acc[i] != 0.0:
			var s := v.length()
			if s > 1e-4:
				v = v / s * move_toward(s, _vmax[i], absf(_acc[i]) * dt)
		_vel[i] = v
		var p1 := p0 + v * dt
		_pos[i] = p1
		if _split[i] > 0.0:
			_split[i] -= dt
			if _split[i] <= 0.0:
				_burst(p1, _split_n[i], _col[i], _dmg[i])
				Vfx.glint(p1, Color.WHITE.lerp(_col[i], 0.5), 2.2)
				_remove(i)
				continue
		if p1.y < -0.5:
			_remove(i)
			continue
		if vulnerable and _harm[i] == 1 and _age[i] > 0.08:
			var reach := _r[i] * HIT_K + PLAYER_R
			var cp := Geometry3D.get_closest_point_to_segment(pc, p0, p1)
			if cp.distance_squared_to(pc) < reach * reach:
				var dir := v.normalized() if v.length_squared() > 1e-4 else Vector3.FORWARD
				var dmg := _dmg[i]
				_remove(i)
				if on_hit.is_valid():
					on_hit.call(cp, dir, dmg)
				vulnerable = can_hit.is_valid() and can_hit.call()
				continue
		i += 1
	for e: Array in _pending:
		spawn(e[0], e[1], e[2], e[3], e[4], e[5])
	_pending.clear()
	_upload()


## 写回两张 MultiMesh：变换只放位置（朝向在着色器里按相机算），颜色转线性，alpha 管淡入淡出，
## 自定义数据 = (飞行方向, 半径)；悬停待射的弹一明一暗地闪，清屏消散的弹胀大淡出
func _upload() -> void:
	var n := _pos.size()
	# 一整块：前 CAP 个槽放圆弹，后 CAP 个放针弹，写完再切成两段（Packed 数组是值类型，不拆成两个变量来回传）
	var b := PackedFloat32Array()
	b.resize(CAP * STRIDE * 2)
	var cnt := [0, 0]
	var t := Time.get_ticks_msec() * 0.001
	for i in n:
		var k := int(_kind[i])
		var o: int = (k * CAP + int(cnt[k])) * STRIDE
		cnt[k] = int(cnt[k]) + 1
		var p := _pos[i]
		var age := _age[i]
		var a := minf(age / FADE_IN, 1.0) * clampf((_life[i] - age) / FADE_OUT, 0.0, 1.0)
		var r := _r[i] * (0.55 + 0.45 * minf(age / FADE_IN, 1.0))
		var col := _col[i]
		if _harm[i] == 0:
			r *= 1.0 + (1.0 - a) * 0.9
		elif _hold[i] > 0.0:
			col = col.lerp(Color.WHITE, 0.25 + 0.25 * sin(t * 28.0 + float(i)))
		var lc := col.srgb_to_linear()
		var v := _vel[i]
		var d := v / v.length() if v.length_squared() > 1e-8 else Vector3.UP  # 悬停弹的速度只有 0.01，照样朝向目标
		b[o] = 1.0
		b[o + 1] = 0.0
		b[o + 2] = 0.0
		b[o + 3] = p.x
		b[o + 4] = 0.0
		b[o + 5] = 1.0
		b[o + 6] = 0.0
		b[o + 7] = p.y
		b[o + 8] = 0.0
		b[o + 9] = 0.0
		b[o + 10] = 1.0
		b[o + 11] = p.z
		b[o + 12] = lc.r
		b[o + 13] = lc.g
		b[o + 14] = lc.b
		b[o + 15] = a
		b[o + 16] = d.x
		b[o + 17] = d.y
		b[o + 18] = d.z
		b[o + 19] = r
	for k in 2:
		_mm[k].buffer = b.slice(k * CAP * STRIDE, (k + 1) * CAP * STRIDE)
		_mm[k].visible_instance_count = int(cnt[k])
