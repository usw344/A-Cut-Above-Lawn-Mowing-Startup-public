shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec2 wind_direction = vec2(1.0, 0.25);
uniform float wind_speed : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float wind_strength : hint_range(0.0, 0.25, 0.001) = 0.055;
uniform float gust_strength : hint_range(0.0, 0.15, 0.001) = 0.025;

uniform vec3 low_color : source_color = vec3(0.05, 0.16, 0.065);
uniform vec3 high_color : source_color = vec3(0.23, 0.39, 0.12);
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.88;
uniform float foliage_surface : hint_range(0.0, 1.0, 1.0) = 1.0;
uniform float surface_noise_strength : hint_range(0.0, 0.25, 0.005) = 0.1;
uniform float subsurface_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform vec3 subsurface_color : source_color = vec3(0.42, 0.62, 0.18);

varying vec4 authored_mask;
varying vec3 tree_world_position;

float hash_position(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash_position_3d(vec3 value) {
	return fract(sin(dot(value, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float value_noise_3d(vec3 point) {
	vec3 cell = floor(point);
	vec3 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float n000 = hash_position_3d(cell + vec3(0.0, 0.0, 0.0));
	float n100 = hash_position_3d(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash_position_3d(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash_position_3d(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash_position_3d(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash_position_3d(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash_position_3d(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash_position_3d(cell + vec3(1.0, 1.0, 1.0));
	float near_z0 = mix(mix(n000, n100, fraction.x), mix(n010, n110, fraction.x), fraction.y);
	float near_z1 = mix(mix(n001, n101, fraction.x), mix(n011, n111, fraction.x), fraction.y);
	return mix(near_z0, near_z1, fraction.z);
}

void vertex() {
	authored_mask = COLOR;
	vec2 direction_2d = wind_direction;
	if (dot(direction_2d, direction_2d) < 0.0001) {
		direction_2d = vec2(1.0, 0.0);
	}
	direction_2d = normalize(direction_2d);

	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	float phase = hash_position(instance_origin.xz + vec2(0.173, 0.619)) * 6.28318530718;
	float amplitude = mix(0.84, 1.16, hash_position(instance_origin.zx + vec2(4.17, 9.31)));
	float speed = mix(0.91, 1.09, hash_position(instance_origin.xz + vec2(7.73, 2.57)));
	float static_surface_noise = value_noise_3d(VERTEX * 1.42 + phase * 2.7);
	VERTEX += NORMAL * ((static_surface_noise - 0.5) * 2.0 * surface_noise_strength * authored_mask.b);
	float wind_time = TIME * wind_speed * speed;
	float broad_sway = (
		sin(wind_time * 0.82 + phase)
		+ 0.34 * sin(wind_time * 1.29 + phase * 1.71)
	) / 1.34;
	float gust = pow(0.5 + 0.5 * sin(wind_time * 0.27 + phase * 0.43), 3.0);
	vec3 original_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float detail = sin(wind_time * 1.61 + dot(original_world_position, vec3(0.79, 0.37, 1.09)) + phase);
	float turbulence = value_noise_3d(
		original_world_position * 0.34
		+ vec3(wind_time * 0.13, phase, -wind_time * 0.09)
	) - 0.5;
	float bend = (broad_sway * wind_strength + gust * gust_strength) * amplitude;
	bend += detail * wind_strength * 0.12 * authored_mask.b;
	bend += turbulence * gust_strength * 0.32 * authored_mask.b;

	vec3 world_wind = vec3(direction_2d.x, 0.0, direction_2d.y);
	vec3 local_wind = inverse(mat3(MODEL_MATRIX)) * world_wind;
	local_wind.y = 0.0;
	local_wind = normalize(local_wind);
	VERTEX += local_wind * bend * authored_mask.r;
	tree_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float variation = clamp(authored_mask.g, 0.0, 1.0);
	vec3 surface_color = mix(low_color, high_color, variation);
	float broad_dapple = 0.5 + 0.5 * sin(
		tree_world_position.x * 1.37
		+ tree_world_position.y * 0.83
		+ tree_world_position.z * 1.11
	);
	float vertical_light = smoothstep(-0.3, 7.5, tree_world_position.y);
	surface_color *= mix(0.91, 1.055, broad_dapple * foliage_surface);
	surface_color *= mix(0.94, 1.04, vertical_light);
	ALBEDO = surface_color;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = mix(0.16, 0.24, foliage_surface);
	AO = mix(0.78, 1.0, vertical_light);
	AO_LIGHT_AFFECT = 0.38;
	SSS_STRENGTH = subsurface_strength * foliage_surface;
	SSS_TRANSMITTANCE_COLOR = vec4(subsurface_color, 1.0);
	SSS_TRANSMITTANCE_DEPTH = mix(0.05, 0.38, foliage_surface);
	SSS_TRANSMITTANCE_BOOST = 0.12 * foliage_surface;
	BACKLIGHT = surface_color * 0.08 * foliage_surface;
}
