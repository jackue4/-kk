// 旋涡门的"地面"：取自 portal_preview.tscn 里 GroundMesh 的内联着色器（圆形软边、render_priority -128、depth_draw_always）。
// 原版的洞是 Hole（portal_effect）在这块地面上抠出来、透出地下的漏斗光锥；R 的门悬在半空、没有地面，
// 所以每扇门自带一块这样的圆面当"地面"：遮住门后的光锥，只让它从 Hole 的旋涡里透出来。
// 去掉棋盘格和打光，改成深紫近黑；alpha 用 instance uniform，所有门共用一份材质。
shader_type spatial;
render_mode unshaded, depth_draw_always, shadows_disabled, fog_disabled;

uniform vec3 albedo_color : source_color = vec3(0.04, 0.03, 0.08);
uniform float inner = 0.3;   // UV 半径：这里以内完全不透明
uniform float outer = 0.45;  // UV 半径：这里以外完全透明

instance uniform float alpha = 1.0;

void fragment() {
	ALBEDO = albedo_color;
	ALPHA = smoothstep(outer, inner, length(UV - vec2(0.5))) * alpha;
}
