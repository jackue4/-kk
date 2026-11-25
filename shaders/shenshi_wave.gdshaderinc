// 神识一扫的地形光波（scripts/shen_shi.gd，2026-11-23）：一道光波从主角脚下贴着地形往外扫过去。
// 地表（block_world.gdshader）和垫底的水面 / 云面（block_sea.gdshader）都 include 这一份，脚本每帧把波前半径等参数设进这两个材质。
// 没在扫的时候 ss_look.x = 0：调用方用 uniform 的 if 整段跳过，平时一点不多花（手机档也一样）。
// 画的东西都加在自发光上；颜色按 sRGB 给、返回值也是 sRGB，调用方按渲染器自己换算（见 block_world.gdshader 里的说明）：
//   · 波前：一道细亮的白芯 + 两侧一层带七彩的晕；境界高的白芯沿圆周抖成电弧
//   · 波后：等高线（每 3 米一道）+ 一圈圈往外荡的涟漪，随波前远去淡掉，像神识把山形「摸」了一遍
//   · 扫到最大半径附近淡出；脚底下几米不画（那里是身周的光环）
uniform vec4 ss_wave = vec4(0.0, 0.0, 0.0, 0.0);     // xyz 中心（世界坐标），w 波前半径（米）
uniform vec4 ss_look = vec4(0.0, 4.0, 0.0, 0.0);     // x 强度（0 = 关），y 波带半宽（米），z 电弧抖动 0~1，w 七彩 0~1
uniform vec3 ss_col_a = vec3(0.8, 0.95, 1.0);        // 主色（sRGB；不标 source_color，两种渲染器对它的处理不一样）
uniform vec3 ss_col_b = vec3(0.6, 0.8, 1.0);         // 副色
uniform float ss_max = 100.0;                        // 这一扫的最大半径（米）

vec3 shenshi_wave(vec3 at, float time) {
	vec2 dv = at.xz - ss_wave.xz;
	float d = length(dv);
	float R = ss_wave.w;
	float W = max(ss_look.y, 0.5);
	float ang = atan(dv.y, dv.x);
	// 电弧：沿圆周几道频率不同的起伏叠起来，波前那条线就不是死板的正圆
	float jit = (sin(ang * 23.0 + time * 7.0) * 0.55 + sin(ang * 61.0 - time * 12.0) * 0.3 + sin(ang * 149.0 + time * 19.0) * 0.15) * ss_look.z * 1.8;
	float x = d - R + jit;
	float core = exp(-x * x / (0.035 * W * W + 0.06));
	float band = exp(-x * x / (W * W));
	float trail = x < 0.0 ? exp(x / (W * 5.0)) : 0.0;
	// 波前身后再拖两道细光丝（像图二那样几股光并着走），沿圆周时明时暗
	float x1 = x + W * 0.95;
	float x2 = x + W * 2.0;
	float sw = 0.02 * W * W + 0.05;
	float brk = 0.55 + 0.45 * sin(ang * 7.0 + time * 1.6 + d * 0.025);
	float strands = (exp(-x1 * x1 / sw) * 0.65 + exp(-x2 * x2 / sw) * 0.38) * brk;
	// 等高线：每 3 米一道；线宽按屏幕算（fwidth），太密的地方（远处 / 陡坡）不画，免得糊成一片
	float hy = at.y / 3.0;
	float fw = max(fwidth(hy), 1e-4);
	float contour = (1.0 - smoothstep(fw * 0.6, fw * 1.7, abs(fract(hy + 0.5) - 0.5))) * (1.0 - smoothstep(0.12, 0.45, fw));
	// 波后的涟漪
	float s = 0.5 + 0.5 * sin(x * 0.7 - time * 3.0);
	float s2 = s * s;
	float rip = s2 * s2 * s2;
	// 七彩：顺着圆周、半径慢慢流动
	float h = fract(ang * 0.3183 + d * 0.011 - time * 0.12);
	vec3 irid = 0.55 + 0.45 * cos(6.2832 * (h + vec3(0.0, 0.33, 0.67)));
	vec3 tint = mix(ss_col_a, ss_col_b, 0.5 + 0.5 * sin(ang * 3.0 + time * 0.7));
	vec3 fringe = mix(tint, irid, ss_look.w);
	float edge = 1.0 - smoothstep(ss_max * 0.8, ss_max, d);
	float nearfade = smoothstep(1.5, 7.0, d);
	// 白芯：境界高（七彩多）的往七彩里掺一点，免得在亮地面上只剩一道白
	vec3 core_c = mix(vec3(0.95, 0.98, 1.0), fringe, 0.4 * ss_look.w);
	vec3 add = core_c * core * 1.35 + mix(fringe, vec3(1.0), 0.15) * band * 0.85
			+ mix(fringe, vec3(1.0), 0.3) * strands
			+ fringe * trail * (0.1 + 0.6 * contour + 0.22 * rip);
	return add * ss_look.x * edge * nearfade;
}
