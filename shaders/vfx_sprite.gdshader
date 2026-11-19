// 通用特效面片，全部走"线条"语言，不画实心光斑。
// mode: 0 细十字星芒  1 细线环  2 针形剑芒（两头尖）  3 微型飞剑剪影（剑尖朝 +X）
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform int mode = 0;
uniform float alpha = 1.0;
uniform float intensity = 1.2;
uniform bool billboard = true;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ax = fwidth(p.x) * 1.5 + 1e-4;
	float ay = fwidth(p.y) * 1.5 + 1e-4;
	float a = 0.0;
	float hot = 0.0;  // 向白色偏的程度，只给线芯
	if (mode == 0) {
		float sx = pow(max(1.0 - abs(p.x), 0.0), 2.5) * (1.0 - smoothstep(0.0, max(ay, 0.03), abs(p.y)));
		float sy = pow(max(1.0 - abs(p.y), 0.0), 2.5) * (1.0 - smoothstep(0.0, max(ax, 0.03), abs(p.x)));
		float pip = pow(max(1.0 - r * 5.0, 0.0), 2.0);
		a = max(max(sx, sy), pip);
		hot = a * 0.6;
	} else if (mode == 1) {
		float w = max(fwidth(r) * 1.5, 0.022);
		a = 1.0 - smoothstep(0.0, w, abs(r - 0.92));
		hot = a * 0.25;
	} else if (mode == 2) {
		float t = max(1.0 - abs(p.x), 0.0);
		float y = abs(p.y) / max(pow(t, 0.7), 1e-3);
		float body = 1.0 - smoothstep(0.25, 1.0, y);
		float needle = 1.0 - smoothstep(0.08, 0.3, y);
		a = max(body * body * 0.5, needle) * smoothstep(0.0, 0.12, t);
		hot = needle * 0.7;
	} else {
		float bw = 0.36 * clamp((1.0 - p.x) / 0.5, 0.0, 1.0);
		float blade = (1.0 - smoothstep(bw - ay, bw + ay, abs(p.y)))
				* smoothstep(-0.42 - ax, -0.42 + ax, p.x) * step(p.x, 1.0);
		float guard = (1.0 - smoothstep(0.07 - ax, 0.07 + ax, abs(p.x + 0.46)))
				* (1.0 - smoothstep(0.85 - ay, 0.85 + ay, abs(p.y)));
		float grip = (1.0 - smoothstep(0.26 - ax, 0.26 + ax, abs(p.x + 0.74)))
				* (1.0 - smoothstep(0.15 - ay, 0.15 + ay, abs(p.y)));
		float ridge = 1.0 - smoothstep(0.0, 0.1 + ay, abs(p.y));
		a = max(blade, max(guard, grip));
		hot = blade * (0.3 + 0.45 * ridge);
	}
	ALBEDO = mix(color.rgb, vec3(1.0), clamp(hot, 0.0, 1.0)) * intensity;
	ALPHA = clamp(a, 0.0, 1.0) * alpha;
}
