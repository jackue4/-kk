shader_type spatial;
// 元婴身后放出来的七彩光芒（yuanying_cine.gd）：一张面朝镜头的半透明面片，上面是从中心往外放射、缓缓流动的一条条光带——
// 宽的像极光的帘子，细的像光丝；颜色顺着方向在青、金、蓝、紫之间慢慢变（参考《凡人修仙传》结婴那一幕）。
// 手机上要便宜：整张面片在全景里差不多铺满一屏，所以只查烘好的噪声贴图（fx/cine/cine_noise.png，三次采样），
// 没有现算的噪声。颜色按「屏幕上看到的」写：兼容渲染器（网页 / 手机）直接交，桌面的渲染器要先转成线性（不转就发白）。
// 用普通的半透明混合、不用加色：这时候天已经放亮了，加色叠上去一片白，颜色全没了；半透明盖上去才留得住青、金、蓝、紫。
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float power = 0.0;
uniform float reach = 0.8;       // 光带最远伸到面片半宽的几成
uniform float surge = 0.0;       // 消散时的那一阵涌动（0 ~ 1）：流得更快、光丝更密、整体更亮

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 dir = p / max(r, 0.0001);
	float t = TIME * (1.0 + 1.4 * surge);
	// 噪声坐标主要跟着方向走（同一个方向上沿半径变化很慢）→ 一条条放射的带子；再让它随半径慢慢偏一点，带子就有了弧度、像在飘
	// R / B 通道是分形噪声（8 个单位一个周期），G 是单层值噪声（64 格一个周期）
	float c = texture(noise_tex, (dir * 1.25 + vec2(r * 0.55 - t * 0.05, r * 0.2 + t * 0.018)) * 0.125 + vec2(0.21, 0.63)).r;
	float s = texture(noise_tex, (dir * 6.4 + vec2(t * 0.04, r * 1.1 - t * 0.16)) * 0.125 + vec2(0.57, 0.13)).b;
	float f = textureLod(noise_tex, (dir * 34.0 + vec2(r * 4.0 - t * 0.9, 3.0)) * 0.015625, 0.0).g;
	float wide = smoothstep(0.40, 0.64, c);                       // 宽帘子
	float strand = smoothstep(0.36, 0.60, s);                     // 帘子里的细带
	float f2 = f * f;
	float thread = f2 * f2 * f;                                   // 最细的光丝
	float band = wide * (0.16 + 0.84 * strand) + thread * (0.35 + 0.65 * surge) * (0.35 + 0.65 * wide);
	// 每条带子伸得不一样远；正中（被身子挡着）挖空，免得把脸糊白
	float far = reach * (0.55 + 0.75 * c);
	float fall = smoothstep(0.035, 0.17, r) * (1.0 - smoothstep(far * 0.45, far, r)) * (1.0 - smoothstep(0.86, 1.0, r));
	// 七彩：色相跟着帘子、细带和方向一起变
	float hue = c * 1.7 + s * 0.6 + dir.x * 0.22 + dir.y * 0.13 + r * 0.3 - t * 0.025;
	// 在参考图里的那几种颜色之间转：青 → 金 → 蓝 → 紫。不走整圈彩虹（试过：大红、草绿、品红一起上，太跳、太艳）
	vec4 w = 0.5 + 0.5 * cos(6.2832 * (hue - vec4(0.0, 0.25, 0.5, 0.75)));
	w *= w;
	vec3 col = (w.x * vec3(0.25, 0.98, 0.86) + w.y * vec3(1.0, 0.84, 0.42) + w.z * vec3(0.32, 0.62, 1.0) + w.w * vec3(0.74, 0.52, 1.0)) / (w.x + w.y + w.z + w.w);
	col = mix(col, vec3(1.0, 0.98, 0.92), 0.16 + 0.5 * thread);     // 压一点白：是光，不是颜料
	col *= 1.0 + 0.2 * surge;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = col;
#else
	ALBEDO = pow(col, vec3(2.2));
#endif
	ALPHA = clamp(band * fall * power * (1.0 + 0.3 * surge), 0.0, 0.8);
}
