// 主角皮肤模型（scripts/hero_skin.gd，2026-11-23）：带骨骼的贴图网格。
// 受击闪白 / 化光这两个参数和方块人（block.gdshader）同名同义，voxel_hero.gd 的 set_flash / set_glow 两边一起设。
// floor_glow：按贴图本来的颜色自带一点底光（和怪的模型一个做法）—— 脸背光、站在影子里也不会黑成一团。
// 贴图带透明通道的皮肤（冰雪战士的纱）：透明度不到 1 的地方按屏幕格点抖动着丢像素 —— 还在不透明队列里画，不用排序；
//   贴图不带透明的皮肤一个像素也不丢，画面和原来一样。
// rim：边缘光（默认 0 = 没有）。贴图是纯黑的皮肤（霸哥）靠它勾出体积，不然就是屏幕上的一块黑洞。
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float rough : hint_range(0.0, 1.0) = 0.8;
uniform float floor_glow : hint_range(0.0, 1.0) = 0.16;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.4, 0.7, 1.0);
uniform float rim : hint_range(0.0, 2.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.55, 0.62, 0.78);

const float BAYER[16] = float[](0.03, 0.53, 0.16, 0.66, 0.78, 0.28, 0.91, 0.41, 0.22, 0.72, 0.09, 0.59, 0.97, 0.47, 0.84, 0.34);

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	if (tex.a < 0.98) {
		ivec2 cell = ivec2(FRAGCOORD.xy) & ivec2(3);
		if (tex.a < BAYER[cell.y * 4 + cell.x]) {
			discard;
		}
	}
	vec3 base = tex.rgb;
	ALBEDO = mix(base, vec3(1.0), flash * 0.6);
	ALBEDO = mix(ALBEDO, mix(glow_color, vec3(1.0), 0.35), glow * 0.85);
	float edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	EMISSION = base * floor_glow * (1.0 - glow) + vec3(1.0, 0.95, 0.9) * flash * 0.25 + glow_color * glow * 1.6 + rim_color * edge * rim * (1.0 - glow);
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
