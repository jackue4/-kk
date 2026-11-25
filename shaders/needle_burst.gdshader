// 针芒迸射（scripts/heroes/cg_fx.gd）：一个网格、一次绘制，画几十根从一点往外窜的细长针 —— 命中点 / 刀光炸开的地方用。
// 每根针是一个四边形，四个顶点都在原点：NORMAL = 这根针朝哪窜（本地系），UV.x 0 尾 → 1 尖，UV.y -1 / +1 = 左右两边，
// COLOR.r = 长度倍数，COLOR.g = 晚多久才窜（0~1），COLOR.b > 0.5 = 这是一根深色的针（压在亮针中间，亮背景上靠它读出形状）。
// 顶点着色器里把针拉长、朝着镜头摊开；age 0 → 1：针尖窜出去 → 针尾追上来 → 细掉。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, world_vertex_coords;

uniform vec4 col_hot : source_color = vec4(1.0);
uniform vec4 col_body : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform vec4 col_dark : source_color = vec4(0.05, 0.1, 0.25, 1.0);
uniform float age = 0.0;
uniform float reach = 3.0;      // 最长的针窜多远（米）
uniform float width = 0.07;     // 针最粗的地方（米）
uniform float alpha = 1.0;

varying float v_dark;
varying float v_t;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 dir = normalize(NORMAL);
	float delay = COLOR.g * 0.3;
	float t = clamp((age - delay) / (1.0 - delay), 0.0, 1.0);
	float tip = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
	float tail = tip * smoothstep(0.25, 1.0, t);
	float len = reach * COLOR.r;
	vec3 p = origin + dir * len * mix(tail, tip, UV.x);
	vec3 view = normalize(CAMERA_POSITION_WORLD - p);
	vec3 side = cross(dir, view);
	side = length(side) > 1e-4 ? normalize(side) : vec3(0.0, 1.0, 0.0);
	float w = width * sin(UV.x * 3.14159) * (1.0 - t * 0.7) * (0.6 + 0.4 * COLOR.r);
	VERTEX = p + side * UV.y * w;
	NORMAL = view;
	v_dark = COLOR.b;
	v_t = t;
}

void fragment() {
	float core = 1.0 - abs(UV.y);
	vec3 bright = mix(col_body.rgb, col_hot.rgb, smoothstep(0.35, 0.8, core));
	ALBEDO = v_dark > 0.5 ? col_dark.rgb : bright;
	float a = smoothstep(0.0, 0.25, core) * (1.0 - smoothstep(0.7, 1.0, v_t)) * step(0.001, v_t);
	ALPHA = clamp(a * alpha * (v_dark > 0.5 ? 0.85 : 1.0), 0.0, 1.0);
}
