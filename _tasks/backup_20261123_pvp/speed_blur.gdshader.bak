// 速度感后处理：只作用于画面边缘的轻微径向拖影 + 细速度线 + 暗角。
// 画面中部（角色与遁光丝线所在）完全不采样偏移，避免把亮线抹成白核。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 tint : source_color = vec4(1.0);
// 空战斗法：impact = 重击命中的冲击帧（空间破碎：画面碎成错位的碎片、裂缝发光，零点几秒内合拢）；rush = 突进 / 击飞的速度线
uniform float impact = 0.0;
uniform float rush = 0.0;
uniform float shatter_r = 0.95;   // 空间破碎的范围
// 空间扭曲：以 warp_c（屏幕坐标）为心、warp_r 为半径，画面往里吸、一圈圈往外荡，边缘带一点色散；warp_k = 强度（随境界变强）
uniform vec2 warp_c = vec2(0.5, 0.5);
uniform float warp_k = 0.0;
uniform float warp_r = 0.2;

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
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 wsplit = vec2(0.0);
	if (warp_k > 0.0005) {
		vec2 w = (uv - warp_c) * vec2(aspect, 1.0);
		float wr = length(w);
		float fall = smoothstep(warp_r, 0.0, wr);
		vec2 wd = w / max(wr, 1e-4) / vec2(aspect, 1.0);
		float ripple = sin(wr / warp_r * 22.0 - TIME * 16.0);
		float swirl = vnoise(w * 26.0 + TIME * 3.0) - 0.5;
		uv += wd * warp_k * fall * (0.55 + 0.75 * ripple + 0.9 * swirl) * smoothstep(0.0, 0.25, wr / warp_r);
		wsplit = wd * warp_k * fall * 0.35;
	}
	vec2 d = uv - center;
	vec2 da = d * vec2(aspect, 1.0);
	float r = length(da);
	float mask = smoothstep(0.32, 0.95, r);
	float amt = strength * mask * 0.07;
	// 交错梯度噪声做逐像素抖动，避免高亮物体被复制成离散重影
	float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy + fract(TIME * 7.0) * 17.0, vec2(0.06711056, 0.00583715))));
	vec2 ca = d * amt * 0.08 + wsplit;
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
		// 冲击帧：空间破碎——画面像一面镜子以冲击点为心碎成不规则的碎片，每片朝外错开一点、各自偏一点色，
		// 碎片之间的裂缝里是幽暗的虚空，缝沿上一圈境界色的微光。保留场景原本的颜色，不闪黑白。
		vec2 gp = da * 5.5;
		vec2 gi = floor(gp);
		vec2 gf = fract(gp);
		float f1 = 9.0;
		float f2 = 9.0;
		vec2 cell = vec2(0.0);
		vec2 cpos = vec2(0.0);
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 o = vec2(float(x), float(y));
				vec2 id = gi + o;
				vec2 pt = o + vec2(hash(id), hash(id + 17.3)) * 0.8 + 0.1;
				float dd = length(pt - gf);
				if (dd < f1) {
					f2 = f1;
					f1 = dd;
					cell = id;
					cpos = (gi + pt) / 5.5;
				} else if (dd < f2) {
					f2 = dd;
				}
			}
		}
		float near = smoothstep(shatter_r, shatter_r * 0.1, r);                      // 离冲击点越近碎得越厉害
		float k = impact * near;
		// 每片碎片整体往外错位，再带一点各自的随机偏移和偏色
		vec2 out_dir = cpos / max(length(cpos), 1e-3) / vec2(aspect, 1.0);
		vec2 rnd = vec2(hash(cell + 3.1), hash(cell + 8.7)) - 0.5;
		vec2 shift = (out_dir * (0.02 + 0.03 * hash(cell + 5.5)) + rnd * 0.022) * k;
		vec2 suv = uv - shift;
		vec2 split = out_dir * 0.004 * k;
		vec3 shard = vec3(texture(screen_tex, suv + split).r, texture(screen_tex, suv).g, texture(screen_tex, suv - split).b);
		shard *= 1.0 + (hash(cell + 1.9) - 0.5) * 0.3 * k;          // 每片明暗略有不同，像角度不一的碎镜
		// 裂缝：到碎片边界的距离
		float edge = f2 - f1;
		float gap_w = 0.05 * k;
		float gap = 1.0 - smoothstep(gap_w * 0.6, gap_w, edge);
		float rim = (1.0 - smoothstep(gap_w, gap_w * 2.6 + 0.004, edge)) * k;
		vec3 void_col = mix(vec3(0.02, 0.015, 0.05), tint.rgb * 0.25, 0.35);
		vec3 broken = mix(shard, void_col, gap);
		broken += mix(vec3(1.0), tint.rgb, 0.55) * rim * 0.75 * (1.0 - gap * 0.6);
		col = mix(col, broken, clamp(impact * 2.2, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
