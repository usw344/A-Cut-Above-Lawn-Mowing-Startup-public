class_name ACATrailerMowerAdapter
extends Node
## DEVELOPMENT / MEDIA TOOLING. Takes controlled ownership of the REAL rider
## mower for the length of a trailer shot.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## Trailer V2 drove the real controller at 1.4x gameplay speed by holding the
## real input actions down. That produced footage of ALTERED GAMEPLAY, and it
## had a specific visual failure: the mower is authored two units above the lawn
## and falls into place, so a shot that starts the instant it is repositioned
## catches it dropping, and a fast repositioned mower on a slope can visibly
## launch.
##
## A trailer is a PRESENTATION, not a physics benchmark. So for trailer shots
## the mower's transform is owned here instead:
##
##   * the mower is the REAL `Mower Rider.tscn` -- real model, real wheels, real
##     steering wheel, real engine audio, real fuel burn;
##   * its own `_physics_process` is switched off, so gravity, `move_and_slide`
##     and the input actions are out of the picture entirely;
##   * it is planted at the lawn's own ground height and never leaves it;
##   * it travels a designed path at a speed this file owns, which is nothing to
##     do with `model.speed` and therefore cannot affect gameplay.
##
## Everything is restored by `release()`, which `Trailer Test` asserts.
##
## ---------------------------------------------------------------------------
## WHY THE GROUND HEIGHT IS ASKED FOR, NOT RAYCAST
## ---------------------------------------------------------------------------
## The obvious answer is a downward ray, and it was the wrong tool when every
## blade of grass was a three unit static body: the ray hit GRASS and parked the
## machine on top of the lawn.
##
## The terrain now answers its own height directly, so the director hands this
## adapter that query through `set_ground_provider()` and a driven shot follows
## the land. Without a provider it falls back to the single height the director
## measured, which is what a flat property amounts to anyway.

## Wheel spin is `speed * 2 * delta` radians in the real visual script. At
## trailer speed that strobes, so the visual is fed a capped speed. It still
## reads as "moving fast" and stays legible on video.
const MAX_VISUAL_WHEEL_SPEED := 17.0

## Yaw approach rate while following a path, e-foldings per second. Slower than
## the gameplay controller's 18 on purpose: this is a camera subject, and a
## cinematic turn should arc.
const YAW_SMOOTHING := 3.4

## A trailer-only suspension: a small bob and a roll proportional to yaw rate,
## so a scripted mower does not read as a decal sliding over the lawn.
##
## THESE ARE THE DEFAULTS, NOT THE LAW. A shot whose camera is MOUNTED on the
## mower turns every millimetre of bob into camera shake, so `set_suspension()`
## lets an over-the-mower shot damp it almost to nothing while a side shot keeps
## enough of it to look sprung. Milestone 13: the shipped numbers were tuned for
## a distant chase and read as hopping the moment the lens came close.
const BOB_HEIGHT := 0.045
const BOB_HZ := 2.4
const ROLL_PER_YAW_RATE := 0.16
const MAX_ROLL := 0.05

## Emitted every frame the mower moves, with the segment it covered. The lawn
## adapter cuts along it -- with physics off there are no slide collisions, so
## nothing else would tell the grid anything happened.
signal moved(from: Vector3, to: Vector3)

var _mower: CharacterBody3D = null
var _parts: Node = null
var _ground_y: float = 0.0
## Optional (x, z) -> ground height query, supplied by the director from the
## property's terrain. Empty means the flat fallback above.
var _ground_provider: Callable = Callable()
## How far the measured plant height sat above the raw terrain, so a provider
## keeps the same wheels-on-the-dirt offset the director worked out.
var _ride_height: float = 0.0
var _bound: bool = false

var _path: Curve3D = null
var _distance: float = 0.0
var _speed: float = 0.0
var _loop: bool = false
var _yaw: float = 0.0
var _target_yaw: float = 0.0
var _turn_rate: float = 0.0
var _bob_phase: float = 0.0
var _roll: float = 0.0
var _driving: bool = false
var _bob_height: float = BOB_HEIGHT
var _bob_hz: float = BOB_HZ
var _roll_scale: float = ROLL_PER_YAW_RATE

## Saved so `release()` leaves the mower exactly as it was found.
var _saved_physics_process: bool = true
var _saved_process: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ================================================================== ownership

## THE terrain height query, (x, z) -> float. Set before `bind()` so the ride
## height can be worked out from the same measurement the director made. An
## invalid Callable puts the adapter back on a single flat height.
func set_ground_provider(provider: Callable) -> void:
	_ground_provider = provider


## Take the mower over. `ground_y` is where the director decided the wheels
## belong at the middle of the lawn.
func bind(mower: CharacterBody3D, ground_y: float) -> void:
	if mower == null or not is_instance_valid(mower):
		return
	release()
	_mower = mower
	_parts = mower.get_node_or_null(^"LawnTractor01")
	_ground_y = ground_y
	# How far this machine's origin sits above its lowest visible point. Added
	# to whatever the terrain answers, so the wheels stay on the ground the
	# camera can see wherever the shot takes it.
	_ride_height = visual_lift(mower)
	_saved_physics_process = mower.is_physics_processing()
	_saved_process = mower.is_processing()
	# THE handover. With this off the controller reads no input, applies no
	# gravity, calls no move_and_slide and emits no collisions.
	mower.set_physics_process(false)
	mower.velocity = Vector3.ZERO
	_yaw = mower.rotation.y
	_target_yaw = _yaw
	_bound = true
	reset_suspension()
	# The engine is running throughout every trailer shot, so pin the loop at
	# its moving level once instead of leaving it wherever the controller's last
	# frame left it.
	var audio := mower.get_node_or_null(^"AudioStreamPlayer3D") as AudioStreamPlayer3D
	if audio != null:
		audio.volume_db = float(mower.get(&"moving_volume_db"))
		audio.pitch_scale = float(mower.get(&"moving_pitch"))
		if not audio.playing:
			audio.play()


## Hand the mower back exactly as it was.
func release() -> void:
	if _mower != null and is_instance_valid(_mower):
		_mower.set_physics_process(_saved_physics_process)
		_mower.set_process(_saved_process)
		_mower.velocity = Vector3.ZERO
		_mower.set(&"target_body_yaw", _mower.rotation.y)
	_mower = null
	_parts = null
	_path = null
	_bound = false
	_driving = false


func is_bound() -> bool:
	return _bound and _mower != null and is_instance_valid(_mower)


## How much sprung movement THIS shot wants. A mounted, over-the-mower lens
## needs almost none -- at that range the default bob is camera shake, which is
## exactly what made the old mowing footage read as comical.
func set_suspension(bob_height: float, bob_hz: float, roll_scale: float) -> void:
	_bob_height = maxf(bob_height, 0.0)
	_bob_hz = maxf(bob_hz, 0.0)
	_roll_scale = maxf(roll_scale, 0.0)


func reset_suspension() -> void:
	_bob_height = BOB_HEIGHT
	_bob_hz = BOB_HZ
	_roll_scale = ROLL_PER_YAW_RATE


## The height the mower's ORIGIN has to sit at for its lowest visible point to
## touch `ground_plane_y`. Measured from the real meshes, so it survives the
## model being rescaled.
##
## WHY THIS IS NOT "WHERE THE PHYSICS SETTLED". See the note at the top of the
## file: the settled height is on top of the GRASS, and the mowing ground's own
## collision box stands half a unit proud of the plane you can actually see. Up
## to Milestone 12 the trailer used the settled value and the mower flew.
static func visual_lift(mower: Node3D) -> float:
	if mower == null or not is_instance_valid(mower):
		return 0.0
	var lowest: float = INF
	for node in mower.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	if is_inf(lowest):
		return 0.0
	return mower.global_position.y - lowest


func mower() -> Node3D:
	return _mower


# ==================================================================== staging

## Put the mower down at a spot, facing `yaw`, planted. No fall, no settle.
func place(where: Vector3, yaw: float) -> void:
	if not is_bound():
		return
	_path = null
	_driving = false
	_yaw = yaw
	_target_yaw = yaw
	_roll = 0.0
	var pos := where
	pos.y = _ground_y_at(where)
	_mower.global_position = pos
	_mower.rotation = Vector3(0.0, yaw, 0.0)
	_mower.set(&"target_body_yaw", yaw)
	_mower.velocity = Vector3.ZERO


## Drive a designed path. `points` are world positions; y is ignored and
## replaced by the ground height, so a path can be authored in 2D.
func drive_path(points: PackedVector3Array, speed: float, start_at: float = 0.0) -> void:
	if not is_bound() or points.size() < 2:
		return
	_path = Curve3D.new()
	for p in points:
		_path.add_point(Vector3(p.x, _ground_y_at(p), p.z))
	for i in _path.point_count:
		var prev: Vector3 = _path.get_point_position(maxi(i - 1, 0))
		var next: Vector3 = _path.get_point_position(mini(i + 1, _path.point_count - 1))
		var tangent: Vector3 = (next - prev) * 0.3
		_path.set_point_in(i, -tangent)
		_path.set_point_out(i, tangent)
	_speed = speed
	_distance = clampf(start_at, 0.0, 1.0) * _path.get_baked_length()
	_driving = true
	# Snap to the head of the path so the first frame of the shot is already
	# composed -- no lurch into position after the cut.
	_snap_to_path()


## Drive in a straight line from where it stands, optionally arcing.
## `turn_rate` is radians per second.
func drive_straight(speed: float, turn_rate: float = 0.0) -> void:
	if not is_bound():
		return
	_path = null
	_speed = speed
	_turn_rate = turn_rate
	_driving = true


func stop() -> void:
	_driving = false


func is_driving() -> bool:
	return _driving


func position_now() -> Vector3:
	return _mower.global_position if is_bound() else Vector3.ZERO


func yaw_now() -> float:
	return _yaw


## Where the mower will be `seconds` from now, for composing a shot that has to
## have it enter or leave frame at a particular moment.
func position_after(seconds: float) -> Vector3:
	if not is_bound():
		return Vector3.ZERO
	if _path != null:
		var d := _distance + _speed * seconds
		return _path.sample_baked(clampf(d, 0.0, _path.get_baked_length()), true)
	var forward := Vector3(sin(_yaw), 0.0, cos(_yaw))
	return _mower.global_position + forward * _speed * seconds


# ==================================================================== driving

func _process(delta: float) -> void:
	if not is_bound() or not _driving or delta <= 0.0:
		return

	var from: Vector3 = _mower.global_position
	var previous_yaw: float = _yaw

	if _path != null:
		_advance_path(delta)
	else:
		_advance_straight(delta)

	var yaw_rate: float = wrapf(_yaw - previous_yaw, -PI, PI) / delta
	_apply_body(delta, yaw_rate)
	_feed_visuals(delta, yaw_rate)

	# The real fuel system keeps running, so the production HUD's gauge in the
	# gameplay-proof shot is showing a tank that is genuinely being burnt.
	MowerFuel.consume(delta, 1.0)

	var to: Vector3 = _mower.global_position
	if from.distance_squared_to(to) > 0.0:
		moved.emit(from, to)


func _advance_path(delta: float) -> void:
	var length := _path.get_baked_length()
	_distance += _speed * delta
	if _distance >= length:
		_distance = length
		_driving = false
	_snap_to_path()


func _snap_to_path() -> void:
	var length := _path.get_baked_length()
	var here := _path.sample_baked(clampf(_distance, 0.0, length), true)
	var ahead := _path.sample_baked(clampf(_distance + 1.5, 0.0, length), true)
	var direction := ahead - here
	if direction.length_squared() > 0.0001:
		_target_yaw = atan2(direction.x, direction.z)
	_mower.global_position = Vector3(here.x, _ground_y_at(here), here.z)


func _advance_straight(delta: float) -> void:
	_target_yaw += _turn_rate * delta
	var forward := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var next: Vector3 = _mower.global_position + forward * _speed * delta
	_mower.global_position = Vector3(next.x, _ground_y_at(next), next.z)


## Plant it, then add the suspension. The bob is applied ON TOP of the ground
## height, never instead of it, so the mower can never end up under the lawn.
func _apply_body(delta: float, yaw_rate: float) -> void:
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-YAW_SMOOTHING * delta))

	_bob_phase += delta * _bob_hz * TAU
	var bob := sin(_bob_phase) * _bob_height
	var wanted_roll := clampf(-yaw_rate * _roll_scale, -MAX_ROLL, MAX_ROLL)
	_roll = lerpf(_roll, wanted_roll, 1.0 - exp(-6.0 * delta))

	var pos := _mower.global_position
	pos.y = _ground_y_at(pos) + bob
	_mower.global_position = pos
	_mower.rotation = Vector3(0.0, _yaw, _roll)
	# Kept in step so releasing the mower does not snap it to a stale target.
	_mower.set(&"target_body_yaw", _yaw)


## The mower's own visual script still runs; it just is not being fed by the
## controller any more. Wheels and the steering wheel come from here instead.
func _feed_visuals(delta: float, yaw_rate: float) -> void:
	if _parts == null or not is_instance_valid(_parts):
		return
	var visual_speed: float = minf(_speed, MAX_VISUAL_WHEEL_SPEED)
	_parts.call(&"send_speed_data", Vector3(0.0, 0.0, visual_speed), delta)
	if absf(yaw_rate) > 0.0001:
		_parts.call(&"send_rotation_data", yaw_rate * delta)


## Ask the terrain, or fall back to the measured height. See the note at the top
## of the file for why this is not a raycast.
func _ground_y_at(where: Vector3) -> float:
	if _ground_provider.is_valid():
		return float(_ground_provider.call(where.x, where.z)) + _ride_height
	return _ground_y
