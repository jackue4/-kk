extends Node3D
## 战斗字（弹反 / 破防 / 斩 / 架势崩溃 / 被弹开）：取代原来屏幕中部的平面 banner，
## 用技能题字（skill_calligraphy.gd）同一套发光毛笔字做法——SubViewport 里用行楷写好字，贴到几层面片上
## （skill_calligraphy.gdshader：后几层压暗错开叠出字身厚度、一层加色外发光、最前一层 HDR 近白字面）——
## 立在角色身边的场景空间里。和技能题字不同的是节奏与冲击：
## · 一行横排、字字错落；整组正对出字那一刻的镜头再侧转一点（看得出字身厚度），之后固定在世界里；
## · 从 1+SLAM 倍大小、离镜头更近处猛砸回原位（T_SLAM 内加速落下），落定瞬间身后炸开光环、
##   一圈放射状光线、一闪点光，字身短促震颤；笔势极快地写出（全句约 0.2s）；
## · 停留到 T_HOLD 后噪声消散、边缘烧成主色、光丝上飘；
## · 关掉深度测试，永远盖在角色、剑光之上，不会被身体挡住。
## 时间按真实时间走（不受顿帧 / 慢动作影响）。同一时间通常只留一个：新字出来时旧字立即消散；
## 但若旧字还在砸落 / 书写（STACK 秒内，如弹反当帧又破防），新字叠在旧字上方，两个都看得到。
## 故意不写 class_name：用 preload 引用。

const Calligraphy := preload("res://scripts/skill_calligraphy.gd")
const Banner := preload("res://scripts/realm_banner.gd")
const PX := 200             # 贴图里的字号
const CELL := 1.1           # 字格 = 字号 × CELL
const STEP := Vector2(0.84, 0.16)  # 横排：下一个字相对上一个右移、略下沉（按字格）
const PAD := 40.0
const CHAR_H := 1.2         # 场景里一个字格多高（米）
const LAYERS := 4           # 字身厚度层数
const THICK := 0.16         # 字身厚度（米）
const TURN := 0.3           # 正对镜头之后再侧转的角度（露出厚度）
const ROLL := 0.07          # 整行微微倾斜
const T_CHAR0 := 0.02
const T_GAP := 0.05
const T_WRITE := 0.1
const T_SLAM := 0.11        # 砸落用时
const SLAM := 1.3           # 砸落起始放大倍数 = 1 + SLAM
const SLAM_NEAR := 1.4      # 砸落起点离镜头更近多少米
const T_HOLD := 1.3
const INK := Color(0.035, 0.03, 0.04)  # 墨晕 / 字身厚度压暗用的墨色
const T_OUT := 0.45
const STACK := 0.35

static var _font: Font
static var _shaders: Array[Shader] = []  # [字身 / 字面, 外发光]：题字 shader 关掉深度测试的版本
static var _current = null
static var _side := 1.0                   # 侧转方向，每次换边

var _t := 0.0
var _col := Color.WHITE
var _n := 0
var _sc := 1.0
var _mats: Array[ShaderMaterial] = []
var _root: Node3D
var _rest := Vector3.ZERO
var _to_cam := Vector3.BACK
var _centers: Array[Vector3] = []
var _size := Vector2.ONE                  # 面片尺寸（米）
var _done := 0
var _landed := false
var _scattered := false


## 在 anchor 处立起 3D 战斗字 text（不含空格），col 为主色，size_k 整体放大（"斩"这类单字用大一号）
static func pop(text: String, anchor: Vector3, col: Color, size_k := 1.0) -> Node3D:
	text = text.replace(" ", "")
	if text.is_empty() or Vfx.root == null:
		return null
	if is_instance_valid(_current):
		if _current._t < STACK:
			# 旧字还在砸落 / 书写：两个字左右错开并排（旧字往镜头左侧让，新字落在右侧略低），都看得到
			var cam := Vfx.root.get_viewport().get_camera_3d()
			var right := cam.global_basis.x if cam != null else Vector3.RIGHT
			right = Vector3(right.x, 0.0, right.z).normalized()
			var wn := CHAR_H * size_k * (1.0 + STEP.x * (text.length() - 1))
			var shift := (float(_current._size.x) + wn) * 0.42
			var old: Node3D = _current
			old.create_tween().tween_property(old, "global_position", old.global_position - right * shift, 0.12) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			anchor = old.global_position + right * shift + Vector3.DOWN * 0.3
		else:
			_current.hurry()
	if _font == null:
		_font = Banner._load_font()
	var w := new()
	w._sc = size_k
	Vfx.root.add_child(w)
	w._setup(text.left(4), anchor, col)
	_current = w
	return w


static func _shader(glow: bool) -> Shader:
	if _shaders.is_empty():
		for g: bool in [false, true]:
			var s := Shader.new()
			var code := Calligraphy.SHADER.code.replace("depth_draw_never", "depth_draw_never, depth_test_disabled")
			s.code = code.replace("blend_mix", "blend_add") if g else code
			_shaders.append(s)
	return _shaders[1 if glow else 0]


## 立即转入消散
func hurry() -> void:
	if _t < T_HOLD:
		_t = T_HOLD
		_done = _n


func _setup(text: String, anchor: Vector3, col: Color) -> void:
	_col = col
	_n = text.length()
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else anchor + Vector3.BACK * 6.0
	var d := cam_pos - anchor
	_to_cam = d.normalized() if d.length_squared() > 1e-4 else Vector3.BACK
	var flat := Vector3(_to_cam.x, 0.0, _to_cam.z)
	flat = flat.normalized() if flat.length_squared() > 1e-4 else Vector3.BACK
	_side = -_side
	var z := (Basis(Vector3.UP, TURN * _side) * flat).normalized()
	_rest = anchor
	global_position = anchor

	# 一行字的贴图：每字一个字格，手写式的错位与倾斜；R = 字芯，G = 外扩一圈的字形
	var cell := float(PX) * CELL
	var size := Vector2(cell * (1.0 + STEP.x * (_n - 1)), cell * (1.0 + STEP.y * (_n - 1))) + Vector2.ONE * PAD * 2.0
	var vp := SubViewport.new()
	vp.size = Vector2i(ceili(size.x), ceili(size.y))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var rects: Array[Rect2] = []
	var rots := PackedFloat32Array()
	var cells := PackedVector4Array()
	for k in 4:
		if k < _n:
			var p := Vector2(PAD, PAD) + STEP * cell * float(k) + Vector2(randf_range(-8.0, 8.0), randf_range(-10.0, 10.0))
			var r := Rect2(p, Vector2(cell, cell))
			rects.append(r)
			rots.append(randf_range(-0.14, 0.08))
			cells.append(Vector4(r.position.x / size.x, r.position.y / size.y, r.size.x / size.x, r.size.y / size.y))
		else:
			cells.append(Vector4(0.0, 0.0, 1.0, 1.0))
	var cv := Control.new()
	cv.size = size
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(cv)
	var font := _font
	var chars := text
	var m := _n
	cv.draw.connect(func() -> void:
		var base := (font.get_ascent(PX) - font.get_descent(PX)) * 0.5
		for k in m:
			cv.draw_set_transform(rects[k].get_center(), rots[k], Vector2.ONE)
			var p := Vector2(-cell * 0.5, base)
			cv.draw_string_outline(font, p, chars[k], HORIZONTAL_ALIGNMENT_CENTER, cell, PX, 24, Color(0.0, 1.0, 0.0))
			cv.draw_string(font, p, chars[k], HORIZONTAL_ALIGNMENT_CENTER, cell, PX, Color(1.0, 1.0, 0.0))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))

	var qm := QuadMesh.new()
	_size = size * (CHAR_H * _sc / cell)
	qm.size = _size
	_root = Node3D.new()
	add_child(_root)
	_root.global_transform = Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z).rotated(z, -ROLL * _side), anchor)
	var tex := vp.get_texture()
	for L in range(-1, LAYERS + 2):
		var mat := ShaderMaterial.new()
		mat.shader = _shader(L == LAYERS)
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("col", _col.lerp(INK, 0.6) if L < LAYERS else _col)
		mat.set_shader_parameter("idx0", 0.0)
		mat.set_shader_parameter("count", _n)
		mat.set_shader_parameter("cells", cells)
		mat.set_shader_parameter("texel", Vector2.ONE / size)
		mat.set_shader_parameter("t_char0", T_CHAR0)
		mat.set_shader_parameter("t_gap", T_GAP)
		mat.set_shader_parameter("t_write", T_WRITE)
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)
		# 不做深度测试，靠 render_priority 定先后：墨晕衬底 → 厚度层由深到浅 → 外发光 → 字面
		if L < 0:
			# 墨晕：外发光同款模糊字形，但用普通混合、染成近黑，浅色场景里也压得住字
			mat.set_shader_parameter("layer", 1)
			mat.set_shader_parameter("col", INK)
			mi.position.z = -THICK * _sc - 0.03
			mi.scale = Vector3.ONE * 1.04
			mat.render_priority = 99
		elif L < LAYERS:
			var dk := 1.0 - float(L) / float(LAYERS - 1)
			mat.set_shader_parameter("layer", 0)
			mat.set_shader_parameter("depth_k", dk)
			mi.position.z = -THICK * _sc * dk
			mat.render_priority = 100 + L
		elif L == LAYERS:
			mat.set_shader_parameter("layer", 1)
			mi.position.z = -0.02
			mat.render_priority = 100 + LAYERS
		else:
			mat.set_shader_parameter("layer", 2)
			mat.render_priority = 101 + LAYERS
		_mats.append(mat)
	for k in _n:
		var c := rects[k].get_center()
		_centers.append(_root.transform * Vector3((c.x / size.x - 0.5) * qm.size.x, (0.5 - c.y / size.y) * qm.size.y, 0.0))
	_place(0.0)


## 摆位（相对 _rest 的局部量都随整组一起动）：砸落 → 震颤 → 缓缓上浮
func _place(t: float) -> void:
	var u := clampf(t / T_SLAM, 0.0, 1.0)
	var e := u * u  # 加速砸下
	var s := 1.0 + SLAM * (1.0 - e)
	var off := _to_cam * SLAM_NEAR * (1.0 - e)
	if u >= 1.0:
		# 落定：先压扁一下再弹回，伴随衰减的抖动
		var k := t - T_SLAM
		s *= 1.0 - 0.08 * exp(-k * 18.0) * cos(k * 40.0)
		var amp := 0.07 * _sc * exp(-k * 14.0)
		off = Vector3(sin(k * 97.0), cos(k * 83.0), 0.0) * amp + Vector3.UP * 0.22 * maxf(k - 0.2, 0.0)
	_root.scale = Vector3.ONE * s
	_root.position = off


func _process(delta: float) -> void:
	var dt := minf(delta / maxf(Engine.time_scale, 0.01), 0.05)
	_t += dt
	var out := clampf((_t - T_HOLD) / T_OUT, 0.0, 1.0)
	for m in _mats:
		m.set_shader_parameter("t", _t)
		m.set_shader_parameter("fade", out)
	_place(_t)
	if not _landed and _t >= T_SLAM:
		_landed = true
		_land()
	while _done < _n and _t >= T_CHAR0 + T_GAP * _done + T_WRITE:
		var c := global_transform * _centers[_done]
		Vfx.glint(c, Color.WHITE.lerp(_col, 0.3), 0.9 * _sc)
		Vfx.ribbon_burst(c, Vector3.UP, Color.WHITE.lerp(_col, 0.5), 6, 6.0, 120.0, 0.55, Vector3(0, -2.0, 0))
		_done += 1
	if not _scattered and _t >= T_HOLD:
		_scattered = true
		for c in _centers:
			Vfx.ribbon_burst(global_transform * c, Vector3.UP, Color.WHITE.lerp(_col, 0.6), 8, 4.5, 150.0, 0.8, Vector3(0, 1.5, 0))
	if _t >= T_HOLD + T_OUT + 0.05:
		if _current == self:
			_current = null
		queue_free()


## 落定那一下：身后光环 + 放射状光线 + 一闪点光
func _land() -> void:
	var c := global_position
	var r := maxf(_size.x, _size.y) * 0.5
	Vfx.halo(c - _to_cam * 0.2, _to_cam, _col, r * 0.75, 0.35)
	Vfx._burst_lines(c, 14, Color.WHITE.lerp(_col, 0.35), r * 0.9, 0.05 * _sc, r * 0.8, 0.26)
	Vfx.flash_light(c + _to_cam * 0.8, _col, 5.0, 6.0 * _sc, 0.3)
