// 神识一扫的光带（scripts/shen_shi.gd，2026-11-23，参考用户给的图二）：一条预先算好路径的带状网格，
// UV.x = 沿路径 0 → 1，UV.y = 横跨 0 → 1。脚本只推 head（头部走到路径的哪里），网格不用每帧重建。
//   · 地面光带：从主角脚下顺着山势贴地往外窜，头部跟着地形光波的波前走，身后拖一截渐淡的尾巴
//   · 身周气丝（soft = 1）：绕着主角盘旋上升的几缕柔光，白芯弱、晕宽
// 加色、不写深度；被山挡住的部分照常被挡（有深度测试）。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float head = 0.0;           // 头部在路径上的位置（UV.x 的单位）
uniform float tail = 0.25;          // 拖尾长度（同上）
uniform float power = 1.0;
uniform float irid = 0.5;
uniform float jit = 0.3;            // 白芯的电弧抖动
uniform float soft = 0.0;           // 1 = 气丝（柔）
uniform float seed = 0.0;
uniform vec3 col_a : source_color = vec3(0.8, 0.95, 1.0);
uniform vec3 col_b : source_color = vec3(0.6, 0.8, 1.0);

void fragment() {
	float u = UV.x;
	float v = UV.y * 2.0 - 1.0;
	float s = (head - u) / max(tail, 1e-3);            // 0 = 头，1 = 尾巴末梢
	float along = smoothstep(0.0, 0.035, s) * (1.0 - smoothstep(0.55, 1.0, s));
	along *= 1.0 - 0.6 * s;
	// 地面光带的起头（主角脚下、镜头跟前那一截）淡进来：贴着镜头的几层加色叠起来会糊成一片白；气丝本来就短，不淡
	along *= mix(smoothstep(0.02, 0.12, u), 1.0, soft);
	// 白芯沿着带子抖（电弧），越靠头越躁
	float wob = (sin(u * 170.0 + TIME * 21.0 + seed * 7.0) * 0.6 + sin(u * 410.0 - TIME * 33.0 + seed) * 0.4) * jit * 0.32 * (1.0 - s);
	float vc = v - wob - sin(u * 23.0 + seed * 3.0 + TIME * 2.0) * 0.18;
	float core = exp(-vc * vc / mix(0.006, 0.05, soft));
	float body = exp(-v * v / mix(0.18, 0.45, soft));
	float h = fract(u * 3.5 + v * 0.25 - TIME * 0.25 + seed * 0.37);
	vec3 ir = 0.55 + 0.45 * cos(6.2832 * (h + vec3(0.0, 0.33, 0.67)));
	vec3 tint = mix(col_a, col_b, 0.5 + 0.5 * sin(u * 9.0 + seed * 2.0));
	vec3 fr = mix(tint, ir, irid);
	vec3 c = vec3(1.0) * core * mix(1.0, 0.35, soft) + fr * body * mix(0.55, 0.42, soft);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	c *= 0.62;      // 手机 / 网页：加色在 sRGB 里叠，同样的数要亮得多
#endif
	ALBEDO = c * along * power;
	ALPHA = 1.0;
}
