shader_type spatial;
// 生物模型的叠加层（material_overlay）：受击闪白 + 精英 / Boss / 高品阶掉落的轮廓泛光 + 暗的区域里所有怪都有的一圈轮廓光。
// 只加亮、不改原贴图；不用的时候脚本会把叠加层摘掉，不多一遍绘制。
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.6, 0.2);
uniform float rim = 0.0;      // 轮廓泛光强度（精英 / Boss，会呼吸）
uniform float flash = 0.0;    // 受击闪白
uniform vec3 edge_col : source_color = vec3(1.0, 1.0, 1.0);
uniform float edge = 0.0;     // 区域给的轮廓光（血色禁地 / 坠魔谷）：边上一圈亮、全身再垫一点底，深色的怪不会融进深色的地

void fragment() {
	float nv = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float f = pow(nv, 3.2);
	float pulse = 0.8 + 0.2 * sin(TIME * 3.0);
	ALBEDO = tint * (f * rim * pulse + rim * 0.04) + edge_col * edge * (pow(nv, 2.6) * 1.1 + 0.035) + vec3(flash * 0.85);
}
