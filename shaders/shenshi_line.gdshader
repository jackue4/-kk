// 神识描边（scripts/shen_shi.gd，2026-11-23）：被扫到的目标的「影子网格」只画背面、往外撑一圈 = 一道轮廓线。
// 有深度测试（被挡住的地方不画，看得见的时候才有线；隔着山的方位交给透视那一遍）。
//   corner = 1：方块人（voxel_hero.gd 的每一件，UV / UV2.x 里存着方块角的方向，同 block_outline.gdshader，棱角不开缝）
//   corner = 0：资源库模型（带骨骼的 GLB）沿法线撑出去
// 线宽在视空间里按米算，离得远就放宽（屏幕上始终看得见）；撑出去之后再顺着视线往远处挪一点，挨得近的零件之间不出线。
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.6, 0.9, 1.0);
uniform float power = 0.0;
uniform float width = 0.035;
uniform float corner = 0.0;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
const float ENERGY = 1.05;
#else
const float ENERGY = 1.35;
#endif

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(vp.xyz);
	float w = width * power * clamp(dist / 7.0, 1.0, 12.0);
	vec3 dir;
	if (corner > 0.5) {
		dir = (MODELVIEW_MATRIX * vec4(vec3(UV, UV2.x), 0.0)).xyz;
	} else {
		dir = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
	vp.xyz += dir * w;
	vp.xyz += normalize(vp.xyz) * 0.12;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = mix(tint, vec3(1.0), 0.08) * (0.88 + 0.12 * sin(TIME * 6.0)) * ENERGY;
}
