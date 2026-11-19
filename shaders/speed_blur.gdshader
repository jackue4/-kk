// 速度感后处理：只作用于画面边缘的轻微径向拖影 + 细速度线 + 暗角。
// 画面中部（角色与遁光丝线所在）完全不采样偏移，避免把亮线抹成白核。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 tint : source_color = vec4(1.0);

const int SAMPLES = 12;

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
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 da = d * vec2(aspect, 1.0);
	float r = length(da);
	float mask = smoothstep(0.32, 0.95, r);
	float amt = strength * mask * 0.07;
	// 交错梯度噪声做逐像素抖动，避免高亮物体被复制成离散重影
	float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy + fract(TIME * 7.0) * 17.0, vec2(0.06711056, 0.00583715))));
	vec2 ca = d * amt * 0.08;
	vec3 col = vec3(0.0);
	float ws = 0.0;
	for (int i = 0; i < SAMPLES; i++) {
		float t = (float(i) + jit) / float(SAMPLES);
		vec2 s = uv - d * amt * t;
		float w = 1.0 - t * 0.6;
		col += vec3(texture(screen_tex, s + ca).r, texture(screen_tex, s).g, texture(screen_tex, s - ca).b) * w;
		ws += w;
	}
	col /= ws;

	vec2 q = da / max(r, 1e-4);
	float ln = vnoise(q * 46.0 + floor(TIME * 24.0) * 3.7);
	float lines = smoothstep(0.88, 1.0, ln) * smoothstep(0.5, 1.0, r) * clamp(strength - 0.25, 0.0, 1.0);
	col += tint.rgb * lines * 0.14;
	col *= 1.0 - strength * 0.22 * smoothstep(0.5, 1.1, r);
	COLOR = vec4(col, 1.0);
}
