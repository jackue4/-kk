extends RefCounted
## 画面定调（2026-11-23 画面专项）。用户原话：「视觉应当明亮、柔和、通透，具有温暖、梦幻的仙侠氛围。使用丰富的明暗与色彩变化，
## 避免过度曝光、灰白和荧光感」，并且「要注意考虑手机端的性能表现」。
## 改之前量到的（_tasks/look_20261123/look_probe.gd）：主城 / 草原的画面平均亮度 0.70 上下、平均饱和度 0.15~0.19，
## 两到五成的像素「又亮又没颜色」（亮度 > 0.72、饱和 < 0.12）——铺地和石墙是近白的灰，环境光又几乎和日光一样强，明暗拉不开。
## 这里放所有场景共用的两样东西，都不按像素多算什么（手机上等于白送）：
##   · 一张调色表（24³ 的三维查找表，挂在 Environment.adjustment_color_correction 上，引擎在最后那遍色调映射里顺手查一次）：
##       高光往下收一点、留出层次（不死白）；暗部染一点冷紫、亮部染一点暖杏（灰石头在日光下是奶白、在影子里是淡紫）；
##       不饱和的颜色多补一点鲜活度，本来就很艳又很亮的（门心、符文、水面的荧光色）反而收一点
##   · 辉光改成柔的滤色叠加：灯笼、晶体、门心周围一圈软晕，不再把亮处直接加爆
## 另有主城里飘的花瓣（一张 MultiMesh，位置全在顶点着色器里算，脚本每帧不碰它）。
## 各场景自己的日光 / 环境光 / 雾在各自的地方调（主城 hub_hall.gd 的 _build_env，大世界 raid_data.gd 的 REGIONS / LOOK）。
## 对照开关：命令行 `-- --no-grade` 不挂调色表（自检 / 截图对比用）。

const LUT_N := 24
## 鲜活度：不饱和的颜色最多把彩度放大到 1 + VIB 倍；饱和度 > CALM_FROM 又亮的收掉 CALM
const VIB := 0.42
const CALM := 0.2
const CALM_FROM := 0.72
## 分色：加在暗部 / 亮部上的偏色（屏幕色，量很小）
const SHADOW_TINT := Vector3(0.010, -0.004, 0.052)
const LIGHT_TINT := Vector3(0.040, 0.014, -0.036)
## 亮度曲线的控制点（输入亮度 0、0.2、…、1.0 对应的输出）：中间调基本不动，0.6 以上往下收，纯白落在 0.955
const CURVE := [0.0, 0.2, 0.392, 0.572, 0.748, 0.955]

static var _lut: ImageTexture3D
static var _petal_shader: Shader


static func enabled() -> bool:
	return not OS.get_cmdline_user_args().has("--no-grade")


## 一个屏幕色（sRGB）调完是什么颜色
static func grade(c: Color) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	var y := 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z
	var mx := maxf(v.x, maxf(v.y, v.z))
	var mn := minf(v.x, minf(v.y, v.z))
	var sat := 0.0 if mx < 0.0001 else (mx - mn) / mx
	# 鲜活度
	var k := 1.0 + VIB * (1.0 - sat) * (1.0 - sat) - CALM * smoothstep(CALM_FROM, 1.0, sat) * smoothstep(0.35, 0.7, y)
	v = Vector3(y, y, y) + (v - Vector3(y, y, y)) * k
	# 亮度曲线（按比例缩，色相不变）
	var t := clampf(y, 0.0, 1.0) * 5.0
	var i := mini(int(t), 4)
	var y2 := lerpf(float(CURVE[i]), float(CURVE[i + 1]), t - float(i))
	if y > 0.0001:
		v *= y2 / y
	# 分色
	var sh := (1.0 - y2) * (1.0 - y2)
	var hi := y2 * y2
	v += SHADOW_TINT * sh * smoothstep(0.0, 0.12, y2) + LIGHT_TINT * hi
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))


## 调色表：x / y / z = 输入的红 / 绿 / 蓝，每个格子存调完的颜色。只在第一次要的时候算一遍（一万多个格子，几十毫秒）
static func lut() -> Texture3D:
	if _lut != null:
		return _lut
	var n := LUT_N
	var slices: Array[Image] = []
	for b in n:
		var data := PackedByteArray()
		data.resize(n * n * 3)
		var bz := (float(b) + 0.5) / float(n)
		for g in n:
			var gy := (float(g) + 0.5) / float(n)
			for r in n:
				var o := grade(Color((float(r) + 0.5) / float(n), gy, bz))
				var at := (g * n + r) * 3
				data[at] = int(roundf(o.r * 255.0))
				data[at + 1] = int(roundf(o.g * 255.0))
				data[at + 2] = int(roundf(o.b * 255.0))
		slices.append(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, data))
	_lut = ImageTexture3D.new()
	_lut.create(Image.FORMAT_RGB8, n, n, n, false, slices)
	return _lut


## 给一个 Environment 挂上调色表、把辉光换成柔的。block_world.gd 的 make_environment 末尾调（主城、大世界共用）
static func apply(env: Environment) -> void:
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.62
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_luminance_cap = 2.6
	if not enabled():
		return
	env.adjustment_enabled = true
	env.adjustment_color_correction = lut()


## 主城里飘的花瓣：n 片粉色的小菱形，绕着镜头循环（镜头走到哪，周围都有），位置和翻转全在顶点着色器里按时间算
static func petals(n: int) -> MultiMeshInstance3D:
	if _petal_shader == null:
		_petal_shader = Shader.new()
		_petal_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 box = vec3(56.0, 22.0, 56.0);
varying vec3 tint;
void vertex() {
	vec4 c = INSTANCE_CUSTOM;                       // xyz = 0~1 的随机位置，w = 相位
	float t = TIME * (0.55 + 0.5 * c.w);
	vec3 p = c.xyz * box;
	p.y -= t * 1.5;                                 // 往下落
	p.x += sin(t * 0.7 + c.w * 40.0) * 2.2 + t * 0.9;   // 被风带着往东飘，左右荡
	p.z += cos(t * 0.5 + c.w * 23.0) * 1.8;
	vec3 cam = CAMERA_POSITION_WORLD;
	p = mod(p - cam, box) - box * 0.5 + cam;        // 绕着镜头循环
	float a = t * 2.4 + c.w * 60.0;                 // 翻转
	float b = t * 1.7 + c.w * 31.0;
	vec3 v = VERTEX;
	v = vec3(v.x * cos(a) + v.y * sin(a) * 0.4, v.y * cos(b) - v.x * sin(a) * 0.3, v.x * sin(a) * 0.8 + v.y * sin(b));
	// 离镜头太近的缩没（不糊脸），远处的略大一点（不然看不见）
	float d = length(p - cam);
	float s = smoothstep(1.5, 4.0, d) * (1.0 + d * 0.02);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p + v * s, 1.0));
	tint = mix(vec3(1.0, 0.72, 0.82), vec3(1.0, 0.90, 0.92), fract(c.w * 7.0));
}
void fragment() {
	if (abs(UV.x - 0.5) + abs(UV.y - 0.5) > 0.5) {
		discard;
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = tint;
#else
	ALBEDO = pow(tint, vec3(2.2));
#endif
}
"""
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(0.24, 0.3)
	mm.mesh = q
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	for i in n:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = _petal_shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-4000.0, -200.0, -4000.0), Vector3(8000.0, 600.0, 8000.0))     # 位置在着色器里算，包围盒给大，别被裁掉
	return mi
