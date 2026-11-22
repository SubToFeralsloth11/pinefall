// Opaque foliage: Poly Haven ARM textures, translucent backlighting, wind sway + leaf flutter.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, world_vertex_coords;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Poly Haven ARM packing: R = ambient occlusion, G = roughness, B = metallic.
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 backlight_tint : source_color = vec3(0.55, 0.6, 0.25);
uniform float specular_amount = 0.3;
uniform float sway_height = 1.0; // metres above the instance origin where sway reaches full strength
uniform float wind_strength = 0.05; // metres of displacement at sway_height
uniform float flutter = 0.01;
uniform float wind_speed = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp((VERTEX.y - origin.y) / sway_height, 0.0, 1.0);
	h *= h;
	float t = TIME * wind_speed;
	float phase = dot(origin.xz, vec2(0.071, 0.113));
	// Slow gusts travelling across the forest + a faster secondary sway.
	float gust = sin(t * 0.7 + origin.x * 0.05 + origin.z * 0.03) * 0.5 + 0.5;
	vec2 sway = vec2(sin(t + phase) + 0.35 * sin(t * 2.7 + phase * 3.1),
			0.6 * cos(t * 0.83 + phase * 1.7));
	sway *= (0.45 + gust);
	float f = sin(t * 7.0 + dot(VERTEX, vec3(4.1, 3.3, 3.7)));
	VERTEX += vec3(sway.x, 0.0, sway.y) * wind_strength * h + NORMAL * (f * flutter * h);
}

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb * tint;
	vec3 arm = texture(arm_tex, UV).rgb;
	ALBEDO = albedo;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = arm.g;
	METALLIC = 0.0;
	SPECULAR = specular_amount;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	BACKLIGHT = albedo * backlight_tint * 2.0;
}
