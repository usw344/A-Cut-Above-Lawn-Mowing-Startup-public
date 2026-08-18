shader_type canvas_item;

uniform vec4 tint_colour : source_color = vec4(0.008, 0.027, 0.020, 0.74);
uniform float fade_end : hint_range(0.25, 0.85, 0.01) = 0.58;

void fragment() {
	float strength = 1.0 - smoothstep(0.0, fade_end, UV.x);
	COLOR = vec4(tint_colour.rgb, tint_colour.a * strength);
}
