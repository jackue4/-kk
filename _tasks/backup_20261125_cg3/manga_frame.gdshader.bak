// 觉醒演出的黑白漫画帧（scripts/awaken_cine.gd，2026-11-25）：把当前画面整屏画成漫画稿——
// 白纸、黑线稿（亮度的边缘）、暗部涂黑、中间调打网点，再压一圈朝焦点收拢的集中线；invert = 1 时整张反白（黑底白线）。
// 只在觉醒演出的那零点几秒里开（平时这一层不画）；不现算噪声贴图，一个像素五次取样 + 几次哈希。
// 用户原话（2026-11-25）：「觉醒的时候……没有视觉冲击感很强的黑白漫画风画面」。普通出招 / 命中不用它（那边的规矩还是不闪屏）。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float k = 0.0;            // 0 原画面 … 1 整屏漫画帧
uniform float invert = 0.0;       // 0 白纸黑线 · 1 黑底白线
uniform vec2 center = vec2(0.5, 0.5);   // 集中线的焦点（屏幕 0~1）
uniform float lines = 0.0;        // 集中线的多少 / 粗细 0~1
uniform float tone = 1.0;         // 网点 0~1
uniform float seed = 0.0;         // 换一组集中线
uniform float aspect = 1.78;
uniform float bars = 0.0;         // 上下黑边各占屏高多少
uniform float hole = 0.2;         // 集中线中间空出来的半径（按屏高）
// 剪影：sil = 1 的那几帧，把主角画成实心黑（反白后就是黑底白人）。主角在哪由 mask_tex 给 —— 演出另开一个只画主角的小视口
// （和主镜头同一个机位，背景透明），它的透明度就是主角的轮廓；不靠画面亮度去猜（白地面 / 亮天空会被认错）
uniform float sil = 0.0;
uniform sampler2D mask_tex : repeat_disable, filter_linear;

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 src = texture(screen_tex, uv).rgb;
	vec3 col = src;
	if (k > 0.001) {
		float l0 = lum(src);
		// 线稿：左右 / 上下的亮度差
		float w = 1.6;
		float lx = lum(texture(screen_tex, uv + vec2(px.x * w, 0.0)).rgb) - lum(texture(screen_tex, uv - vec2(px.x * w, 0.0)).rgb);
		float ly = lum(texture(screen_tex, uv + vec2(0.0, px.y * w)).rgb) - lum(texture(screen_tex, uv - vec2(0.0, px.y * w)).rgb);
		float edge = smoothstep(0.05, 0.14, length(vec2(lx, ly)));
		// 暗部涂黑
		float ink = smoothstep(0.26, 0.18, l0);
		// 中间调：45 度排的网点，越暗点越大
		float dot_px = max(4.0, 1.0 / px.y / 150.0);
		vec2 q = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * (FRAGCOORD.xy / dot_px);
		float rad = 0.54 * smoothstep(0.66, 0.24, l0) * tone;
		float dots = (1.0 - smoothstep(rad - 0.07, rad + 0.07, length(fract(q) - 0.5))) * step(0.001, rad);
		float v = 1.0 - max(max(ink, dots), edge);      // 1 白 · 0 黑
		// 集中线：一圈楔形的黑线朝焦点收，离焦点 hole 以内空着
		if (lines > 0.001) {
			vec2 d = vec2((uv.x - center.x) * aspect, uv.y - center.y);
			float rr = length(d);
			float a = atan(d.y, d.x) / 6.28318 + 0.5;
			float n = 110.0;
			float seg = floor(a * n);
			float h1 = hash1(seg + seed * 17.0);
			float h2 = hash1(seg * 1.7 + 3.1 + seed * 5.0);
			float fa = abs(fract(a * n) - 0.5);
			float start = hole + 0.42 * h2 * (1.0 - 0.6 * lines);
			float wid = (0.5 - 0.4 * h1) * smoothstep(start, start + 0.3, rr);
			float line = step(1.0 - 0.72 * lines, h1) * step(start, rr) * (1.0 - smoothstep(wid * 0.75, wid, fa));
			v = min(v, 1.0 - line);
		}
		if (sil > 0.5) {
			v = mix(v, 0.0, smoothstep(0.35, 0.65, texture(mask_tex, uv).a));
		}
		v = mix(v, 1.0 - v, invert);
		col = mix(src, vec3(v), k);
	}
	if (bars > 0.001) {
		col = mix(col, vec3(0.0), clamp(step(uv.y, bars) + step(1.0 - bars, uv.y), 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
