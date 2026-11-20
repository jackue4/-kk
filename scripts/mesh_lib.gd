class_name MeshLib
extends RefCounted
## 程序化占位模型与共享资源（飞剑、噪声贴图、拖尾材质）。

const TRAIL_SHADER := preload("res://shaders/trail.gdshader")

static var _blade: ArrayMesh
static var _noise: NoiseTexture2D
static var _vc_mode := -1


## 顶点色 / 实例色该存成什么（col 是按屏幕上想看到的颜色写的）。
## 桌面的渲染器把着色器里的 ALBEDO 当线性色用，所以要先转成线性再存；兼容渲染器（网页 / 手机）把 ALBEDO 当 sRGB 用、
## 自己再转线性，这时候还先转一遍就是压了两次暗（2026-11-20 之前网页上的主角、方块怪、碎块都比桌面暗、比桌面艳，就是这个原因）。
## 凡是「顶点色直接当 ALBEDO」的网格都从这里过，两边看到的才是同一个颜色。
static func vcol(col: Color) -> Color:
	if _vc_mode < 0:
		_vc_mode = 0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1
	return col.srgb_to_linear() if _vc_mode == 1 else col


static func noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.02
		fn.fractal_octaves = 3
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.noise = fn
	return _noise


## col_a 线芯（头部最亮处）、col_b 线身。intensity 保持在 1 附近：线靠"细而清楚"而不是靠过曝
static func trail_material(col_a: Color, col_b: Color, style: int, intensity := 1.15) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TRAIL_SHADER
	m.set_shader_parameter("color_a", col_a)
	m.set_shader_parameter("color_b", col_b)
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("noise_tex", noise_tex())
	return m


static func std_mat(col: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


## 剑身：菱形截面 + 收尖，沿 +Y 为剑尖。
static func blade_mesh() -> ArrayMesh:
	if _blade != null:
		return _blade
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var y0 := -0.25
	var y1 := 0.5
	var y2 := 0.72
	var w := 0.055
	var th := 0.014
	var r0: Array[Vector3] = [Vector3(w, y0, 0), Vector3(0, y0, th), Vector3(-w, y0, 0), Vector3(0, y0, -th)]
	var r1: Array[Vector3] = [Vector3(w * 0.85, y1, 0), Vector3(0, y1, th), Vector3(-w * 0.85, y1, 0), Vector3(0, y1, -th)]
	var tip := Vector3(0, y2, 0)
	for i in 4:
		var j := (i + 1) % 4
		st.add_vertex(r0[i]); st.add_vertex(r1[i]); st.add_vertex(r1[j])
		st.add_vertex(r0[i]); st.add_vertex(r1[j]); st.add_vertex(r0[j])
		st.add_vertex(r1[i]); st.add_vertex(tip); st.add_vertex(r1[j])
	st.generate_normals()
	_blade = st.commit()
	return _blade


## 单刃弯刀刀身：三角截面（刀背厚、刀刃薄），刀身微弯，刃口在 +X，沿 +Y 为刀尖。
static func saber_blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var n := 10
	var y0 := -0.26
	var y1 := 0.8
	var rows: Array = []
	for i in n + 1:
		var t := float(i) / float(n)
		var y := lerpf(y0, y1, t)
		var bend := -0.07 * t * t                       # 刀背向后微弯
		var w := lerpf(0.085, 0.062, t)
		if t > 0.82:
			w *= 1.0 - (t - 0.82) / 0.18 * 0.98          # 刀尖斜收
		var th := lerpf(0.02, 0.012, t)
		var back := bend - w * 0.4
		var edge := bend + w * 0.6 + (0.0 if t <= 0.82 else -(t - 0.82) * 0.25)
		rows.append([Vector3(back, y, th), Vector3(edge, y, 0.0), Vector3(back, y, -th)])
	for i in n:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		for k in 3:
			var j := (k + 1) % 3
			st.add_vertex(a[k]); st.add_vertex(b[k]); st.add_vertex(b[j])
			st.add_vertex(a[k]); st.add_vertex(b[j]); st.add_vertex(a[j])
	st.generate_normals()
	return st.commit()


## 刀客的弯刀：暗钢刀身 + 圆镡 + 长柄（双手可握）。握把中心 y=-0.42，刀尖 y=0.8
static func make_saber(glow: Color) -> Node3D:
	var root := Node3D.new()
	var blade := MeshInstance3D.new()
	blade.mesh = saber_blade_mesh()
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.62, 0.64, 0.68)
	bm.metallic = 0.55
	bm.roughness = 0.28
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.emission_enabled = true
	bm.emission = glow
	bm.emission_energy_multiplier = 0.25
	blade.material_override = bm
	root.add_child(blade)
	root.set_meta("blade_mat", bm)
	var guard := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.06
	gm.bottom_radius = 0.06
	gm.height = 0.025
	gm.radial_segments = 12
	guard.mesh = gm
	guard.material_override = std_mat(Color(0.3, 0.22, 0.14), 0.5, 0.5)
	guard.position.y = -0.275
	root.add_child(guard)
	var grip := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = 0.28
	cm.radial_segments = 8
	grip.mesh = cm
	grip.material_override = std_mat(Color(0.45, 0.1, 0.1), 0.8)
	grip.position.y = -0.42
	root.add_child(grip)
	for c in root.get_children():
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## 组装一把飞剑。返回根节点，meta "blade_mat" 为剑身材质（用于换色）。
static func make_sword(glow: Color) -> Node3D:
	var root := Node3D.new()
	var blade := MeshInstance3D.new()
	blade.mesh = blade_mesh()
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.86, 0.9, 0.95)
	bm.metallic = 0.35
	bm.roughness = 0.3
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.emission_enabled = true
	bm.emission = glow
	bm.emission_energy_multiplier = 0.7
	blade.material_override = bm
	root.add_child(blade)
	root.set_meta("blade_mat", bm)

	var gold := std_mat(Color(0.85, 0.68, 0.32), 0.45, 0.6)
	var dark := std_mat(Color(0.16, 0.17, 0.2), 0.7)
	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.2, 0.035, 0.05)
	guard.mesh = gm
	guard.material_override = gold
	guard.position.y = -0.26
	root.add_child(guard)
	var grip := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.016
	cm.height = 0.2
	cm.radial_segments = 8
	grip.mesh = cm
	grip.material_override = dark
	grip.position.y = -0.375
	root.add_child(grip)
	var pommel := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 8
	sm.rings = 4
	pommel.mesh = sm
	pommel.material_override = gold
	pommel.position.y = -0.49
	root.add_child(pommel)
	for c in root.get_children():
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## 光剑：遁光时主角化成的剑。与飞剑同形，但整把只由一种自发光材质构成（没有金属剑身和木柄）。
## meta "blade_mat" 为这份材质（用于换色）。剑尖沿 +Y，剑尖 y=0.72，剑首 y≈-0.52
static func make_light_sword(glow: Color) -> Node3D:
	var root := make_sword(glow)
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.emission_enabled = true
	set_light_sword_color(m, glow)
	for c in root.get_children():
		(c as MeshInstance3D).material_override = m
	root.set_meta("blade_mat", m)
	return root


static func set_light_sword_color(m: StandardMaterial3D, glow: Color) -> void:
	m.albedo_color = Color.WHITE.lerp(glow, 0.35)
	m.emission = glow
	m.emission_energy_multiplier = 2.2
