shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled, world_vertex_coords;

uniform sampler2D texture_albedo : source_color;

uniform float wind_speed = 1.2;
uniform float wind_strength = 0.06;
uniform float wind_scale = 6.0;

void vertex() {
	// Paint vertex color red = 0 on trunk/branches, red = 1 on leaf tips.
	float strength = COLOR.r * wind_strength;

	// A few slightly different waves so motion doesn't look mechanical.
	float t = TIME * wind_speed;

	VERTEX.x += sin(VERTEX.z * wind_scale + t) * strength;
	VERTEX.z += cos(VERTEX.x * wind_scale * 0.8 + t * 1.1) * strength;
	VERTEX.y += sin(VERTEX.x * wind_scale * 0.5 + t * 0.7) * strength * 0.25;
}

void fragment() {
	vec4 albedo_tex = texture(texture_albedo, UV);

	ALBEDO = albedo_tex.rgb;
	ALPHA = albedo_tex.a;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
}