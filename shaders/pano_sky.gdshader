// 主城 / 灵田农场的全景天空（2026-11-21 场景美术专项）：一张 2:1 的等距柱状图（assets/sky/hub_pano.jpg，
// _tasks/scene_art/make_sky.py 生成：左右已经无缝、天顶 / 天底按纬度抹平、整体轻微虚化），按视线方向取样。
// 图的正中（落日）朝 yaw 方向：0 = 正北（−Z），往东为正。
// 两种渲染器都直接写贴图色：带 source_color 的贴图两边取到的值一样（见 web-renderer-color-space 的记录），实测再用 exposure / tint 微调。
shader_type sky;

uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float yaw = 0.0;
uniform float exposure = 1.0;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);
uniform float horizon = 0.0;      // 地平线往上抬多少（弧度）：岛浮在云海上，眼睛比云面高，云海的边可以略低于视平线

void sky() {
	vec3 d = normalize(EYEDIR);
	float lon = atan(d.x, -d.z) - yaw;
	float lat = asin(clamp(d.y, -1.0, 1.0)) - horizon;
	vec2 uv = vec2(fract(lon / TAU + 0.5), clamp(0.5 - lat / PI, 0.002, 0.998));
	COLOR = texture(pano, uv).rgb * tint * exposure;
}
