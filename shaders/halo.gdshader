// 法相光环（化神剑轮 / 大乘剑河 / 天环）：一张面片上画多层细线圆环，取代以前"一圈细环一闪即收"。
// 由外向内：外沿极细副环 → 主环（亮芯 + 柔光 + 绕行的两点高光）→ 刻度环（72 道细刻，每 6 道一长）
// → 反向旋转的三段弧 → 符文环（十二段断续弧，段间一颗小菱点）→ 内环 → 放射细辐 → 中心小环。
// 线宽按像素下限取，远近都是清晰的细线；open 0→1 由内向外依次展开，展开前沿亮一下；
// spin 由脚本推进（真实时间），各层按不同速率、方向转；rainbow > 0 时环色沿角度缓慢流转（大乘）。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(0.5, 0.78, 1.0, 1.0);
uniform float alpha = 1.0;
uniform float open = 1.0;
uniform float spin = 0.0;
uniform float rainbow = 0.0;
uniform float intensity = 1.35;

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

float line(float d, float w, float aa) {
	return 1.0 - smoothstep(w, w + aa, abs(d));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float u = atan(p.y, p.x) / TAU + 0.5;
	float aa = fwidth(r) * 1.2 + 1e-4;
	float lw = max(aa * 0.9, 0.005);

	float core = 0.0;  // 亮芯（偏白）
	float body = 0.0;  // 色带

	// 外沿副环 + 主环
	body += line(r - 0.975, lw * 0.6, aa) * 0.6;
	core += line(r - 0.93, lw, aa);
	body += exp(-abs(r - 0.93) * 55.0) * 0.5;
	// 主环上两点反向绕行的高光
	float h1 = pow(max(cos((u - spin * 0.09) * TAU), 0.0), 28.0);
	float h2 = pow(max(cos((u + spin * 0.07 + 0.5) * TAU), 0.0), 40.0);
	float hl = h1 + h2 * 0.7;
	core += line(r - 0.93, lw * 2.4, aa * 2.0) * hl;
	body += exp(-abs(r - 0.93) * 22.0) * hl * 0.5;

	// 刻度环：按弧长画刻线，宽度不随半径变；每 6 道一根长刻
	float tk = (u - spin * 0.035) * 72.0;
	float tlong = 1.0 - step(0.5, mod(floor(tk), 6.0));
	float r_out = mix(0.882, 0.905, tlong);
	float band = smoothstep(0.845 - aa, 0.845, r) * (1.0 - smoothstep(r_out, r_out + aa, r));
	float td = (fract(tk) - 0.5) / 72.0 * TAU * r;
	body += line(td, lw * 0.9, aa) * band * 0.9;
	body += line(r - 0.835, lw * 0.7, aa) * 0.55;

	// 三段反向旋转的弧（各约 70°），弧端收尖
	float f2 = fract((u + spin * 0.06) * 3.0);
	float seg = smoothstep(0.0, 0.03, f2) * (1.0 - smoothstep(0.16, 0.2, f2));
	core += line(r - 0.76, lw * 0.7, aa) * seg * 0.7;
	body += line(r - 0.76, lw * 1.8, aa) * seg;

	// 符文环：十二段断续弧 + 段间小菱点
	float f3 = fract((u - spin * 0.02) * 12.0);
	float gap = smoothstep(0.07, 0.11, f3) * (1.0 - smoothstep(0.89, 0.93, f3));
	body += line(r - 0.625, lw, aa) * gap * 0.85;
	body += line(r - 0.585, lw * 0.6, aa) * gap * 0.5;
	float da = min(f3, 1.0 - f3) / 12.0 * TAU * r;
	core += 1.0 - smoothstep(0.02, 0.02 + aa, da + abs(r - 0.605));

	// 内环 + 放射细辐（中段亮、两头淡）+ 中心小环
	body += line(r - 0.5, lw * 0.8, aa) * 0.7;
	float sd = (fract((u + spin * 0.025) * 24.0) - 0.5) / 24.0 * TAU * r;
	float env = smoothstep(0.17, 0.26, r) * (1.0 - smoothstep(0.4, 0.48, r));
	body += line(sd, lw * 0.8, aa) * env * 0.55;
	body += line(r - 0.15, lw, aa) * 0.8;
	core += line(r - 0.07, lw * 0.6, aa) * 0.5;

	// 由内向外展开
	float edge = open * 1.05;
	float reveal = 1.0 - smoothstep(edge - 0.06, edge, r);
	float front = exp(-abs(r - edge) * 28.0) * (1.0 - smoothstep(0.85, 1.0, open)) * step(r, 1.0);

	vec3 cb = color_b.rgb;
	if (rainbow > 0.0) {
		vec3 rb = hsv2rgb(vec3(fract(u + spin * 0.05), 0.5, 1.0));
		cb = mix(cb, rb, rainbow * 0.5);
	}
	float c = clamp(core, 0.0, 1.0);
	ALBEDO = mix(cb, color_a.rgb, c * 0.8) * intensity * (1.0 + 0.4 * c);
	ALPHA = clamp(max(c, body) * reveal + front * 0.5, 0.0, 1.0) * alpha;
}
