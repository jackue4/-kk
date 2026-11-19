// 吉卜力风道具 / 建筑着色：纯色反照率 + 程序花纹（不用贴图），光照见 ghibli_light.gdshaderinc。
// pattern：0 平涂 1 木板墙 2 筒瓦（用 UV，单位米）3 灰泥 4 石块 5 树皮 6 玻璃 7 木纹 8 白石
// 花纹的平面坐标按世界坐标三向投影取，同一种材质拼在一起没有接缝。
shader_type spatial;
render_mode cull_back;

#include "res://shaders/ghibli_light.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.8);
uniform int pattern = 0;
uniform float soft = 0.1;
uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap, hint_default_black;

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 lpos;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
}

void fragment() {
	vec3 c = albedo;
	vec3 an = abs(wnrm);
	vec2 tp = an.y > 0.6 ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	float n = texture(detail_noise, tp * 0.12).r;
	float nf = texture(detail_noise, tp * 0.9).r;
	if (pattern == 1) {
		// 木板墙：一条条横板，竖向接缝错开
		float b = wpos.y / 0.26;
		float id = floor(b);
		float f = fract(b);
		float seam = floor((tp.x + hash12(vec2(id, 3.0)) * 3.0) / 2.6);
		c *= 0.84 + 0.22 * hash12(vec2(id, seam));
		c *= mix(0.62, 1.0, smoothstep(0.0, 0.1, f));
		c *= 0.94 + 0.1 * nf;
	} else if (pattern == 2) {
		// 筒瓦：一排排错缝，每片中间鼓起、下沿压一道影，几片颜色深浅不一，零星青苔
		vec2 t = UV / vec2(0.34, 0.30);
		float row = floor(t.y);
		float u = t.x + mod(row, 2.0) * 0.5;
		float fu = fract(u);
		float fv = fract(t.y);
		c *= 0.74 + 0.32 * sin(fu * PI);
		c *= 1.0 - 0.38 * smoothstep(0.72, 1.0, fv);
		c *= 0.86 + 0.24 * hash12(vec2(floor(u), row));
		c = mix(c, vec3(0.40, 0.48, 0.24), smoothstep(0.6, 0.78, n) * 0.35);
	} else if (pattern == 3) {
		// 灰泥：大块浅浅的污渍
		c *= 0.93 + 0.08 * n + 0.04 * nf;
		c = mix(c, c * vec3(0.84, 0.80, 0.72), smoothstep(0.6, 0.8, n) * 0.5);
	} else if (pattern == 4) {
		// 石块：错缝砌块 + 灰缝
		vec2 t = tp / vec2(0.55, 0.32);
		float row = floor(t.y);
		float u = t.x + mod(row, 2.0) * 0.5;
		vec2 f = fract(vec2(u, t.y));
		float m = smoothstep(0.0, 0.07, f.x) * (1.0 - smoothstep(0.93, 1.0, f.x))
				* smoothstep(0.0, 0.1, f.y) * (1.0 - smoothstep(0.9, 1.0, f.y));
		c *= (0.82 + 0.26 * hash12(vec2(floor(u), row))) * mix(0.62, 1.0, m);
	} else if (pattern == 5) {
		// 树皮：竖纹 + 一侧青苔
		float g = sin(atan(lpos.z, lpos.x) * 9.0 + lpos.y * 0.7 + n * 5.0);
		c *= 0.86 + 0.14 * g;
		c = mix(c, vec3(0.42, 0.52, 0.26), smoothstep(0.5, 0.72, n + wnrm.x * 0.2) * 0.55);
	} else if (pattern == 6) {
		// 玻璃：掠射角映一点天色
		float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		c = mix(c, vec3(0.62, 0.76, 0.9), 0.15 + fr * 0.5);
	} else if (pattern == 7) {
		// 木纹：栏杆、柱子、门
		c *= 0.88 + 0.12 * nf + 0.06 * sin((wpos.x + wpos.z) * 9.0 + n * 10.0);
	} else if (pattern == 8) {
		// 草原上的白石：浅浅的明暗 + 朝上的面长一点苔
		c *= 0.9 + 0.12 * n;
		c = mix(c, vec3(0.50, 0.58, 0.34), smoothstep(0.55, 0.85, wnrm.y) * smoothstep(0.58, 0.75, nf) * 0.4);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float lit = ghibli_lit(dot(NORMAL, LIGHT), soft, ATTENUATION);
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * ghibli_diffuse(lit * ghibli_cloud(wpos, TIME));
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit;
	}
}
