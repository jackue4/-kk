// 吉卜力风树冠 / 灌木 / 爬藤：一团实心的扁球打底，表面贴几十张"叶簇卡片"（卡片按 UV 抠成锯齿圆，透明裁剪），
// 卡片的法线不用几何法线，而是从整个树冠中心往外指（网格里已经算好），所以整团叶子像一个蓬松的大球那样受光：
// 迎光一面黄绿、背光一面青绿（环境光偏蓝），边缘是一簇簇叶子的锯齿剪影。
// 顶点色：r 风摆权重，g 每张卡片的随机种子（锯齿相位），b 叶团内的明暗（越靠里、越靠下越暗）。
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/ghibli_light.gdshaderinc"

uniform vec3 leaf_color : source_color = vec3(0.30, 0.48, 0.32);
uniform float sway = 1.0;

varying vec3 wpos;
varying vec3 nview;
varying float ao;
varying float seed;

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	float w = COLOR.r * sway;
	float t = TIME * 1.2 + inst.x * 0.05 + inst.z * 0.07;
	float hk = max(VERTEX.y, 0.0) * 0.03;
	VERTEX.x += sin(t + VERTEX.y * 0.4 + VERTEX.z * 0.3) * w * hk;
	VERTEX.z += cos(t * 0.8 + VERTEX.x * 0.3) * w * hk * 0.8;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	nview = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * NORMAL, 0.0)).xyz);
	ao = COLOR.b;
	seed = COLOR.g;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float edge = 0.80 + 0.13 * sin(ang * 6.0 + seed * 40.0) + 0.06 * sin(ang * 11.0 + seed * 17.0);
	ALPHA = 1.0 - smoothstep(edge - 0.04, edge + 0.04, r);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// 叶簇内细碎的深浅
	float h = fract(sin(dot(floor(wpos * 1.7), vec3(12.9, 78.2, 37.7))) * 43758.5);
	ALBEDO = leaf_color * mix(0.70, 1.05, ao) * (0.94 + 0.10 * h);
	NORMAL = nview;   // 正反两面一样受光
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = mix(1.0, ATTENUATION, 0.65);   // 叶团自阴影只吃一部分，不然卡片上全是碎影
	float lit = smoothstep(-0.12, 0.32, ndl) * sh;
	if (LIGHT_IS_DIRECTIONAL) {
		lit *= ghibli_cloud(wpos, TIME);
		// 正对太阳的一面再往黄绿推一点
		vec3 warm = vec3(1.0) + vec3(0.18, 0.10, -0.08) * smoothstep(0.45, 0.85, ndl) * lit;
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * ghibli_diffuse(lit) * warm;
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit * ATTENUATION;
	}
}
