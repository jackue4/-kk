// 方块世界（搜打撤大世界，见 scripts/block_world.gd）的地表 + 点缀物：一块地一个网格、一次绘制调用。
// 颜色全在顶点色里（生成时已经烘进：格子明暗抖动、墙根 / 夹角的压暗、灯火照亮的一圈），这里只做：
// · 低分辨率贴图的感觉：按 1 米方格给明暗加一点噪点，近处再叠一层 25 厘米的像素颗粒，方块接缝处压一道暗边
// · 顶点色 alpha = 自发光强度（水面 / 血池 / 晶体 / 灯），配合辉光出氛围
// · 补光（fill_col）：不受影子影响、从背着日头的那一侧来的一层光。暗的区域靠它保证影子里看得清地面、分得出面的朝向
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;   // 包裹漫反射：明暗交界柔一点

uniform float emis = 2.0;
uniform float grain = 0.09;
uniform float pixel = 0.075;
// 下面四个颜色都是线性值，由 raid_manager.gd 按区域设进来（不标 source_color：两种渲染器对它的处理不一样，自己转最稳）
// 半球补光：朝上的面染一点天色、朝下 / 侧面染一点地面的反光，背光面不会一片死色（很便宜，手机上也开着）
uniform vec3 hemi_sky = vec3(1.0, 1.0, 1.0);
uniform vec3 hemi_ground = vec3(0.67, 0.67, 0.75);
uniform vec3 fill_col = vec3(0.0, 0.0, 0.0);      // 亮的区域是 0
uniform vec3 fill_dir = vec3(0.0, 1.0, 0.0);

varying vec3 wp;
varying vec3 wn;

// 2026-11-23 神识一扫的地形光波（参数和画法在这个文件里；不扫的时候 ss_look.x = 0，下面整段跳过）
#include "res://shaders/shenshi_wave.gdshaderinc"

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
	// 近处的像素颗粒：46 米外淡没（再远一个颗粒不到一个像素，留着只会闪）
	float near = clamp(1.0 + VERTEX.z / 46.0, 0.0, 1.0);
	float g2 = hash3(floor(q * 4.0) + vec3(17.0, 5.0, 11.0));
	float tex = 1.0 + (g - 0.5) * 2.0 * grain + (g2 - 0.5) * 2.0 * pixel * near;
	vec3 f = fract(q / vec3(2.0, 1.0, 2.0));
	vec3 an = abs(wn);
	float e = max(max(step(0.94, f.x) * (1.0 - an.x), step(0.94, f.z) * (1.0 - an.z)), step(0.9, f.y) * (1.0 - an.y));
	// k：乘在底色上的系数；glow：自发光是底色的多少倍（都是线性空间里的倍数）
	vec3 k = mix(hemi_ground, hemi_sky, wn.y * 0.5 + 0.5) * (tex * (1.0 - 0.1 * e));
	vec3 glow = vec3(clamp(COLOR.a, 0.0, 1.0) * emis) + k * fill_col * (0.62 + 0.38 * dot(wn, fill_dir));
	// 顶点色是 sRGB。开着 MSAA 时三角形边缘的插值会外推出负数，pow 负数 = NaN（画面上是黑心 + 一大团白晕），先夹住
	vec3 c = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// 兼容渲染器（网页 / 手机）：ALBEDO、EMISSION 要按 sRGB 写，引擎随后自己转成线性。顶点色本来就是 sRGB，只把倍数换算过去。
	// 2026-11-20 之前这里和下面一样先 pow(…, 2.2)，等于转了两次：网页上整个地表比桌面暗得多、艳得多，暗的区域近乎全黑。
	ALBEDO = c * pow(k, vec3(0.4545));
	EMISSION = c * pow(glow, vec3(0.4545));
	if (ss_look.x > 0.001) {
		EMISSION += shenshi_wave(wp, TIME);
	}
#else
	vec3 base = pow(c, vec3(2.2));
	ALBEDO = base * k;
	EMISSION = base * glow;
	if (ss_look.x > 0.001) {
		vec3 sw = shenshi_wave(wp, TIME);
		EMISSION += sw * sw * 1.6;      // sRGB → 大致的线性（平方），桌面有辉光，略提一点
	}
#endif
	ROUGHNESS = 1.0;
}
