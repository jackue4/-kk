// 血刃破空的气浪圈（scripts/heroes/cg_fx.gd 的 air_split，2026-11-25）：一张垂直于血刃去向的圆片上，套着五圈断断续续的弧线 ——
// 墨黑为主、夹几道暗红，每一段弧两头尖、粗细不一，各圈慢慢错着转；脚本把片从小放到大，age 0 → 1 淡掉。
// 参考（用户给的图）：血刃飞过的地方，空气被劈成一圈圈往外甩的黑色弧线，像隧道。
// 不读屏幕、不查贴图，一个像素几次哈希。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 col_a : source_color = vec3(0.02, 0.0, 0.02);
uniform vec3 col_b : source_color = vec3(0.55, 0.02, 0.04);
uniform float age = 0.0;
uniform float seed = 0.0;
uniform float alpha = 1.0;

float hash(float n) {
	return fract(sin(n * 78.233 + seed * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.28318 + 0.5;
	float rr = (r - 0.38) / 0.6 * 5.0;
	float idx = floor(rr);
	float f = fract(rr);
	float h = hash(idx + 1.0);
	// 这一圈分几段弧、转到哪了
	float segs = 3.0 + floor(h * 4.0);
	float aa = fract(a + h * 3.7 + age * (h - 0.5) * 0.7);
	float seg = floor(aa * segs);
	float sa = fract(aa * segs);
	float hs = hash(idx * 7.3 + seg * 1.9 + 5.0);
	float on = step(0.3, hs);
	float taper = smoothstep(0.0, 0.3, sa) * (1.0 - smoothstep(0.55, 1.0, sa));
	float w = (0.1 + 0.28 * hash(idx * 3.1 + seg + 9.0)) * taper;
	float line = (1.0 - smoothstep(w * 0.5, w * 0.5 + 0.07, abs(f - 0.5))) * on * step(0.02, taper);
	line *= step(0.38, r) * (1.0 - smoothstep(0.94, 0.98, r));
	ALBEDO = mix(col_a, col_b, step(0.72, hash(idx * 1.7 + seg * 0.31 + 2.0)));
	ALPHA = clamp(line * alpha * (1.0 - age * age), 0.0, 1.0);
}
