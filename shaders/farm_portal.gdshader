// 主城 ⇄ 灵田农场的透视门（hub_portal.gd，2026-11-21 场景美术专项）：门洞里的那张面片。
// view 是另一边场景的实时画面（一个 SubViewport：自己的 World3D、相机 = 门对门的变换 × 主镜头），按 SCREEN_UV 取 —— 透过门洞看到的就是走过去会看到的。
// 那边的画面出图时不做色调映射 / 调色（hub_portal.gd 给它一份关掉这些的环境），这里还原成线性色交给主画面统一做，颜色和真走过去一致。
// 门洞四周（两侧和顶上；底边是地面，不画）：一圈粉金色的流光、靠边的画面像水面一样轻轻荡、几粒往上飘的光点。
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, depth_draw_opaque;

uniform sampler2D view : filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 size = vec2(8.0, 7.0);              // 门洞宽 / 高（米）
uniform vec3 rim_a = vec3(1.0, 0.66, 0.88);      // 屏幕色（sRGB）
uniform vec3 rim_b = vec3(1.0, 0.90, 0.62);
uniform float ripple = 0.006;                    // 靠边的画面荡多大（屏幕比例）
uniform float live = 1.0;                        // 0 = 那边还没画出来：只显示一层流光，不取画面

void fragment() {
	vec2 m = vec2(UV.x * size.x, (1.0 - UV.y) * size.y);
	float e = min(min(m.x, size.x - m.x), size.y - m.y);      // 到门洞边（两侧、顶）的距离
	float t = TIME;
	float rim_k = 1.0 - smoothstep(0.0, 1.8, e);
	vec2 nuv = m * 0.085 + vec2(t * 0.045, -t * 0.07);
	vec2 off = vec2(texture(noise_tex, nuv).r, texture(noise_tex, nuv + vec2(0.37, 0.61)).b) - 0.5;
	vec2 suv = SCREEN_UV + off * 2.0 * ripple * (0.2 + 0.8 * rim_k);
	vec3 v = texture(view, clamp(suv, vec2(0.001), vec2(0.999))).rgb;
	// 流光：沿着门边转的一圈噪声，颜色在粉和金之间流
	float sw = texture(noise_tex, vec2(e * 0.16 - t * 0.11, (m.x + m.y) * 0.055 + t * 0.035)).r;
	float glow = (1.0 - smoothstep(0.0, 1.05, e)) * (0.45 + 0.75 * sw);
	glow += (1.0 - smoothstep(0.0, 0.18, e)) * 0.6;
	vec3 rim = mix(rim_a, rim_b, smoothstep(0.3, 0.7, sw));
	// 光点：靠边多、往上飘
	float sp = texture(noise_tex, m * 0.31 + vec2(0.0, -t * 0.22)).g;
	sp = smoothstep(0.84, 0.9, sp) * (0.25 + 0.75 * rim_k);
	// 整面一层很淡的亮带，几秒扫过一次（看得出是一道门，不是一个洞）
	float sweep = exp(-pow((m.x - mod(t * 3.2, size.x * 3.0) + size.x) * 0.55, 2.0)) * 0.10;
	vec3 base = mix(rim_a * 0.55 + vec3(0.25), v, live);
	vec3 c = base * (1.0 - glow * 0.45) + rim * glow * 0.95 + vec3(1.0, 0.96, 0.86) * (sp * 0.9 + sweep);
	c = clamp(c, vec3(0.0), vec3(1.0));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = c;
#else
	ALBEDO = pow(c, vec3(2.2));
#endif
}
