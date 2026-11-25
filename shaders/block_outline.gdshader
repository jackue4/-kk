// 方块人的描边（voxel_hero.gd 的 set_outline）：挂在身体材质的 next_pass 上，只画背面、把每个方块往外撑一圈。
// 方块的每个顶点都带着它所在那个角的方向（UV = x、y，UV2.x = z，各为 ±1）：照这个方向推出去，整块正好大一圈，棱角不开缝。
// 推出去之后再顺着视线往远处挪一点（屏幕上的位置不变）：身上挨得近的小零件之间不出线，只留外轮廓和前后隔得开的肢体之间那一道。
// 只在描边开着的时候才挂上这一遍；不读屏幕、不透明，手机档多出来的只是身体那二十来件再画一次背面。
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec3 line_color : source_color = vec3(0.5, 0.9, 1.0);
uniform float width = 0.026;     // 线宽（米）；离镜头远了按距离放宽，屏幕上始终看得见
uniform float power = 1.0;       // 0~1：淡入淡出（线宽跟着收）
uniform float push = 0.16;       // 顺着视线往远处挪多少（米）
// 2026-11-21 PvP 锁定描边（voxel_hero.gd 的 set_lock_outline）用：whiten 线色往白里掺多少、flicker 线宽 / 亮度跟着闪多少。默认值 = 觉醒描边原样
uniform float whiten = 0.25;
uniform float flicker = 1.0;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
const float ENERGY = 1.0;
#else
const float ENERGY = 1.5;
#endif

void vertex() {
	vec3 corner = vec3(UV, UV2.x);
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float w = width * power * clamp(dist / 7.0, 1.0, 3.5) * mix(1.0, 0.88 + 0.12 * sin(TIME * 7.0), flicker);
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX + corner * w, 1.0);
	vp.xyz += normalize(vp.xyz) * push;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = mix(line_color, vec3(1.0), whiten) * mix(1.0, 0.9 + 0.1 * sin(TIME * 7.0), flicker) * ENERGY;
}
