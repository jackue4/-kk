// 披风的描边（cape_cloth.gd 的 set_outline，和 block_outline.gdshader 是一对）：披风是一张敞开的薄片，没法靠「往外撑一圈」出线，
// 这里把整幅在屏幕上以披风中心为心往外放大一圈，再顺着视线往远处挪一点：正面被披风自己挡住，只在四周露出一道边。
// 网格里外两层各有一遍顶点（COLOR 白 = 外面，灰 = 里衬），只画外面那一层。
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 line_color : source_color = vec3(0.5, 0.9, 1.0);
uniform float width = 0.026;
uniform float power = 1.0;
uniform float push = 0.16;
uniform vec3 center = vec3(0.0, -0.55, 0.12);    // 披风中心（节点本地，cape_cloth.gd 每帧给）
// 2026-11-21 PvP 锁定描边用（同 block_outline.gdshader）：默认值 = 觉醒描边原样
uniform float whiten = 0.25;
uniform float flicker = 1.0;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
const float ENERGY = 1.0;
#else
const float ENERGY = 1.5;
#endif

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 vc = MODELVIEW_MATRIX * vec4(center, 1.0);
	vec2 d = vp.xy / max(-vp.z, 0.05) - vc.xy / max(-vc.z, 0.05);
	float dl = length(d);
	float w = width * power * clamp(length(vp.xyz) / 7.0, 1.0, 3.5) * mix(1.0, 0.88 + 0.12 * sin(TIME * 7.0), flicker);
	if (dl > 1e-5) {
		vp.xy += d / dl * w;
	}
	vp.xyz += normalize(vp.xyz) * push;
	POSITION = PROJECTION_MATRIX * vp;
	if (COLOR.r < 0.8) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);     // 里衬那一层：收成屏幕外的一个点，不画
	}
}

void fragment() {
	ALBEDO = mix(line_color, vec3(1.0), whiten) * mix(1.0, 0.9 + 0.1 * sin(TIME * 7.0), flicker) * ENERGY;
}
