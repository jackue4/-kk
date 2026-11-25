// 灵田农场（hub_farm.gd）的流水：水渠 / 池塘的水面和瀑布共用一个着色器（2026-11-21 场景美术专项）。
// 颜色在顶点色里（sRGB，和 block_world.gdshader 同一套约定），alpha = 亮度加成。
// · 朝上的面（水渠、池塘）：两层噪声朝相反方向漂，亮处是波光
// · 竖着的面（瀑布、水车引水槽的出水）：竖向条纹往下流，越往下越白（水花）
// 不受光（unshaded）：水本来就是亮的那一块，也省掉阴影 / 灯光的着色器变体；雾照常。
// 噪声查 fx/cine/cine_noise.png（可无缝平铺，手机上别现算噪声，见 mobile-fullscreen-shader-cost）。
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float speed = 1.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = clamp(COLOR.rgb, vec3(0.0), vec3(1.0));
	float t = TIME * speed;
	vec3 c;
	if (abs(wn.y) > 0.5) {
		vec2 p = wp.xz;
		float n1 = texture(noise_tex, p * 0.031 + vec2(t * 0.018, t * 0.011)).r;
		float n2 = texture(noise_tex, p * 0.057 - vec2(t * 0.015, -t * 0.019)).b;
		float w = n1 * 0.6 + n2 * 0.4;
		float glint = smoothstep(0.60, 0.74, w);
		c = base * (0.84 + 0.30 * w) + vec3(0.92, 0.98, 1.0) * glint * 0.32;
	} else {
		float h = wp.x + wp.z;
		float s = texture(noise_tex, vec2(h * 0.21, wp.y * 0.024 + t * 0.42)).r;
		float s2 = texture(noise_tex, vec2(h * 0.47 + 0.3, wp.y * 0.05 + t * 0.75)).g;
		float k = s * 0.65 + s2 * 0.35;
		float foam = smoothstep(0.52, 0.70, k);
		c = base * (0.80 + 0.36 * k) + vec3(0.95, 0.98, 1.0) * foam * 0.36;
	}
	c *= 1.0 + clamp(COLOR.a, 0.0, 1.0) * 0.25;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = c;
#else
	ALBEDO = pow(c, vec3(2.2));
#endif
}
