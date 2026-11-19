// 剑光 / 遁光丝线。UV.x: 0=头 1=尾；UV.y: 横向。
// 画法：中间一条亮芯 + 两侧迅速收边的色带；头亮，尾部随几何收尖并淡出。
// 全程 blend_mix、亮度封顶，不做加色叠白，所以多条线交叠也不会糊成白团。
// style 只在线身上做轻微变化，不改变"线"的轮廓：
// 0 丝光  1 焰（尾段断续成火舌）  2 雷弧（亮芯明灭）  3 五行  4 虹（色相缓慢流转）  5 裂空（尾段断成短划）
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform int style = 0;
uniform float intensity = 1.15;
uniform float scroll = 2.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	float u = UV.x;
	float v = abs(UV.y - 0.5) * 2.0;
	float n = texture(noise_tex, vec2(u * 3.0 - TIME * scroll * 0.7, 0.37)).r;

	float soft = max(fwidth(v) * 1.5, 0.14);
	float core = 1.0 - smoothstep(0.14, 0.14 + soft, v);
	float edge = 1.0 - smoothstep(0.3, 1.0, v);
	edge *= edge;
	float head = pow(max(1.0 - u, 0.0), 2.5);
	float fade = 1.0 - smoothstep(0.5, 1.0, u);

	vec3 body = color_b.rgb;
	float gap = 1.0;
	if (style == 1) {
		gap = smoothstep(u * 0.9 - 0.25, u * 0.9 + 0.1, n + 0.25);
		body = mix(color_b.rgb, color_a.rgb, 0.25 * n);
	} else if (style == 2) {
		core *= 0.7 + 0.3 * step(0.5, fract(n * 5.0 + TIME * 11.0));
	} else if (style == 4) {
		vec3 rb = hsv2rgb(vec3(fract(u * 0.6 - TIME * 0.25), 0.55, 1.0));
		body = mix(color_b.rgb, rb, 0.45);
	} else if (style == 5) {
		gap = mix(1.0, step(0.45, n), smoothstep(0.25, 0.7, u));
	}

	vec3 col = mix(body, color_a.rgb, core * (0.3 + 0.7 * head));
	float a = max(core * (0.6 + 0.4 * head), edge * 0.5) * fade * gap;
	ALBEDO = col * intensity * (1.0 + 0.3 * core * head) * COLOR.rgb;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
