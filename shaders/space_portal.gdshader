shader_type spatial;
// 择境传送门的门心（level_portal.gd）：一张始终转向镜头的面片，画一个悬在半空的「宇宙之门」（参考用户给的那张紫色星门）——
//   门里：深紫近黑的太空、两层星点、蓝和品红的星云。星空按「视线方向」取样：人绕着门走，星空不跟着门动，像真的隔着门洞看另一片天
//   门沿：一圈参差的紫白亮边，旋涡光带绕着门慢慢转；门外是一圈往外淡出的紫色辉光和细电弧
// 2026-11-20 之前门心里是把真实关卡渲染进一个 SubViewport（多画半个屏幕的一整个世界，外加一层读屏幕的扭曲），手机上很贵；
// 用户说「外表做成宇宙空间，不用看到实际关卡」，现在整扇门就这一张面片、五次贴图采样。
// 噪声查 fx/cine/cine_noise.png（R / B = 分形噪声，8 个单位一个周期；G = 单层值噪声，64 格一个周期）。
// 混合用预乘：门里不透明（盖住后面的东西），门外的辉光是纯加色。
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float radius = 0.58;      // 门洞半径占面片半宽的几成（外面那圈留给辉光）
uniform float open = 1.0;         // 0 合着 → 1 全开
uniform float pulse = 0.0;        // 有人走近时亮一点（0 ~ 1）

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash2f(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float rr = radius * open;
	float t = TIME;
	// 旋涡坐标：越靠里拧得越多，整体慢慢转
	float sw = 1.5 / (r + 0.3) + t * 0.2;
	float cs = cos(sw);
	float sn = sin(sw);
	vec2 q = vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
	float arms = texture(noise_tex, q * 0.14 + vec2(0.11, 0.37)).r;                              // 旋臂（宽）
	float fine = textureLod(noise_tex, (q * 11.0 + vec2(t * 0.7, 0.0)) * 0.015625, 0.0).g;      // 细丝 / 电弧

	// ---- 门里的太空：按视线方向取样 ----
	vec3 vd = normalize(wpos - CAMERA_POSITION_WORLD);
	vec2 sv = vd.xz / (abs(vd.y) + 0.75) * 2.4 + vec2(vd.y * 0.6, vd.y * 1.3);
	// 星云：形状长在门上（门洞里总能看到几团，离远了也不会只剩一片渐变），再按视线方向错开一点（走动时有前后层次）；
	// 越靠门沿越被旋涡扯着卷，门心留暗，星云聚在中圈
	vec2 pl = mix(p, q, 0.35 + 0.5 * smoothstep(rr * 0.3, rr, r));
	float n1 = texture(noise_tex, (pl * 3.4 + sv * 1.1) * 0.125 + vec2(t * 0.004, 0.2)).r;
	float n2 = texture(noise_tex, (pl * 6.5 + sv * 2.0) * 0.125 + vec2(0.63, -t * 0.006)).b;
	float mid = smoothstep(rr * 0.12, rr * 0.7, r);
	vec3 space = vec3(0.020, 0.010, 0.055);
	float blue = smoothstep(0.46, 0.74, n1) * (0.35 + 0.65 * mid);
	space += vec3(0.08, 0.30, 0.90) * blue * sqrt(blue) * 0.85;                                   // 蓝色星云
	space += vec3(0.85, 0.20, 0.70) * smoothstep(0.52, 0.78, n2) * smoothstep(0.36, 0.62, n1) * 0.6 * mid;   // 品红
	float hot = smoothstep(0.64, 0.84, n1) * mid;
	space += vec3(0.50, 0.95, 1.0) * hot * hot * 0.7;                                             // 最浓的地方发青白
	// 星点：两层格子，一格一颗，亮度随机，近的那层会闪
	vec2 g1 = sv * 26.0;
	vec2 c1 = floor(g1);
	float h1 = hash2f(c1);
	vec2 o1 = fract(g1) - 0.5 - (vec2(hash2f(c1 + 7.1), hash2f(c1 + 3.7)) - 0.5) * 0.6;
	float stars = step(0.80, h1) * smoothstep(0.11, 0.0, length(o1)) * (0.6 + 0.4 * sin(t * (1.5 + h1 * 3.0) + h1 * 40.0));
	vec2 g2 = sv * 61.0 + 13.0;
	stars += step(0.86, hash2f(floor(g2))) * smoothstep(0.17, 0.0, length(fract(g2) - 0.5)) * 0.6;
	space += vec3(0.9, 0.92, 1.0) * stars;
	// 门洞里贴边的一圈紫雾（跟着旋臂明暗）
	float haze = smoothstep(rr * 0.42, rr, r);
	space = mix(space, vec3(0.42, 0.16, 0.82) * (0.45 + 1.0 * arms), haze * haze * 0.8);

	// ---- 门沿和门外的光 ----
	float edge = rr * (1.0 + (arms - 0.47) * 0.12);                // 参差的门沿
	float inside = 1.0 - smoothstep(edge - 0.012, edge + 0.012, r);
	float rim = exp(-abs(r - edge) * 26.0);
	float halo = exp(-max(r - edge, 0.0) * 4.4) * (1.0 - inside);
	float streak = smoothstep(0.42, 0.72, arms);
	float f2 = fine * fine;
	float arc = f2 * f2 * f2 * fine;                               // 细电弧
	vec3 glow = vec3(0.60, 0.28, 1.0) * halo * (0.22 + 0.78 * streak) * 0.95
			+ vec3(0.93, 0.82, 1.0) * rim * (0.85 + 0.6 * streak)
			+ vec3(0.86, 0.76, 1.0) * arc * halo * 1.5;
	glow *= (1.0 - smoothstep(0.82, 1.0, r)) * (1.0 + 0.45 * pulse) * step(0.02, open);
	vec3 col = space * inside + glow;
	// col 按屏幕上看到的颜色调。兼容渲染器（网页 / 手机）直接交；桌面的渲染器要先转成线性
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = col;
#else
	ALBEDO = pow(col, vec3(2.2));
#endif
	ALPHA = inside;
}
