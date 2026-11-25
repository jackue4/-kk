// 铺在世界里的空间波动（scripts/qi_fx.gd，2026-11-25）：一张以人为中心、水平摆着的圆片，上面一圈圈波纹沿着这张片往里收 / 往外荡，
// 片盖住的那块画面跟着波纹挪动（折射）。和 aura_warp.gdshader 是同一种波动，区别：那个面片永远朝着镜头（看着像贴在屏幕上——
// 用户：「效果要在世界场景中的，基于玩家为中心，围绕在周边的空间波动，现在看起来像是屏幕上的」），这个片有自己的朝向，
// 波纹的挪动方向按片在屏幕上的投影算，所以镜头一转，看到的是地面上方一圈有透视的涟漪。
// pulse = 那道最强的波前现在在片的多远处（0 中心 … 1 外沿），由脚本推着走：攒气从外往里，爆开从里往外。
// 手机档（Compatibility）：不读屏幕，画明暗成对的波纹线。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.5, 0.9, 1.0);
uniform float power = 0.0;
uniform float strength = 0.05;         // 挪多远（占片半径的比例）
uniform float pulse = 1.0;
uniform float front_k = 1.0;           // 波前有多强
uniform float flow_dir = 1.0;          // 细波往哪走：1 往外 · -1 往里
uniform float calm = 0.5;              // 细波的幅度倍数
uniform float hole = 0.1;              // 中间留空的半径（人站的地方）

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
varying vec2 sx;                       // 片的本地 +X / +Y 半径在屏幕上是哪个方向、多长（SCREEN_UV 单位）
varying vec2 sy;

void vertex() {
	mat4 mvp = PROJECTION_MATRIX * MODELVIEW_MATRIX;
	vec4 c0 = mvp * vec4(0.0, 0.0, 0.0, 1.0);
	// 只往外量一小步再放大十倍：直接量到片的边上，那个点可能在镜头背后
	vec4 cx = mvp * vec4(0.05, 0.0, 0.0, 1.0);
	vec4 cy = mvp * vec4(0.0, 0.05, 0.0, 1.0);
	vec2 n0 = c0.xy / max(c0.w, 0.05);
	sx = (cx.xy / max(cx.w, 0.05) - n0) * vec2(5.0, -5.0);
	sy = (cy.xy / max(cy.w, 0.05) - n0) * vec2(5.0, -5.0);
}
#endif

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 dl = p / max(r, 1e-3);
	float mask = smoothstep(hole * 0.6, hole * 1.8, r) * (1.0 - smoothstep(0.72, 1.0, r)) * power;
	float ph = r * 26.0 - TIME * 7.0 * flow_dir + sin(dl.x * 2.6 + dl.y * 1.7 + TIME * 1.1) * 1.1 + sin(dl.y * 5.3 - dl.x * 3.9 - TIME * 1.7) * 0.5;
	float wave = sin(ph);
	float front = exp(-(r - pulse) * (r - pulse) / 0.004) * front_k;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	float amt = (wave * 0.6 * calm + front * 3.0) * strength * mask;
	vec2 off = (sx * dl.x - sy * dl.y) * amt;      // UV 的 y 朝下 = 本地 -Y
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV + off * 1.06).r;
	col.g = texture(screen_tex, SCREEN_UV + off).g;
	col.b = texture(screen_tex, SCREEN_UV + off * 0.94).b;
	float crest = max(wave, 0.0);
	col += tint * (crest * crest * 0.06 * calm + front * 0.28) * mask;
	ALBEDO = col;
	ALPHA = clamp(mask * 6.0, 0.0, 1.0);
#else
	float c2 = wave * wave;
	float line = c2 * c2 * c2;
	float lit = step(0.0, wave);
	float brk = 0.55 + 0.45 * sin(dl.x * 4.0 - dl.y * 3.0 + r * 9.0 - TIME * 0.8);
	ALBEDO = mix(vec3(0.05, 0.06, 0.1), mix(tint, vec3(1.0), 0.45), max(lit, min(front * 2.0, 1.0)));
	ALPHA = clamp((line * mix(0.26, 0.4, lit) * brk * calm + front * 0.5) * mask, 0.0, 1.0);
#endif
}
