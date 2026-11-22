// Still forest pond. Opaque on purpose: Godot's SSR only applies to opaque surfaces,
// so the trees, sky and light shafts are mirrored in real screen-space reflections
// (with a ReflectionProbe catching what leaves the screen).
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D wave_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.010, 0.016, 0.012);
uniform float normal_strength = 0.25;
uniform float roughness = 0.015;

void fragment() {
	vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 n1 = texture(wave_a, p * 0.045 + TIME * vec2(0.006, 0.004)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(wave_b, p * 0.13 - TIME * vec2(0.004, 0.009)).rgb * 2.0 - 1.0;
	// Whiteout blend of the two detail normals.
	vec3 n = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;
	ALBEDO = deep_color;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = roughness;
}
