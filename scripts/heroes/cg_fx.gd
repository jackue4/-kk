extends RefCounted
## 苍鸿（剑修）的刀光画面（2026-11-25 第三轮）。用户原话：「剑修的特效太弱了，剑气都看不清，觉醒后跟普通技能的特效招式也没拉开差异……
## 之前的空间波动等效果就挺好的，要复用这些……刀光的特效一定要帅，发射的路上带有空间波动，觉醒后的表现也要做差异化」。
## 这里只管画（都是静态函数，本机和别人机器上都调它）：
##   slash    一道新月刀光（挥剑那一下）：三层色阶 + 勾边（shaders/blade_wave.gdshader），亮地面上也看得清
##   needles  针芒迸射（命中点 / 刀光炸开）：几十根细长的针一次画完（shaders/needle_burst.gdshader）
##   cut      贯穿一点的长斩线：深色衬底 + 刀色 + 白芯三笔
##   hit_fx / wave_hit / scar  几样拼起来的成套画面
## 平时是青白色；觉醒「赤霄」换成赤红 + 墨黑（pal()），针更多更长、斩线更长，另带一道合不上的黑缝 —— 一眼分得出是不是觉醒。
## 网格缓存挂在 Vfx.root 的 meta 上（技能脚本这一路不放 static var，见 kit_canghong2.gd 的说明）。故意不写 class_name。

const WAVE := preload("res://shaders/blade_wave.gdshader")
const NEEDLE := preload("res://shaders/needle_burst.gdshader")
const HeroFx := preload("res://scripts/hero_fx.gd")
const SWAVE := preload("res://shaders/space_wave.gdshader")
const TEAR := preload("res://shaders/air_tear.gdshader")

const CRIMSON := Color(1.0, 0.13, 0.1)
const VOID := Color(0.03, 0.01, 0.04)


## 这一下用哪套颜色：[刃线, 刀身, 暗部]
static func pal(col: Color, aw: bool) -> Array:
	if aw:
		return [Color(1.0, 0.9, 0.82), CRIMSON, Color(0.2, 0.0, 0.03)]
	var body := Color.from_hsv(col.h, clampf(col.s * 1.5 + 0.2, 0.0, 0.85), 1.0)
	return [Color.WHITE, body, Color.from_hsv(fmod(col.h + 0.04, 1.0), 0.85, 0.34)]


## 觉醒时特效的主色
static func main_col(col: Color, aw: bool) -> Color:
	return CRIMSON if aw else col


# ---------- 新月刀光 ----------

## 新月网格：躺在 XZ 平面上、朝 -Z 鼓出去，从 -X 一侧扫到 +X 一侧。UV.x 沿弧，UV.y 0 内缘 → 1 外缘。
## kind 0 = 挥剑的弧（刀尖那头厚）· 1 = 飞出去的刀光（两头对称，更厚）
## 除了平躺的那一片，沿外缘还立着一道「光幕」（上下各一截，中线最亮、往上下撕碎）：平躺的一片从侧面 / 正后方看过去只剩一条线
## （镜头在人身后，横斩的刀光正好是侧对着的 —— 第一版就是这样「看不清」），有了立着的这一道，哪个角度看都有厚度
static func crescent(span: int, kind: int) -> ArrayMesh:
	var key := "cgfx_cr2_%d_%d" % [span, kind]
	if Vfx.root.has_meta(key):
		return Vfx.root.get_meta(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 32 if span > 200 else 20
	var half := deg_to_rad(float(span)) * 0.5
	var rows: Array = []
	for i in seg + 1:
		var u := float(i) / float(seg)
		var a := lerpf(-half, half, u)
		var w := 0.46 * pow(sin(PI * u), 0.6) * (0.45 + 0.55 * u) if kind == 0 else 0.6 * pow(sin(PI * u), 0.75)
		var h := w * (0.42 if kind == 0 else 0.5)
		var dirv := Vector3(sin(a), 0.0, -cos(a))
		rows.append([dirv, dirv * (1.0 - maxf(w, 0.01)), u, dirv * (1.0 - w * 0.12) + Vector3.UP * h, dirv * (1.0 - w * 0.12) - Vector3.UP * h])
	for i in seg:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var u0 := float(r0[2])
		var u1 := float(r1[2])
		var quad: Array = [[r0[0], Vector2(u0, 1.0)], [r1[0], Vector2(u1, 1.0)], [r1[1], Vector2(u1, 0.0)],
				[r0[0], Vector2(u0, 1.0)], [r1[1], Vector2(u1, 0.0)], [r0[1], Vector2(u0, 0.0)],
				# 立着的光幕：外缘那条线是 0.88（刃线），往上 / 往下各淡到 0.1
				[r0[0], Vector2(u0, 0.88)], [r1[0], Vector2(u1, 0.88)], [r1[3], Vector2(u1, 0.1)],
				[r0[0], Vector2(u0, 0.88)], [r1[3], Vector2(u1, 0.1)], [r0[3], Vector2(u0, 0.1)],
				[r0[0], Vector2(u0, 0.88)], [r1[4], Vector2(u1, 0.1)], [r1[0], Vector2(u1, 0.88)],
				[r0[0], Vector2(u0, 0.88)], [r0[4], Vector2(u0, 0.1)], [r1[4], Vector2(u1, 0.1)]]
		for q: Array in quad:
			st.set_normal(Vector3.UP)
			st.set_uv(q[1])
			st.add_vertex(q[0])
	var m := st.commit()
	Vfx.root.set_meta(key, m)
	return m


static func wave_mat(p: Array, ink := 0.6, flow := 3.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WAVE
	m.set_shader_parameter("col_edge", p[0])
	m.set_shader_parameter("col_body", p[1])
	m.set_shader_parameter("col_dark", p[2])
	m.set_shader_parameter("seed", randf() * 10.0)
	m.set_shader_parameter("ink", ink)
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("age", 0.0)
	m.set_shader_parameter("alpha", 1.0)
	return m


## 朝 fwd 鼓出去、沿 swing 扫过的那个朝向（网格的 +X = 挥剑方向、-Z = 鼓出去的方向）
static func arc_basis(fwd: Vector3, swing: Vector3) -> Basis:
	var z := -(fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD)
	var x := swing - z * swing.dot(z)
	if x.length_squared() < 1e-5:
		x = Vector3.UP.cross(z)
		if x.length_squared() < 1e-5:
			x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x).normalized(), z)


## 一道刀光：圆心 center，朝 fwd 鼓出去，沿 swing 扫过，半径 radius。顺着挥剑方向转过一小截、略放大，内缘先碎、随即散掉
static func slash(center: Vector3, fwd: Vector3, swing: Vector3, radius: float, span: int, col: Color, aw: bool, dur := 0.26) -> void:
	if not HeroFx.ok() or Vfx.mute >= 1:
		return
	var b := arc_basis(fwd, swing)
	var y := b.y
	var m := wave_mat(pal(col, aw))
	var mi := MeshInstance3D.new()
	mi.mesh = crescent(span, 0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	mi.global_transform = Transform3D(b.rotated(y, 0.5).scaled(Vector3.ONE * radius * 0.84), center)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_transform", Transform3D(b.rotated(y, -0.16).scaled(Vector3.ONE * radius * 1.1), center), dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "shader_parameter/age", 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## 一道往前飞一小段的刀光（觉醒平砍的「剑气延伸」）：从 center 朝 fwd 飞 dist 米，边飞边散
static func fly_arc(center: Vector3, fwd: Vector3, swing: Vector3, radius: float, span: int, col: Color, aw: bool, dist: float, dur := 0.22) -> void:
	if not HeroFx.ok() or Vfx.mute >= 1:
		return
	var b := arc_basis(fwd, swing)
	var m := wave_mat(pal(col, aw), 0.6, 5.0)
	var mi := MeshInstance3D.new()
	mi.mesh = crescent(span, 1)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	var f := fwd.normalized()
	mi.global_transform = Transform3D(b.scaled(Vector3.ONE * radius * 0.7), center)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_transform", Transform3D(b.scaled(Vector3.ONE * radius * 1.15), center + f * dist), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "shader_parameter/age", 1.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


# ---------- 针芒迸射 ----------

## 针的网格。kind：0 扇面（绕 +Y 约 60 度的锥）· 1 四面八方 · 2 贴着 XZ 平面的一圈 · 3 窄锥（约 22 度，朝 +Y）
static func needle_mesh(kind: int, n: int) -> ArrayMesh:
	var key := "cgfx_nd_%d_%d" % [kind, n]
	if Vfx.root.has_meta(key):
		return Vfx.root.get_meta(key)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + kind * 131 + n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var d := Vector3.UP
		match kind:
			0:
				d = Vector3.UP.rotated(Vector3.RIGHT, rng.randf_range(0.05, 1.05)).rotated(Vector3.UP, rng.randf() * TAU)
			1:
				d = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
				d = d.normalized() if d.length_squared() > 0.01 else Vector3.UP
			2:
				var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
				d = Vector3(cos(a), rng.randf_range(-0.12, 0.12), sin(a)).normalized()
			_:
				d = Vector3.UP.rotated(Vector3.RIGHT, rng.randf_range(0.0, 0.38)).rotated(Vector3.UP, rng.randf() * TAU)
		var dark := i % 4 == 3
		var c := Color(rng.randf_range(0.35, 1.0) * (0.8 if dark else 1.0), rng.randf(), 1.0 if dark else 0.0, 1.0)
		for q: Vector2 in [Vector2(0, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0, -1), Vector2(1, 1), Vector2(0, 1)]:
			st.set_normal(d)
			st.set_uv(q)
			st.set_color(c)
			st.add_vertex(Vector3.ZERO)
	var m := st.commit()
	Vfx.root.set_meta(key, m)
	return m


## 从 pos 往外窜一把针：axis = 锥 / 圈的轴，reach = 最长的针多长（米）
static func needles(pos: Vector3, axis: Vector3, kind: int, col: Color, aw: bool, reach := 3.0, dur := 0.34, width := 0.07, n := 0) -> void:
	if not HeroFx.ok() or Vfx.mute >= 1:
		return
	if n <= 0:
		n = 24 if aw else 16
	if Vfx.lite:
		n = maxi(n * 2 / 3, 8)
	var p := pal(col, aw)
	var m := ShaderMaterial.new()
	m.shader = NEEDLE
	m.set_shader_parameter("col_hot", p[0])
	m.set_shader_parameter("col_body", p[1])
	m.set_shader_parameter("col_dark", p[2])
	m.set_shader_parameter("reach", reach)
	m.set_shader_parameter("width", width * (1.25 if aw else 1.0))
	m.set_shader_parameter("age", 0.0)
	m.set_shader_parameter("alpha", 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = needle_mesh(kind, n)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = reach + 1.0
	Vfx.root.add_child(mi)
	var y := axis.normalized() if axis.length_squared() > 1e-6 else Vector3.UP
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, randf() * TAU), pos)
	var tw := mi.create_tween()
	tw.tween_property(m, "shader_parameter/age", 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)


# ---------- 斩线 ----------

## 贯穿 pos 的一道长斩线：深色衬底（亮背景上靠它）+ 刀色 + 白芯。length = 全长（米）
static func cut(pos: Vector3, dir: Vector3, length: float, col: Color, aw: bool, hold := 0.05, k := 1.0) -> void:
	if not HeroFx.ok() or Vfx.mute >= 1:
		return
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.RIGHT
	var a := pos - d * length * 0.5
	var b := pos + d * length * 0.5
	var p := pal(col, aw)
	Vfx._stroke(a, b, p[2], 0.5 * k, hold + 0.04, 0.2)
	Vfx._stroke(a, b, p[1], 0.26 * k, hold, 0.22)
	Vfx._stroke(a, b, p[0], 0.09 * k, hold + 0.02, 0.16)


## 剑砍中人的那一下（平砍 / 技能命中都走它）：顺着挥剑方向一道贯穿的斩线 + 逆着刀路迸出来的一把针。
## heavy = 重手 / 收尾：再来一道交叉的、针多一倍、荡开一圈空间波动
static func hit_fx(pos: Vector3, swing: Vector3, fwd: Vector3, col: Color, aw: bool, heavy := false) -> void:
	if not HeroFx.ok():
		return
	var s := swing.normalized() if swing.length_squared() > 1e-6 else Vector3.RIGHT
	var l := (5.2 if aw else 3.8) * (1.3 if heavy else 1.0)
	cut(pos, s, l, col, aw, 0.05, 1.7 if heavy else 1.3)
	needles(pos, (s + fwd * 0.5).normalized(), 3, col, aw, 2.6 if aw else 2.0, 0.3)
	if aw and not Vfx.lite:
		needles(pos, -s, 3, col, aw, 1.8, 0.26, 0.06, 12)
	if heavy:
		var up := s.cross(fwd).normalized() if absf(s.dot(fwd)) < 0.95 else Vector3.UP
		cut(pos, (s * 0.35 + up).normalized(), l * 0.8, col, aw, 0.03, 0.9)
		needles(pos, fwd, 1, col, aw, 3.2 if aw else 2.4, 0.36)
		Vfx.space_ring(pos, 2.0 if aw else 1.6, main_col(col, aw), 0.4, 0.06)


## 飞行刀光打中 / 飞到头炸开：交叉的斩线 + 往上、往前窜的两把针 + 一圈空间波动；big（收尾那一下）再裂几道空间裂缝
static func wave_hit(pos: Vector3, dir: Vector3, swing: Vector3, col: Color, aw: bool, big: bool) -> void:
	if not HeroFx.ok():
		return
	var mc := main_col(col, aw)
	var s := swing.normalized() if swing.length_squared() > 1e-6 else Vector3.RIGHT
	var k := (1.4 if big else 1.0) * (1.25 if aw else 1.0)
	cut(pos, s, 6.5 * k, col, aw, 0.08, 1.3 * k)
	needles(pos, (Vector3.UP * 0.8 - dir * 0.45).normalized(), 0, col, aw, 4.4 * k, 0.42, 0.12)
	needles(pos, dir, 3, col, aw, 5.0 * k, 0.34, 0.1, 14)
	var star := Vfx._sprite(pos, pal(col, aw)[0], 0, 1.2 * k)
	Vfx._fade(star, Vector3.ONE * 4.5 * k, 0.2)
	Vfx.space_ring(pos, 2.2 * k, mc, 0.45, 0.07)
	Vfx.flash_light(pos, mc, 1.6 * k, 8.0, 0.2)
	if big:
		var other := s - 2.0 * s.dot(Vector3.UP) * Vector3.UP
		cut(pos, other if other.length_squared() > 0.01 else Vector3.UP, 5.0 * k, col, aw, 0.09, k)
		needles(pos, Vector3.UP, 1, col, aw, 4.0 * k, 0.45, 0.08)
		Vfx.shockwave(pos, dir, Color.WHITE.lerp(mc, 0.5), 1.6 * k)
		if not Vfx.lite:
			Vfx.space_crack(pos, mc, 1.5 * k, 4 if aw else 3, 0.45, 0.35)


## 刀光飞过的那条线上留下的一道痕：平时 = 一线白光一闪；觉醒 = 一道合不上的黑缝（空间被切开），镶着红边，停一拍才合
static func scar(from: Vector3, to: Vector3, col: Color, aw: bool) -> void:
	if not HeroFx.ok() or from.distance_to(to) < 1.0:
		return
	var p := pal(col, aw)
	if aw:
		Vfx._stroke(from, to, VOID, 0.34, 0.2, 0.26)
		Vfx._stroke(from, to, VOID, 0.2, 0.22, 0.26)
		Vfx._stroke(from, to, p[1], 0.07, 0.16, 0.3, true)
	else:
		Vfx._stroke(from, to, p[1], 0.2, 0.03, 0.24)
		Vfx._stroke(from, to, p[0], 0.07, 0.05, 0.2)


## 载入时预热要摆出来的节点（两种新材质各一个）
static func warm_nodes() -> Array:
	var out: Array = []
	if not HeroFx.ok():
		return out
	for aw: bool in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = crescent(150, 1 if aw else 0)
		mi.material_override = wave_mat(pal(Color(0.45, 0.85, 1.0), aw))
		mi.scale = Vector3.ONE * 0.3
		out.append(mi)
	var nd := MeshInstance3D.new()
	nd.mesh = needle_mesh(0, 16)
	var m := ShaderMaterial.new()
	m.shader = NEEDLE
	m.set_shader_parameter("age", 0.5)
	m.set_shader_parameter("reach", 0.3)
	nd.material_override = m
	out.append(nd)
	var tq := MeshInstance3D.new()
	tq.mesh = _fx_quad()
	var tm := ShaderMaterial.new()
	tm.shader = TEAR
	tm.set_shader_parameter("age", 0.3)
	tq.material_override = tm
	out.append(tq)
	return out


# ---------- 破空（蓄力放出去的刀光一路把空气撕开）----------

## 一圈立在世界里的空间波动：圆片的法线 = normal，波前从中心荡到外沿（shaders/space_wave.gdshader，和攒气 / 觉醒用的是同一个）
static func ring_warp(pos: Vector3, normal: Vector3, radius: float, col: Color, dur := 0.45, strength := 0.07) -> void:
	if not HeroFx.ok() or Vfx.mute >= 1:
		return
	var m := ShaderMaterial.new()
	m.shader = SWAVE
	m.render_priority = -90
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("power", 1.0)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("calm", 0.5)
	m.set_shader_parameter("flow_dir", 1.0)
	m.set_shader_parameter("pulse", 0.15)
	m.set_shader_parameter("front_k", 1.0)
	m.set_shader_parameter("hole", 0.02)
	var mi := MeshInstance3D.new()
	mi.mesh = _fx_quad()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	var z := normal.normalized() if normal.length_squared() > 1e-6 else Vector3.FORWARD
	var ref := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(z).normalized()
	mi.global_transform = Transform3D(Basis(x, z.cross(x), z).scaled(Vector3.ONE * radius * 2.0), pos)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "shader_parameter/pulse", 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "shader_parameter/power", 0.0, dur * 0.45).set_delay(dur * 0.55)
	tw.chain().tween_callback(mi.queue_free)


static func _fx_quad() -> QuadMesh:
	if Vfx.root.has_meta("cgfx_quad"):
		return Vfx.root.get_meta("cgfx_quad")
	var q := QuadMesh.new()
	Vfx.root.set_meta("cgfx_quad", q)
	return q


## 一片破空的气浪圈（shaders/air_tear.gdshader：五圈断续的墨黑 / 暗红弧线），垂直于 dir，从半径 r0 甩到 r1、淡掉
static func tear(pos: Vector3, dir: Vector3, r0: float, r1: float, dur: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = TEAR
	m.set_shader_parameter("age", 0.0)
	m.set_shader_parameter("seed", randf() * 20.0)
	m.set_shader_parameter("alpha", 0.92)
	var mi := MeshInstance3D.new()
	mi.mesh = _fx_quad()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx.root.add_child(mi)
	# 歪一点：不是整整齐齐立着的靶子
	var z := (dir.normalized() + Vector3(randf_range(-0.16, 0.16), randf_range(-0.16, 0.16), randf_range(-0.16, 0.16))).normalized()
	var ref := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(z).normalized()
	var b := Basis(x, z.cross(x), z).rotated(z, randf() * TAU)
	mi.global_transform = Transform3D(b.scaled(Vector3.ONE * r0 * 2.0), pos)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_transform", Transform3D(b.rotated(z, randf_range(-0.5, 0.5)).scaled(Vector3.ONE * r1 * 2.0), pos), dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "shader_parameter/age", 1.0, dur)
	tw.chain().tween_callback(mi.queue_free)


## 血刃飞过的这一处：空气被劈开 —— 一圈立着的空间波动往外荡、一两片墨黑夹暗红的气浪圈甩出去、一把白红的细芒顺着圈面迸开；
## 平时的光刀只要那圈空间波动（rich = false）
static func air_split(pos: Vector3, dir: Vector3, radius: float, col: Color, aw: bool, rich: bool) -> void:
	if not HeroFx.ok() or Vfx.mute >= 1:
		return
	var mc := main_col(col, aw)
	ring_warp(pos, dir, radius * (2.2 if rich else 1.6), mc, 0.5 if rich else 0.4, 0.09 if rich else 0.06)
	if not rich:
		return
	tear(pos, dir, radius * 1.2, radius * 3.0, 0.55)
	if not Vfx.lite:
		tear(pos - dir * 0.8, dir, radius * 0.9, radius * 2.1, 0.42)
	needles(pos, dir, 2, col, true, radius * 1.8, 0.42, 0.07, 18)
