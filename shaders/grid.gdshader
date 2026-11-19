// 测试大厅网格：世界空间坐标，三向投影，远处自动淡出
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.35);
uniform vec3 line_color : source_color = vec3(0.86);
uniform float cell = 1.0;
uniform float major = 10.0;
uniform float line_strength = 0.6;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float size, float width) {
	vec2 c = p / size;
	vec2 g = abs(fract(c - 0.5) - 0.5) / max(fwidth(c), vec2(1e-5));
	return 1.0 - min(min(g.x, g.y) / width, 1.0);
}

void fragment() {
	vec3 an = abs(wnrm);
	vec2 p = wpos.xz;
	if (an.x > an.y && an.x > an.z) {
		p = wpos.zy;
	} else if (an.z > an.y) {
		p = wpos.xy;
	}
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float f1 = 1.0 - smoothstep(35.0, 130.0, dist);
	float f2 = 1.0 - smoothstep(350.0, 1100.0, dist);
	float g1 = grid(p, cell, 1.0) * 0.55 * f1;
	float g2 = grid(p, major, 1.6) * f2;
	float l = max(g1, g2) * line_strength;
	ALBEDO = mix(base_color, line_color, l);
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
}
