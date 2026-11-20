// 觉醒时身周的空间波动（awaken_fx.gd）：一张朝着镜头的面片罩在修士身上，身体所在的那条椭圆留空，四周一圈圈往外荡。
// 桌面档：读屏幕，把面片盖住的那块画面按波形挪一挪（折射），波峰上带一点色散和境界色的微光；
//         材质的 render_priority 调到最低，在所有半透明特效之前画，所以身边的剑光、火花不会被它盖掉。
// 手机档（Compatibility）：不读屏幕（读屏幕要每帧整屏拷一份，觉醒一开十几秒，太贵），只画一圈圈明暗成对的淡波纹线。
// pulse：一道更强的波前从里荡到外（0 → 1；1 = 没有），境界越高来得越勤。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.5, 0.9, 1.0);
uniform float power = 0.0;             // 0~1：淡入淡出
uniform float strength = 0.035;        // 扭曲幅度（占面片半径的比例）
uniform vec2 axis = vec2(0.0, 1.0);    // 身体在屏幕上的朝向：留空的椭圆顺着它
uniform float pulse = 1.0;
uniform float gap = 1.0;               // 1 = 中间留出身体那条椭圆；0 = 不留（Vfx.space_ring 那种一次性的波动圈）
uniform float calm = 1.0;              // 持续荡着的那几圈的幅度倍数（一次性的波动圈调小，主要看那道波前）

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
varying vec2 scr;                      // 面片半径在屏幕上占多少（SCREEN_UV 的横、竖单位）

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float half_size = length(MODEL_MATRIX[0].xyz) * 0.5;
	scr = vec2(abs(PROJECTION_MATRIX[0][0]), abs(PROJECTION_MATRIX[1][1])) * half_size / max(-c.z, 0.1) * 0.5;
}
#endif

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 dir = p / max(r, 1e-3);
	// 身体那一条留空，外沿淡出
	float along = dot(p, axis);
	float across = dot(p, vec2(-axis.y, axis.x));
	float hole = mix(1.0, smoothstep(1.0, 1.9, length(vec2(across / 0.17, along / 0.44))), gap);
	float mask = hole * (1.0 - smoothstep(0.5, 1.0, r)) * power;
	// 往外荡的波：沿环向再叠两道起伏，把同心圆打散（不然像靶子）
	float ph = r * 21.0 - TIME * 6.5 + sin(dir.x * 2.6 + dir.y * 1.7 + TIME * 1.1) * 1.3 + sin(dir.y * 5.3 - dir.x * 3.9 - TIME * 1.7) * 0.5;
	float wave = sin(ph);
	float pr = mix(0.14, 1.0, pulse);
	float front = exp(-(r - pr) * (r - pr) / 0.005) * (1.0 - pulse);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	vec2 off = dir * (wave * 0.6 * calm + front * 3.2) * strength * mask * scr;
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV + off * 1.05).r;
	col.g = texture(screen_tex, SCREEN_UV + off).g;
	col.b = texture(screen_tex, SCREEN_UV + off * 0.95).b;
	float crest = max(wave, 0.0);
	col += tint * (crest * crest * 0.045 * calm + front * 0.22) * mask;
	ALBEDO = col;
	ALPHA = clamp(mask * 6.0, 0.0, 1.0);
#else
	// 没有折射可用：波峰画一道亮线、波谷画一道暗线，成对出现，像空气被压出了一圈圈明暗（亮背景、暗背景上都读得出来）
	float c2 = wave * wave;
	float line = c2 * c2 * c2;
	float lit = step(0.0, wave);
	float brk = 0.55 + 0.45 * sin(dir.x * 4.0 - dir.y * 3.0 + r * 9.0 - TIME * 0.8);
	ALBEDO = mix(vec3(0.05, 0.06, 0.1), mix(tint, vec3(1.0), 0.45), max(lit, min(front * 2.0, 1.0)));
	ALPHA = clamp((line * mix(0.24, 0.36, lit) * brk * calm + front * 0.45) * mask, 0.0, 1.0);
#endif
}
