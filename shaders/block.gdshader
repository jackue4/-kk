// 方块人（voxel_hero.gd）：光面塑料质感的整块方块，顶点色上色；棱边的圆角是网格里真切出来的倒角。
shader_type spatial;

uniform float rough : hint_range(0.0, 1.0) = 0.55;
// 受击闪白（独立材质才用）
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 化光（主角化作光剑 / 由光剑现形的过渡）：整身染成遁光色并自发光
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.4, 0.7, 1.0);

void fragment() {
	ALBEDO = mix(COLOR.rgb, vec3(1.0), flash * 0.6);
	ALBEDO = mix(ALBEDO, mix(glow_color, vec3(1.0), 0.35), glow * 0.85);
	EMISSION = vec3(1.0, 0.95, 0.9) * flash * 0.25 + glow_color * glow * 1.6;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
