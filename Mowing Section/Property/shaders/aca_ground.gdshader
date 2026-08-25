shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// THE GROUND UNDER THE GRASS.
//
// It is not soil. A lawn seen from a mower is thatch and shadow between the
// blades, so the default here is a DEEP GREEN, and bare earth only appears
// where the land is genuinely too steep to hold turf. Anything else makes a
// mown stripe read as a trench of dirt.
//
// Three jobs:
//   1. give the grass something coherent to sit on at every distance;
//   2. take over entirely once the grass instances have faded out;
//   3. respond to the lawn cut mask, so a cut stripe is a change in the whole
//      surface rather than in the blades alone.

group_uniforms Lawn;
// R cut amount, G cut heading (0..1 over a half turn), B spare, A mowable.
uniform sampler2D lawn_mask : hint_default_transparent, filter_linear, repeat_disable;
uniform vec2 lawn_centre = vec2(0.0, 0.0);
uniform float lawn_size = 96.0;
uniform float lawn_half_extent = 48.0;

group_uniforms Colour;
uniform vec3 lawn_deep : source_color = vec3(0.100, 0.198, 0.071);
uniform vec3 lawn_light : source_color = vec3(0.184, 0.332, 0.122);
uniform vec3 cut_colour : source_color = vec3(0.280, 0.458, 0.168);
uniform vec3 meadow_colour : source_color = vec3(0.148, 0.250, 0.101);
uniform vec3 dry_colour : source_color = vec3(0.300, 0.290, 0.128);
uniform vec3 soil_colour : source_color = vec3(0.190, 0.145, 0.098);
uniform vec3 distant_colour : source_color = vec3(0.152, 0.226, 0.130);
uniform float dryness : hint_range(0.0, 1.0) = 0.24;
uniform float colour_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float terrain_seed = 0.0;

group_uniforms Shore;
// A SHORELINE IS NOT A LINE, IT IS A BAND OF DAMP GROUND. The one thing that
// gave the pond away was that the grass simply stopped and the water simply
// started, with nothing in between that had been wet recently.
//
// This is driven by HEIGHT rather than by distance, which is why it follows an
// irregular outline exactly without the shader knowing anything about the
// pond's shape: ground within `shore_wet_band` above the water line is damp,
// ground below it is bed. The rectangle only scopes the effect to the feature,
// so a dip somewhere else on the property does not turn into mud.
uniform vec2 shore_centre = vec2(0.0, 0.0);
// Half extents. Zero disables the whole term, which is what a property with no
// pond gets.
uniform vec2 shore_extent = vec2(0.0, 0.0);
uniform float shore_water_y = 0.0;
uniform float shore_wet_band : hint_range(0.05, 6.0) = 0.85;
uniform vec3 shore_damp : source_color = vec3(0.206, 0.196, 0.132);
uniform vec3 shore_bed : source_color = vec3(0.292, 0.256, 0.170);

group_uniforms Surface;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.94;
// Where turf gives up. Slope is 1 - normal.y, so 0.34 is roughly twenty degrees.
uniform float soil_slope_start : hint_range(0.0, 1.0) = 0.30;
uniform float soil_slope_end : hint_range(0.0, 1.0) = 0.62;
// How far away the ground stops being read as individual grass and becomes a
// single landscape tone.
uniform float distance_blend_start = 130.0;
uniform float distance_blend_end = 620.0;
uniform float stripe_strength : hint_range(0.0, 0.5) = 0.10;

varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.77));
	p += dot(p, p + 47.13);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Two octaves is enough for macro variation and keeps the ground from looking
// like static. A third octave reads as noise, not as land.
float macro_noise(vec2 p) {
	return value_noise(p) * 0.66 + value_noise(p * 2.13 + vec2(9.7, 4.3)) * 0.34;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 seed_offset = vec2(terrain_seed, terrain_seed * 1.7);

	float view_distance = length(world_position
		- (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);

	// ------------------------------------------------------------ lawn state
	vec2 lawn_uv = (p - lawn_centre) / max(lawn_size, 1.0) + vec2(0.5);
	// A little positional wobble so the mask's own cell edges never show as a
	// straight line on the ground.
	vec2 wobble = vec2(
		macro_noise(p * 0.85 + seed_offset) - 0.5,
		macro_noise(p * 0.85 + seed_offset + vec2(31.7, 12.9)) - 0.5
	) * (1.6 / max(lawn_size, 1.0));
	vec4 mask = vec4(0.0);
	if (lawn_uv.x > 0.0 && lawn_uv.x < 1.0 && lawn_uv.y > 0.0 && lawn_uv.y < 1.0) {
		mask = texture(lawn_mask, lawn_uv + wobble);
	}
	float cut = mask.r;

	// ------------------------------------------------------------ base colour
	float macro = macro_noise(p * 0.017 + seed_offset);
	float mid = macro_noise(p * 0.075 + seed_offset * 1.3);
	float fine = value_noise(p * 0.42 + seed_offset * 0.6);

	// Inside the lawn rectangle the ground is kept turf; outside it drifts to
	// rougher meadow. The transition is WIDE and noisy on purpose: a property
	// seen from above should read as tended ground fading into rough ground,
	// not as a bright rectangle laid on a dark field.
	vec2 edge = abs(p - lawn_centre) - vec2(lawn_half_extent);
	float outside = max(edge.x, edge.y)
		+ (macro - 0.5) * 11.0
		+ (mid - 0.5) * 4.0;
	float lawn_weight = 1.0 - smoothstep(-7.0, 17.0, outside);

	vec3 turf = mix(lawn_deep, lawn_light, macro * 0.72 + mid * 0.28);
	vec3 wild = mix(meadow_colour, lawn_light, mid * 0.5);
	wild = mix(wild, dry_colour, clamp(dryness * (0.35 + macro * 0.9), 0.0, 0.85));
	vec3 base = mix(wild, turf, lawn_weight);

	// A seeded drift, so two properties are not the same green.
	base *= mix(vec3(0.94, 1.0, 0.92), vec3(1.06, 1.0, 0.90), colour_bias * 0.5 + 0.5);
	base *= mix(0.93, 1.07, fine);

	// WARM AND COOL PATCHES, not just light and dark ones. Ground that varies
	// only in brightness reads as one green under a cloud; a drift in HUE over
	// tens of units is what a real field does, and because it rides the same
	// slow noise the tone does, it lands as ground rather than as speckle.
	vec3 warm_cast = vec3(1.075, 1.00, 0.865);
	vec3 cool_cast = vec3(0.905, 1.00, 1.055);
	base *= mix(vec3(1.0), mix(cool_cast, warm_cast, macro * 0.7 + mid * 0.3), 0.62);

	// ------------------------------------------------------------- fresh cut
	// A cut lawn is BRIGHTER and slightly warmer, never darker. The mowed
	// surface is still turf.
	vec3 cut_tone = mix(cut_colour, lawn_light, mid * 0.4);
	base = mix(base, cut_tone, cut * 0.85 * lawn_weight);

	// Stripes, matching the grass exactly: the ground under a pass laid away
	// from the viewer lightens with it, so the two never disagree.
	float heading = mask.g * 6.28318530718;
	vec2 stripe_dir = vec2(cos(heading), sin(heading));
	vec3 to_camera = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - world_position;
	vec2 view_dir = normalize(length(to_camera.xz) > 0.001
		? to_camera.xz : vec2(0.0, 1.0));
	// Stripes hold through the whole of a normal view and give out well beyond
	// it, so a lawn seen from the far side of the property still shows its
	// passes and one seen from half a kilometre settles into a single mown
	// tone rather than into a band a pixel wide.
	float stripe_near = 1.0 - smoothstep(190.0, 460.0, view_distance);
	base *= 1.0 + dot(stripe_dir, view_dir)
		* stripe_strength * cut * lawn_weight * stripe_near;

	// ------------------------------------------------------------------ soil
	// Only genuinely steep ground shows earth, and even then it is a warm dry
	// tone rather than something black.
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float bare = smoothstep(soil_slope_start, soil_slope_end, slope);
	bare *= 1.0 - lawn_weight * 0.85;
	base = mix(base, mix(soil_colour, dry_colour, fine * 0.4), bare * 0.8);

	// ----------------------------------------------------------- the shoreline
	if (shore_extent.x > 0.001 && shore_extent.y > 0.001) {
		vec2 from_centre = abs(p - shore_centre) / shore_extent;
		float inside = 1.0 - smoothstep(0.80, 1.06, max(from_centre.x, from_centre.y));
		float above = world_position.y - shore_water_y;
		float damp = smoothstep(shore_wet_band, -0.05, above) * inside;
		// Silt under the water, damp earth above it, and the same fine noise
		// the turf uses so the band is not a flat colour.
		vec3 bank = mix(shore_damp, shore_bed, smoothstep(0.05, -0.7, above));
		bank *= mix(0.86, 1.16, fine);
		bank = mix(bank, mix(bank, soil_colour, 0.35), slope);
		base = mix(base, bank, damp * 0.66);
	}

	// -------------------------------------------------------------- distance
	// Far ground loses the fine detail and settles into one landscape tone, so
	// the horizon does not shimmer and the grass fade has somewhere to land.
	float far = smoothstep(distance_blend_start, distance_blend_end, view_distance);
	vec3 far_tone = mix(distant_colour, dry_colour, dryness * 0.3 + macro * 0.15);
	base = mix(base, far_tone, far * 0.75);

	ALBEDO = base;
	ROUGHNESS = mix(roughness_value, roughness_value * 0.86, cut * lawn_weight);
	METALLIC = 0.0;
	SPECULAR = 0.16;
	NORMAL_MAP_DEPTH = 1.0;
}
