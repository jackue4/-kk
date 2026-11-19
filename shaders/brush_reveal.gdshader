// 毛笔题字的书写遮罩：front（本地 y）以上可见，前沿是一道毛糙的笔锋；前沿附近的笔画略微发亮（湿墨）。
// 用在 realm_banner.gd 的字层上：该层不做 draw_set_transform，VERTEX 就是层内坐标。
shader_type canvas_item;

uniform float front = -1000.0;
uniform float jag = 12.0;

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float j = 0.5 + 0.3 * sin(lp.x * 0.09 + front * 0.05) + 0.2 * sin(lp.x * 0.23 + 1.3);
	float edge = front - jag * j;
	COLOR.a *= 1.0 - smoothstep(edge - 3.0, edge, lp.y);
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), 0.45 * (1.0 - smoothstep(0.0, 22.0, edge - lp.y)));
}
