shader_type spatial;
// 元婴脑后的光轮（yuanying_cine.gd）：几道流动的细环、环里一团柔光、贴着环往外放的细光芒；
// burst > 0 时再叠一片铺满整张面片的金色背光（全景镜头里从身后炸开的那一片）。加色。
// 面片比光轮大得多（留给金色背光用）：radius 是环的半径占面片半宽的比例。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.5, 1.0, 0.92);
uniform vec3 gold : source_color = vec3(1.0, 0.78, 0.36);
uniform float power = 1.0;
uniform float ring = 1.0;
uniform float rays = 1.0;
uniform float burst = 0.0;
uniform float open = 1.0;       // 环从中心张开到位
uniform float radius = 0.42;

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
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 dir = p / max(r, 0.0001);
	float rr = radius * open;
	float wd = radius * 0.03;
	float ringv = (1.0 - smoothstep(0.0, wd, abs(r - rr))) + (1.0 - smoothstep(0.0, wd * 0.5, abs(r - rr * 1.09))) * 0.55
			+ (1.0 - smoothstep(0.0, wd * 0.45, abs(r - rr * 0.93))) * 0.3;
	ringv *= 0.7 + 0.5 * vnoise(dir * 5.0 + vec2(TIME * 0.7, -TIME * 0.4));
	float glowv = (1.0 - smoothstep(0.0, rr, r)) * 0.3 + (1.0 - smoothstep(rr, rr * 1.5, r)) * 0.14;
	// 光芒要细、要疏：贴着环往外放一小段，不能盖过脸
	float ra = pow(vnoise(dir * 24.0 + 2.0), 12.0) * 3.0 + pow(vnoise(dir * 60.0 + vec2(TIME * 0.15, 5.0)), 16.0) * 3.0;
	float rayv = ra * smoothstep(rr * 0.5, rr * 1.0, r) * (1.0 - smoothstep(rr * 1.1, rr * 2.6, r));
	vec3 col = tint * (ringv * 1.2 * ring + glowv * 0.6) + mix(tint, vec3(1.0), 0.45) * rayv * rays * 0.2;
	if (burst > 0.001) {      // 金色背光只在全景那几秒才有，平时不算
		float b = pow(vnoise(dir * 9.0 + 9.0), 2.0) * (1.0 - smoothstep(0.0, 1.0, r)) * 1.5
				+ pow(vnoise(dir * 30.0 + vec2(4.0, TIME * 0.1)), 5.0) * (1.0 - smoothstep(0.0, 0.9, r)) * 2.2
				+ (1.0 - smoothstep(0.0, rr * 1.7, r)) * 0.8;
		col += gold * b * burst;
	}
	ALBEDO = col * power * (1.0 - smoothstep(0.88, 1.0, r));
}
