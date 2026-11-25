shader_type canvas_item;
// 一笔干刷：沿 UV.x 方向刷过去的一道颜色，上下边和两头都是一丝丝的飞白（手绘稿上大笔刷出来的色块）。
// 放在一个 ColorRect 上，整个矩形转个角度用。

uniform vec4 fill : source_color = vec4(0.945, 0.545, 0.1, 1.0);
uniform float rows = 70.0;           // 这一笔有多少根毛
uniform float seed = 1.0;
uniform float reveal = 1.0;          // 0 → 1 一笔刷过去

float hash(float n) {
	return fract(sin(n * 91.7 + seed * 13.1) * 43758.5453);
}

void fragment() {
	float row = floor(UV.y * rows);
	float h1 = hash(row);
	float h2 = hash(row + 37.0);
	float h3 = hash(floor(row / 4.0) + 71.0);
	// 越靠上下边，这根毛越短、越容易断
	float mid = 1.0 - abs(UV.y - 0.5) * 2.0;
	float body = smoothstep(0.0, 0.45, mid);
	float x0 = (0.02 + 0.2 * h1 * h1) * (1.6 - body) + 0.05 * h3;
	float x1 = 1.0 - (0.03 + 0.34 * h2 * h2) * (1.7 - body) - 0.06 * h3;
	float a = step(x0, UV.x) * step(UV.x, x1);
	// 飞白：有的毛蘸的颜料少，刷到后半截就断断续续
	float dry = step(0.78 + 0.2 * body, hash(row + 5.0));
	float gap = step(0.5, fract(UV.x * (3.0 + 9.0 * h2) + h1));
	a *= 1.0 - dry * gap * step(0.35, UV.x);
	a *= step(0.06 * (1.0 - body), h3 + mid);
	a *= step(UV.x, reveal * 1.02);
	COLOR = vec4(fill.rgb, fill.a * a);
}
