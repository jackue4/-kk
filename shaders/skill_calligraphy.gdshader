// 3D 技能题字（参考 _ref/skill_calligraphy.png）：SubViewport 里写好的毛笔字贴到场景里的几层面片上。
// 贴图通道：R 字芯覆盖 | G 外扩一圈的字形（发光用）。某像素属于哪个字按离哪个字格中心最近来定（cells / count）。
// layer: 0 字身厚度层（压暗、半透明，几层错开叠出立体感）| 1 外发光（skill_calligraphy.gd 把它换成加色混合用）
//        2 字面（近白、HDR 起辉；枯笔飞白、湿墨前沿、流光扫过）
// 书写：每字按"先上后下、先左后右"的斜向笔势推进，前沿毛糙；消散：噪声阈值逐渐吞掉字身，边缘烧成境界色。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D tex : filter_linear, repeat_disable;
uniform vec4 col : source_color = vec4(0.5, 0.78, 1.0, 1.0);
uniform int layer = 2;
uniform float t = 0.0;          // 题字开始后的时间（真实时间）
uniform float idx0 = 0.0;       // 本组第一个字在整句里的序号
uniform float t_char0 = 0.12;
uniform float t_gap = 0.16;
uniform float t_write = 0.24;
uniform float fade = 0.0;       // 0~1 消散
uniform float depth_k = 0.0;    // 厚度层：0 贴着字面 ~ 1 最深
uniform vec4 cells[4];          // 本组各字在贴图里的 UV 矩形 (x, y, w, h)
uniform int count = 2;          // 本组字数（≤4）
uniform vec2 texel = vec2(0.002);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 离 uv 最近的字格（按像素距离）
float nearest_cell(vec2 uv) {
	float best = 1e12;
	float k = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= count) {
			break;
		}
		vec4 c = cells[i];
		vec2 d = (uv - (c.xy + c.zw * 0.5)) / texel;
		float dd = dot(d, d);
		if (dd < best) {
			best = dd;
			k = float(i);
		}
	}
	return k;
}

// 第 k 个字的书写遮罩；wet = 前沿附近的湿墨高光
float reveal(vec2 uv, float k, out float wet) {
	vec4 c = cells[clamp(int(k), 0, 3)];
	vec2 lp = (uv - c.xy) / max(c.zw, vec2(1e-4));
	float w = clamp((t - t_char0 - (idx0 + k) * t_gap) / t_write, 0.0, 1.0);
	float s = lp.y * 0.72 + lp.x * 0.38;
	float front = w * 1.25 - 0.08 + 0.07 * (vnoise(lp * 9.0 + k * 3.1) - 0.5);
	wet = (1.0 - smoothstep(0.0, 0.16, front - s)) * step(0.001, w) * (1.0 - smoothstep(0.8, 1.0, w));
	return 1.0 - smoothstep(front - 0.03, front, s);
}

// 已写出的部分：dil=true 取外扩字形（G），否则取字芯（R）
float revealed(vec2 uv, bool dil, out float wet) {
	vec4 s = texture(tex, uv);
	wet = 0.0;
	if (s.g < 0.004) {
		return 0.0;
	}
	return (dil ? s.g : s.r) * reveal(uv, nearest_cell(uv), wet);
}

void fragment() {
	float dn = vnoise(UV * 18.0) * 0.7 + vnoise(UV * 55.0) * 0.3;
	float cut = fade * 1.1;
	float keep = smoothstep(cut - 0.05, cut, dn);
	float ember = (1.0 - smoothstep(0.0, 0.08, dn - cut + 0.05)) * step(0.001, fade);
	float wet = 0.0;
	vec3 outc = vec3(0.0);
	float outa = 0.0;

	if (layer == 1) {
		// 外发光：外扩字形的两圈 12 点模糊，微微闪动
		float acc = revealed(UV, true, wet);
		float wsum = 1.0;
		for (int j = 1; j <= 2; j++) {
			for (int i = 0; i < 12; i++) {
				float an = float(i) * 0.5236 + 0.26 * float(j);
				float wt = 1.0 / float(j);
				float w0 = 0.0;
				acc += revealed(UV + vec2(cos(an), sin(an)) * texel * (10.0 * float(j)), true, w0) * wt;
				wsum += wt;
			}
		}
		float g = acc / wsum;
		float flick = 0.85 + 0.15 * sin(TIME * 7.0 + UV.x * 11.0 + UV.y * 5.0);
		outc = col.rgb * 1.6 * flick;
		outa = g * 0.85 * (1.0 - fade) + ember * keep * 0.5;
	} else if (layer == 0) {
		float a = revealed(UV, false, wet);
		outc = col.rgb * mix(0.7, 0.22, depth_k);
		outa = a * (0.9 - 0.55 * depth_k) * keep;
	} else {
		float a = revealed(UV, false, wet);
		// 飞白：靠近笔画边缘处顺着斜向笔势拉出细丝状的枯笔
		float rb = 0.0;
		for (int i = 0; i < 8; i++) {
			float an = float(i) * 0.7854;
			rb += texture(tex, UV + vec2(cos(an), sin(an)) * texel * 5.0).r;
		}
		rb /= 8.0;
		vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * UV;
		float fiber = smoothstep(0.3, 0.62, vnoise(q * vec2(6.0, 140.0)));
		float dry = 1.0 - smoothstep(0.45, 0.9, rb);
		a *= mix(1.0, fiber, dry * 0.85);
		// 光痕：一道斜向流光扫过字面
		float sweep = exp(-pow((UV.x * 0.6 + UV.y * 0.8 - (t - 0.55) * 0.9) * 6.0, 2.0));
		vec3 c = mix(vec3(1.0), col.rgb, 0.1 + 0.45 * (1.0 - rb));
		c *= 1.35 + 0.9 * wet + 1.1 * sweep;
		outc = mix(c, col.rgb * 2.4, ember);
		outa = a * keep;
	}
	ALBEDO = outc;
	ALPHA = clamp(outa, 0.0, 1.0);
}
