class_name ACALawnObstacles
extends ACAPropertyFeature
## ROLE
## The solid things standing ON the contract: lawn rocks and the odd stubborn
## shrub clump the owner has clearly mown around for years.
##
## ---------------------------------------------------------------------------
## WHY THIS IS ONE FEATURE AND NOT MANY
## ---------------------------------------------------------------------------
## A property gets between three and a dozen obstacles. As individual features
## that would be a dozen entries in `ACAFeatureSet`, a dozen broad-phase
## rectangles tested per grass tuft, and a dozen physics bodies. As ONE feature
## holding a list, it is one entry, one rectangle around the whole set, and one
## static body carrying a sphere per obstacle.
##
## ---------------------------------------------------------------------------
## WHAT AN OBSTACLE DOES
## ---------------------------------------------------------------------------
## Everything the pond already does, through the same interface:
##
##   * the ground under it stops counting towards completion, so the contract is
##     still finishable at exactly 100% without a single obstacle-specific rule
##     in the mowing code;
##   * no lawn grass grows through it;
##   * no scenery is placed on top of it;
##   * and it is SOLID - the machine hits it.
##
## It does NOT dig the terrain. A rock sits on the ground; it does not deform it.
##
## ---------------------------------------------------------------------------
## PLACEMENT IS A ROUTE-PLANNING PROBLEM
## ---------------------------------------------------------------------------
## Obstacles exist to make a lawn worth thinking about, not to make it a maze.
## Every one of the rules in `_roll()` is there because breaking it produces a
## property that is either unfair or dull:
##
##   * inset from the lawn edge, so the last pass round the perimeter is never
##     jammed between a rock and the fence;
##   * clear of the arrival corridor, so a contract never begins with the
##     machine nose-first into a boulder;
##   * clear of the pond and its bank, which the pond has already claimed;
##   * and separated from each other by MORE than the widest deck in the game,
##     so there is never a gap the player can see but not drive through.
##
## PUBLIC API
##   ACALawnObstacles.for_params(params, lawn_centre, existing_features)
##   obstacles()      -> [{ position: Vector2, radius: float, kind: int }]
##   count()
##   plus the whole ACAPropertyFeature interface
##
## SIGNALS: None.
##
## INVARIANTS
##   * Placement is a pure function of the property seed and lawn size, so a
##     resumed contract rebuilds the same rocks in the same places.
##   * `terrain_offset_at()` is always zero. Obstacles do not move the ground.
##   * Every obstacle is inside the lawn rectangle, which is inside the playable
##     boundary, which is why they are the only scenery on the property that
##     needs collision.
##
## PERSISTENCE OWNERSHIP
##   None. Rebuilt from ACAPropertyParams like every other feature.

## Meshes. Rocks come from the pack the wood already uses, so a lawn rock and a
## treeline rock are recognisably the same stone.
## THE ROUND ONES. This pack also ships flat-topped, near-cuboid stones, and the
## first render put one of those in the middle of a lawn at close range: it read
## as a dropped concrete block, not as a rock somebody has mown around for years.
const ROCK_SOURCES := [
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_C_Color1.gltf", "height": 2.4},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_F_Color1.gltf", "height": 2.8},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_1_J_Color1.gltf", "height": 2.5},
	{"path": "res://Assets/Foilage/Low Poly/Rocks/Rock_3_G_Color1.gltf", "height": 2.7},
]
const SHRUB_SOURCES := [
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_2_C_Color1.gltf", "height": 3.4},
	{"path": "res://Assets/Foilage/Low Poly/Bushes/Bush_4_D_Color1.gltf", "height": 3.8},
]

## Warm, so a grey stone does not turn blue under the sky ambient. Pushed
## further than the treeline's tint because a lawn rock stands on the brightest,
## most open ground on the property with a green field behind it, where a cool
## grey reads as concrete.
## LIFTED as well as warmed. The KayKit rocks take their colour from a shared
## atlas, and at any distance the mip chain averages that atlas towards its
## darker entries - so a stone that reads as mid grey up close reads as a black
## block from the far corner of a Large property, which is exactly what the
## forty-seed review showed. The multiplier is above one on every channel.
const ROCK_TINT := Color(1.38, 1.16, 0.88)
const SHRUB_TINT := Color(0.74, 0.86, 0.62)

enum Kind { ROCK, SHRUB }

## One obstacle per this many square units of lawn, before the clamps.
const CELLS_PER_OBSTACLE := 3600.0
const MIN_OBSTACLES := 3
const MAX_OBSTACLES := 12

## Obstacle footprint radius, in world units. A world unit is about a quarter of
## a metre, so this is a stone between a metre and a metre and a half across.
const MIN_RADIUS := 1.6
const MAX_RADIUS := 2.9

## THE WIDEST MACHINE IN THE GAME is the non-rider's chassis, at 6.83 units -
## which is what actually has to fit between two rocks, and is wider than the
## widest DECK (the rider's 5.6). Two obstacles are never left closer together
## than this, measured rim to rim, so every gap on the lawn is a gap the machine
## fits through with room to steer.
##
## It went up from 9.5 when the grass exclusion grew: the mowable strip left
## between two rocks is now the gap minus two clearance bands, and at 9.5 that
## strip was narrower than the machine that has to drive down it.
const MOWER_CLEARANCE := 11.0

## How far in from the lawn edge an obstacle must sit, measured to its rim.
const EDGE_INSET := 7.0
## Radius of the clear circle around the point the machine arrives at, and the
## width of the corridor it drives up. A contract that starts with a rock in the
## windscreen is a contract that reads as broken.
const SPAWN_CLEAR := 16.0
const ARRIVAL_CORRIDOR := 9.0

## How much clear ground is left around the pond, past its own bank.
const POND_CLEAR := 4.0

## How far past its footprint an obstacle keeps grass out.
##
## TWO THINGS ARE ADDED TOGETHER HERE, and they are added rather than merged
## because they answer different questions.
##
##   TIDINESS  a tuft growing out of the side of a boulder is the one thing
##             that gives an instanced rock away, so a little ground is cleared
##             for the look of it. This is the 0.5 the first version used.
##   REACH     the machine is stopped by the collision sphere with its CHASSIS,
##             and on two of the three canonical machines the chassis is wider
##             than the deck. Without this band the last strip of grass around
##             every rock is visible, counted, and impossible to cut.
##
## The second number is measured rather than chosen; see `ACAMowerClearance`.
const TIDY_MARGIN := 0.5
const GRASS_MARGIN := TIDY_MARGIN + ACAMowerClearance.REQUIRED

## Give up placing after this many rejected candidates. A property that cannot
## fit its full quota simply gets fewer, which is the right answer for a small
## lawn with a large pond on it.
const MAX_ATTEMPTS := 400

var _obstacles: Array[Dictionary] = []
var _bounds := AABB()
var _body: StaticBody3D = null
var _nodes := 0


## THE constructor. `existing` is the feature set as it stands - in practice the
## pond - so obstacles can be kept off ground another feature has already taken.
static func for_params(params: ACAPropertyParams, lawn_centre: Vector2,
		existing: ACAFeatureSet = null) -> ACALawnObstacles:
	var f := ACALawnObstacles.new()
	f._roll(params, lawn_centre, existing)
	return f


func feature_id() -> StringName:
	return &"lawn_obstacles"


func count() -> int:
	return _obstacles.size()


func obstacles() -> Array[Dictionary]:
	return _obstacles.duplicate(true)


# ==================================================================== rolling

func _roll(params: ACAPropertyParams, lawn_centre: Vector2,
		existing: ACAFeatureSet) -> void:
	var half := params.lawn_half_extent()
	var usable := half - EDGE_INSET
	if usable <= MAX_RADIUS * 2.0:
		return

	# A SEPARATE stream, seeded from the property seed but never drawn from
	# `ACAPropertyParams.for_seed()`. That is deliberate: obstacles could be
	# added without moving a single existing draw, so every property in every
	# save keeps the terrain, wood and pond it already had.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(params.seed, 51501))

	var area := float(params.lawn_size) * float(params.lawn_size)
	var wanted: int = clampi(int(round(area / CELLS_PER_OBSTACLE)),
		MIN_OBSTACLES, MAX_OBSTACLES)
	# The rock density the seed already drew decides how stony this address is,
	# so a property with a stony treeline has a stony lawn.
	wanted = maxi(int(round(float(wanted) * lerpf(0.6, 1.25,
		clampf(params.rock_density / 0.9, 0.0, 1.0)))), MIN_OBSTACLES)

	# The arrival: `ACAProperty.mower_start_transform()` puts the machine off
	# the -X edge at the lawn's centre line and drives it towards +X.
	var arrival := Vector2(lawn_centre.x - half, lawn_centre.y)

	var attempts := 0
	while _obstacles.size() < wanted and attempts < MAX_ATTEMPTS:
		attempts += 1
		var radius := rng.randf_range(MIN_RADIUS, MAX_RADIUS)
		var at := Vector2(
			lawn_centre.x + rng.randf_range(-1.0, 1.0) * (usable - radius),
			lawn_centre.y + rng.randf_range(-1.0, 1.0) * (usable - radius))
		if not _acceptable(at, radius, arrival, lawn_centre, half, existing):
			continue
		var kind: int = Kind.SHRUB if rng.randf() < 0.22 else Kind.ROCK
		_obstacles.append({
			"position": at,
			"radius": radius,
			"kind": kind,
			"yaw": rng.randf_range(0.0, TAU),
			"pick": rng.randi(),
		})
	_recompute_bounds()


func _acceptable(at: Vector2, radius: float, arrival: Vector2,
		lawn_centre: Vector2, half: float, existing: ACAFeatureSet) -> bool:
	# The arrival circle, and the corridor the machine drives up from it.
	if at.distance_to(arrival) < SPAWN_CLEAR + radius:
		return false
	if absf(at.y - arrival.y) < ARRIVAL_CORRIDOR + radius \
			and at.x < lawn_centre.x:
		return false

	# Ground another feature has already taken. Asked through the interface, so
	# a future feature is respected without this class learning what it is.
	if existing != null:
		for f in existing.features():
			if f == self:
				continue
			var rect := Rect2(
				Vector2(f.bounds().position.x, f.bounds().position.z),
				Vector2(f.bounds().size.x, f.bounds().size.z)).grow(
					radius + POND_CLEAR)
			if rect.has_point(at):
				return false

	# Room to drive between this one and every one already placed.
	for other: Dictionary in _obstacles:
		var gap: float = at.distance_to(other["position"]) \
			- radius - float(other["radius"])
		if gap < MOWER_CLEARANCE:
			return false
	return true


func _recompute_bounds() -> void:
	if _obstacles.is_empty():
		_bounds = AABB()
		return
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for o: Dictionary in _obstacles:
		var p: Vector2 = o["position"]
		var r: float = float(o["radius"]) + GRASS_MARGIN
		min_x = minf(min_x, p.x - r)
		min_z = minf(min_z, p.y - r)
		max_x = maxf(max_x, p.x + r)
		max_z = maxf(max_z, p.y + r)
	_bounds = AABB(Vector3(min_x, -400.0, min_z),
		Vector3(max_x - min_x, 800.0, max_z - min_z))


# ================================================================== interface

func bounds() -> AABB:
	return _bounds


## Obstacles sit ON the ground. They never move it.
func terrain_offset_at(_x: float, _z: float) -> float:
	return 0.0


## The machine hits these. That is the whole point of them.
func is_solid() -> bool:
	return true


## Already folded into `GRASS_MARGIN`, which the exclusion disc uses directly.
## Answered here so a caller asking the interface gets the truth.
func clearance() -> float:
	return ACAMowerClearance.REQUIRED


## A hard disc of `radius + GRASS_MARGIN`. Unlike the pond there is no fade: a
## rock either occupies a square of lawn or it does not, and half a rock is not
## a thing to blend. The margin is what the machine cannot reach, so the band is
## as hard as the collision that causes it.
func exclusion_at(x: float, z: float, _ground_y: float) -> float:
	var point := Vector2(x, z)
	for o: Dictionary in _obstacles:
		var r: float = float(o["radius"]) + GRASS_MARGIN
		if point.distance_squared_to(o["position"] as Vector2) <= r * r:
			return 1.0
	return 0.0


# ====================================================================== nodes

## One body for the whole set, plus one MultiMesh per source mesh. A property
## with a dozen lawn rocks on it therefore costs ONE physics body and two or
## three draw calls.
func build_nodes(parent: Node3D, terrain: Node3D, _params: ACAPropertyParams) -> void:
	if parent == null or _obstacles.is_empty():
		return
	var rocks := _prepare(ROCK_SOURCES)
	var shrubs := _prepare(SHRUB_SOURCES)
	if rocks.is_empty() and shrubs.is_empty():
		return

	_body = StaticBody3D.new()
	_body.name = "Lawn Obstacle Collision"
	parent.add_child(_body)

	var batches: Dictionary = {}
	for i in _obstacles.size():
		var o: Dictionary = _obstacles[i]
		var at: Vector2 = o["position"]
		var radius: float = float(o["radius"])
		var ground: float = float(terrain.call(&"height_at", at.x, at.y)) \
			if terrain != null and terrain.has_method(&"height_at") else 0.0
		var sources: Array[Dictionary] = rocks if int(o["kind"]) == Kind.ROCK else shrubs
		if sources.is_empty():
			sources = rocks if not rocks.is_empty() else shrubs
		var pick: int = int(o["pick"]) % sources.size()
		var source: Dictionary = sources[pick]

		# The mesh is normalised to a height, then scaled so its FOOTPRINT is
		# the radius the exclusion and the collision both use. A rock whose
		# collision does not match what is drawn is worse than no rock.
		var visual_scale: float = float(source["scale"]) \
			* (radius / maxf(float(source["footprint"]), 0.01))
		# SET WELL IN. A stone resting exactly on the surface reads as placed; one
		# with a third of itself below the turf reads as something the ground
		# has been growing around, which is what a lawn rock is.
		var sink: float = radius * (0.42 if int(o["kind"]) == Kind.ROCK else 0.16)
		var basis := Basis(Vector3.UP, float(o["yaw"])) \
			.scaled(Vector3(visual_scale, visual_scale, visual_scale))
		var key := "%d|%d" % [int(o["kind"]), pick]
		if not batches.has(key):
			batches[key] = {
				"mesh": source["mesh"],
				"kind": int(o["kind"]),
				"transforms": PackedFloat32Array(),
			}
		_append(batches[key]["transforms"],
			Transform3D(basis, Vector3(at.x, ground - sink, at.y)))

		# A SPHERE, not a convex hull of the mesh. The machine should slide off
		# a boulder rather than catch on whichever facet it met, and a sphere is
		# also the cheapest shape Jolt has.
		var shape := SphereShape3D.new()
		shape.radius = radius
		var node := CollisionShape3D.new()
		node.name = "Obstacle %d" % i
		node.shape = shape
		# Set into the ground by the same amount it is drawn set into it, and no
		# deeper: the part the player can see is the part that stops them.
		node.position = Vector3(at.x, ground - sink * 0.5, at.y) - parent.global_position
		_body.add_child(node)

	for key in batches:
		var batch: Dictionary = batches[key]
		_commit(parent, batch["mesh"], batch["transforms"],
			ROCK_TINT if int(batch["kind"]) == Kind.ROCK else SHRUB_TINT)


func _prepare(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		var mesh := _load_mesh(String(entry["path"]))
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		var height: float = maxf(aabb.size.y, 0.001)
		var scale: float = float(entry["height"]) / height
		out.append({
			"mesh": mesh,
			"scale": scale,
			# Half the wider horizontal span AT that normalised scale. This is
			# what ties the drawn size to the collision radius.
			"footprint": maxf(aabb.size.x, aabb.size.z) * 0.5 * scale,
		})
	return out


func _commit(parent: Node3D, mesh: Mesh, transforms: PackedFloat32Array,
		tint: Color) -> void:
	var count := transforms.size() / 12
	if count <= 0:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.buffer = transforms

	var instance := MultiMeshInstance3D.new()
	instance.name = "Lawn Obstacle %d" % _nodes
	instance.multimesh = multimesh
	instance.material_override = _tinted(mesh, tint)
	# These DO cast shadows, unlike the treeline. There are a dozen of them, they
	# stand on the flattest, brightest, most-looked-at ground on the property,
	# and the contact shadow is most of what makes one read as an object on the
	# lawn rather than a decal printed on it.
	instance.extra_cull_margin = 3.0
	parent.add_child(instance)
	_nodes += 1


## A COPY of the mesh's own imported material with its albedo multiplied.
##
## Not a fresh `StandardMaterial3D`: these meshes carry a texture atlas, and
## overriding them with a plain coloured material throws the atlas away and
## leaves a white block sitting on the lawn - which is exactly what the first
## render of this system showed. Copied rather than edited, because an imported
## mesh's material is a SHARED resource and writing to it would recolour every
## other use of that asset in the project. `ACAForest` does the same thing for
## the same reason.
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
		push_warning("[OBSTACLES] could not load %s" % path)
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
