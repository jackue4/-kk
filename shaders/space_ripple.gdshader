shader_type spatial;
// 剑气拖尾的空间波动（yuanying_cine.gd）：剑气冲过的地方荡开的一圈气浪。一张平放的加色面片，
// 上面一道往外扩的环：最外一道细而亮，里面跟着两道越来越淡的回波，环身微微起伏、亮度有疏密。age 0 → 1 = 从生到灭。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.55, 1.0, 0.93);
uniform float power = 1.0;
uniform float age = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rr = mix(0.16, 0.9, 1.0 - pow(1.0 - age, 2.2));
	float d = r - rr - sin(a * 5.0 + TIME * 3.0) * 0.012 - sin(a * 13.0 - TIME * 5.0) * 0.006;
	float band = exp(-d * d / 0.0005) + 0.5 * exp(-(d + 0.06) * (d + 0.06) / 0.0016) + 0.28 * exp(-(d + 0.14) * (d + 0.14) / 0.004);
	float brk = 0.6 + 0.4 * sin(a * 9.0 + rr * 20.0);
	ALBEDO = mix(tint, vec3(1.0), exp(-d * d / 0.00015) * 0.6) * band * brk * power * (1.0 - age) * (1.0 - age);
}
