class_name ACAConservationZone
extends ACAPropertyFeature
## ROLE
## Ground on the contract that the customer does not want cut: a wildflower
## meadow, a pollinator strip, a bank of long grass round the pond.
##
## ---------------------------------------------------------------------------
## IT IS NOT AN OBSTACLE
## ---------------------------------------------------------------------------
## Every other thing on a lawn that is not lawn stops the machine or cannot be
## reached. This can be driven straight through. That is the whole of the
## challenge: the ground is available, the blades will cut it, and the player is
## being asked not to.
##
## So it is deliberately NOT solid, owes the deck no clearance, and builds no
## collision. What it answers instead is `is_protected_vegetation()`, and
## `ACALawn` does the rest: a protected cell is swept by the deck exactly as a
## lawn cell is, and what it records is DAMAGE rather than progress.
##
## ---------------------------------------------------------------------------
## IT NEVER MAKES A CONTRACT UNFINISHABLE
## ---------------------------------------------------------------------------
## A protected cell is excluded from `total_item_count()` like any other
## excluded ground, so a property with two meadows on it still finishes at
## exactly 100% - and the player is never asked to mow the thing they are being
## asked not to mow. That falls straight out of the existing feature interface;
## not one line of the mowing core knows this class exists.
##
## PUBLIC API
##   ACAConservationZone.for_params(params, lawn_centre, existing)
##   zones() -> [{ position, radius, squash, yaw, kind }]
##   count() / total_area() -> float
##   kind_name(kind) / description() -> String
##   plus the whole ACAPropertyFeature interface
##
## SIGNALS: None.
##
## INVARIANTS
##   * Placement is a pure function of the property seed and the archetype, so a
##     resumed contract rebuilds the same meadows in the same places.
##   * `terrain_offset_at()` is always zero. A meadow is planting, not a hole.
##   * Never inside the arrival corridor, and never against another feature: a
##     player who is told not to cut something must be able to see it coming.
##
## PERSISTENCE OWNERSHIP
##   None. Rebuilt from ACAPropertyParams like every other feature. The DAMAGE
##   belongs to `ACALawn`, which is where the rest of the cut state lives.

enum Kind { WILDFLOWER, POLLINATOR_STRIP, LONG_GRASS_ISLAND }

const KIND_NAMES := {
	Kind.WILDFLOWER: "Wildflower meadow",
	Kind.POLLINATOR_STRIP: "Pollinator strip",
	Kind.LONG_GRASS_ISLAND: "Long-grass island",
}

## WHICH KINDS OF PROPERTY HAVE THESE, and how many.
##
## A rural roadside and a public green plausibly have habitat set aside on them;
## a suburban back garden does not, and a hotel forecourt certainly does not. The
## gate is the ARCHETYPE rather than the property type, because the archetype is
## what the property generator already knows and is the same derivation the
## surrounds and the beds are gated on.
##
##   `chance`  how many properties of this kind get any zone at all.
##   `count`   how many zones, when one is rolled.
##   `radius`  the size of one, in world units.
const PLANS := {
	ACAPropertyArchetype.Kind.RURAL: {
		"chance": 0.34, "count": Vector2i(1, 2), "radius": Vector2(11.0, 19.0),
	},
	ACAPropertyArchetype.Kind.PARK: {
		"chance": 0.46, "count": Vector2i(1, 3), "radius": Vector2(9.0, 17.0),
	},
	ACAPropertyArchetype.Kind.LANDSCAPED: {
		"chance": 0.16, "count": Vector2i(1, 1), "radius": Vector2(8.0, 13.0),
	},
}

## Clear ground round the arrival point. A contract that opens with the machine
## standing in the thing it must not cut is a contract that has already failed.
const SPAWN_CLEAR := 24.0
## ...and the corridor it drives up from there.
const ARRIVAL_CORRIDOR := 12.0
## How far in from the lawn edge a zone sits, measured to its rim. Generous:
## a strip jammed against the fence turns the last perimeter pass into a trap.
const EDGE_INSET := 9.0
## Clear ground between a zone and anything else already on the property, and
## between two zones. Wider than the widest machine, so there is always a
## mowable lane between a meadow and whatever is next to it.
const SEPARATION := 12.0
const FEATURE_CLEAR := 6.0

const MAX_ATTEMPTS := 260

## Tufts planted per square world unit of meadow. The zone draws itself with the
## lawn's own tuft mesh and the lawn's own shader, which is what lets it react to
## being driven over without a line of new rendering code.
##
## DENSER AND TALLER THAN THE LAWN, and both were raised after the first render:
## at 0.55 tufts and 1.34 height a meadow read as a slightly darker patch of
## lawn from above, and a conservation objective the player cannot SEE is a trap
## rather than a challenge.
const TUFTS_PER_UNIT := 1.15
## How much taller a meadow tuft stands than kept lawn.
const MEADOW_HEIGHT := 2.1
## Flower heads per square unit, on the kinds that have them. Raised with the
## rest: the flowers are the only thing in the zone that is a COLOUR rather than
## a shade of the same green, and they are what carries it at fifty units.
const FLOWERS_PER_UNIT := 0.55
## How big a flower head is, in world units. This world is about four times life
## size, so this is a head a couple of centimetres across.
const FLOWER_RADIUS := 0.26

## The flower colours. Three, seeded per zone, so one meadow is not the same as
## the next and none of them is a rainbow.
const FLOWER_PALETTES := [
	[Color(0.878, 0.812, 0.361), Color(0.933, 0.898, 0.812)],
	[Color(0.741, 0.494, 0.702), Color(0.878, 0.784, 0.882)],
	[Color(0.914, 0.573, 0.310), Color(0.949, 0.827, 0.545)],
]

## The meadow's own tint, applied to the shared grass material so a protected
## strip reads as a different plant from the lawn beside it before the player
## has been told anything.
## PUSHED FURTHER FROM THE LAWN'S OWN GREEN than the first version's, for the
## same reason the density was: the boundary of a protected area has to be
## visible from the seat of a machine crossing the property.
const MEADOW_BASE := Color(0.243, 0.302, 0.106)
const MEADOW_TIP := Color(0.612, 0.639, 0.267)

var _zones: Array[Dictionary] = []
var _bounds := AABB()
var _nodes := 0


## THE constructor. `existing` is the feature set as it stands - the pond, the
## obstacles and the beds - so a meadow is never laid over ground another
## feature has already claimed.
##
## Returns a zone with nothing in it on the great majority of properties, and
## `ACAProperty` simply does not add it. That is the common path and it costs a
## single random draw.
static func for_params(params: ACAPropertyParams, lawn_centre: Vector2,
		existing: ACAFeatureSet = null) -> ACAConservationZone:
	var f := ACAConservationZone.new()
	f._roll(params, lawn_centre, existing)
	return f


## WILL THIS PROPERTY HAVE PROTECTED GROUND ON IT? Pure, cheap, and answerable
## without generating a property.
##
## It is the FIRST DRAW of the same stream `_roll()` takes, against the same
## gates, so it can never disagree with the real answer about whether a zone
## exists - only about how many and where, which it does not claim to know.
##
## This is what lets a work order warn the player about conservation ground
## before they accept the contract, without the job board building a property.
static func likely_present(property_seed: int, archetype_kind: int,
		lawn_size_units: int) -> bool:
	if not PLANS.has(archetype_kind):
		return false
	if float(lawn_size_units) * 0.5 - EDGE_INSET <= 16.0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(property_seed, 73310))
	return rng.randf() < float(PLANS[archetype_kind]["chance"])


## The same question asked of a contract, which is how everything outside the
## property generator asks it.
static func likely_for_job(job: ACAJob) -> bool:
	if job == null:
		return false
	var size: int = job.grid_size.x if job.grid_size.x > 0 else 96
	return likely_present(job.seed,
		ACAPropertyArchetype.for_property_type(job.property_type, job.seed), size)


func feature_id() -> StringName:
	return &"conservation"


func count() -> int:
	return _zones.size()


func zones() -> Array[Dictionary]:
	return _zones.duplicate(true)


static func kind_name(kind: int) -> String:
	return String(KIND_NAMES.get(kind, "Protected planting"))


## What the work order says about this property's protected ground.
func description() -> String:
	if _zones.is_empty():
		return ""
	var names := {}
	for zone: Dictionary in _zones:
		names[kind_name(int(zone["kind"]))] = true
	var parts := PackedStringArray()
	for name: String in names:
		parts.append(name.to_lower())
	if _zones.size() == 1:
		return "One %s. Do not cut it." % parts[0]
	return "%d protected areas - %s. Do not cut them." % [
		_zones.size(), " and ".join(parts)]


## Total protected area in square world units. Diagnostic; the LAWN's own
## `protected_cell_count()` is what scoring uses, because that is the number
## measured against the ground that actually exists.
func total_area() -> float:
	var total := 0.0
	for zone: Dictionary in _zones:
		var r: float = float(zone["radius"])
		total += PI * r * r * float(zone["squash"])
	return total


# ==================================================================== rolling

func _roll(params: ACAPropertyParams, lawn_centre: Vector2,
		existing: ACAFeatureSet) -> void:
	# NOT ON A PROPERTY GENERATED BEFORE THIS EXISTED. A contract already in
	# progress would have its completion denominator moved underneath it, and a
	# save is a promise about the ground the player is standing on.
	if params.generation_version < 5:
		return
	if not PLANS.has(params.archetype):
		return
	var plan: Dictionary = PLANS[params.archetype]
	var half := params.lawn_half_extent()
	var usable := half - EDGE_INSET
	if usable <= 16.0:
		return

	# A SEPARATE stream, exactly like the obstacles' and the beds'. Conservation
	# zones could be added without moving a single existing draw in
	# `ACAPropertyParams.for_seed()`, so every property in every save keeps the
	# terrain, wood, pond, rocks and beds it already had.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(params.seed, 73310))

	if rng.randf() >= float(plan["chance"]):
		return

	var count_range: Vector2i = plan["count"]
	var wanted := rng.randi_range(count_range.x, count_range.y)
	var radius_range: Vector2 = plan["radius"]
	var arrival := Vector2(lawn_centre.x - half, lawn_centre.y)

	var attempts := 0
	while _zones.size() < wanted and attempts < MAX_ATTEMPTS:
		attempts += 1
		var radius := rng.randf_range(radius_range.x, radius_range.y)
		var reach: float = usable - radius
		if reach <= 0.0:
			break
		var at := lawn_centre + Vector2(
			rng.randf_range(-1.0, 1.0) * reach, rng.randf_range(-1.0, 1.0) * reach)
		if not _acceptable(at, radius, arrival, lawn_centre, existing):
			continue
		var kind: int = Kind.WILDFLOWER
		var squash := rng.randf_range(0.62, 1.0)
		var roll := rng.randf()
		if roll < 0.28:
			# A STRIP rather than a patch: long, narrow, and laid along an axis.
			kind = Kind.POLLINATOR_STRIP
			squash = rng.randf_range(0.24, 0.36)
		elif roll < 0.46:
			kind = Kind.LONG_GRASS_ISLAND
		_zones.append({
			"position": at,
			"radius": radius,
			"squash": squash,
			"yaw": rng.randf_range(0.0, PI),
			"kind": kind,
			"palette": rng.randi() % FLOWER_PALETTES.size(),
			"pick": rng.randi(),
		})
	_recompute_bounds()


func _acceptable(at: Vector2, radius: float, arrival: Vector2,
		lawn_centre: Vector2, existing: ACAFeatureSet) -> bool:
	if at.distance_to(arrival) < SPAWN_CLEAR + radius:
		return false
	if absf(at.y - arrival.y) < ARRIVAL_CORRIDOR + radius and at.x < lawn_centre.x:
		return false
	# GROUND ANOTHER FEATURE HAS ALREADY TAKEN, asked for through the interface
	# so this class never learns what the other features are.
	#
	# AGAINST EACH FEATURE'S REAL FOOTPRINTS, not against the box around them.
	# The first version of this tested `bounds()`, and on a park property - a
	# pond, a dozen lawn rocks and half a dozen beds, each with a combined
	# bounding box covering most of the lawn - it rejected every candidate: 88
	# of 89 seeds that should have had a meadow generated without one. The
	# measurement is in the pass notes.
	if existing != null:
		for f in existing.features():
			if f == self or not f.blocks_mowing():
				continue
			if not _clear_of(f, at, radius):
				return false
	for other: Dictionary in _zones:
		var gap: float = at.distance_to(other["position"] as Vector2) \
			- radius - float(other["radius"])
		if gap < SEPARATION:
			return false
	return true


## Is a zone of this size at this point clear of everything one other feature
## occupies? A feature that reports no footprints is ONE thing and its bounds
## are the honest answer for it; anything else is tested circle by circle.
static func _clear_of(feature: ACAPropertyFeature, at: Vector2,
		radius: float) -> bool:
	var items := feature.footprints()
	if items.is_empty():
		var b := feature.bounds()
		var rect := Rect2(Vector2(b.position.x, b.position.z),
			Vector2(b.size.x, b.size.z)).grow(radius + FEATURE_CLEAR)
		return not rect.has_point(at)
	for item: Dictionary in items:
		var gap: float = at.distance_to(item["position"] as Vector2) \
			- radius - float(item.get("radius", 1.0))
		if gap < FEATURE_CLEAR:
			return false
	return true


func _recompute_bounds() -> void:
	if _zones.is_empty():
		_bounds = AABB()
		return
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for zone: Dictionary in _zones:
		var at: Vector2 = zone["position"]
		var r: float = float(zone["radius"])
		min_x = minf(min_x, at.x - r)
		min_z = minf(min_z, at.y - r)
		max_x = maxf(max_x, at.x + r)
		max_z = maxf(max_z, at.y + r)
	_bounds = AABB(Vector3(min_x, -400.0, min_z),
		Vector3(max_x - min_x, 800.0, max_z - min_z))


# ================================================================== interface

func bounds() -> AABB:
	return _bounds


## A meadow does not dig the ground it stands on.
func terrain_offset_at(_x: float, _z: float) -> float:
	return 0.0


## THE POINT OF THIS CLASS, twice over. It is not solid - the machine drives
## through it - and it IS protected, which is what tells the lawn to record what
## the deck did there instead of counting it.
func is_solid() -> bool:
	return false


func is_protected_vegetation() -> bool:
	return true


## Protected ground is out of the contract, keeps the lawn's own grass off, and
## keeps scenery off - the zone plants its own.
func blocks_mowing() -> bool:
	return true


func blocks_grass() -> bool:
	return true


func blocks_foliage() -> bool:
	return true


## A hard-edged oval, like a bed. There is no fade: a boundary the player is
## going to be judged against has to be somewhere exact.
func exclusion_at(x: float, z: float, _ground_y: float) -> float:
	var point := Vector2(x, z)
	for zone: Dictionary in _zones:
		var local := (point - (zone["position"] as Vector2)).rotated(-float(zone["yaw"]))
		local.y /= maxf(float(zone["squash"]), 0.05)
		var r: float = float(zone["radius"])
		if local.length_squared() <= r * r:
			return 1.0
	return 0.0


# ====================================================================== nodes

## THE PLANTING, drawn with the lawn's own tuft mesh and the lawn's own shader.
##
## That is not a shortcut: it is what makes a meadow react to being driven
## through. The grass shader shortens and lays over any tuft whose cell reads
## CUT in the lawn mask, and `ACALawn._damage_cell()` writes exactly that bit
## when the deck goes over protected ground. So a strip the player has mown
## through visibly IS mown, through the bridge the lawn already had, with no
## per-instance update and nothing new on the frame path.
func build_nodes(parent: Node3D, terrain: Node3D, params: ACAPropertyParams) -> void:
	if parent == null or _zones.is_empty():
		return
	var root := Node3D.new()
	root.name = "Conservation"
	parent.add_child(root)

	var lawn := _find_lawn(parent)
	var material := _meadow_material(params, lawn)
	var mesh := ACAGrassMesh.near_tuft()
	var rng := RandomNumberGenerator.new()

	for i in _zones.size():
		var zone: Dictionary = _zones[i]
		rng.seed = hash(Vector2i(int(zone["pick"]), 9931))
		_plant_zone(root, terrain, zone, i, mesh, material, rng)


func _plant_zone(root: Node3D, terrain: Node3D, zone: Dictionary, index: int,
		mesh: Mesh, material: Material, rng: RandomNumberGenerator) -> void:
	var at: Vector2 = zone["position"]
	var radius: float = float(zone["radius"])
	var squash: float = float(zone["squash"])
	var yaw: float = float(zone["yaw"])
	var area: float = PI * radius * radius * squash
	var wanted: int = clampi(int(round(area * TUFTS_PER_UNIT)), 24, 5200)

	var transforms := PackedFloat32Array()
	var customs := PackedColorArray()
	for _tuft in wanted:
		var angle := rng.randf_range(0.0, TAU)
		var distance: float = sqrt(rng.randf()) * radius
		var local := Vector2(cos(angle) * distance, sin(angle) * distance * squash)
		var point := at + local.rotated(yaw)
		var ground := _ground_at(terrain, point)
		var height: float = MEADOW_HEIGHT * rng.randf_range(0.82, 1.22)
		var spread: float = rng.randf_range(1.0, 1.45)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
			Vector3(spread, height, spread))
		_append(transforms, Transform3D(basis, Vector3(point.x, ground - 0.02, point.y)))
		# INSTANCE_CUSTOM, as the lawn's grass uses it: x colour drift, y height
		# multiplier, z wind phase, w the meadow flag. The meadow flag is on,
		# which is what makes these tufts move and shade as wild grass.
		customs.append(Color(rng.randf(), height, rng.randf(), 1.0))
	_commit(root, mesh, material, transforms, customs, "Meadow %d" % index)

	if int(zone["kind"]) == Kind.LONG_GRASS_ISLAND:
		return
	_plant_flowers(root, terrain, zone, index, rng, area)


## The flower heads. Small unshaded quadrics on stems, batched per colour, and
## deliberately NOT part of the grass material: they are the one thing on the
## property that has to read as colour at fifty units, and a wildflower meadow
## the player cannot pick out from the lawn is a trap rather than an objective.
func _plant_flowers(root: Node3D, terrain: Node3D, zone: Dictionary,
		index: int, rng: RandomNumberGenerator, area: float) -> void:
	var palette: Array = FLOWER_PALETTES[int(zone["palette"]) % FLOWER_PALETTES.size()]
	var at: Vector2 = zone["position"]
	var radius: float = float(zone["radius"])
	var squash: float = float(zone["squash"])
	var yaw: float = float(zone["yaw"])
	var wanted: int = clampi(int(round(area * FLOWERS_PER_UNIT)), 12, 1400)

	var head := SphereMesh.new()
	head.radius = FLOWER_RADIUS
	head.height = FLOWER_RADIUS * 1.4
	head.radial_segments = 6
	head.rings = 3

	for colour_index in palette.size():
		var transforms := PackedFloat32Array()
		var share: int = wanted / palette.size()
		for _flower in share:
			var angle := rng.randf_range(0.0, TAU)
			var distance: float = sqrt(rng.randf()) * radius * 0.94
			var local := Vector2(cos(angle) * distance, sin(angle) * distance * squash)
			var point := at + local.rotated(yaw)
			var ground := _ground_at(terrain, point)
			var lift: float = MEADOW_HEIGHT * rng.randf_range(0.72, 1.02)
			var scale := rng.randf_range(0.85, 1.3)
			_append(transforms, Transform3D(
				Basis().scaled(Vector3(scale, scale, scale)),
				Vector3(point.x, ground + lift, point.y)))
		if transforms.is_empty():
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = palette[colour_index]
		material.roughness = 0.92
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_commit(root, head, material, transforms, PackedColorArray(),
			"Flowers %d-%d" % [index, colour_index])


## The lawn's grass material, re-tinted. Sharing the SHADER and the lawn mask is
## the whole trick; only the colours differ.
func _meadow_material(params: ACAPropertyParams, lawn: ACALawn) -> Material:
	var shader := load("res://Mowing Section/Property/shaders/aca_grass.gdshader") as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if lawn != null:
		var centre := lawn.lawn_centre()
		mat.set_shader_parameter("lawn_mask", lawn.cut_mask())
		mat.set_shader_parameter("lawn_centre", Vector2(centre.x, centre.z))
		mat.set_shader_parameter("lawn_size", lawn.lawn_half_extent() * 2.0)
	mat.set_shader_parameter("wind_direction", params.wind_direction)
	mat.set_shader_parameter("wind_speed", params.wind_speed)
	mat.set_shader_parameter("dryness", params.dryness * 0.6)
	mat.set_shader_parameter("colour_bias", params.lawn_colour_bias)
	mat.set_shader_parameter("base_colour", MEADOW_BASE)
	mat.set_shader_parameter("tip_colour", MEADOW_TIP)
	mat.set_shader_parameter("meadow_tip", MEADOW_TIP)
	return mat


## ---------------------------------------------------------------------------
## THE BUFFER IS INTERLEAVED WHEN THERE IS CUSTOM DATA
## ---------------------------------------------------------------------------
## A `MultiMesh` with `use_custom_data` reads SIXTEEN floats per instance -
## twelve of transform and four of custom - out of one flat buffer. The first
## version of this handed it twelve, and the render showed exactly what that
## does: the meadow came out as a scrambled sheet of texture lying flat in the
## middle of the property, because every instance after the first read its
## transform out of the previous one's data.
##
## `ACALawnGrass._add_layer()` interleaves for the same reason and this follows
## it deliberately - the two are drawing the same tuft with the same shader, and
## a second way of packing the same buffer is a second thing to get wrong.
func _commit(parent: Node3D, mesh: Mesh, material: Material,
		transforms: PackedFloat32Array, customs: PackedColorArray,
		node_name: String) -> void:
	var count := transforms.size() / 12
	if count <= 0 or mesh == null:
		return
	var with_custom := customs.size() >= count
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = with_custom
	multimesh.mesh = mesh
	multimesh.instance_count = count
	if with_custom:
		var buffer := PackedFloat32Array()
		buffer.resize(count * 16)
		for i in count:
			var t := i * 12
			var w := i * 16
			for k in 12:
				buffer[w + k] = transforms[t + k]
			var c := customs[i]
			buffer[w + 12] = c.r
			buffer[w + 13] = c.g
			buffer[w + 14] = c.b
			buffer[w + 15] = c.a
		multimesh.buffer = buffer
	else:
		multimesh.buffer = transforms

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	if material != null:
		instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 3.0
	parent.add_child(instance)
	_nodes += 1


static func _ground_at(terrain: Node3D, point: Vector2) -> float:
	if terrain != null and terrain.has_method(&"height_at"):
		return float(terrain.call(&"height_at", point.x, point.y))
	return 0.0


## The lawn is a sibling under the property root by the time features build
## their nodes. Asked for by TYPE rather than by name, so renaming the node
## cannot quietly leave the meadow with no mask to read.
static func _find_lawn(parent: Node3D) -> ACALawn:
	if parent == null:
		return null
	if parent.has_method(&"lawn"):
		var found: Variant = parent.call(&"lawn")
		if found is ACALawn:
			return found
	for child in parent.get_children():
		if child is ACALawn:
			return child
	return null


static func _append(into: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	var o := t.origin
	into.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x,
		b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z,
	]))
