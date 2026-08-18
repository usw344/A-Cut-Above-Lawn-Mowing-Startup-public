shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 valley_color : source_color = vec3(0.13, 0.17, 0.15);
uniform vec3 peak_color : source_color = vec3(0.30, 0.34, 0.32);
uniform vec3 sun_color : source_color = vec3(0.42, 0.36, 0.27);
uniform float mountain_height : hint_range(1.0, 30.0, 0.1) = 16.0;
uniform float plane_depth : hint_range(10.0, 100.0, 0.5) = 60.0;
uniform float noise_scale : hint_range(0.005, 0.2, 0.001) = 0.028;
uniform vec2 noise_offset = vec2(0.0);
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 1.0;

varying float generated_height;
varying float ridge_detail;

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

float fbm(vec2 point) {
	float result = value_noise(point) * 0.54;
	result += value_noise(point * 2.03 + 17.2) * 0.29;
	result += value_noise(point * 4.11 - 8.7) * 0.12;
	result += value_noise(point * 8.07 + 31.4) * 0.05;
	return result;
}

float mountain_shape(vec2 point) {
	vec2 sample_point = point * noise_scale + noise_offset;
	float broad = fbm(sample_point);
	float ridge_source = fbm(sample_point * vec2(0.72, 1.45) + vec2(9.3, -4.7));
	float ridge = 1.0 - abs(ridge_source * 2.0 - 1.0);
	ridge = ridge * ridge;
	float depth = clamp((-point.y + plane_depth * 0.5) / plane_depth, 0.0, 1.0);
	float depth_profile = smoothstep(0.0, 0.76, depth);
	// A narrow noise-shaped crest across the rear half creates a readable
	// mountain skyline while the same basic plane still supplies its slopes.
	float crest_source = fbm(vec2(sample_point.x * 1.28 + 27.4, noise_offset.y * 1.91));
	float crest = pow(1.0 - abs(crest_source * 2.0 - 1.0), 2.2);
	float crest_band = 1.0 - smoothstep(0.0, 0.29, abs(depth - 0.76));
	float rolling_height = (broad * 0.58 + ridge * 0.42) * mix(0.12, 0.72, depth_profile);
	return (rolling_height + crest * crest_band * 0.62) * mountain_height;
}

void vertex() {
	float height = mountain_shape(VERTEX.xz);
	VERTEX.y += height;
	float sample_distance = 0.55;
	float left_height = mountain_shape(VERTEX.xz - vec2(sample_distance, 0.0));
	float right_height = mountain_shape(VERTEX.xz + vec2(sample_distance, 0.0));
	float back_height = mountain_shape(VERTEX.xz - vec2(0.0, sample_distance));
	float front_height = mountain_shape(VERTEX.xz + vec2(0.0, sample_distance));
	NORMAL = normalize(vec3(
		left_height - right_height,
		2.0 * sample_distance,
		back_height - front_height
	));
	generated_height = height / max(mountain_height, 0.001);
	ridge_detail = value_noise(VERTEX.xz * noise_scale * 5.7 + noise_offset * 2.3);
}

void fragment() {
	float elevation = smoothstep(0.12, 0.86, generated_height);
	vec3 color = mix(valley_color, peak_color, elevation);
	float sunward_patch = smoothstep(0.62, 0.95, ridge_detail) * (1.0 - elevation * 0.35);
	color = mix(color, sun_color, sunward_patch * 0.22);
	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
