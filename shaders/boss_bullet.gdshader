// Boss 弹幕弹体（boss_bullets.gd 的 MultiMesh 用）：朝相机的发光弹，白芯 + 主色弹身 + 一圈亮环 + 深色描边，
// 灰白大厅里也一眼可读。INSTANCE_CUSTOM = (飞行方向 xyz, 半径)；stretch > 1 时沿飞行方向（投到屏幕上）拉长成针弹。
// 实例颜色 COLOR 已转线性，alpha 用于生成 / 消散时的淡入淡出。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform float stretch = 1.0;
uniform float core = 0.4;
uniform float max_ang = 0.05;  // 屏幕尺寸上限：半径 ≤ 到镜头距离 × max_ang，近镜头的弹不会糊满一屏

varying vec4 v_col;

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - c);
	vec3 d = INSTANCE_CUSTOM.xyz;
	vec3 ax = d - to_cam * dot(d, to_cam);
	if (dot(ax, ax) < 1e-6) {
		ax = cross(to_cam, vec3(0.0, 1.0, 0.0));
	}
	if (dot(ax, ax) < 1e-6) {
		ax = vec3(1.0, 0.0, 0.0);
	}
	ax = normalize(ax);
	vec3 ay = normalize(cross(to_cam, ax));
	float r = min(INSTANCE_CUSTOM.w, distance(CAMERA_POSITION_WORLD, c) * max_ang);
	vec3 w = c + ax * VERTEX.x * 2.0 * r * stretch + ay * VERTEX.y * 2.0 * r;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz);
	v_col = COLOR;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.2 + 1e-4;
	float edge = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	float body = 1.0 - smoothstep(0.8 - aa, 0.8 + aa, r);
	float hot = 1.0 - smoothstep(core - 0.1, core + 0.06, r);
	vec3 rim = v_col.rgb * 0.12;
	vec3 col = mix(rim, v_col.rgb * 1.3, body);
	float ring = exp(-pow((r - 0.64) / 0.07, 2.0)) * body;
	col += mix(v_col.rgb, vec3(1.0), 0.35) * ring * 0.9;
	col = mix(col, vec3(1.7), hot);
	ALBEDO = col;
	ALPHA = edge * v_col.a;
}
