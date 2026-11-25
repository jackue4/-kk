// 透视门（hub_portal.gd）的外圈特效，叠加混合（2026-11-21 场景美术专项）：
// mode 0 = 竖着贴在门前的一张面片：门洞边往外溢的光、从门里飘出来的樱花瓣、往上飘的金色光点
// mode 1 = 平铺在门脚地上的一张面片：门前一摊柔光 + 两圈慢慢转的光纹
// 都是程序画的（不用粒子：手机档少一种着色器变体、少一套发射器）。噪声查 fx/cine/cine_noise.png。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float mode = 0.0;
uniform vec2 size = vec2(14.0, 11.0);            // 这张面片的宽 / 高（米）；mode 0 底边贴地、左右居中
uniform vec2 hole = vec2(8.0, 7.0);              // 门洞宽 / 高
uniform vec3 col_a = vec3(1.0, 0.62, 0.86);      // 屏幕色（sRGB）
uniform vec3 col_b = vec3(1.0, 0.88, 0.55);
uniform float strength = 1.0;

uint ihash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float rnd(uint i, uint salt) {
	return float(ihash(i * 747796405u + salt * 2891336453u) & 0xffffu) / 65535.0;
}

vec3 to_out(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return pow(max(c, vec3(0.0)), vec3(2.2));
#endif
}

void fragment() {
	float t = TIME;
	vec3 c = vec3(0.0);
	if (mode < 0.5) {
		vec2 m = vec2((UV.x - 0.5) * size.x, (1.0 - UV.y) * size.y);
		float dx = hole.x * 0.5 - abs(m.x);
		float dy = hole.y - m.y;
		float inside = min(dx, dy);
		// 门边溢出的光：贴着门洞边最亮，往里往外都淡下去；沿边有流动的明暗
		float fl = texture(noise_tex, vec2((m.x + m.y) * 0.07 - t * 0.06, t * 0.05)).r;
		float spill = exp(-abs(inside) * 1.25) * (0.35 + 0.65 * fl) * (inside > 0.0 ? 0.55 : 0.85);
		spill *= smoothstep(-0.2, 0.6, m.y);
		c += mix(col_a, col_b, fl) * spill * 0.55;
		// 樱花瓣：从门洞里飘出来，往外、往下摆着落，转着身
		for (uint i = 0u; i < 16u; i++) {
			float life = 5.5 + rnd(i, 1u) * 3.0;
			float ph = fract(t / life + rnd(i, 2u));
			vec2 p0 = vec2((rnd(i, 3u) - 0.5) * hole.x * 0.9, hole.y * (0.25 + 0.7 * rnd(i, 4u)));
			float side = rnd(i, 5u) < 0.5 ? -1.0 : 1.0;
			vec2 p = p0 + vec2(side * ph * (2.2 + 2.6 * rnd(i, 6u)) + sin(ph * 9.0 + float(i)) * 0.35, -ph * (2.0 + 2.2 * rnd(i, 7u)));
			vec2 d = m - p;
			float ang = ph * 12.0 * (rnd(i, 8u) - 0.5) + float(i);
			vec2 r = vec2(cos(ang) * d.x - sin(ang) * d.y, sin(ang) * d.x + cos(ang) * d.y);
			float s = 0.11 + 0.07 * rnd(i, 9u);
			float pet = 1.0 - smoothstep(0.75, 1.0, length(r / vec2(s * 1.7, s)));
			float fade = smoothstep(0.0, 0.12, ph) * (1.0 - smoothstep(0.7, 1.0, ph));
			c += vec3(1.0, 0.70, 0.84) * pet * fade * 0.85;
		}
		// 金色光点：从门脚往上飘
		vec2 q = vec2(m.x * 0.42, m.y * 0.2 - t * 0.16);
		float sp = texture(noise_tex, q).g;
		float near = exp(-max(-inside, 0.0) * 0.8);
		c += col_b * smoothstep(0.86, 0.92, sp) * near * 0.9;
	} else {
		// 门脚地面：size = (门宽方向, 往门外的纵深)；UV.y = 0 在门这边
		vec2 m = vec2((UV.x - 0.5) * size.x, UV.y * size.y);
		vec2 g = vec2(m.x / (hole.x * 0.62), m.y / (size.y * 0.55));
		float r = length(g);
		float pool = exp(-r * r * 2.2);
		float ring = 0.0;
		for (int k = 0; k < 2; k++) {
			float rr = 0.55 + 0.3 * float(k);
			float a = atan(g.y, g.x) + t * (k == 0 ? 0.35 : -0.25);
			float dash = smoothstep(0.2, 0.8, sin(a * 18.0) * 0.5 + 0.5);
			ring += (1.0 - smoothstep(0.0, 0.035, abs(r - rr))) * (0.4 + 0.6 * dash);
		}
		float fl = texture(noise_tex, m * 0.08 + vec2(t * 0.03, -t * 0.05)).r;
		c += mix(col_a, col_b, fl) * (pool * (0.35 + 0.3 * fl) + ring * 0.35);
		c *= smoothstep(0.0, 0.4, m.y + 0.4);
	}
	c *= strength;
	ALBEDO = to_out(c);
	ALPHA = 1.0;
}
