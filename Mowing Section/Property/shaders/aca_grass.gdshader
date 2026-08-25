shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// THE LAWN.
//
// One material draws standing grass, cut grass and the wild meadow outside the
// property, because they are the same plant in different states. What decides
// the state is a small texture the mowing system writes: one texel per square
// world unit, R for cut, G for the heading the mower was on. No per instance
// update, no MultiMesh rebuild, no node touched when a stripe is cut.
//
// The blade mesh carries UV.y as the height fraction along a leaf, which is
// what lets the tip move while the root stays planted. Everything below - wind,
// flattening, shading - is weighted by it. COLOR.rg carries the leaf's own AXIS,
// which is what lets a cut leaf be straightened without being narrowed.

group_uniforms Lawn;
uniform sampler2D lawn_mask : hint_default_transparent, filter_linear, repeat_disable;
uniform vec2 lawn_centre = vec2(0.0, 0.0);
uniform float lawn_size = 96.0;
// How far the visual cut boundary is allowed to wander from the logical one,
// in world units. This is what stops a mown edge from showing the grid.
uniform float edge_wander : hint_range(0.0, 4.0) = 1.70;

group_uniforms Wind;
uniform vec2 wind_direction = vec2(0.86, 0.51);
uniform float wind_speed : hint_range(0.0, 3.0) = 0.62;
// The three layers the motion is built from. See the note above `vertex()`.
// BROAD is the gust front crossing the property; LOCAL is the small
// disagreement between one patch and the next; JITTER is per tuft, and is the
// smallest of the three on purpose.
uniform float wind_strength : hint_range(0.0, 0.6) = 0.19;
uniform float gust_strength : hint_range(0.0, 0.4) = 0.10;
uniform float local_strength : hint_range(0.0, 0.3) = 0.055;
// Wavelength of the broad gust, in world units. A whole Large property is 192
// units across, so a front this size crosses it as a single slow pass rather
// than as a series of waves.
uniform float gust_wavelength : hint_range(20.0, 400.0) = 145.0;
// ...and of the local variation. A few tufts across, not a few dozen.
uniform float local_wavelength : hint_range(2.0, 60.0) = 13.0;
// The height, in world units, that `wind_strength` is calibrated against. A
// blade taller than this bends further and a mown one barely at all, which is
// what makes a tall lawn look loose and a cut one look firm.
uniform float wind_reference_height : hint_range(0.1, 3.0) = 0.86;

group_uniforms Cut;
// How much of its height a cut blade keeps.
//
// LOWERED WHEN THE LAWN GREW. `ACALawnGrass.LAWN_HEIGHT` went from 0.44 world
// units to 0.86, and if this had stayed at 0.44 the mown lawn would have gone
// up with it - the same ratio of a taller blade. The absolute height left
// behind is what a mower deck decides, so this came down by almost the same
// factor: mown grass is left at about 0.19 units, which is within a
// millimetre or two of where it was before, and the whole of the extra height
// is now on the side the player is paid to remove.
uniform float cut_height : hint_range(0.05, 0.8) = 0.250;
// How far a cut blade lies over, in WORLD units, along the pass that cut it.
uniform float cut_lean : hint_range(0.0, 0.6) = 0.062;
// A cut blade stands back UP. The mesh's own lean is horizontal, so shortening
// a blade without pulling its tip back in leaves a stroke lying flat on the
// ground - which is the whole reason mown grass was reading as scribble.
// A cut blade is drawn more upright than it used to be as well. The leaf is
// now a quarter of a much taller one, so what is left of it after the deck has
// been over is a stub, and a stub lying over reads as a clipping rather than
// as living grass.
uniform float cut_stand : hint_range(0.1, 1.0) = 0.40;
// ...and spreads a little at the root, so a shorter blade still covers ground.
uniform float cut_root_spread : hint_range(0.8, 1.4) = 1.12;
// A cut leaf is drawn WIDER. Height is what a mower takes; width is not, and a
// short lawn only reads as dense if the leaves still cover the ground.
// LOWERED, after the first render of the taller lawn. The reasoning that put
// this up to 1.62 was sound - a blade cut to a quarter of a tall leaf has less
// leaf in it than one cut to a half of a short one - but the mesh had been
// widened by nineteen per cent at the same time, and the two together turned
// mown grass into a scatter of flat pale chips lying on dark ground. Which is
// the exact failure the whole cut treatment exists to avoid.
uniform float cut_width : hint_range(0.8, 2.4) = 1.15;
// How far either side of the logical boundary a tuft may disagree about whether
// it was cut. This is what turns a one-texel edge into a mown margin.
uniform float cut_dither : hint_range(0.0, 1.0) = 0.62;
uniform float stripe_strength : hint_range(0.0, 0.6) = 0.19;

group_uniforms Colour;
uniform vec3 base_colour : source_color = vec3(0.124, 0.240, 0.091);
uniform vec3 tip_colour : source_color = vec3(0.302, 0.522, 0.181);
uniform vec3 cut_colour : source_color = vec3(0.290, 0.472, 0.167);
uniform vec3 dry_colour : source_color = vec3(0.430, 0.395, 0.155);
uniform vec3 meadow_tip : source_color = vec3(0.360, 0.470, 0.180);
uniform float dryness : hint_range(0.0, 1.0) = 0.24;
uniform float colour_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.88;
uniform float translucency : hint_range(0.0, 0.5) = 0.11;

varying float height_fraction;
varying float cut_amount;
varying float colour_variation;
varying float is_meadow;
varying float stripe_shade;

// Matches ACAGrassMesh.AXIS_RANGE. The two have to agree or a cut leaf moves
// to the wrong place.
const float AXIS_RANGE = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	// INSTANCE_CUSTOM: x coherent colour drift, y height multiplier,
	// z wind phase, w 1.0 for the wild meadow outside the lawn.
	colour_variation = INSTANCE_CUSTOM.x;
	is_meadow = INSTANCE_CUSTOM.w;
	height_fraction = UV.y;
	float blade_id = UV.x;

	vec3 root = MODEL_MATRIX[3].xyz;

	// ------------------------------------------------------------- cut state
	vec2 mask_uv = (root.xz - lawn_centre) / max(lawn_size, 1.0) + vec2(0.5);
	// The logical mowing grid is one texel per world unit. Sampling it at a
	// position nudged by a per tuft hash means the visible boundary follows the
	// mower rather than the spreadsheet.
	vec2 nudge = vec2(hash12(root.xz * 3.7), hash12(root.zx * 5.1 + 19.3)) - 0.5;
	mask_uv += nudge * (edge_wander / max(lawn_size, 1.0));
	vec4 mask = vec4(0.0);
	if (mask_uv.x > 0.0 && mask_uv.x < 1.0 && mask_uv.y > 0.0 && mask_uv.y < 1.0) {
		mask = textureLod(lawn_mask, mask_uv, 0.0);
	}
	// The mask is one texel per world unit and the sampler filters it, so the
	// raw value already ramps across roughly a unit at the boundary. Each tuft
	// then disagrees with its neighbours about where in that ramp "cut" begins,
	// which is what makes the last pass end in a mown margin rather than on a
	// line. Nothing about the LOGICAL cut moves; this is entirely how it reads.
	float raw_cut = mask.r;
	float tuft_bias = (hash12(root.xz * 7.31 + 4.17) - 0.5) * cut_dither;
	cut_amount = smoothstep(0.34, 0.78, raw_cut + tuft_bias) * (1.0 - is_meadow);
	float cut_heading = mask.g * 6.28318530718;
	vec2 cut_dir = vec2(cos(cut_heading), sin(cut_heading));

	// A cut blade keeps its root and loses its height, then lies over along the
	// pass that cut it. That directional lie IS the mowing stripe.
	//
	// THE HEIGHT IS NOT THE WHOLE STORY. Every blade in the mesh leans out
	// horizontally towards its tip, and that lean is authored in the XZ plane.
	// Scaling only Y leaves the full horizontal reach on a blade a third of its
	// former height, which lays it flat: a bright stroke on dark ground. So the
	// tip is drawn back towards the tuft's axis by the same act that shortens
	// it, and the root is let out slightly to keep the ground covered.
	float height_scale = mix(INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.y * cut_height, cut_amount);
	VERTEX.y *= height_scale;
	float along = height_fraction * height_fraction;
	// COLOR.rg is the leaf's axis; whatever is left of VERTEX.xz is its width.
	// Separating the two is the point: the axis comes in towards vertical, the
	// width goes out. Scaling the pair together instead is what tapers a mown
	// leaf into a needle and leaves the ground showing between the needles.
	vec2 leaf_axis = (COLOR.rg * 2.0 - 1.0) * AXIS_RANGE;
	vec2 leaf_width = VERTEX.xz - leaf_axis;
	VERTEX.xz = leaf_axis * mix(1.0, mix(cut_root_spread, cut_stand, along), cut_amount)
		+ leaf_width * mix(1.0, cut_width, cut_amount);

	// The lie has to point along the PASS, in world space. Applied straight to
	// VERTEX it would be turned by each tuft's own random yaw, which scatters
	// the lay directions and is the second half of the scribbled look. Project
	// it through the model axes instead, so the offset lands where it was meant
	// to and `cut_lean` reads in world units.
	vec3 axis_x = MODEL_MATRIX[0].xyz;
	vec3 axis_z = MODEL_MATRIX[2].xyz;
	float scale_x = max(dot(axis_x, axis_x), 0.0001);
	float scale_z = max(dot(axis_z, axis_z), 0.0001);
	vec3 lay = vec3(cut_dir.x, 0.0, cut_dir.y);
	vec2 lay_local = vec2(dot(lay, axis_x) / scale_x, dot(lay, axis_z) / scale_z);
	VERTEX.xz += lay_local * (along * cut_amount * cut_lean);

	// ----------------------------------------------------------------- wind
	//
	// THREE LAYERS, IN ORDER OF SIZE, and the order matters more than any of the
	// individual numbers:
	//
	//   BROAD   one long, slow gust front travelling ALONG the wind direction.
	//           Its wavelength is a whole property, so what the player sees is
	//           the lawn leaning as a field and coming back, not a series of
	//           waves rolling across it. The previous version's wave was about
	//           thirty units long, which is what made a big lawn look like open
	//           water.
	//   LOCAL   a much shorter field on top, at a third of the amplitude, so
	//           one patch of grass is never doing exactly what the patch beside
	//           it is doing.
	//   JITTER  a per tuft phase at the smallest amplitude of the three. This
	//           is what stops the two fields above from ever resolving into a
	//           pattern, and it is deliberately the quietest term: turn it up
	//           and a lawn stops swaying and starts fidgeting.
	//
	// EVERY TERM IS SAMPLED FROM WORLD POSITION, never from anything a tile or
	// a MultiMesh knows, so the motion is continuous across every chunk
	// boundary on the property.
	vec2 direction = normalize(length(wind_direction) > 0.001
		? wind_direction : vec2(1.0, 0.0));
	float phase = INSTANCE_CUSTOM.z * 6.28318530718;
	float t = TIME * wind_speed;

	float along_wind = dot(root.xz, direction);
	float broad_k = 6.28318530718 / max(gust_wavelength, 1.0);
	float local_k = 6.28318530718 / max(local_wavelength, 1.0);

	// The broad front. Slow, and shaped so the lawn spends longer relaxed than
	// leaning - which is how a gust actually arrives.
	float front = sin(t * 0.42 - along_wind * broad_k);
	float gust = pow(0.5 + 0.5 * front, 2.2);
	// The steady breeze underneath it, at a wavelength between the two.
	float sway = sin(t * 0.95 - along_wind * broad_k * 3.1 + phase * 0.35);
	// Local disagreement, from a second axis so it is not a harmonic of the
	// first and cannot beat with it.
	vec2 across = vec2(-direction.y, direction.x);
	float local_wave = sin(t * 1.42 - dot(root.xz, across) * local_k + phase);
	// And the per tuft fidget, quietest of all.
	float jitter = sin(t * 2.05 + phase * 3.7 + blade_id * 2.1);

	// Flexibility grows towards the tip; a root never moves.
	float flexibility = pow(height_fraction, 1.6);
	// TALL GRASS MOVES MORE. The model matrix's Y axis is the instance height in
	// world units, so this is the real height of this blade measured against
	// what the strengths were tuned for. A mown blade is short AND stiff, which
	// is two reasons it barely moves rather than one.
	float blade_height = length(MODEL_MATRIX[1].xyz);
	float height_response = clamp(blade_height / max(wind_reference_height, 0.01),
		0.35, 2.2);
	float bend = (sway * wind_strength
			+ gust * gust_strength
			+ local_wave * local_strength
			+ jitter * local_strength * 0.45)
		* flexibility * height_response
		* mix(1.0, 1.30, is_meadow) * (1.0 - cut_amount * 0.90);
	VERTEX.xz += direction * bend;
	// A gust also pushes a little ACROSS itself. Without it the whole lawn
	// slides on one axis, which reads as a sheet being dragged.
	VERTEX.xz += across * (local_wave * local_strength * 0.6 * flexibility
		* height_response * (1.0 - cut_amount * 0.90));

	// Stripe shading, the way real ones work: grass laid AWAY from the viewer
	// reflects, grass laid TOWARDS them absorbs. Nothing is painted on - the
	// pattern comes out of the direction the blades were pushed over, so it
	// changes as the player turns, exactly as a mown lawn does.
	vec3 to_camera = INV_VIEW_MATRIX[3].xyz - root;
	vec2 view_dir = normalize(length(to_camera.xz) > 0.001
		? to_camera.xz : vec2(0.0, 1.0));
	stripe_shade = dot(cut_dir, view_dir) * cut_amount;
}

void fragment() {
	// A blade is drawn from both sides, and Godot flips the normal on the back
	// one. Undoing that flip is what keeps a lawn from being half black: every
	// face of every blade should light as though it were facing the sky, which
	// is how a lawn behaves and how a single leaf does not.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	// Tip lighter than base: the single cheapest thing that makes grass read as
	// grass rather than as green geometry. Meadow blades are taller, so more of
	// their length would sit in the dark base tone; lifting their root keeps the
	// rough ground from reading as a shadow around the property.
	vec3 tip = mix(tip_colour, meadow_tip, is_meadow);
	vec3 root_colour = mix(base_colour, base_colour * 1.45, is_meadow);
	vec3 colour = mix(root_colour, tip, pow(height_fraction, 0.75));

	// Coherent drift, sampled from a noise field at placement time rather than
	// rolled per blade, so the lawn has patches instead of confetti.
	colour = mix(colour, dry_colour, clamp(dryness * (0.25 + colour_variation * 1.1), 0.0, 0.8));
	// The same field moves TONE and HUE together, so a patch of lawn is not
	// merely a lighter patch of the same green. Both are weakened from what
	// tone alone used to carry: two small differences read as a lawn, one large
	// one reads as a stain.
	colour *= mix(0.90, 1.10, colour_variation);
	colour *= mix(vec3(0.925, 1.0, 1.045), vec3(1.065, 1.0, 0.895), colour_variation);
	colour *= mix(vec3(0.95, 1.0, 0.93), vec3(1.06, 1.0, 0.90), colour_bias * 0.5 + 0.5);

	// Fresh cut is brighter and slightly warmer. It is never darker: a mown
	// lawn that goes dark reads as exposed soil.
	// The root of a cut leaf sits close to the tone of the ground under it. A
	// short lawn is read as ONE surface, and every step of contrast between the
	// leaves and the thatch they stand in turns that surface back into confetti.
	vec3 fresh = mix(cut_colour * 0.72, cut_colour, height_fraction);
	colour = mix(colour, fresh, cut_amount * 0.9);
	colour *= 1.0 + stripe_shade * stripe_strength;

	// Contact shading at the root so a tuft sits into the ground instead of
	// hovering over it.
	colour *= mix(0.80, 1.0, smoothstep(0.0, 0.35, height_fraction));

	ALBEDO = colour;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	// Cheaper than subsurface scattering across a whole lawn, and enough to let
	// sunlit blade tips feel thin.
	// A standing leaf is thin enough for the sun to come through it. A mown one
	// is a stub, and letting it glow is what turns short grass into flecks.
	BACKLIGHT = colour * translucency * smoothstep(0.15, 1.0, height_fraction)
		* (1.0 - cut_amount * 0.65);
}
