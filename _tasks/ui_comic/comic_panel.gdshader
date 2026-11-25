shader_type canvas_item;
// 人物身后的那块主色：斜切的平行四边形 + 墨线边 + 集中线 + 底部网点 + 下边像干笔刷出来的毛边。
// 一个 ColorRect 一张着色器，换英雄时用 reveal 从一侧擦进来。

uniform vec4 fill : source_color = vec4(0.945, 0.545, 0.1, 1.0);
uniform vec4 fill2 : source_color = vec4(0.82, 0.4, 0.04, 1.0);      // 集中线 / 网点的深一档
uniform vec4 ink : source_color = vec4(0.09, 0.078, 0.102, 1.0);
uniform vec2 rect_px = vec2(600.0, 730.0);
uniform float skew = 0.1;
uniform float border_px = 6.0;
uniform vec2 focus = vec2(0.5, 0.36);
uniform float rays = 44.0;
uniform float ray_amt = 1.0;
uniform float dot_cell = 9.0;          // 网点格子（屏幕像素）
uniform float rough_px = 0.0;         // 下边毛边有多深（0 = 齐的）
uniform float reveal = 1.0;            // 0 → 1 擦进来
uniform float wipe_dir = 1.0;          // 1 从左往右擦，-1 从右往左
uniform float flat_only = 0.0;         // 1 = 只要纯色（投影那一层用）

float hash(float n) {
	return fract(sin(n * 127.1 + 3.7) * 43758.5453);
}

void fragment() {
	vec2 p = UV * rect_px;
	float s = skew * rect_px.y;
	float xl = s * (1.0 - UV.y);
	float xr = rect_px.x - s * UV.y;
	// 下边：一道道宽窄不一的笔触，各自停在不同的高度
	float strip = floor((p.x + p.y * skew) / 7.0);
	float jag = rough_px * pow(hash(strip), 2.2) + rough_px * 0.35 * hash(floor(strip / 5.0) + 11.0);
	float yb = rect_px.y - jag;
	float d_side = min(p.x - xl, xr - p.x);
	float d_top = p.y;
	float d_bot = yb - p.y;
	if (d_side < 0.0 || d_top < 0.0 || d_bot < 0.0) {
		discard;
	}
	float t = (p.x - xl) / max(xr - xl, 1.0);
	float edge_t = wipe_dir > 0.0 ? t : 1.0 - t;
	if (edge_t > reveal) {
		discard;
	}
	vec3 col = fill.rgb;
	if (flat_only < 0.5) {
		// 集中线：从 focus 往外的一圈楔形
		vec2 v = (UV - focus) * rect_px;
		float ang = atan(v.y, v.x);
		float r = length(v) / rect_px.y;
		float k = ang / 6.2831853 * rays;
		float id = floor(k);
		float f = fract(k);
		float w = 0.1 + 0.34 * hash(id);
		float start = 0.2 + 0.22 * hash(id + 7.0);
		float ray = step(abs(f - 0.5), w * 0.5 * smoothstep(start, start + 0.45, r));
		col = mix(col, fill2.rgb, ray * ray_amt);
		// 底部网点
		vec2 g = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * FRAGCOORD.xy / dot_cell;
		float dr = length(fract(g) - 0.5);
		float amt = smoothstep(0.5, 1.0, UV.y);
		col = mix(col, fill2.rgb, step(dr, amt * 0.52));
		// 墨线边（下边是毛边，不描）
		float d = min(d_side * 0.98, d_top);
		if (rough_px < 0.5) {
			d = min(d, d_bot);
		}
		col = mix(ink.rgb, col, step(border_px, d));
		// 擦进来的那条边压一道墨线
		col = mix(col, ink.rgb, step(reveal - 0.012, edge_t) * step(reveal, 0.995));
	}
	COLOR = vec4(col, fill.a);
}
