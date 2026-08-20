extends Node
## DEVELOPMENT ONLY. Renders close-up, grazing-angle shots of the REAL Business
## Town so surface artefacts (Z-fighting, floating decals, gaps) can be judged
## from pixels. Needs a real renderer; it captures the viewport.
##
##   godot --path . "res://Dev tools/Validation/Town Probe.tscn" -- "--town-output=<dir>"
##
## Shallow angles are deliberate: two exactly coplanar surfaces are most obvious
## when the camera is nearly in their plane.
##
## Each shot is also rendered a SECOND time with the camera's far plane nudged.
## `near`/`far` appear only in the depth row of the projection matrix, so the
## image is pixel-identical EXCEPT where two surfaces are tied in depth: there,
## the different quantisation flips which one wins. Every pixel that changes is
## a Z-fighting pixel, which turns "does this look wrong?" into a number.
##
## Shadows and SSAO are switched off for BOTH halves of that comparison: the
## directional shadow splits are derived from the camera range, so leaving them
## on paints every shadow edge in the town red and buries the real signal.

const DEFAULT_OUTPUT_DIR := "user://town_probe"
const SETTLE_FRAMES := 30
## Far-plane perturbation used to break depth ties. Big enough to reshuffle the
## quantisation, small enough that nothing legitimately clips differently.
const FAR_A := 400.0
const FAR_B := 331.7
const DIFF_THRESHOLD := 6

## name, camera position, look-at target, fov
const SHOTS := [
	["parkinglot-graze", Vector3(8.4, 0.62, 6.6), Vector3(1.6, 0.10, 2.9), 40.0],
	["parkinglot-high", Vector3(4.6, 3.4, 8.2), Vector3(2.2, 0.10, 3.2), 45.0],
	["parkpath-west", Vector3(-16.6, 0.85, 6.6), Vector3(-12.9, 0.08, 3.4), 40.0],
	["parkpath-east", Vector3(-1.2, 0.8, 7.0), Vector3(-4.7, 0.08, 3.6), 40.0],
	["parkpath-high", Vector3(-8.8, 4.2, 11.0), Vector3(-8.8, 0.08, 4.2), 46.0],
	["futurelot-sill", Vector3(13.4, 1.1, 1.4), Vector3(10.9, 0.22, -1.4), 34.0],
	["mainstreet-graze", Vector3(-15.5, 0.9, 4.2), Vector3(10.0, 0.10, -0.2), 32.0],
	["frontage-graze", Vector3(-14.0, 0.75, -4.6), Vector3(8.0, 0.09, -2.0), 30.0],
	["overview-persp", Vector3(-13.0, 9.5, 15.0), Vector3(-0.5, 0.6, -1.5), 45.0],
]

var _dir: String = DEFAULT_OUTPUT_DIR
var _camera: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = _output_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	print("[TOWN] writing to %s" % _dir)
	_run.call_deferred()


func _output_dir() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--town-output="):
			return arg.trim_prefix("--town-output=")
	return DEFAULT_OUTPUT_DIR


func _run() -> void:
	GameSession.start_new_game()
	while GameSession.current_screen() != ACAGameSession.Screen.TOWN:
		await get_tree().process_frame
	await _settle(50)

	var scene := get_tree().current_scene
	var town := scene.get_node_or_null(^"BusinessTown")
	if town == null:
		printerr("[TOWN] no BusinessTown in the town screen")
		get_tree().quit(1)
		return
	var hud := town.get_node_or_null(^"BusinessHUD")
	if hud != null:
		hud.visible = false
	AppUI.clear_notifications()
	_set_depth_dependents(town, false)

	# The real rig, as the player sees it, with the same tie-break test.
	var rig_cam: Camera3D = town.get_node_or_null(^"CameraRig/Camera3D")
	await _settle(SETTLE_FRAMES)
	await _shot("real-overview", rig_cam)

	_camera = Camera3D.new()
	_camera.near = 0.08
	town.add_child(_camera)
	_camera.make_current()

	for shot in SHOTS:
		_camera.global_position = shot[1]
		_camera.look_at(shot[2], Vector3.UP)
		_camera.fov = float(shot[3])
		await _settle(SETTLE_FRAMES)
		await _shot(String(shot[0]), _camera)

	_set_depth_dependents(town, true)
	print("[TOWN] done, %d shots" % (SHOTS.size() + 1))
	get_tree().quit(0)


## Shadow maps and SSAO are both driven by the camera depth range, so they move
## when `far` moves and would show up as depth ties that are not there.
func _set_depth_dependents(town: Node, enabled: bool) -> void:
	for l in [town.get_node_or_null(^"Sun"), town.get_node_or_null(^"FillLight")]:
		if l is DirectionalLight3D:
			(l as DirectionalLight3D).shadow_enabled = enabled and l.name == &"Sun"
	var we := town.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ssao_enabled = enabled


## One shot: image, tie-break image, and a diff mask of the pixels that moved.
func _shot(name: String, cam: Camera3D) -> void:
	if cam == null:
		return
	var was_far := cam.far
	cam.far = FAR_A
	await _settle(3)
	var a := await _grab()
	a.save_png("%s/town-%s.png" % [_dir, name])
	cam.far = FAR_B
	await _settle(3)
	var b := await _grab()
	cam.far = was_far
	var count := _write_diff(a, b, name)
	print("[TOWN] %-18s  depth-tie pixels: %d" % [name, count])


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _write_diff(a: Image, b: Image, name: String) -> int:
	var w := a.get_width()
	var h := a.get_height()
	var mask := Image.create(w, h, false, Image.FORMAT_RGB8)
	var count := 0
	for y in h:
		for x in w:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := int(maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b)) * 255.0)
			if d >= DIFF_THRESHOLD:
				count += 1
				mask.set_pixel(x, y, Color(1, 0, 0))
			else:
				mask.set_pixel(x, y, ca.darkened(0.72))
	if count > 0:
		mask.save_png("%s/zfight-%s.png" % [_dir, name])
	return count


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
