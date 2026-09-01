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
## LAYOUTS: THE SAME OBSTACLES, ARRANGED INTO A ROUTE
## ---------------------------------------------------------------------------
## Uniform scatter is a fair way to place rocks and a poor way to make a lawn
## worth thinking about. With the count clamped between three and twelve and
## every pair held eleven units apart, scattered obstacles average out - one
## property mows very much like the next, and the answer to all of them is the
## same back-and-forth.
##
## A layout changes NOTHING about what an obstacle is, and none of the rules in
## `_acceptable()`. It only changes where candidates are offered from, so the
## same rocks land in an arrangement that asks for a particular route:
##
##   SCATTER    what the generator always did. Kept, and still common: a plain
##              open lawn is a legitimate property and a rest between awkward
##              ones.
##   ISLAND     everything gathered into the middle. The perimeter is wide open
##              and the centre wants circling.
##   GAUNTLET   two offset ranks walked across the property, so a straight pass
##              has to weave - the S-shaped route.
##   AVENUE     a line on a drawn heading, splitting the lawn into two strips
##              that are mown separately.
##   CORNERS    pushed into one or two corners. Open middle, awkward ends.
##   PERIMETER  held out near the edge, so the middle is quick and the last
##              strip round the outside is the work.
##
## The layout is drawn from the SAME stream as the positions, so a seed still
## reproduces its property exactly - and a property generated before layouts
## existed keeps its scatter. See `_layout_for()`.
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
##   layout() / layout_name()
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

## The arrangement this property's obstacles were offered from. See the LAYOUTS
## section above.
enum Layout { SCATTER, ISLAND, GAUNTLET, AVENUE, CORNERS, PERIMETER }

const LAYOUT_NAMES := ["Scatter", "Island", "Gauntlet", "Avenue", "Corners",
	"Perimeter"]

## Below this lawn size a property has neither the room nor the obstacle count
## for an arrangement to read as one, and forcing a layout on it produces a
## cramped lawn rather than an interesting one.
const LAYOUT_MIN_LAWN := 120

## The most obstacles an ISLAND is given. See the note in `_layout_shape()`.
const ISLAND_OBSTACLES := 5

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
var _layout: int = Layout.SCATTER
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


## Which arrangement this property's obstacles were offered from.
func layout() -> int:
	return _layout


func layout_name() -> String:
	return LAYOUT_NAMES[_layout]


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
	# ...and how neglected it is decides how much has been left lying in it. Zero
	# on every ordinary property, so this multiplies by exactly one on all of
	# them; a rescue job has noticeably more to work round.
	if params.clutter > 0.0:
		wanted = mini(int(round(float(wanted) * (1.0 + params.clutter * 0.8))),
			MAX_OBSTACLES)

	# The arrival: `ACAProperty.mower_start_transform()` puts the machine off
	# the -X edge at the lawn's centre line and drives it towards +X.
	var arrival := Vector2(lawn_centre.x - half, lawn_centre.y)

	# THE ARRANGEMENT, and whatever it needs decided, drawn before any position
	# so the sequence is fixed for a seed.
	_layout = _layout_for(params, rng)
	var shape := _layout_shape(rng, lawn_centre, usable)
	# An island is a THING TO DRIVE ROUND, not a quota spread over the middle of
	# the lawn. Fewer of them is what lets them sit close enough together to
	# read as one feature - see `island_radius`.
	if _layout == Layout.ISLAND:
		wanted = mini(wanted, ISLAND_OBSTACLES)

	var attempts := 0
	var index := 0
	while _obstacles.size() < wanted and attempts < MAX_ATTEMPTS:
		attempts += 1
		var radius := rng.randf_range(MIN_RADIUS, MAX_RADIUS)
		var span := usable - radius
		# Past halfway through the attempt budget the arrangement has had its
		# chance. The rest is filled by ordinary scatter, because a property that
		# is three rocks short of its quota is worse than one whose last two are
		# not quite on the pattern.
		var at := (_scatter(rng, lawn_centre, span) if attempts > MAX_ATTEMPTS / 2
			else _propose(rng, shape, index, wanted, lawn_centre, span))
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
		index += 1
	_recompute_bounds()


## WHICH ARRANGEMENT THIS PROPERTY GETS.
##
## Scatter keeps a real share of the weight deliberately. Every property being
## a composition is the same mistake as every property being a scatter: the
## variety is in the CONTRAST, and a plain open lawn is what makes the next
## gauntlet feel like something.
static func _layout_for(params: ACAPropertyParams,
		rng: RandomNumberGenerator) -> int:
	# NOT ON A PROPERTY GENERATED BEFORE LAYOUTS EXISTED, for exactly the reason
	# conservation zones are not given to one: a contract already in progress
	# would have its obstacles, and so its completion denominator, moved
	# underneath it. A save is a promise about the ground being stood on.
	if params.generation_version < 6:
		return Layout.SCATTER
	if params.lawn_size < LAYOUT_MIN_LAWN:
		return Layout.SCATTER if rng.randf() < 0.55 else Layout.CORNERS
	var roll := rng.randf()
	if roll < 0.22:
		return Layout.SCATTER
	if roll < 0.42:
		return Layout.ISLAND
	if roll < 0.60:
		return Layout.GAUNTLET
	if roll < 0.74:
		return Layout.AVENUE
	if roll < 0.87:
		return Layout.CORNERS
	return Layout.PERIMETER


## Everything an arrangement needs that must be the same for every obstacle on
## the property - where the island is, which way the avenue runs - drawn once,
## in a fixed order, before any position.
func _layout_shape(rng: RandomNumberGenerator, lawn_centre: Vector2,
		usable: float) -> Dictionary:
	return {
		# Off the exact middle, so an island is not always the same loop.
		"island": lawn_centre + Vector2(rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)) * usable * 0.22,
		# THE CLEARANCE RULE SETS A FLOOR ON HOW TIGHT ANY GROUP CAN BE. Two
		# obstacles are never left closer than eleven units rim to rim, so a
		# group of seven is about twenty-six units across whatever this says.
		#
		# 0.40 was tried first and drew a group filling most of the lawn - only
		# the numbers could tell it from a scatter. Simply tightening it to 0.30
		# made it WORSE: the clearance rule rejected nearly every candidate
		# inside the smaller disc, the placement fell back to scatter, and the
		# arrangement measured closer to a scatter than it had before. The disc
		# is tight AND the group is smaller, which is the combination that
		# actually fits.
		"island_radius": usable * 0.30,
		"angle": rng.randf_range(0.0, PI),
		"rank": usable * rng.randf_range(0.30, 0.50),
		"corner_a": Vector2(1.0 if rng.randf() < 0.5 else -1.0,
			1.0 if rng.randf() < 0.5 else -1.0),
		"corner_b": Vector2(1.0 if rng.randf() < 0.5 else -1.0,
			1.0 if rng.randf() < 0.5 else -1.0),
	}


## One candidate position for this arrangement. It is only an OFFER: every rule
## in `_acceptable()` still applies to it, so no layout can put a rock in the
## arrival corridor, in the pond, or close enough to another to close a gap the
## machine has to fit through.
func _propose(rng: RandomNumberGenerator, shape: Dictionary, index: int,
		wanted: int, lawn_centre: Vector2, span: float) -> Vector2:
	match _layout:
		Layout.ISLAND:
			# Square-rooted radius, so the group fills its disc evenly instead of
			# bunching at the middle.
			var island_at: Vector2 = shape["island"]
			var reach: float = float(shape["island_radius"]) * sqrt(rng.randf())
			var around: float = rng.randf_range(0.0, TAU)
			return _inside(island_at + Vector2(cos(around), sin(around)) * reach,
				lawn_centre, span)
		Layout.GAUNTLET:
			# Alternating ranks either side of a line, walked along it, so the
			# gaps stagger into a weave rather than lining up into a corridor.
			var run := Vector2(cos(float(shape["angle"])), sin(float(shape["angle"])))
			var across := Vector2(-run.y, run.x)
			var along: float = (float(index) / maxf(float(wanted - 1), 1.0)) * 2.0 - 1.0
			var side: float = 1.0 if index % 2 == 0 else -1.0
			return _inside(lawn_centre + run * along * span * 0.85
				+ across * side * float(shape["rank"])
				+ _jitter(rng, span * 0.10), lawn_centre, span)
		Layout.AVENUE:
			var line := Vector2(cos(float(shape["angle"])), sin(float(shape["angle"])))
			return _inside(lawn_centre + line * rng.randf_range(-0.9, 0.9) * span
				+ _jitter(rng, span * 0.08), lawn_centre, span)
		Layout.CORNERS:
			# Two in three go to the first corner, so one end is clearly the
			# difficult one rather than both being equally cluttered.
			var corner: Vector2 = shape["corner_b"] if index % 3 == 2 \
				else shape["corner_a"]
			return _inside(lawn_centre + corner * span * rng.randf_range(0.55, 0.95)
				+ _jitter(rng, span * 0.18), lawn_centre, span)
		Layout.PERIMETER:
			var bearing: float = rng.randf_range(0.0, TAU)
			var out: float = span * rng.randf_range(0.62, 0.98)
			return _inside(lawn_centre + Vector2(cos(bearing), sin(bearing)) * out,
				lawn_centre, span)
	return _scatter(rng, lawn_centre, span)


static func _scatter(rng: RandomNumberGenerator, lawn_centre: Vector2,
		span: float) -> Vector2:
	return Vector2(
		lawn_centre.x + rng.randf_range(-1.0, 1.0) * span,
		lawn_centre.y + rng.randf_range(-1.0, 1.0) * span)


static func _jitter(rng: RandomNumberGenerator, amount: float) -> Vector2:
	return Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * amount


## Arrangements are described in their own terms and can reach past the lawn;
## this is what keeps every offer inside the rectangle obstacles may occupy.
static func _inside(at: Vector2, lawn_centre: Vector2, span: float) -> Vector2:
	return Vector2(
		clampf(at.x, lawn_centre.x - span, lawn_centre.x + span),
		clampf(at.y, lawn_centre.y - span, lawn_centre.y + span))


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


## THE ROCKS THEMSELVES, rather than the box around all of them. See
## `ACAPropertyFeature.footprints()`: the combined box of a dozen scattered
## obstacles is most of the lawn, and a placer that treated it as occupied
## ground could never put anything anywhere.
func footprints() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in _obstacles:
		out.append({
			"position": o["position"] as Vector2,
			"radius": float(o["radius"]),
		})
	return out


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
