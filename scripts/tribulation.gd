extends CanvasLayer
## 雷劫：大境界突破前要渡的一关（raid_manager.gd 在经验攒满、要跨大境界时调起）。
## 流程：
##   1. 开场运镜（约 2.4 秒）：主角被托到半空，天色压暗、劫云在头顶盘成一个旋涡，镜头从脚下低机位绕着升上去
##   2. 渡劫：一道道天雷劈下来。每道雷来之前屏幕上亮出一个「挡」字圆钮，外圈一道红环往里收，
##      收到底之前点它（触屏点圆钮 / 鼠标点 / 键盘按攻击键）就挡下这道雷；收到最后四成才点 = 完美。
##      连着挡算连击；没点到，雷就劈在身上（掉气血、断连击）。失误超过「劫数」就渡劫失败。
##   3. 收尾：成功 —— 劫云散开、镜头推近，交回去由调用方真正突破；失败 —— 被最后一道雷劈落。
## 段位越高越难、越花（realm_to = 要突破到的境界下标 1~7）：
##   · 雷的道数 = 2 + 段位（3~9 道），红环收得更快、间隔更短；化神起会两道一起来；炼虚起最后一道是要连点三下的巨雷
##   · 雷色：筑基 青白 / 结丹 金 / 元婴 紫 / 化神 赤 / 炼虚 五行轮换 / 合体 幽紫 / 大乘 紫金
##   · 元婴起（「元婴之后」）：身后升起一尊半透明的化身法相（越高越大）、头顶劫云更大并多出天环异象，
##     每道雷都带空间波动和空间破碎，破碎的范围随段位扩大（合体、大乘铺满全屏）
## 期间主角停止处理（不吃别的输入、不被打），镜头由这里接管；结束后还原。时间按真实时间走。
## 故意不写 class_name：用 preload 引用。

signal finished(success: bool, perfect: int, total: int)

const UiStyle := preload("res://scripts/ui_style.gd")
const Sfx := preload("res://scripts/sfx.gd")

const INTRO := 2.4
const OUTRO := 2.4
const BTN_R := 62.0
const NAMES := ["", "三九雷劫", "金丹雷劫", "紫霄雷劫", "焚天火劫", "五行雷劫", "裂空雷劫", "九天紫金雷劫"]
const COLS: Array[Color] = [Color.WHITE, Color(0.72, 0.9, 1.0), Color(1.0, 0.84, 0.4), Color(0.72, 0.45, 1.0),
		Color(1.0, 0.42, 0.2), Color(0.4, 1.0, 0.6), Color(0.55, 0.32, 0.98), Color(1.0, 0.86, 0.5)]
const FIVE: Array[Color] = [Color(1.0, 0.86, 0.4), Color(0.25, 1.0, 0.45), Color(0.25, 0.55, 1.0), Color(1.0, 0.28, 0.15), Color(0.85, 0.62, 0.3)]

## 有雷劫在进行（main.gd 据此让触屏层让出触摸）
static var running := false

var player: Player
var cam: CameraRig
var realm_to := 1
## 联机：net_cb = 把「开始 / 每道雷 / 结束」报出去的回调（渡劫的人填）；
## spectate = 旁观模式（别人在渡劫，这里只在他的木偶 subject 头上放表现：不接管镜头、不出界面、不吃输入，雷按网络事件落）
var net_cb := Callable()
var spectate := false
var subject: Node3D = null
var demo_auto := -1.0     # >= 0：自检用，自动点，每道雷有这么大的概率点中
var storm := 0.0          # 0~1：天色该压多暗（raid_manager.gd 读）

var _t := 0.0
var _phase := 0           # 0 开场 1 渡劫 2 收尾
var _t2 := 0.0
var _sched: Array = []    # {at, win, taps, pos}
var _next := 0
var _live: Array = []     # {pos, t, win, left, taps, idx}
var _total := 0
var _done := 0
var _combo := 0
var _best := 0
var _perfect := 0
var _missed := 0
var _allow := 1
var _success := false
var _emitted := false
var _root: Control
var _base := Vector3.ZERO
var _yaw0 := 0.0
var _cloud: MeshInstance3D
var _ring: MeshInstance3D
var _avatar: Node3D
var _msg := ""
var _msg_t := 0.0
var _msg_col := Color.WHITE
var _amb := 0.0
var _old_mouse := Input.MOUSE_MODE_VISIBLE
var _old_r := 0.95
var _last_tap := 0


func _ready() -> void:
	layer = 30
	if subject == null:
		subject = player
	if spectate:
		_ready_spectate()
		return
	running = true
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw)
	add_child(_root)
	_base = player.global_position
	_yaw0 = cam.yaw
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_old_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_old_r = cam.impact_r
	# 空间破碎的范围：元婴起逐级扩大
	cam.impact_r = 0.95 if realm_to < 3 else 1.1 + 0.35 * float(realm_to - 3)
	_build_schedule()
	var col := _col(0)
	# 头顶的劫云旋涡（元婴起更大，外面再套一圈天环）
	var big := realm_to >= 3
	_cloud = Vfx.halo_disc(col, 1.0, 1.0 if realm_to == 5 else 0.0)
	if big:
		_ring = Vfx.halo_disc(Color.WHITE.lerp(col, 0.5), 1.0, 1.0 if realm_to >= 5 else 0.0)
	Vfx.takeoff_burst(_base, col, 0.8 + 0.2 * float(realm_to))
	Sfx.play("ascend", -3.0, 0.5)
	Sfx.play("slam", -6.0, 0.6)
	player.hero.set_glow(0.2, col)
	if net_cb.is_valid():
		net_cb.call(0, realm_to, 0)


## 旁观：只建劫云（和天环），其余靠网络事件
func _ready_spectate() -> void:
	_base = subject.global_position
	_total = 99
	var col := _col(0)
	_cloud = Vfx.halo_disc(col, 1.0, 1.0 if realm_to == 5 else 0.0)
	if realm_to >= 3:
		_ring = Vfx.halo_disc(Color.WHITE.lerp(col, 0.5), 1.0, 1.0 if realm_to >= 5 else 0.0)
	Vfx.takeoff_burst(_base, col, 0.8 + 0.2 * float(realm_to))
	subject.get("hero").set_glow(0.2, col)


## 旁观：渡劫的人那边落了一道雷（bits：位 0 挡下 · 位 1 完美 · 位 2 巨雷）
func remote_bolt(idx: int, bits: int) -> void:
	if is_instance_valid(subject):
		_bolt_fx(idx, (bits & 1) != 0, (bits & 2) != 0, (bits & 4) != 0)
		_done += 1


## 旁观：渡劫的人那边结束了
func remote_finish(ok: bool) -> void:
	if _phase < 2 and is_instance_valid(subject):
		_finish(ok)


func _exit_tree() -> void:
	if not spectate:
		running = false
	for n: Variant in [_cloud, _ring, _avatar]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()


func _col(i: int) -> Color:
	return FIVE[i % 5] if realm_to == 5 else COLS[realm_to]


func _sky() -> Vector3:
	return _base + Vector3(0.0, 34.0 + 3.0 * float(realm_to), 0.0)


func _pc() -> Vector3:
	return subject.global_position + Vector3(0.0, 0.95, 0.0)


func _build_schedule() -> void:
	var r := realm_to
	var n := 2 + r
	var k := float(r - 1) / 6.0
	var win := lerpf(1.3, 0.66, k)
	var gap := lerpf(1.2, 0.6, k)
	var t := INTRO + 0.3
	var last_pos := Vector2(0.5, 0.45)
	for i in n:
		var last := i == n - 1
		var taps := 3 if last and r >= 5 else 1
		last_pos = _rand_pos(last_pos)
		_sched.append({"at": t, "win": win * (1.8 if taps > 1 else 1.0), "taps": taps, "pos": last_pos})
		if r >= 4 and i % 3 == 1 and not last:
			# 化神起：双雷，几乎同时落下
			last_pos = _rand_pos(last_pos)
			_sched.append({"at": t + 0.14, "win": win, "taps": 1, "pos": last_pos})
		t += gap
	_total = _sched.size()
	_allow = maxi(1, int(floorf(float(n) / 3.0)))


## 圆钮的位置（屏幕比例）：避开四周的界面，和上一个隔开一点
func _rand_pos(prev: Vector2) -> Vector2:
	var p := prev
	for _i in 12:
		p = Vector2(randf_range(0.24, 0.76), randf_range(0.26, 0.66))
		if p.distance_to(prev) > 0.2:
			break
	return p


# ---------- 输入 ----------

func _input(e: InputEvent) -> void:
	if spectate or _phase != 1:
		return
	var hit := -1
	if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
		hit = _target_at((e as InputEventScreenTouch).position)
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		hit = _target_at((e as InputEventMouseButton).position)
	elif (e.is_action_pressed("attack") or e.is_action_pressed("jump")) and not e.is_echo():
		hit = 0 if not _live.is_empty() else -1   # 键盘：挡最早落下的那一道
	else:
		return
	get_viewport().set_input_as_handled()
	var now := Time.get_ticks_msec()
	if hit >= 0 and now - _last_tap > 45:   # 鼠标模拟触摸时同一下会来两个事件
		_last_tap = now
		_tap(hit)


func _target_at(pos: Vector2) -> int:
	var vs := _root.size
	var best := -1
	var bd := BTN_R * 1.35
	for i in _live.size():
		var d := pos.distance_to((_live[i]["pos"] as Vector2) * vs)
		if d < bd:
			bd = d
			best = i
	return best


func _tap(i: int) -> void:
	var b: Dictionary = _live[i]
	b["left"] = int(b["left"]) - 1
	var to := _pc() + Vector3.UP * 1.6
	if int(b["left"]) > 0:
		# 巨雷：还要再点
		Vfx.blade_clash(to, Vector3.UP, 0.7)
		Sfx.play("block", -4.0, 1.2)
		cam.add_trauma(0.15)
		return
	var perfect := float(b["t"]) >= float(b["win"]) * 0.6
	_live.remove_at(i)
	_resolve(int(b["idx"]), true, perfect, int(b["taps"]) > 1)


# ---------- 每道雷的结算 ----------

func _resolve(idx: int, blocked: bool, perfect: bool, giant: bool) -> void:
	_done += 1
	if net_cb.is_valid():
		net_cb.call(1, idx, (1 if blocked else 0) | (2 if perfect else 0) | (4 if giant else 0))
	_bolt_fx(idx, blocked, perfect, giant)
	if blocked:
		_combo += 1
		_best = maxi(_best, _combo)
		if perfect:
			_perfect += 1
		_say("完美" if perfect else "抵挡", Color(1.0, 0.86, 0.45) if perfect else UiStyle.TEXT)
	else:
		_combo = 0
		_missed += 1
		player.melee.hp = maxf(player.melee.hp - 14.0, 5.0)
		_say("失误", UiStyle.CINNABAR.lightened(0.25))
		if _missed > _allow:
			_finish(false)
			return
	if _done >= _total and _phase == 1:
		_finish(true)


## 一道雷的表现（渡劫的人和旁观的人都走这里；镜头的震动 / 破碎只给渡劫的人自己）
func _bolt_fx(idx: int, blocked: bool, perfect: bool, giant: bool) -> void:
	var r := realm_to
	var col := _col(idx)
	var edge := Color.WHITE.lerp(col, 0.4)
	var from := _sky() + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
	var pc := _pc()
	var w := (0.2 + 0.035 * float(r)) * (1.8 if giant else 1.0)
	if blocked:
		var to := pc + Vector3.UP * 1.6
		Vfx.lightning(from, to, col, w, 0.3, 10)
		Vfx.lightning(from + Vector3(2.0, 0.0, -1.5), to, edge, w * 0.4, 0.24, 8)
		Vfx.shockwave(to, Vector3.UP, edge, 1.4 + 0.3 * float(r))
		Vfx.blade_clash(to, Vector3.UP, 1.0)
		Vfx.line_sparks(to, Vector3.UP, edge, 10 + 2 * r, 16.0, 170.0, 0.4)
		Vfx.flash_light(to, col, 2.5, 12.0, 0.25)
		if perfect:
			Vfx.glint(to, edge, 2.4)
		if not spectate:
			Sfx.play("perfect" if perfect else "block", -2.0, 1.0 + 0.04 * float(_combo))
			Sfx.play("slam", -7.0, 1.3)
			cam.add_trauma(0.25 + 0.04 * float(r))
		subject.get("hero").set_flash(0.6)
		if r >= 3:
			# 元婴起：挡下来的一瞬间，空间跟着一荡、碎一下
			Vfx.warp_pos = to
			Vfx.warp_k = maxf(Vfx.warp_k, (0.014 + 0.005 * float(r)) * (1.6 if giant else 1.0))
			if not spectate:
				cam.impact((0.3 + 0.06 * float(r)) * (1.5 if giant else 1.0))
			if is_instance_valid(_avatar):
				_avatar_pulse()
	else:
		Vfx.lightning(from, pc, col, w * 1.2, 0.34, 10)
		Vfx.thunder(pc, col, 1.0 + 0.15 * float(r))
		Vfx.fire_explode(pc, Vector3.DOWN, true)
		if not spectate:
			Sfx.play("hit_heavy", 0.0, 0.8)
			cam.add_trauma(0.6)
			cam.impact(0.5 if r < 3 else 0.8)
		subject.get("hero").set_flash(1.0)


func _say(s: String, c: Color) -> void:
	_msg = s
	_msg_col = c
	_msg_t = 0.7


func _finish(ok: bool) -> void:
	_phase = 2
	_t2 = 0.0
	_success = ok
	_live.clear()
	if net_cb.is_valid():
		net_cb.call(2, 1 if ok else 0, 0)
	var pc := _pc()
	var col := _col(0)
	if ok:
		Vfx.sky_ring(_sky() - Vector3.UP * 4.0, col, 16.0 + 4.0 * float(realm_to), 1.2, 1.0 if realm_to >= 5 else 0.0)
		Vfx.breakthrough(subject.global_position, col, 1.0 + 0.2 * float(realm_to))
		if realm_to >= 3:
			Vfx.warp_pos = pc
			Vfx.warp_k = 0.03 + 0.008 * float(realm_to)
		if not spectate:
			Sfx.play("ascend", 0.0, 0.9)
			if realm_to >= 3:
				cam.impact(1.0)
	else:
		Vfx.thunder(pc, col, 2.0)
		if not spectate:
			Sfx.play("slam", 0.0, 0.6)
			cam.impact(0.9)


# ---------- 化身法相（元婴起） ----------

func _avatar_scale() -> float:
	return 2.6 + 0.9 * float(realm_to - 3)


func _spawn_avatar() -> void:
	var col := _col(0)
	_avatar = Vfx._ghost_node(subject.get("visual"), Color.WHITE.lerp(col, 0.65), 0.0, subject.global_position)
	_avatar.scale = Vector3.ONE * 0.6
	var s := _avatar_scale()
	var tw := _avatar.create_tween().set_parallel(true)
	tw.tween_property(_avatar, "scale", Vector3.ONE * s, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_avatar.get_meta("mat"), "albedo_color:a", 0.3, 0.6)
	Vfx.sky_ring(subject.global_position + Vector3.UP * 1.0, col, 3.0 * s, 0.8, 0.0)
	if not spectate:
		Sfx.play("ascend", -5.0, 0.7)


func _avatar_pulse() -> void:
	var m: StandardMaterial3D = _avatar.get_meta("mat")
	m.albedo_color.a = 0.6
	var tw := _avatar.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.3, 0.3)


# ---------- 每帧 ----------

func _process(delta: float) -> void:
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.05)
	_t += dt
	_msg_t -= dt
	var r := realm_to
	var col := _col(_done)
	if not is_instance_valid(subject):
		queue_free()      # 旁观的那个人掉线了
		return
	# 主角托到半空（元婴起托得更高）；旁观时对方的位置本来就是同步过来的，不用管
	var lift := (4.0 + 0.6 * float(r)) * smoothstep(0.0, 1.8, _t)
	if _phase == 2:
		_t2 += dt
		if not _success:
			lift *= 1.0 - smoothstep(0.0, 0.5, _t2)
		elif _t2 > OUTRO - 0.6:
			lift *= 1.0 - smoothstep(OUTRO - 0.6, OUTRO, _t2)
	if not spectate:
		player.global_position = _base + Vector3.UP * lift
		storm = smoothstep(0.0, 1.4, _t) if _phase < 2 else 1.0 - smoothstep(0.3, OUTRO, _t2)
	# 劫云：越转越大；收尾时散开
	var cr := (10.0 + 3.0 * float(r)) * smoothstep(0.0, 2.0, _t)
	var ca := 0.9
	if _phase == 2:
		cr *= 1.0 + _t2 * (0.9 if _success else 0.2)
		ca = 0.9 * (1.0 - smoothstep(0.2, 1.6, _t2))
	_place_disc(_cloud, _sky(), cr, ca, _t * (0.9 + 0.15 * float(r)))
	if _ring != null:
		_place_disc(_ring, _sky() - Vector3.UP * 5.0, cr * 1.7, ca * 0.6, -_t * 0.5)
	if r >= 3 and _avatar == null and _t >= 1.1:
		_spawn_avatar()
	if is_instance_valid(_avatar):
		_avatar.global_position = subject.global_position - Basis(Vector3.UP, _yaw0) * Vector3(0.0, 0.0, -0.4 * _avatar_scale())
		if _phase == 2 and _t2 > 0.3 and _success:
			# 成功：法相缩回本体
			_avatar.scale = _avatar.scale.lerp(Vector3.ONE, 1.0 - exp(-6.0 * dt))
			(_avatar.get_meta("mat") as StandardMaterial3D).albedo_color.a = 0.3 * (1.0 - smoothstep(0.3, 1.4, _t2))
	# 云里的闷雷
	_amb -= dt
	if _amb <= 0.0 and _phase < 2 and _t > 0.8:
		_amb = randf_range(0.12, 0.4) / (1.0 + 0.15 * float(r))
		var a := randf() * TAU
		var p0 := _sky() + Vector3(cos(a), 0.0, sin(a)) * cr * randf_range(0.2, 0.9)
		var p1 := p0 + Vector3(randf_range(-6.0, 6.0), randf_range(-5.0, -1.0), randf_range(-6.0, 6.0))
		Vfx.lightning(p0, p1, Color.WHITE.lerp(col, 0.6), 0.07, 0.14, 5)
		if r >= 3 and randf() < 0.25:
			Vfx.warp_pos = p1
			Vfx.warp_k = maxf(Vfx.warp_k, 0.006 + 0.002 * float(r))
	if spectate:
		# 旁观：没有镜头、界面和出雷的时间表；结束后收尾完就走，太久没消息（对方那边出了岔子）也走
		if _phase == 0 and _t >= INTRO:
			_phase = 1
		if (_phase == 2 and _t2 >= OUTRO) or _t > 90.0:
			subject.get("hero").set_glow(0.0, _col(0))
			queue_free()
		return
	_tick_cam(dt)
	match _phase:
		0:
			if _t >= INTRO:
				_phase = 1
		1:
			_tick_bolts(dt)
		2:
			if not _emitted and _t2 >= 0.55:
				_emitted = true
				finished.emit(_success, _perfect, _total)
			if _t2 >= OUTRO:
				_end()
	_root.queue_redraw()


func _place_disc(d: MeshInstance3D, pos: Vector3, rad: float, alpha: float, spin: float) -> void:
	if d == null:
		return
	Vfx.orient_disc(d, pos, Vector3.DOWN, maxf(rad, 0.01))
	var m := d.material_override as ShaderMaterial
	m.set_shader_parameter("open", 1.0)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("spin", spin)


func _tick_bolts(dt: float) -> void:
	while _next < _sched.size() and _t >= float(_sched[_next]["at"]):
		var s: Dictionary = _sched[_next]
		_live.append({"pos": s["pos"], "t": 0.0, "win": s["win"], "left": s["taps"], "taps": s["taps"], "idx": _next,
				"auto": demo_auto >= 0.0 and randf() < demo_auto})
		_next += 1
		Sfx.play("swing_heavy", -8.0, 0.5)
		# 雷落之前，云里先亮一下
		Vfx.glint(_sky() + Vector3(randf_range(-5.0, 5.0), -1.0, randf_range(-5.0, 5.0)), _col(_next), 3.0)
	var i := 0
	while i < _live.size():
		var b: Dictionary = _live[i]
		b["t"] = float(b["t"]) + dt
		var win: float = b["win"]
		if bool(b["auto"]) and float(b["t"]) >= win * (0.72 if int(b["taps"]) == 1 else 0.3 + 0.2 * float(int(b["taps"]) - int(b["left"]))):
			_tap(i)
			if _phase != 1:
				return
			continue
		if float(b["t"]) >= win:
			_live.remove_at(i)
			_resolve(int(b["idx"]), false, false, int(b["taps"]) > 1)
			if _phase != 1:
				return
			continue
		i += 1


## 运镜：开场从脚下低机位绕着升起来 → 渡劫时斜后方仰拍（主角在画面下方、劫云在上方）→ 收尾推近 / 拉远
func _tick_cam(dt: float) -> void:
	var pc := _pc()
	var eye: Vector3
	var look: Vector3
	var fov := 68.0
	var back := Basis(Vector3.UP, _yaw0) * Vector3(0.0, 0.0, 1.0)
	var side := Basis(Vector3.UP, _yaw0) * Vector3(1.0, 0.0, 0.0)
	var play_eye := pc + back * 9.5 + side * 3.2 + Vector3.UP * -1.6
	var play_look := pc + Vector3.UP * 5.5
	if _phase == 0:
		var u := clampf(_t / INTRO, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		var ang := _yaw0 + PI * 0.9 + e * 2.6
		var rad := lerpf(3.2, 9.5, e)
		eye = pc + Vector3(sin(ang) * rad, lerpf(-1.9, -1.2, e), cos(ang) * rad)
		look = pc + Vector3.UP * lerpf(0.4, 5.5, e * e)
		# 最后三成并到渡劫机位上
		var j := smoothstep(0.7, 1.0, u)
		eye = eye.lerp(play_eye, j)
		look = look.lerp(play_look, j)
		fov = lerpf(52.0, 68.0, e)
	elif _phase == 1:
		eye = play_eye + side * sin(_t * 0.35) * 0.6
		look = play_look
	else:
		var u2 := clampf(_t2 / OUTRO, 0.0, 1.0)
		if _success:
			eye = play_eye.lerp(pc + back * 4.2 + side * 1.4 + Vector3.UP * 0.6, smoothstep(0.0, 0.8, u2))
			look = play_look.lerp(pc + Vector3.UP * 0.4, smoothstep(0.0, 0.6, u2))
			fov = lerpf(68.0, 50.0, smoothstep(0.0, 0.8, u2))
		else:
			eye = play_eye + back * 3.0 * u2
			look = play_look.lerp(pc, smoothstep(0.0, 0.5, u2))
	var f := look - eye
	cam.cine_xf = Transform3D(Basis.looking_at(f, Vector3.UP), eye)
	cam.cine_fov = fov
	cam.cine_k = 1.0 if _phase < 2 else 1.0 - smoothstep(OUTRO - 0.5, OUTRO, _t2)
	if dt > 0.0 and _phase == 1:
		cam.add_trauma(0.004 * float(realm_to))


func _end() -> void:
	cam.cine_k = 0.0
	cam.impact_r = _old_r
	player.global_position = _base + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	player.hero.set_glow(0.0, _col(0))
	player.process_mode = Node.PROCESS_MODE_INHERIT
	Input.mouse_mode = _old_mouse
	queue_free()


# ---------- 界面 ----------

func _draw() -> void:
	var vs := _root.size
	var bf := UiStyle.brush()
	var kf := UiStyle.kai()
	var gold := UiStyle.GOLD
	var ink := UiStyle.INK
	var k := vs.y / 720.0
	# 顶上：劫名 · 第几道 · 劫数（还能失误几次）
	var title: String = "%s　第 %d / %d 道" % [NAMES[realm_to], mini(_done + (0 if _live.is_empty() else 1), _total), _total] if _phase > 0 else NAMES[realm_to]
	var fs := int(46.0 * k)
	var ts := bf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var ta := clampf(_t / 0.8, 0.0, 1.0)
	_root.draw_string_outline(bf, Vector2((vs.x - ts.x) * 0.5, 74.0 * k), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(ink.r, ink.g, ink.b, 0.9 * ta))
	_root.draw_string(bf, Vector2((vs.x - ts.x) * 0.5, 74.0 * k), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE.lerp(_col(_done), 0.5) * Color(1, 1, 1, ta))
	if _phase == 1:
		var lives := _allow + 1 - _missed
		for i in _allow + 1:
			var c := Vector2(vs.x * 0.5 + (float(i) - float(_allow) * 0.5) * 30.0 * k, 104.0 * k)
			_root.draw_circle(c, 8.0 * k, Color(ink.r, ink.g, ink.b, 0.8))
			if i < lives:
				_root.draw_circle(c, 6.0 * k, gold)
			_root.draw_arc(c, 8.0 * k, 0.0, TAU, 20, Color(gold.r, gold.g, gold.b, 0.8), 1.5, true)
		var hint := "雷落之前点「挡」" if demo_auto < 0.0 else "（自检：自动点击）"
		var hs := kf.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k))
		_root.draw_string_outline(kf, Vector2((vs.x - hs.x) * 0.5, 138.0 * k), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k), 5, Color(ink.r, ink.g, ink.b, 0.9))
		_root.draw_string(kf, Vector2((vs.x - hs.x) * 0.5, 138.0 * k), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * k), UiStyle.TEXT)
	# 圆钮
	var rr := BTN_R * k
	for b: Dictionary in _live:
		var c := (b["pos"] as Vector2) * vs
		var u := clampf(float(b["t"]) / float(b["win"]), 0.0, 1.0)
		var bc := _col(int(b["idx"]))
		var perfect := u >= 0.6
		_root.draw_circle(c, rr, Color(ink.r, ink.g, ink.b, 0.78))
		_root.draw_arc(c, rr, 0.0, TAU, 48, gold if perfect else Color(gold.r, gold.g, gold.b, 0.7), 4.0 if perfect else 2.5, true)
		_root.draw_arc(c, rr - 7.0 * k, 0.0, TAU, 48, Color(bc.r, bc.g, bc.b, 0.5), 1.5, true)
		# 往里收的环：进了完美区变金色
		var orad := lerpf(rr * 2.7, rr, u)
		var oc := Color(1.0, 0.86, 0.45) if perfect else UiStyle.CINNABAR.lightened(0.25)
		_root.draw_arc(c, orad, 0.0, TAU, 64, oc, 5.0 * k, true)
		var txt := "挡" if int(b["taps"]) == 1 else "×%d" % int(b["left"])
		var f2 := int(rr * (0.95 if txt.length() == 1 else 0.7))
		var s2 := bf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f2)
		_root.draw_string(bf, c + Vector2(-s2.x * 0.5, s2.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f2, Color.WHITE.lerp(bc, 0.35))
	# 连击 / 判定
	if _phase == 1 and _combo >= 2:
		var ct := "%d 连" % _combo
		var f3 := int(54.0 * k)
		_root.draw_string_outline(bf, Vector2(vs.x * 0.78, vs.y * 0.3), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, f3, 8, Color(ink.r, ink.g, ink.b, 0.9))
		_root.draw_string(bf, Vector2(vs.x * 0.78, vs.y * 0.3), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, f3, Color(1.0, 0.86, 0.45))
	if _msg_t > 0.0 and _phase == 1:
		var a := clampf(_msg_t / 0.3, 0.0, 1.0)
		var f4 := int(60.0 * k * (1.0 + 0.25 * clampf(_msg_t - 0.5, 0.0, 0.2) / 0.2))
		var s4 := bf.get_string_size(_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, f4)
		var p4 := Vector2((vs.x - s4.x) * 0.5, vs.y * 0.82)
		_root.draw_string_outline(bf, p4, _msg, HORIZONTAL_ALIGNMENT_LEFT, -1, f4, 8, Color(ink.r, ink.g, ink.b, 0.9 * a))
		_root.draw_string(bf, p4, _msg, HORIZONTAL_ALIGNMENT_LEFT, -1, f4, Color(_msg_col.r, _msg_col.g, _msg_col.b, a))
	# 结果
	if _phase == 2:
		var res := "渡劫成功" if _success else "渡劫失败"
		var ra := clampf(_t2 / 0.3, 0.0, 1.0) * (1.0 - smoothstep(OUTRO - 0.5, OUTRO, _t2))
		var f5 := int(110.0 * k)
		var s5 := bf.get_string_size(res, HORIZONTAL_ALIGNMENT_LEFT, -1, f5)
		var p5 := Vector2((vs.x - s5.x) * 0.5, vs.y * 0.3)
		_root.draw_string_outline(bf, p5, res, HORIZONTAL_ALIGNMENT_LEFT, -1, f5, 12, Color(ink.r, ink.g, ink.b, 0.9 * ra))
		var rc := Color(1.0, 0.88, 0.5) if _success else UiStyle.CINNABAR.lightened(0.2)
		_root.draw_string(bf, p5, res, HORIZONTAL_ALIGNMENT_LEFT, -1, f5, Color(rc.r, rc.g, rc.b, ra))
		var sub := "完美 %d / %d　最高 %d 连" % [_perfect, _total, _best] if _success else "修为倒退，稳固后再来"
		var f6 := int(26.0 * k)
		var s6 := kf.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, f6)
		_root.draw_string_outline(kf, Vector2((vs.x - s6.x) * 0.5, vs.y * 0.3 + 54.0 * k), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, f6, 6, Color(ink.r, ink.g, ink.b, 0.9 * ra))
		_root.draw_string(kf, Vector2((vs.x - s6.x) * 0.5, vs.y * 0.3 + 54.0 * k), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, f6, Color(UiStyle.TEXT.r, UiStyle.TEXT.g, UiStyle.TEXT.b, ra))
