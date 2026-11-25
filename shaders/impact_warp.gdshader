// 手机档的冲击帧 / 空间扭曲（桌面档见 speed_blur.gdshader）：只在重击命中、对波、雷劫那零点几秒里开，
// 每像素最多采两次屏幕（桌面档是 36 次 + 色散）。速度线和暗角在另一层（speed_lines.gdshader），不读屏幕。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 tint : source_color = vec4(1.0);
uniform float impact = 0.0;
uniform float shatter_r = 0.95;
const float SHATTER_R = 0.4;      // 平时（打斗）实际画多大，见 fragment 里的说明
uniform vec2 warp_c = vec2(0.5, 0.5);
uniform float warp_k = 0.0;
uniform float warp_r = 0.2;

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
	if (warp_k > 0.0005) {
		vec2 w = (uv - warp_c) * vec2(aspect, 1.0);
		float wr = length(w);
		float fall = smoothstep(warp_r, 0.0, wr);
		vec2 wd = w / max(wr, 1e-4) / vec2(aspect, 1.0);
		float ripple = sin(wr / warp_r * 22.0 - TIME * 16.0);
		float swirl = vnoise(w * 26.0 + TIME * 3.0) - 0.5;
		uv += wd * warp_k * fall * (0.55 + 0.75 * ripple + 0.9 * swirl) * smoothstep(0.0, 0.25, wr / warp_r);
	}
	vec3 col = texture(screen_tex, uv).rgb;
	if (impact > 0.001) {
		// 空间破碎：画面以冲击点为心碎成错位的碎片，裂缝里是幽暗的虚空、缝沿一圈境界色的微光（保留原色，不闪黑白）
		vec2 da = (uv - center) * vec2(aspect, 1.0);
		float r = length(da);
		// 2026-11-23 用户嫌「打斗时屏幕上的裂缝太大、整个屏幕都占了」：平时传进来的范围是 0.95（camera_rig.gd 的 impact_r 默认值，
		// 低段位雷劫也是这个数），这里按 SHATTER_R 画 —— 只碎冲击点周围一块，碎片、错位跟着范围按比例变小；
		// 高段位雷劫把范围放到 1.1 以上（铺满全屏）时照原样，sc = 1
		float sr = shatter_r < 0.96 ? min(shatter_r, SHATTER_R) : shatter_r;
		float sc = clamp(sr / 0.95, 0.4, 1.0);
		float cells = 5.5 / sc;
		vec2 gp = da * cells;
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
					cpos = (gi + pt) / cells;
				} else if (dd < f2) {
					f2 = dd;
				}
			}
		}
		float k = impact * smoothstep(sr, sr * 0.1, r);
		vec2 out_dir = cpos / max(length(cpos), 1e-3) / vec2(aspect, 1.0);
		vec2 rnd = vec2(hash(cell + 3.1), hash(cell + 8.7)) - 0.5;
		vec2 shift = (out_dir * (0.02 + 0.03 * hash(cell + 5.5)) + rnd * 0.022) * k * sc;
		vec3 shard = texture(screen_tex, uv - shift).rgb;
		shard *= 1.0 + (hash(cell + 1.9) - 0.5) * 0.3 * k;
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
