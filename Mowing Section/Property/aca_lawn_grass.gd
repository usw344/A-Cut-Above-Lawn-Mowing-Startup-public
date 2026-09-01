class_name ACALawnGrass
extends Node3D
## ROLE
## Everything green that grows on the property: the kept lawn inside the
## contract's rectangle and the wild meadow around it. It places grass and it
## renders grass. It does not know what has been cut.
##
## ---------------------------------------------------------------------------
## WHY CUTTING COSTS NOTHING HERE
## ---------------------------------------------------------------------------
## Nothing in this class runs while the player mows. The cut state lives in one
## small texture that ACALawn writes and the grass shader reads, so a pass of
## the mower changes bytes in an image rather than rebuilding a MultiMesh,
## deleting a node or touching an instance. That is the whole reason a lawn can
## now be dense enough to look like a lawn.
##
## ---------------------------------------------------------------------------
## HOW IT IS ARRANGED
## ---------------------------------------------------------------------------
## The near field is cut into square tiles. Each tile carries two MultiMeshes:
## detailed tufts for the ground near the camera, and broader, sparser clumps
## for the middle distance. Godot's own visibility ranges fade between them and
## cull the rest, so the number of tufts DRAWN depends on where the player is
## looking rather than on how big the contract is. Past the last clump the
## ground shader carries the colour on its own.
##
## PUBLIC API
##   build(params, terrain, lawn, features)
##   statistics() -> Dictionary
##   set_quality(level)          0 low, 1 medium, 2 high
##   instance_count() / node_count()
##
## SIGNALS: None.
##
## INVARIANTS
##   * Placement is a pure function of the property seed and the tile position.
##     Two builds of one property put every blade in the same place.
##   * No grass is placed where a feature excludes it, and none inside the lawn
##     rectangle on a cell the lawn says is not mowable. Grass the mower cannot
##     reach is never grown in the first place.
##   * Nothing here is saved.
##
## PERSISTENCE OWNERSHIP: None.

const GRASS_SHADER := "res://Mowing Section/Property/shaders/aca_grass.gdshader"

## Side of one grass tile, in world units. Tiles are the unit of culling, so
## smaller is finer-grained and costs more nodes.
const TILE := 24.0

## Spacing of the jittered placement lattice, in world units.
const LAWN_SPACING := 0.71
const MEADOW_SPACING := 1.35

## Distance bands. The near band is dense and detailed; the mid band is what
## the eye reads as "grass over there".
const NEAR_END := 46.0
## A LONG overlap. The two bands cross-fade over this distance, and the wider it
## is the less there is to notice: what gives a distance band away is not the
## band itself, it is how short a stretch of ground one representation takes to
## turn into the other.
const NEAR_FADE := 17.0
const MID_END := 165.0
const MID_FADE := 44.0

## One clump stands in for this many detailed tufts. Three rather than four,
## because the mid clump is narrower than the one it replaced, and a lawn that
## thins out at forty metres is exactly the step this is trying to remove.
const MID_KEEP := 3

## Authored tuft height in world units before per-instance variation.
##
## THE WORLD IS ABOUT FOUR TIMES LIFE SIZE, so one world unit is roughly a
## quarter of a metre. The lawn used to stand at 0.44 units, which is a bit
## over ten real centimetres: a lawn that has just been cut. That is the wrong
## starting state for a contract. What the player is paid to remove should be
## an OVERDUE lawn - somewhere between the ankle and the shin - and the
## difference between that and what is left behind is most of the satisfaction
## in the whole game.
##
## 0.86 units is about twenty-one real centimetres. It is deliberately not
## higher: past roughly a unit the lawn stops reading as neglected turf and
## starts reading as meadow, and the wild grass outside the property loses the
## contrast that tells the player where the contract ends.
##
## THE CUT HEIGHT DID NOT FOLLOW IT UP. `cut_height` in the grass shader was
## lowered by the same factor, so mown grass is left at almost exactly the
## height it was left at before. What grew is the gap.
const LAWN_HEIGHT := 0.86
## THE WILD GRASS OUTSIDE THE CONTRACT. Taller than the lawn, and no taller
## than it needs to be: the first pass at the taller lawn took this to 1.34 and
## the arrival shot came back with the machine parked in what read as a wheat
## field, because the mower arrives seven units OFF the lawn - in the meadow
## band - and that is the player's first sight of the property.
const MEADOW_HEIGHT := 1.12

## Over how many units outside the contract the turf thins from lawn
## density to meadow density.
const MEADOW_THIN_OVER := 15.0

## How far past the contract the grass stays at lawn height, and over how many
## units it then rises to the meadow, both in world units.
const MEADOW_VERGE := 10.0
const MEADOW_RISE := 16.0

var _params: ACAPropertyParams = null
var _material: ShaderMaterial = null
var _stats := {}
var _instances := 0
var _nodes := 0


# ======================================================================= build

func build(params: ACAPropertyParams, terrain: ACATerrain, lawn: ACALawn,
		features: ACAFeatureSet) -> void:
	_params = params
	var t0 := Time.get_ticks_usec()
	_clear()

	_material = _make_material(params, lawn)

	var extent := terrain.near_extent()
	var tiles: int = int(ceil(extent * 2.0 / TILE))
	var origin := -extent
	var set := features if features != null else ACAFeatureSet.new()

	var colour_noise := FastNoiseLite.new()
	colour_noise.seed = params.seed + 17
	colour_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Patches a few tufts across, not a wash and not per-blade static.
	colour_noise.frequency = 1.0 / 13.0

	var placed := 0
	for tz in tiles:
		for tx in tiles:
			placed += _build_tile(
				Vector2(origin + float(tx) * TILE, origin + float(tz) * TILE),
				terrain, lawn, set, colour_noise)

	_instances = placed
	_stats = {
		"build_ms": float(Time.get_ticks_usec() - t0) / 1000.0,
		"tiles": tiles * tiles,
		"instances": placed,
		"nodes": _nodes,
	}


func statistics() -> Dictionary:
	return _stats.duplicate()


func instance_count() -> int:
	return _instances


func node_count() -> int:
	return _nodes


func material() -> ShaderMaterial:
	return _material


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_nodes = 0
	_instances = 0


# ==================================================================== placement

## One tile's worth of grass. Returns how many tufts were placed.
func _build_tile(tile_origin: Vector2, terrain: ACATerrain, lawn: ACALawn,
		features: ACAFeatureSet, colour_noise: FastNoiseLite) -> int:
	var lawn_centre := lawn.lawn_centre()
	var lawn_half := lawn.lawn_half_extent()
	var extent := terrain.near_extent()

	# Two lattices, because a kept lawn is denser than the meadow around it and
	# a single spacing would either thin the lawn or drown the property.
	var near_transforms := PackedFloat32Array()
	var near_custom := PackedFloat32Array()
	var mid_transforms := PackedFloat32Array()
	var mid_custom := PackedFloat32Array()

	var placed := 0
	var kept := 0
	var steps: int = int(ceil(TILE / LAWN_SPACING))
	for gz in steps:
		for gx in steps:
			var jitter_x := _hash2(tile_origin.x + float(gx), tile_origin.y + float(gz))
			var jitter_z := _hash2(tile_origin.y + float(gz) * 3.1, tile_origin.x + float(gx) * 1.7)
			# Jitter across almost the whole cell. Anything less leaves the
			# lattice readable as rows once a few thousand tufts line up.
			var x: float = tile_origin.x + (float(gx) + 0.02 + jitter_x * 0.96) * LAWN_SPACING
			var z: float = tile_origin.y + (float(gz) + 0.02 + jitter_z * 0.96) * LAWN_SPACING
			if absf(x) > extent or absf(z) > extent:
				continue

			var inside_lawn: bool = absf(x - lawn_centre.x) <= lawn_half \
				and absf(z - lawn_centre.z) <= lawn_half
			var ground := terrain.height_at(x, z)

			# How far outside the contract this candidate is, on a WANDERING
			# edge so nothing about the property boundary is a straight line.
			# Both the density and the height are read off this one number.
			var out: float = 0.0
			if not inside_lawn:
				var out_x: float = maxf(absf(x - lawn_centre.x) - lawn_half, 0.0)
				var out_z: float = maxf(absf(z - lawn_centre.z) - lawn_half, 0.0)
				out = sqrt(out_x * out_x + out_z * out_z)
				out += (_hash2(x * 0.31, z * 0.29) - 0.5) * 4.5
				out = maxf(out, 0.0)

			# Thin the meadow out on its own lattice by skipping most of the
			# candidates, so one loop serves both densities.
			#
			# GRADUALLY. Dropping straight to the meadow's own spacing the
			# moment a candidate left the rectangle put a hard step in the turf
			# exactly on the property line: from a mower's seat the ground in
			# front of the lawn went abruptly thin and dark along a dead
			# straight edge, which is the one thing the wide, noisy ground
			# transition was written to avoid. The grass has to make the same
			# journey the ground does.
			if not inside_lawn:
				var thinnest := LAWN_SPACING / MEADOW_SPACING
				thinnest *= thinnest
				var keep: float = lerpf(1.0, thinnest,
					smoothstep(0.0, MEADOW_THIN_OVER, out))
				keep *= _params.meadow_density
				if _hash2(x * 0.77, z * 0.91) > keep:
					continue

			# Excluded ground grows nothing, and the exclusion FADES, so a
			# shoreline thins out instead of ending on a ring.
			var exclusion := features.grass_exclusion_at(x, z, ground)
			if exclusion > 0.0:
				if exclusion >= 1.0:
					continue
				if _hash2(z * 1.31, x * 2.07) < exclusion:
					continue

			# Inside the contract rectangle, grass only grows where the lawn
			# says the mower can reach. Grass that cannot be cut is grass that
			# stops a property reaching a hundred per cent.
			if inside_lawn and not lawn.is_mowable(Vector3(x, ground, z)):
				continue

			var slope := terrain.slope_at(x, z)
			if slope > 0.62:
				continue

			var meadow: float = 0.0 if inside_lawn else 1.0
			var variation: float = colour_noise.get_noise_2d(x, z) * 0.5 + 0.5
			# THE PROPERTY'S CONDITION. 1.0 on every ordinary contract, which is
			# almost all of them; well above it on a neglected one, and that
			# extra height is the whole of what a rescue job looks like from the
			# seat. It rides on the STANDING height only - `cut_height` in the
			# shader is what a deck leaves behind, and a deck leaves the same
			# thing behind whatever it went through.
			var condition: float = maxf(_params.grass_height_scale, 0.1)
			var height_scale: float = LAWN_HEIGHT * condition
			if not inside_lawn:
				# The meadow starts barely taller than the kept lawn and grows
				# into itself over the next dozen units. Whether a blade is
				# MOWABLE is a hard line, because a contract is; how tall it is
				# should not be, or the property ends on a fence of grass.
				# A MOWN VERGE FIRST, THEN THE MEADOW. The machine arrives
				# `ACAProperty.ARRIVAL_SETBACK` units off the lawn edge, which is
				# inside this band - and the first render of the taller grass
				# showed why that matters: the player's first sight of the
				# property was from inside what looked like a wheat field, with
				# the lawn they had been hired to cut invisible behind it. So
				# the first several units past the contract stay at lawn height,
				# the way the verge of a kept property does, and the wild grass
				# starts further out where the trees are.
				height_scale = lerpf(LAWN_HEIGHT * condition * 1.02, MEADOW_HEIGHT,
					clampf((out - MEADOW_VERGE) / MEADOW_RISE, 0.0, 1.0))
			# RESTRAINED. The old spread was 0.80 - 1.24 of the authored height,
			# which was invisible at eleven centimetres and became a ragged,
			# spiky field at twenty-one. A lawn nobody has cut for three weeks
			# is uneven; it is not a saw blade.
			height_scale *= 0.88 + _hash2(x * 4.3, z * 2.9) * 0.24

			# Taller grass gathers into slightly wider clumps rather than
			# standing as separate stalks, which is what stops the extra height
			# reading as sparseness.
			var spread: float = (0.90 + _hash2(z * 6.1, x * 3.3) * 0.38) \
				* (1.0 if inside_lawn else 1.22)
			var yaw: float = _hash2(x * 9.7, z * 8.3) * TAU
			var basis := Basis(Vector3.UP, yaw).scaled(
				Vector3(spread, height_scale, spread))
			var transform := Transform3D(basis, Vector3(x, ground - 0.02, z))
			var custom := Color(variation, 1.0, _hash2(x * 11.3, z * 13.9), meadow)

			_append_instance(near_transforms, near_custom, transform, custom)
			placed += 1

			# A share of the tufts are also distant clumps, broader and taller so
			# the same ground reads at range with a fraction of the geometry.
			# Chosen by a POSITION hash, never by a counter: taking every fourth
			# candidate off a lattice picks one row in four, and a row in four is
			# corduroy across the middle distance.
			if _hash2(x * 3.71, z * 5.33) < 1.0 / float(MID_KEEP):
				# Widened enough to cover the tufts it stands in for, and no
				# wider. At 1.9 a clump was so much broader than a near tuft
				# that the middle distance read as a different plant.
				var mid_basis := Basis(Vector3.UP, yaw).scaled(
					Vector3(spread * 1.62, height_scale * 1.12, spread * 1.62))
				_append_instance(mid_transforms, mid_custom,
					Transform3D(mid_basis, Vector3(x, ground - 0.03, z)), custom)
				kept += 1

	if placed == 0:
		return 0

	var centre := Vector3(tile_origin.x + TILE * 0.5, 0.0, tile_origin.y + TILE * 0.5)
	_add_layer("Near", ACAGrassMesh.near_tuft(), near_transforms, near_custom,
		placed, centre, 0.0, NEAR_END, NEAR_FADE)
	if kept > 0:
		_add_layer("Mid", ACAGrassMesh.mid_tuft(), mid_transforms, mid_custom,
			kept, centre, NEAR_END - NEAR_FADE, MID_END, MID_FADE)
	return placed


## The MultiMesh buffer is written in one go. Setting instance transforms one at
## a time is the difference between a property building in a tenth of a second
## and in a second and a half.
func _append_instance(transforms: PackedFloat32Array, custom: PackedFloat32Array,
		t: Transform3D, colour: Color) -> void:
	var b := t.basis
	var o := t.origin
	transforms.append(b.x.x)
	transforms.append(b.y.x)
	transforms.append(b.z.x)
	transforms.append(o.x)
	transforms.append(b.x.y)
	transforms.append(b.y.y)
	transforms.append(b.z.y)
	transforms.append(o.y)
	transforms.append(b.x.z)
	transforms.append(b.y.z)
	transforms.append(b.z.z)
	transforms.append(o.z)
	custom.append(colour.r)
	custom.append(colour.g)
	custom.append(colour.b)
	custom.append(colour.a)


func _add_layer(suffix: String, mesh: Mesh, transforms: PackedFloat32Array,
		custom: PackedFloat32Array, count: int, centre: Vector3,
		begin: float, end: float, fade: float) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	# Godot expects transform floats and custom data interleaved per instance.
	var buffer := PackedFloat32Array()
	buffer.resize(count * 16)
	for i in count:
		var t := i * 12
		var c := i * 4
		var w := i * 16
		for k in 12:
			buffer[w + k] = transforms[t + k]
		for k in 4:
			buffer[w + 12 + k] = custom[c + k]
	multimesh.buffer = buffer

	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass %s %d" % [suffix, _nodes]
	instance.multimesh = multimesh
	instance.material_override = _material
	# Thousands of shadow casters cost far more than the contact they add, and
	# the ground shader already darkens under the turf.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_begin = begin
	instance.visibility_range_begin_margin = fade if begin > 0.0 else 0.0
	instance.visibility_range_end = end
	instance.visibility_range_end_margin = fade
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.extra_cull_margin = 2.0
	add_child(instance)
	instance.position = Vector3.ZERO
	_nodes += 1
	# The tile's own centre is what the visibility range measures against.
	instance.set_meta(&"tile_centre", centre)


# ==================================================================== material

func _make_material(params: ACAPropertyParams, lawn: ACALawn) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := load(GRASS_SHADER) as Shader
	if shader == null:
		push_error("[GRASS] shader missing at %s" % GRASS_SHADER)
		return mat
	mat.shader = shader
	var centre := lawn.lawn_centre()
	mat.set_shader_parameter("lawn_mask", lawn.cut_mask())
	mat.set_shader_parameter("lawn_centre", Vector2(centre.x, centre.z))
	mat.set_shader_parameter("lawn_size", lawn.lawn_half_extent() * 2.0)
	mat.set_shader_parameter("wind_direction", params.wind_direction)
	mat.set_shader_parameter("wind_speed", params.wind_speed)
	mat.set_shader_parameter("dryness", params.dryness)
	mat.set_shader_parameter("colour_bias", params.lawn_colour_bias)
	return mat


## Follow the player's graphics setting, and keep following it if they change it
## mid-contract. Index order matches `ACAGameSettings.QUALITY_NAMES`.
const QUALITY_LEVELS := {"low": 0, "medium": 1, "high": 2, "ultra": 2}


func bind_to_settings() -> void:
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings == null or not settings.has_method(&"graphics_quality"):
		return
	if not settings.is_connected(&"applied", _on_settings_applied):
		settings.connect(&"applied", _on_settings_applied)
	_apply_settings_quality(settings)


func _on_settings_applied(_values: Dictionary) -> void:
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings != null:
		_apply_settings_quality(settings)


func _apply_settings_quality(settings: Node) -> void:
	var name := String(settings.call(&"graphics_quality"))
	set_quality(int(QUALITY_LEVELS.get(name, 2)))


## Graphics quality trims the distance bands rather than the density, because a
## thinner lawn looks broken while a shorter draw distance looks like weather.
func set_quality(level: int) -> void:
	var near_scales: Array[float] = [0.62, 0.82, 1.0]
	var mid_scales: Array[float] = [0.5, 0.75, 1.0]
	var near_scale: float = near_scales[clampi(level, 0, 2)]
	var mid_scale: float = mid_scales[clampi(level, 0, 2)]
	for child in get_children():
		var instance := child as MultiMeshInstance3D
		if instance == null:
			continue
		if String(instance.name).contains("Near"):
			instance.visibility_range_end = NEAR_END * near_scale
		else:
			instance.visibility_range_end = MID_END * mid_scale


static func _hash2(x: float, z: float) -> float:
	# A deterministic, position-only hash. No RNG state, so placement never
	# depends on the order tiles happen to be built in.
	var v := Vector2(x, z)
	var s := sin(v.dot(Vector2(127.1, 311.7))) * 43758.5453
	return s - floor(s)
