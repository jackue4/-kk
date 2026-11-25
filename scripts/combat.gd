extends RefCounted
## 战斗公共：顿帧（hit-stop）、慢动作与战斗时钟。
## 顿帧只作用于"战斗相关对象"——主角近战、刀客、手中剑的剑光，它们都用 cdt() 推进；
## 世界其它部分（相机、飞剑环绕、遁光丝线、木人桩）照常走，所以不会像整机掉帧。
## 慢动作（完美闪避）则是整个画面一起变慢：直接改 Engine.time_scale，先骤降、停一拍、再加速回到 1。
## 顿帧与慢动作的计时都按真实时间走，慢动作里顿帧不会被拉长。
## 故意不写 class_name：用 preload 引用（同 voxel_model.gd），命令行运行不依赖全局类缓存。

const MAX_DT := 1.0 / 30.0  # 单帧战斗推进上限：截图存盘等长帧不会让招式时间轴跳帧

static var _stop := 0.0
## 2026-11-25 联机：正在结算的这一下命中附带的东西（破防 brk / 真人硬直 pstun / 冻结 freeze），net.gd 的 _hit 在转给关卡之前写、转完清掉，
## air_melee.receive_attack 读。走这里是因为三个关卡管理器的 net_take_hit 签名不想为它各改一遍
static var net_ext: Dictionary = {}
static var _stop_scale := 0.0
## 演示截图存盘期间冻结战斗时间（只给 --combat-shot 用）
static var hold := false

## 逐帧录像（--trailer，配合 --fixed-fps）时设为每帧时长：顿帧 / 慢动作 / 输入缓冲改按这个固定步长走，
## 不看墙钟（录像每帧存盘很慢，墙钟会比画面时间快得多）
static var fixed_dt := 0.0
static var _clock := 0.0

static var _last_us := 0
static var _slow_t := -1.0   # 慢动作已过的真实时间，-1 = 不在慢动作
static var _slow_low := 0.15
static var _slow_hold := 0.4
static var _slow_ramp := 0.45


## sec: 真实时间秒；scale: 顿帧期间的时间流速（0.0 完全冻结）
static func hitstop(sec: float, scale := 0.03) -> void:
	if sec >= _stop:
		_stop = sec
		_stop_scale = scale


## 立刻结束顿帧（闪现打断出招时用：闪出去的那一下不被顿帧拖住）
static func clear_hitstop() -> void:
	_stop = 0.0


## 慢动作：time_scale 当帧降到 low，保持 hold 秒，再在 ramp 秒内加速（先慢后快）回到 1。都是真实时间
static func slowmo(low := 0.15, hold_sec := 0.4, ramp := 0.45) -> void:
	_slow_low = low
	_slow_hold = hold_sec
	_slow_ramp = ramp
	_slow_t = 0.0
	Engine.time_scale = low


## 提前结束慢动作的"停"：直接进入加速段，并在 ramp 秒内回到 1（闪避反击出手时用）
static func slowmo_release(ramp := 0.14) -> void:
	if _slow_t < 0.0:
		return
	var cur := Engine.time_scale
	_slow_low = cur
	_slow_hold = 0.0
	_slow_ramp = ramp
	_slow_t = 0.0


## 慢动作强度 0~1（后处理调色用）
static func slowmo_k() -> float:
	if _slow_t < 0.0:
		return 0.0
	return clampf((1.0 - Engine.time_scale) / maxf(1.0 - minf(_slow_low, 0.95), 0.05), 0.0, 1.0)


## 每帧调一次（main._process）；dt 参数仅作兜底，实际用真实时间
static func tick(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := 0.0 if _last_us == 0 else float(now - _last_us) * 1e-6
	_last_us = now
	if fixed_dt > 0.0:
		real_dt = fixed_dt
		_clock += fixed_dt
	if _slow_t >= 0.0:
		_slow_t += minf(real_dt, MAX_DT)
		var u := clampf((_slow_t - _slow_hold) / maxf(_slow_ramp, 1e-3), 0.0, 1.0)
		Engine.time_scale = lerpf(_slow_low, 1.0, u * u)
		if u >= 1.0:
			_slow_t = -1.0
			Engine.time_scale = 1.0
	if hold:
		return
	_stop = maxf(_stop - minf(real_dt, MAX_DT), 0.0)


## 真实时间（秒），输入缓冲 / 连段宽限用；录像时为按固定步长累计的时钟
static func now() -> float:
	return _clock if fixed_dt > 0.0 else Time.get_ticks_msec() * 0.001


static func time_scale() -> float:
	if hold:
		return 0.0
	return _stop_scale if _stop > 0.0 else 1.0


static func frozen() -> bool:
	return hold or _stop > 0.0


## 战斗对象本帧应推进的时间
static func cdt(dt: float) -> float:
	return minf(dt, MAX_DT) * time_scale()
