class_name ACATownTraffic
extends Node3D
## ROLE
## The cars that drive around Business Town, and nothing else.
##
## ---------------------------------------------------------------------------
## THIS IS DECORATION, AND IT IS BUILT LIKE DECORATION
## ---------------------------------------------------------------------------
## A town with no moving traffic reads as a model of a town. Three or four cars
## going about their business is the whole difference, and the cheapest honest
## way to get it is a handful of authored lane loops with a car sliding along
## each one.
##
## So there is NO navigation, NO steering behaviour, NO physics, NO collision
## avoidance and NO traffic signalling. Every car follows a `PathFollow3D` at a
## constant speed around a closed lane and starts at a different offset. What
## the player sees from a fixed isometric camera thirty units up is exactly the
## same as what a simulation would have produced, at about a thousandth of the
## cost and none of the failure modes.
##
## WHAT KEEPS IT BELIEVABLE is entirely in where the lanes are drawn:
##
##   * a lane is offset to ONE side of its street's centre line, the side that
##     matches the direction of travel, so two cars passing each other pass on
##     the correct sides;
##   * corners are rounded with real intermediate points rather than square,
##     because `PathFollow3D` rotation on a right-angle corner snaps;
##   * every lane is a CLOSED loop that stays on tarmac the whole way round,
##     which is what stops a car ever driving over a pavement or through a
##     building - it is not avoiding them, it is simply never routed near them;
##   * speeds and start offsets are drawn from a fixed seed, so no two cars are
##     ever in step and the town looks the same every time it is opened.
##
## PUBLIC API
##   car_count() -> int
##   set_traffic_enabled(value: bool)
##   lane_count() -> int
##
## SIGNALS: None.
##
## INVARIANTS
##   * Lane points are in the TOWN's local space, on the y = ROAD_SURFACE plane.
##   * Nothing here reads or writes game state. It can be deleted and the town
##     still works.
##   * `PROCESS_MODE_PAUSABLE`: traffic stops when the game is paused, because a
##     car sliding past an open menu is worse than no car at all.
##
## PERSISTENCE OWNERSHIP
##   None.

## The vehicle models. The same four the town already parks at its kerbs, so
## the moving traffic and the parked traffic are the same town.
const CAR_SCENES := [
	"res://Main Area/ACA_BusinessTown/Assets/Vehicles/car_hatchback.gltf",
	"res://Main Area/ACA_BusinessTown/Assets/Vehicles/car_sedan.gltf",
	"res://Main Area/ACA_BusinessTown/Assets/Vehicles/car_stationwagon.gltf",
	"res://Main Area/ACA_BusinessTown/Assets/Vehicles/car_taxi.gltf",
]

## Where a car's wheels sit. Matched to the parked cars already in the scene.
const ROAD_SURFACE := 0.17
## How far a lane sits from its street's centre line. A road tile is two units
## wide, so this puts a car in the middle of its own half.
const LANE_OFFSET := 0.55
## World units per second. A town this size is about thirty units across, so
## this crosses it in roughly twenty seconds - a car pottering through a small
## town rather than one being chased through it.
const MIN_SPEED := 1.5
const MAX_SPEED := 2.4
## Points used to round each corner. Three is enough at this camera distance and
## keeps the whole network under a hundred points.
const CORNER_POINTS := 3
## How far back from a corner the rounding starts.
const CORNER_RADIUS := 1.1

## The seed every speed and start offset is drawn from, so the town opens the
## same way twice.
const TRAFFIC_SEED := 20260824

## ---------------------------------------------------------------------------
## THE LANES
## ---------------------------------------------------------------------------
## Each entry is a closed loop of corner points on the road grid, in the order
## the car drives them. They were read off the road tiles rather than invented:
## the main street is at z = 0, the back street at z = -6, the side street at
## x = 2 and the connector at x = -4, and every tile is two units square, so a
## lane offset half a unit from a centre line is comfortably inside the tarmac.
##
## Three loops, four cars. A fourth loop was tried and cut: at this camera
## distance the town started to look busy rather than alive.
const LANES := [
	{
		# The east block: down the main street, up the side street, back along
		# the back street. The loop that passes the Job Office.
		"name": "east_block",
		"corners": [
			Vector2(14.0, LANE_OFFSET),
			Vector2(2.0 - LANE_OFFSET, LANE_OFFSET),
			Vector2(2.0 - LANE_OFFSET, -6.0 - LANE_OFFSET),
			Vector2(14.0, -6.0 - LANE_OFFSET),
			Vector2(14.0, -6.0 + LANE_OFFSET),
			Vector2(2.0 + LANE_OFFSET, -6.0 + LANE_OFFSET),
			Vector2(2.0 + LANE_OFFSET, -LANE_OFFSET),
			Vector2(14.0, -LANE_OFFSET),
		],
	},
	{
		# The middle block: the connector at x = -4 and the side street at
		# x = 2 with the two streets between them. A short circuit, so this one
		# is the car the player sees most often.
		"name": "middle_block",
		"corners": [
			Vector2(-4.0 + LANE_OFFSET, -LANE_OFFSET),
			Vector2(2.0 - LANE_OFFSET, -LANE_OFFSET),
			Vector2(2.0 - LANE_OFFSET, -6.0 + LANE_OFFSET),
			Vector2(-4.0 + LANE_OFFSET, -6.0 + LANE_OFFSET),
		],
	},
	{
		# The west end: out past the Supply Store, round the far end of both
		# streets, and back. It leaves the island at both ends, which is what
		# the main street already does - the road goes on somewhere else.
		"name": "west_run",
		"corners": [
			Vector2(-14.6, LANE_OFFSET),
			Vector2(-4.0 - LANE_OFFSET, LANE_OFFSET),
			Vector2(-4.0 - LANE_OFFSET, -6.0 - LANE_OFFSET),
			Vector2(-14.6, -6.0 - LANE_OFFSET),
			Vector2(-14.6, -6.0 + LANE_OFFSET),
			Vector2(-4.0 + LANE_OFFSET, -6.0 + LANE_OFFSET),
			Vector2(-4.0 + LANE_OFFSET, -LANE_OFFSET),
			Vector2(-14.6, -LANE_OFFSET),
		],
	},
]

## Which lane each car runs on. Two on the long east loop, one each on the
## others, so the busiest street is the one outside the Job Office.
const CAR_LANES := [0, 0, 1, 2]

var _followers: Array[PathFollow3D] = []
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()


func car_count() -> int:
	return _followers.size()


func lane_count() -> int:
	return LANES.size()


func set_traffic_enabled(value: bool) -> void:
	_enabled = value
	visible = value


func _process(delta: float) -> void:
	if not _enabled:
		return
	for i in _followers.size():
		var follower := _followers[i]
		# `loop` is on, so progress wraps on its own and a car never has to be
		# put back to the start.
		follower.progress += _speeds[i] * delta


# ======================================================================= build

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TRAFFIC_SEED

	var paths: Array[Path3D] = []
	for lane: Dictionary in LANES:
		var path := Path3D.new()
		path.name = "Lane %s" % String(lane["name"])
		path.curve = _closed_curve(lane["corners"] as Array)
		add_child(path)
		paths.append(path)

	for i in CAR_LANES.size():
		var lane_index: int = int(CAR_LANES[i])
		if lane_index >= paths.size():
			continue
		var car := _make_car(i, rng)
		if car == null:
			continue
		var follower := PathFollow3D.new()
		follower.name = "Car %d" % i
		follower.loop = true
		# The car model faces down its own +Z, and so does a PathFollow3D, so
		# the two agree without a correction.
		follower.rotation_mode = PathFollow3D.ROTATION_Y
		# Tilting a car to the road would be right on a hill. This town is flat,
		# and leaving it on makes a car roll slightly on every corner.
		follower.cubic_interp = true
		paths[lane_index].add_child(follower)
		follower.add_child(car)
		# STAGGERED. Two cars on one loop starting together would drive round it
		# nose to tail forever.
		follower.progress_ratio = rng.randf()
		_followers.append(follower)
		_speeds.append(rng.randf_range(MIN_SPEED, MAX_SPEED))


## A closed curve through `corners`, with every corner rounded.
##
## A `Curve3D` through square corners makes a `PathFollow3D` snap through ninety
## degrees in one frame, which at this camera distance reads as a car glitching
## rather than turning. Each corner is replaced by a short arc between the two
## points `CORNER_RADIUS` back along its arms.
func _closed_curve(corners: Array) -> Curve3D:
	var curve := Curve3D.new()
	var count := corners.size()
	for i in count:
		var previous: Vector2 = corners[(i - 1 + count) % count]
		var here: Vector2 = corners[i]
		var following: Vector2 = corners[(i + 1) % count]
		var into := (here - previous)
		var out := (following - here)
		if into.length() < 0.001 or out.length() < 0.001:
			curve.add_point(_ground(here))
			continue
		# Never round by more than half of either arm, or two adjacent corners
		# eat each other and the lane crosses itself.
		var radius: float = minf(CORNER_RADIUS,
			minf(into.length(), out.length()) * 0.45)
		var start := here - into.normalized() * radius
		var finish := here + out.normalized() * radius
		curve.add_point(_ground(start))
		for step in range(1, CORNER_POINTS + 1):
			var t := float(step) / float(CORNER_POINTS + 1)
			# A quadratic Bezier with the corner itself as the control point.
			var inverse := 1.0 - t
			var at: Vector2 = start * inverse * inverse \
				+ here * 2.0 * inverse * t + finish * t * t
			curve.add_point(_ground(at))
		curve.add_point(_ground(finish))
	return curve


static func _ground(at: Vector2) -> Vector3:
	return Vector3(at.x, ROAD_SURFACE, at.y)


func _make_car(index: int, rng: RandomNumberGenerator) -> Node3D:
	var picks := CAR_SCENES.duplicate()
	var path := String(picks[index % picks.size()])
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[TRAFFIC] could not load %s" % path)
		return null
	var car := packed.instantiate() as Node3D
	if car == null:
		return null
	car.name = "Body"
	# A hair of yaw variation, so four identical models on four lanes do not all
	# sit dead square to their own direction of travel.
	car.rotate_y(rng.randf_range(-0.02, 0.02))
	return car
