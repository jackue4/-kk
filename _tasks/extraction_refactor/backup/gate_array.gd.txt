extends Node
## 大乘专属技能「大罡剑阵」（R）。参考吉尔伽美什剑门齐射段（_ref/gil_frames/dense，原视频约 8~20s）：
## 身后与两侧疏疏落落地张开十几扇 tornado_portal 旋涡门（space_gate.gd，原版 portal_preview 整套）→ 剑尖从门心探出
## → 一排排射成金色剑束砸向前方。不做视频里的 saber 斩击。旋涡门只有这个技能用。
## 时间轴（游戏时间，共约 5.7s；主角原地定身、双臂向两侧张开，镜头由演出接管，见 CameraRig.cine_*）：
##   0.00  镜头硬切到主角正前方低机位仰拍，先推近；0.10「大罡剑阵」3D 毛笔字（放大一圈、盖印般压下）立在主角两侧，
##         每写成一字镜头一顿；0.95 最后一字落定（最重的一下）→ 1.12 起一路拉远抬高，字与身后门墙铺满画面。
##         推得再近也不会把字推出画：最近只到 CAM_NEAR，且每帧按题字取景框（_frame）再兜底退远（_fit_dist）
##   0.15~1.25  主角身后一面内凹的门墙（WALL_SLOTS，错开的几排、门与门相隔 4~6 米）+ 身前两侧（FLANK_SLOTS）
##         由中心向外依次张开（每扇按原版动画 0.5s 张开、0.2s 回弹），张开后飞剑从门心的黑洞里慢慢伸出来（缓入缓出，
##         用掉悬停时间的 EMERGE_K），伸到头停一拍
##   2.05  开火：一排排剑束自下而上依次全速射出，共 ROUNDS 轮（每扇门每轮 PER 柄；后几轮提前 NOCK_LEAD 秒开始慢慢伸出）；
##         一半追目标区域里的敌人，一半铺满目标区域插地
##   2.55  镜头硬切到目标区域侧面贴地仰拍，看剑束成片砸下；题字开始消散
##   3.50  目标上空张开一扇巨门、巨剑慢慢探出；3.70 起镜头拉远抬高；4.30 巨剑贯下
##   5.05  解除定身，镜头 BLEND_OUT 秒混回跟随机位；门各自在最后一柄剑射出后收拢消失（space_gate.gd 自己计时）
## 灵力：起手扣 COST × 灵力上限（大乘 300 → 150），不够则灰光一闪 + 闷响、不放。非大乘按 R 没有反应。
## 地面 / 空战都能放；遁光飞行、起飞、闪现、近战出招中不行（Player.can_ult）。
## 故意不写 class_name：用 preload 引用。

const Proj := preload("res://scripts/spell_projectile.gd")
const Gate := preload("res://scripts/space_gate.gd")
const Calligraphy := preload("res://scripts/skill_calligraphy.gd")
const Sfx := preload("res://scripts/sfx.gd")

const NAME := "大罡剑阵"
const COST := 0.5            # 起手消耗（灵力上限的比例）
const GOLD := Color(1.0, 0.78, 0.3)
const GOLDS: Array[Color] = [Color(1.0, 0.8, 0.34), Color(1.0, 0.9, 0.56), Color(1.0, 0.66, 0.2)]
## 身后门墙：(左右 x, 高 y)，米，相对主角脚下。几排错开、中间下方留给主角身体；每扇再随机抖 ±0.5 米
const WALL_SLOTS: Array[Vector2] = [
	Vector2(-6.0, 1.7), Vector2(6.0, 1.7), Vector2(-11.0, 2.2), Vector2(11.0, 2.2),
	Vector2(-3.0, 4.6), Vector2(3.0, 4.6), Vector2(-8.6, 5.2), Vector2(8.6, 5.2),
	Vector2(0.0, 7.6), Vector2(-5.8, 8.0), Vector2(5.8, 8.0),
	Vector2(-2.9, 10.6), Vector2(2.9, 10.6),
]
## 身前两侧：(离中线 x, 高 y, 往前 z)，左右各一份
const FLANK_SLOTS: Array[Vector3] = [Vector3(7.4, 2.6, 2.8), Vector3(9.4, 6.4, 1.2)]
const ROUNDS := 4            # 每扇门吐几轮
const PER := 2               # 每轮每扇门几柄（在门面上左右错开）
const ROW_H := 2.8           # 按高度分排，每排这么高
const T_TEXT := 0.1
const TEXT_SIZE := 1.35      # 题字放大倍数（比 Q 剑阵的题字大一圈）
const TEXT_STAMP := 0.35     # 题字"盖印"压下的幅度
const TEXT_LIFT := 0.7       # 题字锚点比身体中心再高这么多（放大后下排的字不埋进地里）
## 镜头 A：先推近（四字逐个写成，每落一字镜头一顿）→ 最近处停一拍 → 一路拉远抬高，字和身后门墙一起铺满画面
const T_PUSH := 0.95         # 推到最近（≈ 最后一字写成：T_TEXT + 0.12 + 0.16×3 + 0.24）
const T_PULL := 1.12         # 开始拉远
const CAM_START := 10.5      # 起手机位离身体中心的水平距离（米）
const CAM_NEAR := 7.2        # 推到最近：16:9 下四个字连盖印胀大都还在画内；画幅更窄时 _fit_dist 自动再退
const CAM_FAR := 13.0
const FRAME_MARGIN := 0.92   # 题字取景留边：取景点要落在视野的这个比例以内
const T_OPEN0 := 0.15
const T_OPEN_SPREAD := 1.1   # 门由中心向外依次张开用时
const T_NOCK := 0.45         # 门开始张开后多久剑尖开始探出（原版 0.5s 张开到最大）
const NOCK_LEAD := 0.45      # 第二轮起：射出前这么久开始从门里伸出来
const EMERGE_K := 0.88       # 伸出用掉悬停时间的比例，剩下的是伸到头后停的一拍
const T_FIRE := 2.05
const ROUND_GAP := 0.5
const ROW_GAP := 0.1
const T_SHOT_B := 2.55
const T_GIANT_OPEN := 3.5
const T_SHOT_C := 3.7
const T_GIANT_FIRE := 4.3
const T_END := 5.05
const BLEND_OUT := 0.6
const HOME_R := 9.0          # 目标点周围这么远内的敌人会被追

var player: Player
var active := false
var face_yaw := 0.0

var _t := 0.0
var _out := -1.0             # 演出结束后镜头混回的计时，-1 = 不在混回
var _pose := 0.0
var _pc := Vector3.ZERO      # 起手时主角身体中心
var _pt := Vector3.ZERO      # 目标点
var _g := Vector3.ZERO       # 目标点脚下地面
var _tgt: Node3D = null
var _fwd := Vector3.FORWARD  # 主角 → 目标（水平）
var _side := Vector3.RIGHT
var _gates: Array = []       # 规划好的门：{pos, rad, open, life, node, opened}
var _events: Array = []      # 按时间排好的出剑：[出剑时刻, 门下标, 射出时刻]
var _cues: Array = []        # 每排齐射的声响 / 镜头震动：[时刻, 排号]
var _ev := 0
var _cue := 0
var _pool: Array[Node3D] = []
var _text = null
var _text_on := false
var _text_out := false
var _beat := 0               # 题字已落下几个字（每字给一下镜头顿挫）
var _giant := false
var _frame := PackedVector3Array()  # 镜头 A 必须完整入画的点：题字四角（SkillCalligraphy.frame_points）+ 主角头脚


## R：大乘才有反应；灵力不够不放
func try_cast() -> void:
	if active or Realm.art(player.realm) != 6:
		return
	if not player.can_ult():
		return
	var cost := player.mp_max() * COST
	if player.mp < cost:
		Vfx.cast_flash(player.center(), Color(0.55, 0.6, 0.7), 0.6)
		Sfx.play("block", -10.0, 0.7)
		return
	player.mp -= cost
	_begin()


## 中途打断（回出生点等）：已张开的门立刻收拢，镜头混回
func abort() -> void:
	if not active:
		return
	for gd in _gates:
		var g = gd["node"]
		if is_instance_valid(g):
			g.close_in(0.0)
	_events.clear()
	_cues.clear()
	_giant = true
	_finish()


func _begin() -> void:
	active = true
	_t = 0.0
	_out = -1.0
	_ev = 0
	_cue = 0
	_giant = false
	_text = null
	_text_on = false
	_text_out = false
	_beat = 0
	player.caster.cancel()
	player.velocity = Vector3.ZERO
	_pc = player.center()
	_pick_target()
	var d := _pt - _pc
	d.y = 0.0
	_fwd = d.normalized() if d.length_squared() > 0.25 else player.cam.flat_forward()
	_side = _fwd.cross(Vector3.UP).normalized()
	face_yaw = atan2(-_fwd.x, -_fwd.z)
	player.face_now(face_yaw)
	_plan()
	# 题字在 T_TEXT 按当时的镜头位置摆好朝向：先按同一条镜头曲线预估那一刻的机位，算出取景框
	var a := _shot_a(T_TEXT)
	_frame = Calligraphy.frame_points(NAME, _pc + Vector3.UP * TEXT_LIFT,
			_cam_pos(_cam_dir(T_TEXT), a.x, a.y), TEXT_SIZE, TEXT_STAMP)
	_frame.append(player.global_position)
	_frame.append(_pc + Vector3.UP * 1.05)
	_cam_tick()
	Sfx.play("swing_heavy", -4.0, 0.55)
	Vfx.flash_light(_pc, GOLD, 1.6, 10.0, 0.5)


func _finish() -> void:
	active = false
	_out = 0.0


## 目标：准星锁定的敌人 → 镜头前方 40m 内最近的敌人 → 前方 18m 处的地面
func _pick_target() -> void:
	_tgt = player.caster.aim_target()
	var fwd := player.cam.flat_forward()
	if _tgt == null:
		var best := INF
		for e in Proj.targets(player.get_tree()):
			var to := Proj.aim_of(e) - _pc
			var flat := Vector3(to.x, 0.0, to.z)
			if to.length() > 40.0 or flat.length_squared() < 0.25:
				continue
			var dot := flat.normalized().dot(fwd)
			if dot < 0.5:
				continue
			var s := to.length() * (2.0 - dot)
			if s < best:
				best = s
				_tgt = e
	if _tgt != null:
		_pt = Proj.aim_of(_tgt)
	else:
		_pt = _ground_below(player.global_position + fwd * 18.0 + Vector3.UP * 4.0)
	_g = _ground_below(_pt + Vector3.UP * 0.5)


## 规划所有门的位置、张开时刻和每柄剑的出剑 / 射出时刻
func _plan() -> void:
	_gates.clear()
	_events.clear()
	_cues.clear()
	var base := player.global_position
	var back := -_fwd
	# 门墙：身后一面内凹的稀疏门墙，越往外越向前包住主角；由中心向外依次张开
	for s in WALL_SLOTS:
		var x := s.x + randf_range(-0.5, 0.5)
		var y := s.y + randf_range(-0.4, 0.4)
		var r := Vector2(x, (y - 4.6) * 1.4).length()
		_add_gate(base + _side * x + Vector3.UP * y + back * (3.2 - 0.024 * x * x),
				randf_range(0.95, 1.35), clampf(r / 12.0, 0.0, 1.0))
	# 身前两侧：左右各一列，从两边包到前方，最后张开
	for f in FLANK_SLOTS:
		for sgn: float in [-1.0, 1.0]:
			var p := base + _side * sgn * (f.x + randf_range(-0.5, 0.5)) + Vector3.UP * (f.y + randf_range(-0.4, 0.4)) \
					+ _fwd * (f.z + randf_range(-0.4, 0.4))
			_add_gate(p, randf_range(0.9, 1.2), 0.8 + 0.2 * randf())
	# 出剑：第一轮在门张开后开始慢慢伸出、一直搭在门里等到开火；之后几轮开火前 NOCK_LEAD 秒才开始伸出
	var rows := {}
	for gi in _gates.size():
		var gd: Dictionary = _gates[gi]
		var row := clampi(int(((gd["pos"] as Vector3).y - base.y) / ROW_H), 0, 9)
		var last := 0.0
		for rd in ROUNDS:
			for k in PER:
				var fire := T_FIRE + ROUND_GAP * rd + ROW_GAP * row + 0.08 * k + randf_range(0.0, 0.04)
				var nock: float = float(gd["open"]) + T_NOCK if rd == 0 else fire - NOCK_LEAD
				_events.append([nock, gi, fire, k])
				last = maxf(last, fire)
			var key := rd * 16 + row
			if not rows.has(key):
				rows[key] = true
				_cues.append([T_FIRE + ROUND_GAP * rd + ROW_GAP * row, row])
		gd["life"] = last - float(gd["open"]) + 0.14
	_events.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	_cues.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))


func _add_gate(pos: Vector3, rad: float, order: float) -> void:
	_gates.append({"pos": pos, "rad": rad, "open": T_OPEN0 + order * T_OPEN_SPREAD + randf_range(0.0, 0.06),
			"life": 1.0, "node": null, "opened": false})


func tick(dt: float) -> void:
	if _out >= 0.0:
		_out += dt
		player.cam.cine_k = 1.0 - clampf(_out / BLEND_OUT, 0.0, 1.0)
		if _out >= BLEND_OUT:
			_out = -1.0
			player.cam.cine_k = 0.0
	if not active:
		_pose = move_toward(_pose, 0.0, dt * 3.0)
		return
	_t += dt
	_pose = move_toward(_pose, 1.0, dt * 4.0)
	player.velocity = Vector3.ZERO
	if not _text_on and _t >= T_TEXT:
		_text_on = true
		_text = Calligraphy.show_text(NAME, _pc + Vector3.UP * TEXT_LIFT, GOLD, TEXT_SIZE, TEXT_STAMP)
	# 每个字写成的那一刻镜头一顿（时刻同 SkillCalligraphy 的 T_CHAR0 + T_GAP×i + T_WRITE），最后一字最重
	while _text_on and _beat < NAME.length() \
			and _t >= T_TEXT + Calligraphy.T_CHAR0 + Calligraphy.T_GAP * _beat + Calligraphy.T_WRITE:
		var last := _beat == NAME.length() - 1
		player.cam.add_trauma(0.22 if last else 0.1)
		player.cam.fov_punch(-2.5 if last else -1.0)  # 收窄幅度在 FRAME_MARGIN 的留边以内，顿挫时字不出画
		if last:
			Sfx.play("slam", -8.0, 0.7)
		_beat += 1
	if not _text_out and _t >= T_SHOT_B:
		_text_out = true
		if is_instance_valid(_text):
			_text.hurry()
	for gd in _gates:
		if not gd["opened"] and _t >= float(gd["open"]):
			gd["opened"] = true
			var p: Vector3 = gd["pos"]
			gd["node"] = Gate.open(p, _pt - p, float(gd["rad"]), float(gd["life"]) - (_t - float(gd["open"])))
			if randf() < 0.5:
				Sfx.play("warp", -14.0, randf_range(1.0, 1.4))
	if _ev < _events.size():
		_refresh_pool()
	while _ev < _events.size() and _t >= float(_events[_ev][0]):
		_launch(_events[_ev])
		_ev += 1
	while _cue < _cues.size() and _t >= float(_cues[_cue][0]):
		Sfx.play("swing_heavy", -9.0, 1.1 + 0.05 * float(_cues[_cue][1]))
		player.cam.add_trauma(0.05)
		_cue += 1
	if not _giant and _t >= T_GIANT_OPEN:
		_giant = true
		_open_giant()
	_cam_tick()
	if _t >= T_END:
		_finish()


func _refresh_pool() -> void:
	_pool.clear()
	for e in Proj.targets(player.get_tree()):
		if Proj.aim_of(e).distance_to(_pt) <= HOME_R:
			_pool.append(e)


## 一柄剑：从门心的黑洞里慢慢伸出来，伸到头停一拍，到点不带起步加速、直接全速射向目标区域（一半追敌人、一半铺开插地）
func _launch(ev: Array) -> void:
	var gd: Dictionary = _gates[int(ev[1])]
	var g = gd["node"]
	if not is_instance_valid(g):
		return
	var c: Vector3 = g.global_position
	var hold := maxf(float(ev[2]) - _t, 0.05)
	var tgt: Node3D = null
	var aim := _g + _disk(6.0) - Vector3.UP * randf_range(0.3, 1.0)
	if not _pool.is_empty() and randf() < 0.5:
		tgt = _pool[randi() % _pool.size()]
		aim = Proj.aim_of(tgt)
	# 同一轮的 PER 柄在门面上左右分开，几轮之间再略微错开
	var f := (aim - c).normalized()
	var r := f.cross(Vector3.UP)
	r = r.normalized() if r.length_squared() > 1e-4 else Vector3.RIGHT
	var lane := (float(ev[3]) - 0.5 * float(PER - 1)) * 0.55
	var from: Vector3 = c + (r * (lane + randf_range(-0.12, 0.12)) + r.cross(f) * randf_range(-0.25, 0.25)) * float(gd["rad"])
	var heavy := _ev % 7 == 0
	Proj.launch(player, Proj.K.SWORD, from, tgt, aim,
			{"dmg": float(player.realm["dmg"]) * 0.32, "color": GOLDS[_ev % GOLDS.size()], "speed": 120.0,
			 "hold": hold, "turn": 9.0, "straight": tgt == null, "art": 6, "lite": not heavy, "light": true,
			 "style": 4, "tw": 0.2, "tl": 0.32, "scale": 1.8, "emerge": true, "emerge_t": hold * EMERGE_K,
			 "life": hold + 1.4, "sfx": _ev % 5 == 0, "trauma": 0.02})
	g.flare_in(hold, 0.8)


## 收尾：目标上空一扇巨门，巨剑从门里慢慢探出、悬停一拍，再贯下
func _open_giant() -> void:
	var sky := _g + Vector3.UP * 13.0 - _fwd * 3.0
	var hold := T_GIANT_FIRE - _t
	var g = Gate.open(sky, _pt - sky, 3.4, hold + 0.6)
	var tgt: Node3D = _tgt if Proj.alive(_tgt) else null
	Proj.launch(player, Proj.K.SWORD, sky, tgt, _pt if tgt == null else Proj.aim_of(tgt),
			{"dmg": float(player.realm["dmg"]) * 3.0, "color": GOLDS[0], "speed": 70.0, "hold": hold, "turn": 20.0,
			 "scale": 6.0, "radius": 6.5, "light": true, "style": 4, "tw": 0.6, "tl": 0.4, "art": 6,
			 "trauma": 0.35, "emerge": true, "emerge_t": hold * EMERGE_K, "life": hold + 2.0})
	if is_instance_valid(g):
		g.flare_in(hold, 1.6)
	Sfx.play("swing_heavy", -5.0, 0.45)
	Vfx.flash_light(sky, GOLD, 2.0, 14.0, 0.5)


## 演出镜头：A 主角正前方低机位仰拍，先推近看题字一个个砸下、再拉远抬高让字与身后门墙铺满画面
## → B 目标区域侧面贴地仰拍 → C 拉远抬高看巨门巨剑
func _cam_tick() -> void:
	var xf: Transform3D
	var fov: float
	if _t < T_SHOT_B:
		var a := _shot_a(_t)
		var dir := _cam_dir(_t)
		var at := _pc + Vector3.UP * a.z
		fov = a.w
		xf = _look(_cam_pos(dir, _fit_dist(a.x, dir, a.y, at, fov), a.y), at)
	else:
		var me := -_fwd
		var u := clampf((_t - T_SHOT_B) / (T_SHOT_C - T_SHOT_B), 0.0, 1.0)
		var pos := _g + me * lerpf(5.0, 6.2, u) + _side * lerpf(6.2, 5.0, u) + Vector3.UP * 0.9
		pos.y = maxf(pos.y, _g.y + 0.5)
		xf = _look(pos, _g.lerp(_pc + Vector3.UP * 3.0, 0.4))
		fov = 74.0
		if _t > T_SHOT_C:
			var v := clampf((_t - T_SHOT_C) / 0.55, 0.0, 1.0)
			v = v * v * (3.0 - 2.0 * v)
			var wide := _look(_g + me * 15.0 + _side * 10.0 + Vector3.UP * 5.5, _g + Vector3.UP * 5.0)
			xf = xf.interpolate_with(wide, v)
			fov = lerpf(74.0, 68.0, v)
	player.cam.cine_xf = xf
	player.cam.cine_fov = fov
	player.cam.cine_k = 1.0


## 镜头 A 在 t 时刻的 (距离, 机位高, 注视高, 视野)，高度都相对起手时的身体中心
func _shot_a(t: float) -> Vector4:
	if t < T_PULL:
		# 推近：先快后慢，压低机位、收窄视野，越来越仰视；最近只到 CAM_NEAR，四个字都还在画里
		var u := clampf(t / T_PUSH, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		return Vector4(lerpf(CAM_START, CAM_NEAR, e), lerpf(-0.2, -0.45, e), lerpf(1.9, 2.2, e), lerpf(62.0, 56.0, e))
	# 拉远：起步猛、收尾缓，抬高并放宽视野，字组和整面门墙一起入画
	var u := clampf((t - T_PULL) / (T_SHOT_B - T_PULL), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 2.4)
	return Vector4(lerpf(CAM_NEAR, CAM_FAR, e), lerpf(-0.45, 0.6, e), lerpf(2.2, 3.6, e), lerpf(56.0, 68.0, e))


## 镜头 A 的机位方向：从主角正前方略偏一侧，演出中缓缓绕到另一侧
func _cam_dir(t: float) -> Vector3:
	return Basis(Vector3.UP, lerpf(-0.12, 0.12, clampf(t / T_SHOT_B, 0.0, 1.0))) * _fwd


func _cam_pos(dir: Vector3, dist: float, h: float) -> Vector3:
	var pos := _pc + dir * dist + Vector3.UP * h
	pos.y = maxf(pos.y, player.global_position.y + 0.2)
	return pos


## 兜底：取景点（题字四角 + 主角头脚）放不进画面（留 FRAME_MARGIN 的边）时，把机位沿 dir 往后退到刚好放得下。
## 先每次退 0.5 米找到放得下的距离，再二分到厘米级，退的距离随镜头参数连续变化、不跳；16:9 下 CAM_NEAR 本身就够，一般不会触发
func _fit_dist(dist: float, dir: Vector3, h: float, at: Vector3, fov: float) -> float:
	if _frame.is_empty():
		return dist
	var vs := player.get_viewport().get_visible_rect().size
	var tv := tan(deg_to_rad(fov) * 0.5) * FRAME_MARGIN  # Camera3D 默认 KEEP_HEIGHT：fov 是竖直视野
	var th := tv * vs.x / maxf(vs.y, 1.0)
	if _fits(dist, dir, h, at, th, tv):
		return dist
	var lo := dist
	var hi := dist + 0.5
	while not _fits(hi, dir, h, at, th, tv) and hi < dist + 30.0:
		lo = hi
		hi += 0.5
	for i in 6:
		var mid := (lo + hi) * 0.5
		if _fits(mid, dir, h, at, th, tv):
			hi = mid
		else:
			lo = mid
	return hi


func _fits(dist: float, dir: Vector3, h: float, at: Vector3, th: float, tv: float) -> bool:
	var inv := _look(_cam_pos(dir, dist, h), at).affine_inverse()
	for p in _frame:
		var l := inv * p
		var depth := -l.z
		if depth < 0.5 or absf(l.x) > depth * th or absf(l.y) > depth * tv:
			return false
	return true


static func _look(pos: Vector3, at: Vector3) -> Transform3D:
	var d := at - pos
	if d.length_squared() < 1e-4:
		d = Vector3.FORWARD
	return Transform3D(Basis.looking_at(d, Vector3.UP), pos)


## 在 hero.animate 之后叠上去：双臂向两侧斜下张开（参考帧里的起手姿势），上身微挺
func apply_pose(hero: Node3D) -> void:
	var k := _pose * _pose * (3.0 - 2.0 * _pose)
	if k <= 0.001:
		return
	var ar: Node3D = hero.arm_r
	var al: Node3D = hero.arm_l
	var up: Node3D = hero.upper
	ar.rotation.z = lerpf(ar.rotation.z, 0.95, k)
	al.rotation.z = lerpf(al.rotation.z, -0.95, k)
	ar.rotation.x = lerpf(ar.rotation.x, 0.25, k)
	al.rotation.x = lerpf(al.rotation.x, 0.25, k)
	up.rotation.x = lerpf(up.rotation.x, -0.08, k)


static func _disk(rad: float) -> Vector3:
	var a := randf() * TAU
	var r := rad * sqrt(randf())
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func _ground_below(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 40.0, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3) + Vector3.UP * 0.08 if not hit.is_empty() else Vector3(p.x, 0.0, p.z)
