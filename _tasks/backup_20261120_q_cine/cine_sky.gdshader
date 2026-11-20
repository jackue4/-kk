shader_type spatial;
// 结婴演出的天幕（yuanying_cine.gd）：一个罩在镜头外面的大球，把真实的天空盖住，自己画三种天色并在它们之间过渡：
//   乌云夜（褐金色的翻滚云层、缝里透青、青色的星点）→ 剑气在云里撕开一个洞（洞沿一圈亮边，洞里透光、往外放光）
//   → 洞越撕越大，里面是白昼的蓝天，天光从洞口往外漫开，把剩下的云照成金色；元婴特写时再压成一片深青的星空做背景。
// 云是把视线投到头顶一个平面上取的分形噪声；洞是围着 tear_dir（镜头看向剑气穿云那一点的方向）的一个圆，边沿顺着云的形状参差。
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform float fade = 0.0;        // 天幕的不透明度（开头淡入、结尾淡出）
uniform float day = 0.0;         // 0 乌云夜 → 1 白昼
uniform float tear = 0.0;        // 云洞的角半径（弧度）
uniform vec3 tear_dir = vec3(0.0, 1.0, 0.0);
uniform float backdrop = 0.0;    // 元婴特写：压成深青星空
uniform float flash = 0.0;       // 闪电 / 破云的一下全天发亮
uniform vec3 rim_col = vec3(0.5, 1.0, 0.9);

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// 整数哈希：格点的随机数必须一丝不差（原来用 sin 的写法，相邻两格算同一个格点会差出一点，放大后整片云碎成一块块多边形）
float hash2(vec2 p) {
	ivec2 q = ivec2(floor(p + 0.5));
	uint h = uint(q.x) * 374761393u + uint(q.y) * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return float(h & 65535u) / 65535.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 每一层都转个角度再叠，看不出噪声的方格
float fbm(vec2 p, int oct) {
	float a = 0.5;
	float s = 0.0;
	mat2 m = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < oct; i++) {
		s += vnoise(p) * a;
		p = m * p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return s;
}

// 下面的颜色都按「屏幕上看到的颜色」来写、来混，最后统一转成线性光交给渲染（不转的话整片天会发白发淡）
void fragment() {
	vec3 d = normalize(dir);
	vec3 td = normalize(tear_dir);
	float t = TIME * 0.03;
	// 云：越靠天边越扁；用一层噪声把坐标轻轻搅一下
	vec2 uv = d.xz * (1.3 / (max(d.y, -0.08) + 0.3));
	vec2 tuv = td.xz * (1.3 / (max(td.y, -0.08) + 0.3));
	vec2 wq = vec2(fbm(uv * 0.8 + vec2(t, 4.1), 3), fbm(uv * 0.8 + vec2(8.3, -t), 3)) - 0.44;
	vec2 cp = uv * 1.1 + wq * 0.7 + vec2(t, -t * 0.6);
	float n = fbm(cp, 5);
	// 朝云洞（光从那里来）挪一点再取一次：那边更稀说明这一面迎着光，更密说明背光——云就有了明暗面，看着是一团团的而不是一张贴图
	vec2 lv = tuv - uv;
	float nl = fbm(cp + lv / max(length(lv), 0.001) * 0.16, 4);
	float n2 = fbm(uv * 2.7 + wq * 0.9 - vec2(t * 1.5, t), 4);
	float shade = clamp(0.5 + (n - nl) * 3.4 + (n2 - 0.47) * 0.9, 0.0, 1.0);
	float cl = smoothstep(0.36, 0.62, n);
	float sp = step(0.9965, hash3(floor(d * 210.0)));
	// 乌云夜：褐金色的云、缝里透着青
	vec3 gap = mix(vec3(0.02, 0.05, 0.065), vec3(0.04, 0.2, 0.21), n2);
	vec3 cdark = mix(vec3(0.085, 0.065, 0.05), vec3(0.78, 0.56, 0.26), shade * shade);
	vec3 storm = mix(gap, cdark, cl) + vec3(0.35, 1.0, 0.82) * sp * (1.0 - cl);
	// 白昼：深蓝的天、迎光面金色背光面紫灰的云（云比夜里少一些）
	vec3 skyc = mix(vec3(0.60, 0.77, 0.95), vec3(0.11, 0.31, 0.72), clamp(d.y * 1.15 + 0.08, 0.0, 1.0));
	vec3 cday = mix(vec3(0.34, 0.25, 0.32), vec3(1.0, 0.76, 0.40), shade);
	cday = mix(cday, vec3(1.0, 0.93, 0.74), shade * shade * shade * 0.45);
	vec3 dayc = mix(skyc, cday, smoothstep(0.42, 0.66, n) * 0.94);
	// 天光从云洞往外漫开：洞口先亮，远处的云晚一步
	float ang0 = acos(clamp(dot(d, td), -1.0, 1.0));
	vec3 col = mix(storm, dayc, smoothstep(0.0, 1.0, day * 2.6 - ang0 * 0.8));
	// 云洞：边沿顺着云的形状参差
	float on = step(0.005, tear);
	float ang = ang0 + ((n - 0.48) * 1.1 + (n2 - 0.47) * 0.3) * min(tear * 1.4, 1.0);
	float inside = (1.0 - smoothstep(tear - 0.09, tear, ang)) * on;
	float rim = smoothstep(tear - 0.24, tear - 0.02, ang) * (1.0 - smoothstep(tear, tear + 0.2, ang)) * on;
	vec3 light = mix(rim_col, vec3(1.0, 0.84, 0.5), day);
	vec3 hole = mix(mix(vec3(0.16, 0.7, 0.66), vec3(0.8, 1.0, 0.96), smoothstep(tear, 0.0, ang0)), skyc, day);
	col = mix(col, hole, inside);
	col += light * rim * mix(0.6, 0.45, day) * (0.4 + 0.6 * cl);
	// 洞里透出来的光：围着洞心的一团 + 放射的光条；白昼时洞心是一轮太阳
	float c = max(dot(d, td), 0.0);
	float a2 = atan(d.z - td.z, d.x - td.x);
	float rays = pow(vnoise(vec2(cos(a2), sin(a2)) * 6.0 + 3.0), 3.0);
	vec3 glare = light * (pow(c, 12.0) * 0.45 + pow(c, 3.0) * rays * 0.3) * mix(1.0, 0.55, day) + vec3(1.0, 0.96, 0.85) * pow(c, 90.0) * 0.9 * day;
	col += glare * on * (1.0 - 0.7 * backdrop);
	// 特写的背景：深青星空，边上留一点金褐的云
	vec3 deep = mix(vec3(0.015, 0.05, 0.07), vec3(0.04, 0.22, 0.24), n) + vec3(0.6, 1.0, 0.9) * sp + cdark * 0.55 * cl * shade;
	col = mix(col, deep, backdrop);
	col += vec3(0.6, 0.75, 0.85) * flash * (0.2 + 0.5 * cl) * 0.5;
	// col 是按屏幕色调的。兼容渲染器（网页 / 手机）里 ALBEDO 本来就按屏幕色（sRGB）解释，不能再转一次线性
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = clamp(col, vec3(0.0), vec3(1.15));
#else
	ALBEDO = pow(clamp(col, vec3(0.0), vec3(1.15)), vec3(2.2));
#endif
	ALPHA = fade;
}
