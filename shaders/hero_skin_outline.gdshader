// 主角皮肤模型的描边（scripts/hero_skin.gd 的 set_line，2026-11-23）：觉醒描边 / PvP 锁定描边在皮肤模型上的那一遍。
// 参数和方块人的 block_outline.gdshader 一一对应（线色 / 线宽 / 淡入 / 泛白 / 闪动），区别只在往哪个方向撑：
// 方块人按方块角的方向，这里是带骨骼的网格，沿法线撑 —— 用的是法线磨平过的网格副本（面与面的接缝不裂开），骨骼照样带着它动。
// 线宽在视空间里按米算（模型节点上有 0.01 的缩放，不能在模型空间里加）。
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec3 line_color : source_color = vec3(0.5, 0.9, 1.0);
uniform float width = 0.026;
uniform float power = 1.0;
uniform float push = 0.16;
uniform float whiten = 0.25;
uniform float flicker = 1.0;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
const float ENERGY = 1.0;
#else
const float ENERGY = 1.5;
#endif

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(vp.xyz);
	float w = width * power * clamp(dist / 7.0, 1.0, 3.5) * mix(1.0, 0.88 + 0.12 * sin(TIME * 7.0), flicker);
	vp.xyz += normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz) * w;
	vp.xyz += normalize(vp.xyz) * push;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = mix(line_color, vec3(1.0), whiten) * mix(1.0, 0.9 + 0.1 * sin(TIME * 7.0), flicker) * ENERGY;
}
