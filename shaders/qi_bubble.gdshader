// 觉醒那一下从身体里鼓出来的气罩（scripts/qi_fx.gd，2026-11-25）：一个球，零点二秒里从身边胀到十来米，随即散掉。
// 桌面档：读屏幕，球面上的画面按法线方向挪开（像隔着一层鼓起来的水膜看东西），边缘厚、中间薄，带一点乳白；
// 手机档（Compatibility）：不读屏幕，只画边缘那一圈乳白的膜。
// 参考（用户给的突破录像）：突破的一瞬间一个半透明的罩子从人身上鼓出来、胀满画面，后面才是往外冲的气流。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.6, 1.0, 0.92);
uniform float age = 0.0;          // 0 → 1
uniform float strength = 0.06;    // 折射挪多远（屏幕比例）

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
#endif

void fragment() {
	vec3 nv = normalize(NORMAL);
	float facing = abs(dot(nv, normalize(VIEW)));
	float rim = 1.0 - facing;
	float fade = (1.0 - age) * (1.0 - age);
	// 膜上一圈圈的纹（顺着视线法线的角度起伏）：不是一片死白
	float bands = 0.5 + 0.5 * sin(rim * 26.0 - age * 9.0);
	float milk = (pow(rim, 1.6) * 0.75 + 0.1 + 0.12 * bands * rim) * fade;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	vec2 off = nv.xy * vec2(1.0, -1.0) * strength * (0.35 + rim * 1.4) * fade;
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV + off * 1.06).r;
	col.g = texture(screen_tex, SCREEN_UV + off).g;
	col.b = texture(screen_tex, SCREEN_UV + off * 0.94).b;
	ALBEDO = mix(col, mix(tint, vec3(1.0), 0.6), clamp(milk, 0.0, 0.85));
	ALPHA = clamp(fade * 3.0, 0.0, 1.0);
#else
	ALBEDO = mix(tint, vec3(1.0), 0.6);
	ALPHA = clamp(milk * 0.9, 0.0, 0.85);
#endif
}
