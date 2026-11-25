shader_type canvas_item;
// 把透明底小视口里的 3D 英雄画成漫画人：粗墨线描边（按透明度往外扩）+ 内部墨线（亮度的索贝尔）+ 色阶 + 暗部压冷色网点 + 一块硬投影。
// 只是视口贴图上的一遍后处理，不动模型的材质，兼容渲染器（网页 / 手机）也能跑。

uniform vec2 texel = vec2(0.002, 0.002);         // 1 / 视口像素数
uniform float line_px = 5.0;                      // 轮廓线粗细（视口像素）
uniform vec4 ink : source_color = vec4(0.09, 0.078, 0.102, 1.0);
uniform float edge_gain = 1.0;                    // 内线强度（0 = 不画）
uniform float edge_thresh = 0.24;
uniform float shade_lo = 0.4;                     // 亮度低于它算暗部
uniform float dot_cell = 6.0;                     // 网点格子（屏幕像素）
uniform vec4 shade_col : source_color = vec4(0.2, 0.22, 0.5, 1.0);
uniform float shade_amt = 0.6;
uniform float sat = 1.25;
uniform float gain = 1.0;
uniform float levels = 5.0;
uniform float poster = 0.55;
uniform float mono = 0.0;                         // 1 = 两色墨稿（没选中的头像）
uniform vec4 mono_dark : source_color = vec4(0.13, 0.17, 0.3, 1.0);
uniform vec4 mono_light : source_color = vec4(0.86, 0.86, 0.84, 1.0);
uniform vec2 drop = vec2(0.0, 0.0);               // 硬投影偏移（UV）
uniform vec4 drop_col : source_color = vec4(0.09, 0.078, 0.102, 0.0);

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// 旁边那个像素的亮度；它是透明的就当成和自己一样（轮廓归描边管，纱 / 披风那种隔一个像素镂一个的抖动透明也不会被当成一堆线）
float nlum(sampler2D tex, vec2 uv, float self_l) {
	vec4 s = texture(tex, uv);
	return s.a > 0.5 ? lum(s.rgb / s.a) : self_l;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec4 n_t = texture(TEXTURE, UV + texel * vec2(0.0, -1.0));
	vec4 n_b = texture(TEXTURE, UV + texel * vec2(0.0, 1.0));
	vec4 n_l = texture(TEXTURE, UV + texel * vec2(-1.0, 0.0));
	vec4 n_r = texture(TEXTURE, UV + texel * vec2(1.0, 0.0));
	// 透明底视口出来的颜色是乘过透明度的（边缘偏黑），先除回去
	vec3 col = c.a > 0.004 ? clamp(c.rgb / c.a, 0.0, 1.0) : vec3(0.0);
	float ca = c.a;
	// 抖动透明（霜华的纱）：自己是镂空的、上下左右多数是实的 → 补成实的，颜色取旁边的平均
	float solid_n = step(0.5, n_t.a) + step(0.5, n_b.a) + step(0.5, n_l.a) + step(0.5, n_r.a);
	if (ca < 0.5 && solid_n > 2.5) {
		col = clamp((n_t.rgb + n_b.rgb + n_l.rgb + n_r.rgb) / max(n_t.a + n_b.a + n_l.a + n_r.a, 0.001), 0.0, 1.0);
		ca = 1.0;
	}
	float l0 = lum(col);

	float a_ring = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5235988;
		vec2 d = vec2(cos(ang), sin(ang)) * texel * line_px;
		a_ring = max(a_ring, texture(TEXTURE, UV + d).a);
		a_ring = max(a_ring, texture(TEXTURE, UV + d * 0.55).a);
	}
	float tl = nlum(TEXTURE, UV + texel * vec2(-1.0, -1.0), l0);
	float tr = nlum(TEXTURE, UV + texel * vec2(1.0, -1.0), l0);
	float bl = nlum(TEXTURE, UV + texel * vec2(-1.0, 1.0), l0);
	float br = nlum(TEXTURE, UV + texel * vec2(1.0, 1.0), l0);
	float tc = n_t.a > 0.5 ? lum(n_t.rgb / n_t.a) : l0;
	float bc = n_b.a > 0.5 ? lum(n_b.rgb / n_b.a) : l0;
	float ml = n_l.a > 0.5 ? lum(n_l.rgb / n_l.a) : l0;
	float mr = n_r.a > 0.5 ? lum(n_r.rgb / n_r.a) : l0;
	float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
	float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
	float e = smoothstep(edge_thresh, edge_thresh + 0.2, sqrt(gx * gx + gy * gy)) * edge_gain;

	// 色阶：亮度压成几档（赛璐璐的平涂感），只压一半，留一点原来的过渡
	float lq = floor(l0 * levels + 0.5) / levels;
	col *= mix(1.0, lq / max(l0, 0.02), poster);
	col = clamp(mix(vec3(lum(col)), col, sat) * gain, 0.0, 1.0);
	// 暗部：冷色网点（越暗点越大，最暗处连成一片）
	vec2 g = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * FRAGCOORD.xy / dot_cell;
	float dr = length(fract(g) - 0.5);
	float dark = 1.0 - smoothstep(shade_lo - 0.2, shade_lo + 0.04, l0);
	float dots = step(dr, dark * 0.66);
	col = mix(col, col * shade_col.rgb * 1.5, dots * shade_amt);
	if (mono > 0.5) {
		float m = smoothstep(0.2, 0.72, l0);
		m = floor(m * 3.0 + 0.5) / 3.0;
		col = mix(mono_dark.rgb, mono_light.rgb, m);
		col = mix(col, mono_dark.rgb, dots * 0.5);
	}
	col = mix(col, ink.rgb, e * step(0.5, ca));

	// 合成：人 > 轮廓线 > 投影。轮廓线只画在「旁边比自己实」的地方
	float a_line = clamp(a_ring - ca, 0.0, 1.0);
	float a = ca + a_line;
	vec3 outc = (col * ca + ink.rgb * a_line) / max(a, 0.001);
	a = min(a, 1.0);
	float a_drop = step(0.5, texture(TEXTURE, UV - drop).a) * drop_col.a;
	outc = mix(drop_col.rgb, outc, a);
	a = max(a, a_drop);
	COLOR = vec4(outc, a);
}
