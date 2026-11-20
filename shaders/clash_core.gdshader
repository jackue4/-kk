// 飞剑对波 · 交汇点的光核：套在一个球上（本地 -Y 朝主角那一头、+Y 朝对手那一头）。
// 正对镜头是白热的核，外沿一圈带流动能量纹的光壳；两个半球各是一方气劲的颜色，交界随 mix_k（谁占上风）偏移。
// 终爆时同一个着色器套在一个迅速胀大的球上（shell = 1：只留外壳，中间掏空）。
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled, cull_back;

#include "res://shaders/clash_noise.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.4, 0.85, 1.0, 1.0);   // 主角
uniform vec4 color_b : source_color = vec4(1.0, 0.3, 0.35, 1.0);   // 对手
uniform float mix_k = 0.5;       // 0 全是对手的颜色 ~ 1 全是主角的
uniform float intensity = 2.4;
uniform float alpha = 1.0;
uniform float spin = 0.0;        // 脚本推进（0~512 循环）
uniform float shell = 0.0;       // 0 实心光核 ~ 1 只剩外壳

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float f = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	vec3 p = normalize(v_local);
	float n = clash_noise(p.xy * 3.0 + vec2(spin * 1.3, 40.0) + 700.0) * clash_noise(p.zy * 4.2 + vec2(-spin * 1.9, 80.0) + 500.0);
	float hot = pow(f, 3.0) * (1.0 - shell);
	float rim = pow(1.0 - f, mix(2.0, 1.2, shell));
	// 交界：占上风的一方把自己的颜色推过中线
	float side = smoothstep(-0.35, 0.35, p.y + (mix_k - 0.5) * 1.6);
	vec3 base = mix(color_a.rgb, color_b.rgb, side);
	vec3 col = mix(base, vec3(1.0), clamp(hot * 1.2, 0.0, 1.0)) * (0.9 + 2.2 * hot) + base * rim * (0.7 + 2.6 * n);
	ALBEDO = col * intensity;
	ALPHA = clamp(hot + rim * (0.55 + 0.8 * n) + 0.1 * (1.0 - shell), 0.0, 1.0) * alpha;
}
