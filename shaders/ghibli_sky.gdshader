// 吉卜力 / Europa 式的天空：天顶深蓝 → 中段亮蓝 → 地平线发白的天色；地平线一圈堆得很厚的积云，往上是一团团大白云，
// 高处几缕卷云。云是把视线投到一张"云层平面"上采两张噪声（低频 fbm 定形 + 细胞噪声鼓包），边缘收得比较利（手绘感）；
// 明暗：朝天顶方向、朝太阳方向各多采一次密度，密度往那边下降 = 这一侧是云的受光面（白），反之是背光的青灰；
// 薄边一圈发亮，远处的云沉进地平线的雾气里。云随时间慢慢漂。
// 环境光用的是固定颜色（见 ghibli_kit.gd），辐照度立方图那一趟（AT_CUBEMAP_PASS）只画天色渐变，省事也稳定。
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.07, 0.30, 0.66);
uniform vec3 upper : source_color = vec3(0.17, 0.50, 0.86);
uniform vec3 horizon : source_color = vec3(0.66, 0.82, 0.94);
uniform vec3 below : source_color = vec3(0.56, 0.70, 0.60);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 cloud_mid : source_color = vec3(0.86, 0.90, 0.97);
uniform vec3 cloud_dark : source_color = vec3(0.55, 0.64, 0.80);
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap, hint_default_black;
uniform sampler2D puff_noise : repeat_enable, filter_linear_mipmap, hint_default_black;
uniform float cover_low = 0.50;    // 地平线附近的云量阈值（越小云越多）
uniform float cover_high = 0.64;   // 天顶
uniform float cloud_scale = 0.16;
uniform float drift = 0.0012;

float dens(vec2 uv) {
	float a = texture(cloud_noise, uv).r;
	float b = texture(puff_noise, uv * 2.2 + vec2(0.31, 0.17)).r;
	float c = texture(cloud_noise, uv * 5.5 + vec2(0.7, 0.2)).r;
	return a * 0.60 + b * 0.30 + c * 0.10;
}

vec3 sky_grad(float e) {
	vec3 c = mix(horizon, upper, smoothstep(0.0, 0.30, e));
	return mix(c, zenith, smoothstep(0.28, 0.95, e));
}

void sky() {
	vec3 d = EYEDIR;
	float e = d.y;
	vec3 col = sky_grad(max(e, 0.0));
	if (e < 0.0) {
		col = mix(horizon, below, smoothstep(0.0, 0.25, -e));
	}
	vec3 sd = LIGHT0_DIRECTION;
	float sdot = max(dot(d, sd), 0.0);
	if (LIGHT0_ENABLED) {
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (pow(sdot, 8.0) * 0.10 + smoothstep(0.9994, 0.9997, sdot) * 3.0);
	}
	if (!AT_CUBEMAP_PASS && e > -0.02) {
		float ee = max(e, 0.0);
		vec2 base_uv = d.xz / (ee + 0.07) * cloud_scale;
		vec2 uv = base_uv + vec2(TIME * drift, TIME * drift * 0.4);
		float n = dens(uv);
		float cov = mix(cover_low, cover_high, smoothstep(0.03, 0.55, ee));
		float a = smoothstep(cov, cov + 0.04, n);
		if (a > 0.001) {
			vec2 dxz = normalize(d.xz + vec2(1e-5));
			vec2 sxz = normalize(sd.xz + vec2(1e-5));
			float n_up = dens(uv - dxz * 0.03);
			float n_sun = dens(uv + sxz * 0.025);
			float lit_up = clamp((n - n_up) * 9.0 + 0.5, 0.0, 1.0);
			float lit_sun = clamp((n - n_sun) * 9.0 + 0.5, 0.0, 1.0);
			float thick = smoothstep(cov + 0.02, cov + 0.22, n);
			float l = clamp(lit_up * 0.62 + lit_sun * 0.38, 0.0, 1.0);
			l = mix(l, l * 0.75, thick);
			vec3 cc = mix(cloud_dark, cloud_mid, smoothstep(0.12, 0.48, l));
			cc = mix(cc, cloud_lit, smoothstep(0.48, 0.78, l));
			cc = mix(cc, cloud_lit, (1.0 - thick) * 0.45);           // 薄边透亮
			cc += LIGHT0_COLOR * pow(sdot, 6.0) * 0.12 * (1.0 - thick); // 迎着太阳的云边更亮
			cc = mix(cc, horizon * 1.03, (1.0 - smoothstep(0.0, 0.12, ee)) * 0.45);
			a *= smoothstep(-0.01, 0.03, e);
			col = mix(col, cc, a);
		}
		// 高空卷云：拉长的噪声，只在中高天空、没有积云的地方
		vec2 uv2 = d.xz / (ee + 0.35) * 0.32 + vec2(TIME * drift * 1.5, 0.0);
		float w = texture(cloud_noise, vec2(uv2.x * 0.6 + uv2.y * 0.3, uv2.y * 3.2)).r;
		float wa = smoothstep(0.58, 0.74, w) * smoothstep(0.12, 0.4, ee) * 0.45 * (1.0 - a);
		col = mix(col, vec3(0.95, 0.97, 1.0), wa);
	}
	COLOR = col;
}
