shader_type spatial;
// 主城「关卡入口」那排拱门的门心（hub_hall.gd）：一面竖着的面片，拱形（上圆下方），里面是慢慢翻涌的一色灵光——
// 开着的门亮、往中间聚成一团白；没开的门（locked）压成灰蓝、暗着，几乎不动。
// 噪声查 fx/cine/cine_noise.png（R / B 分形噪声），一共两次采样，手机上便宜。
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 col_a : source_color = vec3(0.3, 0.9, 0.5);     // 主色
uniform vec3 col_b : source_color = vec3(0.9, 1.0, 0.8);     // 亮处
uniform float locked = 0.0;

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);      // x -1..1，y 0 底 → 1 顶
	// 拱形：下面七成是直的，上面收成半圆
	float arch = p.y < 0.68 ? abs(p.x) : length(vec2(p.x, (p.y - 0.68) / 0.32));
	if (arch > 1.0) {
		discard;
	}
	float t = TIME * mix(0.5, 0.06, locked);
	float n1 = texture(noise_tex, vec2(p.x * 0.20 + 0.3, p.y * 0.26 - t * 0.05)).r;
	float n2 = texture(noise_tex, vec2(p.x * 0.42 - t * 0.03, p.y * 0.5 - t * 0.09) + vec2(0.57, 0.11)).b;
	float glow = smoothstep(0.30, 0.78, n1 * 0.6 + n2 * 0.6);
	float core = 1.0 - smoothstep(0.0, 0.9, length(vec2(p.x, (p.y - 0.42) * 1.25)));
	vec3 c = mix(col_a * 0.42, col_a, glow) + col_b * (core * core * 0.75 + glow * glow * 0.3);
	c *= 0.7 + 0.3 * smoothstep(1.0, 0.82, arch);              // 贴着门框暗一点
	vec3 dull = vec3(0.30, 0.34, 0.42) * (0.55 + 0.6 * glow);  // 没开：灰蓝
	c = mix(c, dull, locked);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = c;
#else
	ALBEDO = pow(c, vec3(2.2));
#endif
}
