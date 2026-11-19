// 贴图刀光（参考 _ref/blade_trail.jpg）：把 fx/blade_trail/blade_trail.png（AI 生成的横向刀光，透明底）
// 沿挥砍弧铺开。UV.x: 0=最新 1=最旧 → 贴图从右端尖头（最新）铺到左端尖尾（最旧）；UV.y: 0=靠剑柄 1=剑尖外沿，对应贴图上下。
// 贴图自带中间亮芯、两边墨色描边和碎点 / 金星；这里只按境界色给中间调轻染一层，亮芯保持近白、墨边保持深色。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_k = 0.35;   // 境界色染中间调的比例
uniform float glow = 1.2;      // 整体提亮（unshaded 下略过 1 让亮芯起辉）
uniform float alpha = 1.0;

void fragment() {
	vec4 c = texture(tex, vec2(1.0 - UV.x, UV.y));
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	// 中间调：既不是墨色暗部，也不是近白亮芯
	float mid = smoothstep(0.15, 0.5, hi) * (1.0 - smoothstep(0.75, 0.95, lo));
	vec3 col = mix(c.rgb, tint.rgb * hi, tint_k * mid);
	// 最旧一截再淡出一点，收刀干脆
	float fade = 1.0 - smoothstep(0.72, 1.0, UV.x);
	ALBEDO = col * glow;
	ALPHA = clamp(c.a * fade * alpha, 0.0, 1.0);
}
