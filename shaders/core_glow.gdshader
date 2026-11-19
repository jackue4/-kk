// 遁光本体：视角相关的柔边光核
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float intensity = 4.0;
uniform float alpha = 1.0;
uniform float falloff = 1.6;

void fragment() {
	float f = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float core = pow(f, falloff * 6.0);
	ALBEDO = mix(color.rgb, vec3(1.0), core) * intensity;
	ALPHA = pow(f, falloff) * alpha;
}
