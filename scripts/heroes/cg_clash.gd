extends Node3D
## 苍鸿蓄力刀光的对冲（2026-11-25）。用户原话：「记得要做对冲的逻辑，假设对方也是剑修，蓄力释放了一样的技能，要有个对冲的表现，
## 对冲的时候视觉冲击力要强，有一瞬间黑白画面，空间劈裂，空间波动的效果，有个运镜，能看到对波的具体表现，然后销毁，
## 触发这个的前提是，波的强度是一样的」。
## 谁建它：scripts/heroes/cg_wave.gd —— 两道蓄力放的刀光迎面撞上、强度一样（同是觉醒 / 同是平时，蓄力差不超过两成）时，
## 把两道都定在撞上的地方（held），在两道中间建这个节点；强度不一样的不走这里（强的把弱的劈碎、接着飞）。
## 三段（按真实时间走）：
##   0 相持 LOCK 秒：两道刀光刃口顶着刃口，每 SLAM 秒退半步再撞一下（每撞一下：火星、空间裂缝、一圈空间波动、镜头一震、顿一帧、
##     周边的方块崩掉一块），越撞越大，接触点不停地迸针芒
##   1 黑白 BW 秒：整屏一张黑白冲击帧（前半白底、后半反白），两道交叉的大斩线和一片空间裂缝印在上面，战斗时钟停住
##   2 炸开：两道刀光一起碎掉 —— 大裂缝、立着和平躺的两圈空间波动、黑红的破空圈、往四面八方迸的针芒和碎刀光；AFTER 秒后收
## 镜头和黑白只给放刀光的本机主角（attach(player)，技能脚本在 on_clash 里调）：切到接触点侧面的机位，相持时慢慢推近，炸开后拉远、混回跟随机位。
## 别人（旁观的 / 对面那位在他自己机器上）各自的机器上也会各自撞一遍：这个节点两边都建，伤害两边各自作废。
## 平时出招不闪黑白的规矩没变：这是用户点名要的例外（和觉醒演出、一线天一样）。故意不写 class_name。

const CgFx := preload("res://scripts/heroes/cg_fx.gd")
const Combat := preload("res://scripts/combat.gd")
const Sfx := preload("res://scripts/sfx.gd")
const SHADER := preload("res://shaders/manga_frame.gdshader")

const LOCK := 1.3             # 相持多久（第一版 0.75 秒，用户：「一下就过去了……要让两个刀刃撞在一起，持续一下」）
const SLAM := 0.26            # 相持中每隔这么久两道刀刃退半步、再撞一下
const BW := 0.16
const AFTER := 0.6

static var played := 0          # 自检用：对冲过几回
static var cine_n := 0          # 自检用：其中几回带镜头

var a: Node3D                   # 两道刀光（cg_wave.gd）
var b: Node3D
var axis := Vector3.FORWARD     # a 的去向
var col_a := Color(0.45, 0.85, 1.0)
var col_b := Color(0.45, 0.85, 1.0)
var aw := false
var size := 3.0                 # 刀光的半径（画面跟着它定大小）

var _phase := 0
var _t := 0.0
var _last_ms := 0
var _spark := 0.0
var _ring := 0.0
var _crack := 0.15
var _snd := 0.0
var _slam_n := -1
var _side := Vector3.RIGHT
var _player: Player = null
var _layer: CanvasLayer
var _mat: ShaderMaterial
var _rect: ColorRect
var _cam_k := 0.0


func _ready() -> void:
	process_priority = 20
	played += 1
	_last_ms = Time.get_ticks_msec()
	axis = axis.normalized() if axis.length_squared() > 1e-6 else Vector3.FORWARD
	_side = axis.cross(Vector3.UP)
	_side = _side.normalized() if _side.length_squared() > 1e-4 else Vector3.RIGHT
	var cam := get_viewport().get_camera_3d()
	if cam != null and _side.dot(cam.global_position - global_position) < 0.0:
		_side = -_side
	# 撞上的那一下
	var mc := CgFx.main_col(col_a, aw)
	CgFx.ring_warp(global_position, axis, size * 2.4, mc, 0.5, 0.1)
	CgFx.needles(global_position, axis, 2, col_a, aw, size * 2.2, 0.4, 0.09, 22)
	Vfx.glint(global_position, Color.WHITE, 2.0)
	Vfx.flash_light(global_position, mc, 3.0, 14.0, 0.3)
	Sfx.play("clash", 0.0, 0.9)
	Sfx.play("blade_cut", -2.0, 0.7)


func _exit_tree() -> void:
	if is_instance_valid(_player) and _player.cam != null:
		_player.cam.cine_k = 0.0


## 本机主角放的那一道撞上了：给他镜头和黑白帧
func attach(p: Player) -> void:
	if not is_instance_valid(p) or _player != null or DisplayServer.get_name() == "headless":
		return
	_player = p
	cine_n += 1
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("sil", 0.0)
	_mat.set_shader_parameter("k", 0.0)
	_mat.set_shader_parameter("bars", 0.0)
	_mat.set_shader_parameter("dim", 0.0)
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	_layer.add_child(_rect)
	Combat.hitstop(0.07, 0.0)
	p.cam.add_trauma(0.45)
	# 机位摆在接触点的哪一侧：两侧各探一下，挑空旷的那边（另一边可能贴着墙 / 大石头）
	var dist := size * 2.2 + 5.0
	var c := global_position
	var ra := _clear(c, c + _side * dist * 1.25 + Vector3.UP * dist * 0.22)
	var rb := _clear(c, c - _side * dist * 1.25 + Vector3.UP * dist * 0.22)
	if rb > ra + 0.08:
		_side = -_side


func _process(_dt: float) -> void:
	# 按真实时间走（黑白那一段战斗时钟是停的；有人开了慢动作也不拖长）
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_ms) * 0.001, 0.0, 0.05)
	_last_ms = now
	_t += dt
	var c := global_position
	var mc := CgFx.main_col(col_a, aw)
	match _phase:
		0:
			var u := clampf(_t / LOCK, 0.0, 1.0)
			# 两道刀刃：退半步（幅度越来越大）再撞回来，同一个节拍
			var cyc := fmod(_t, SLAM) / SLAM
			var off := -size * (0.14 + 0.1 * u) * sin(PI * cyc)
			for w: Node3D in [a, b]:
				if is_instance_valid(w):
					w.set("hold_off", off)
					w.set("hold_grow", u)
			var sn := int(_t / SLAM)
			if sn != _slam_n:
				_slam_n = sn
				_slam(u)
			_spark -= dt
			if _spark <= 0.0:
				_spark = 0.06 if not Vfx.lite else 0.11
				var rd := (_side * randf_range(-1.0, 1.0) + Vector3.UP * randf_range(-1.0, 1.0)).normalized()
				CgFx.needles(c + rd * size * 0.3 * randf(), rd, 3, col_a if randf() < 0.5 else col_b, aw, size * (1.2 + 1.2 * u), 0.3, 0.07, 10)
				Vfx.line_sparks(c, rd, Color(1.0, 0.9, 0.7), 4, 26.0, 60.0, 0.3)
			if _player != null:
				_player.cam.add_trauma(0.035 + 0.03 * u)      # 相持的时候镜头一直在抖，越到后面越凶
			if _t >= LOCK:
				_phase = 1
				_t = 0.0
				_bw_start()
		1:
			if _t >= BW:
				_phase = 2
				_t = 0.0
				_explode()
		2:
			if _t >= AFTER:
				queue_free()
				return
	_cam()


## 相持中的一下：两道刀刃刚撞上 —— 火星、裂缝、空间波动、镜头一震、顿一帧，周边的方块崩一块
func _slam(u: float) -> void:
	var c := global_position
	var mc := CgFx.main_col(col_a, aw)
	Vfx.blade_clash(c, _side, 1.4 + 1.2 * u)
	Vfx.glint(c, Color.WHITE, 1.6 + 1.4 * u)
	CgFx.ring_warp(c, axis, size * (1.6 + 1.6 * u), mc, 0.4, 0.08 + 0.05 * u)
	CgFx.needles(c, axis, 2, col_a if _slam_n % 2 == 0 else col_b, aw, size * (1.8 + 1.4 * u), 0.34, 0.09, 18)
	Vfx.space_crack(c, mc, size * (0.7 + 0.8 * u), (2 if Vfx.lite else 4) + int(3.0 * u), 0.34, 0.35)
	if aw or u > 0.5:
		CgFx.tear(c, axis, size * 0.9, size * (2.2 + 1.0 * u), 0.42)
	Vfx.flash_light(c, mc, 2.0 + 2.0 * u, 12.0, 0.16)
	Sfx.play("clash", -3.0 + 3.0 * u, randf_range(0.8, 1.05))
	Sfx.play("hit_heavy", -8.0, randf_range(0.7, 0.9))
	if _player != null:
		var cam := _player.cam
		cam.add_trauma(0.3 + 0.25 * u)
		cam.fov_punch(3.0 + 3.0 * u)
		Combat.hitstop(0.04, 0.0)
		if u > 0.4:
			cam.impact(0.2 + 0.2 * u)
		Vfx.warp_pos = c
		Vfx.warp_k = maxf(Vfx.warp_k, 0.02 + 0.015 * u)
		# 觉醒的血刃对冲：每撞一下周边崩一大块；平时的光刀：只崩一小块浅的（减半）
		if aw:
			_wreck(c, size * (1.2 + 0.9 * u), 1.0 + 0.8 * u)
		else:
			_wreck(c, size * (0.55 + 0.4 * u), 0.4 + 0.3 * u)


## 把周边的方块打碎（scripts/destruct.gd；只有本机放刀光的人这边炸，破坏自己会同步给别人）
func _wreck(pos: Vector3, r: float, power: float) -> void:
	if not ResourceLoader.exists("res://scripts/destruct.gd"):
		return
	var ds: GDScript = load("res://scripts/destruct.gd")
	if ds != null and ds.has_method("blast"):
		ds.call("blast", pos, r, power, Vector3.ZERO, {} if aw else {"depth_k": 0.3})


## 黑白那一帧：先把交叉的两道大斩线和一片裂缝画出来（它们会印在黑白画面上），战斗时钟停住
func _bw_start() -> void:
	var c := global_position
	var mc := CgFx.main_col(col_a, aw)
	var d1 := (_side * 0.8 + Vector3.UP * 0.6).normalized()
	var d2 := (_side * -0.8 + Vector3.UP * 0.6).normalized()
	CgFx.cut(c, d1, size * 9.0, col_a, aw, BW + 0.1, 2.4)
	CgFx.cut(c, d2, size * 9.0, col_b, aw, BW + 0.1, 2.4)
	Vfx.space_crack(c, mc, size * 1.6, 5 if Vfx.lite else 9, BW + 0.45, 0.5)
	Vfx.rift(c, _side, mc, size * 0.9, BW + 0.35)
	Sfx.play("perfect", -2.0, 0.7)
	Sfx.play("punch_heavy", -1.0, 0.6)
	if _player != null:
		Combat.hitstop(BW, 0.0)
		_player.cam.add_trauma(0.4)


## 炸开：两道刀光一起碎掉
func _explode() -> void:
	var c := global_position
	var mc := CgFx.main_col(col_a, aw)
	for w: Node3D in [a, b]:
		if is_instance_valid(w):
			w.call("shatter")
	CgFx.ring_warp(c, axis, size * 5.0, mc, 0.7, 0.13)
	CgFx.ring_warp(c, Vector3.UP, size * 4.0, mc, 0.8, 0.1)
	CgFx.tear(c, axis, size * 1.2, size * 4.5, 0.7)
	if not Vfx.lite:
		CgFx.tear(c, (axis + _side * 0.5).normalized(), size * 0.9, size * 3.4, 0.6)
	CgFx.needles(c, Vector3.UP, 1, col_a, aw, size * 4.0, 0.6, 0.1, 30)
	CgFx.needles(c, axis, 2, col_b, aw, size * 4.5, 0.55, 0.1, 30)
	# 碎掉的刀光：几片小新月往四面甩出去
	var n := 4 if Vfx.lite else 8
	for i in n:
		var rd := Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 1.0), randf_range(-1.0, 1.0)).normalized()
		CgFx.fly_arc(c + rd * size * 0.3, rd, rd.cross(axis + Vector3.UP * 0.3), size * randf_range(0.35, 0.7), 130, col_a if i % 2 == 0 else col_b, aw, size * randf_range(2.0, 4.0), randf_range(0.3, 0.5))
	Vfx.shockwave(c, axis, Color.WHITE.lerp(mc, 0.4), 3.0)
	Vfx.flash_light(c, mc, 5.0, 20.0, 0.4)
	var star := Vfx._sprite(c, Color.WHITE, 0, size)
	Vfx._fade(star, Vector3.ONE * size * 7.0, 0.25)
	Sfx.play("shatter", 0.0, 0.7)
	Sfx.play("cut_burst", 1.0, 0.75)
	Sfx.play("slam", -2.0, 0.8)
	if _player != null:
		var cam := _player.cam
		cam.impact(0.7)
		cam.add_trauma(0.9)
		cam.fov_punch(10.0)
		Vfx.warp_pos = c
		Vfx.warp_k = maxf(Vfx.warp_k, 0.04)
		# 炸开：周围一大片方块一起碎（接触点一个大的，沿两道刀光来的方向各补一个）
		if aw:
			_wreck(c, size * 3.0, 2.5)
			_wreck(c + axis * size * 2.0, size * 1.8, 2.0)
			_wreck(c - axis * size * 2.0, size * 1.8, 2.0)
			_wreck(c + _side * size * 2.0, size * 1.6, 1.8)
			_wreck(c - _side * size * 2.0, size * 1.6, 1.8)
		else:
			_wreck(c, size * 1.4, 1.0)


static func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u)


## 从接触点往机位看过去，第一处挡住的东西在几成的地方（1 = 一路没挡）：物理射线（试剑台 / 主城的方块）+ 关卡自己的实心盒子
func _clear(c: Vector3, eye: Vector3) -> float:
	var k := 1.0
	var w := get_world_3d()
	if w != null and w.direct_space_state != null:
		var q := PhysicsRayQueryParameters3D.create(c, eye)
		q.collide_with_areas = false
		if _player is CollisionObject3D:
			q.exclude = [(_player as CollisionObject3D).get_rid()]
		var hit := w.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			k = clampf(c.distance_to(hit["position"]) / maxf(c.distance_to(eye), 0.01), 0.0, 1.0)
	var sh: Vector3 = _player.solid_hit(c, eye, 0.4, 0.5, 0.0)
	if sh != Vector3.INF:
		k = minf(k, clampf(c.distance_to(sh) / maxf(c.distance_to(eye), 0.01), 0.0, 1.0))
	return k


func _fit(c: Vector3, eye: Vector3) -> Vector3:
	var k := _clear(c, eye)
	if k < 0.3:
		return Vector3.INF
	var e := c + (eye - c) * (1.0 if k >= 0.999 else k * 0.86)
	var fy := -1e9
	if _player.cam.floor_fn.is_valid():
		fy = float(_player.cam.floor_fn.call(e.x, e.z))
	e.y = maxf(e.y, fy + 0.4)
	return e


## 镜头（只有本机放刀光的人）：接触点侧面偏上的机位，两道刀光一左一右顶在画面中间；相持时推近，黑白那一帧再贴近、歪一点，炸开后拉远混回去
func _cam() -> void:
	if _player == null or not is_instance_valid(_player) or _player.dead:
		return
	var cam := _player.cam
	var c := global_position
	var vs := get_viewport().get_visible_rect().size
	var dist := size * 2.2 + 5.0
	var eye := Vector3.ZERO
	var fov := 56.0
	var roll := 0.0
	var k := 0.0
	var inv := 0.0
	var ck := 1.0
	match _phase:
		0:
			var u := _ease(_t / LOCK)
			eye = c + _side * dist * lerpf(1.25, 0.9, u) + Vector3.UP * dist * 0.22 + axis * dist * lerpf(0.35, 0.1, u)
			fov = lerpf(60.0, 48.0, u)
			roll = lerpf(0.0, 0.06, u)
			ck = clampf(_t / 0.2, 0.0, 1.0)
		1:
			eye = c + _side * dist * 0.8 + Vector3.UP * dist * 0.16 + axis * dist * 0.08
			fov = 44.0
			roll = -0.12
			k = 1.0
			inv = 1.0 if _t > BW * 0.5 else 0.0
		2:
			var u2 := _ease(_t / AFTER)
			eye = c + _side * dist * lerpf(0.9, 1.5, u2) + Vector3.UP * dist * lerpf(0.2, 0.35, u2) + axis * dist * 0.1
			fov = lerpf(64.0, 58.0, u2)
			ck = clampf((AFTER - _t) / 0.3, 0.0, 1.0)
	var fit := _fit(c, eye)
	if fit == Vector3.INF:
		cam.cine_k = 0.0
	else:
		var f := c - fit
		var up := Vector3.UP if absf(f.normalized().dot(Vector3.UP)) < 0.97 else Vector3.BACK
		cam.cine_xf = Transform3D(Basis.looking_at(f, up) * Basis(Vector3.BACK, roll), fit)
		cam.cine_fov = fov
		cam.cine_k = ck
	if _mat != null:
		_mat.set_shader_parameter("k", k)
		_mat.set_shader_parameter("invert", inv)
		_mat.set_shader_parameter("lines", 0.9 if k > 0.5 else 0.0)
		_mat.set_shader_parameter("seed", 8.0 + inv)
		_mat.set_shader_parameter("center", Vector2(0.5, 0.5))
		_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		_rect.visible = k > 0.001
