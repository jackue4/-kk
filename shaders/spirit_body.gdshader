shader_type spatial;
// 元婴法相的灵体材质（yuanying_cine.gd 把它罩在一个放大的方块人身上）：通体青色、自己发光、半透明，
// 身上有往上流的光纹和一闪一闪的细碎光点，轮廓泛白；衣服上的金边保留成金色；头发和眉眼是亮的青白。
// reveal：自下而上显形（一道亮边扫上去）；dissolve：收功时自下而上、一小格一小格地化成光点散掉（正在散的那一圈烧成金白色）。
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back, shadows_disabled, fog_disabled;

// 颜色都按「屏幕上看到的颜色」写，最后统一转线性；顶点色到这里已经是线性的，先转回来再判断深浅
uniform vec3 tint = vec3(0.16, 0.78, 0.70);
uniform vec3 deep = vec3(0.03, 0.26, 0.30);
uniform vec3 gold = vec3(1.0, 0.80, 0.42);
uniform float alpha = 0.96;
uniform float reveal = 1.0;
uniform float base_y = 0.0;
uniform float height = 34.0;
uniform float boost = 1.0;
uniform float dissolve = 0.0;    // 消散 0 完整 → 1 散尽

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	// src：身上本来的颜色（屏幕色）。桌面的渲染器里顶点色存的是线性色，要转回来；兼容渲染器（网页 / 手机）里存的就是屏幕色
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 src = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));
#else
	vec3 src = pow(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
#endif
	float lum = dot(src, vec3(0.3, 0.59, 0.11));
	// 金边：又暖又浓的颜色（肤色暖但不浓，不算）
	float warm = smoothstep(0.38, 0.52, (src.r - src.b) / max(src.r, 0.01)) * smoothstep(0.25, 0.45, lum);
	// 头发 / 眉 / 靴这些最深的颜色：反过来最亮
	float hair = 1.0 - smoothstep(0.1, 0.2, lum);
	vec3 body = mix(deep, tint, clamp(lum * 0.85 + 0.12, 0.0, 1.0));
	body = mix(body, vec3(0.62, 0.95, 0.9), hair * 0.8);
	float flow = sin(wp.y * 0.85 - TIME * 1.7 + sin(wp.x * 0.6 + wp.z * 0.45) * 2.2) * 0.5 + 0.5;
	body += tint * flow * flow * 0.22;
	float h = hash3(floor(wp * 2.6));
	body += vec3(0.6, 0.95, 0.88) * step(0.95, h) * (0.5 + 0.5 * sin(TIME * 3.2 + h * 40.0)) * 0.55;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	body += tint * fres * 0.55 + vec3(fres * fres * 0.12);
	vec3 col = mix(body, gold * (0.85 + 0.4 * fres + 0.2 * flow), warm * 0.9);
	float y01 = (wp.y - base_y) / height;
	float edge = reveal * 1.2 - 0.05;
	float vis = 1.0 - smoothstep(edge - 0.07, edge, y01);
	col += vec3(1.0, 0.97, 0.85) * smoothstep(edge - 0.14, edge - 0.02, y01) * 0.7 * step(reveal, 0.995);
	// 消散：每一小格（世界里一米二见方）有自己的先后，整体从脚往头走；快轮到的格子先烧亮，轮到了就没了。
	// 只多一次哈希，手机上不心疼；散出去的光点是另外一个粒子系统（yuanying_cine.gd 的 _motes）
	float gone = 0.0;
	if (dissolve > 0.0) {
		float dz = clamp(y01, 0.0, 1.0) * 0.55 + hash3(floor(wp * 0.8) + vec3(3.0, 11.0, 7.0)) * 0.45;
		float thr = dissolve * 1.14 - 0.07;
		gone = 1.0 - smoothstep(thr, thr + 0.025, dz);
		col += vec3(1.0, 0.93, 0.74) * (1.0 - smoothstep(thr + 0.02, thr + 0.13, dz)) * 1.2;
	}
	// col 是按屏幕色调的。兼容渲染器里 ALBEDO 本来就按屏幕色（sRGB）解释，不能再转一次线性
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = clamp(col, vec3(0.0), vec3(1.2)) * pow(boost, 0.4545);
#else
	ALBEDO = pow(clamp(col, vec3(0.0), vec3(1.2)), vec3(2.2)) * boost;
#endif
	ALPHA = alpha * vis * (1.0 - gone) * clamp(0.9 + fres * 0.2 + warm * 0.2, 0.0, 1.0);
}
