// 神识一扫时主角身周的「空间神识波动」（scripts/shen_shi.gd，2026-11-23，参考用户给的图一）：一张平铺在脚下的面片（PlaneMesh，UV 中心 = 主角）。
// 画：几道细亮、边上带七彩的光环（境界越高圈数越多、电弧越躁）+ 一道往外推的波前 + 一圈圈往外荡的涟漪 + 中间一层淡光晕。
// 桌面档：读屏幕，把涟漪那几圈底下的画面沿半径挪一挪（空间被神识荡开的扭曲）；
// 手机档（Compatibility）：不读屏幕，涟漪画成明暗成对的细线（同 aura_warp.gdshader 的做法），整体只开两三秒。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float t = 0.0;              // 出现以来的秒数
uniform float life = 3.0;           // 总时长（秒）
uniform float power = 1.0;          // 总亮度（境界）
uniform float rings = 2.0;          // 光环圈数 1~4
uniform float jit = 0.3;            // 电弧抖动 0~1
uniform float irid = 0.5;           // 七彩 0~1
uniform vec3 col_a : source_color = vec3(0.8, 0.95, 1.0);
uniform vec3 col_b : source_color = vec3(0.6, 0.8, 1.0);
uniform float warp = 0.05;          // 扭曲幅度（桌面档）

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
#endif

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 dir = p / max(r, 1e-3);
	float ang = atan(p.y, p.x);
	float grow = 1.0 - exp(-t * 6.0);                       // 光环张开
	float fade = (1.0 - smoothstep(life * 0.55, life, t)) * smoothstep(0.0, 0.06, t);
	vec3 col = vec3(0.0);
	float a = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		if (fi >= rings) {
			break;
		}
		float rr = (0.24 + 0.11 * fi) * grow;
		// 圈上的电弧：几道高频起伏叠起来；再叠一道低频的慢慢呼吸，整圈略扭、不是正圆
		float wob = (sin(ang * (19.0 + fi * 7.0) + t * (9.0 + fi * 3.0)) * 0.5 + sin(ang * (47.0 + fi * 13.0) - t * 15.0) * 0.3
				+ sin(ang * 103.0 + t * 23.0 + fi) * 0.2) * jit * 0.011;
		float slow = sin(ang * 3.0 + fi * 1.7 + t * 1.3) * 0.01 + sin(ang * 5.0 - fi * 2.3 - t * 0.9) * 0.006;
		float x = r - rr - wob - slow;
		float w = 0.0042 - 0.0006 * fi;
		float core = exp(-x * x / (w * w));
		float halo = exp(-x * x / (w * w * 30.0));
		float h = fract(ang * 0.159 + fi * 0.21 + t * 0.15 + x * 14.0);
		vec3 ir = 0.55 + 0.45 * cos(6.2832 * (h + vec3(0.0, 0.33, 0.67)));
		vec3 tint = mix(col_a, col_b, 0.5 + 0.5 * sin(ang * 2.0 + fi * 1.3 + t * 0.5));
		vec3 fr = mix(tint, ir, irid);
		float k = 1.0 - fi * 0.17;
		col += (vec3(1.0) * core * 0.95 + fr * halo * 0.6) * k;
		a = max(a, max(core, halo * 0.7) * k);
	}
	// 一道波前从光环处推到面片边上（头 0.9 秒）
	float pf = 0.24 + 0.78 * (1.0 - exp(-t * 2.4));
	float front = exp(-(r - pf) * (r - pf) / 0.0025) * (1.0 - smoothstep(0.8, 1.0, pf));
	// 一圈圈往外荡的涟漪：沿圆周再加两道起伏，把同心圆打散（不然像靶子）
	float ph = r * 34.0 - t * 8.0 + sin(dir.x * 2.6 + dir.y * 1.7 + t * 1.1) * 1.2 + sin(dir.y * 5.3 - dir.x * 3.9 - t * 1.7) * 0.5;
	float wave = sin(ph);
	float rip_m = smoothstep(0.18, 0.32, r) * (1.0 - smoothstep(0.7, 1.0, r));
	float glow = exp(-r * r * 9.0) * 0.22;
	vec3 tint0 = mix(col_a, col_b, 0.5);
	col += tint0 * glow + mix(tint0, vec3(1.0), 0.4) * front * 0.7;
	a = max(a, max(glow, front * 0.8));
	col *= power * fade;
	float edge = 1.0 - smoothstep(0.9, 1.0, r);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// 半径方向在屏幕上朝哪：把面片上的径向转到视空间，按距离折算成屏幕 UV 的偏移
	vec3 wdir = (MODEL_MATRIX * vec4(dir.x, 0.0, dir.y, 0.0)).xyz;
	vec3 vdir = (VIEW_MATRIX * vec4(normalize(wdir), 0.0)).xyz;
	float amt = (wave * 0.55 * rip_m + front * 2.2) * warp * power * fade * edge;
	vec2 off = vec2(vdir.x, -vdir.y) * amt / max(-VERTEX.z, 1.5);
	vec3 bg = texture(screen_tex, SCREEN_UV + off).rgb;
	float crest = max(wave, 0.0);
	ALBEDO = bg + col + tint0 * crest * crest * 0.05 * rip_m * power * fade;
	ALPHA = clamp(max(rip_m * fade * 3.0, a * fade * power), 0.0, 1.0) * edge;
#else
	// 没有折射：波峰一道亮线、波谷一道暗线成对出现，像空气被荡出一圈圈明暗
	float c2 = wave * wave;
	float line = c2 * c2 * c2 * rip_m * fade * power;
	float lit = step(0.0, wave);
	float brk = 0.55 + 0.45 * sin(dir.x * 4.0 - dir.y * 3.0 + r * 9.0 - t * 0.8);
	vec3 lc = mix(vec3(0.05, 0.06, 0.1), mix(tint0, vec3(1.0), 0.45), lit);
	float la = line * mix(0.22, 0.34, lit) * brk;
	float ca = clamp(a * fade * power, 0.0, 1.0);
	ALBEDO = mix(lc, col / max(ca, 0.05), clamp(ca / max(ca + la, 1e-3), 0.0, 1.0));
	ALPHA = clamp(ca + la, 0.0, 1.0) * edge;
#endif
}
