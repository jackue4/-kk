// 方块世界垫底的水面 / 云面（scripts/block_world.gd 的 _sea）：一整片跟着主角走的大平面，垫在所有地块下面。
// 整块都是水（或云海）的远处地块不建网格，靠它把海 / 云海一直铺到天边。颜色和自发光由脚本按主角所在的区域渐变着设进来
// （草原的海、黄枫谷的溪河、血色禁地的血河、云梦山的云海、坠魔谷的魔雾）。
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform vec3 col = vec3(0.18, 0.6, 0.68);      // 屏幕上看到的颜色（sRGB）
uniform float em = 0.05;

// 2026-11-23 神识一扫的光波也扫过水面 / 云海（同 block_world.gdshader）
#include "res://shaders/shenshi_wave.gdshaderinc"
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = clamp(col, vec3(0.0), vec3(1.0));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// 兼容渲染器（网页 / 手机）里 ALBEDO、EMISSION 按 sRGB 写，引擎自己转线性（见 block_world.gdshader 里的说明）
	ALBEDO = c;
	EMISSION = c * pow(em * 2.0, 0.4545);
	if (ss_look.x > 0.001) {
		EMISSION += shenshi_wave(wp, TIME);
	}
#else
	vec3 base = pow(c, vec3(2.2));
	ALBEDO = base;
	EMISSION = base * em * 2.0;
	if (ss_look.x > 0.001) {
		vec3 sw = shenshi_wave(wp, TIME);
		EMISSION += sw * sw * 1.6;
	}
#endif
	ROUGHNESS = 1.0;
}
