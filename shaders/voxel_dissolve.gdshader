// 死亡碎块：方块碎裂后逐块"消融"。
// INSTANCE_CUSTOM.x 消融进度 0~1（噪声阈值往上推，被吃掉的边缘烧成 edge_color 的亮边）
// INSTANCE_CUSTOM.y 每块的噪声种子  INSTANCE_CUSTOM.z 裂纹光（碎裂波扫过那一下，沿方块缝发亮）
// 网格是 1x1x1 的方块，VERTEX 本身就是块内坐标（-0.5 ~ 0.5），用来算缝和噪声。
shader_type spatial;
render_mode cull_disabled;

uniform vec3 edge_color : source_color = vec3(1.0, 0.45, 0.2);
uniform float edge_energy = 5.0;
uniform vec3 ash_color : source_color = vec3(0.09, 0.08, 0.08);

varying vec3 lp;
varying vec4 cust;

void vertex() {
	lp = VERTEX;
	cust = INSTANCE_CUSTOM;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 q = lp * 3.2 + vec3(cust.y * 31.7, cust.y * 17.3, cust.y * 7.1);
	float n = vnoise(q) * 0.65 + vnoise(q * 2.7) * 0.35;
	// 顶部先化：同一块里越往上越早被吃掉，像在往上蒸
	n -= (lp.y + 0.5) * 0.18;
	float th = cust.x * 1.25 - 0.2;
	if (cust.x > 0.0 && n < th) {
		discard;
	}
	float e = (1.0 - smoothstep(0.0, 0.12, n - th)) * step(0.001, cust.x);
	vec3 a = abs(lp) * 2.0;
	vec3 w = smoothstep(vec3(0.76), vec3(1.0), a);
	float seam = clamp(w.x + w.y + w.z - 1.0, 0.0, 1.0);
	vec3 base = COLOR.rgb * (1.0 - 0.2 * seam);
	base = mix(base, ash_color, smoothstep(0.15, 0.85, cust.x) * 0.75);
	ALBEDO = mix(base, edge_color, e * 0.75);
	EMISSION = edge_color * edge_energy * e + edge_color * cust.z * (0.6 + 2.5 * seam) + COLOR.rgb * cust.z * 0.5;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
