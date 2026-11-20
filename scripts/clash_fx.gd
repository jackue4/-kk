extends Node3D
## 飞剑对波的画面：两边成片的飞剑在半空迎头对轰（剑是 air_caster.gd / air_foe.gd 出的，一柄柄放大了往交汇点送、撞碎），
## 撞出一个能量交汇点；谁占上风，谁出剑就更密、把交汇点往对面推。
## 胜负和交汇点的位置都在 air_melee.gd 里算（_tick_clash），这里只管画交汇点和串起剑流的那一缕气：
##   · 气脉（shaders/clash_beam.gdshader）：从各自出手处到交汇点的一缕很细的气劲（不是粗光柱 —— 主体是飞剑），
##     压制方的亮一些，被压的发虚、忽明忽暗；主角每点一下「攻击」，一道亮带顺着它推向交汇点
##   · 交汇光核（clash_core）：两色各占半球，交界随优势偏移；随相持的激烈程度胀缩、脉动
##   · 碰撞盘（clash_disc）×2：一张垂直于光束（能量迎头撞上后向四周溅开），一张朝着镜头当光晕
##   · 一盏跟着交汇点的灯（手机画质档关灯时不点）
##   · finish()：分出胜负的那一下 —— 赢家的光束贯穿过去，输家身上炸开一个迅速胀大的光壳、几圈冲击环、火星和电弧
## air_melee.gd 的 _start_clash 建，_tick_clash 每帧调 update()，结束时调 finish() / abort()。挂在 Vfx.root 下，自己收尾。
## 故意不写 class_name：用 preload 引用。

const BEAM := preload("res://shaders/clash_beam.gdshader")
const CORE := preload("res://shaders/clash_core.gdshader")
const DISC := preload("res://shaders/clash_disc.gdshader")
const Sfx := preload("res://scripts/sfx.gd")

const BEAM_R := 0.085         # 势均力敌时气脉的半径（米）：只是细细一缕，画面的主体是飞剑
const BEAM_A := 0.7           # 气脉的不透明度
## 亮度都压着调：这几层是叠加混合，贴近了看很容易糊成一片白（晃眼），宁可暗一点、看得清能量纹和两边的颜色
const I_BEAM := 1.0
const I_CORE := 1.5
const I_DISC := 1.0
const I_HALO := 0.45

var col_a := Color(0.4, 0.85, 1.0)     # 主角的气劲颜色
var col_b := Color(1.0, 0.3, 0.35)     # 对手的
var size_k := 1.0                      # 交汇点（光核、碰撞盘、光晕）的大小倍率：两边境界档位的平均（Realm.COMBAT 的 clash_core）

var _ba: MeshInstance3D
var _bb: MeshInstance3D
var _core: MeshInstance3D
var _disc: MeshInstance3D
var _halo: MeshInstance3D
var _light: OmniLight3D
var _ma: ShaderMaterial
var _mb: ShaderMaterial
var _mc: ShaderMaterial
var _md: ShaderMaterial
var _mh: ShaderMaterial
var _t := 0.0
var _adv := 0.0               # 平滑后的优势：-1 对手压着 ~ 1 主角压着
var _pulse_a := -1.0          # 亮带在主角那一束上的位置（0~1，< 0 = 没有）
var _pulse_b := -1.0
var _pulse_cd := 0.6
var _fade := 0.0
var _ending := false


func _ready() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0          # +Y（交汇点那头）粗，出手处细
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 20
	cyl.rings = 4
	cyl.cap_top = false
	cyl.cap_bottom = false
	_ma = _mat(BEAM)
	_ma.set_shader_parameter("color", col_a)
	_ma.set_shader_parameter("intensity", I_BEAM)
	_mb = _mat(BEAM)
	_mb.set_shader_parameter("color", col_b)
	_mb.set_shader_parameter("intensity", I_BEAM)
	_ba = _mesh(cyl, _ma)
	_bb = _mesh(cyl, _mb)
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 24
	sp.rings = 12
	_mc = _mat(CORE)
	_mc.set_shader_parameter("intensity", I_CORE)
	_core = _mesh(sp, _mc)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_md = _mat(DISC)
	_md.set_shader_parameter("intensity", I_DISC)
	_disc = _mesh(quad, _md)
	_mh = _mat(DISC)
	_mh.set_shader_parameter("rays", 0.35)
	_mh.set_shader_parameter("intensity", I_HALO)
	_halo = _mesh(quad, _mh)
	for m: ShaderMaterial in [_mc, _md, _mh]:
		m.set_shader_parameter("color_a", col_a)
		m.set_shader_parameter("color_b", col_b)
	_light = OmniLight3D.new()
	_light.omni_range = 16.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.visible = Vfx.lights
	add_child(_light)
	_set_alpha(0.0)


func _mat(sh: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	add_child(mi)
	return mi


func _set_alpha(v: float) -> void:
	for m: ShaderMaterial in [_ma, _mb, _mc, _md, _mh]:
		m.set_shader_parameter("alpha", v)


## 把圆柱摆成 from → to 的一根光束，半径 r
func _place_beam(mi: MeshInstance3D, mat: ShaderMaterial, from: Vector3, to: Vector3, r: float) -> void:
	var d := to - from
	var n := d.length()
	mi.visible = n > 0.3
	if not mi.visible:
		return
	var y := d / n
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x * r, y * n, z * r), from + d * 0.5)
	mat.set_shader_parameter("length_m", n)


## 每帧：a / b 两头的出手处，pt 交汇点，adv 优势（-1~1，正 = 主角占上风），heat 激烈程度 0~1（快分胜负时大）
func update(a: Vector3, b: Vector3, pt: Vector3, adv: float, heat: float, dt: float) -> void:
	if _ending:
		return
	_t = fmod(_t + dt, 512.0)
	_fade = move_toward(_fade, 1.0, dt * 5.0)
	_adv = lerpf(_adv, clampf(adv, -1.0, 1.0), 1.0 - exp(-6.0 * dt))
	_set_alpha(_fade)
	_ma.set_shader_parameter("alpha", _fade * BEAM_A)
	_mb.set_shader_parameter("alpha", _fade * BEAM_A)
	# 气脉：压制方亮一些，被压的发虚
	_place_beam(_ba, _ma, a, pt, BEAM_R * (1.0 + 0.5 * _adv))
	_place_beam(_bb, _mb, b, pt, BEAM_R * (1.0 - 0.5 * _adv))
	_ma.set_shader_parameter("flow", _t)
	_mb.set_shader_parameter("flow", _t + 37.0)
	_ma.set_shader_parameter("power", 1.0 + 0.6 * _adv)
	_mb.set_shader_parameter("power", 1.0 - 0.6 * _adv)
	# 亮带：主角的跟着连点走（tap），对手的隔一阵来一下
	if _pulse_a >= 0.0:
		_pulse_a += dt / 0.16
		if _pulse_a > 1.0:
			_pulse_a = -1.0
	_pulse_cd -= dt
	if _pulse_cd <= 0.0:
		_pulse_cd = randf_range(0.25, 0.7)
		_pulse_b = 0.0
	if _pulse_b >= 0.0:
		_pulse_b += dt / 0.2
		if _pulse_b > 1.0:
			_pulse_b = -1.0
	_ma.set_shader_parameter("pulse_pos", _pulse_a)
	_mb.set_shader_parameter("pulse_pos", _pulse_b)
	# 交汇点：光核 + 碰撞盘（垂直于光束）+ 朝镜头的光晕
	var axis := b - a
	axis = axis.normalized() if axis.length_squared() > 1e-4 else Vector3.FORWARD
	var x := axis.cross(Vector3.UP)
	if x.length_squared() < 1e-4:
		x = axis.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(axis)
	var beat := 1.0 + 0.09 * sin(_t * 19.0) + 0.05 * sin(_t * 31.0)
	var mixk := 0.5 + 0.5 * _adv
	_core.global_transform = Transform3D(Basis(x, axis, z).scaled(Vector3.ONE * (0.75 + 0.45 * heat) * beat * size_k), pt)
	_mc.set_shader_parameter("spin", _t)
	_mc.set_shader_parameter("mix_k", mixk)
	_disc.global_transform = Transform3D(Basis(x, z, axis).scaled(Vector3.ONE * (3.0 + 1.4 * heat) * beat * size_k), pt)
	_md.set_shader_parameter("flow", _t)
	_md.set_shader_parameter("mix_k", mixk)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var look := cam.global_position - pt
		look = look.normalized() if look.length_squared() > 1e-4 else Vector3.BACK
		var hx := Vector3.UP.cross(look)
		hx = hx.normalized() if hx.length_squared() > 1e-4 else Vector3.RIGHT
		_halo.global_transform = Transform3D(Basis(hx, look.cross(hx), look).scaled(Vector3.ONE * (3.2 + 1.6 * heat) * beat * size_k), pt)
	_mh.set_shader_parameter("flow", _t * 0.6 + 11.0)
	_mh.set_shader_parameter("mix_k", mixk)
	_light.global_position = pt
	_light.light_color = col_b.lerp(col_a, mixk).lerp(Color.WHITE, 0.35)
	_light.light_energy = (1.6 + 1.4 * heat) * beat * _fade


## 主角点了一下「攻击」：一道亮带从出手处推向交汇点
func tap() -> void:
	_pulse_a = 0.0


## 分出胜负。from 赢家的出手处，at 输家的位置（终爆炸在这儿），win = 主角赢了。之后自己淡出、自己释放
func finish(from: Vector3, at: Vector3, win: bool) -> void:
	if _ending:
		return
	_ending = true
	var wc := col_a if win else col_b
	var wb := _ba if win else _bb
	var wm := _ma if win else _mb
	var lb := _bb if win else _ba
	# 赢家的光束贯穿过去，输家的那束当场断掉
	lb.visible = false
	_place_beam(wb, wm, from, at, BEAM_R * 3.0)
	wm.set_shader_parameter("power", 1.8)
	wm.set_shader_parameter("pulse_pos", 0.5)
	for mi: MeshInstance3D in [_core, _disc, _halo]:
		mi.visible = false
	# 终爆：一个迅速胀大的光壳 + 一团白热的核 + 朝镜头的一大片光晕
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 28
	sp.rings = 14
	var ms := _mat(CORE)
	ms.set_shader_parameter("color_a", wc)
	ms.set_shader_parameter("color_b", Color.WHITE.lerp(wc, 0.5))
	ms.set_shader_parameter("intensity", 1.3)
	ms.set_shader_parameter("shell", 0.4)
	var boom := _mesh(sp, ms)
	boom.global_position = at
	boom.scale = Vector3.ONE * 1.4
	var mk := _mat(CORE)
	mk.set_shader_parameter("color_a", Color.WHITE.lerp(wc, 0.25))
	mk.set_shader_parameter("color_b", Color.WHITE.lerp(wc, 0.25))
	mk.set_shader_parameter("intensity", 1.3)
	var kern := _mesh(sp, mk)
	kern.global_position = at
	kern.scale = Vector3.ONE * 0.8
	_mh.set_shader_parameter("color_a", wc)
	_mh.set_shader_parameter("color_b", wc)
	_mh.set_shader_parameter("rays", 1.0)
	_mh.set_shader_parameter("intensity", 0.7)
	_halo.visible = true
	var cam := get_viewport().get_camera_3d()
	var look := (cam.global_position - at).normalized() if cam != null else Vector3.BACK
	var hx := Vector3.UP.cross(look)
	hx = hx.normalized() if hx.length_squared() > 1e-4 else Vector3.RIGHT
	_halo.global_transform = Transform3D(Basis(hx, look.cross(hx), look).scaled(Vector3.ONE * 4.0), at)
	_light.global_position = at
	_light.light_color = Color.WHITE.lerp(wc, 0.5)
	_light.light_energy = 5.0
	_light.omni_range = 26.0
	var dir := at - from
	dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.FORWARD
	var hot := Color.WHITE.lerp(wc, 0.4)
	Vfx.shockwave(at, dir, hot, 3.6)
	Vfx.shockwave(at, Vector3.UP, wc, 3.0)
	Vfx.line_sparks(at, dir, hot, 14, 30.0, 170.0, 0.6)
	Vfx.line_sparks(at, -dir + Vector3.UP * 0.4, wc, 10, 22.0, 170.0, 0.5)
	for i in 6:
		var od := Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 1.0), randf_range(-1.0, 1.0)).normalized()
		Vfx.lightning(at, at + od * randf_range(4.0, 8.0), hot, 0.09, 0.2, 5)
	Vfx.quake(at, 5.0)
	Sfx.play("slam", 0.0, 0.7)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(boom, "scale", Vector3.ONE * 11.0, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: ms.set_shader_parameter("shell", v), 0.4, 1.0, 0.16)
	tw.tween_method(func(v: float) -> void: ms.set_shader_parameter("alpha", v), 1.0, 0.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_property(kern, "scale", Vector3.ONE * 3.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mk.set_shader_parameter("alpha", v), 1.0, 0.0, 0.24)
	tw.tween_property(_halo, "scale", Vector3.ONE * 9.0, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _mh.set_shader_parameter("alpha", v), 1.0, 0.0, 0.45)
	tw.tween_method(func(v: float) -> void: wm.set_shader_parameter("alpha", v), 1.0, 0.0, 0.32)
	tw.tween_property(_light, "light_energy", 0.0, 0.5)
	# 第二、三圈冲击环晚一点出来
	tw.tween_callback(func() -> void: Vfx.shockwave(at, dir, wc, 4.6)).set_delay(0.09)
	tw.tween_callback(func() -> void: Vfx.shockwave(at, dir.cross(Vector3.UP), hot, 3.2)).set_delay(0.18)
	tw.chain().tween_interval(0.3)
	tw.chain().tween_callback(queue_free)


## 相持被别的事打断（落地、被拉走……）：很快淡掉
func abort() -> void:
	if _ending:
		return
	_ending = true
	var tw := create_tween()
	tw.tween_method(_set_alpha, _fade, 0.0, 0.15)
	tw.parallel().tween_property(_light, "light_energy", 0.0, 0.15)
	tw.tween_callback(queue_free)
