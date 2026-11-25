// 神识标记（scripts/shen_shi.gd，2026-11-23）：被扫到的重点目标脚下立一道细光柱、头上一颗菱形光点，不做深度测试（隔着山也看得见方位）。
// 一张 QuadMesh（1×1），在顶点着色器里摆：
//   glyph = 0 光柱：绕竖轴转向镜头，宽度随距离放宽（屏幕上粗细不变），从目标脚下立到 height 米高
//   glyph = 1 光点：整片朝向镜头，屏幕上大小不变，在目标上方 lift 米
// power：整体淡入淡出；xray：1 = 刚扫到的透视阶段（亮），之后降到一点余光，标记还留着。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.6, 0.9, 1.0);
uniform float power = 0.0;
uniform float xray = 1.0;
uniform float glyph = 0.0;
uniform float height = 30.0;
uniform float lift = 2.5;
uniform float px = 0.006;           // 宽度 / 大小：占「到镜头距离」的比例

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float dist = max(length(cam - origin), 1.0);
	vec3 wpos;
	if (glyph > 0.5) {
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		float s = px * dist * 3.2;
		wpos = origin + vec3(0.0, lift, 0.0) + (right * VERTEX.x + up * VERTEX.y) * s;
	} else {
		vec3 to = cam - origin;
		to.y = 0.0;
		vec3 side = normalize(vec3(-to.z, 0.0, to.x) + vec3(1e-4, 0.0, 0.0));
		wpos = origin + side * VERTEX.x * px * dist + vec3(0.0, (VERTEX.y + 0.5) * height, 0.0);
	}
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wpos, 1.0));
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float k = mix(0.28, 1.0, xray);
	vec3 c;
	if (glyph > 0.5) {
		// 菱形：|x| + |y| 的等值线；外面一圈淡晕，中心白
		float dm = abs(q.x) + abs(q.y);
		float body = 1.0 - smoothstep(0.42, 0.5, dm);
		float ring = exp(-(dm - 0.62) * (dm - 0.62) / 0.004);
		float halo = exp(-dm * dm * 3.0) * 0.35;
		c = mix(tint, vec3(1.0), 0.45 * (1.0 - dm)) * body * 0.9 + tint * (ring * 0.8 + halo);
		k = mix(0.55, 1.0, xray);
	} else {
		float y01 = 1.0 - UV.y;                         // 0 脚下 → 1 顶
		float core = exp(-q.x * q.x / 0.04);
		float glow = exp(-q.x * q.x / 0.35) * 0.35;
		float up = 1.0 - y01;
		float vert = up * up;
		float p = fract(y01 * 3.0 - TIME * 0.9);
		float pulse = exp(-(p - 0.5) * (p - 0.5) / 0.004) * 0.6;
		c = (mix(tint, vec3(1.0), 0.25) * core + tint * glow * 1.4) * (vert + pulse * up);
	}
	ALBEDO = c * power * k;
	ALPHA = 1.0;
}
