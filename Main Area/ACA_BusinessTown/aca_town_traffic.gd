class_name ACATownTraffic
extends Node3D
## ROLE
## The cars that drive around Business Town, and nothing else.
##
## ---------------------------------------------------------------------------
## THIS IS DECORATION, AND IT IS BUILT LIKE DECORATION
## ---------------------------------------------------------------------------
## A town with no moving traffic reads as a model of a town. A handful of cars
## going about their business is the whole difference, and the cheapest honest
## way to get it is authored routes with a car sliding along each one.
##
## So there is NO navigation, NO steering behaviour, NO physics, NO collision
## avoidance and NO traffic signalling. Every car follows a `PathFollow3D` at a
## constant speed and starts at a different offset. What the player sees from a
## fixed isometric camera thirty units up is exactly the same as what a
## simulation would have produced, at about a thousandth of the cost and none of
## the failure modes.
##
## WHAT KEEPS IT BELIEVABLE is entirely in where the routes are drawn:
##
##   * a route is offset to ONE side of its street's centre line, the side that
##     matches the direction of travel, so two cars passing each other pass on
##     the correct sides;
##   * corners are rounded with real intermediate points rather than square,
##     because `PathFollow3D` rotation on a right-angle corner snaps;
##   * every route stays on tarmac for its whole length, WITH THE CAR'S OWN BODY
##     WIDTH TO SPARE. That is not a claim, it is measured: `Town Road Probe`
##     walks each route against the real road tiles' footprint and fails if any
##     sample puts a wheel on a verge.
##
## ---------------------------------------------------------------------------
## TWO KINDS OF ROUTE
## ---------------------------------------------------------------------------
## **Loops** are closed. A car on a loop circulates the town and is never
## removed; this is the traffic that makes the place look inhabited.
##
## **Through routes** are open, and both of their ends are where a street runs
## off the island. A car on one drives in from the edge, crosses the town, and
## leaves at another edge, at which point it is recycled on to a fresh route
## after a delay. That is what stops the town looking like four cars on a
## carousel.
##
## A car on a through route fades in over its first `FADE_DISTANCE` units and
## out over its last, so it is never seen appearing. It only ever appears or
## disappears at a street's end, never mid-block.
##
## ---------------------------------------------------------------------------
## RANDOM, BUT BOUNDED
## ---------------------------------------------------------------------------
## The population, the models, the routes, the speeds, the start offsets and the
## spawn delays are all drawn fresh each time the town is entered, between
## `MIN_CARS` and `MAX_CARS`. The bound is what keeps a calm small town calm: at
## this camera distance more than about seven cars stops reading as "a town with
## some traffic" and starts reading as "rush hour".
##
## PUBLIC API
##   car_count() -> int              cars currently placed (including waiting)
##   active_car_count() -> int       cars actually visible on a route
##   route_count() -> int
##   loop_count() -> int
##   set_traffic_enabled(value: bool)
##
## SIGNALS: None.
##
## INVARIANTS
##   * Route points are in the TOWN's local space, on the y = ROAD_SURFACE plane.
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

## How far a route sits from its street's centre line.
##
## A road tile is two units wide, so a half-carriageway is one unit and a car
## body is about 0.84 across. At the 0.55 this shipped with, a car had three
## hundredths of a unit of kerb clearance and `Town Road Probe` found twenty-six
## samples across the three loops where the body overhung the tarmac. At 0.45
## the clearance is 0.13 and the two directions are still 0.9 apart, which still
## reads as two lanes from above.
const LANE_OFFSET := 0.45

## Where the streets run off the island, so a through route can start and end
## somewhere the town does not have to explain. The island's grass is thirty
## units across, centred on the origin.
const EDGE_WEST := -14.4
const EDGE_EAST := 14.4

## The two streets' centre lines, and the two roads that join them.
const MAIN_Z := 0.0
const BACK_Z := -6.0
const CONNECTOR_X := -4.0
const SIDE_X := 2.0

## World units per second. A town this size is about thirty units across, so
## this crosses it in roughly fifteen to twenty-five seconds - a car pottering
## through a small town rather than one being chased through it.
const MIN_SPEED := 1.5
const MAX_SPEED := 2.6
## Points used to round each corner. Three is enough at this camera distance.
const CORNER_POINTS := 3
## How far back from a corner the rounding starts.
const CORNER_RADIUS := 1.0

## How many cars are on the streets at once. Drawn fresh per visit.
const MIN_CARS := 3
const MAX_CARS := 7
## Seconds a through-route car waits, off screen, before it drives in again.
const MIN_RESPAWN_WAIT := 2.5
const MAX_RESPAWN_WAIT := 9.0
## How far a through-route car fades over at each end of its run.
const FADE_DISTANCE := 2.2

## ---------------------------------------------------------------------------
## THE ROUTES
## ---------------------------------------------------------------------------
## Each entry is a list of corner points on the road grid, in the order the car
## drives them. They were read off the road tiles rather than invented: the main
## street is at z = 0, the back street at z = -6, the side street at x = 2 and
## the connector at x = -4, and every tile is two units square.
##
## `loop` closes the route. Anything else is a through route and both of its
## ends are at `EDGE_WEST` or `EDGE_EAST`.

const LOOPS := [
	{
		# The east block: down the main street, up the side street, back along
		# the back street. The loop that passes the Job Office.
		"name": "east_block",
		"corners": [
			Vector2(13.4, LANE_OFFSET),
			Vector2(SIDE_X - LANE_OFFSET, LANE_OFFSET),
			Vector2(SIDE_X - LANE_OFFSET, BACK_Z - LANE_OFFSET),
			Vector2(13.4, BACK_Z - LANE_OFFSET),
			Vector2(13.4, BACK_Z + LANE_OFFSET),
			Vector2(SIDE_X + LANE_OFFSET, BACK_Z + LANE_OFFSET),
			Vector2(SIDE_X + LANE_OFFSET, -LANE_OFFSET),
			Vector2(13.4, -LANE_OFFSET),
		],
	},
	{
		# The middle block: the connector at x = -4 and the side street at
		# x = 2 with the two streets between them. A short circuit, so this one
		# is the car the player sees most often.
		"name": "middle_block",
		"corners": [
			Vector2(CONNECTOR_X + LANE_OFFSET, -LANE_OFFSET),
			Vector2(SIDE_X - LANE_OFFSET, -LANE_OFFSET),
			Vector2(SIDE_X - LANE_OFFSET, BACK_Z + LANE_OFFSET),
			Vector2(CONNECTOR_X + LANE_OFFSET, BACK_Z + LANE_OFFSET),
		],
	},
	{
		# The west end: out past the Supply Store, round the far end of both
		# streets, and back.
		"name": "west_block",
		"corners": [
			Vector2(-13.4, LANE_OFFSET),
			Vector2(CONNECTOR_X - LANE_OFFSET, LANE_OFFSET),
			Vector2(CONNECTOR_X - LANE_OFFSET, BACK_Z - LANE_OFFSET),
			Vector2(-13.4, BACK_Z - LANE_OFFSET),
			Vector2(-13.4, BACK_Z + LANE_OFFSET),
			Vector2(CONNECTOR_X + LANE_OFFSET, BACK_Z + LANE_OFFSET),
			Vector2(CONNECTOR_X + LANE_OFFSET, -LANE_OFFSET),
			Vector2(-13.4, -LANE_OFFSET),
		],
	},
]

const THROUGH_ROUTES := [
	{
		# Straight through town on the main street, west to east.
		"name": "main_west_east",
		"corners": [
			Vector2(EDGE_WEST, LANE_OFFSET),
			Vector2(EDGE_EAST, LANE_OFFSET),
		],
	},
	{
		"name": "main_east_west",
		"corners": [
			Vector2(EDGE_EAST, -LANE_OFFSET),
			Vector2(EDGE_WEST, -LANE_OFFSET),
		],
	},
	{
		"name": "back_west_east",
		"corners": [
			Vector2(EDGE_WEST, BACK_Z + LANE_OFFSET),
			Vector2(EDGE_EAST, BACK_Z + LANE_OFFSET),
		],
	},
	{
		"name": "back_east_west",
		"corners": [
			Vector2(EDGE_EAST, BACK_Z - LANE_OFFSET),
			Vector2(EDGE_WEST, BACK_Z - LANE_OFFSET),
		],
	},
	{
		# In on the main street, up the connector, out along the back street.
		# The route that makes the junctions look like they are for something.
		"name": "main_west_via_connector",
		"corners": [
			Vector2(EDGE_WEST, LANE_OFFSET),
			Vector2(CONNECTOR_X - LANE_OFFSET, LANE_OFFSET),
			Vector2(CONNECTOR_X - LANE_OFFSET, BACK_Z - LANE_OFFSET),
			Vector2(EDGE_EAST, BACK_Z - LANE_OFFSET),
		],
	},
	{
		# In on the back street, down the side street, out along the main.
		"name": "back_west_via_side",
		"corners": [
			Vector2(EDGE_WEST, BACK_Z + LANE_OFFSET),
			Vector2(SIDE_X + LANE_OFFSET, BACK_Z + LANE_OFFSET),
			Vector2(SIDE_X + LANE_OFFSET, -LANE_OFFSET),
			Vector2(EDGE_EAST, -LANE_OFFSET),
		],
	},
]

## One car in flight.
class Car extends RefCounted:
	var follower: PathFollow3D
	var body: Node3D
	## The car's own mesh instances, collected once. `transparency` lives on
	## GeometryInstance3D, not on the glTF scene's Node3D root.
	var panels: Array[GeometryInstance3D] = []
	var speed: float = 2.0
	var length: float = 1.0
	## Open routes are removed and re-launched; a loop never is.
	var is_loop: bool = false
	## Seconds still to wait, off screen, before this car drives in.
	var wait: float = 0.0

	func collect_panels() -> void:
		panels.clear()
		_gather(body)

	func _gather(node: Node) -> void:
		if node is GeometryInstance3D:
			panels.append(node as GeometryInstance3D)
		for child in node.get_children():
			_gather(child)

	## 0 opaque, 1 invisible. Below the threshold the car is simply hidden: a
	## car at ninety-eight per cent transparency is a smear on the tarmac, and
	## the last two per cent of a fade is not worth a draw call.
	func set_transparency(value: float) -> void:
		var hidden := value >= 0.98
		if follower.visible != (not hidden) and wait <= 0.0:
			follower.visible = not hidden
		for panel in panels:
			panel.transparency = clampf(value, 0.0, 1.0)

# ---------------------------------------------------------------------------
# THE ROUTES AND THE POPULATION ARE OVERRIDABLE, so a REGION can have its own
# ---------------------------------------------------------------------------
# The constants above are the BUSINESS TOWN's, and they stay the default: this
# node is authored into `BusinessTown.tscn` with nothing set, and behaves there
# exactly as it always has.
#
# A regional hub has a different street plan and a different amount of traffic
# on it - a highway service lot is not a market square - so it hands its own
# routes and its own population in before the node enters the tree. The rest of
# the class does not change: the same paths, the same fading, the same recycling.
#
# `configure()` must be called BEFORE the node is added to the tree, because
# `_ready()` is what builds the paths.
var _loops: Array = LOOPS
var _through: Array = THROUGH_ROUTES
var _min_cars: int = MIN_CARS
var _max_cars: int = MAX_CARS
var _min_speed: float = MIN_SPEED
var _max_speed: float = MAX_SPEED

var _cars: Array[Car] = []
var _paths: Array[Path3D] = []
## Parallel to `_paths`: whether that path is a loop.
var _path_is_loop: Array[bool] = []
var _rng := RandomNumberGenerator.new()
var _enabled: bool = true


## Give this node another town's street plan. Everything is optional; a field
## left out keeps the Business Town's own value.
func configure(spec: Dictionary) -> void:
	_loops = spec.get("loops", _loops) as Array
	_through = spec.get("through", _through) as Array
	_min_cars = maxi(int(spec.get("min_cars", _min_cars)), 0)
	_max_cars = maxi(int(spec.get("max_cars", _max_cars)), _min_cars)
	_min_speed = maxf(float(spec.get("min_speed", _min_speed)), 0.05)
	_max_speed = maxf(float(spec.get("max_speed", _max_speed)), _min_speed)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# FRESH EVERY VISIT, deliberately. The town used to open with the same four
	# cars in the same four places, which reads as a diorama rather than a place.
	_rng.randomize()
	_build()


func car_count() -> int:
	return _cars.size()


func active_car_count() -> int:
	var count := 0
	for car in _cars:
		if car.wait <= 0.0:
			count += 1
	return count


func route_count() -> int:
	return _paths.size()


func loop_count() -> int:
	return _loops.size()


func set_traffic_enabled(value: bool) -> void:
	_enabled = value
	visible = value


func _process(delta: float) -> void:
	if not _enabled:
		return
	for car in _cars:
		if car.wait > 0.0:
			car.wait -= delta
			if car.wait <= 0.0:
				_launch(car)
			continue
		car.follower.progress += car.speed * delta
		if car.is_loop:
			# `loop` is on, so progress wraps on its own.
			continue
		_fade(car)
		if car.follower.progress >= car.length:
			_retire(car)


## A through-route car is transparent at both ends of its run, so it is never
## seen to appear. The town's edge is where a street leaves the island, which is
## the one place a car arriving from nowhere is what a player expects.
func _fade(car: Car) -> void:
	var from_start := car.follower.progress
	var from_end := car.length - car.follower.progress
	var alpha := clampf(minf(from_start, from_end) / FADE_DISTANCE, 0.0, 1.0)
	car.set_transparency(1.0 - alpha)


func _retire(car: Car) -> void:
	car.follower.visible = false
	car.wait = _rng.randf_range(MIN_RESPAWN_WAIT, MAX_RESPAWN_WAIT)


## Put a waiting car on a fresh through route, with a fresh speed.
func _launch(car: Car) -> void:
	var choices: Array[int] = []
	for i in _paths.size():
		if not _path_is_loop[i]:
			choices.append(i)
	if choices.is_empty():
		return
	var pick: int = choices[_rng.randi_range(0, choices.size() - 1)]
	var path := _paths[pick]
	if car.follower.get_parent() != path:
		car.follower.reparent(path, false)
	car.length = path.curve.get_baked_length()
	car.speed = _rng.randf_range(_min_speed, _max_speed)
	car.follower.progress = 0.0
	car.follower.visible = true
	car.set_transparency(1.0)


# ======================================================================= build

func _build() -> void:
	for route: Dictionary in _loops:
		_add_path(route, true)
	for route: Dictionary in _through:
		_add_path(route, false)

	# THE POPULATION IS DRAWN, NOT DECLARED. At least one car on a loop, so the
	# town is never empty even if every through-route car happens to be waiting.
	# A plan with no loops on it - a highway, an access lane - gets none.
	var total := _rng.randi_range(_min_cars, _max_cars)
	var on_loops := 0 if _loops.is_empty() else clampi(_rng.randi_range(1, 3), 1, total)
	for i in total:
		var loop := i < on_loops
		var car := _make_car(loop)
		if car != null:
			_cars.append(car)


func _add_path(route: Dictionary, is_loop: bool) -> void:
	var path := Path3D.new()
	path.name = "Route %s" % String(route["name"])
	path.curve = _rounded_curve(route["corners"] as Array, is_loop)
	add_child(path)
	_paths.append(path)
	_path_is_loop.append(is_loop)


func _make_car(on_loop: bool) -> Car:
	var choices: Array[int] = []
	for i in _paths.size():
		if _path_is_loop[i] == on_loop:
			choices.append(i)
	if choices.is_empty():
		return null
	var pick: int = choices[_rng.randi_range(0, choices.size() - 1)]
	var path := _paths[pick]

	var body := _make_body()
	if body == null:
		return null

	var follower := PathFollow3D.new()
	follower.name = "Car %d" % _cars.size()
	follower.loop = on_loop
	# The car model faces down its own +Z, and so does a PathFollow3D, so the
	# two agree without a correction.
	follower.rotation_mode = PathFollow3D.ROTATION_Y
	# Tilting a car to the road would be right on a hill. This town is flat, and
	# leaving it on makes a car roll slightly on every corner.
	follower.cubic_interp = true
	path.add_child(follower)
	follower.add_child(body)

	var car := Car.new()
	car.follower = follower
	car.body = body
	car.is_loop = on_loop
	car.collect_panels()
	car.length = path.curve.get_baked_length()
	car.speed = _rng.randf_range(_min_speed, _max_speed)
	if on_loop:
		# STAGGERED. Two cars on one loop starting together would drive round it
		# nose to tail forever.
		follower.progress_ratio = _rng.randf()
	else:
		# A through-route car starts somewhere along its run rather than all of
		# them arriving at the town edge in the first second.
		follower.progress = _rng.randf() * car.length
		_fade(car)
	return car


func _make_body() -> Node3D:
	var path := String(CAR_SCENES[_rng.randi_range(0, CAR_SCENES.size() - 1)])
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[TRAFFIC] could not load %s" % path)
		return null
	var car := packed.instantiate() as Node3D
	if car == null:
		return null
	car.name = "Body"
	# A hair of yaw variation, so identical models on identical routes do not
	# all sit dead square to their own direction of travel.
	car.rotate_y(_rng.randf_range(-0.02, 0.02))
	return car


## A curve through `corners`, with every corner rounded.
##
## A `Curve3D` through square corners makes a `PathFollow3D` snap through ninety
## degrees in one frame, which at this camera distance reads as a car glitching
## rather than turning. Each corner is replaced by a short arc between the two
## points `CORNER_RADIUS` back along its arms. The first and last point of an
## OPEN route are ends rather than corners and are left alone.
func _rounded_curve(corners: Array, closed: bool) -> Curve3D:
	var curve := Curve3D.new()
	var count := corners.size()
	for i in count:
		var here: Vector2 = corners[i]
		if not closed and (i == 0 or i == count - 1):
			curve.add_point(_ground(here))
			continue
		var previous: Vector2 = corners[(i - 1 + count) % count]
		var following: Vector2 = corners[(i + 1) % count]
		var into := (here - previous)
		var out := (following - here)
		if into.length() < 0.001 or out.length() < 0.001:
			curve.add_point(_ground(here))
			continue
		# Never round by more than half of either arm, or two adjacent corners
		# eat each other and the route crosses itself.
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
	if closed:
		curve.add_point(curve.get_point_position(0))
	return curve


static func _ground(at: Vector2) -> Vector3:
	return Vector3(at.x, ROAD_SURFACE, at.y)
