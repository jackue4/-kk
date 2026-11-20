// 方块世界的天空：天顶 → 天际两色渐变、天际一圈亮带、主光方向的日轮和光晕、一层层的云、方块状的星星（天黑才有）。
// 地平线以下不画暗色：接成云海 / 雾的颜色（low_col），远处没加载地块的地方看上去就是云海一直铺到天边。
// 各区域的颜色由 raid_manager.gd 按主角所在位置渐变着设进来。
shader_type sky;

uniform vec3 top_col : source_color = vec3(0.2, 0.44, 0.86);
uniform vec3 hor_col : source_color = vec3(0.76, 0.87, 0.98);
uniform vec3 glow_col : source_color = vec3(1.0, 0.95, 0.84);
uniform vec3 low_col : source_color = vec3(0.9, 0.93, 0.98);
uniform float stars = 0.0;
uniform float clouds = 0.5;      // 天上云的多少
uniform float sun_size = 1.0;    // 日轮的大小倍数（黄枫谷的夕阳、血色禁地的落日要大得多）
uniform float omen = 0.0;        // 结婴：天色压暗、乌云加厚（0~1）
uniform float tear = 0.0;        // 结婴：头顶云层被撕开的洞（0~1）
uniform float dawn = 0.0;        // 结婴：洞开之后转成白日金光（0~1）
uniform float vortex = 0.0;      // 坠魔谷：封印之门上空的魔气漩涡（0~1）
uniform vec3 vortex_dir = vec3(-0.8, 0.55, 0.0);
uniform vec3 vortex_col : source_color = vec3(0.78, 0.5, 1.0);

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	float y = EYEDIR.y;
	float om = clamp(omen, 0.0, 1.0);
	float dw = clamp(dawn, 0.0, 1.0);
	float tr = clamp(tear, 0.0, 1.0);
	// 异象压暗时云加厚；天亮后云散开。头顶的洞按视线偏离正上方的角度挖。
	float cloud_amt = mix(clouds, max(clouds, 0.97), om);
	cloud_amt = mix(cloud_amt, cloud_amt * 0.22, dw);
	float hole = 0.0;
	float lip = 0.0;
	if (y > 0.02) {
		float tear_ang = length(EYEDIR.xz) / max(y, 0.05);
		hole = smoothstep(0.82, 0.14, tear_ang) * tr;
		lip = smoothstep(0.95, 0.42, tear_ang) * smoothstep(0.12, 0.4, tear_ang) * tr;
	}

	vec3 c = mix(hor_col, top_col, pow(clamp(y, 0.0, 1.0), 0.45));
	c += hor_col * exp(-abs(y) * 9.0) * 0.18;
	float sd = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	// 云：把视线投到头顶的一个平面上取噪声，越近天边越扁、越淡
	if (y > 0.0 && cloud_amt > 0.01) {
		vec2 uv = EYEDIR.xz / (y + 0.22) * 1.6 + vec2(TIME * 0.004, 0.0);
		float n = vnoise(uv) * 0.55 + vnoise(uv * 2.3 + 7.0) * 0.3 + vnoise(uv * 5.1 - 3.0) * 0.15;
		float k = smoothstep(1.0 - cloud_amt * 0.62, 1.0 - cloud_amt * 0.62 + 0.22, n) * smoothstep(0.0, 0.16, y);
		k *= 1.0 - hole;
		vec3 lit = mix(vec3(1.0), glow_col, 0.45) * (0.82 + 0.3 * pow(sd, 3.0));
		vec3 shade = mix(top_col, hor_col, 0.55) * 0.82;
		shade = mix(shade, vec3(0.15, 0.12, 0.08), om);
		lit = mix(lit, vec3(0.40, 0.34, 0.22), om * 0.7);
		c = mix(c, mix(shade, lit, smoothstep(0.35, 0.8, n)), k * 0.9);
		vec3 rim = mix(vec3(0.45, 0.96, 0.9), vec3(1.0, 0.78, 0.42), dw);
		c = mix(c, rim, lip * 0.9);
	}
	// 魔气漩涡：以 vortex_dir 为轴的一个斜盘，三条旋臂慢慢转，中心一个亮核；旋臂之间把云压暗
	if (vortex > 0.01) {
		float cv = dot(EYEDIR, vortex_dir);
		if (cv > 0.5) {
			vec3 ax = normalize(cross(vortex_dir, vec3(0.0, 1.0, 0.0)));
			vec3 ay = cross(ax, vortex_dir);
			vec2 pv = vec2(dot(EYEDIR, ax), dot(EYEDIR, ay) * 1.8) / cv;
			float r = length(pv);
			float arms = sin(atan(pv.y, pv.x) * 3.0 + log(r + 0.03) * 6.0 - TIME * 0.3);
			float band = floor(smoothstep(-0.3, 0.9, arms) * 4.0 + 0.5) * 0.25;      // 分成几档亮度：方块世界里不要太顺滑
			float fall = smoothstep(0.7, 0.05, r);
			float core = exp(-r * r * 70.0);
			c = mix(c, c * 0.5, (1.0 - band) * fall * 0.7 * vortex);
			c += vortex_col * (band * fall * fall * 0.62 + core * 1.5) * vortex;
		}
	}
	float disc = 1.0 - 0.0007 * sun_size * sun_size;
	c += glow_col * (pow(sd, 5.0) * 0.25 + pow(sd, 60.0 / max(sun_size, 1.0)) * 0.5 + smoothstep(disc, disc + 0.0003, sd) * 3.0);
	float s = step(0.9972, hash3(floor(EYEDIR * 190.0))) * smoothstep(0.08, 0.45, y) * stars;
	c += vec3(0.8, 0.9, 1.0) * s * 1.6;
	c = mix(c, low_col, smoothstep(0.02, -0.06, y));
	// omen / dawn / tear 全是 0 时，下面三行不改变原来的天色
	c = mix(c, c * vec3(0.16, 0.14, 0.12) + vec3(0.015, 0.013, 0.012), om * (1.0 - hole * 0.9));
	vec3 day = mix(vec3(1.0, 0.73, 0.38), vec3(0.40, 0.68, 1.0), pow(clamp(y, 0.0, 1.0), 0.5));
	c = mix(c, day, dw * 0.9);
	vec3 shaft = mix(vec3(0.35, 0.95, 0.9), vec3(1.0, 0.8, 0.42), dw);
	c += shaft * pow(hole, 1.3) * 0.6;
	COLOR = c;
}
