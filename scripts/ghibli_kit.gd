extends RefCounted
## 吉卜力风场景公用件（木兰草原、择境门的预览世界共用）：
## · environment() / sun()：手绘天空（ghibli_sky.gdshader）、偏蓝的固定环境光、线性色调映射（颜色所见即所得）、
##   柔和泛光、淡蓝的空气透视雾、稍提饱和度；暖白色太阳，带软阴影。
## · prop_mat() / foliage_mat()：建筑 / 道具 / 树皮 / 石头，以及树冠 / 灌木 / 爬藤的材质（按颜色 + 花纹缓存）。
## · 网格工具：box / cyl / tube / quad / tri（写进 SurfaceTool，绕序自动按法线对齐），叶团 foliage_pad、爬藤 ivy。
## · 成品网格（缓存，只在主线程建一次）：伞形树 tree_mesh、灌木 bush_mesh、白石 rock_mesh。
## 故意不写 class_name：用 preload 引用。

const SKY_SHADER := preload("res://shaders/ghibli_sky.gdshader")
const PROP_SHADER := preload("res://shaders/ghibli_prop.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/ghibli_foliage.gdshader")

## 花纹编号（见 ghibli_prop.gdshader）
const PAT_PLAIN := 0
const PAT_PLANK := 1
const PAT_TILE := 2
const PAT_PLASTER := 3
const PAT_STONE := 4
const PAT_BARK := 5
const PAT_GLASS := 6
const PAT_GRAIN := 7
const PAT_ROCK := 8

## 调色板（sRGB，参考 Europa 截图取色）
const PLASTER := Color(0.88, 0.79, 0.62)
const WOOD := Color(0.56, 0.37, 0.21)
const WOOD_DARK := Color(0.36, 0.23, 0.14)
const STONE := Color(0.72, 0.68, 0.60)
const ROOF_RED := Color(0.72, 0.27, 0.20)
const ROOF_GREEN := Color(0.38, 0.52, 0.31)
const GLASS := Color(0.17, 0.23, 0.29)
const FRAME := Color(0.28, 0.32, 0.22)
const TERRACOTTA := Color(0.70, 0.40, 0.26)
const METAL := Color(0.58, 0.60, 0.62)
const CANVAS := Color(0.93, 0.89, 0.80)
const ROCK := Color(0.86, 0.82, 0.72)
const BARK := Color(0.44, 0.30, 0.20)
const TREE_LEAF := Color(0.32, 0.50, 0.33)
const BUSH_LEAF := Color(0.24, 0.42, 0.32)
const IVY_LEAF := Color(0.30, 0.50, 0.24)

const AMBIENT := Color(0.56, 0.69, 0.92)
const SUN_COLOR := Color(1.0, 0.95, 0.86)
const TREE_VARIANTS := 4
const BUSH_VARIANTS := 3

static var _tex := {}
static var _mats := {}
static var _meshes := {}


# ---------- 噪声贴图 ----------

static func noise_tex(key: String) -> NoiseTexture2D:
	if _tex.has(key):
		return _tex[key]
	var fn := FastNoiseLite.new()
	var t := NoiseTexture2D.new()
	t.seamless = true
	t.generate_mipmaps = true
	t.width = 256
	t.height = 256
	match key:
		"cloud":    # 积云主体：低频 fbm
			fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			fn.seed = 7
			fn.frequency = 0.006
			fn.fractal_octaves = 5
			t.width = 512
			t.height = 512
		"puff":     # 一团团鼓包：细胞噪声取距离再反相
			fn.noise_type = FastNoiseLite.TYPE_CELLULAR
			fn.seed = 9
			fn.frequency = 0.02
			fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
			fn.fractal_octaves = 2
			t.invert = true
			t.width = 512
			t.height = 512
		"shadow":   # 地上的云影
			fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			fn.seed = 31
			fn.frequency = 0.008
			fn.fractal_octaves = 3
		_:          # 道具花纹的细节
			fn.seed = 23
			fn.frequency = 0.03
			fn.fractal_octaves = 2
	t.noise = fn
	_tex[key] = t
	return t


## 带 ghibli_light.gdshaderinc 的材质都要给云影噪声
static func setup_light(m: ShaderMaterial) -> void:
	m.set_shader_parameter("cloud_shadow_noise", noise_tex("shadow"))


# ---------- 环境 / 太阳 ----------

static func environment() -> Environment:
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sm.set_shader_parameter("cloud_noise", noise_tex("cloud"))
	sm.set_shader_parameter("puff_noise", noise_tex("puff"))
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.92
	env.glow_hdr_luminance_cap = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.84, 0.95)
	env.fog_density = 0.00028
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.03
	return env


## 太阳：light_dir 是光线的行进方向（从太阳指向地面）
static func sun(light_dir: Vector3) -> DirectionalLight3D:
	var s := DirectionalLight3D.new()
	s.transform = Transform3D(Basis.looking_at(light_dir.normalized(), Vector3.UP), Vector3.ZERO)
	s.light_color = SUN_COLOR
	s.light_energy = 1.0
	s.shadow_enabled = true
	s.shadow_blur = 1.2
	s.directional_shadow_max_distance = 200.0
	return s


# ---------- 材质 ----------

static func prop_mat(col: Color, pattern: int, soft := 0.1) -> ShaderMaterial:
	var key := "p%s_%d_%.2f" % [col.to_html(false), pattern, soft]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = PROP_SHADER
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("pattern", pattern)
	m.set_shader_parameter("soft", soft)
	m.set_shader_parameter("detail_noise", noise_tex("detail"))
	setup_light(m)
	_mats[key] = m
	return m


static func foliage_mat(col: Color, sway := 1.0) -> ShaderMaterial:
	var key := "f%s_%.2f" % [col.to_html(false), sway]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("leaf_color", col)
	m.set_shader_parameter("sway", sway)
	setup_light(m)
	_mats[key] = m
	return m


# ---------- 网格工具 ----------

static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## 三角形：顶点顺序按法线自动调成 Godot 的正面（从正面看顺时针）
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
		var tu := ub
		ub = uc
		uc = tu
	st.set_normal(na)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(nb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(nc)
	st.set_uv(uc)
	st.add_vertex(c)


## 四边形（a b c d 绕一圈），整面一个法线
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		ua := Vector2(0, 0), ub := Vector2(1, 0), uc := Vector2(1, 1), ud := Vector2(0, 1)) -> void:
	tri(st, a, b, c, n, n, n, ua, ub, uc)
	tri(st, a, c, d, n, n, n, ua, uc, ud)


## 长方体：size 尺寸，xf 中心的变换（不要带缩放）；每面 UV 以米计
static func box(st: SurfaceTool, size: Vector3, xf: Transform3D) -> void:
	var h := size * 0.5
	var c: Array[Vector3] = [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[1, 2, 6, 5, Vector3.RIGHT, size.z, size.y], [4, 7, 3, 0, Vector3.LEFT, size.z, size.y],
			[3, 7, 6, 2, Vector3.UP, size.x, size.z], [0, 1, 5, 4, Vector3.DOWN, size.x, size.z],
			[5, 6, 7, 4, Vector3.BACK, size.x, size.y], [0, 3, 2, 1, Vector3.FORWARD, size.x, size.y]]
	for f: Array in faces:
		var n: Vector3 = xf.basis * (f[4] as Vector3)
		var du: float = f[5]
		var dv: float = f[6]
		quad(st, xf * c[f[0]], xf * c[f[1]], xf * c[f[2]], xf * c[f[3]], n,
				Vector2(0, dv), Vector2(0, 0), Vector2(du, 0), Vector2(du, dv))


## 圆台：沿局部 +Y 从 0 到 h，底半径 r0、顶半径 r1
static func cyl(st: SurfaceTool, r0: float, r1: float, h: float, seg: int, xf: Transform3D, caps := true) -> void:
	var slope := (r0 - r1) / maxf(h, 0.001)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var n0 := xf.basis * (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := xf.basis * (d1 + Vector3(0, slope, 0)).normalized()
		var p00 := xf * (d0 * r0)
		var p01 := xf * (d1 * r0)
		var p10 := xf * (d0 * r1 + Vector3(0, h, 0))
		var p11 := xf * (d1 * r1 + Vector3(0, h, 0))
		var u0 := r0 * a0
		var u1 := r0 * a1
		tri(st, p00, p01, p11, n0, n1, n1, Vector2(u0, h), Vector2(u1, h), Vector2(u1, 0))
		tri(st, p00, p11, p10, n0, n1, n0, Vector2(u0, h), Vector2(u1, 0), Vector2(u0, 0))
		if caps:
			var up := xf.basis * Vector3.UP
			tri(st, xf * Vector3(0, h, 0), p10, p11, up, up, up)
			tri(st, xf * Vector3.ZERO, p00, p01, -up, -up, -up)


## 两点之间一根方木
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, t: float, t2 := -1.0) -> void:
	var y := b - a
	var l := y.length()
	if l < 0.001:
		return
	y /= l
	var ref := Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	box(st, Vector3(t, l, t if t2 < 0.0 else t2), Transform3D(Basis(x, y, z), (a + b) * 0.5))


## 沿折线的管子（树干、树枝）：pts 中心线、rads 各点半径
static func tube(st: SurfaceTool, pts: Array[Vector3], rads: Array[float], seg: int) -> void:
	var rings: Array[PackedVector3Array] = []
	var norms: Array[PackedVector3Array] = []
	var vlen := 0.0
	for i in pts.size():
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == pts.size() - 1:
			t = pts[i] - pts[i - 1]
		else:
			t = pts[i + 1] - pts[i - 1]
		t = t.normalized()
		var ref := Vector3.FORWARD if absf(t.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var u := t.cross(ref).normalized()
		var v := t.cross(u)
		var ring := PackedVector3Array()
		var nr := PackedVector3Array()
		for k in seg + 1:
			var a := TAU * k / seg
			var d := u * cos(a) + v * sin(a)
			ring.append(pts[i] + d * rads[i])
			nr.append(d)
		rings.append(ring)
		norms.append(nr)
	for i in pts.size() - 1:
		var v0 := vlen
		vlen += pts[i].distance_to(pts[i + 1])
		for k in seg:
			var u0 := float(k) / seg
			var u1 := float(k + 1) / seg
			tri(st, rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], norms[i][k], norms[i][k + 1], norms[i + 1][k + 1],
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, vlen))
			tri(st, rings[i][k], rings[i + 1][k + 1], rings[i + 1][k], norms[i][k], norms[i + 1][k + 1], norms[i + 1][k],
					Vector2(u0, v0), Vector2(u1, vlen), Vector2(u0, vlen))
	var last := pts.size() - 1
	var tip := pts[last] + (pts[last] - pts[last - 1]).normalized() * rads[last] * 0.6
	for k in seg:
		tri(st, rings[last][k], rings[last][k + 1], tip, norms[last][k], norms[last][k + 1], norms[last][k])


# ---------- 叶子 ----------

static func _leaf_n(p: Vector3, u: Vector3, cc: Vector3) -> Vector3:
	return (u.normalized() * 0.55 + (p - cc).normalized() * 0.45).normalized()


static func _leaf_v(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


## 一团叶子：c 中心、rad 三轴半径、cc 整个树冠的中心（法线从它往外指）、cards 卡片数、sway 风摆权重
static func foliage_pad(st: SurfaceTool, c: Vector3, rad: Vector3, cc: Vector3, cards: int, rng: RandomNumberGenerator,
		sway := 1.0) -> void:
	var y0 := c.y - rad.y
	# 实心内核
	var rings := 5
	var segs := 10
	var dirs: Array[Vector3] = []
	for j in rings + 1:
		var phi := PI * j / rings
		for i in segs + 1:
			var th := TAU * i / segs
			dirs.append(Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)))
	for j in rings:
		for i in segs:
			var ids: Array[int] = [j * (segs + 1) + i, j * (segs + 1) + i + 1, (j + 1) * (segs + 1) + i + 1, (j + 1) * (segs + 1) + i]
			for tri_i: Array in [[0, 1, 2], [0, 2, 3]]:
				for k: int in tri_i:
					var u := dirs[ids[k]]
					var p := c + u * rad * 0.8
					var ao := clampf(0.35 + 0.5 * (p.y - y0) / (2.0 * rad.y), 0.0, 1.0)
					_leaf_v(st, p, _leaf_n(p, u, cc), Vector2(0.5, 0.5), Color(sway, 0.0, ao))
	# 叶簇卡片
	for k in cards:
		var u := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.55, 1.0), rng.randf_range(-1, 1))
		if u.length() < 0.1:
			continue
		u = u.normalized()
		var p := c + u * rad * rng.randf_range(0.82, 1.02)
		var s := rng.randf_range(0.55, 0.85) * rad.x * 0.62
		var cn := (u + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.5), rng.randf_range(-0.5, 0.5))).normalized()
		var t1 := cn.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		if t1.length() < 0.05:
			t1 = cn.cross(Vector3.UP if absf(cn.y) < 0.9 else Vector3.RIGHT)
		t1 = t1.normalized()
		var t2 := cn.cross(t1)
		var sd := rng.randf()
		var corners: Array[Vector3] = [p - t1 * s - t2 * s, p + t1 * s - t2 * s, p + t1 * s + t2 * s, p - t1 * s + t2 * s]
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for q: int in [0, 1, 2, 0, 2, 3]:
			var cp := corners[q]
			var ao := clampf(0.55 + 0.45 * (cp.y - y0) / (2.0 * rad.y), 0.0, 1.0)
			_leaf_v(st, cp, _leaf_n(cp, u, cc), uvs[q], Color(sway, sd, ao))


## 爬藤：从 base 沿墙往上爬 height 米，墙面朝 n
static func ivy(st: SurfaceTool, base: Vector3, height: float, n: Vector3, rng: RandomNumberGenerator) -> void:
	var side := Vector3.UP.cross(n).normalized()
	var steps := maxi(int(height / 0.3), 2)
	var p := base
	for i in steps:
		p += side * rng.randf_range(-0.18, 0.18) + Vector3.UP * 0.3
		var cnt := 2 if i < steps - 2 else 4
		for k in cnt:
			var c := p + n * rng.randf_range(0.05, 0.14) + side * rng.randf_range(-0.3, 0.3) * (1.0 + float(k) * 0.4)
			var s := rng.randf_range(0.2, 0.32)
			var spin := rng.randf() * TAU
			var t1 := (side * cos(spin) + Vector3.UP * sin(spin))
			var t2 := n.cross(t1).normalized()
			var nn := (n * 0.75 + Vector3.UP * 0.3).normalized()
			var sd := rng.randf()
			var ao := 0.55 + 0.45 * float(i) / steps
			var corners: Array[Vector3] = [c - t1 * s - t2 * s, c + t1 * s - t2 * s, c + t1 * s + t2 * s, c - t1 * s + t2 * s]
			var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for q: int in [0, 1, 2, 0, 2, 3]:
				_leaf_v(st, corners[q], nn, uvs[q], Color(0.3, sd, ao))


# ---------- 成品网格 ----------

## 伞形树（Europa 草原上那种歪脖子大树）：S 形弯的树干，顶上分三四根斜枝，枝头托着几团扁平的大叶团，
## 整个树冠宽而扁。两个面：0 树皮、1 叶子
static func tree_mesh(v: int) -> ArrayMesh:
	var key := "tree%d" % v
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + v * 131
	var bark := begin()
	var leaf := begin()
	var h := rng.randf_range(5.0, 7.0)
	var la := rng.randf() * TAU
	var lean := Vector3(cos(la), 0.0, sin(la)) * rng.randf_range(0.8, 2.2)
	var bend := Vector3(-sin(la), 0.0, cos(la)) * rng.randf_range(-0.9, 0.9)
	var pts: Array[Vector3] = []
	var rads: Array[float] = []
	for i in 9:
		var t := i / 8.0
		pts.append(Vector3(0.0, t * h, 0.0) + lean * t * t + bend * sin(t * PI))
		rads.append(lerpf(0.38, 0.17, t))
	tube(bark, pts, rads, 8)
	cyl(bark, 0.66, 0.36, 0.8, 8, Transform3D(Basis.IDENTITY, Vector3(0, -0.3, 0)), false)
	var pads: Array[Vector3] = []
	var sizes: Array[float] = []
	var nb := rng.randi_range(3, 4)
	var a0 := rng.randf() * TAU
	for b in nb:
		var a := a0 + TAU * b / nb + rng.randf_range(-0.35, 0.35)
		var start := pts[rng.randi_range(5, 7)]
		var dir := Vector3(cos(a), rng.randf_range(0.28, 0.55), sin(a)).normalized()
		var l := rng.randf_range(2.0, 3.2)
		var bp: Array[Vector3] = [start, start + dir * l * 0.5 + Vector3(0, 0.2, 0), start + dir * l + Vector3(0, 0.45, 0)]
		var br: Array[float] = [0.16, 0.11, 0.07]
		tube(bark, bp, br, 6)
		pads.append(bp[2] + Vector3(0, 0.45, 0))
		sizes.append(rng.randf_range(2.1, 2.9))
	pads.append(pts[8] + Vector3(0, 0.7, 0))
	sizes.append(rng.randf_range(2.6, 3.2))
	var cc := Vector3.ZERO
	for p in pads:
		cc += p
	cc /= pads.size()
	cc.y -= 0.8
	for i in pads.size():
		var r := sizes[i]
		foliage_pad(leaf, pads[i], Vector3(r, r * 0.45, r * rng.randf_range(0.85, 1.1)), cc, 30, rng, 1.0)
	var m := bark.commit()
	m.surface_set_material(0, prop_mat(BARK, PAT_BARK, 0.25))
	leaf.commit(m)
	m.surface_set_material(1, foliage_mat(TREE_LEAF, 1.0))
	_meshes[key] = m
	return m


## 灌木：贴地的一两团叶子
static func bush_mesh(v: int) -> ArrayMesh:
	var key := "bush%d" % v
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + v * 71
	var leaf := begin()
	var r := rng.randf_range(1.0, 1.4)
	var cc := Vector3(0, r * 0.3, 0)
	foliage_pad(leaf, Vector3(0, r * 0.55, 0), Vector3(r, r * 0.72, r * rng.randf_range(0.85, 1.1)), cc, 24, rng, 0.35)
	if rng.randf() < 0.7:
		var r2 := r * rng.randf_range(0.6, 0.8)
		foliage_pad(leaf, Vector3(r * 0.8, r2 * 0.5, r * 0.3), Vector3(r2, r2 * 0.7, r2), cc, 14, rng, 0.35)
	var m := leaf.commit()
	m.surface_set_material(0, foliage_mat(BUSH_LEAF, 0.35))
	_meshes[key] = m
	return m


## 草原上的白石：圆润的扁球按顶点位置抖一抖，平滑法线；底部压平（半埋在土里）
static func rock_mesh() -> ArrayMesh:
	if _meshes.has("rock"):
		return _meshes["rock"]
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 7
	var arr := sm.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := begin()
	for i in ids:
		var v := vs[i]
		var hh := hash(Vector3i(roundi(v.x * 50.0), roundi(v.y * 50.0), roundi(v.z * 50.0)))
		var k := 0.85 + float(hh % 1000) / 1000.0 * 0.3
		var p := v * k
		p.y = maxf(p.y, -0.35) * 0.75
		st.add_vertex(p)
	st.index()
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, prop_mat(ROCK, PAT_ROCK, 0.25))
	_meshes["rock"] = m
	return m
