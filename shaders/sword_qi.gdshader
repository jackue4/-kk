shader_type spatial;
// 结婴演出里的三种光（yuanying_cine.gd），都是一张竖着、面朝镜头的加色面片：
//   tip = 1    刀光：一道圆弧顶的巨大光幕，幕里是往下泻的细丝，弧边一道亮线、贴着金色的光屑，底下一团白光
//   taper = 1  天光：从云洞泻下来的一束金光，上窄下宽，边缘是虚的，里面有竖着的光丝和飘着的尘
//   都不是     光柱：剑气拖在身后的那一根，中线亮两边淡，光纹往上窜；wave > 0 时像火苗一样左右摆、忽粗忽细（空间在抖）
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.86, 1.0, 0.97);
uniform vec3 edge_col : source_color = vec3(0.16, 0.86, 0.78);
uniform vec3 spark : source_color = vec3(1.0, 0.85, 0.42);
uniform float power = 1.0;
uniform float flow = 6.0;
uniform float tip = 0.0;
uniform float taper = 0.0;
uniform float wave = 0.0;

// 整数哈希：格点的随机数必须一丝不差（原来用 sin 的写法，相邻两格算同一个格点会差出一点，放大后整片云碎成一块块多边形）
float hash2(vec2 p) {
	ivec2 q = ivec2(floor(p + 0.5));
	uint h = uint(q.x) * 374761393u + uint(q.y) * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return float(h & 65535u) / 65535.0;
}

// 兼容渲染器（网页 / 手机）：值噪声查贴图（fx/cine/cine_noise.png 的 G 通道，64 格一个周期，yuanying_cine.gd 设进来），
// 不在每个像素上现算——这些面片在特写里铺满半个屏幕，一个像素要取好几次。
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
uniform sampler2D noise_tex : repeat_enable, filter_linear;
float vnoise(vec2 p) {
	return textureLod(noise_tex, p * 0.015625, 0.0).g;
}
#else
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}
#endif

void fragment() {
	float v = 1.0 - UV.y;                    // 0 底 → 1 顶
	float sx = UV.x * 2.0 - 1.0;
	vec3 col;
	if (tip > 0.5) {
		float vv = max(v - 0.12, 0.0) / 0.88;
		float w = pow(max(1.0 - vv * vv, 0.0), 0.6);
		float x = abs(sx) / max(w, 0.0001);
		float inside = 1.0 - smoothstep(0.96, 1.0, x);
		float st = vnoise(vec2(sx * 26.0, v * 5.0 + TIME * flow * 0.35)) * 0.6 + vnoise(vec2(sx * 70.0, v * 11.0 + TIME * flow * 0.6)) * 0.4;
		st = pow(st, 2.2);
		float rimv = smoothstep(0.7, 0.97, x) * inside;
		float line = smoothstep(0.9, 0.975, x) * inside;
		float foot = pow(1.0 - clamp(v, 0.0, 1.0), 3.0) * pow(max(1.0 - abs(sx) * 1.4, 0.0), 2.0);
		col = edge_col * (0.16 + 1.1 * st) * inside * (0.55 + 0.45 * (1.0 - v)) + mix(edge_col, core, 0.6) * rimv * 0.55 + core * line * 0.9 + core * foot * 1.2;
		float sp = step(0.93, hash2(floor(vec2(sx * 90.0, v * 200.0 + TIME * flow * 3.0)))) * smoothstep(0.8, 0.97, x) * (1.0 - smoothstep(1.0, 1.22, x));
		col += spark * sp * 2.4;
		col *= smoothstep(0.0, 0.06, v);
	} else if (taper > 0.5) {
		float w = mix(1.0, 0.3, v);
		float x = abs(sx) / w;
		float body = pow(max(1.0 - x, 0.0), 1.3);
		float st = vnoise(vec2(sx / w * 7.0, 1.7)) * 0.6 + vnoise(vec2(sx / w * 19.0 + TIME * 0.05, v * 1.5)) * 0.4;
		float dust = step(0.992, hash2(floor(vec2(sx * 260.0, v * 640.0 - TIME * 4.0)))) * body;
		col = mix(edge_col, core, 0.35 + 0.4 * st) * body * (0.45 + 0.75 * st) + spark * dust * 1.5;
		col *= smoothstep(0.0, 0.08, v) * (1.0 - smoothstep(0.9, 1.0, v));
	} else {
		float sway = (vnoise(vec2(v * 9.0 - TIME * flow * 0.35, 2.7)) - 0.5) * 0.9 * wave * smoothstep(0.02, 0.3, v);
		float pinch = mix(1.0, 0.45 + 0.85 * vnoise(vec2(v * 6.0 - TIME * flow * 0.5, 9.1)), wave);
		float x = abs(sx + sway) / max(0.62 * pinch, 0.05);
		float body = 1.0 - smoothstep(0.4, 1.0, x);
		float corel = pow(1.0 - clamp(x, 0.0, 1.0), 2.4);
		float n = vnoise(vec2(UV.x * 7.0, v * 24.0 - TIME * flow)) * 0.6 + vnoise(vec2(UV.x * 19.0, v * 66.0 - TIME * flow * 1.7)) * 0.4;
		col = mix(edge_col, core, corel) * (0.45 + 0.8 * n) * body + core * corel * 0.55;
		float sp = step(0.95, hash2(floor(vec2(UV.x * 44.0, v * 240.0 - TIME * flow * 5.0)))) * smoothstep(0.45, 0.9, x) * (1.0 - smoothstep(0.95, 1.3, x));
		col += spark * sp * 2.2;
		col *= smoothstep(0.0, 0.05, v) * (1.0 - smoothstep(0.82, 1.0, v));
	}
	ALBEDO = col * power;
}
