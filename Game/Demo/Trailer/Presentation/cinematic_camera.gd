class_name ACACinematicCamera
extends Camera3D
## DEVELOPMENT / MEDIA TOOLING. The trailer's camera. Treated as a FILM camera,
## not as a "camera that follows the player".
##
## Deliberately SEPARATE from the gameplay cameras. Gameplay cameras are tuned
## to feel responsive under a player's hand; this one is tuned to compose a
## shot. Never slow a mower camera down to serve this file -- that was the exact
## bug Milestone 5 fixed.
##
## ---------------------------------------------------------------------------
## A SHOT IS A DICTIONARY
## ---------------------------------------------------------------------------
## Only `mode` is required. Everything else falls back to DEFAULT_SHOT.
##
## WHERE THE CAMERA IS
##   mode "static"  position                fixed world point
##   mode "follow"  offset / world_offset   offset in the TARGET's local frame
##                                          (x right, y up, z forward - the
##                                          mower faces +Z) and in world axes
##   mode "orbit"   pivot radius height speed start_angle
##   mode "rail"    rail: Array[Vector3]    a dolly track, travelled once over
##                  duration                `duration` seconds with `ease`
##   drift          world units/second added to any of the above (a slow crane)
##
## WHERE THE CAMERA LOOKS
##   look_at        an explicit world point
##   look_rail      Array[Vector3] - the aim point runs its own track, so a
##                  dolly can pan across a subject instead of pivoting on it
##   look_offset    relative to the target, in the TARGET's local frame, so
##                  `z` positive is always "ahead of the mower"
##   look_lead      extra units ahead of the target along its facing. Positive
##                  leaves negative space in FRONT; negative shows what it cut.
##
## THE LENS
##   fov            degrees at the start of the shot
##   fov_to         degrees at the end of `duration` - a slow push or pull
##   dof            {distance, transition, amount} or {"target": true} to focus
##                  on the tracked subject. Camera-local, never the environment.
##
## FEEL
##   damp / look_damp   e-foldings per second. 0 is rigid.
##   ease           "linear" | "in" | "out" | "in_out" - shapes rail and lens
##   min_ground     the lens is never allowed below this world Y
##
## `cut_to()` snaps (a hard cut between shots); `ease_to()` keeps the current
## position and lets the damping carry it into the new framing.

const DEFAULT_SHOT := {
	"mode": "follow",
	"offset": Vector3(6.0, 3.0, 0.0),
	"world_offset": Vector3.ZERO,
	"position": Vector3.ZERO,
	"drift": Vector3.ZERO,
	"pivot": Vector3.ZERO,
	"radius": 40.0,
	"height": 20.0,
	"speed": 12.0,
	"start_angle": 0.0,
	"rail": [],
	"look_rail": [],
	"duration": 4.0,
	"ease": "in_out",
	"look_offset": Vector3(0.0, 1.2, 0.0),
	"look_lead": 0.0,
	"fov": 55.0,
	"fov_to": -1.0,
	"damp": 3.0,
	"look_damp": 4.0,
	"min_ground": -1000000.0,
	"dof": {},
}

var target: Node3D = null

var _shot: Dictionary = DEFAULT_SHOT.duplicate(true)
var _shot_time: float = 0.0
var _aim: Vector3 = Vector3.ZERO
var _has_aim: bool = false
var _rail: Curve3D = null
var _look_rail: Curve3D = null
var _attributes: CameraAttributesPractical = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Trailer-only depth of field. It lives on the CAMERA, not on the scene's
	# WorldEnvironment, so no gameplay camera and no saved setting is touched.
	_attributes = CameraAttributesPractical.new()
	attributes = _attributes
	current = true


func set_target(node: Node3D) -> void:
	target = node


## Hard cut: place the camera exactly where the shot wants it.
func cut_to(shot: Dictionary) -> void:
	_apply_shot(shot)
	global_position = _clamped(_desired_position())
	_aim = _desired_aim()
	_has_aim = true
	_face(_aim)


## Soft change: keep the current position and let the damping carry it over.
func ease_to(shot: Dictionary) -> void:
	_apply_shot(shot)


## How far through `duration` this shot is, 0..1.
func shot_progress() -> float:
	return clampf(_shot_time / maxf(float(_shot["duration"]), 0.001), 0.0, 1.0)


func _apply_shot(shot: Dictionary) -> void:
	_shot = DEFAULT_SHOT.duplicate(true)
	for key: String in shot:
		_shot[key] = shot[key]
	_shot_time = 0.0
	_rail = _curve_from(_shot["rail"])
	_look_rail = _curve_from(_shot["look_rail"])
	fov = float(_shot["fov"])
	_apply_dof()


## A Curve3D through the points, so a dolly is a smooth track rather than a
## sequence of straight legs with corners in it.
func _curve_from(points: Variant) -> Curve3D:
	if not (points is Array) or (points as Array).size() < 2:
		return null
	var curve := Curve3D.new()
	for p in points:
		curve.add_point(p)
	# Godot's default handles are zero, which gives a polyline. Give each point
	# a handle along its neighbours' chord so the track actually curves.
	for i in curve.point_count:
		var prev: Vector3 = curve.get_point_position(maxi(i - 1, 0))
		var next: Vector3 = curve.get_point_position(mini(i + 1, curve.point_count - 1))
		var tangent: Vector3 = (next - prev) * 0.28
		curve.set_point_in(i, -tangent)
		curve.set_point_out(i, tangent)
	return curve


func _apply_dof() -> void:
	if _attributes == null:
		return
	var dof: Dictionary = _shot["dof"]
	if dof.is_empty():
		_attributes.dof_blur_far_enabled = false
		_attributes.dof_blur_near_enabled = false
		return
	_attributes.dof_blur_amount = float(dof.get("amount", 0.06))
	_attributes.dof_blur_far_enabled = true
	_attributes.dof_blur_far_distance = float(dof.get("distance", 40.0))
	_attributes.dof_blur_far_transition = float(dof.get("transition", 20.0))
	_attributes.dof_blur_near_enabled = bool(dof.get("near", false))
	_attributes.dof_blur_near_distance = float(dof.get("near_distance", 4.0))
	_attributes.dof_blur_near_transition = float(dof.get("near_transition", 3.0))


func _process(delta: float) -> void:
	_shot_time += delta

	var wanted := _clamped(_desired_position())
	var damp := float(_shot["damp"])
	if damp <= 0.0:
		global_position = wanted
	else:
		global_position = global_position.lerp(wanted, 1.0 - exp(-damp * delta))

	var wanted_aim := _desired_aim()
	if not _has_aim:
		_aim = wanted_aim
		_has_aim = true
	var look_damp := float(_shot["look_damp"])
	if look_damp <= 0.0:
		_aim = wanted_aim
	else:
		_aim = _aim.lerp(wanted_aim, 1.0 - exp(-look_damp * delta))
	_face(_aim)

	# A lens that moves through the shot. Same eased parameter as the rail, so a
	# push-in lands with the dolly rather than ahead of it.
	var fov_to := float(_shot["fov_to"])
	if fov_to > 0.0:
		fov = lerpf(float(_shot["fov"]), fov_to, _eased())

	# Holding focus ON the subject is the point of a hero close-up; a fixed
	# focal distance drifts out of focus as the mower moves.
	var dof: Dictionary = _shot["dof"]
	if not dof.is_empty() and bool(dof.get("target", false)) and _attributes != null \
			and target != null and is_instance_valid(target):
		_attributes.dof_blur_far_distance = global_position.distance_to(
			target.global_position) * float(dof.get("target_scale", 1.2))


## The one clipping guard that is worth having generically: a lens below the
## ground plane sees the underside of the world. Everything else is handled by
## composing the shot so it does not pass through geometry.
func _clamped(wanted: Vector3) -> Vector3:
	wanted.y = maxf(wanted.y, float(_shot["min_ground"]))
	return wanted


func _face(point: Vector3) -> void:
	if global_position.distance_squared_to(point) <= 0.0001:
		return
	var to_point := (point - global_position).normalized()
	# look_at() errors if the aim is exactly straight up or down. Nudge rather
	# than fill the log for a whole shot.
	if absf(to_point.dot(Vector3.UP)) > 0.9995:
		point += Vector3(0.01, 0.0, 0.01)
	look_at(point, Vector3.UP)


## The shot's eased 0..1 parameter.
func _eased() -> float:
	var t := clampf(_shot_time / maxf(float(_shot["duration"]), 0.001), 0.0, 1.0)
	match String(_shot["ease"]):
		"linear":
			return t
		"in":
			return t * t
		"out":
			return 1.0 - (1.0 - t) * (1.0 - t)
		_:
			return smoothstep(0.0, 1.0, t)


func _desired_position() -> Vector3:
	var drift: Vector3 = _shot["drift"] * _shot_time
	match String(_shot["mode"]):
		"static":
			return _shot["position"] + drift
		"rail":
			if _rail == null:
				return _shot["position"] + drift
			return _rail.sample_baked(_eased() * _rail.get_baked_length(), true) + drift
		"orbit":
			var angle := deg_to_rad(float(_shot["start_angle"])
				+ float(_shot["speed"]) * _shot_time)
			var pivot: Vector3 = _shot["pivot"]
			var radius: float = float(_shot["radius"])
			return pivot + Vector3(
				cos(angle) * radius,
				float(_shot["height"]),
				sin(angle) * radius) + drift
		_:
			if target == null or not is_instance_valid(target):
				return global_position
			var basis_offset: Vector3 = target.global_transform.basis * _shot["offset"]
			return target.global_position + basis_offset + _shot["world_offset"] + drift


func _desired_aim() -> Vector3:
	if _look_rail != null:
		return _look_rail.sample_baked(_eased() * _look_rail.get_baked_length(), true)
	if _shot.has("look_at") and _shot["look_at"] is Vector3:
		return _shot["look_at"]
	if String(_shot["mode"]) == "orbit":
		return _shot["pivot"]
	if target != null and is_instance_valid(target):
		var forward: Vector3 = target.global_transform.basis.z
		return target.global_position \
			+ target.global_transform.basis * _shot["look_offset"] \
			+ forward * float(_shot["look_lead"])
	return global_position + Vector3.FORWARD
