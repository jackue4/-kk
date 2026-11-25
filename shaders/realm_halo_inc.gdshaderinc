// 境界光环特效（scripts/realm_halo.gd）三个着色器共用的出口。
// 都用预乘混合：屏幕 = 颜色 + (1 − 遮挡度) × 背景 —— 实心的金 / 玉 / 晶体给遮挡度，柔光遮挡度给 0（纯加亮），一遍画完。
// 颜色都按「显示出来的颜色」写。兼容渲染器（网页 / 手机）就在显示色空间里混合，原样给；
// Forward+ 在线性空间里混合，直接转线性的话柔光会弱很多，按「背后是中等亮度的背景」换算成线性空间里等效的加数
// （2026-11-23 实测过，标定工具留底在 _tasks/realm_halo/v1_sprite/blend_calib.gd.txt）。
uniform float power = 1.0;        // 整体强度（觉醒的淡入淡出）
uniform float rear_push = 0.0;    // 镜头在人身后时，把深度往远处推这么多米（0 = 不推）

// 光环立在人的背后，游戏里镜头也在人身后 —— 光环夹在镜头和人中间，会盖在人身上。
// 所以镜头在光环背面那一侧时，只把「深度」沿视线往远处推到人的后面（屏幕上的位置、大小都不变）：
// 人照常画在它前面，和原画一样是「人在前、环在后」；从正面 / 侧面看时不推，就是它本来的位置。
vec4 halo_clip(vec3 view_pos, vec3 view_n, mat4 proj) {
	vec4 clip = proj * vec4(view_pos, 1.0);
	if (rear_push > 0.0) {
		float len = max(length(view_pos), 0.01);
		float facing = dot(view_n, -view_pos / len);
		float d = rear_push * smoothstep(0.0, 0.2, facing);
		vec4 far = proj * vec4(view_pos * ((len + d) / len), 1.0);
		clip.z = far.z / far.w * clip.w;
	}
	return clip;
}

vec3 halo_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 halo_albedo(vec3 p, float a) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return p;
#else
	vec3 under = vec3(0.4) * (1.0 - a);
	return max(halo_lin(p + under) - halo_lin(vec3(0.4)) * (1.0 - a), vec3(0.0));
#endif
}

float halo_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float halo_hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
