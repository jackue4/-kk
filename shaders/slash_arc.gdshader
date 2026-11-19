// 挥砍剑光弧。UV.x: 0=最新 1=最旧；UV.y: 0=靠剑柄一侧 1=剑尖外沿。
// 像素刀光：一弯新月（刀头厚、越往尾越薄），三档硬色阶（内侧深色 → 刀色 → 外沿亮线），刀头一截白热；
// 尾段碎成一格一格的方块逐渐散掉（格子约等于体素尺寸），和像素命中特效同一种语言。
// blend_mix、亮度封顶，不加色叠白——是"刀光"，不是光团。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color_a : source_color = vec4(1.0);                  // 外沿亮线
uniform vec4 color_b : source_color = vec4(0.4, 0.7, 1.0, 1.0);   // 刀身色带
uniform float alpha = 1.0;
uniform vec2 cells = vec2(34.0, 8.0);   // 碎块格数（沿弧, 沿刃）

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float aa = max(fwidth(v), 0.008);
	float inner = mix(0.48, 0.82, smoothstep(0.0, 0.8, u));
	float body = smoothstep(inner - aa, inner + aa, v) * (1.0 - smoothstep(1.0 - aa * 2.0, 1.0, v));
	float edge = smoothstep(0.91 - aa, 0.91 + aa, v);
	float t = clamp((v - inner) / max(1.0 - inner, 0.02), 0.0, 1.0);
	vec3 col = t < 0.4 ? color_b.rgb * 0.6 : color_b.rgb;
	col = mix(col, color_a.rgb, edge);
	float head = 1.0 - smoothstep(0.06, 0.16, u);
	col = mix(col, vec3(1.0), head * step(0.35, t) * 0.85);

	float h = hash(floor(vec2(u, v) * cells));
	float keep_body = step(smoothstep(0.3, 0.9, u) * 1.05, h);
	float keep_edge = step(smoothstep(0.5, 1.0, u), h);
	float a = max(body * keep_body * mix(0.45, 0.85, t), edge * keep_edge * 0.95);
	a *= 1.0 - smoothstep(0.75, 1.0, u);
	ALBEDO = col;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
