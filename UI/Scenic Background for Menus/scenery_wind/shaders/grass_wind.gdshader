shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_schlick_ggx;

// Names intentionally match tree_wind.gdshader so one lightweight controller
// keeps both vegetation types moving with the same direction and speed.
uniform vec2 wind_direction = vec2(1.0, 0.25);
uniform float wind_speed : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float wind_strength : hint_range(0.0, 0.4, 0.001) = 0.11;
uniform float gust_strength : hint_range(0.0, 0.2, 0.001) = 0.035;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D occlusion_texture : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.01) = 0.33;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.85;
uniform float wind_base_height = 0.02;
uniform float wind_top_height = 2.0;

varying float grass_color_variation;
varying float grass_height_fraction;

float hash_position(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	grass_color_variation = INSTANCE_CUSTOM.x;
	vec2 direction_2d = wind_direction;
	if (dot(direction_2d, direction_2d) < 0.0001) {
		direction_2d = vec2(1.0, 0.0);
	}
	direction_2d = normalize(direction_2d);

	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase_seed = hash_position(instance_origin.xz + vec2(2.13, 8.79));
	float phase = phase_seed * 6.28318530718;
	float instance_amplitude = mix(0.82, 1.18, hash_position(instance_origin.zx + vec2(3.71, 1.97)));
	float instance_speed = mix(0.90, 1.10, hash_position(instance_origin.xz + vec2(6.43, 5.19)));

	float height_fraction = clamp(
		(VERTEX.y - wind_base_height) / max(wind_top_height - wind_base_height, 0.001),
		0.0,
		1.0
	);
	grass_height_fraction = height_fraction;
	float flexibility = pow(smoothstep(0.0, 1.0, height_fraction), 1.45);
	float wind_time = TIME * wind_speed * instance_speed;
	float spatial_phase = dot(world_position.xz, vec2(0.71, 0.93));
	float sway = (
		sin(wind_time * 1.12 + spatial_phase * 0.38 + phase)
		+ 0.32 * sin(wind_time * 1.83 + spatial_phase * 0.71 + phase * 1.47)
	) / 1.32;
	float gust = pow(0.5 + 0.5 * sin(wind_time * 0.31 + phase * 0.53), 3.0);
	float bend = (sway * wind_strength + gust * gust_strength) * instance_amplitude;

	vec3 world_wind = vec3(direction_2d.x, 0.0, direction_2d.y);
	vec3 local_wind = inverse(mat3(MODEL_MATRIX)) * world_wind;
	local_wind.y = 0.0;
	local_wind = normalize(local_wind);
	VERTEX += local_wind * bend * flexibility;
}

void fragment() {
	vec4 base_color = texture(albedo_texture, UV);
	float luminance = dot(base_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 natural_color = mix(vec3(luminance), base_color.rgb, 0.76);
	vec3 cool_tint = vec3(0.78, 0.91, 0.72);
	vec3 warm_tint = vec3(0.93, 0.86, 0.66);
	natural_color *= mix(cool_tint, warm_tint, grass_color_variation);
	natural_color *= mix(0.82, 1.04, smoothstep(0.0, 1.0, grass_height_fraction));
	ALBEDO = natural_color;
	ALPHA = base_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.18;
	AO = texture(occlusion_texture, UV).r;
	AO_LIGHT_AFFECT = 0.65;
	// Cheaper than full SSS across thousands of alpha-cut instances, while
	// still allowing sunlit blade edges to feel thin and organic.
	BACKLIGHT = natural_color * 0.065 * smoothstep(0.2, 1.0, grass_height_fraction);
}
