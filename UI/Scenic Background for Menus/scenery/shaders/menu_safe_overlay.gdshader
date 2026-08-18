shader_type canvas_item;
render_mode unshaded;

uniform vec3 shadow_tint : source_color = vec3(0.018, 0.035, 0.026);
uniform float left_darken : hint_range(0.0, 0.8, 0.01) = 0.34;
uniform float edge_vignette : hint_range(0.0, 0.5, 0.01) = 0.12;

void fragment() {
	float left_mask = 1.0 - smoothstep(0.02, 0.64, UV.x);
	vec2 centred = UV * 2.0 - 1.0;
	float edge_mask = smoothstep(0.62, 1.18, length(centred * vec2(0.82, 1.0)));
	float opacity = left_mask * left_darken + edge_mask * edge_vignette;
	COLOR = vec4(shadow_tint, clamp(opacity, 0.0, 0.7));
}
