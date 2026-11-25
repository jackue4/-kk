// 境界光环特效 · 环带（scripts/realm_halo.gd）。画在环形网格上：UV.x = 沿环一圈 0~1（0 在正上方），UV.y = 从内沿到外沿 0~1。
// 所以不用逐像素算极坐标，只有环带那一圈像素要画。style：
//   0 光线：一道细亮线 + 两侧柔光，上面有流光在跑（炼气的白环、绕身的光轨）
//   1 实环：两道亮边夹着环身，环身上刻着交织的绳纹（筑基的玉环、结丹 / 炼虚 / 合体的金环、元婴的紫金环）
//   2 符文圈：内外两道细线，中间一格一格的符文在亮（大乘）
//   3 断环：一段一段的弧刃，一头宽一头尖（化神的碎环）
//   4 云气：一缕缕流动的雾（炼气绕身的云气）
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/realm_halo_inc.gdshaderinc"

uniform int style = 0;
uniform vec3 col_a = vec3(1.0);           // 环身 / 线的颜色
uniform vec3 col_b = vec3(1.0, 0.85, 0.5);   // 亮边 / 花纹的颜色
uniform float count = 24.0;               // 花纹 / 符文 / 弧刃的个数
uniform float flow = 0.3;                 // 流光跑多快（圈 / 秒）
uniform float solid = 0.0;                // 环身多实（0 = 纯光）
uniform float reveal = 1.0;               // 展开：从正上方往两边画出来
uniform float rear = 1.0;                 // 从背面（镜头在人身后）看时的强度
uniform float seed = 0.0;

void vertex() {
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	POSITION = halo_clip(vp, vn, PROJECTION_MATRIX);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float dv = abs(v - 0.5) * 2.0;        // 0 环带中线，1 边沿
	// c 本色、cov 盖住的范围、op 多实、g 额外加的光（流光）。亮边是盖在环身上的，不是加上去的
	vec3 c = col_a;
	float cov = 0.0;
	float op = 0.0;
	float g = 0.0;
	float shine = pow(max(sin((u - TIME * flow) * 6.2831 * 2.0 + seed), 0.0), 10.0);      // 沿环跑的两段流光
	if (style == 0) {
		float line = exp(-pow(dv / 0.18, 2.0));
		float haze = exp(-dv * 3.0) * 0.3;
		float breathe = 0.85 + 0.15 * sin(TIME * 1.7 + u * 12.566);
		c = mix(col_a, col_b, line * 0.6);
		cov = clamp(line * breathe + haze, 0.0, 1.0);
		op = line * solid;
		g = shine * line * 0.8;
	} else if (style == 1) {
		cov = smoothstep(1.0, 0.86, dv);
		float edge = smoothstep(0.6, 0.76, dv);
		// 绳纹：两股正弦线交织
		float w = sin(u * 6.2831 * count);
		float s1 = exp(-pow((v - 0.5 - 0.17 * w) / 0.07, 2.0));
		float s2 = exp(-pow((v - 0.5 + 0.17 * w) / 0.07, 2.0));
		float knot = max(s1, s2) * smoothstep(0.62, 0.5, dv);
		float lit = 0.7 + 0.3 * (1.0 - v);          // 外沿暗一点、内沿亮一点，有点厚度
		c = mix(col_a * lit, col_b, clamp(edge + knot * 0.75, 0.0, 1.0));
		c = mix(c, vec3(1.0), shine * 0.55);
		op = solid;
	} else if (style == 2) {
		float rails = exp(-pow((dv - 0.9) / 0.06, 2.0));
		float cell = floor(u * count);
		vec2 f = vec2(fract(u * count), v);
		float glyph = 0.0;
		for (int i = 0; i < 4; i++) {
			float h1 = halo_hash(cell * 7.13 + float(i) * 1.7 + seed);
			float h2 = halo_hash(cell * 3.71 + float(i) * 5.3 + seed);
			float h3 = halo_hash(cell * 9.17 + float(i) * 2.9 + seed);
			vec2 cc = vec2(0.28 + 0.44 * h1, 0.3 + 0.4 * h2);
			vec2 d = abs(f - cc);
			// 横画或竖画
			float bar = h3 > 0.5 ? step(d.x, 0.2) * exp(-pow(d.y / 0.04, 2.0)) : step(d.y, 0.17) * exp(-pow(d.x / 0.055, 2.0));
			glyph = max(glyph, bar);
		}
		glyph *= step(0.12, f.x) * step(f.x, 0.88);
		float blink = 0.65 + 0.35 * sin(TIME * 2.3 + cell * 1.9);
		c = mix(col_a, col_b, rails);
		cov = clamp(rails + glyph * blink, 0.0, 1.0);
		op = solid;
		g = shine * rails * 0.6;
	} else if (style == 3) {
		float fu = fract(u * count + seed);
		float body_u = smoothstep(0.0, 0.05, fu) * smoothstep(0.86, 0.8, fu);
		float half = mix(0.22, 1.0, pow(1.0 - fu / 0.86, 0.8));       // 一头宽一头尖
		cov = body_u * smoothstep(half, half - 0.1, dv);
		float edge = smoothstep(half - 0.34, half - 0.16, dv);
		float facet = 0.62 + 0.38 * step(0.5, v);                     // 晶体的两个面一明一暗
		float pat = 0.5 + 0.5 * sin(fu * 60.0);
		c = mix(col_a * facet * (0.8 + 0.2 * pat), col_b, edge);
		c = mix(c, vec3(1.0), shine * 0.5);
		op = solid;
	} else {
		float band = exp(-pow(dv / 0.55, 2.0));
		float wisp = 0.5 + 0.5 * sin((u * count - TIME * flow * 6.0) * 6.2831 + v * 5.0 + seed);
		float wisp2 = 0.5 + 0.5 * sin((u * (count * 0.5 + 1.0) + TIME * flow * 3.0) * 6.2831 - v * 3.0);
		cov = band * wisp * wisp * (0.35 + 0.65 * wisp2);
	}
	// 展开：u = 0 在正上方，往两边画
	float side = min(u, 1.0 - u) * 2.0;
	float shown = smoothstep(reveal * 1.08, reveal * 1.08 - 0.08, side);
	float k = power * shown * mix(1.0, rear, float(FRONT_FACING));
	vec3 p = (c * cov + col_b * g) * k;
	float a = cov * op * k;
	ALBEDO = halo_albedo(p, a);
	ALPHA = a;
}
