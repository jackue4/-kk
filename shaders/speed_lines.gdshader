// 手机档的速度感叠层（桌面档见 speed_blur.gdshader）：只画速度线 + 暗角，直接叠在画面上。
// 不读屏幕：不触发整屏拷贝，也没有逐像素的多次采样（桌面档的径向拖影每像素要采 36 次，手机上一开就掉帧）。
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float strength = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 tint : source_color = vec4(1.0);
uniform float rush = 0.0;      // 突进 / 击飞的速度线

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 da = (SCREEN_UV - center) * vec2(aspect, 1.0);
	float r = length(da);
	vec2 q = da / max(r, 1e-4);
	float ln = vnoise(q * 46.0 + floor(TIME * 24.0) * 3.7);
	float lines = smoothstep(0.88, 1.0, ln) * smoothstep(0.5, 1.0, r) * clamp(strength - 0.25, 0.0, 1.0);
	vec3 add = tint.rgb * lines * 0.14;
	if (rush > 0.001) {
		float rl = vnoise(q * 70.0 + floor(TIME * 30.0) * 5.3);
		float rlines = smoothstep(0.8, 1.0, rl) * smoothstep(0.22, 0.75, r) * rush;
		add += mix(vec3(1.0), tint.rgb, 0.35) * rlines * 0.5;
	}
	// 预乘混合：rgb 是加上去的线，alpha 是把原画面压暗多少（暗角）
	COLOR = vec4(add, strength * 0.22 * smoothstep(0.5, 1.1, r));
}
