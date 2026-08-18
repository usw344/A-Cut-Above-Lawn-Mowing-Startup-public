shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 dark_color : source_color = vec3(0.13, 0.12, 0.10);
uniform vec3 light_color : source_color = vec3(0.34, 0.30, 0.23);
uniform vec3 mineral_color : source_color = vec3(0.42, 0.37, 0.29);
uniform float distortion_strength : hint_range(0.0, 0.5, 0.005) = 0.19;
uniform float noise_scale : hint_range(0.2, 6.0, 0.05) = 1.65;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.97;

varying float rock_noise;
varying float rock_instance_variation;
varying vec3 rock_world_position;

float hash31(vec3 point) {
	return fract(sin(dot(point, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float value_noise_3d(vec3 point) {
	vec3 cell = floor(point);
	vec3 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float n000 = hash31(cell + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(cell + vec3(1.0, 1.0, 1.0));
	float near_y0 = mix(mix(n000, n100, fraction.x), mix(n010, n110, fraction.x), fraction.y);
	float near_y1 = mix(mix(n001, n101, fraction.x), mix(n011, n111, fraction.x), fraction.y);
	return mix(near_y0, near_y1, fraction.z);
}

float rock_fbm(vec3 point) {
	float result = value_noise_3d(point) * 0.62;
	result += value_noise_3d(point * 2.07 + 11.3) * 0.27;
	result += value_noise_3d(point * 4.13 - 5.7) * 0.11;
	return result;
}

void vertex() {
	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	float instance_seed = hash31(instance_origin * 0.173 + vec3(3.1, 7.7, 1.9));
	vec3 radial_direction = normalize(VERTEX);
	float noise = rock_fbm(VERTEX * noise_scale + instance_seed * 17.0);
	float layered_chip = sin((VERTEX.y + instance_seed) * 7.0) * 0.035;
	VERTEX += radial_direction * ((noise - 0.5) * 2.0 * distortion_strength + layered_chip);
	rock_noise = noise;
	rock_instance_variation = instance_seed;
	rock_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float broad_color = clamp(rock_noise * 0.72 + rock_instance_variation * 0.28, 0.0, 1.0);
	vec3 color = mix(dark_color, light_color, broad_color);
	float mineral_patch = smoothstep(0.78, 0.96, rock_noise) * (
		0.5 + 0.5 * sin(dot(rock_world_position, vec3(2.7, 3.1, 2.2)))
	);
	ALBEDO = mix(color, mineral_color, mineral_patch * 0.24);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.14;
}
