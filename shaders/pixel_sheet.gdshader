// pixelfx 精灵表（像素特效序列帧）的 3D 播放：朝相机的面片，锚点对准命中点。
// 像素是方的、最近邻采样，和体素小人的方块质感一致。
// 精灵表里烘进去的柔光晕（低 alpha）和暗色底（如内爆的暗球）都剔掉，只留清楚的亮线、光环和火星，
// 外面再描一圈 1 像素的深色描边——浅色大厅里也压得住，不会糊成灰白雾团。
// recolor 把有颜色的像素换成 tint 的明暗（按亮度），近白的芯保持白，用来按境界 / 刀色换色。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform vec2 sheet_px = vec2(1.0);   // 整张精灵表像素尺寸
uniform vec2 frame_px = vec2(1.0);   // 单帧像素尺寸
uniform vec2 pivot_px = vec2(0.0);   // 锚点（帧内像素坐标，y 向下）
uniform float cols = 1.0;
uniform float frame = 0.0;
uniform float px_size = 0.03;        // 每个像素的世界尺寸（米）
uniform float roll = 0.0;            // 屏幕平面内旋转（弧度）
uniform bool flip = false;           // 水平镜像（绕锚点）
uniform vec4 tint : source_color = vec4(1.0);
uniform float recolor = 0.0;
uniform float intensity = 1.0;
uniform float alpha_cut = 0.42;
uniform float lum_cut = 0.42;
uniform float outline = 0.8;         // 描边不透明度（0 关闭）
uniform float alpha = 1.0;

void vertex() {
	vec2 d = (UV * frame_px - pivot_px) * px_size;
	vec2 o = vec2(flip ? -d.x : d.x, -d.y);
	float c = cos(roll);
	float s = sin(roll);
	o = vec2(o.x * c - o.y * s, o.x * s + o.y * c);
	vec3 world = MODEL_MATRIX[3].xyz + INV_VIEW_MATRIX[0].xyz * o.x + INV_VIEW_MATRIX[1].xyz * o.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

vec4 texel(vec2 base, vec2 px) {
	if (px.x < 0.0 || px.y < 0.0 || px.x >= frame_px.x || px.y >= frame_px.y) {
		return vec4(0.0);
	}
	return texture(sheet, (base + px + 0.5) / sheet_px);
}

bool solid(vec4 c) {
	return c.a >= alpha_cut && max(c.r, max(c.g, c.b)) >= lum_cut;
}

void fragment() {
	float f = floor(frame + 0.5);
	vec2 base = vec2(mod(f, cols), floor(f / cols)) * frame_px;
	vec2 px = floor(UV * frame_px);
	vec4 c = texel(base, px);
	vec3 shade = mix(vec3(0.3, 0.12, 0.06), tint.rgb * 0.28, recolor);
	if (!solid(c)) {
		bool edge = solid(texel(base, px + vec2(1.0, 0.0))) || solid(texel(base, px - vec2(1.0, 0.0)))
				|| solid(texel(base, px + vec2(0.0, 1.0))) || solid(texel(base, px - vec2(0.0, 1.0)));
		if (!edge || outline <= 0.0) {
			discard;
		}
		ALBEDO = shade;
		ALPHA = outline * alpha;
	} else {
		float lum = max(c.r, max(c.g, c.b));
		float sat = lum - min(c.r, min(c.g, c.b));
		float w = smoothstep(0.85, 1.0, lum) * (1.0 - smoothstep(0.1, 0.35, sat));
		vec3 ramp = mix(tint.rgb * (0.55 + 0.45 * lum), vec3(1.0), w * 0.45);
		ALBEDO = mix(c.rgb, ramp, recolor) * intensity;
		ALPHA = clamp(c.a * alpha, 0.0, 1.0);
	}
}
