// 方块世界的天空：天顶 → 天际两色渐变、天际一圈亮带、主光方向的日 / 月轮和光晕、方块状的星星。
// 各区域的颜色由 raid_manager.gd 按主角所在位置渐变着设进来。
shader_type sky;

uniform vec3 top_col : source_color = vec3(0.04, 0.13, 0.24);
uniform vec3 hor_col : source_color = vec3(0.98, 0.52, 0.22);
uniform vec3 glow_col : source_color = vec3(1.0, 0.66, 0.36);
uniform float stars = 0.6;

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(hor_col, top_col, pow(clamp(y, 0.0, 1.0), 0.42));
	c = mix(c, hor_col * 0.45, smoothstep(0.0, -0.3, y));
	c += hor_col * exp(-abs(y) * 10.0) * 0.3;
	float sd = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	c += glow_col * (pow(sd, 5.0) * 0.3 + pow(sd, 60.0) * 0.5 + smoothstep(0.9993, 0.9996, sd) * 3.0);
	float s = step(0.9972, hash3(floor(EYEDIR * 190.0))) * smoothstep(0.08, 0.45, y) * stars;
	c += vec3(0.8, 0.9, 1.0) * s * 1.6;
	COLOR = c;
}
