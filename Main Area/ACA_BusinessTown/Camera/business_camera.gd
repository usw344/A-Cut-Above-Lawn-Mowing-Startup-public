class_name ACABusinessCamera
extends Node3D
## Fixed-orientation isometric camera rig.
##
## This node is the pivot: it sits on the point the camera looks at. The child
## Camera3D keeps a constant offset and rotation, so focusing a building only ever
## slides the pivot and changes the orthographic size - the town never spins.

@export var camera: Camera3D

@export_group("Framing")
## Yaw of the isometric view, degrees. 45 gives the classic two-faces-visible look.
@export var yaw_degrees: float = 42.0
## Pitch of the isometric view, degrees below the horizon.
@export var pitch_degrees: float = 33.0
@export var boom_length: float = 70.0

@export_group("Overview")
@export var overview_pivot: Vector3 = Vector3.ZERO
## Vertical framing of the overview, in world units (Camera3D.size is a full extent).
@export var overview_size: float = 27.5
## Horizontal extent that must stay on screen, so wide layouts survive narrow windows.
@export var overview_min_width: float = 46.0

@export_group("Transition")
@export var transition_time: float = 0.55

var _tween: Tween
var _focused := false
var _focus_pivot := Vector3.ZERO
var _focus_size := 11.0


func _ready() -> void:
	if camera == null:
		camera = get_node_or_null(^"Camera3D") as Camera3D
	if camera == null:
		push_error("ACABusinessCamera has no Camera3D assigned.")
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_place_camera()
	position = overview_pivot
	camera.size = _fitted_size(overview_size, true)
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_on_viewport_resized)


func _place_camera() -> void:
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var dir := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	)
	camera.position = dir * boom_length
	camera.rotation = Vector3(-pitch, yaw, 0.0)
	camera.near = 0.5
	camera.far = boom_length * 3.0


## Grows the vertical framing when the window is too narrow to fit the whole town.
## Only the overview is width-guarded; a focused shot is allowed to zoom right in.
func _fitted_size(desired: float, guard_width: bool) -> float:
	if not guard_width:
		return desired
	var vp := get_viewport()
	if vp == null:
		return desired
	var vs := vp.get_visible_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return desired
	var aspect := vs.x / vs.y
	return maxf(desired, overview_min_width / maxf(aspect, 0.1))


func _on_viewport_resized() -> void:
	if camera == null or (_tween != null and _tween.is_valid()):
		return
	if _focused:
		camera.size = _fitted_size(_focus_size, false)
	else:
		camera.size = _fitted_size(overview_size, true)


func focus_on(pivot: Vector3, ortho_size: float) -> void:
	_focused = true
	_focus_pivot = pivot
	_focus_size = ortho_size
	_run(pivot, _fitted_size(ortho_size, false))


func reset_view() -> void:
	_focused = false
	_run(overview_pivot, _fitted_size(overview_size, true))


func _run(target_pivot: Vector3, target_size: float) -> void:
	if camera == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, ^"position", target_pivot, transition_time)
	_tween.tween_property(camera, ^"size", target_size, transition_time)
