// 速度感后处理：只作用于画面边缘的轻微径向拖影 + 细速度线 + 暗角。
// 画面中部（角色与遁光丝线所在）完全不采样偏移，避免把亮线抹成白核。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 tint : source_color = vec4(1.0);
// 空战斗法：impact = 重击命中的冲击帧（整屏压成黑白两色 + 满屏放射线，零点几秒内退掉）；rush = 突进 / 击飞的速度线
uniform float impact = 0.0;
uniform float rush = 0.0;

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
	if (rush > 0.001) {
		float rl = vnoise(q * 70.0 + floor(TIME * 30.0) * 5.3);
		float rlines = smoothstep(0.8, 1.0, rl) * smoothstep(0.22, 0.75, r) * rush;
		col += mix(vec3(1.0), tint.rgb, 0.35) * rlines * 0.5;
	}
	if (impact > 0.001) {
		// 冲击帧：底片式反相——亮的场景压成墨色，暗部（头发、阴影、轮廓）和彩色的特效翻成白，人形剪影还读得出来
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
		float keep = max(1.0 - smoothstep(0.18, 0.42, lum), smoothstep(0.22, 0.5, sat));
		vec3 ink = mix(vec3(0.04, 0.05, 0.1), mix(vec3(1.0), tint.rgb, 0.18), keep);
		float il = vnoise(q * 34.0 + 11.0);
		float ilines = smoothstep(0.66, 0.92, il) * smoothstep(0.2, 0.7, r);
		ink = mix(ink, vec3(1.0), ilines * 0.85);
		col = mix(col, ink, clamp(impact * 1.3, 0.0, 0.92));
	}
	COLOR = vec4(col, 1.0);
}
