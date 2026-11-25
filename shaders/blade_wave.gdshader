// 苍鸿的刀光（scripts/heroes/cg_fx.gd，2026-11-25 第三轮：用户嫌「剑气都看不清」）。
// 贴在一片新月网格上：UV.x 沿弧 0 → 1（1 = 刀尖去的那一头），UV.y 0 = 内缘 … 1 = 外缘（刀刃）。
// 三层硬色阶：外缘一道白热的刃线 → 刀色的刀身 → 内侧压暗的底色；刀身上是顺着弧飞的碎丝，内缘撕成一缕缕。
// 最外面再勾一道深色的边：亮地面 / 亮天空上也读得出形状（以前是细白弧叠在白地上，看不见）。
// blend_mix，不叠白：是「刀光」不是光团。age 0 → 1 = 从生到散（内缘先碎、整片再淡）。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 col_edge : source_color = vec4(1.0);                    // 刃线
uniform vec4 col_body : source_color = vec4(0.45, 0.85, 1.0, 1.0);   // 刀身
uniform vec4 col_dark : source_color = vec4(0.05, 0.12, 0.3, 1.0);   // 内侧底色 / 勾边
uniform float alpha = 1.0;
uniform float age = 0.0;
uniform float flow = 3.0;       // 碎丝沿弧飞多快
uniform float seed = 0.0;
uniform float ink = 0.6;        // 勾边多重（0 = 不勾）

float hash(float n) {
	return fract(sin(n * 91.7 + seed * 13.1) * 43758.5453);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	// 两头收尖
	float ends = smoothstep(0.0, 0.1, u) * (1.0 - smoothstep(0.92, 1.0, u));
	// 碎丝：按 v 分成一条条带子，每条带子上是几段顺着弧跑的虚线
	float band = floor(v * 14.0);
	float h = hash(band);
	float run = fract(u * (1.2 + 1.6 * h) + h * 7.0 - TIME * flow * (0.5 + h));
	float dash = smoothstep(0.0, 0.08, run) * (1.0 - smoothstep(0.45 + 0.4 * hash(band + 3.0), 0.9, run));
	// 内缘撕开：越往里越只剩碎丝；年纪越大撕得越靠外
	float tear = 0.22 + 0.5 * age;
	float solid = smoothstep(tear, tear + 0.3, v);
	float body = max(solid, dash * smoothstep(tear - 0.25, tear + 0.1, v) * 0.85);
	float edge = smoothstep(0.76, 0.86, v) * (1.0 - smoothstep(0.93, 0.97, v));
	float rim = smoothstep(0.93, 0.97, v);
	vec3 col = mix(col_dark.rgb, col_body.rgb, smoothstep(0.3, 0.7, v) * (0.75 + 0.25 * dash));
	col = mix(col, col_edge.rgb, edge);
	col = mix(col, col_dark.rgb * 0.5, rim);
	float a = max(body * mix(0.55, 0.95, smoothstep(0.2, 0.8, v)), edge);
	a = mix(a, a * ink, rim);
	a *= ends * (1.0 - smoothstep(0.55, 1.0, age));
	ALBEDO = col;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
