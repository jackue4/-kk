// 飞剑对波 · 能量束：套在一根圆柱上（本地 +Y 指向交汇点，高 1、半径 1，由 clash_fx.gd 拉伸摆位）。
// 正对镜头的中轴是白热的芯，往边缘过渡到气劲的颜色再淡出；表面有一道道沿长度方向拉长的能量纹，朝交汇点流。
// power：压制对方时粗壮明亮（> 1），被压时发虚、忽明忽暗（< 1）。pulse_pos：连点时从出手处推向交汇点的一道亮带。
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled, cull_back;

#include "res://shaders/clash_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(0.4, 0.85, 1.0, 1.0);
uniform float intensity = 2.0;
uniform float alpha = 1.0;
uniform float flow = 0.0;        // 脚本推进（0~512 循环）：能量往交汇点流
uniform float power = 1.0;
uniform float pulse_pos = -1.0;  // 0~1 沿光束的位置，< 0 = 没有
uniform float length_m = 10.0;   // 光束实际长度（米）：条纹疏密不随长度变

varying float v_along;

void vertex() {
	v_along = VERTEX.y + 0.5;    // 0 出手处 ~ 1 交汇点
}

void fragment() {
	float f = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float along = v_along * length_m;
	// 绕一圈无缝：拿角度的 cos / sin 当噪声坐标
	vec2 ring = vec2(cos(UV.x * TAU), sin(UV.x * TAU));
	float n1 = clash_noise(vec2(ring.x * 1.7 + along * 0.16, ring.y * 1.7 + along * 0.42 - flow * 7.0) + 600.0);
	float n2 = clash_noise(vec2(ring.x * 3.6 - along * 0.2, ring.y * 3.6 + along * 1.1 - flow * 13.0) + 900.0);
	float streak = 0.45 + 1.5 * n1 * n2;
	float core = pow(f, 5.0);
	float body = pow(f, 1.5);
	// 被压时忽明忽暗
	float weak = clamp(1.0 - power, 0.0, 1.0);
	float flick = mix(1.0, 0.45 + 0.55 * clash_noise(vec2(flow * 40.0, along * 0.3) + 300.0), weak);
	// 出手处收细淡入，靠近交汇点更亮
	float head = smoothstep(0.0, 0.06, v_along);
	float tail = mix(1.0, 1.7, smoothstep(0.75, 1.0, v_along));
	float band = pulse_pos >= 0.0 ? exp(-pow((v_along - pulse_pos) * 9.0, 2.0)) : 0.0;
	float lum = (body * streak + core * 1.3) * flick * head * tail * (0.65 + 0.6 * power) + band * (0.6 + body);
	ALBEDO = mix(color.rgb, vec3(1.0), clamp(core * 0.85 + band * 0.5, 0.0, 1.0)) * intensity * lum;
	ALPHA = clamp(body * 1.2, 0.0, 1.0) * alpha;
}
