// 境界光环特效 · 圆面（scripts/realm_halo.gd）。画在一张方片上，kind：
//   0 光核：中间一团柔光 + 一圈缓缓转的光芒（各档环心的光）
//   1 星门：深紫的夜空、旋臂、星点、亮核，整体慢慢转（化神）
//   2 元婴：一团光里蜷着的小人影，随呼吸明暗（元婴）
//   3 灵胎：半透明的一颗大珠子，边上实、中间透，里面有缓缓转的流纹（元婴的环心）
// 都不采贴图、不用噪声，手机上也便宜；而且只在觉醒那十几秒里画。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/realm_halo_inc.gdshaderinc"

uniform int kind = 0;
uniform vec3 col_a = vec3(1.0, 0.9, 0.7);      // 主色
uniform vec3 col_b = vec3(1.0);               // 亮处 / 核心的颜色
uniform float rays = 12.0;                    // 光芒条数（0 = 没有）
uniform float reveal = 1.0;
uniform float rear = 1.0;                     // 从背面（镜头在人身后）看时的强度：圆面正好挡着人，背面要淡
uniform float seed = 0.0;

float sd_ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	return (length(q) - 1.0) * min(r.x, r.y);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void vertex() {
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	POSITION = halo_clip(vp, vn, PROJECTION_MATRIX);
}

void fragment() {
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(q);
	float th = atan(q.x, q.y);
	vec3 p = vec3(0.0);
	float a = 0.0;
	if (kind == 0) {
		float core = exp(-r * r * 9.0);
		float haze = exp(-r * 2.6) * 0.5;
		float ray = 0.0;
		if (rays > 0.5) {
			float s = sin(th * rays + TIME * 0.35 + seed);
			float s2 = sin(th * (rays * 0.5 + 1.0) - TIME * 0.22);
			ray = pow(max(s, 0.0), 6.0) * (0.6 + 0.4 * s2) * exp(-r * 2.2) * smoothstep(0.05, 0.3, r);
		}
		float pulse = 0.88 + 0.12 * sin(TIME * 1.9 + seed);
		p = (col_b * core + col_a * (haze + ray * 0.9)) * pulse * smoothstep(1.0, 0.75, r);
	} else if (kind == 1) {
		float inside = smoothstep(1.0, 0.93, r);
		float sp = th + TIME * 0.22;
		// 两条对数螺旋的旋臂
		float arm = 0.5 + 0.5 * sin(2.0 * sp + 7.5 * log(r + 0.06));
		float arms = pow(arm, 3.0) * exp(-r * 2.4) * smoothstep(0.02, 0.2, r);
		float dust = (0.5 + 0.5 * sin(5.0 * sp - 11.0 * r)) * exp(-r * 1.6) * 0.25;
		float core = exp(-r * r * 60.0) + exp(-r * 7.0) * 0.6;
		// 星点：跟着慢转的格子
		float ca = cos(TIME * 0.05);
		float sa = sin(TIME * 0.05);
		vec2 sq = vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca) * 13.0;
		vec2 cell = floor(sq);
		vec2 f = fract(sq) - 0.5;
		float h = halo_hash2(cell + seed);
		vec2 off = vec2(halo_hash2(cell + 3.1), halo_hash2(cell + 7.7)) - 0.5;
		float star = step(0.78, h) * exp(-dot(f - off * 0.6, f - off * 0.6) * 90.0) * (0.55 + 0.45 * sin(TIME * (1.5 + h * 3.0) + h * 30.0));
		float rim = exp(-pow((r - 0.93) / 0.07, 2.0));
		vec3 sky = mix(vec3(0.16, 0.08, 0.38), vec3(0.46, 0.26, 0.74), smoothstep(0.9, 0.1, r));
		p = (sky * 0.75 + col_a * (arms * 1.3 + dust) + col_b * (core + star * 1.4)) * inside + col_a * rim * 0.8;
		a = inside * 0.86;
	} else if (kind == 3) {
		float inside = smoothstep(1.0, 0.97, r);
		float edge = pow(r, 2.5);
		float swirl = 0.5 + 0.5 * sin(th * 3.0 + r * 7.0 - TIME * 0.5 + seed);
		float hl = exp(-dot(q - vec2(-0.38, 0.46), q - vec2(-0.38, 0.46)) * 10.0);      // 左上一点高光
		a = inside * mix(0.42, 0.7, edge);
		p = (mix(col_a * 0.8, col_a, edge) * a + col_b * (swirl * 0.07 * (1.0 - edge) + hl * 0.16)) * inside;
	} else {
		// 蜷着的小人：头、身子、腿、手几个椭圆软软地并起来
		float d = sd_ellipse(q, vec2(-0.2, 0.3), vec2(0.29, 0.29));                    // 头（脸朝左）
		d = smin(d, sd_ellipse(q, vec2(0.17, 0.0), vec2(0.26, 0.4)), 0.1);            // 弓着的背
		d = smin(d, sd_ellipse(q, vec2(-0.06, -0.35), vec2(0.3, 0.16)), 0.1);         // 蜷上来的腿
		d = smin(d, sd_ellipse(q, vec2(-0.13, -0.05), vec2(0.15, 0.075)), 0.06);      // 抱在胸前的手
		float breathe = 0.9 + 0.1 * sin(TIME * 1.6 + seed);
		float body = smoothstep(0.02, -0.03, d);
		float glow = exp(-max(d, 0.0) * 7.0) * 0.55;
		float shade = 0.86 + 0.14 * smoothstep(-0.25, 0.0, d);          // 边上亮、里面柔
		float orb = smoothstep(0.98, 0.7, r);
		float orb_rim = exp(-pow((r - 0.9) / 0.05, 2.0)) * 0.7;
		p = (col_b * body * shade + col_a * (glow * 0.6 + orb * 0.12 + orb_rim * 0.8)) * breathe;
		a = body * 0.9 + orb * 0.3;
		p *= smoothstep(1.0, 0.95, r);
		a *= smoothstep(1.0, 0.95, r);
	}
	float k = power * smoothstep(0.0, 0.6, reveal) * mix(1.0, rear, float(FRONT_FACING));
	ALBEDO = halo_albedo(p * k, a * k);
	ALPHA = a * k;
}
