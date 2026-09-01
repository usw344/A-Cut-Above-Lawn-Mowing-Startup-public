class_name ACATerrain
extends Node3D
## ROLE
## The ground. It owns the procedural height field, the visible mesh, the
## collision, and the queries every other system asks about the surface.
##
## THE SHAPE IS A FUNCTION, NOT A FILE. A property is rebuilt from a seed and a
## handful of numbers, so nothing here is ever saved: no mesh, no heightmap, no
## vertex buffer. The same parameters always produce the same ground, which is
## what lets a save restore a property by rebuilding it.
##
## TWO SCALES, ON PURPOSE
##   * The NEAR FIELD is gentle. It is what the mower drives on, so the height
##     is levelled inside the lawn and only rolls slowly outside it.
##   * The DISTANT LANDSCAPE is not. It is built out of concentric square rings
##     that share their inner boundary with the near mesh, so there is no seam,
##     and it is allowed to have real hills because nobody has to mow them.
##
## PUBLIC API
##   build(params, features)          -> generate everything
##   height_at(x, z) -> float         -> world-space ground height
##   normal_at(x, z) -> Vector3       -> world-space surface normal
##   base_height_at(x, z) -> float    -> height BEFORE feature offsets
##   bounds() -> AABB                 -> the near field, the walkable part
##   world_bounds() -> AABB           -> everything, distant rings included
##   surface_height_at(x, z) -> float  -> the height of the surface DRAWN
##   near_extent() -> float
##   contains(x, z) -> bool
##   ground_material() -> ShaderMaterial
##   set_lawn_mask(texture, centre, size)
##   collision_body() -> StaticBody3D
##   statistics() -> Dictionary       -> build timings and counts
##
## SIGNALS: None.
##
## INVARIANTS
##   * `height_at()` agrees with the rendered near mesh: both read the same
##     baked lattice with the same triangle split.
##   * Queries are valid the moment `build()` returns; nothing waits a frame.
##   * The property is generated around this node's ORIGIN. Place the node, do
##     not offset the generation.
##
## PERSISTENCE OWNERSHIP
##   None. Everything here is reconstructed from ACAPropertyParams.

const GROUND_SHADER := "res://Mowing Section/Property/shaders/aca_ground.gdshader"

## World units between baked height samples. One sample per mowing cell, which
## is what keeps the collision, the queries and the mowing grid in step.
const CELL := 1.0

## Wavelength of the lawn's grade, in world units. Chosen against the lawns the
## game actually generates - 96 to 192 units across - so a property sits on ONE
## rise or ONE fall rather than on a series of them. A shorter wavelength is not
## a gentler hill, it is a bumpier lawn.
const LAWN_GRADE_SCALE := 118.0

## How far past a level zone the grade is eased back in, in world units. Wide
## enough that the easing is itself gentler than the grade it is easing.
const LEVEL_ZONE_FALLOFF := 30.0

## How far past the lawn the ground is baked for collision and queries. The
## mower can drive this far off the property before it runs out of world.
const COLLISION_MARGIN := 44.0

## How far past the lawn the fine visual mesh runs before the distant rings take
## over. Smaller than COLLISION_MARGIN because the rings start at one-unit steps
## and are indistinguishable from the core mesh where they meet it.
const CORE_MARGIN := 22.0

## Radial step growth for the distant rings, and the cap that stops a single
## step from swallowing a whole hill.
const RING_GROWTH := 1.28
const RING_STEP_MIN := 1.0

## A last downward nudge on `surface_height_at()`, as a fraction of the local
## ring span. The low pass gets most of the sag; this covers the rest, because
## a distant tree an armspan into a hillside is invisible and one an armspan
## over it is the first thing the eye finds.
const SURFACE_SINK := 0.07

# ------------------------------------------------------------------- state
var _params: ACAPropertyParams = null
var _features: ACAFeatureSet = null

## Baked near-field heights, row-major, `_verts` per row. Includes feature
## offsets. This IS the terrain as far as every query is concerned.
var _heights := PackedFloat32Array()
var _verts: int = 0
var _cells: int = 0
var _extent: float = 0.0
var _min_height: float = 0.0
var _max_height: float = 0.0
## Where the generated ground was placed, captured once at build time. Queries
## use this rather than `global_position` so they work before the node is in the
## tree and never change under a caller mid-frame.
var _origin: Vector3 = Vector3.ZERO

var _noise_broad: FastNoiseLite = null
var _noise_fine: FastNoiseLite = null
var _noise_micro: FastNoiseLite = null
var _noise_distant: FastNoiseLite = null
var _noise_grade: FastNoiseLite = null

## Features that need level ground under them, as `[Vector3(x, z, radius)]`.
## Almost always empty or one entry - see `_collect_level_zones()`.
var _level_zones: Array[Vector3] = []

var _core_mesh: MeshInstance3D = null
var _ring_mesh: MeshInstance3D = null
## The distant rings' own plan: the half extent of each loop, and how many
## segments it carries per side. Kept after the build so anything PLACED out
## there can ask how coarse the surface it is standing on really is.
var _ring_halves := PackedFloat32Array()
var _ring_sides := PackedInt32Array()
var _body: StaticBody3D = null
var _material: ShaderMaterial = null

var _stats := {}


# ======================================================================= build

## Generate the ground. Safe to call again; everything is rebuilt.
func build(params: ACAPropertyParams, features: ACAFeatureSet = null) -> void:
	_params = params
	_features = features if features != null else ACAFeatureSet.new()
	_stats = {}

	var t_start := Time.get_ticks_usec()
	_origin = global_position if is_inside_tree() else position
	_make_noise()
	# The near-field extent decides where the distant hills are allowed to start,
	# so it is resolved before anything samples the height function.
	_resolve_extent()
	# BEFORE `prepare()`, because a pond measures its water line against ground
	# this has already levelled. A zone is read from the feature's own bounds,
	# which a pond can answer before it has traced anything.
	_collect_level_zones()

	# Features resolve their reference ground BEFORE the bake, because a pond
	# measures its water line from the ground it is about to dig away.
	_features.prepare(base_height_world)
	var t_prepared := Time.get_ticks_usec()

	_bake()
	var t_baked := Time.get_ticks_usec()

	_build_core_mesh()
	var t_core := Time.get_ticks_usec()

	_build_rings()
	var t_rings := Time.get_ticks_usec()

	_build_collision()
	var t_end := Time.get_ticks_usec()

	_stats = {
		"prepare_ms": float(t_prepared - t_start) / 1000.0,
		"bake_ms": float(t_baked - t_prepared) / 1000.0,
		"core_mesh_ms": float(t_core - t_baked) / 1000.0,
		"ring_mesh_ms": float(t_rings - t_core) / 1000.0,
		"collision_ms": float(t_end - t_rings) / 1000.0,
		"total_ms": float(t_end - t_start) / 1000.0,
		"samples": _heights.size(),
		"core_vertices": _stats.get("core_vertices", 0),
		"core_triangles": _stats.get("core_triangles", 0),
		"ring_vertices": _stats.get("ring_vertices", 0),
		"ring_triangles": _stats.get("ring_triangles", 0),
		"min_height": _min_height,
		"max_height": _max_height,
	}


func statistics() -> Dictionary:
	return _stats.duplicate()


func _make_noise() -> void:
	_noise_broad = _noise(_params.seed, 1.0 / 165.0, 2)
	_noise_fine = _noise(_params.seed + 1, 1.0 / 41.0, 2)
	_noise_micro = _noise(_params.seed + 2, 1.0 / 9.5, 1)
	_noise_distant = _noise(_params.seed + 3, 1.0 / maxf(_params.distant_hill_scale, 40.0), 3)
	# ONE OCTAVE, deliberately. A second octave on a shape this broad is exactly
	# the medium-frequency unevenness the lawn is levelled to remove.
	_noise_grade = _noise(_params.seed + 4, 1.0 / LAWN_GRADE_SCALE, 1)


func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


# ================================================================ the function

## The ground BEFORE any feature has dug into it. This is what a pond measures
## its water line against, and it is the only place the landscape shape lives.
func base_height_at(x: float, z: float) -> float:
	var flat := _flatten_weight(x, z)

	# Broad roll first: this is the shape read as "the land tilts that way".
	var local := _noise_broad.get_noise_2d(x, z) * _params.broad_hill_strength * 0.62
	local += _noise_fine.get_noise_2d(x, z) * _params.fine_variation
	local *= _params.terrain_amplitude

	# Surface relief survives inside the lawn at reduced weight, so a mown lawn
	# is never a mathematically perfect plane, but is still pleasant to steer on.
	var micro := _noise_micro.get_noise_2d(x, z) * _params.micro_relief
	micro *= lerpf(1.0, 0.34, flat)

	local *= lerpf(1.0, 1.0 - _params.playable_flatness, flat)

	# THE GRADE, AND THE ONE THING THE LEVELLING DOES NOT TOUCH.
	#
	# Everything above is flattened towards nothing inside the mowable
	# rectangle, which is why a lawn used to be a plane with a little noise on
	# it. This term is not, because it is the shape the property is MEANT to
	# have: one broad rise or one shallow fall, forty centimetres or so across
	# the whole lawn, at a wavelength longer than the lawn is wide.
	#
	# It is what gives the machines something real to sit on. Vertical movement
	# in this game comes from ground that is genuinely not level - not from
	# tilting the mower, which is what it used to come from and what made
	# driving unpleasant. See `ACAMowerHandling.ground_tilt()`.
	#
	# Zero on every property generated before version 7.
	var grade := _grade_at(x, z)

	return local + micro + grade + _distant_height(x, z)


## ---------------------------------------------------------------------------
## THE GRADE, AND WHERE IT IS HELD LEVEL
## ---------------------------------------------------------------------------
## A pond's surface is a flat plane. A grade running across one either floods
## out of the bowl on the low side or leaves the water line short of the bank on
## the high side, and both are worse than a level pond - the second one also
## pushes the traced shoreline outside the AABB the feature rejects points with,
## which silently leaves mowable grass inside the collision ring.
##
## So the grade is HELD at its value at the feature's centre across the zone,
## rather than removed. The ground does not step and the land outside keeps
## falling exactly as it was; it simply stops falling where the water is, which
## is what a pond in a real garden looks like.
##
## Cost: a loop over a list that is empty or has one entry in it.
func _grade_at(x: float, z: float) -> float:
	if is_zero_approx(_params.lawn_grade):
		return 0.0
	var raw := _noise_grade.get_noise_2d(x, z) * _params.lawn_grade
	for zone in _level_zones:
		var dx := x - zone.x
		var dz := z - zone.y
		var distance := sqrt(dx * dx + dz * dz)
		if distance >= zone.z + LEVEL_ZONE_FALLOFF:
			continue
		var held: float = _noise_grade.get_noise_2d(zone.x, zone.y) 			* _params.lawn_grade
		var blend: float = smoothstep(zone.z, zone.z + LEVEL_ZONE_FALLOFF,
			distance)
		raw = lerpf(held, raw, blend)
	return raw


## Read once, at build, from the features' own bounds. A pond can answer this
## before it has traced its shoreline, which is exactly why the zone is taken
## from `bounds()` rather than from the traced ring.
func _collect_level_zones() -> void:
	_level_zones.clear()
	if _features == null:
		return
	for feature in _features.features():
		if not feature.levels_ground():
			continue
		var box := feature.bounds()
		var centre := box.position + box.size * 0.5
		var radius: float = maxf(box.size.x, box.size.z) * 0.5
		_level_zones.append(Vector3(centre.x - _origin.x, centre.z - _origin.z,
			radius))


## Scenic hills. Zero across the whole playable area, then ramped in with
## distance, so the mower never meets them and the horizon is never empty.
func _distant_height(x: float, z: float) -> float:
	var radius := sqrt(x * x + z * z)
	var start := maxf(_params.distant_hill_start, _extent + 20.0)
	if radius <= start:
		return 0.0
	var ramp: float = smoothstep(start, start + _params.distant_hill_scale * 0.75, radius)
	var hills := _noise_distant.get_noise_2d(x, z) * _params.distant_hill_strength
	# A gentle overall rise as well as the hills, so the far ground closes the
	# horizon instead of falling away out of sight.
	var lift: float = _params.distant_hill_strength * 0.28 * smoothstep(
		start, start + _params.distant_hill_scale * 2.0, radius)
	return (hills + lift) * ramp


## 1 inside the mowable rectangle, falling to 0 over `flatten_falloff` units
## outside it. Distance is measured to the RECTANGLE, not to the centre, so the
## flat area is a lawn rather than a circle.
func _flatten_weight(x: float, z: float) -> float:
	var half := _params.lawn_half_extent()
	var dx: float = maxf(absf(x) - half, 0.0)
	var dz: float = maxf(absf(z) - half, 0.0)
	if dx <= 0.0 and dz <= 0.0:
		return 1.0
	var distance := sqrt(dx * dx + dz * dz)
	return 1.0 - smoothstep(0.0, maxf(_params.flatten_falloff, 1.0), distance)


## The height function in WORLD space, for callers outside this class. Features
## are placed in world coordinates, so this is what they measure against.
func base_height_world(x: float, z: float) -> float:
	return _origin.y + base_height_at(x - _origin.x, z - _origin.z)


## The base shape plus everything dug into it, in the terrain's own space. Used
## for the bake and for any query outside the baked area.
func _full_height_at(x: float, z: float) -> float:
	return base_height_at(x, z) + _features.terrain_offset_at(x + _origin.x, z + _origin.z)


# ======================================================================== bake

func _resolve_extent() -> void:
	_extent = _params.lawn_half_extent() + COLLISION_MARGIN
	_cells = int(round(_extent * 2.0 / CELL))
	if _cells % 2 == 1:
		_cells += 1
	_extent = float(_cells) * CELL * 0.5
	_verts = _cells + 1


func _bake() -> void:
	_heights.resize(_verts * _verts)
	var lowest := INF
	var highest := -INF
	var origin := -_extent
	var index := 0
	for iz in _verts:
		var z := origin + float(iz) * CELL
		for ix in _verts:
			var h := _full_height_at(origin + float(ix) * CELL, z)
			_heights[index] = h
			index += 1
			if h < lowest:
				lowest = h
			if h > highest:
				highest = h
	_min_height = lowest
	_max_height = highest


# ==================================================================== queries

func near_extent() -> float:
	return _extent


func contains(x: float, z: float) -> bool:
	return absf(x - _origin.x) <= _extent and absf(z - _origin.z) <= _extent


## Ground height in world space. Inside the near field this reads the baked
## lattice with the SAME triangle split the mesh was built with, so a query and
## the surface a camera sees are the same number. Outside it, the analytic
## function answers, which is what the distant rings were built from.
func height_at(x: float, z: float) -> float:
	return _origin.y + _sample(x - _origin.x, z - _origin.z)


## The height of the SURFACE THAT IS DRAWN, which past the near field is not
## the same number as `height_at()`.
##
## The distant rings are coarse on purpose: their radial step grows to a
## hundred units or more, so a triangle out there spans a good fraction of a
## hill and its middle sags well below the height function it was sampled from.
## Anything placed by `height_at()` past the lattice therefore hangs over the
## ground it is supposed to be standing on - which is exactly what the far tree
## band was doing, a scatter of specks floating above the hills.
##
## The tessellation is not reproduced here. The height function is low-passed
## over the ring's own span instead, which is what a flat triangle across that
## span averages out to, and the answer is held at or below the direct sample so
## that whatever error is left buries a trunk rather than exposing one. Inside
## the near field this IS `height_at()`, to the bit.
func surface_height_at(x: float, z: float) -> float:
	if contains(x, z):
		return height_at(x, z)
	var span := _ring_span_at(maxf(absf(x - _origin.x), absf(z - _origin.z)))
	if span <= CELL * 2.0:
		return height_at(x, z)
	var half := span * 0.5
	var averaged: float = 0.25 * (
		height_at(x - half, z) + height_at(x + half, z)
		+ height_at(x, z - half) + height_at(x, z + half))
	# MOSTLY the average, leaning a little towards the lower of the two.
	# Taking the minimum outright looked like the safe choice and was not: near
	# a ridge the four samples half a span out are all well below the crest, so
	# "safe" buried a whole hillside of trees. Taking the average alone left the
	# steepest slopes still holding a tree or two off the ground. A third of the
	# way between them settles both.
	var direct := height_at(x, z)
	var lowest := minf(direct, averaged)
	return lerpf(averaged, lowest, 0.34) - span * SURFACE_SINK


## How coarse the drawn surface is at a given Chebyshev distance from the
## centre: the larger of the ring's radial step and its tangential spacing,
## because a triangle sags across whichever of the two is longer.
func _ring_span_at(chebyshev: float) -> float:
	var loops := _ring_halves.size()
	if loops < 2:
		return CELL
	if chebyshev <= _ring_halves[0]:
		return CELL
	for k in range(loops - 1):
		if chebyshev <= _ring_halves[k + 1]:
			return maxf(_ring_halves[k + 1] - _ring_halves[k],
				_ring_halves[k] * 2.0 / maxf(float(_ring_sides[k]), 1.0))
	var last := loops - 1
	return maxf(_ring_halves[last] - _ring_halves[last - 1],
		_ring_halves[last] * 2.0 / maxf(float(_ring_sides[last]), 1.0))


## Surface normal in world space, by central difference. The step is one cell,
## so the answer describes the surface a wheel rolls on rather than the
## micro-relief between two samples.
func normal_at(x: float, z: float) -> Vector3:
	var step := CELL
	var left := height_at(x - step, z)
	var right := height_at(x + step, z)
	var back := height_at(x, z - step)
	var front := height_at(x, z + step)
	return Vector3(left - right, 2.0 * step, back - front).normalized()


## Slope at a point, 0 flat and 1 vertical.
func slope_at(x: float, z: float) -> float:
	return 1.0 - clampf(normal_at(x, z).y, 0.0, 1.0)


## The near field: the part with collision, grass and a fine mesh.
func bounds() -> AABB:
	return AABB(
		_origin + Vector3(-_extent, _min_height - 1.0, -_extent),
		Vector3(_extent * 2.0, (_max_height - _min_height) + 2.0, _extent * 2.0))


## Everything, distant rings included.
func world_bounds() -> AABB:
	var r: float = _params.landscape_radius if _params != null else _extent
	var h: float = _params.distant_hill_strength * 1.5 if _params != null else 10.0
	return AABB(
		_origin + Vector3(-r, _min_height - h, -r),
		Vector3(r * 2.0, (_max_height - _min_height) + h * 2.0, r * 2.0))


func collision_body() -> StaticBody3D:
	return _body


func ground_material() -> ShaderMaterial:
	return _material


## Hand the ground the lawn's cut mask, so the soil under a mown stripe can
## respond with it instead of ignoring it.
func set_lawn_mask(mask: Texture2D, centre: Vector2, size: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("lawn_mask", mask)
	_material.set_shader_parameter("lawn_centre", centre)
	_material.set_shader_parameter("lawn_size", size)


# ======================================================================= mesh

func _build_core_mesh() -> void:
	var core_extent: float = _params.lawn_half_extent() + CORE_MARGIN
	var core_cells: int = int(round(core_extent * 2.0 / CELL))
	if core_cells % 2 == 1:
		core_cells += 1
	core_extent = float(core_cells) * CELL * 0.5
	var core_verts := core_cells + 1

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(core_verts * core_verts)
	normals.resize(core_verts * core_verts)
	uvs.resize(core_verts * core_verts)

	# The core sits inside the baked lattice, so both the height and the normal
	# come straight out of `_heights`. Re-evaluating the noise here would cost
	# five height evaluations per vertex for an identical answer.
	var lattice_offset := int(round((_extent - core_extent) / CELL))
	var origin := -core_extent
	var index := 0
	for iz in core_verts:
		var z := origin + float(iz) * CELL
		var lz := iz + lattice_offset
		for ix in core_verts:
			var x := origin + float(ix) * CELL
			var lx := ix + lattice_offset
			vertices[index] = Vector3(x, _lattice(lx, lz), z)
			normals[index] = _lattice_normal(lx, lz)
			uvs[index] = Vector2(x, z) * 0.02
			index += 1

	var indices := PackedInt32Array()
	indices.resize(core_cells * core_cells * 6)
	var w := 0
	for iz in core_cells:
		for ix in core_cells:
			var i00 := iz * core_verts + ix
			var i10 := i00 + 1
			var i01 := i00 + core_verts
			var i11 := i01 + 1
			# Split along (0,0)-(1,1), matching height_at(). The winding is the
			# one Godot treats as front-facing upwards; `Property Test` asserts
			# it rather than trusting the convention.
			indices[w] = i00
			indices[w + 1] = i10
			indices[w + 2] = i11
			indices[w + 3] = i00
			indices[w + 4] = i11
			indices[w + 5] = i01
			w += 6

	_stats["core_vertices"] = vertices.size()
	_stats["core_triangles"] = indices.size() / 3
	_core_mesh = _commit(_core_mesh, "Ground", vertices, normals, uvs, indices)
	if _core_mesh != null:
		# The ground RECEIVES shadows; it does not need to cast them. A gentle
		# lawn shadows almost nothing of itself, and casting would push a
		# hundred thousand triangles through every shadow cascade for it.
		_core_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Concentric square rings out to the landscape radius.
##
## The innermost ring shares its vertex count per side with the core mesh's
## outer edge, so the two surfaces meet without a crack. As the radial step
## grows, the tangential count HALVES and a fan of three triangles bridges the
## two resolutions, which is what keeps the far landscape from costing more
## than the ground the player actually drives on.
func _build_rings() -> void:
	var core_extent: float = _params.lawn_half_extent() + CORE_MARGIN
	var core_cells: int = int(round(core_extent * 2.0 / CELL))
	if core_cells % 2 == 1:
		core_cells += 1
	core_extent = float(core_cells) * CELL * 0.5

	var step_cap: float = maxf(_params.distant_hill_scale / 5.0, 20.0)
	var target: float = maxf(_params.landscape_radius, core_extent + 200.0)

	# Plan the loops first: half-extent and tangential segment count per side.
	var halves := PackedFloat32Array()
	var sides := PackedInt32Array()
	var half := core_extent
	var per_side := core_cells
	var step := RING_STEP_MIN
	halves.append(half)
	sides.append(per_side)
	while half < target and halves.size() < 160:
		step = minf(step * RING_GROWTH, step_cap)
		half += step
		# Halve the tangential resolution once a quad would be far longer
		# radially than it is wide. Long thin triangles buy nothing.
		var spacing := half * 2.0 / float(per_side)
		if step > spacing * 2.0 and per_side >= 32 and per_side % 2 == 0:
			per_side /= 2
		halves.append(half)
		sides.append(per_side)

	var loops := halves.size()
	if loops < 2:
		return
	_ring_halves = halves
	_ring_sides = sides

	# --------------------------------------------------------------- vertices
	var offsets := PackedInt32Array()
	offsets.resize(loops)
	var total := 0
	for k in loops:
		offsets[k] = total
		total += sides[k] * 4

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(total)
	normals.resize(total)
	uvs.resize(total)

	for k in loops:
		var count := sides[k] * 4
		var base := offsets[k]
		for i in count:
			var p := _perimeter_point(halves[k], i, sides[k])
			vertices[base + i] = Vector3(p.x, _sample(p.x, p.y), p.y)
			uvs[base + i] = p * 0.02

	# Normals from the ring lattice itself. One height evaluation per vertex
	# rather than five, which is the difference between this taking tens of
	# milliseconds and taking hundreds.
	for k in loops:
		var count := sides[k] * 4
		var base := offsets[k]
		var prev_k: int = maxi(k - 1, 0)
		var next_k: int = mini(k + 1, loops - 1)
		for i in count:
			var tangential := vertices[base + (i + 1) % count] 				- vertices[base + (i - 1 + count) % count]
			var inner := vertices[offsets[prev_k] + _match_index(i, count, sides[prev_k] * 4)]
			var outer := vertices[offsets[next_k] + _match_index(i, count, sides[next_k] * 4)]
			var radial := outer - inner
			var n := tangential.cross(radial)
			if n.y < 0.0:
				n = -n
			if n.length_squared() < 0.000001:
				n = Vector3.UP
			normals[base + i] = n.normalized()

	# ---------------------------------------------------------------- indices
	var indices := PackedInt32Array()
	for k in loops - 1:
		var inner_count := sides[k] * 4
		var outer_count := sides[k + 1] * 4
		var inner_base := offsets[k]
		var outer_base := offsets[k + 1]
		if inner_count == outer_count:
			for i in outer_count:
				var j := (i + 1) % outer_count
				# Winding matches the core mesh, with the OUTER loop playing the
				# role of the near edge. The perimeter walk is clockwise seen
				# from above, so one rule holds for all four sides.
				indices.append(outer_base + i)
				indices.append(outer_base + j)
				indices.append(inner_base + j)
				indices.append(outer_base + i)
				indices.append(inner_base + j)
				indices.append(inner_base + i)
		else:
			# Two inner segments to one outer segment: a fan of three.
			for i in outer_count:
				var j := (i + 1) % outer_count
				var a0 := inner_base + (i * 2) % inner_count
				var a1 := inner_base + (i * 2 + 1) % inner_count
				var a2 := inner_base + (i * 2 + 2) % inner_count
				indices.append(outer_base + i)
				indices.append(outer_base + j)
				indices.append(a2)
				indices.append(outer_base + i)
				indices.append(a2)
				indices.append(a1)
				indices.append(outer_base + i)
				indices.append(a1)
				indices.append(a0)

	_stats["ring_vertices"] = vertices.size()
	_stats["ring_triangles"] = indices.size() / 3
	_stats["ring_loops"] = loops
	_ring_mesh = _commit(_ring_mesh, "Distant Landscape", vertices, normals, uvs, indices)
	if _ring_mesh != null:
		# The rings are scenery. Shadow casting across four thousand units buys
		# nothing and costs a shadow pass over the whole landscape.
		_ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The vertex in a neighbouring loop that sits at roughly the same place around
## the perimeter, whether that loop has the same, twice or half the resolution.
func _match_index(index: int, from_count: int, to_count: int) -> int:
	if from_count == to_count:
		return index
	return clampi(int(float(index) * float(to_count) / float(from_count)), 0, to_count - 1)


## Walk the perimeter of a square of half-extent `half`, `per_side` segments to
## a side, starting at the -X -Z corner and going in +X first.
func _perimeter_point(half: float, i: int, per_side: int) -> Vector2:
	var side := i / per_side
	var t := float(i % per_side) / float(per_side)
	var span := half * 2.0
	match side:
		0: return Vector2(-half + span * t, -half)
		1: return Vector2(half, -half + span * t)
		2: return Vector2(half - span * t, half)
		_: return Vector2(-half, half - span * t)


## Ground height in the terrain's OWN space. Inside the baked area this reads
## the lattice with the same triangle split the core mesh was built with, so a
## query and the surface a camera sees are the same number. Outside it, the
## analytic function answers, which is what the distant rings were built from.
func _sample(x: float, z: float) -> float:
	if _verts < 2 or absf(x) > _extent or absf(z) > _extent:
		return _full_height_at(x, z)

	var gx: float = (x + _extent) / CELL
	var gz: float = (z + _extent) / CELL
	var ix: int = clampi(int(gx), 0, _cells - 1)
	var iz: int = clampi(int(gz), 0, _cells - 1)
	var fx: float = gx - float(ix)
	var fz: float = gz - float(iz)

	var row := iz * _verts + ix
	var h00 := _heights[row]
	var h10 := _heights[row + 1]
	var h01 := _heights[row + _verts]
	var h11 := _heights[row + _verts + 1]

	# The quad is split along the (0,0)-(1,1) diagonal, matching _build_core_mesh.
	if fz <= fx:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h01 - h00) * fz + (h11 - h01) * fx


## One baked sample, clamped at the edge of the lattice.
func _lattice(ix: int, iz: int) -> float:
	return _heights[clampi(iz, 0, _cells) * _verts + clampi(ix, 0, _cells)]


## Central difference straight off the lattice: no noise, no interpolation.
func _lattice_normal(ix: int, iz: int) -> Vector3:
	var left := _lattice(ix - 1, iz)
	var right := _lattice(ix + 1, iz)
	var back := _lattice(ix, iz - 1)
	var front := _lattice(ix, iz + 1)
	return Vector3(left - right, 2.0 * CELL, back - front).normalized()


func _commit(node: MeshInstance3D, node_name: String,
		vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var instance := node
	if instance == null or not is_instance_valid(instance):
		instance = MeshInstance3D.new()
		instance.name = node_name
		add_child(instance)
	instance.mesh = mesh
	instance.material_override = _ensure_material()
	return instance


func _ensure_material() -> ShaderMaterial:
	if _material != null:
		return _material
	var shader := load(GROUND_SHADER) as Shader
	_material = ShaderMaterial.new()
	if shader != null:
		_material.shader = shader
	_apply_material_parameters()
	return _material


func _apply_material_parameters() -> void:
	if _material == null or _material.shader == null or _params == null:
		return
	_material.set_shader_parameter("lawn_half_extent", _params.lawn_half_extent())
	_material.set_shader_parameter("lawn_centre", Vector2.ZERO)
	_material.set_shader_parameter("lawn_size", _params.lawn_half_extent() * 2.0)
	_material.set_shader_parameter("dryness", _params.dryness)
	_material.set_shader_parameter("colour_bias", _params.lawn_colour_bias)
	_material.set_shader_parameter("terrain_seed",
		float(_params.seed % 4096) * 0.37)


# ================================================================== collision

## `HeightMapShape3D` is exactly this data structure, so the collision is the
## baked lattice with no conversion, no trimesh and no per-cell body. One shape
## covers the whole walkable property.
func _build_collision() -> void:
	if _body == null or not is_instance_valid(_body):
		_body = StaticBody3D.new()
		_body.name = "Ground Collision"
		add_child(_body)
		var shape_node := CollisionShape3D.new()
		shape_node.name = "Shape"
		_body.add_child(shape_node)

	var shape := HeightMapShape3D.new()
	shape.map_width = _verts
	shape.map_depth = _verts
	shape.map_data = _heights

	var shape_node := _body.get_node(^"Shape") as CollisionShape3D
	shape_node.shape = shape
	# HeightMapShape3D is centred on its own origin with one unit per sample,
	# which is exactly how the lattice was baked.
	shape_node.position = Vector3.ZERO
