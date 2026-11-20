class_name FlyingSword
extends Node3D
## 单柄飞剑：阵位环绕 → 出击 → 命中 →（连斩）→ 贝塞尔回鞘。出击轨迹按法相档位（Realm.ARTS strike）整套更换：
##   0 炼气/筑基 弧线飞斩：三次贝塞尔先向外上方荡开再折向目标（剑尖对准切线，连斩/回程 C1 连续不折角）
##   1 结丹 金丹剑气：剑尖先对准目标、后撤蓄势，再一条直线贯穿过去
##   2 元婴 雷闪折线：几段锯齿折线闪向目标，折角处迸电星；连斩时两目标间劈一道电弧
##   3 化神 火轮环斩：剑身翻滚成火轮，荡到目标侧面后绕着目标螺旋收紧斩入，剑光从剑尖拖出（一圈圈火环）
##   4 炼虚 遁虚天降：原地遁入虚空，从目标正上方的光环里现身，直坠而下
##   5 合体 裂空穿刺：前冲钻进一道裂隙，从目标侧面另一道裂隙里刺出，贯穿而过
##   6 大乘 天剑下贯：拔地升空、剑身涨成巨剑，身后张开一扇空间门，悬停一瞬后下贯，落点范围伤害
## 剑尖始终对准运动方向（火轮翻滚除外）。

const Proj := preload("res://scripts/spell_projectile.gd")

enum S { ORBIT, STRIKE, RETURN }

const SIZE := Vector3.ONE * 1.8     # 飞剑整体放大（2026-11 两次：1.0 → 1.45 → 1.8）
var mgr: SwordManager
var state := S.ORBIT
var model: Node3D
var trail: Trail3D

var _idx := 0
var _off := Vector3.ZERO      # 环绕时相对玩家的偏移（局部跟随，高速飞行不掉队）
var _p0 := Vector3.ZERO
var _p1 := Vector3.ZERO
var _p2 := Vector3.ZERO
var _p3 := Vector3.ZERO
var _p2_rel := Vector3.ZERO
var _t := 0.0
var _dur := 0.4
var _target: Node3D           # 木桩 / 刀客 / 空战对手 / 搜打撤的怪（见 SwordManager.pick_enemy）
var _chain := 0
var _dir := Vector3.DOWN
var _col := Color.WHITE
var _blade_mat: StandardMaterial3D
var _dying := false
var _cloaked := false
var _hidden := false          # 出击途中遁入虚空 / 裂隙，剑身暂不可见
var _art := 0                 # 本次出击的法相档位
var _ph := 0                  # 出击分段
var _ph_t := 0.0
var _zig := PackedVector3Array()
var _zi := 0
var _spin := 0.0
var _tip_trail := false       # 火轮：剑光从剑尖拖出
var _swirl := 1.0             # 火轮绕目标的方向
var _ent := Vector3.ZERO      # 火轮切入点相对目标的偏移
var _big := 1.0               # 天剑：剑身当前放大倍数


func _ready() -> void:
	model = MeshLib.make_sword(_col)
	_blade_mat = model.get_meta("blade_mat")
	model.visible = not _cloaked
	add_child(model)
	# 出剑剑光：一条很细的线，留存稍长，能看清整段弧形轨迹
	trail = Trail3D.new()
	trail.width = 0.07
	trail.lifetime = 0.32
	trail.min_px = 2.2
	trail.smooth = 2
	trail.point_fn = _trail_head
	trail.material_override = MeshLib.trail_material(Color.WHITE, _col, 0, 1.2)
	Vfx.root.add_child(trail)


func _exit_tree() -> void:
	if is_instance_valid(trail):
		trail.queue_free()


func _trail_head() -> Vector3:
	if _tip_trail and model != null:
		return model.global_transform * Vector3(0.0, 0.62, 0.0)
	return global_position


func set_color(col_a: Color, col_b: Color) -> void:
	_col = col_b
	if _blade_mat != null:
		_blade_mat.emission = col_b
		var tm := trail.material_override as ShaderMaterial
		tm.set_shader_parameter("color_a", Color.WHITE.lerp(col_a, 0.5))
		tm.set_shader_parameter("color_b", col_b)


## 换法相：剑光样式与宽度（Realm.ARTS trail / tw），高阶剑身更亮
func set_art(art: int) -> void:
	var info: Dictionary = Realm.ARTS[art]
	trail.width = float(info["tw"])
	trail.lifetime = 0.32 + 0.025 * art
	(trail.material_override as ShaderMaterial).set_shader_parameter("style", int(info["trail"]))
	if _blade_mat != null:
		_blade_mat.emission_energy_multiplier = 0.7 + 0.25 * art


## 遁光时隐藏剑身本体（出击中的剑只剩一条细剑光）；收遁后弹回显示
func set_cloaked(on: bool) -> void:
	if _cloaked == on:
		return
	_cloaked = on
	if model == null:
		return
	model.visible = not on and not _hidden
	if not on and not _dying and not _hidden:
		spawn_pop()


func _set_hidden(on: bool) -> void:
	_hidden = on
	model.visible = not on and not _cloaked


## 召剑：直接放到环位上（相对玩家的偏移 off），不从玩家身上飞出来
func place(off: Vector3, b: Basis) -> void:
	_off = off
	global_position = mgr.player.global_position + off
	global_basis = b


func spawn_pop() -> void:
	model.scale = SIZE * 0.01
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func dismiss() -> void:
	_dying = true
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * 0.01, 0.2)
	tw.tween_callback(queue_free)


func is_idle() -> bool:
	return state == S.ORBIT and not _dying


func tick(dt: float, idx: int) -> void:
	_idx = idx
	var pc := mgr.player.global_position
	match state:
		S.ORBIT:
			var so := mgr.slot_offset(idx)
			_off = _off.lerp(so, 1.0 - exp(-12.0 * dt))
			global_position = pc + _off
			_orient_to(mgr.slot_basis_for(idx, so), dt, 10.0)
		S.STRIKE:
			if Proj.alive(_target):
				_p3 = Proj.aim_of(_target)
			match _art:
				1: _tick_thrust(dt)
				2: _tick_zig(dt)
				3: _tick_wheel(dt)
				4: _tick_void(dt)
				5: _tick_rift(dt)
				6: _tick_heaven(dt)
				_: _tick_arc(dt)
		S.RETURN:
			var so := mgr.slot_offset(idx)
			_p3 = pc + so
			_p2 = _p3 + _p2_rel
			# 遁光中回鞘的剑会追着高速移动的主角，剑光会在遁光轨迹旁多拖出杂线：直接收掉
			if _cloaked:
				trail.emitting = false
			if _big > 1.001:
				_big = lerpf(_big, 1.0, 1.0 - exp(-8.0 * dt))
				model.scale = SIZE * _big
			_t += dt / _dur
			var u := minf(_t, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			if u < 0.72:
				_follow_curve(e, dt, 18.0)
			else:
				global_position = _p0.bezier_interpolate(_p1, _p2, _p3, e)
				_orient_to(mgr.slot_basis_for(idx, so), dt, 14.0)
			if _t >= 1.0:
				state = S.ORBIT
				_off = global_position - pc
				trail.emitting = false
				_big = 1.0
				model.scale = SIZE


func _follow_curve(e: float, dt: float, rate: float) -> void:
	_follow(_p3, e, dt, rate)


## 沿 _p0 → _p1 → _p2 → end 的三次贝塞尔走到参数 e，剑尖对准切线
func _follow(end: Vector3, e: float, dt: float, rate: float) -> void:
	global_position = _p0.bezier_interpolate(_p1, _p2, end, e)
	var d := _p0.bezier_derivative(_p1, _p2, end, e)
	if d.length_squared() > 1e-6:
		_dir = d.normalized()
	_orient_to(_aim_basis(_dir), dt, rate)


## 剑尖(+Y)对准 d、尽量保持当前滚转的朝向
func _aim_basis(d: Vector3) -> Basis:
	var b := global_basis
	var x := d.cross(b.z)
	if x.length_squared() < 1e-6:
		x = d.cross(b.x)
	x = x.normalized()
	return Basis(x, d, x.cross(d))


func _orient_to(target: Basis, dt: float, rate: float) -> void:
	var q := global_basis.get_rotation_quaternion()
	global_basis = Basis(q.slerp(target.get_rotation_quaternion(), 1.0 - exp(-rate * dt)))


## 直线移动一帧并让剑尖对准移动方向
func _move_line(to: Vector3, dt: float, rate: float) -> void:
	var d := to - global_position
	if d.length_squared() > 1e-6:
		_dir = d.normalized()
		_orient_to(_aim_basis(_dir), dt, rate)
	global_position = to


func _frame(fwd: Vector3) -> Array:
	var side := fwd.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	return [side, side.cross(fwd)]


## from_dir 非零时表示连斩：起始切线沿上一击的出射方向
func strike(target: Node3D, chain: int, from_dir := Vector3.ZERO) -> void:
	state = S.STRIKE
	_target = target
	_chain = chain
	_art = Realm.art(mgr.player.realm)
	_t = 0.0
	_ph = 0
	_ph_t = 0.0
	_p0 = global_position
	_p3 = Proj.aim_of(target)
	model.basis = Basis.IDENTITY
	_tip_trail = false
	match _art:
		1:
			_begin_thrust(from_dir)
		2:
			_begin_zig()
		3:
			_begin_wheel(from_dir)
		4:
			trail.emitting = false
		5:
			_begin_rift()
		6:
			_begin_heaven()
		_:
			_begin_arc(from_dir)


# ---------- 0 弧线飞斩（炼气 / 筑基） ----------

func _begin_arc(from_dir: Vector3) -> void:
	var to := _p3 - _p0
	var dist := maxf(to.length(), 0.01)
	var fwd := to / dist
	var fr := _frame(fwd)
	var side: Vector3 = fr[0]
	var up: Vector3 = fr[1]
	var swing := clampf(dist * 0.45, 1.5, 9.0)
	if from_dir != Vector3.ZERO:
		_p1 = _p0 + from_dir * swing
		_dur = clampf(dist / 50.0, 0.18, 0.45)
	else:
		# 先向外侧上方荡开，再折向目标
		var out := _p0 - mgr.player.center()
		out.y = 0.0
		out = out.normalized() if out.length_squared() > 1e-4 else side
		var k := out * randf_range(0.5, 1.0) + Vector3.UP * randf_range(0.3, 1.0) + side * randf_range(-0.6, 0.6)
		_p1 = _p0 + k.normalized() * swing
		_dur = clampf(dist / 38.0, 0.3, 0.62)
	_p2 = _p3 - fwd * swing * 0.5 + side * randf_range(-1.0, 1.0) * swing * 0.6 + up * randf_range(-0.2, 0.9) * swing * 0.5
	_p1.y = maxf(_p1.y, 0.4)
	_p2.y = maxf(_p2.y, 0.4)
	trail.emitting = true


func _tick_arc(dt: float) -> void:
	_t += dt / _dur
	var u := minf(_t, 1.0)
	var e := u * u * (2.2 - 1.2 * u)  # 先蓄势后加速
	_follow_curve(e, dt, 24.0)
	if _t >= 1.0:
		_on_hit()


# ---------- 1 金丹剑气：后撤蓄势 → 直线贯穿 ----------

func _begin_thrust(from_dir: Vector3) -> void:
	if from_dir != Vector3.ZERO:
		_start_dash(75.0)
		return
	var fwd := (_p3 - _p0).normalized()
	_p1 = _p0 - fwd * 0.9 + Vector3.UP * 0.25
	trail.emitting = false


func _start_dash(spd: float) -> void:
	_ph = 1
	_t = 0.0
	_p0 = global_position
	_dur = clampf(_p0.distance_to(_p3) / spd, 0.07, 0.35)
	trail.emitting = true


func _tick_thrust(dt: float) -> void:
	if _ph == 0:
		_ph_t += dt
		var u := minf(_ph_t / 0.15, 1.0)
		global_position = _p0.lerp(_p1, 1.0 - (1.0 - u) * (1.0 - u))
		_dir = (_p3 - global_position).normalized()
		_orient_to(_aim_basis(_dir), dt, 30.0)
		if u >= 1.0:
			Vfx.glint(global_position + _dir * 0.7, Color(1.0, 0.86, 0.45), 0.7)
			_start_dash(75.0)
		return
	_t += dt / _dur
	var u := minf(_t, 1.0)
	_move_line(_p0.lerp(_p3, u * (0.45 + 0.55 * u)), dt, 40.0)
	if _t >= 1.0:
		_on_hit()


# ---------- 2 雷闪折线 ----------

func _begin_zig() -> void:
	var to := _p3 - _p0
	var dist := maxf(to.length(), 0.01)
	var fwd := to / dist
	var fr := _frame(fwd)
	var n := 3 if dist < 12.0 else 4
	_zig.clear()
	var s := 1.0 if randf() < 0.5 else -1.0
	for k in n:
		var t := (float(k) + 0.6) / float(n + 1)
		s = -s  # 左右交替，折成锯齿
		var p := _p0 + to * t + (fr[0] as Vector3) * s * randf_range(0.5, 1.0) * minf(dist * 0.22, 3.5) \
				+ (fr[1] as Vector3) * randf_range(-0.3, 0.6) * minf(dist * 0.15, 2.0)
		p.y = maxf(p.y, 0.4)
		_zig.append(p)
	_zi = 0
	trail.emitting = true


func _tick_zig(dt: float) -> void:
	var step := 66.0 * dt
	var to_target := _zi >= _zig.size()
	var w := _p3 if to_target else _zig[_zi]
	var d := w - global_position
	var l := d.length()
	if l <= step:
		# 正好停在折角上，剑光才折得干脆
		_move_line(w, dt, 80.0)
		global_basis = _aim_basis(_dir)
		if to_target:
			_on_hit()
			return
		_zi += 1
		Vfx.glint(w, Color.WHITE.lerp(_col, 0.4), 0.45)
	else:
		_move_line(global_position + d / l * step, dt, 80.0)
		global_basis = _aim_basis(_dir)


# ---------- 3 火轮环斩 ----------

func _begin_wheel(from_dir: Vector3) -> void:
	var to := _p3 - _p0
	var dist := maxf(to.length(), 0.01)
	var fwd := to / dist
	var fr := _frame(fwd)
	_swirl = 1.0 if randf() < 0.5 else -1.0
	_ent = (fr[0] as Vector3) * _swirl * 2.6 - fwd * 0.6 + Vector3.UP * 0.7
	var swing := clampf(dist * 0.4, 1.5, 7.0)
	var lead := from_dir if from_dir != Vector3.ZERO else (Vector3.UP * 0.7 + fwd * 0.5 + (fr[0] as Vector3) * _swirl * 0.4).normalized()
	_p1 = _p0 + lead * swing
	_p1.y = maxf(_p1.y, 0.4)
	_dur = clampf(dist / 42.0, 0.22, 0.5)
	_tip_trail = true
	trail.emitting = true


func _tick_wheel(dt: float) -> void:
	_spin += dt * 24.0
	model.basis = Basis(Vector3.RIGHT, _spin)
	var ent := _p3 + _ent
	if _ph == 0:
		_p2 = ent - (_ent.cross(Vector3.UP).normalized() * _swirl * 2.0)
		_t += dt / _dur
		var u := minf(_t, 1.0)
		_follow(ent, u * (0.6 + 0.4 * u), dt, 20.0)
		if _t >= 1.0:
			_ph = 1
			_t = 0.0
		return
	# 绕目标转约 0.8 圈并收紧到目标身上
	_t += dt / 0.34
	var u := minf(_t, 1.0)
	var a0 := atan2(_ent.z, _ent.x)
	var a := a0 - _swirl * u * TAU * 0.8
	var r := Vector2(_ent.x, _ent.z).length() * (1.0 - u)
	_move_line(_p3 + Vector3(cos(a) * r, _ent.y * (1.0 - u), sin(a) * r), dt, 30.0)
	if _t >= 1.0:
		model.basis = Basis.IDENTITY
		_on_hit()


# ---------- 4 遁虚天降 ----------

func _tick_void(dt: float) -> void:
	_ph_t += dt
	match _ph:
		0:
			# 原地缩成一点、遁入虚空
			var u := minf(_ph_t / 0.12, 1.0)
			model.scale = SIZE * maxf(1.0 - u, 0.01)
			if u >= 1.0:
				Vfx.glint(global_position, Color.WHITE.lerp(_col, 0.4), 0.6)
				_set_hidden(true)
				_next_ph()
		1:
			if _ph_t >= 0.08:
				# 目标正上方现身：一圈光环里冒出来，剑尖朝下
				var a := randf() * TAU
				global_position = _p3 + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.4, 1.3) + Vector3.UP * 7.0
				_dir = (_p3 - global_position).normalized()
				global_basis = _aim_basis(_dir)
				trail.clear()
				Vfx.sky_ring(global_position + Vector3.UP * 0.6, _col, 0.9, 0.35)
				_set_hidden(false)
				_next_ph()
		2:
			var u := minf(_ph_t / 0.1, 1.0)
			model.scale = SIZE * lerpf(0.2, 1.25, u)
			_dir = (_p3 - global_position).normalized()
			_orient_to(_aim_basis(_dir), dt, 30.0)
			if u >= 1.0:
				_start_dash(90.0)
				_ph = 3
		_:
			_t += dt / _dur
			var u := minf(_t, 1.0)
			_move_line(_p0.lerp(_p3, u * u), dt, 40.0)
			if _t >= 1.0:
				model.scale = SIZE
				_on_hit()


func _next_ph() -> void:
	_ph += 1
	_ph_t = 0.0


# ---------- 5 裂空穿刺 ----------

func _begin_rift() -> void:
	var fwd := (_p3 - _p0).normalized()
	_p1 = _p0 + fwd * 1.4
	Vfx.rift(_p1, fwd, _col, 0.8, 0.32)
	trail.emitting = true


func _tick_rift(dt: float) -> void:
	_ph_t += dt
	match _ph:
		0:
			# 朝目标前冲一小段，钻进面前的裂隙
			var u := minf(_ph_t / 0.14, 1.0)
			_move_line(_p0.lerp(_p1, u * u), dt, 40.0)
			model.scale = SIZE * clampf((1.0 - u) / 0.4, 0.01, 1.0)
			if u >= 1.0:
				_set_hidden(true)
				trail.emitting = false
				_next_ph()
		1:
			if _ph_t >= 0.07:
				# 目标侧面 / 背后另开一道裂隙，从里面刺出
				var tp := _p3 - mgr.player.center()
				tp.y = 0.0
				tp = tp.normalized() if tp.length_squared() > 1e-4 else Vector3.FORWARD
				var side := tp.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
				var ed := (side + tp * randf_range(0.0, 0.9) + Vector3.UP * randf_range(0.2, 0.5)).normalized()
				global_position = _p3 + ed * 4.2
				global_position.y = maxf(global_position.y, 0.5)
				_dir = (_p3 - global_position).normalized()
				global_basis = _aim_basis(_dir)
				Vfx.rift(global_position, _dir, _col, 1.0, 0.36)
				trail.clear()
				model.scale = SIZE
				_set_hidden(false)
				_next_ph()
		2:
			_dir = (_p3 - global_position).normalized()
			_orient_to(_aim_basis(_dir), dt, 40.0)
			if _ph_t >= 0.06:
				_start_dash(90.0)
				_ph = 3
		_:
			_t += dt / _dur
			var u := minf(_t, 1.0)
			_move_line(_p0.lerp(_p3, u), dt, 40.0)
			if _t >= 1.0:
				_on_hit()


# ---------- 6 天剑下贯 ----------

func _begin_heaven() -> void:
	var pc := mgr.player.center()
	var dist := _p0.distance_to(_p3)
	_p2_rel = pc.lerp(_p3, 0.45) + Vector3.UP * (9.0 + dist * 0.1)  # 升空的顶点
	_p1 = _p0 + Vector3.UP * 3.0
	_p2 = _p2_rel - Vector3.UP * 2.5
	_dur = 0.34
	trail.emitting = true


func _tick_heaven(dt: float) -> void:
	_ph_t += dt
	match _ph:
		0:
			_t += dt / _dur
			var u := minf(_t, 1.0)
			_follow(_p2_rel, 1.0 - (1.0 - u) * (1.0 - u), dt, 22.0)
			_big = lerpf(1.0, 2.8, u)
			model.scale = SIZE * _big
			if _t >= 1.0:
				# 顶点处一圈细环（不开空间门：旋涡门只给 R 大罡剑阵用）
				Vfx.sky_ring(global_position, Realm.line_color(mgr.player.realm), 1.5, 0.35)
				_next_ph()
		1:
			_dir = (_p3 - global_position).normalized()
			_orient_to(_aim_basis(_dir), dt, 26.0)
			if _ph_t >= 0.12:
				_start_dash(95.0)
				_ph = 2
		_:
			_t += dt / _dur
			var u := minf(_t, 1.0)
			_move_line(_p0.lerp(_p3, u * u), dt, 40.0)
			if _t >= 1.0:
				_on_hit()


# ---------- 命中 / 连斩 / 回鞘 ----------

func _on_hit() -> void:
	var realm := mgr.player.realm
	var pos := _p3
	var prev: Node3D = _target if is_instance_valid(_target) else null    # 目标可能在飞行途中被释放（大世界的怪死了就删）
	if Proj.alive(_target):
		var dmg: float = realm["dmg"]
		_hurt(_target, dmg * randf_range(0.85, 1.15))
		if _art == 0:
			Vfx.hit(pos, _dir, _col, 1.0)
		else:
			Vfx.art_hit(pos, _dir, _col, _art, false)
		var near := clampf(1.0 - pos.distance_to(mgr.player.center()) / 30.0, 0.0, 1.0)
		mgr.player.cam.add_trauma((0.12 if _art == 6 else 0.05) * near)
	if _art == 6:
		Proj.hurt_area(mgr.player, pos, 3.5, float(realm["dmg"]) * 0.6, _dir, _col, true, prev)
	if _chain > 0 and not _dying:
		var rng: float = realm["range"]
		var nxt := mgr.pick_enemy(pos, rng * 0.6, prev, mgr.player.melee_k >= 0.5)
		if nxt != null:
			if _art == 2:
				Vfx.lightning(pos, Proj.aim_of(nxt), _col, 0.1, 0.25, 6)
			strike(nxt, _chain - 1, _dir)
			return
	_begin_return()


## 一柄飞剑扎中：木桩直接扣血；别的（刀客、空战对手、搜打撤的怪）走它们自己的受击入口，和法术弹命中是同一套参数。
## 不走 Proj.hurt：那边会给空战连击计数加数，飞剑阵是自动出剑，不该替玩家攒连击；也不带顿帧（一秒十几剑，带了画面会一直卡）。
func _hurt(n: Node3D, dmg: float) -> void:
	if n is EnemyDummy:
		(n as EnemyDummy).take_hit(dmg, _dir, _col)
		return
	if not n.has_method("receive_hit"):
		return
	var fd := Vector3(_dir.x, 0.0, _dir.z)
	fd = fd.normalized() if fd.length_squared() > 1e-4 else Vector3.FORWARD
	n.receive_hit(mgr.player, {"dmg": dmg, "pst": dmg * 0.6, "kb": 1.5, "dir": fd, "step": 0, "heavy": false,
			"contact": Proj.aim_of(n), "launch": 0.0, "air": false, "swing": _dir, "stop": 0.0})


func _begin_return() -> void:
	state = S.RETURN
	_t = 0.0
	_set_hidden(false)
	_tip_trail = false
	model.basis = Basis.from_scale(Vector3.ONE * _big)
	_p0 = global_position
	var so := mgr.slot_offset(_idx)
	var slot := mgr.player.global_position + so
	var dist := _p0.distance_to(slot)
	_p1 = _p0 + _dir * clampf(dist * 0.4, 1.5, 8.0)  # 穿过目标后的余势
	_p1.y = maxf(_p1.y, 0.4)
	var out := Vector3(so.x, 0.0, so.z).normalized()
	_p2_rel = (out * 0.6 + Vector3.UP).normalized() * clampf(dist * 0.3, 1.0, 5.0)  # 从外上方落回
	_dur = clampf(dist / 30.0, 0.35, 0.7)
	trail.emitting = not _cloaked
