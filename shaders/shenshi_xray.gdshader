// 神识透视（scripts/shen_shi.gd，2026-11-23）：被神识扫到的目标身上挂一份「影子网格」（同一份网格、同一副骨架，跟着动画走），
// 用这个材质再画一遍：不做深度测试，隔着山、隔着墙也画得出来；加色的边缘光（菲涅耳）+ 淡淡一层底色 + 往上流的几道光纹。
// 只在被扫到的头几秒开（power 0~1 淡入淡出），让玩家知道东西大概在哪个方向。
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.6, 0.9, 1.0);
uniform float power = 0.0;

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = f * f;
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = 0.5 + 0.5 * sin(wpos.y * 5.0 - TIME * 5.0);
	float s2 = s * s;
	float band = s2 * s2 * s2 * 0.35;
	vec3 c = mix(tint, vec3(1.0), rim * 0.35) * (0.32 + rim * 2.1 + band);
	ALBEDO = c * power;
	ALPHA = 1.0;
}
