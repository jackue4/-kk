// GDQuest WindGrass 原版着色器（Demos/WindGrass，Shaders/wind_grass.gdshader）。风、角色推草两段原样未动；
// 木兰草原改动（标 [木兰草原]）：
// · 从 unshaded 改成受光：草叶法线统一朝天（整片草地像一张毯子那样受光、吃树影和云影），
//   光照走 ghibli_light.gdshaderinc 的吉卜力色块光，逆光时草尖透亮；
// · 草环外缘按到角色的水平距离把草压矮淡出；
// · 按世界坐标采样与地面同一张色斑噪声做枯黄色斑，每丛草再随机一点深浅。
shader_type spatial;
render_mode cull_disabled;

// [木兰草原]
#include "res://shaders/ghibli_light.gdshaderinc"
uniform float fade_far = 120.0;
uniform float fade_len = 30.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 dry_color : source_color = vec3(0.86, 0.80, 0.42);
uniform sampler2D tint_noise : repeat_enable, filter_linear;
varying float patch_dry;
varying vec3 root_w;
varying float blade_var;
varying float tip;

uniform float wind_speed = 0.05;
uniform float wind_strength = 2.0;
// How big, in world space, is the noise texture
// wind will tile every wind_texture_tile_size
uniform float wind_texture_tile_size = 20.0;
uniform float wind_vertical_strength = 0.3;
uniform vec2 wind_horizontal_direction = vec2(1.0, 0.5);

uniform sampler2D color_ramp : source_color;
// we need a tiling noise here!
uniform sampler2D wind_noise : hint_default_black;

uniform vec3 character_position;
uniform float character_radius = 3.0;
uniform sampler2D character_distance_falloff_curve : hint_default_black;
uniform float character_push_strength = 1.0;

varying float debug_wind;

void vertex() {
	vec3 world_vert = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec2 normalized_wind_direction = normalize(wind_horizontal_direction);
	vec2 world_uv = world_vert.xz / wind_texture_tile_size + normalized_wind_direction * TIME * wind_speed;
	// we displace only the top part of the mesh
	// note that this means that the mesh needs to have UV in a way that the bottom of UV space
	// is at the top of the mesh
	float displacement_affect = (1.0 - UV.y);
	float wind_noise_intensity = (textureLod(wind_noise, world_uv, 0.0).r - 0.5);

	// We convert the direction of the wind into vertex space from world space
	// if we used it directly in vertex space, rotated blades of grass wouldn't behave properly
	vec2 vert_space_horizontal_dir = 
			(inverse(MODEL_MATRIX) * vec4(wind_horizontal_direction, 0.0, 0.0)).xy;
	
	vert_space_horizontal_dir = normalize(vert_space_horizontal_dir);
	
	vec3 bump_wind = vec3(
		wind_noise_intensity * vert_space_horizontal_dir.x,
		1.0 - wind_noise_intensity,
		wind_noise_intensity * vert_space_horizontal_dir.y);
	
	normalize(bump_wind);
	
	bump_wind *= vec3(wind_strength, wind_vertical_strength, wind_strength);
	
	VERTEX += bump_wind * displacement_affect;
	
	// At the moment the blades are pushed away in a perfectly circular manner.
	// We could distort the distance to the character based on a noise, to break a bit the
	// circular shape. We could distort the falloff by sampling in a noise based on the xz coordinates.
	// The task is left to the reader
	
	vec3 dir_to_character = character_position - MODEL_MATRIX[3].xyz;
	// uncomment the following line to have a horizontal only character push
	//dir_to_character.y = 0.0;
	float distance_to_character = length(dir_to_character);
	float falloff = 1.0 - smoothstep(0.0, 1.0, distance_to_character/character_radius);
	// Because we operate in vertex space, we need to convert the direction to the character
	// in vertex space. Otherwise, it wouldn't work for rotated blades of grass.
	// comment the next line to observe how the blades are not all facing away from the character.
	dir_to_character = (inverse(MODEL_MATRIX) * vec4(dir_to_character, 0.0)).xyz;
	dir_to_character = normalize(dir_to_character);

	// sample the curve based on how far we are from the character, in normalized coordinates
	float falloff_curve = texture(character_distance_falloff_curve, vec2(falloff)).x;
	// direction to character is inverted because we want to point away from it
	VERTEX += normalize(-dir_to_character) * falloff_curve * character_push_strength * displacement_affect;

	// [木兰草原] 草环外缘淡出：离角色越远草越矮，到 fade_far 压平（和地面贴图接上，不留一道硬边）
	vec3 root = MODEL_MATRIX[3].xyz;
	float d_flat = length(root.xz - character_position.xz);
	VERTEX *= 1.0 - smoothstep(fade_far - fade_len, fade_far, d_flat);
	patch_dry = smoothstep(0.5, 0.75, textureLod(tint_noise, root.xz / 900.0, 0.0).r) * 0.5;
	root_w = root;
	blade_var = 0.86 + 0.26 * fract(sin(dot(root.xz, vec2(12.9898, 78.233))) * 43758.5453);
	tip = 1.0 - UV.y;
}

void fragment() {
	ALBEDO = texture(color_ramp, vec2(1.0 - UV.y, 0)).rgb ;
	// [木兰草原]
	ALBEDO = mix(ALBEDO, ALBEDO * dry_color * 1.45, patch_dry) * tint * blade_var;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

// [木兰草原]
void light() {
	float lit = ghibli_lit(dot(NORMAL, LIGHT), 0.3, ATTENUATION);
	if (LIGHT_IS_DIRECTIONAL) {
		lit *= ghibli_cloud(root_w, TIME);
		// 逆光：草尖透亮
		float trans = pow(clamp(-dot(VIEW, LIGHT), 0.0, 1.0), 3.0) * tip * 0.4 * lit;
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * (ghibli_diffuse(lit) + vec3(trans));
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit;
	}
}