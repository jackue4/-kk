// 木兰草原地面（吉卜力风）：
// · 草色：主角草环里用偏深的"草根色"（草叶从上面盖住），草环外换成草叶整体看上去的亮黄绿，接缝处渐变；
//   再叠大块枯黄 / 浓绿色斑（tint_noise，和草叶着色器同一尺度，色斑对得上）和顺风方向的细长"草浪"明暗。
// · 土路：path_pts 是一串折线点（x, z, 半宽），按到折线的距离 + 噪声抠出不规则的路边；村中心 plaza 一圈空地。
//   草叶 / 花 / 树在 CPU 上按同一条折线让开（见 meadow_gen.gd 的 path_info）。
// · 陡坡露出暖白色的岩壁（带一点横向岩层），不再有灰石头和雪。
// · 光照见 ghibli_light.gdshaderinc（柔边色块 + 青蓝阴影 + 云影）。
// horizon = true 时是远景整张网格：cover_mask（一格一个 256 米地块）里已有细地块的地方直接丢弃，不和细地块打架。
shader_type spatial;
render_mode cull_back;

#include "res://shaders/ghibli_light.gdshaderinc"

uniform vec3 grass_root : source_color = vec3(0.30, 0.50, 0.11);
uniform vec3 grass_far : source_color = vec3(0.54, 0.75, 0.20);
uniform vec3 grass_dry : source_color = vec3(0.74, 0.74, 0.32);
uniform vec3 grass_deep : source_color = vec3(0.26, 0.48, 0.16);
uniform vec3 dirt : source_color = vec3(0.84, 0.76, 0.58);
uniform vec3 dirt_dark : source_color = vec3(0.66, 0.56, 0.40);
uniform vec3 rock : source_color = vec3(0.88, 0.82, 0.68);
uniform vec3 rock_dark : source_color = vec3(0.68, 0.62, 0.52);
uniform sampler2D tint_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 path_pts[32];
uniform int path_n = 0;
uniform vec3 plaza = vec3(0.0, 0.0, -1.0);    // x, z, 半径
uniform vec3 grass_ring_center = vec3(0.0);
uniform float grass_ring_r = 95.0;

uniform bool horizon = false;
uniform sampler2D cover_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin = vec2(-12288.0);
uniform float mask_span = 24576.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 到土路折线的距离；hw 返回该处路的半宽
float path_dist(vec2 p, out float hw) {
	float best = 1e9;
	hw = 1.3;
	for (int i = 0; i < path_n - 1; i++) {
		vec2 a = path_pts[i].xy;
		vec2 b = path_pts[i + 1].xy;
		vec2 ab = b - a;
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		float d = length(p - (a + ab * t));
		if (d < best) {
			best = d;
			hw = mix(path_pts[i].z, path_pts[i + 1].z, t);
		}
	}
	return best;
}

void fragment() {
	if (horizon) {
		vec2 m = (wpos.xz - mask_origin) / mask_span;
		if (m.x > 0.0 && m.y > 0.0 && m.x < 1.0 && m.y < 1.0 && texture(cover_mask, m).r > 0.5) {
			discard;
		}
	}
	float n_big = texture(tint_noise, wpos.xz / 900.0).r;
	float n_mid = texture(tint_noise, wpos.xz / 170.0 + vec2(0.37, 0.11)).r;
	float n_fine = texture(detail_noise, wpos.xz / 6.0).r;
	float n_str = texture(detail_noise, vec2(wpos.x / 60.0 + wpos.z / 120.0, wpos.z / 11.0 - wpos.x / 30.0)).r;
	float ring = smoothstep(grass_ring_r * 0.6, grass_ring_r * 1.05, length(wpos.xz - grass_ring_center.xz));
	vec3 g = mix(grass_root, grass_far, ring);
	g = mix(g, grass_dry, smoothstep(0.5, 0.75, n_big) * 0.5);
	g = mix(g, grass_deep, smoothstep(0.55, 0.8, n_mid) * 0.35);
	g *= 0.9 + 0.12 * n_fine + 0.10 * (n_str - 0.5) * ring;
	vec3 col = g;
	// 土路 + 村中空地
	float edge = (n_fine - 0.5) * 0.9 + (n_mid - 0.5) * 0.6;
	float hw;
	float pd = path_dist(wpos.xz, hw);
	float on_path = 1.0 - smoothstep(hw - 0.2, hw + 0.2, pd + edge);
	float on_plaza = 1.0 - smoothstep(-0.4, 0.4, length(wpos.xz - plaza.xy) - plaza.z + edge * 2.0);
	float dk = max(on_path, on_plaza);
	if (dk > 0.0) {
		float mid_line = 1.0 - smoothstep(0.0, hw * 0.8, pd);
		vec3 dc = mix(dirt_dark, dirt, 0.45 + 0.35 * smoothstep(0.25, 0.75, n_fine) + 0.2 * mid_line * on_path);
		col = mix(col, dc, dk);
	}
	// 陡坡：暖白岩壁
	float up = normalize(wnrm).y;
	float rk = 1.0 - smoothstep(0.62, 0.78, up + (n_mid - 0.5) * 0.15);
	vec3 rc = mix(rock_dark, rock, smoothstep(0.3, 0.7, n_fine));
	rc *= 0.92 + 0.08 * sin(wpos.y * 1.3 + n_mid * 6.0);
	col = mix(col, rc, rk);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float lit = ghibli_lit(dot(NORMAL, LIGHT), 0.2, ATTENUATION);
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * ghibli_diffuse(lit * ghibli_cloud(wpos, TIME));
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit;
	}
}
