// 方块世界（搜打撤大世界，见 scripts/block_world.gd）的地表 + 点缀物：一块地一个网格、一次绘制调用。
// 颜色全在顶点色里（生成时已经烘进：格子明暗抖动、墙根 / 夹角的压暗、灯火照亮的一圈），这里只做：
// · 低分辨率贴图的感觉：按 1 米方格给明暗加一点噪点，方块接缝处压一道暗边
// · 顶点色 alpha = 自发光强度（水面 / 血池 / 晶体 / 灯），配合辉光出氛围
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float emis = 2.0;
uniform float grain = 0.09;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec3 q = wp - wn * 0.05;                 // 往方块里缩一点，面正好落在整数坐标上也不闪
	float g = hash3(floor(q));
	vec3 f = fract(q / vec3(4.0, 2.0, 4.0));
	vec3 an = abs(wn);
	float e = max(max(step(0.955, f.x) * (1.0 - an.x), step(0.955, f.z) * (1.0 - an.z)), step(0.93, f.y) * (1.0 - an.y));
	// 顶点色是 sRGB。开着 MSAA 时三角形边缘的插值会外推出负数，pow 负数 = NaN（画面上是黑心 + 一大团白晕），先夹住
	vec3 base = pow(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)), vec3(2.2));
	ALBEDO = base * (1.0 + (g - 0.5) * 2.0 * grain) * (1.0 - 0.13 * e);
	EMISSION = base * clamp(COLOR.a, 0.0, 1.0) * emis;
	ROUGHNESS = 1.0;
}
