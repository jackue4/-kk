extends Node3D
## 技能题字（参考 _ref/skill_calligraphy.png）：放技能时，招式名化作大号发光毛笔字立在场景空间里，不是屏幕 UI。
## 摆位：以放招那一刻主角身体中心为锚，字分左右两组（"千剑 | 莲台"），分立在主角左右各 SIDE 米、
## 往镜头反方向退 BACK 米处，左组略高右组略低；每组组内两个字错落斜排，整组正对放招那一刻的镜头、再各自向内侧多转一点，
## 像两面夹着主角的字墙。之后固定在世界里，不跟镜头、不跟人（≤2 个字时只一组，立在主角身后头顶上方）。
## 每组的字在一张 SubViewport 里用行楷 / 舒体写好（字体见 RealmBanner._load_font），贴到几层面片上
## （skill_calligraphy.gdshader）：后面几层压暗、错开叠出字身厚度，一层加色外发光，最前一层近白字面
## （HDR 起辉、枯笔飞白、湿墨前沿、流光扫过）。外加每组两道绕字盘旋的光痕（Trail3D）。
## 时间轴（真实时间，不受慢动作影响）：逐字按笔势写出 → 每字写成迸一簇光丝 → 停留 → 噪声消散、边缘烧成境界色、光丝上飘。
## 同一时间只留一处：再放技能时旧的立即转入消散。
## 故意不写 class_name：用 preload 引用。

const SHADER := preload("res://shaders/skill_calligraphy.gdshader")
const Banner := preload("res://scripts/realm_banner.gd")
const Sfx := preload("res://scripts/sfx.gd")
const PX := 220             # 贴图里的字号
const CELL := 1.12          # 字格 = 字号 × CELL
const STEP := Vector2(0.6, 0.62)  # 组内下一个字相对上一个的错位（按字格）
const PAD := 44.0
const CHAR_H := 1.9         # 场景里一个字格多高（米）
const LAYERS := 5           # 字身厚度层数
const THICK := 0.18         # 字身厚度（米）
const SIDE := 2.9
const BACK := 1.4
const TURN := 0.18          # 正对镜头之后再向内侧多转的角度
const T_CHAR0 := 0.12
const T_GAP := 0.16
const T_WRITE := 0.24
const T_HOLD := 2.2
const T_OUT := 0.8

static var _font: Font
static var _glow_shader: Shader
static var _current = null

var _t := 0.0
var _col := Color.WHITE
var _n := 0
var _mats: Array[ShaderMaterial] = []
var _roots: Array[Node3D] = []
var _rest: Array[Vector3] = []      # 各组落定的位置
var _centers: Array[Vector3] = []   # 每个字的中心（世界坐标，按整句序号）
var _trails: Array[Trail3D] = []
var _orbits: Array = []             # 每道光痕：[组下标, 半宽, 半高, 相位, 方向, 离面幅度]
var _done := 0
var _scattered := false
var _over := false
var _sc := 1.0                      # 整体尺寸倍数（字格、左右间距、厚度一起放大）
var _stamp := 0.0                   # >0：每写成一字，所在字组从 1+_stamp 倍"盖印"般砸回原大
var _half := 99                     # 第几个字起属于右组
var _kick: Array[float] = []        # 各组最近一次盖印的时刻，<0 = 还没有


## 在 anchor（主角身体中心）两侧立起 text 的 3D 题字，col 为境界主色。
## size_k 放大整组字（大招用）；stamp > 0 时每写成一字、所在字组从 1+stamp 倍猛地压回原大，像一方大印盖下
static func show_text(text: String, anchor: Vector3, col: Color, size_k := 1.0, stamp := 0.0) -> Node3D:
	if text.is_empty() or Vfx.root == null:
		return null
	if is_instance_valid(_current):
		_current.hurry()
	if _font == null:
		_font = Banner._load_font()
	var s := new()
	s._sc = size_k
	s._stamp = stamp
	Vfx.root.add_child(s)
	s._setup(text, anchor, col)
	_current = s
	Sfx.play("swing_heavy", -8.0, 0.6)
	return s


## 外发光层：同一份 shader 换成加色混合
static func _glow() -> Shader:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = SHADER.code.replace("blend_mix", "blend_add")
	return _glow_shader


## 立即转入消散（新的题字出来时）
func hurry() -> void:
	if _t < T_HOLD:
		_t = T_HOLD
		_done = _n


func _setup(text: String, anchor: Vector3, col: Color) -> void:
	_col = col
	_n = text.length()
	_centers.resize(_n)
	global_position = anchor
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else anchor + Vector3.BACK * 7.0
	var groups := _layout(_n, anchor, cam_pos, _sc)
	if groups.size() > 1:
		_half = int(groups[1][2])
	for g: Array in groups:
		_group(text.substr(int(g[2]), int(g[3])), int(g[2]), g[0], g[1])


## 各组字的摆位：[组中心, 面法线, 首字序号, 字数]。cam_pos 为写字那一刻的镜头位置
static func _layout(n: int, anchor: Vector3, cam_pos: Vector3, sc: float) -> Array:
	var to_cam := cam_pos - anchor
	to_cam.y = 0.0
	to_cam = to_cam.normalized() if to_cam.length_squared() > 1e-4 else Vector3.BACK
	var right := Vector3.UP.cross(to_cam)  # 镜头看过去的右手方向
	if n <= 2:
		var p := anchor - to_cam * BACK * 1.3 * sc + Vector3.UP * 1.6 * sc
		return [[p, _face(p, cam_pos, to_cam, 0.0), 0, n]]
	var half := (n + 1) / 2
	var pl := anchor - right * SIDE * sc - to_cam * BACK * sc + Vector3.UP * 0.75 * sc
	var pr := anchor + right * SIDE * sc - to_cam * BACK * sc + Vector3.UP * 0.35 * sc
	return [[pl, _face(pl, cam_pos, to_cam, TURN), 0, half], [pr, _face(pr, cam_pos, to_cam, -TURN), half, n - half]]


## 一组 m 个字的贴图尺寸（像素，含四周留白 PAD）
static func _px_size(m: int) -> Vector2:
	var cell := float(PX) * CELL
	return Vector2(cell * (1.0 + STEP.x * (m - 1)), cell * (1.0 + STEP.y * (m - 1))) + Vector2.ONE * PAD * 2.0


## 预估整句题字的取景框：每组字格区域（不含留白）按盖印的最大幅度放大、顶边再加上停留期间的上浮量，
## 返回各组四角的世界坐标。镜头据此保证字始终入画（见 gate_array.gd）；参数同 show_text，cam_pos 为写字那一刻的镜头位置
static func frame_points(text: String, anchor: Vector3, cam_pos: Vector3, size_k := 1.0, stamp := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cell := float(PX) * CELL
	for g: Array in _layout(text.length(), anchor, cam_pos, size_k):
		var hs := (_px_size(mini(int(g[3]), 4)) * 0.5 - Vector2.ONE * PAD) * (CHAR_H * size_k / cell) * (1.0 + stamp)
		var p: Vector3 = g[0]
		var x := Vector3.UP.cross(g[1] as Vector3)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				out.append(p + x * hs.x * sx + Vector3.UP * (hs.y * sy + (0.12 * T_HOLD if sy > 0.0 else 0.0)))
	return out


## 面法线：先正对镜头（水平方向），再绕竖轴多转 turn——左组正、右组负，内侧边退后、外侧边靠前
static func _face(pos: Vector3, cam_pos: Vector3, fallback: Vector3, turn: float) -> Vector3:
	var d := cam_pos - pos
	d.y = 0.0
	d = d.normalized() if d.length_squared() > 1e-4 else fallback
	return (Basis(Vector3.UP, turn) * d).normalized()


## 一组字：SubViewport 写字 → 几层面片 → 两道盘旋光痕。z 为字面朝向（面法线）
func _group(chars: String, idx0: int, pos: Vector3, z: Vector3) -> void:
	var m := mini(chars.length(), 4)
	var cell := float(PX) * CELL
	var size := _px_size(m)
	var vp := SubViewport.new()
	vp.size = Vector2i(ceili(size.x), ceili(size.y))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE     # 字是静态的（书写动画在着色器里）：只画一帧，不用每帧重画
	add_child(vp)

	# 每字一个字格，手写式的错位与倾斜
	var rects: Array[Rect2] = []
	var rots := PackedFloat32Array()
	var cells := PackedVector4Array()
	for k in 4:
		if k < m:
			var p := Vector2(PAD, PAD) + STEP * cell * float(k) + Vector2(randf_range(-10.0, 10.0), randf_range(-8.0, 8.0))
			var r := Rect2(p, Vector2(cell, cell))
			rects.append(r)
			rots.append(randf_range(-0.12, 0.06))
			cells.append(Vector4(r.position.x / size.x, r.position.y / size.y, r.size.x / size.x, r.size.y / size.y))
		else:
			cells.append(Vector4(0.0, 0.0, 1.0, 1.0))
	var cv := Control.new()
	cv.size = size
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(cv)
	var font := _font
	# R = 字芯，G = 外扩一圈的字形（描边先画、字芯盖在上面）
	cv.draw.connect(func() -> void:
		var base := (font.get_ascent(PX) - font.get_descent(PX)) * 0.5
		for k in m:
			cv.draw_set_transform(rects[k].get_center(), rots[k], Vector2.ONE)
			var p := Vector2(-cell * 0.5, base)
			cv.draw_string_outline(font, p, chars[k], HORIZONTAL_ALIGNMENT_CENTER, cell, PX, 24, Color(0.0, 1.0, 0.0))
			cv.draw_string(font, p, chars[k], HORIZONTAL_ALIGNMENT_CENTER, cell, PX, Color(1.0, 1.0, 0.0))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))

	var qm := QuadMesh.new()
	qm.size = size * (CHAR_H * _sc / cell)
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), pos)
	_roots.append(root)
	_rest.append(pos)
	_kick.append(-1.0)
	var tex := vp.get_texture()
	for L in LAYERS + 2:
		var mat := ShaderMaterial.new()
		mat.shader = _glow() if L == LAYERS else SHADER
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("col", _col)
		mat.set_shader_parameter("idx0", float(idx0))
		mat.set_shader_parameter("count", m)
		mat.set_shader_parameter("cells", cells)
		mat.set_shader_parameter("texel", Vector2.ONE / size)
		mat.set_shader_parameter("t_char0", T_CHAR0)
		mat.set_shader_parameter("t_gap", T_GAP)
		mat.set_shader_parameter("t_write", T_WRITE)
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		if L < LAYERS:
			# 厚度层：最深的先画，越靠前越亮
			var dk := 1.0 - float(L) / float(LAYERS - 1)
			mat.set_shader_parameter("layer", 0)
			mat.set_shader_parameter("depth_k", dk)
			mi.position.z = -THICK * _sc * dk
			mat.render_priority = -10 + L
		elif L == LAYERS:
			mat.set_shader_parameter("layer", 1)
			mi.position.z = -0.02
			mat.render_priority = -4
		else:
			mat.set_shader_parameter("layer", 2)
			mat.render_priority = -3
		_mats.append(mat)
	for k in m:
		var c := rects[k].get_center()
		_centers[idx0 + k] = root.global_transform * Vector3((c.x / size.x - 0.5) * qm.size.x, (0.5 - c.y / size.y) * qm.size.y, 0.0)

	# 两道绕字盘旋的光痕：一正一反，椭圆轨道略微出离字面，有前后穿插的立体感
	var gi := _roots.size() - 1
	for j in 2:
		_orbits.append([gi, qm.size.x * 0.55, qm.size.y * 0.42, randf() * TAU + PI * j, 1.0 if j == 0 else -1.0, 0.5 + 0.3 * j])
		var tr := Trail3D.new()
		tr.width = 0.05 * _sc
		tr.lifetime = 0.5
		tr.min_px = 2.0
		tr.smooth = 3
		tr.taper = 0.8
		tr.point_fn = _orbit_point.bind(_orbits.size() - 1)
		tr.material_override = MeshLib.trail_material(Color.WHITE, _col, 0, 1.4)
		tr.emitting = true
		Vfx.root.add_child(tr)
		_trails.append(tr)


func _orbit_point(i: int) -> Vector3:
	var o: Array = _orbits[i]
	var root := _roots[int(o[0])]
	var a := float(o[3]) + float(o[4]) * ((1.0 - exp(-_t * 2.2)) * TAU * 1.3 + _t * 0.9)  # 先快后慢地绕
	var lp := Vector3(cos(a) * float(o[1]), sin(a) * float(o[2]) + 0.15 * sin(a * 2.0), sin(a * 1.5 + float(o[3])) * float(o[5]))
	return root.global_transform * lp


func _process(delta: float) -> void:
	if _over:
		return
	var dt := minf(delta / maxf(Engine.time_scale, 0.01), 0.05)
	_t += dt
	var out := clampf((_t - T_HOLD) / T_OUT, 0.0, 1.0)
	for m in _mats:
		m.set_shader_parameter("t", _t)
		m.set_shader_parameter("fade", out)
	# 出现时从镜头一侧轻轻推入落定，之后缓缓上浮
	var intro := 1.0 - exp(-_t * 9.0)
	for i in _roots.size():
		var r := _roots[i]
		# 盖印：组里每写成一个字，整组猛地一胀再砸回原大（0.14s 内），落定时略下沉回弹
		var st := 1.0
		if _stamp > 0.0 and _kick[i] >= 0.0:
			var k := _t - _kick[i]
			var u := clampf(k / 0.14, 0.0, 1.0)
			st = 1.0 + _stamp * (1.0 - u) * (1.0 - u) - 0.05 * _stamp * sin(clampf((k - 0.14) / 0.2, 0.0, 1.0) * PI)
		r.scale = Vector3.ONE * st
		r.global_position = _rest[i] + r.global_basis.z * 0.6 * _sc * (1.0 - intro) + Vector3.UP * 0.12 * _t
	while _done < _n and _t >= T_CHAR0 + T_GAP * _done + T_WRITE:
		_char_done(_done)
		_done += 1
	if not _scattered and _t >= T_HOLD:
		_scattered = true
		for c in _centers:
			Vfx.ribbon_burst(c, Vector3.UP, Color.WHITE.lerp(_col, 0.6), 10, 5.0, 160.0, 0.9, Vector3(0, 1.5, 0))
	for tr in _trails:
		tr.emitting = _t < T_HOLD + T_OUT * 0.5
	if _t >= T_HOLD + T_OUT + 0.05:
		_finish()


## 一个字写成：字心一颗十字星 + 一簇向上散开的光丝 + 一声轻响
func _char_done(i: int) -> void:
	var gi := mini(1 if i >= _half else 0, _kick.size() - 1)
	if gi >= 0:
		_kick[gi] = _t
	var c := _centers[i]
	Vfx.glint(c, Color.WHITE.lerp(_col, 0.3), 1.6)
	Vfx.ribbon_burst(c, Vector3.UP, Color.WHITE.lerp(_col, 0.5), 8, 6.0, 110.0, 0.7, Vector3(0, -1.5, 0))
	Sfx.play("swing", -15.0, 0.6 + 0.06 * i)


func _finish() -> void:
	_over = true
	for tr in _trails:
		if is_instance_valid(tr):
			tr.emitting = false
			get_tree().create_timer(tr.lifetime + 0.1).timeout.connect(func() -> void:
				if is_instance_valid(tr):
					tr.queue_free())
	_trails.clear()
	if _current == self:
		_current = null
	queue_free()
