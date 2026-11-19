// 体素小人：顶点色 + 逐像素倒角。
// cell = 片元在所属方块内的坐标（-0.5 ~ 0.5，建模空间轴向），由 UV/UV2 传入。
// 靠近方块棱边时把法线向棱外偏转并略微压暗，得到"每块都有小倒角"的手办质感，
// 网格本身仍是密闭的整面，不会因为真倒角而漏缝。
shader_type spatial;

uniform float bevel : hint_range(0.0, 0.6) = 0.22;
uniform float bevel_tilt : hint_range(0.0, 1.5) = 0.85;
uniform float edge_shade : hint_range(0.0, 1.0) = 0.14;
uniform float rough : hint_range(0.0, 1.0) = 0.82;
// 受击闪白（只给敌人的独立材质用；默认 0，主角不受影响）。上限压在 0.6，不会变成白团
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 化光（主角化作光剑 / 由光剑现形的过渡）：整身染成遁光色并自发光
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.4, 0.7, 1.0);

varying vec3 cell;
varying vec3 axis_x;
varying vec3 axis_y;
varying vec3 axis_z;

void vertex() {
	cell = vec3(UV, UV2.x);
	axis_x = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	axis_y = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	axis_z = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
}

void fragment() {
	vec3 a = abs(cell) * 2.0;
	// 面法线所在的轴恒为 1；其余两轴只在倒角带内升起
	vec3 w = smoothstep(vec3(1.0 - bevel), vec3(1.0), a);
	float seam = clamp(w.x + w.y + w.z - 1.0, 0.0, 1.0);
	vec3 face = step(vec3(0.999), a);
	vec3 nm = sign(cell) * mix(w * bevel_tilt, vec3(1.0), face);
	NORMAL = normalize(axis_x * nm.x + axis_y * nm.y + axis_z * nm.z);
	ALBEDO = mix(COLOR.rgb * (1.0 - edge_shade * seam), vec3(1.0), flash * 0.6);
	ALBEDO = mix(ALBEDO, mix(glow_color, vec3(1.0), 0.35), glow * 0.85);
	EMISSION = vec3(1.0, 0.95, 0.9) * flash * 0.25 + glow_color * glow * 1.6;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
