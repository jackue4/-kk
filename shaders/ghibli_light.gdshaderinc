// 吉卜力风光照公用部分（地面 / 草 / 树 / 房子 / 石头共用，见 scripts/ghibli_kit.gd）：
// · 受光面 / 背光面之间是一道窄而柔的过渡（不是写实的余弦渐变），色块感更像手绘背景；
// · 背光面不黑：太阳在阴影里还留一点偏青蓝的补光（ghibli_diffuse），再加上偏蓝的环境光，阴影是青绿色而不是灰黑；
// · 地上飘过大块云影（ghibli_cloud，世界坐标噪声随时间平移）。
// 只给平行光（太阳）加阴影补光，点光 / 聚光（传送门那盏）照常按受光量计算。

uniform sampler2D cloud_shadow_noise : repeat_enable, filter_linear, hint_default_black;
uniform float cloud_shadow_k = 0.32;

// 云影：1 = 晴，1 - cloud_shadow_k = 云下
float ghibli_cloud(vec3 wp, float t) {
	vec2 uv = wp.xz / 1100.0 + vec2(t * 0.0030, t * 0.0011);
	float n = texture(cloud_shadow_noise, uv).r;
	return 1.0 - cloud_shadow_k * smoothstep(0.55, 0.64, n);
}

// 受光量 0..1：soft 是明暗交界的半宽
float ghibli_lit(float ndl, float soft, float shadow) {
	return smoothstep(-soft, soft, ndl - 0.04) * shadow;
}

// 乘在 LIGHT_COLOR 上的漫反射：背光处留一点青蓝补光
vec3 ghibli_diffuse(float lit) {
	return mix(vec3(0.15, 0.21, 0.31), vec3(1.0), lit);
}
