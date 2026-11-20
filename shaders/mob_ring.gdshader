shader_type spatial;
// 脚下的法阵光环：精英怪 / Boss 脚下一圈、掉落物底下一小圈（按品阶染色）。一张平铺的加色面片。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.6, 0.2);
uniform float power = 1.0;
uniform float spokes = 6.0;   // 内圈断成几段（0 = 不画内圈）

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ring = smoothstep(0.07, 0.0, abs(r - 0.86));
	float inner = smoothstep(0.035, 0.0, abs(r - 0.62)) * step(0.0, sin(a * spokes + TIME * 1.4)) * step(0.5, spokes);
	float fill = (1.0 - smoothstep(0.0, 0.9, r)) * 0.22;
	float k = (ring + inner * 0.8 + fill) * step(r, 1.0) * (0.85 + 0.15 * sin(TIME * 2.2));
	ALBEDO = tint * k * power;
}
