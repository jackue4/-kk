// 境界光环特效 · 片（scripts/realm_halo.gd）。一个光环上所有的「片」—— 莲瓣、羽毛、火苗、晶簇、符纸、金符、宝石、星芒、
// 冠上的花苞、流苏 —— 都是同一个 MultiMesh 里的方片，各自的形状在这里按 style 画（不采贴图，放多大都是清楚的）。
// 每片自己的数据：COLOR = 颜色（rgb）和浓淡（a）；INSTANCE_CUSTOM = (style, 相位 0~1, 摆动幅度（弧度）, 参数)。
// 片的局部坐标：x 横向 -1~1，y 从根（-1）到尖（+1）。展开时按相位一片片长出来；摆动绕着根。
//   0 莲瓣（半透明、亮边、叶脉）  1 莲瓣线稿（只有发光的轮廓）  2 羽毛  3 火苗  4 晶簇  5 符纸  6 菱形金符
//   7 宝石  8 星芒（会闪）  9 花苞（实心，冠饰用）  10 流苏  11 尖角（龙角 / 龙吻）  12 光团
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/realm_halo_inc.gdshaderinc"

uniform vec3 rim_col = vec3(1.0, 0.86, 0.52);      // 描边 / 高光的颜色（这一档的金）
uniform float reveal = 1.0;
uniform float rear = 1.0;

varying vec4 v_inst;
varying vec4 v_tint;

void vertex() {
	v_inst = INSTANCE_CUSTOM;
	v_tint = COLOR;
	float ph = INSTANCE_CUSTOM.g;
	float grow = smoothstep(ph * 0.55, ph * 0.55 + 0.45, reveal);
	int st = int(INSTANCE_CUSTOM.r + 0.5);
	vec2 q = VERTEX.xy;
	if (st == 8) {
		q *= grow * (0.5 + 0.5 * sin(TIME * (1.6 + ph * 2.6) + ph * 40.0));
	} else {
		q.y += 0.5;
		q *= vec2(mix(0.5, 1.0, grow), grow);
		float ang = INSTANCE_CUSTOM.b * sin(TIME * 1.3 + ph * 6.2831);
		q = vec2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang));
		q.y -= 0.5;
	}
	VERTEX.xy = q;
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	POSITION = halo_clip(vp, vn, PROJECTION_MATRIX);
}

// 中间鼓、两头尖的轮廓：t = 0 根、1 尖；a、b 越小那一头越钝。归一到最宽处 = 1
float prof(float t, float a, float b) {
	float n = pow(a / (a + b), a) * pow(b / (a + b), b);
	return pow(max(t, 0.0001), a) * pow(max(1.0 - t, 0.0001), b) / n;
}

void fragment() {
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0) / 0.9;       // 四周留一点边给柔光
	float t = clamp(q.y * 0.5 + 0.5, 0.0, 1.0);
	int st = int(v_inst.r + 0.5);
	float par = v_inst.a;
	vec3 tint = v_tint.rgb;
	float in_y = step(abs(q.y), 1.0);
	// 每种形状给出：c 本色、cov 形状盖住的范围、op 多实（1 = 不透，0 = 纯光）、g 形状外面的一圈柔光、
	// lum 自己发多少光（0 = 半透明的地方颜色也跟着淡，像琉璃；1 = 再透也是满亮度，像火）。
	// 颜色是「盖」上去的（亮边盖在本色上，不是加上去），不然几层一叠就冲成白的了
	vec3 c = tint;
	float cov = 0.0;
	float op = 0.0;
	float g = 0.0;
	float lum = 0.35;
	vec3 gc = tint;
	if (st == 0 || st == 1 || st == 9) {
		float half = 0.86 * prof(t, 0.42, 0.72);
		float d = (half - abs(q.x)) * in_y;
		cov = smoothstep(0.0, 0.05, d);
		float rim = smoothstep(st == 9 ? 0.12 : 0.16, 0.03, d);
		g = exp(-max(-d, 0.0) * 12.0) * (1.0 - cov) * in_y;
		if (st == 0) {
			float vein = exp(-pow(q.x / 0.035, 2.0)) * smoothstep(0.03, 0.3, t) * (1.0 - 0.6 * t);
			float side = pow(max(sin(abs(q.x) / max(half, 0.02) * 7.8), 0.0), 10.0) * 0.5 * smoothstep(0.15, 0.5, t);
			float ink = clamp(rim + vein * 0.7 + side, 0.0, 1.0);
			c = mix(tint * (0.6 + 0.4 * t), rim_col, ink);
			op = mix(0.3 + 0.62 * par, 0.97, ink);
			g *= 0.3;
		} else if (st == 1) {
			// 线稿：一圈轮廓 + 中间一道叶脉，线是实的
			float vein = exp(-pow(q.x / 0.04, 2.0)) * smoothstep(0.08, 0.35, t) * (1.0 - t);
			c = rim_col;
			cov *= max(rim, vein * 0.7);
			op = 0.9;
			lum = 1.0;
			g *= 0.5;
			gc = rim_col;
		} else {
			// 实心花苞：左上受光、右下暗一点，中间一道棱
			float lit = 0.76 + 0.24 * smoothstep(0.5, -0.5, q.x * 0.8 - q.y * 0.3);
			float ridge = exp(-pow(q.x / 0.05, 2.0)) * 0.45;
			c = mix(tint * lit, rim_col, clamp(rim * 0.85 + ridge, 0.0, 1.0));
			op = 0.96;
			g *= 0.3;
			gc = rim_col;
		}
	} else if (st == 2) {
		float half = 0.8 * prof(t, 0.3, 1.05);
		float d = (half - abs(q.x)) * in_y;
		cov = smoothstep(0.0, 0.05, d);
		float spine = exp(-pow(q.x / 0.045, 2.0)) * (1.0 - 0.4 * t);
		float barb = (0.5 + 0.5 * sin(abs(q.x) * 16.0 - q.y * 22.0)) * 0.2;
		float rim = smoothstep(0.1, 0.015, d);
		float ink = clamp(spine * 0.9 + rim * 0.7, 0.0, 1.0);
		c = mix(tint * (0.66 + 0.34 * (1.0 - t) + barb), rim_col, ink);
		op = mix(0.25 + 0.65 * par, 0.95, ink);
		g = exp(-max(-d, 0.0) * 11.0) * (1.0 - cov) * in_y * 0.35;
	} else if (st == 3) {
		float wob = 0.1 * sin(q.y * 5.0 - TIME * 5.5 + v_inst.g * 30.0) * t;
		float half = 0.62 * prof(t, 0.45, 1.3) * (0.92 + 0.08 * sin(TIME * 7.0 + v_inst.g * 17.0));
		float d = (half - abs(q.x - wob)) * in_y;
		cov = smoothstep(0.0, 0.08, d);
		float core = smoothstep(0.1, 0.4, d) * smoothstep(0.8, 0.15, t);
		c = mix(mix(tint, rim_col, core), vec3(1.0, 0.97, 0.8), core * core * 0.45);
		cov *= 0.8 + 0.2 * core;
		op = 0.3 + 0.5 * par;
		lum = 0.75;
		g = exp(-max(-d, 0.0) * 8.0) * (1.0 - cov) * in_y * 0.45;
	} else if (st == 4) {
		float half = 0.62 * min(min(t / 0.3, 1.0), (1.0 - t) / 0.42);
		float d = (half - abs(q.x)) * in_y;
		cov = smoothstep(0.0, 0.045, d);
		float rim = smoothstep(0.1, 0.015, d);
		float facet = q.x < 0.0 ? 1.0 : 0.66;
		float ridge = exp(-pow(q.x / 0.03, 2.0)) * 0.8;
		float gl = pow(max(1.0 - abs(t - 0.62) * 3.0, 0.0), 3.0) * 0.6;
		c = mix(tint * facet * (0.6 + 0.4 * t), rim_col, clamp(rim * 0.75 + ridge, 0.0, 1.0));
		c = mix(c, vec3(1.0), gl);
		op = 0.5 + 0.4 * par;
		g = exp(-max(-d, 0.0) * 12.0) * (1.0 - cov) * in_y * 0.4;
	} else if (st == 5) {
		vec2 b = abs(q) - vec2(0.56, 0.9);
		float d = -max(b.x, b.y);
		cov = smoothstep(0.0, 0.04, d);
		float border = smoothstep(0.15, 0.1, d) * smoothstep(0.02, 0.06, d);
		// 符纸上的字：几道横画，长短按相位掷；中间一竖
		float row = floor((q.y + 0.75) / 0.25);
		float fy = fract((q.y + 0.75) / 0.25) - 0.5;
		float len = 0.14 + 0.26 * halo_hash(row * 3.7 + v_inst.g * 91.0);
		float glyph = step(abs(q.y), 0.72) * step(abs(q.x), len) * exp(-pow(fy / 0.16, 2.0));
		float stem = step(abs(q.y), 0.66) * exp(-pow(q.x / 0.035, 2.0)) * 0.7;
		float ink = clamp(border + glyph * 0.9 + stem, 0.0, 1.0);
		c = mix(tint * 0.75, rim_col, ink);
		cov *= max(ink, 0.3);
		op = 0.25 * par;
		lum = 1.0;
		g = exp(-max(-d, 0.0) * 10.0) * (1.0 - cov) * 0.3;
	} else if (st == 6 || st == 7) {
		float d = 1.0 - (abs(q.x) / 0.72 + abs(q.y) / 1.0);
		cov = smoothstep(0.0, 0.035, d);
		g = exp(-max(-d, 0.0) * 9.0) * (1.0 - cov);
		if (st == 6) {
			float border = smoothstep(0.18, 0.12, d);
			float inner = exp(-pow((d - 0.36) / 0.035, 2.0));
			float knot = smoothstep(0.035, 0.0, abs(1.0 - (abs(q.x) / 0.2 + abs(q.y) / 0.28)) * 0.2);
			float cross = (exp(-pow(q.x / 0.03, 2.0)) + exp(-pow(q.y / 0.04, 2.0))) * step(0.36, d) * 0.6;
			float lit = 0.55 + 0.35 * smoothstep(-1.0, 1.0, -q.x + q.y);
			c = mix(tint * lit, rim_col, clamp(border + inner * 0.9 + knot + cross, 0.0, 1.0));
			op = 0.7 * par;
			g *= 0.4;
			gc = rim_col;
		} else {
			float facet = 0.55 + 0.45 * smoothstep(0.3, -0.3, q.x - q.y * 0.6);
			float border = smoothstep(0.16, 0.06, d);
			c = mix(tint * facet, rim_col, border * 0.8);
			op = 0.92;
			// 宝石上的一点星芒（形状外面也有）
			float star = (exp(-abs(q.x) * 14.0) * exp(-abs(q.y) * 2.6) + exp(-abs(q.y) * 14.0) * exp(-abs(q.x) * 2.6)) * (0.6 + 0.4 * sin(TIME * 2.4 + v_inst.g * 30.0));
			c = mix(c, vec3(1.0), clamp(star, 0.0, 1.0) * cov);
			g = g * 0.5 + star * (1.0 - cov) * 0.7;
			gc = mix(tint, vec3(1.0), 0.5);
		}
	} else if (st == 8) {
		float star = exp(-abs(q.x) * 16.0) * exp(-abs(q.y) * 2.4) + exp(-abs(q.y) * 16.0) * exp(-abs(q.x) * 2.4);
		g = clamp(star + exp(-dot(q, q) * 26.0), 0.0, 1.0);
		gc = mix(tint, vec3(1.0), 0.4);
	} else if (st == 10) {
		float line = exp(-pow(q.x / 0.06, 2.0)) * step(-0.55, q.y) * in_y;
		float bead = smoothstep(0.2, 0.12, length((q - vec2(0.0, 0.82)) * vec2(1.0, 0.55)));
		float ty = clamp((-0.55 - q.y) / 0.45, 0.0, 1.0);
		float fringe = step(q.y, -0.55) * in_y * smoothstep(0.26 * (1.0 - ty * 0.7), 0.0, abs(q.x)) * (0.6 + 0.4 * sin(q.x * 40.0));
		cov = clamp(line + bead + fringe, 0.0, 1.0);
		lum = 1.0;
		c = mix(tint, rim_col, clamp(line + bead, 0.0, 1.0));
		op = clamp(bead * 0.9 + fringe * 0.6 * par + line * 0.5, 0.0, 1.0);
	} else if (st == 11) {
		float half = 0.85 * (1.0 - t) * (0.9 + 0.1 * t);
		float d = (half - abs(q.x)) * in_y;
		cov = smoothstep(0.0, 0.05, d);
		float rim = smoothstep(0.12, 0.02, d);
		float lit = 0.78 + 0.22 * smoothstep(0.4, -0.4, q.x);
		c = mix(tint * lit, rim_col, rim * 0.8);
		op = 0.94 * par;
		g = exp(-max(-d, 0.0) * 12.0) * (1.0 - cov) * in_y * 0.3;
	} else {
		float r = length(q);
		float core = exp(-r * r * 7.0);
		g = clamp(core + exp(-r * 3.0) * 0.4, 0.0, 1.0) * (0.88 + 0.12 * sin(TIME * 2.2 + v_inst.g * 20.0)) * smoothstep(1.0, 0.8, r);
		gc = mix(tint, vec3(1.0), core * 0.6);
	}
	float k = power * v_tint.a * mix(1.0, rear, float(FRONT_FACING));
	vec3 p = (c * cov * mix(op, 1.0, lum) + gc * g * 0.55) * k;
	float a = cov * op * k;
	ALBEDO = halo_albedo(p, a);
	ALPHA = a;
}
