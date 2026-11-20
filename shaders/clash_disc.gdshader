// 飞剑对波 · 碰撞盘：一张面片，画两束能量迎头撞上后向四周溅开的样子 ——
// 中心一团白热、向外流的放射能量纹、一圈圈往外荡的环。clash_fx.gd 里用了两张：
// 一张垂直于光束立在交汇点（从肩后机位看是一面炸开的光盘），一张始终朝着镜头（当光晕）。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/clash_noise.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.4, 0.85, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.3, 0.35, 1.0);
uniform float mix_k = 0.5;
uniform float intensity = 1.8;
uniform float alpha = 1.0;
uniform float flow = 0.0;        // 脚本推进（0~512 循环）
uniform float rays = 1.0;        // 放射纹的分量（当光晕用的那张调小）

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	vec2 dir = p / max(r, 1e-4);
	// 放射纹：角度方向无缝，半径方向往外流
	float n1 = clash_noise(vec2(dir.x * 3.2 + 20.0, dir.y * 3.2 + r * 2.4 - flow * 5.0) + 800.0);
	float n2 = clash_noise(vec2(dir.x * 7.5 - r * 1.3 + 60.0, dir.y * 7.5 + r * 5.0 - flow * 9.0) + 400.0);
	float ray = pow(n1 * n2 * 2.2, 1.6) * (1.0 - r) * rays;
	float ring1 = exp(-pow((r - fract(flow * 0.85)) * 7.0, 2.0));
	float ring2 = exp(-pow((r - fract(flow * 0.85 + 0.5)) * 7.0, 2.0));
	float center = exp(-r * r * 12.0);
	float fade = 1.0 - smoothstep(0.5, 1.0, r);
	vec3 base = mix(color_b.rgb, color_a.rgb, clamp(mix_k + (n1 - 0.5) * 0.5, 0.0, 1.0));
	float lum = center * 2.6 + ray * 1.5 + (ring1 + ring2) * 0.55 * rays;
	ALBEDO = mix(base, vec3(1.0), clamp(center * 1.3, 0.0, 1.0)) * intensity * lum;
	ALPHA = clamp(lum, 0.0, 1.0) * fade * alpha;
}
