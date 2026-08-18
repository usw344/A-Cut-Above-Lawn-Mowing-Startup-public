shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Shared breeze values. SceneryWindController writes these to every vegetation
// material so trees and grass respond to one conceptual wind field.
uniform vec2 wind_direction = vec2(1.0, 0.25);
uniform float wind_speed : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float wind_strength : hint_range(0.0, 0.25, 0.001) = 0.055;
uniform float gust_strength : hint_range(0.0, 0.15, 0.001) = 0.025;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 color_tint : source_color = vec3(0.90, 0.93, 0.84);
uniform float color_saturation : hint_range(0.0, 1.25, 0.01) = 0.72;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.84;

// Asset-specific, local-space mask bounds. The supplied tree meshes have no
// vertex colour mask and combine trunk/canopy in one surface, so height keeps
// the root still while radial distance gives branch tips more freedom than the
// upper trunk.
uniform float wind_base_height = 0.10;
uniform float wind_top_height = 4.0;
uniform float canopy_radius = 2.0;
uniform float height_mask_power : hint_range(0.5, 4.0, 0.05) = 1.8;
uniform float trunk_motion_ratio : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float wind_response : hint_range(0.0, 2.0, 0.01) = 1.0;

varying float tree_height_fraction;

float hash_position(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	vec2 direction_2d = wind_direction;
	if (dot(direction_2d, direction_2d) < 0.0001) {
		direction_2d = vec2(1.0, 0.0);
	}
	direction_2d = normalize(direction_2d);

	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase_seed = hash_position(instance_origin.xz + vec2(0.173, 0.619));
	float phase = phase_seed * 6.28318530718;
	float instance_amplitude = mix(0.86, 1.14, hash_position(instance_origin.zx + vec2(4.17, 9.31)));
	float instance_speed = mix(0.92, 1.08, hash_position(instance_origin.xz + vec2(7.73, 2.57)));

	float safe_height_span = max(wind_top_height - wind_base_height, 0.001);
	float height_fraction = clamp((VERTEX.y - wind_base_height) / safe_height_span, 0.0, 1.0);
	tree_height_fraction = height_fraction;
	float height_mask = pow(smoothstep(0.0, 1.0, height_fraction), height_mask_power);
	float radial_fraction = clamp(length(VERTEX.xz) / max(canopy_radius, 0.001), 0.0, 1.0);
	float extremity_mask = smoothstep(0.08, 1.0, radial_fraction);
	float flexibility = height_mask * mix(trunk_motion_ratio, 1.0, extremity_mask);

	float wind_time = TIME * wind_speed * instance_speed;
	float broad_sway = (
		sin(wind_time * 0.82 + phase)
		+ 0.38 * sin(wind_time * 1.31 + phase * 1.73)
	) / 1.38;
	float slow_gust = pow(
		0.5 + 0.5 * sin(wind_time * 0.29 + phase * 0.41),
		3.0
	);
	float branch_detail = sin(
		wind_time * 1.67
		+ dot(world_position, vec3(0.83, 0.41, 1.17))
		+ phase * 1.23
	) * extremity_mask;

	float bend = (
		broad_sway * wind_strength
		+ slow_gust * gust_strength
		+ branch_detail * wind_strength * 0.16
	) * instance_amplitude * wind_response;

	// Convert the common world-space breeze into this instance's local space.
	// This keeps differently rotated trees leaning in the same world direction.
	vec3 world_wind = vec3(direction_2d.x, 0.0, direction_2d.y);
	vec3 local_wind = inverse(mat3(MODEL_MATRIX)) * world_wind;
	local_wind.y = 0.0;
	local_wind = normalize(local_wind);
	vec3 local_crosswind = vec3(-local_wind.z, 0.0, local_wind.x);

	VERTEX += local_wind * bend * flexibility;
	VERTEX += local_crosswind * branch_detail * wind_strength * 0.035 * flexibility;
}

void fragment() {
	vec4 base_color = texture(albedo_texture, UV);
	float luminance = dot(base_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded_color = mix(vec3(luminance), base_color.rgb, color_saturation) * color_tint;
	graded_color *= mix(0.91, 1.035, smoothstep(0.0, 1.0, tree_height_fraction));
	ALBEDO = graded_color;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.22;
}
