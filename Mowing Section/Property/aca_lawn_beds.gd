class_name ACALawnBeds
extends ACAPropertyFeature
## ROLE
## The planted beds on a contract: mulched ground with shrubs in it, that a
## contractor mows AROUND rather than through.
##
## ---------------------------------------------------------------------------
## THE FIRST FEATURE THAT IS NOT SOLID
## ---------------------------------------------------------------------------
## A rock stops the machine. A pond stops the machine. A garden bed does not -
## you simply do not drive over it, and nothing in the world prevents you.
##
## That is exactly the distinction `ACAPropertyFeature.is_solid()` was added
## for, and this is the feature that proves it earns its place: a bed answers
## FALSE, so it owes the deck no clearance band and its exclusion is its own
## outline and nothing more. The mower can put its deck right up to the mulch,
## which is what a real operator does.
##
## The consequences fall out of the existing architecture with no new rules:
##
##   * bedded ground stops counting towards completion, so a property with beds
##     still finishes at exactly 100%;
##   * no lawn grass grows in a bed;
##   * no scenery is scattered on one, because the bed plants its own;
##   * and there is NO collision body, anywhere, for any of them.
##
## ---------------------------------------------------------------------------
## WHERE THEY GO, AND WHY THAT IS PER ARCHETYPE
## ---------------------------------------------------------------------------
## A rural contract has none: a field does not have planting in it. The other
## three do, and they have DIFFERENT planting, because that is a large part of
## what makes the four kinds of place read differently from the seat:
##
##   suburban    one or two small beds, tucked against an edge, near the house
##   park        three to five large informal beds out in the open grass - the
##               most of any archetype, because a park has nothing beyond its
##               fence to tell the player what it is
##   landscaped  three to five smaller ones, the tidiest of the three
##
## PUBLIC API
##   ACALawnBeds.for_params(params, lawn_centre, existing)
##   beds()  -> [{ position: Vector2, radius: float, squash: float, yaw: float }]
##   count()
##   plus the whole ACAPropertyFeature interface
##
## SIGNALS: None.
##
## INVARIANTS
##   * Placement is a pure function of the property seed, lawn size and
##     archetype, so a resumed contract rebuilds the same beds.
##   * `terrain_offset_at()` is always zero. A bed is level with the lawn.
##   * `is_solid()` is FALSE and must stay false. A bed the machine cannot drive
##     through is a rock, and belongs in `ACALawnObstacles` instead.
##
## PERSISTENCE OWNERSHIP
##   None. Rebuilt from ACAPropertyParams like every other feature.

## The shrubs a bed is planted with. The same pack the treeline and the lawn
## obstacles use, so a bed's planting is recognisably the same plant life.
const SHRUB_SOURCES := [
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_1_A_Color1.gltf", "height": 2.1},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_1_C_Color1.gltf", "height": 1.8},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_3_A_Color1.gltf", "height": 2.4},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_4_A_Color1.gltf", "height": 2.0},
]

## Bark mulch. Warm and dark, so a bed reads as worked ground against the lawn
## rather than as a patch of dead grass.
const MULCH_COLOUR := Color(0.278, 0.196, 0.129)
const SHRUB_TINT := Color(0.82, 0.94, 0.70)

## How many beds each kind of place gets, and how big they are in world units.
## A world unit is about a quarter of a metre, so a radius of six is a bed about
## three metres across.
const PLANS := {
	ACAPropertyArchetype.Kind.SUBURBAN: {
		"count": Vector2i(1, 2), "radius": Vector2(4.5, 7.5), "edge_bias": 0.78,
	},
	# PARK GETS THE MOST AND THE LARGEST. Out of the four kinds of place it is
	# the one whose identity lives on the lawn rather than beyond the fence -
	# it has no buildings around it, so the planting IS the difference between a
	# public green and a field. The sixteen-property review showed park and rural
	# reading almost the same from above with two small beds on one of them.
	ACAPropertyArchetype.Kind.PARK: {
		"count": Vector2i(3, 5), "radius": Vector2(7.5, 13.0), "edge_bias": 0.35,
	},
	ACAPropertyArchetype.Kind.LANDSCAPED: {
		"count": Vector2i(3, 5), "radius": Vector2(5.0, 9.0), "edge_bias": 0.62,
	},
}

## How far in from the lawn edge a bed's rim must sit. Smaller than the
## obstacles' inset, because a bed against an edge is where a bed usually is.
const EDGE_INSET := 5.0
## Clear ground around the arrival point, so a contract never opens with the
## machine parked in a flowerbed.
const SPAWN_CLEAR := 18.0
## Gap left between one bed and anything else on the lawn, rim to rim. Wider
## than the widest machine, so the grass between two beds is always mowable.
const SEPARATION := 9.0
## How much clear ground is left around a pond or an obstacle.
const FEATURE_CLEAR := 5.0

const MAX_ATTEMPTS := 220
## How many shrubs go in a bed, per unit of its radius. Raised from 0.55 after
## the review: a large park bed at that rate came out as seven shrubs scattered
## over three metres of bare mulch, which reads as a bed nobody has finished.
const SHRUBS_PER_UNIT := 0.95

var _beds: Array[Dictionary] = []
var _bounds := AABB()
var _nodes := 0


## THE constructor. `existing` is the feature set as it stands - the pond and
## the lawn obstacles - so a bed is never planted on ground already claimed.
static func for_params(params: ACAPropertyParams, lawn_centre: Vector2,
		existing: ACAFeatureSet = null) -> ACALawnBeds:
	var f := ACALawnBeds.new()
	f._roll(params, lawn_centre, existing)
	return f


func feature_id() -> StringName:
	return &"lawn_beds"


func count() -> int:
	return _beds.size()


func beds() -> Array[Dictionary]:
	return _beds.duplicate(true)


# ==================================================================== rolling

func _roll(params: ACAPropertyParams, lawn_centre: Vector2,
		existing: ACAFeatureSet) -> void:
	if not PLANS.has(params.archetype):
		return
	var plan: Dictionary = PLANS[params.archetype]
	var half := params.lawn_half_extent()
	var usable := half - EDGE_INSET
	if usable <= 12.0:
		return

	# A SEPARATE stream, like the obstacles'. Beds could be added without moving
	# a single existing draw in `ACAPropertyParams.for_seed()`.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(params.seed, 62114))

	var range_count: Vector2i = plan["count"]
	var wanted := rng.randi_range(range_count.x, range_count.y)
	var radius_range: Vector2 = plan["radius"]
	var edge_bias: float = float(plan["edge_bias"])
	var arrival := Vector2(lawn_centre.x - half, lawn_centre.y)

	var attempts := 0
	while _beds.size() < wanted and attempts < MAX_ATTEMPTS:
		attempts += 1
		var radius := rng.randf_range(radius_range.x, radius_range.y)
		# `edge_bias` pulls a bed towards the perimeter without pinning it to
		# one: a suburban bed hugs a fence, a park bed sits out in the grass.
		var reach: float = usable - radius
		var at := lawn_centre + Vector2(
			_biased(rng, edge_bias) * reach, _biased(rng, edge_bias) * reach)
		if not _acceptable(at, radius, arrival, existing):
			continue
		_beds.append({
			"position": at,
			"radius": radius,
			# Beds are ovals rather than circles, and rotated, so five of them
			# on one lawn are not five identical discs.
			"squash": rng.randf_range(0.55, 1.0),
			"yaw": rng.randf_range(0.0, PI),
			"pick": rng.randi(),
		})
	_recompute_bounds()


## A value in -1..1 pushed towards the ends by `bias`. Zero is uniform; one puts
## everything against the perimeter.
func _biased(rng: RandomNumberGenerator, bias: float) -> float:
	var raw := rng.randf_range(-1.0, 1.0)
	var pushed: float = signf(raw) * pow(absf(raw), lerpf(1.0, 0.45, clampf(bias, 0.0, 1.0)))
	return pushed


func _acceptable(at: Vector2, radius: float, arrival: Vector2,
		existing: ACAFeatureSet) -> bool:
	if at.distance_to(arrival) < SPAWN_CLEAR + radius:
		return false
	if existing != null:
		for f in existing.features():
			if f == self:
				continue
			var b := f.bounds()
			var rect := Rect2(Vector2(b.position.x, b.position.z),
				Vector2(b.size.x, b.size.z)).grow(radius + FEATURE_CLEAR)
			if rect.has_point(at):
				return false
	for other: Dictionary in _beds:
		var gap: float = at.distance_to(other["position"] as Vector2) \
			- radius - float(other["radius"])
		if gap < SEPARATION:
			return false
	return true


func _recompute_bounds() -> void:
	if _beds.is_empty():
		_bounds = AABB()
		return
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for b: Dictionary in _beds:
		var at: Vector2 = b["position"]
		var r: float = float(b["radius"])
		min_x = minf(min_x, at.x - r)
		min_z = minf(min_z, at.y - r)
		max_x = maxf(max_x, at.x + r)
		max_z = maxf(max_z, at.y + r)
	_bounds = AABB(Vector3(min_x, -400.0, min_z),
		Vector3(max_x - min_x, 800.0, max_z - min_z))


# ================================================================== interface

func bounds() -> AABB:
	return _bounds


## Beds are level with the lawn. They are mulch on the ground, not a raised box.
func terrain_offset_at(_x: float, _z: float) -> float:
	return 0.0


## THE POINT OF THIS CLASS. The machine drives over a bed perfectly happily;
## a contractor simply does not. So no clearance is owed and no collision is
## built - see the note at the top of the file.
func is_solid() -> bool:
	return false


## A hard oval. There is no fade: mulch either starts or it does not.
func exclusion_at(x: float, z: float, _ground_y: float) -> float:
	var point := Vector2(x, z)
	for b: Dictionary in _beds:
		var local := (point - (b["position"] as Vector2)).rotated(-float(b["yaw"]))
		local.y /= maxf(float(b["squash"]), 0.05)
		var r: float = float(b["radius"])
		if local.length_squared() <= r * r:
			return 1.0
	return 0.0


# ====================================================================== nodes

## One flat mulch disc per bed, plus one MultiMesh per shrub source for
## everything planted in all of them. NO physics bodies: see `is_solid()`.
func build_nodes(parent: Node3D, terrain: Node3D, _params: ACAPropertyParams) -> void:
	if parent == null or _beds.is_empty():
		return
	var shrubs := _prepare(SHRUB_SOURCES)
	var rng := RandomNumberGenerator.new()
	var batches: Dictionary = {}

	for i in _beds.size():
		var bed: Dictionary = _beds[i]
		_build_mulch(parent, terrain, bed, i)
		if shrubs.is_empty():
			continue
		rng.seed = hash(Vector2i(int(bed["pick"]), 4177))
		var radius: float = float(bed["radius"])
		var squash: float = float(bed["squash"])
		var planted: int = maxi(int(round(radius * SHRUBS_PER_UNIT)), 2)
		for _shrub in planted:
			# Inside the oval, and not right on its rim, so no shrub hangs over
			# the mulch edge on to the grass.
			var angle := rng.randf_range(0.0, TAU)
			var distance: float = sqrt(rng.randf()) * radius * 0.74
			var local := Vector2(cos(angle) * distance, sin(angle) * distance * squash)
			var at: Vector2 = (bed["position"] as Vector2) + local.rotated(float(bed["yaw"]))
			var ground: float = float(terrain.call(&"height_at", at.x, at.y)) \
				if terrain != null and terrain.has_method(&"height_at") else 0.0
			var pick: int = rng.randi() % shrubs.size()
			var source: Dictionary = shrubs[pick]
			var scale: float = float(source["scale"]) * rng.randf_range(0.75, 1.2)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) \
				.scaled(Vector3(scale, scale, scale))
			var key := str(pick)
			if not batches.has(key):
				batches[key] = {"mesh": source["mesh"], "transforms": PackedFloat32Array()}
			_append(batches[key]["transforms"],
				Transform3D(basis, Vector3(at.x, ground - 0.12, at.y)))

	for key in batches:
		_commit(parent, batches[key]["mesh"], batches[key]["transforms"])


## The mulch itself: a squashed, rotated disc laid on the ground.
##
## A MESH RATHER THAN A DECAL. A decal projects on to whatever is under it and
## would take the grass with it; the ground here has no grass on it at all,
## because the exclusion already removed it, so what is wanted is a surface.
func _build_mulch(parent: Node3D, terrain: Node3D, bed: Dictionary,
		index: int) -> void:
	var at: Vector2 = bed["position"]
	var radius: float = float(bed["radius"])
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	# Shallow rather than flat: a plane exactly on the terrain fights it for
	# depth, and a bed is genuinely a little proud of a lawn anyway.
	mesh.height = 0.34
	mesh.radial_segments = 18
	mesh.rings = 1

	var material := StandardMaterial3D.new()
	material.albedo_color = MULCH_COLOUR
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var instance := MeshInstance3D.new()
	instance.name = "Bed %d" % index
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	var ground: float = float(terrain.call(&"height_at", at.x, at.y)) \
		if terrain != null and terrain.has_method(&"height_at") else 0.0
	instance.transform = Transform3D(
		Basis(Vector3.UP, float(bed["yaw"])).scaled(
			Vector3(1.0, 1.0, maxf(float(bed["squash"]), 0.05))),
		Vector3(at.x, ground - 0.10, at.y))


func _prepare(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		var mesh := _load_mesh(String(entry["path"]))
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		out.append({
			"mesh": mesh,
			"scale": float(entry["height"]) / maxf(aabb.size.y, 0.001),
		})
	return out


func _commit(parent: Node3D, mesh: Mesh, transforms: PackedFloat32Array) -> void:
	var count := transforms.size() / 12
	if count <= 0:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.buffer = transforms

	var instance := MultiMeshInstance3D.new()
	instance.name = "Bed Planting %d" % _nodes
	instance.multimesh = multimesh
	instance.material_override = _tinted(mesh, SHRUB_TINT)
	instance.extra_cull_margin = 3.0
	parent.add_child(instance)
	_nodes += 1


## A COPY of the mesh's own imported material with its albedo multiplied - the
## same treatment `ACAForest` and `ACALawnObstacles` give their instances, and
## for the same reason: these meshes share a texture atlas, and replacing their
## material with a plain colour throws the atlas away.
static func _tinted(mesh: Mesh, tint: Color) -> Material:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var source := mesh.surface_get_material(0) as BaseMaterial3D
	if source == null:
		return null
	var copy := source.duplicate() as BaseMaterial3D
	copy.albedo_color = Color(
		source.albedo_color.r * tint.r,
		source.albedo_color.g * tint.g,
		source.albedo_color.b * tint.b,
		source.albedo_color.a)
	return copy


static func _load_mesh(path: String) -> Mesh:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[BEDS] could not load %s" % path)
		return null
	var instance := packed.instantiate()
	var mesh := _first_mesh(instance)
	instance.free()
	return mesh


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


static func _append(into: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	var o := t.origin
	into.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x,
		b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z,
	]))
