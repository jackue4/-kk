shader_type canvas_item;
// 把一张带透明度的图压成一块纯色的剪影（2D 立绘身后的硬投影用）。
uniform vec4 tint : source_color = vec4(0.09, 0.078, 0.102, 1.0);

void fragment() {
	COLOR = vec4(tint.rgb, step(0.5, texture(TEXTURE, UV).a) * tint.a);
}
