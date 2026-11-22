// Lens finishing pass on top of the tonemapped frame: chromatic aberration,
// vignette, film grain, anamorphic letterbox, fade to black.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration = 0.0025;
uniform float vignette = 0.38;
uniform float grain = 0.03;
uniform float letterbox = 0.0; // bar height as a fraction of the screen, each side
uniform float fade = 0.0; // 0 = picture, 1 = black

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec2 shift = d * aberration * r2 * 4.0;
	vec3 col = vec3(
			texture(screen_tex, uv - shift).r,
			texture(screen_tex, uv).g,
			texture(screen_tex, uv + shift).b);
	float v = smoothstep(0.85, 0.15, length(d * vec2(1.0, 0.75)));
	col *= mix(1.0, v, vignette);
	float n = hash(FRAGCOORD.xy + fract(TIME * 7.13) * 1000.0) - 0.5;
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col += n * grain * (1.0 - luma * 0.6);
	col *= 1.0 - fade;
	if (uv.y < letterbox || uv.y > 1.0 - letterbox) {
		col = vec3(0.0);
	}
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
