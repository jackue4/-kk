extends RefCounted
## 攒气 / 觉醒的灵气波动（2026-11-25）。用户原话：「玩家攒气时……有一层从外到内的空间波动吸附灵气到玩家身上的感觉，
## 觉醒后，不要现在的光圈特效，太丑了，改为灵气爆开，由玩家身体内向外爆开灵气波动」。
## 第一版照参考视频加了带旋的气丝圆片、往里扎的细线、漫天细芒 —— 用户看了说「效果不对，你复用空间波动那套其实就够了，
## 不需要这么多粒子特效，由外朝内的空间波动效果」。所以这里**只用空间波动**（aura_warp.gdshader，对拳 / 觉醒身周 / Vfx.space_ring 那一种），别再往上加粒子：
##   gather_pulse  攒气的一拍：一圈波动从外面收到身上（波前倒着放，圈里那几道细波也往里走）
##   burst         觉醒爆开：一个气罩从身体里鼓出来胀开（隔着它看东西是扭的）+ 两圈往外荡的空间波动 + 身上一白
## 不放 static var（缓存挂 Vfx.root 的 meta）。故意不写 class_name。

const BUBBLE := preload("res://shaders/qi_bubble.gdshader")
const WAVE := preload("res://shaders/space_wave.gdshader")


static func ok() -> bool:
	return Vfx.root != null and is_instance_valid(Vfx.root) and Vfx.root.is_inside_tree() and Vfx.mute < 1


static func _quad() -> QuadMesh:
	if Vfx.root.has_meta("qifx_quad"):
		return Vfx.root.get_meta("qifx_quad")
	var q := QuadMesh.new()
	Vfx.root.set_meta("qifx_quad", q)
	return q


static func _sphere() -> SphereMesh:
	if Vfx.root.has_meta("qifx_sphere"):
		return Vfx.root.get_meta("qifx_sphere")
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 28
	s.rings = 14
	Vfx.root.set_meta("qifx_sphere", s)
	return s


## 铺在世界里的一圈空间波动（shaders/space_wave.gdshader）：以 pos 为中心水平摆着的一张圆片，半径 radius 米。
## inward = 波前从外沿收到中心（攒气），否则从中心荡到外沿（爆开）。dur 秒走完
static func wave(pos: Vector3, radius: float, col: Color, dur: float, inward: bool, strength := 0.06, delay := 0.0, calm := 0.55) -> void:
	var m := ShaderMaterial.new()
	m.shader = WAVE
	m.render_priority = -90
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("power", 0.0)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("calm", calm)
	m.set_shader_parameter("flow_dir", -1.0 if inward else 1.0)
	m.set_shader_parameter("pulse", 0.92 if inward else 0.06)
	m.set_shader_parameter("front_k", 1.0)      # 没设过的参数读出来是空的，后面的渐变会接不上
	var mi := MeshInstance3D.new()
	mi.mesh = _quad()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	# 面片的法线（本地 +Z）朝天：平躺在世界里
	mi.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP).rotated(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * radius * 2.0), pos)
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(m, "shader_parameter/power", 1.0, dur * 0.22)
	if inward:
		tw.parallel().tween_property(m, "shader_parameter/pulse", 0.06, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		tw.parallel().tween_property(m, "shader_parameter/pulse", 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(m, "shader_parameter/front_k", 0.0, dur * 0.5).set_delay(dur * 0.5)
	tw.tween_property(m, "shader_parameter/power", 0.0, dur * 0.25)
	tw.tween_callback(mi.queue_free)


## 攒气的一拍：人周围一圈空间波动从 radius 米外收到身上（dur 秒）。脚下一层、（桌面档）腰上再一层小一点的：两层错开，看得出是围着人的一团，不是一张片
static func gather_pulse(pos: Vector3, col: Color, radius := 7.0, dur := 0.7) -> void:
	if not ok():
		return
	wave(pos - Vector3(0.0, 0.85, 0.0), radius, col, dur, true, 0.07)
	if not Vfx.lite:
		wave(pos + Vector3(0.0, 0.35, 0.0), radius * 0.66, col, dur * 0.85, true, 0.05, dur * 0.25)


## 觉醒爆开：身上一白 → 气罩从身体里鼓出来胀开 → 脚下、腰上两层空间波动一前一后往外荡
static func burst(pos: Vector3, col: Color, power := 1.0) -> void:
	if not ok():
		return
	var qc := Color.from_hsv(col.h, clampf(col.s * 0.75, 0.15, 0.7), 1.0)
	var m := ShaderMaterial.new()
	m.shader = BUBBLE
	m.render_priority = -80
	m.set_shader_parameter("tint", qc)
	m.set_shader_parameter("age", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.6
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 11.0 * power, 0.32).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "shader_parameter/age", 1.0, 0.36).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)
	var star := Vfx._sprite(pos, Color.WHITE, 0, 1.4)
	Vfx._fade(star, Vector3.ONE * 6.0 * power, 0.2)
	Vfx.flash_light(pos, qc, 3.0 * power, 12.0, 0.3)
	wave(pos - Vector3(0.0, 0.85, 0.0), 13.0 * power, qc, 0.8, false, 0.1, 0.0, 0.7)
	wave(pos + Vector3(0.0, 0.3, 0.0), 9.0 * power, qc, 0.7, false, 0.08, 0.12, 0.7)


## 载入时预热要摆出来的节点（气罩、世界里的波动片两种材质）
static func warm_nodes() -> Array:
	var out: Array = []
	if Vfx.root == null or not is_instance_valid(Vfx.root):
		return out
	var b := MeshInstance3D.new()
	b.mesh = _sphere()
	var mb := ShaderMaterial.new()
	mb.shader = BUBBLE
	mb.set_shader_parameter("age", 0.5)
	b.material_override = mb
	out.append(b)
	var w := MeshInstance3D.new()
	w.mesh = _quad()
	var mw := ShaderMaterial.new()
	mw.shader = WAVE
	mw.set_shader_parameter("power", 0.05)
	w.material_override = mw
	out.append(w)
	return out
