shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// EXPERIMENTAL pond water. Project-owned, and deliberately free of external
// assets: every wave and every normal here is arithmetic, so there is no
// texture to license and nothing to copy alongside the shader.
//
// ---------------------------------------------------------------------------
// WHAT THIS IS NOT
// ---------------------------------------------------------------------------
// No FFT, no simulation, no per-vertex CPU update, no physics. This is a SMALL
// POND. Four sine waves and two noise samples buy everything a small pond
// needs, and cost the same whatever the weather is doing.
//
// ---------------------------------------------------------------------------
// THE SHORELINE
// ---------------------------------------------------------------------------
// The edge is where cheap water gives itself away: a hard line where the plane
// intersects the bank. `DEPTH_TEXTURE` gives the distance to whatever is behind
// the water, so the surface can fade out as the bed rises to meet it. That one
// term does more for believability than the waves do.

uniform vec4 shallow_color : source_color = vec4(0.29, 0.47, 0.42, 1.0);
uniform vec4 deep_color : source_color = vec4(0.07, 0.19, 0.24, 1.0);
// How quickly the colour reaches `deep_color`, in world units of depth.
uniform float depth_falloff : hint_range(0.05, 8.0) = 1.6;
// Distance over which the surface fades out as it meets the bed.
uniform float shore_fade : hint_range(0.01, 4.0) = 0.55;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.90;

uniform float wave_speed : hint_range(0.0, 4.0) = 0.55;
uniform float wave_height : hint_range(0.0, 0.5) = 0.035;
uniform float wave_scale : hint_range(0.05, 8.0) = 0.42;
// Strength of the small-scale normal detail between the big waves.
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.22;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.06;
uniform float fresnel_power : hint_range(0.5, 8.0) = 4.0;
uniform vec4 fresnel_color : source_color = vec4(0.72, 0.82, 0.92, 1.0);

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_position;

// ---------------------------------------------------------------------------
// Value noise. Cheap, seamless enough for ripples, and no texture needed.
// ---------------------------------------------------------------------------
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Four crossing sine waves.
//
// TUNED, after the first render came out as PLAID. Two things caused that: the
// directions were close to the axes, so the crests formed a grid rather than a
// weave, and the high-frequency terms carried far too much of the amplitude.
// The directions below are deliberately off-axis and mutually irrational, the
// amplitude falls away sharply with frequency, and the speeds are not simple
// multiples of each other so the pattern does not resolve into a beat.
float wave_field(vec2 p, float t) {
	float w = 0.0;
	w += sin(dot(p, vec2(0.94, 0.34)) * 0.85 + t * 0.90) * 0.52;
	w += sin(dot(p, vec2(-0.42, 0.91)) * 1.33 - t * 0.71) * 0.27;
	w += sin(dot(p, vec2(0.61, -0.79)) * 2.05 + t * 1.23) * 0.13;
	w += sin(dot(p, vec2(-0.87, -0.49)) * 3.11 - t * 1.51) * 0.07;
	return w;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	VERTEX.y += wave_field(world_position.xz * wave_scale, t) * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = world_position.xz * wave_scale;

	// Normals from the analytic gradient of the same field the vertices use,
	// plus a finer noise layer for the detail between the big waves. Sampling
	// the field rather than differencing the mesh keeps the ripples independent
	// of how finely the plane happens to be subdivided.
	float e = 0.12;
	float hx = wave_field(p + vec2(e, 0.0), t) - wave_field(p - vec2(e, 0.0), t);
	float hz = wave_field(p + vec2(0.0, e), t) - wave_field(p - vec2(0.0, e), t);

	vec2 rp = p * 2.1 + vec2(t * 0.30, -t * 0.22);
	float rx = value_noise(rp + vec2(0.1, 0.0)) - value_noise(rp - vec2(0.1, 0.0));
	float rz = value_noise(rp + vec2(0.0, 0.1)) - value_noise(rp - vec2(0.0, 0.1));

	// The normal amplification was the other half of the plaid: a strong
	// gradient turns gentle crests into hard bands.
	vec3 n = normalize(vec3(
		-(hx * 1.1 + rx * ripple_strength * 1.4),
		1.0,
		-(hz * 1.1 + rz * ripple_strength * 1.4)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// How much water the view ray passes through before it hits the bed.
	float raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float bed_distance = -view.z;
	float water_distance = -VERTEX.z;
	float through = max(bed_distance - water_distance, 0.0);

	// Deeper water is darker and bluer. Shallow water keeps the bank's colour
	// showing through it, which is what makes a pond read as shallow at all.
	float depth_mix = 1.0 - exp(-through / max(depth_falloff, 0.01));
	vec3 water = mix(shallow_color.rgb, deep_color.rgb, depth_mix);

	// Glancing angles reflect the sky; straight down you see the bottom.
	float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0),
		fresnel_power);

	// 0.65 put a hard white band along the far shore, where the view is most
	// glancing. A pond is not a mirror.
	ALBEDO = mix(water, fresnel_color.rgb, fresnel * 0.42);
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.6;

	// THE SHORELINE. Fade out as the bed comes up to meet the surface, so the
	// water disappears into the bank instead of ending at a hard rim. Fresnel
	// is added back in so the very edge keeps a highlight rather than vanishing.
	float shore = clamp(through / max(shore_fade, 0.01), 0.0, 1.0);
	ALPHA = clamp(max_alpha * shore + fresnel * 0.25 * shore, 0.0, 1.0);
}
