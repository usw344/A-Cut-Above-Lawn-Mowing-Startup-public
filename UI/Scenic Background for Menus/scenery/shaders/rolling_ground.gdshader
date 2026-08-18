shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 low_color : source_color = vec3(0.115, 0.072, 0.041);
uniform vec3 high_color : source_color = vec3(0.255, 0.170, 0.095);
uniform vec3 dry_color : source_color = vec3(0.360, 0.255, 0.140);
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.985;

varying vec3 terrain_world_position;
varying float terrain_height_value;

float terrain_height(vec2 point) {
	float local_roll = sin(point.x * 0.105 + 0.65) * 0.24;
	local_roll += cos(point.y * 0.085 - 0.55) * 0.22;
	float crossing_roll = sin((point.x + point.y) * 0.045) * 0.38;
	crossing_roll += cos((point.x - point.y) * 0.061) * 0.19;
	float distant_rise = smoothstep(3.0, 32.0, -point.y) * 1.4;
	return local_roll + crossing_roll + distant_rise;
}

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
}

float soil_noise(vec2 point) {
	float result = value_noise(point) * 0.58;
	result += value_noise(point * 2.07 + 13.4) * 0.29;
	result += value_noise(point * 4.13 - 7.1) * 0.13;
	return result;
}

float surface_relief(vec2 point) {
	float broad_relief = (soil_noise(point * 0.45) - 0.5) * 0.12;
	float fine_relief = (value_noise(point * 1.2 + 19.7) - 0.5) * 0.035;
	return broad_relief + fine_relief;
}

float total_terrain_height(vec2 point) {
	return terrain_height(point) + surface_relief(point);
}

void vertex() {
	VERTEX.y += total_terrain_height(VERTEX.xz);

	float sample_distance = 0.18;
	float left_height = total_terrain_height(VERTEX.xz - vec2(sample_distance, 0.0));
	float right_height = total_terrain_height(VERTEX.xz + vec2(sample_distance, 0.0));
	float back_height = total_terrain_height(VERTEX.xz - vec2(0.0, sample_distance));
	float front_height = total_terrain_height(VERTEX.xz + vec2(0.0, sample_distance));
	NORMAL = normalize(vec3(
		left_height - right_height,
		2.0 * sample_distance,
		back_height - front_height
	));

	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_height_value = VERTEX.y;
}

void fragment() {
	float broad_soil = soil_noise(terrain_world_position.xz * 0.075);
	float fine_soil = value_noise(terrain_world_position.xz * 0.82 + 19.7);
	float compacted = smoothstep(0.28, 0.82, broad_soil + terrain_height_value * 0.018);
	vec3 soil_color = mix(low_color, high_color, compacted);
	float dry_patch = smoothstep(0.7, 0.94, broad_soil * 0.72 + fine_soil * 0.28);
	soil_color = mix(soil_color, dry_color, dry_patch * 0.42);
	float mineral_fleck = smoothstep(0.965, 0.995, value_noise(terrain_world_position.xz * 3.7));
	ALBEDO = soil_color + mineral_fleck * 0.025;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
