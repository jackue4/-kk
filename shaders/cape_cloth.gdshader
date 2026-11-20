shader_type spatial;
// 披风（cape_cloth.gd 的布料网格）：厚实的皮料质感——细颗粒纹理、略带光泽、两侧和下摆一道镶边加一行缝线。
// 网格正反两面各出一遍顶点（COLOR 白 = 外面，灰 = 里衬），所以这里照常剔除背面。
// flash / glow 和方块人的 block.gdshader 同名同义（受击闪白、化光）。

uniform vec3 cape_col : source_color = vec3(0.2, 0.2, 0.3);
uniform vec3 trim_col : source_color = vec3(0.85, 0.7, 0.35);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.4, 0.7, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// 离两侧 / 下摆边缘的距离（以披风长度为 1）
	float edge = min(min(UV.x, 1.0 - UV.x) * 0.8, 1.0 - UV.y);
	float trim = 1.0 - smoothstep(0.042, 0.048, edge);
	float seam = (1.0 - smoothstep(0.0, 0.008, abs(edge - 0.07))) * step(0.5, fract(max(UV.x, UV.y) * 46.0));
	float grain = vnoise(UV * vec2(70.0, 96.0)) * 0.6 + vnoise(UV * vec2(190.0, 260.0)) * 0.4;
	vec3 base = mix(cape_col, trim_col, trim);
	base *= 0.9 + 0.2 * grain;
	base = mix(base, trim_col * 0.8, seam * 0.6 * (1.0 - trim));
	base *= COLOR.rgb;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = mix(base + vec3(fres * 0.05), vec3(1.0), flash * 0.6);
	ALBEDO = mix(ALBEDO, mix(glow_color, vec3(1.0), 0.35), glow * 0.85);
	EMISSION = vec3(1.0, 0.95, 0.9) * flash * 0.25 + glow_color * glow * 1.6;
	ROUGHNESS = mix(0.46, 0.68, grain);
	SPECULAR = 0.45;
}
