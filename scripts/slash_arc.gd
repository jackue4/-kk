extends MeshInstance3D
## 挥砍剑光弧：每帧记录剑身上内、外两点，连成一条扫过的弧形带（世界空间）。
## 采样之间用 Catmull-Rom 细分，快刀下也是一条圆滑的弧而不是折线；整条快出快收，尾段在 shader 里碎成方块散掉。
## 挂在不移动的节点下。故意不写 class_name：用 preload 引用。

const SHADER := preload("res://shaders/slash_arc.gdshader")
const TEX_SHADER := preload("res://shaders/blade_trail_tex.gdshader")
## AI 生成的横向刀光贴图（_ref/blade_trail.jpg 图生图 → 抠透明底 → 裁成横条，见 _tasks/blade/）
const TEX_PATH := "res://fx/blade_trail/blade_trail.png"

static var _tex: Texture2D

var lifetime := 0.14
var emitting := false
var time_scale := 1.0  # 随顿帧一起定格
var inner_fn: Callable
var outer_fn: Callable

var _a := PackedVector3Array()
var _b := PackedVector3Array()
var _born := PackedFloat32Array()
var _im := ImmediateMesh.new()
var _time := 0.0
var _drawn := false


func _init() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_priority = 30


static func make_material(edge: Color, band: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("color_a", edge)
	m.set_shader_parameter("color_b", band)
	return m


## 贴图刀光材质：band 为境界色，只轻染贴图的中间调
static func make_tex_material(band: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TEX_SHADER
	m.set_shader_parameter("tex", blade_texture())
	m.set_shader_parameter("tint", band)
	return m


## 刀光贴图：已导入就走资源；新拷进来还没被编辑器导入时直接读 PNG（运行中的游戏不会自己导入）
static func blade_texture() -> Texture2D:
	if _tex == null:
		if FileAccess.file_exists(TEX_PATH + ".import"):
			_tex = load(TEX_PATH)
		else:
			var img := Image.load_from_file(TEX_PATH)
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				_tex = ImageTexture.create_from_image(img)
	return _tex


func set_colors(edge: Color, band: Color) -> void:
	var m := material_override as ShaderMaterial
	m.set_shader_parameter("color_a", edge)
	m.set_shader_parameter("color_b", band)
	m.set_shader_parameter("tint", band)


func clear() -> void:
	_a.clear()
	_b.clear()
	_born.clear()


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


func _process(dt: float) -> void:
	_time += dt * time_scale
	var cut := 0
	while cut < _born.size() and _time - _born[cut] > lifetime:
		cut += 1
	if cut > 0:
		_a = _a.slice(cut)
		_b = _b.slice(cut)
		_born = _born.slice(cut)

	if emitting and outer_fn.is_valid() and inner_fn.is_valid():
		var ob: Vector3 = outer_fn.call()
		var n0 := _b.size()
		if n0 == 0 or _b[n0 - 1].distance_squared_to(ob) > 0.0004:
			_a.append(inner_fn.call())
			_b.append(ob)
			_born.append(_time)

	var n := _b.size()
	if n < 2:
		if _drawn:
			_im.clear_surfaces()
			_drawn = false
		return
	_im.clear_surfaces()
	_drawn = true
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	# 从最新到最旧
	for i in range(n - 1, 0, -1):
		var i0 := mini(i + 1, n - 1)
		var i3 := maxi(i - 2, 0)
		var seg := int(clampf(_b[i].distance_to(_b[i - 1]) / 0.06, 1.0, 8.0))
		for s in seg:
			var t := float(s) / float(seg)
			var ob := _cr(_b[i0], _b[i], _b[i - 1], _b[i3], t)
			var ia := _cr(_a[i0], _a[i], _a[i - 1], _a[i3], t)
			var age := lerpf(_time - _born[i], _time - _born[i - 1], t)
			_vert(ia, ob, clampf(age / lifetime, 0.0, 1.0))
	_vert(_a[0], _b[0], clampf((_time - _born[0]) / lifetime, 0.0, 1.0))
	_im.surface_end()


func _vert(ia: Vector3, ob: Vector3, u: float) -> void:
	# 内沿随时间向外沿收拢一点；新月形的厚薄主要交给 shader（尾段要留出宽度给碎块）
	var inner := ob.lerp(ia, 1.0 - 0.4 * u)
	_im.surface_set_uv(Vector2(u, 0.0))
	_im.surface_add_vertex(inner)
	_im.surface_set_uv(Vector2(u, 1.0))
	_im.surface_add_vertex(ob)
