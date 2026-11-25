extends Node3D
## 境界光环（2026-11-23 第二版）：觉醒时在修士背后展开的一轮法相光环，每个境界一套，照用户的八张效果图搭的
## （炼气 ~ 大乘，原图在 _tasks/realm_halo/ref/）。
##
## 第一版是把效果图里的光环抠成一张图、常驻贴在人身后，用户看了的原话：「后面的光环做的太丑太差了，换一种实现方式，
## 用特效去还原，然后光环要离玩家远一点，跟随玩家旋转，只有觉醒的时候，才需要触发光环」。所以现在：
##   · 不贴图，全是特效：环带、莲瓣、羽翼、符文圈、星门、宝石……都是着色器按形状现画的（放多大都清楚），
##     各层有前后、各转各的，环上有流光在跑，花瓣和羽毛会摆，星点会闪。
##     三种图元：环形网格（realm_halo_ring.gdshader）、一个 MultiMesh 里的许多「片」（realm_halo_blade.gdshader）、
##     方片上的圆面（realm_halo_disc.gdshader：光核 / 星门 / 元婴）。
##   · 立在人背后一米多的地方（PLACE 的 dist），跟着人的朝向转，不是贴着镜头的平面图。
##   · 只在觉醒期间有：由 awaken_fx.gd 建、摆位、收场（本机主角和联机里别人的觉醒都走它）。
##     展开时从环顶往两边画出来、花瓣羽毛一片片长出来；觉醒结束淡掉。
## 镜头在人身后时光环夹在镜头和人中间：着色器里把它的深度沿视线推到人的后面（halo_clip，屏幕上的位置大小不变），
## 人照常画在它前面，就是原画那种「人在前、环在后」。各层另有个 rear 系数，从背面看时可以再压淡一点（现在基本不用压）。
## 坐标：光环自己的 x 向人的右手、y 向上、z 向人的背后；片 / 环的角度都是「从正上方起、顺时针」的度数。
## 故意不写 class_name：用 preload 引用。

const SH_RING := preload("res://shaders/realm_halo_ring.gdshader")
const SH_DISC := preload("res://shaders/realm_halo_disc.gdshader")
const SH_BLADE := preload("res://shaders/realm_halo_blade.gdshader")

## 每档摆在哪：cy 光环中心离脚底多高（米）、dist 离人背后多远
const PLACE: Array = [
	{"cy": 1.45, "dist": 1.3},       # 炼气
	{"cy": 1.55, "dist": 1.4},       # 筑基
	{"cy": 1.75, "dist": 1.5},       # 结丹
	{"cy": 1.95, "dist": 1.6},       # 元婴
	{"cy": 1.95, "dist": 1.65},      # 化神
	{"cy": 1.9, "dist": 1.7},        # 炼虚
	{"cy": 2.05, "dist": 1.8},       # 合体
	{"cy": 2.2, "dist": 1.9},        # 大乘
]
const UNFOLD := 0.9           # 展开用多少秒
## 镜头在人身后时，光环的深度推到人身后（离镜头更远的那一侧）这么多米：人自己、贴身缠斗的对手都画在光环前面，不被它盖住
const REAR_GAP := 2.4

const WHITE := Color(1.0, 1.0, 1.0)
const GOLD := Color(1.0, 0.82, 0.42)
const GOLD_HI := Color(1.0, 0.93, 0.68)

static var enabled := not OS.get_cmdline_user_args().has("--no-halo")
static var _rings := {}       # 环形网格缓存
static var _force := -2       # 调试开关 --halo-tier=N：不管什么境界一律用第 N 档（0 起），看各档在游戏里的样子用

var tier := -1
var _mats: Array[ShaderMaterial] = []
var _spin: Array = []         # [节点, 弧度 / 秒]
var _blades: Array = []       # 正在攒的片
var _reveal := 1.0
var _power := -1.0
var _n := 0
var _hue := -1.0            # 英雄色的色相（-1 = 不换色）


## 第 idx 个境界的光环（还没进树；关掉了返回 null）
## tint（a > 0 才算）：2026-11-25 英雄档 —— 整个光环的金 / 橙换成这位英雄的颜色（色相挪过去，明暗和浓淡不动）。不给 = 这一档原来的配色
static func make(idx: int, tint := Color(0, 0, 0, 0)) -> Node3D:
	if not enabled:
		return null
	var h: Node3D = (load("res://scripts/realm_halo.gd") as GDScript).new()
	if tint.a > 0.0:
		h.set("_hue", tint.h)
	h.call("_build", _tier_of(idx))
	return h


static func place(idx: int) -> Dictionary:
	return PLACE[_tier_of(idx)]


static func _tier_of(idx: int) -> int:
	if _force == -2:
		_force = -1
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--halo-tier="):
				_force = int(a.substr(12))
	return clampi(_force if _force >= 0 else idx, 0, PLACE.size() - 1)


## 整体显隐 0~1（觉醒的淡入淡出）
func set_power(k: float) -> void:
	if is_equal_approx(k, _power):
		return
	_power = k
	visible = k > 0.005
	for m in _mats:
		m.set_shader_parameter("power", k)


## 从头展开一遍
func play_in() -> void:
	_reveal = 0.0
	_push_reveal()
	set_process(true)


func _push_reveal() -> void:
	for m in _mats:
		m.set_shader_parameter("reveal", _reveal)


func _process(dt: float) -> void:
	if not visible:
		return
	for e: Array in _spin:
		(e[0] as Node3D).rotate_object_local(Vector3(0.0, 0.0, 1.0), float(e[1]) * dt)      # 绕自己的轴转（椭圆的环只转花纹，不转椭圆本身）
	if _reveal < 1.0:
		_reveal = minf(_reveal + dt / UNFOLD, 1.0)
		_push_reveal()


# ---------- 图元 ----------

static func _annulus(r0: float, r1: float, a0: float, sweep: float) -> ArrayMesh:
	var key := "%.3f|%.3f|%.3f|%.3f" % [r0, r1, a0, sweep]
	if _rings.has(key):
		return _rings[key]
	var seg := maxi(int(96.0 * sweep / TAU), 8)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in seg + 1:
		var f := float(i) / float(seg)
		var a := a0 + sweep * f
		var d := Vector3(sin(a), cos(a), 0.0)
		verts.append(d * r0)
		verts.append(d * r1)
		uvs.append(Vector2(f, 0.0))
		uvs.append(Vector2(f, 1.0))
		if i < seg:
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_rings[key] = am
	return am


## 换成英雄色：有颜色的（金、橙、红）把色相挪到英雄色附近，原来色相上的那点差别留四成；白 / 灰不动
func _tc(c: Color) -> Color:
	if _hue < 0.0 or c.s < 0.1:
		return c
	return Color.from_hsv(fposmod(_hue + (c.h - 0.115) * 0.4, 1.0), clampf(c.s * 0.9, 0.0, 1.0), c.v, c.a)


func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _mat(sh: Shader, prio: int, rear: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = prio
	m.set_shader_parameter("rear", rear)
	m.set_shader_parameter("power", 0.0)
	m.set_shader_parameter("rear_push", float(PLACE[tier]["dist"]) + REAR_GAP)
	_mats.append(m)
	return m


func _add(mi: GeometryInstance3D, o: Dictionary) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-4, -4, -1), Vector3(8, 8, 2))
	mi.position = Vector3(float(o.get("x", 0.0)), float(o.get("y", 0.0)), float(o.get("z", 0.0)))
	if o.has("sx"):
		mi.scale = Vector3(float(o["sx"]), float(o.get("sy", 1.0)), 1.0)
	if o.has("flat"):
		# 平放、套在人身上：光环的原点在人背后 dist 米、离脚底 cy 米，这里挪回人的腰间
		var pl: Dictionary = PLACE[tier]
		mi.rotation.x = -PI * 0.5
		mi.position = Vector3(0.0, float(o.get("waist", 1.0)) - float(pl["cy"]), -float(pl["dist"]))
		(mi.material_override as ShaderMaterial).set_shader_parameter("rear_push", 0.0)      # 套在人身上的，前后本来就对
	add_child(mi)
	if absf(float(o.get("spin", 0.0))) > 0.0001:
		_spin.append([mi, float(o["spin"])])


## 环带。r 半径、w 宽；style 见 realm_halo_ring.gdshader。o：count flow solid z spin rear a0 sweep（度）sx sy flat y prio seed
func _ring(r: float, w: float, style: int, ca: Color, cb: Color, o := {}) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _annulus(r - w * 0.5, r + w * 0.5, deg_to_rad(float(o.get("a0", 0.0))), deg_to_rad(float(o.get("sweep", 360.0))))
	var m := _mat(SH_RING, int(o.get("prio", 0)), float(o.get("rear", 1.0)))
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("col_a", _v3(_tc(ca)))
	m.set_shader_parameter("col_b", _v3(_tc(cb)))
	m.set_shader_parameter("count", float(o.get("count", 24.0)))
	m.set_shader_parameter("flow", float(o.get("flow", 0.25)))
	m.set_shader_parameter("solid", float(o.get("solid", 0.0)))
	m.set_shader_parameter("seed", float(o.get("seed", float(_mats.size()) * 1.7)))
	mi.material_override = m
	_add(mi, o)


## 圆面。kind 见 realm_halo_disc.gdshader；size 边长。o：x y z rays rear prio sx sy
func _disc(kind: int, size: float, ca: Color, cb: Color, o := {}) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	var m := _mat(SH_DISC, int(o.get("prio", -2)), float(o.get("rear", 0.45)))
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("col_a", _v3(_tc(ca)))
	m.set_shader_parameter("col_b", _v3(_tc(cb)))
	m.set_shader_parameter("rays", float(o.get("rays", 0.0)))
	m.set_shader_parameter("seed", float(_mats.size()) * 2.3)
	mi.material_override = m
	_add(mi, o)


## 攒一片。base 根的位置（o.center = true 时是中心）；ang 朝向（度，从正上方起顺时针）；len / wid 长宽（米）。
## o：ph 相位（展开先后 / 摆动错开，不写按顺序排）sway 摆动幅度（弧度）par 参数 alpha 浓淡 z
func _blade(style: int, base: Vector2, ang: float, length: float, wid: float, col: Color, o := {}) -> void:
	var a := deg_to_rad(ang)
	var dir := Vector3(sin(a), cos(a), 0.0)
	var org := Vector3(base.x, base.y, float(o.get("z", 0.0)))
	if not bool(o.get("center", false)):
		org += dir * length * 0.5
	var xf := Transform3D(Basis(Vector3(cos(a), -sin(a), 0.0) * wid, dir * length, Vector3(0, 0, 1)), org)
	_n += 1
	_blades.append([xf, Color(col.r, col.g, col.b, float(o.get("alpha", 1.0))),
			Color(float(style), float(o.get("ph", fmod(float(_n) * 0.137, 1.0))), float(o.get("sway", 0.0)), float(o.get("par", 1.0)))])


## 把攒着的片建成一个 MultiMesh。rim 描边 / 高光色。o：spin rear prio z
func _flush(rim: Color, o := {}) -> void:
	if _blades.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mm.mesh = qm
	mm.instance_count = _blades.size()
	for i in _blades.size():
		mm.set_instance_transform(i, _blades[i][0])
		mm.set_instance_color(i, _tc(_blades[i][1]))
		mm.set_instance_custom_data(i, _blades[i][2])
	_blades.clear()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := _mat(SH_BLADE, int(o.get("prio", 1)), float(o.get("rear", 1.0)))
	m.set_shader_parameter("rim_col", _v3(_tc(rim)))
	mi.material_override = m
	_add(mi, o)


## 一圈（或一段弧上的）莲瓣：n 片，根在 r0、尖在 r1，宽 = 长 × wk。o.at 圆心挪到哪；o.arch > 0 时中间的最长、两边的短到 arch 倍
func _petals(style: int, n: int, r0: float, r1: float, wk: float, col: Color, o := {}) -> void:
	var a0 := float(o.get("a0", 0.0))
	var sweep := float(o.get("sweep", 360.0))
	var full := sweep >= 359.0
	var at: Vector2 = o.get("at", Vector2.ZERO)
	var arch := float(o.get("arch", 0.0))
	for i in n:
		var f := float(i) / float(n) if full else float(i) / float(maxi(n - 1, 1))
		var ang := a0 + sweep * f
		var a := deg_to_rad(ang)
		var length := r1 - r0
		if arch > 0.0:
			length *= lerpf(arch, 1.0, pow(sin(f * PI), 0.8))
		var oo := o.duplicate()
		oo["ph"] = absf(angle_difference(0.0, a)) / PI * 0.8      # 从顶上往两边依次长出来
		_blade(style, at + Vector2(sin(a), cos(a)) * r0, ang, length, length * wk, col, oo)


## 冠饰：中间一枚高花苞、两侧各两片矮的、底下一颗宝石。at 底座中心，s 大小
func _crest(at: Vector2, s: float, bud: Color, gem: Color, o := {}) -> void:
	var z := float(o.get("z", -0.03))
	for side: float in [-1.0, 1.0]:
		_blade(9, at + Vector2(side * 0.06 * s, -0.02 * s), side * 62.0, 0.5 * s, 0.2 * s, bud.darkened(0.12), {"z": z, "ph": 0.05})
		_blade(9, at + Vector2(side * 0.03 * s, 0.0), side * 34.0, 0.72 * s, 0.26 * s, bud.darkened(0.05), {"z": z, "ph": 0.03})
	_blade(9, at + Vector2(0.0, -0.04 * s), 0.0, 1.0 * s, 0.36 * s, bud, {"z": z, "ph": 0.0})
	_blade(7, at + Vector2(0.0, 0.26 * s), 0.0, 0.34 * s * float(o.get("gem", 1.0)), 0.24 * s * float(o.get("gem", 1.0)), gem, {"z": z - 0.01, "center": true, "ph": 0.0})


## 四角星饰：一横一竖两枚花苞交叉，中间一颗宝石（环上的镶件）
func _star4(at: Vector2, s: float, col: Color, gem: Color, ang := 0.0, ph := 0.5) -> void:
	_blade(9, at, ang, s, s * 0.36, col, {"center": true, "ph": ph})
	_blade(9, at, ang + 180.0, s, s * 0.36, col, {"center": true, "ph": ph})
	_blade(9, at, ang + 90.0, s * 0.7, s * 0.3, col.darkened(0.08), {"center": true, "ph": ph})
	_blade(9, at, ang - 90.0, s * 0.7, s * 0.3, col.darkened(0.08), {"center": true, "ph": ph})
	_blade(7, at, ang, s * 0.42, s * 0.3, gem, {"center": true, "ph": ph, "z": -0.02})


## 一只翅膀：长羽从 a_top 扇到 a_bot（度，从正上方起往外），最上面的最长（len_long），往下越来越短（len_short）；
## 根上再压一排短的覆羽（col3）。side = 1 右、-1 左（角度自动镜像）
func _wing(pivot: Vector2, side: float, n: int, a_top: float, a_bot: float, len_long: float, len_short: float, style: int, col: Color, col2: Color, o := {}) -> void:
	var wk := float(o.get("wk", 0.3))
	for i in n:
		var f := float(i) / float(n - 1)
		var ang := lerpf(a_top, a_bot, f) * side
		var length := lerpf(len_long, len_short, pow(f, 0.8))
		_blade(style, Vector2((pivot.x + 0.015 * float(i)) * side, pivot.y - 0.03 * float(i)), ang, length, length * wk, col.lerp(col2, f),
				{"z": float(o.get("z", 0.1)) + 0.012 * float(i), "ph": 0.25 + 0.6 * f, "sway": float(o.get("sway", 0.05)) * (1.3 - 0.7 * f) * side,
				"par": float(o.get("par", 0.8)), "alpha": float(o.get("alpha", 1.0))})
	if o.has("covert"):
		var m := maxi(n - 3, 3)
		for i in m:
			var f := float(i) / float(m - 1)
			var ang := lerpf(a_top + 6.0, a_bot - 4.0, f) * side
			var length := lerpf(len_long, len_short, pow(f, 0.8)) * 0.46
			_blade(2, Vector2((pivot.x - 0.02 + 0.015 * float(i)) * side, pivot.y + 0.02 - 0.03 * float(i)), ang, length, length * (wk + 0.1), o["covert"],
					{"z": float(o.get("z", 0.1)) - 0.01, "ph": 0.2 + 0.5 * f, "sway": float(o.get("sway", 0.05)) * 0.5 * side, "par": 1.0})


## 沿折线取点（平滑过各个点），s 0~1
func _path(pts: PackedVector2Array, s: float) -> Vector2:
	var n := pts.size() - 1
	var x := clampf(s, 0.0, 1.0) * float(n)
	var i := mini(int(x), n - 1)
	return pts[i].cubic_interpolate(pts[i + 1], pts[maxi(i - 1, 0)], pts[mini(i + 2, n)], x - float(i))


## 一条龙（坐标按右边那条写，side = -1 时左右镜像）：龙头在 head、吻朝 face（度），鬃羽往外上扬；
## 身子沿 pts 盘下去（pts[0] 在头后面），一节节鳞越来越细，尾梢渐成红绫
func _dragon(side: float, head: Vector2, face: float, pts: PackedVector2Array, ivory: Color, body: Color, red: Color, eye: Color) -> void:
	var fa := deg_to_rad(face)
	var fd := Vector2(sin(fa), cos(fa))
	var up := Vector2(0.0, 1.0)
	# 身子：从尾往头排（后画的压在上面），每节的尖朝尾巴
	var n := 14
	for k in n:
		var i := n - 1 - k
		var s := float(i) / float(n - 1)
		var p := _path(pts, s)
		var d := (_path(pts, minf(s + 0.03, 1.0)) - _path(pts, maxf(s - 0.03, 0.0))).normalized()
		var ang := rad_to_deg(atan2(d.x, d.y))
		_blade(9, Vector2(p.x * side, p.y), ang * side, lerpf(0.62, 0.38, s), lerpf(0.48, 0.17, s), body.lerp(red, smoothstep(0.62, 0.95, s)),
				{"center": true, "ph": 0.35 + 0.5 * s})
		if i % 2 == 0 and i > 0 and i < n - 2:
			# 背上的鬃：朝外、朝尾
			var out := (p.normalized() * 0.8 + d * 0.6).normalized()
			_blade(2, Vector2(p.x * side, p.y), rad_to_deg(atan2(out.x, out.y)) * side, lerpf(0.4, 0.22, s), 0.12, ivory.lerp(GOLD_HI, 0.4),
					{"ph": 0.4 + 0.5 * s, "sway": 0.1 * side, "par": 1.0})
	# 尾上的红绫
	var tail := _path(pts, 1.0)
	_blade(2, Vector2(tail.x * side, tail.y), 110.0 * side, 1.05, 0.2, red, {"ph": 0.85, "sway": 0.16 * side, "par": 1.0})
	_blade(2, Vector2(tail.x * side, tail.y), 148.0 * side, 0.85, 0.17, red.lightened(0.18), {"ph": 0.9, "sway": -0.2 * side, "par": 1.0})
	# 鬃：一把白金长羽，从头后往外上扬
	var hb := head - fd * 0.2
	for i in 7:
		var f := float(i) / 6.0
		_blade(2, Vector2((hb.x + 0.03 * float(i)) * side, hb.y + 0.03 - 0.02 * float(i)), lerpf(14.0, 104.0, f) * side, lerpf(0.62, 0.9, sin(f * PI)), 0.24,
				ivory.lerp(GOLD_HI, f * 0.5), {"ph": 0.3 + 0.4 * f, "sway": 0.05 * side, "par": 1.0})
	# 下颌（张着嘴）、头、吻
	var jaw := head + fd * 0.02 - up * 0.1
	var bone := ivory.lerp(WHITE, 0.6)
	_blade(9, Vector2(jaw.x * side, jaw.y), (face - 30.0) * side, 0.46, 0.26, bone.darkened(0.08), {"ph": 0.32})
	_blade(11, Vector2((jaw.x + fd.x * 0.1) * side, jaw.y + 0.03), (face - 14.0) * side, 0.34, 0.1, Color(0.95, 0.3, 0.34), {"ph": 0.34})
	_blade(9, Vector2((head.x - fd.x * 0.04) * side, head.y - fd.y * 0.04), face * side, 0.8, 0.52, bone, {"center": true, "ph": 0.3})
	var nose := head + fd * 0.1 + up * 0.03
	_blade(9, Vector2(nose.x * side, nose.y), (face + 5.0) * side, 0.56, 0.4, bone, {"ph": 0.3})
	# 角：两支金角往后上方（压在鬃上面）
	var horn := Color(1.0, 0.7, 0.26)
	var hp := head - fd * 0.16 + up * 0.12
	_blade(11, Vector2(hp.x * side, hp.y), 22.0 * side, 0.82, 0.14, horn, {"ph": 0.3})
	_blade(11, Vector2((hp.x + 0.1) * side, hp.y - 0.02), 50.0 * side, 0.62, 0.12, horn, {"ph": 0.32})
	var ep := head + fd * 0.1 + up * 0.11
	_blade(7, Vector2(ep.x * side, ep.y), face * side, 0.16, 0.1, eye, {"center": true, "ph": 0.3})
	# 须
	var wp := head + fd * 0.6
	_blade(2, Vector2(wp.x * side, wp.y), (face - 62.0) * side, 0.56, 0.06, GOLD_HI, {"ph": 0.4, "sway": 0.25 * side, "par": 1.0})


## 星芒：在半径 r0 ~ r1 的一圈里撒 n 颗
func _sparks(n: int, r0: float, r1: float, col: Color, size: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 97 + tier * 13
	for i in n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (r1 - r0) + r0
		var s := size * rng.randf_range(0.6, 1.4)
		_blade(8, Vector2(sin(a), cos(a)) * r, rng.randf_range(-20.0, 20.0), s, s, col, {"center": true, "ph": rng.randf(), "z": rng.randf_range(-0.2, 0.25)})


# ---------- 八档 ----------

func _build(idx: int) -> void:
	tier = idx
	match idx:
		0: _t_lianqi()
		1: _t_zhuji()
		2: _t_jiedan()
		3: _t_yuanying()
		4: _t_huashen()
		5: _t_lianxu()
		6: _t_heti()
		_: _t_dacheng()
	set_power(0.0)
	set_process(true)


## 炼气：一圈细白环、顶上一朵莲纹、两张符、两侧甩出去的云气、绕身一缕云气
func _t_lianqi() -> void:
	var c := Color(0.8, 0.97, 1.0)
	var c2 := Color(0.55, 0.88, 1.0)
	var r := 0.8
	_disc(0, 1.7, c2 * 0.28, c * 0.22, {"z": 0.1, "rear": 0.8})
	_ring(r, 0.1, 0, c, WHITE, {"flow": 0.2, "solid": 0.5})
	_ring(r * 0.9, 0.04, 0, c2 * 0.7, c2, {"flow": -0.12, "spin": -0.2})
	_ring(0.85, 0.34, 4, Color(0.9, 0.97, 1.0) * 0.6, c, {"flat": true, "waist": 1.0, "count": 3.0, "flow": 0.12})
	for side: float in [-1.0, 1.0]:
		# 两侧的云气：贴着环的下半边往外甩
		for i in 3:
			_blade(2, Vector2(side * r * (0.86 - 0.05 * float(i)), -0.2 - 0.14 * float(i)), side * (96.0 + 17.0 * float(i)), 0.74 - 0.15 * float(i), 0.2 - 0.03 * float(i),
					c.lerp(c2, 0.3 * float(i)), {"ph": 0.4 + 0.1 * float(i), "sway": 0.1 * side, "par": 0.45, "z": 0.04})
		_blade(1, Vector2(side * 0.04, r + 0.0), side * 50.0, 0.26, 0.13, c, {"ph": 0.02})
		_blade(1, Vector2(side * 0.1, r - 0.01), side * 82.0, 0.2, 0.08, c, {"ph": 0.04})
		_blade(5, Vector2(side * r * 1.02, r * 0.7), side * 28.0, 0.36, 0.2, c, {"center": true, "sway": 0.12 * side, "ph": 0.35, "par": 1.0})
	_blade(1, Vector2(0.0, r - 0.02), 0.0, 0.4, 0.19, c, {"ph": 0.0})
	_blade(12, Vector2(0.0, r + 0.14), 0.0, 0.22, 0.22, c, {"center": true, "ph": 0.0})
	_sparks(16, 0.5, 1.3, c, 0.11)
	_flush(WHITE)


## 筑基：玉环镶金边、金冠嵌翠、环内八瓣金莲线纹、斜四角的金叶、四枚金符绕着转
func _t_zhuji() -> void:
	var jade := Color(0.56, 0.88, 0.7)
	var green := Color(0.35, 0.95, 0.6)
	var r := 1.0
	_disc(0, 2.0, Color(1.0, 0.7, 0.35) * 0.25, GOLD_HI * 0.2, {"z": 0.12, "rear": 0.8, "rays": 8.0})
	_ring(r, 0.12, 1, jade, GOLD, {"solid": 0.94, "count": 22.0, "flow": 0.1})
	_ring(r + 0.09, 0.024, 0, GOLD, GOLD_HI, {"flow": 0.3, "solid": 0.8})
	# 环内的莲花线纹：两层
	_petals(1, 8, 0.16, 0.76, 0.62, GOLD, {"z": 0.08})
	_petals(1, 8, 0.1, 0.48, 0.6, GOLD_HI, {"z": 0.08, "a0": 22.5})
	_flush(Color(1.0, 0.8, 0.4), {"prio": -1, "spin": 0.06})
	# 冠、两侧的宝石、斜四角的金叶
	_crest(Vector2(0.0, r - 0.05), 0.42, GOLD, green)
	for side: float in [-1.0, 1.0]:
		_blade(9, Vector2(side * r, 0.0), 0.0, 0.26, 0.2, GOLD, {"center": true, "ph": 0.5})
		_blade(9, Vector2(side * r, 0.0), 90.0, 0.2, 0.13, GOLD.darkened(0.1), {"center": true, "ph": 0.5})
		_blade(7, Vector2(side * r, 0.0), 0.0, 0.13, 0.11, green, {"center": true, "ph": 0.5, "z": -0.02})
	for ang: float in [-135.0, -45.0, 45.0, 135.0]:
		var a := deg_to_rad(ang)
		var at := Vector2(sin(a), cos(a)) * (r + 0.02)
		_blade(9, at, ang - 24.0, 0.3, 0.13, GOLD.darkened(0.06), {"ph": 0.45})
		_blade(9, at, ang + 24.0, 0.3, 0.13, GOLD.darkened(0.06), {"ph": 0.45})
		_blade(9, at, ang, 0.36, 0.16, green.lerp(GOLD_HI, 0.35), {"ph": 0.45})
	_sparks(16, 0.3, 1.5, GOLD_HI, 0.11)
	_flush(GOLD_HI)
	# 四枚金符：绕着环慢慢转
	for i in 4:
		var a := deg_to_rad(90.0 * float(i))
		_blade(6, Vector2(sin(a), cos(a)) * (r + 0.42), rad_to_deg(a) + 20.0, 0.34, 0.24, GOLD, {"center": true, "ph": 0.6 + 0.08 * float(i), "sway": 0.1})
	_flush(GOLD_HI, {"spin": 0.25})
	for i in 4:
		_ring(r + 0.42, 0.016, 0, GOLD, GOLD_HI, {"a0": 13.0 + 90.0 * float(i), "sweep": 34.0, "spin": 0.25, "flow": 0.6, "solid": 0.6})


## 结丹：金环、背后两层金红琉璃莲瓣、环里一团金丹火、四枚晶簇
func _t_jiedan() -> void:
	var amber := Color(1.0, 0.76, 0.34)
	var deep := Color(1.0, 0.58, 0.22)
	var r := 0.9
	_disc(0, 2.6, Color(1.0, 0.6, 0.25) * 0.3, GOLD_HI * 0.22, {"z": 0.2, "rear": 0.8, "rays": 10.0})
	# 背后的莲瓣：外层九瓣深一点，内层八瓣亮一点，都是中间的最高
	for i in 9:
		var f := float(i) / 8.0
		var ang := lerpf(-128.0, 128.0, f)
		var a := deg_to_rad(ang)
		var length := lerpf(0.46, 0.84, pow(sin(f * PI), 0.8))
		_blade(0, Vector2(sin(a), cos(a)) * (r - 0.14), ang, length, length * 0.68, deep, {"z": 0.18, "ph": absf(f - 0.5) * 1.4, "par": 0.85, "sway": 0.025})
	for i in 8:
		var f := float(i) / 7.0
		var ang := lerpf(-112.0, 112.0, f)
		var a := deg_to_rad(ang)
		var length := lerpf(0.32, 0.58, pow(sin(f * PI), 0.8))
		_blade(0, Vector2(sin(a), cos(a)) * (r - 0.12), ang, length, length * 0.7, amber, {"z": 0.15, "ph": absf(f - 0.5) * 1.4 + 0.1, "par": 0.95, "sway": 0.03})
	_flush(GOLD_HI, {"prio": -1})
	_ring(r, 0.1, 1, GOLD.darkened(0.05), GOLD_HI, {"solid": 0.94, "count": 30.0, "flow": 0.12})
	_ring(r - 0.075, 0.018, 0, GOLD, GOLD_HI, {"flow": -0.25, "solid": 0.7})
	# 金丹：一团光 + 火苗
	_blade(12, Vector2(0.0, 0.42), 0.0, 0.46, 0.46, Color(1.0, 0.78, 0.36), {"center": true, "ph": 0.1, "alpha": 0.8})
	_blade(3, Vector2(0.0, 0.3), 0.0, 0.5, 0.3, Color(1.0, 0.56, 0.16), {"ph": 0.12})
	_blade(3, Vector2(-0.09, 0.3), -22.0, 0.3, 0.17, Color(1.0, 0.5, 0.16), {"ph": 0.2})
	_blade(3, Vector2(0.09, 0.3), 22.0, 0.3, 0.17, Color(1.0, 0.5, 0.16), {"ph": 0.25})
	_blade(9, Vector2(0.0, 0.16), 0.0, 0.2, 0.3, GOLD, {"ph": 0.1})
	# 环顶的晶苞
	_blade(4, Vector2(0.0, r - 0.1), 0.0, 0.46, 0.2, Color(1.0, 0.9, 0.62), {"ph": 0.0, "z": -0.03})
	_blade(9, Vector2(0.0, r - 0.12), -40.0, 0.24, 0.12, GOLD, {"ph": 0.02, "z": -0.02})
	_blade(9, Vector2(0.0, r - 0.12), 40.0, 0.24, 0.12, GOLD, {"ph": 0.02, "z": -0.02})
	_sparks(18, 0.4, 1.7, GOLD_HI, 0.12)
	_flush(GOLD_HI)
	# 四枚晶簇，拖着一道光
	var spots: Array = [[-118.0, 1.5], [-62.0, 1.6], [70.0, 1.56], [128.0, 1.48]]
	for e: Array in spots:
		var a := deg_to_rad(float(e[0]))
		_blade(4, Vector2(sin(a), cos(a)) * float(e[1]), float(e[0]) + 62.0, 0.36, 0.15, Color(1.0, 0.88, 0.6), {"center": true, "sway": 0.14, "ph": 0.7})
		_ring(float(e[1]) - 0.05, 0.014, 0, GOLD, GOLD_HI, {"a0": float(e[0]) - 26.0, "sweep": 24.0, "flow": 0.7, "spin": 0.12, "solid": 0.5})
	_flush(GOLD_HI, {"spin": 0.12})


## 元婴：紫金环里一颗半透明的灵珠，珠里一座紫莲台、莲台上蜷着元婴，两侧一对紫粉的翅
func _t_yuanying() -> void:
	var purple := Color(0.58, 0.4, 0.96)
	var pink := Color(0.93, 0.68, 1.0)
	var r := 1.1
	_disc(0, 2.8, purple * 0.3, pink * 0.2, {"z": 0.2, "rear": 0.8, "rays": 9.0})
	_disc(3, r * 2.0, Color(0.5, 0.36, 0.86), Color(0.95, 0.8, 1.0), {"z": 0.16, "rear": 0.9, "prio": -3})
	# 莲台：珠子下半边往上开的两层莲瓣
	_petals(0, 9, 0.1, 0.92, 0.6, purple, {"at": Vector2(0.0, -0.52), "a0": -96.0, "sweep": 192.0, "arch": 0.72, "z": 0.12, "par": 0.75})
	_petals(0, 7, 0.08, 0.66, 0.62, Color(0.76, 0.6, 1.0), {"at": Vector2(0.0, -0.5), "a0": -72.0, "sweep": 144.0, "arch": 0.75, "z": 0.1, "par": 0.85})
	_flush(Color(1.0, 0.86, 0.6), {"prio": -1})
	_ring(r, 0.12, 1, purple.darkened(0.1), GOLD, {"solid": 0.94, "count": 26.0, "flow": 0.1})
	_ring(0.43, 0.04, 1, GOLD, GOLD_HI, {"solid": 0.9, "count": 16.0, "y": 0.3, "z": -0.02, "sx": 1.0, "sy": 0.9})
	_disc(2, 0.78, Color(0.8, 0.64, 1.0), Color(1.0, 0.95, 1.0), {"y": 0.3, "z": -0.03, "rear": 1.0, "prio": 0})
	# 一对翅：从下面两侧往外上扇开
	for side: float in [-1.0, 1.0]:
		_wing(Vector2(0.56, -0.66), side, 8, 62.0, 124.0, 1.45, 0.66, 2, pink, purple, {"z": 0.14, "sway": 0.06, "par": 0.6, "wk": 0.3, "covert": GOLD_HI})
	_flush(Color(1.0, 0.88, 0.6), {"prio": -1})
	# 冠、环上四角的星饰、环底的坠子
	_crest(Vector2(0.0, r - 0.04), 0.42, GOLD, Color(0.97, 0.9, 1.0))
	for ang: float in [-128.0, -52.0, 52.0, 128.0]:
		var a := deg_to_rad(ang)
		_star4(Vector2(sin(a), cos(a)) * r, 0.2, GOLD, Color(0.97, 0.88, 1.0), ang)
	_star4(Vector2(0.0, -r), 0.2, GOLD, pink)
	_sparks(20, 0.4, 1.8, pink, 0.12)
	_flush(GOLD_HI)
	# 环外两道紫气
	_ring(r + 0.2, 0.03, 0, purple, pink, {"a0": 200.0, "sweep": 120.0, "flow": 0.5, "spin": 0.2})
	_ring(r + 0.3, 0.024, 0, purple, pink, {"a0": 20.0, "sweep": 100.0, "flow": 0.5, "spin": -0.15})


## 化神：三圈各转各的碎晶弧刃围着一扇星门，外面浮着紫晶
func _t_huashen() -> void:
	var lav := Color(0.7, 0.74, 1.0)
	var violet := Color(0.58, 0.42, 1.0)
	var edge := Color(1.0, 0.92, 0.74)
	_disc(1, 2.2, Color(0.72, 0.5, 1.0), Color(1.0, 0.86, 1.0), {"z": 0.12, "rear": 0.85, "sx": 1.12, "prio": -3})
	_ring(1.16, 0.26, 3, lav, edge, {"solid": 0.9, "count": 4.0, "spin": 0.35, "sx": 1.1})
	_ring(1.42, 0.22, 3, lav.lerp(violet, 0.4), edge, {"solid": 0.85, "count": 3.0, "spin": -0.24, "sx": 1.1, "z": 0.05})
	_ring(1.66, 0.15, 3, violet.lerp(lav, 0.3), edge, {"solid": 0.75, "count": 5.0, "spin": 0.16, "sx": 1.1, "z": 0.1})
	_ring(1.03, 0.035, 0, Color(0.9, 0.8, 1.0), WHITE, {"flow": 0.35, "sx": 1.1, "solid": 0.4})
	_crest(Vector2(0.0, 1.06), 0.5, GOLD_HI, Color(0.8, 0.9, 1.0))
	_star4(Vector2(0.0, -1.06), 0.22, GOLD_HI, Color(0.8, 0.9, 1.0))
	_sparks(22, 0.3, 2.0, Color(0.9, 0.85, 1.0), 0.12)
	_flush(edge)
	for i in 6:
		var a := deg_to_rad(30.0 + 60.0 * float(i))
		var rr := 1.95 + 0.12 * sin(float(i) * 2.1)
		_blade(4, Vector2(sin(a) * 1.08, cos(a)) * rr, rad_to_deg(a) + 25.0, 0.42 + 0.12 * cos(float(i) * 1.7), 0.18, violet.lerp(WHITE, 0.2), {"center": true, "sway": 0.18, "ph": 0.6 + 0.05 * float(i)})
	_flush(edge, {"spin": -0.12})


## 炼虚：金环、环里一树金莲、两侧一对金焰翅
func _t_lianxu() -> void:
	var flame := Color(1.0, 0.56, 0.16)
	var gold := Color(1.0, 0.76, 0.3)
	var r := 1.25
	_disc(0, 3.0, Color(1.0, 0.62, 0.2) * 0.32, GOLD_HI * 0.22, {"z": 0.22, "rear": 0.8, "rays": 12.0})
	# 金莲树：三层莲瓣往上开，越外越深；中间一道火
	_petals(0, 9, 0.5, 1.14, 0.44, gold.lerp(flame, 0.55), {"at": Vector2(0.0, -0.2), "a0": -92.0, "sweep": 184.0, "arch": 0.7, "z": 0.16, "par": 0.8})
	_petals(0, 7, 0.3, 0.9, 0.5, gold.lerp(flame, 0.25), {"at": Vector2(0.0, -0.2), "a0": -78.0, "sweep": 156.0, "arch": 0.72, "z": 0.13, "par": 0.9})
	_petals(0, 5, 0.1, 0.62, 0.58, gold, {"at": Vector2(0.0, -0.2), "a0": -60.0, "sweep": 120.0, "arch": 0.75, "z": 0.1, "par": 1.0})
	_blade(3, Vector2(0.0, -0.3), 0.0, 1.2, 0.3, flame, {"ph": 0.1, "z": 0.08})
	_flush(GOLD_HI, {"prio": -1})
	_ring(r, 0.13, 1, gold, GOLD_HI, {"solid": 0.95, "count": 34.0, "flow": 0.12})
	_ring(r + 0.11, 0.024, 0, GOLD, GOLD_HI, {"flow": 0.3, "solid": 0.7})
	# 金焰翅：外面一排火羽，里面一排金羽
	for side: float in [-1.0, 1.0]:
		_wing(Vector2(0.66, -0.7), side, 10, 46.0, 128.0, 1.8, 0.8, 3, gold, flame, {"z": 0.16, "sway": 0.05, "wk": 0.3, "par": 0.9})
		_wing(Vector2(0.62, -0.68), side, 8, 58.0, 122.0, 1.2, 0.6, 2, gold, gold.lerp(flame, 0.4), {"z": 0.12, "sway": 0.04, "wk": 0.3, "par": 1.0, "covert": GOLD_HI})
	_flush(GOLD_HI, {"prio": -1})
	_crest(Vector2(0.0, r - 0.03), 0.52, GOLD, Color(0.97, 0.98, 1.0))
	_blade(12, Vector2(0.0, 0.52), 0.0, 0.42, 0.42, GOLD_HI, {"center": true, "ph": 0.1, "alpha": 0.7})
	_blade(4, Vector2(0.0, 0.36), 0.0, 0.34, 0.17, Color(1.0, 0.98, 0.9), {"ph": 0.1, "z": -0.02})
	_sparks(26, 0.4, 2.1, GOLD_HI, 0.13)
	_flush(GOLD_HI)


## 合体：金环、赤玉冠、环心莲纹、左右各一条白金龙（头朝里、鬃羽上扬、紫身盘着环的下半边、尾系红绫）、两侧垂着宫灯流苏
func _t_heti() -> void:
	var ivory := Color(1.0, 0.95, 0.84)
	var purple := Color(0.52, 0.3, 0.84)
	var red := Color(0.94, 0.2, 0.26)
	var eye := Color(0.75, 0.4, 1.0)
	var r := 1.5
	_disc(0, 3.2, Color(1.0, 0.76, 0.5) * 0.3, ivory * 0.22, {"z": 0.2, "rear": 0.8, "rays": 14.0})
	_petals(1, 8, 0.25, 0.9, 0.6, ivory, {"z": 0.12})
	_petals(1, 8, 0.15, 0.58, 0.58, GOLD_HI, {"z": 0.12, "a0": 22.5})
	_flush(GOLD_HI, {"prio": -1, "spin": 0.05})
	_ring(r, 0.14, 1, ivory.darkened(0.04), GOLD, {"solid": 0.95, "count": 36.0, "flow": 0.1, "sy": 1.08})
	_ring(r + 0.11, 0.024, 0, GOLD, GOLD_HI, {"flow": 0.3, "solid": 0.7, "sy": 1.08})
	_ring(r + 0.3, 0.016, 0, GOLD_HI * 0.8, WHITE, {"flow": 0.4, "sx": 1.2, "sy": 0.5, "spin": 0.3})
	for side: float in [-1.0, 1.0]:
		_dragon(side, Vector2(1.2, -0.06), -102.0,
				PackedVector2Array([Vector2(1.5, -0.14), Vector2(1.74, -0.5), Vector2(1.62, -0.98), Vector2(1.22, -1.3), Vector2(0.88, -1.16), Vector2(0.76, -1.44)]),
				ivory, purple, red, eye)
		# 环上的星饰、外侧的宫灯和流苏、环底垂下的金穗
		_star4(Vector2(side * 0.98, 1.22), 0.22, GOLD, WHITE, side * 40.0, 0.2)
		_blade(8, Vector2(side * 0.98, 1.22), 0.0, 0.5, 0.5, ivory, {"center": true, "ph": 0.2 + 0.3 * side})
		_blade(10, Vector2(side * (r + 0.72), 0.0), 180.0, 0.95, 0.16, ivory, {"ph": 0.7, "sway": 0.08})
		_star4(Vector2(side * (r + 0.72), 0.1), 0.19, GOLD, eye, 0.0, 0.6)
		_blade(10, Vector2(side * 0.5, -1.52), 180.0, 0.7, 0.12, GOLD_HI, {"ph": 0.8, "sway": 0.07})
		_blade(10, Vector2(side * 0.62, -1.47), 180.0, 0.5, 0.1, GOLD_HI, {"ph": 0.85, "sway": 0.07})
	# 赤玉冠、底下的坠子
	_crest(Vector2(0.0, r * 1.08 - 0.04), 0.6, GOLD, red, {"gem": 1.5})
	_star4(Vector2(0.0, -r * 1.08), 0.26, GOLD, eye)
	_blade(10, Vector2(0.0, -r * 1.08 - 0.14), 180.0, 0.6, 0.12, red, {"ph": 0.95, "sway": 0.1})
	_sparks(28, 0.5, 2.3, ivory, 0.13)
	_flush(GOLD_HI)


## 大乘：层层琉璃莲瓣、莲心一朵金莲、外面一圈转着的符文、圈上八朵琉璃莲苞、绕身几道金光轨
func _t_dacheng() -> void:
	var glass := Color(1.0, 0.96, 0.9)
	var rose := Color(1.0, 0.86, 0.9)
	var lilac := Color(0.92, 0.88, 1.0)
	var gold := Color(1.0, 0.8, 0.4)
	var rim := Color(1.0, 0.76, 0.34)
	_disc(0, 3.6, Color(1.0, 0.78, 0.45) * 0.34, GOLD_HI * 0.25, {"z": 0.25, "rear": 0.8, "rays": 16.0})
	# 琉璃莲：最外一圈十二瓣，往里两层往上开的（中间的最高）
	_petals(0, 12, 0.6, 1.5, 0.52, lilac, {"z": 0.2, "par": 0.4, "sway": 0.02})
	_petals(0, 9, 0.3, 1.5, 0.48, glass.lerp(rose, 0.5), {"at": Vector2(0.0, -0.22), "a0": -104.0, "sweep": 208.0, "arch": 0.7, "z": 0.16, "par": 0.5, "sway": 0.02})
	_petals(0, 7, 0.2, 1.12, 0.52, glass, {"at": Vector2(0.0, -0.2), "a0": -84.0, "sweep": 168.0, "arch": 0.72, "z": 0.13, "par": 0.6, "sway": 0.02})
	# 莲心的金莲
	_petals(0, 5, 0.1, 0.72, 0.56, gold, {"at": Vector2(0.0, -0.16), "a0": -62.0, "sweep": 124.0, "arch": 0.74, "z": 0.1, "par": 0.95})
	_petals(1, 8, 0.1, 0.5, 0.6, GOLD_HI, {"z": 0.08, "a0": 22.5})
	_flush(rim, {"prio": -1})
	# 符文圈：两道细金线夹着一圈符文，整圈慢转；外面再一圈淡的反着转
	_ring(1.95, 0.2, 2, gold, GOLD_HI, {"count": 40.0, "flow": 0.05, "spin": 0.12, "solid": 0.9})
	_ring(2.13, 0.03, 0, gold, GOLD_HI, {"flow": -0.2, "spin": -0.08, "solid": 0.4})
	# 八朵琉璃莲苞，跟着符文圈转；正上正下的大一点
	for i in 8:
		var ang := 45.0 * float(i)
		var a := deg_to_rad(ang)
		var at := Vector2(sin(a), cos(a)) * 1.95
		var k := 1.3 if i % 4 == 0 else (1.1 if i % 2 == 0 else 0.9)
		_blade(0, at - Vector2(sin(a), cos(a)) * 0.1 * k, ang - 38.0, 0.34 * k, 0.17 * k, rose, {"ph": 0.5, "par": 0.8})
		_blade(0, at - Vector2(sin(a), cos(a)) * 0.1 * k, ang + 38.0, 0.34 * k, 0.17 * k, rose, {"ph": 0.5, "par": 0.8})
		_blade(0, at - Vector2(sin(a), cos(a)) * 0.14 * k, ang, 0.5 * k, 0.22 * k, glass, {"ph": 0.5, "par": 0.9})
		_blade(7, at, ang, 0.16 * k, 0.11 * k, Color(0.9, 0.95, 1.0), {"center": true, "ph": 0.5})
		_blade(8, at, 0.0, 0.36 * k, 0.36 * k, WHITE, {"center": true, "ph": 0.1 + 0.11 * float(i)})
	_flush(rim, {"spin": 0.12})
	# 莲心、星点、绕身的光轨
	_blade(12, Vector2(0.0, 0.1), 0.0, 0.7, 0.7, Color(1.0, 0.9, 0.62), {"center": true, "ph": 0.0, "alpha": 0.7})
	_sparks(34, 0.5, 2.4, GOLD_HI, 0.14)
	_flush(GOLD_HI)
	_ring(1.1, 0.06, 0, Color(1.0, 0.88, 0.55), WHITE, {"flat": true, "waist": 1.15, "flow": 0.5})
	_ring(1.35, 0.04, 0, GOLD, GOLD_HI, {"flat": true, "waist": 0.9, "flow": -0.35})
	_ring(0.8, 0.03, 0, GOLD, GOLD_HI, {"flat": true, "waist": 1.4, "flow": 0.7})
