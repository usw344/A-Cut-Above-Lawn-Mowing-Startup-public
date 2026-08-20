extends Node3D
## DEVELOPMENT ONLY. Renders JUST THE SKY, so cloud parameters can be judged
## from pixels in one run instead of one 33-second trailer per guess.
##
##   godot --path . "res://Dev tools/Validation/Sky Probe.tscn" -- "--sky-output=<dir>"
##
## **Needs a real renderer.** It captures the viewport.
##
## Why it exists: the Milestone 10 weather hero shot had no visible clouds. The
## adapter was composing exactly the values it claimed to (verified by dumping
## the live shader parameters), so the question was what those values actually
## LOOK like. This answers that directly.
##
## `clouds_cumulus_size` is the one that mattered. Sky3D samples its cumulus
## noise at `intersection_point * clouds_cumulus_size * 0.0212`, and at the
## shipped 0.5 the dominant octave barely moves across the whole dome - the
## result is a featureless overcast wash rather than clouds.

const PRESET_MANAGER := preload("res://Weather/Preset Manager/Preset Manager.tscn")

## Camera aim: low and tilted up, the way the trailer's weather hero shot sits.
const CAMERA_PITCH_DEGREES := 18.0
const CAMERA_FOV := 62.0

## One PNG per row. A `size` of -1 means "leave whatever the adapter composed",
## which is the review case; an explicit size is a sweep case for re-tuning.
const CASES: Array = [
	# THE SHIPPED LOOKS - review these.
	{"weather": "Clear", "hour": 12.0, "size": -1.0},
	{"weather": "Clear", "hour": 16.3, "size": -1.0},
	{"weather": "Foggy", "hour": 12.0, "size": -1.0},
	{"weather": "Rain", "hour": 11.6, "size": -1.0},
	{"weather": "Rain", "hour": 15.4, "size": -1.0},
	{"weather": "Rain", "hour": 22.0, "size": -1.0},
	# THE SWEEP that chose them. 0.5 is Sky3D's shipped default and renders a
	# featureless wash at this dome scale - that is the bug this probe found.
	{"weather": "Rain", "hour": 15.4, "size": 0.5},
	{"weather": "Rain", "hour": 15.4, "size": 2.0},
	{"weather": "Rain", "hour": 15.4, "size": 9.0},
	{"weather": "Clear", "hour": 12.0, "size": 0.5},
]

var _out_dir: String = ""
var _pm: preset_manager = null
var _camera: Camera3D = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--sky-output="):
			_out_dir = arg.trim_prefix("--sky-output=")
	if _out_dir.is_empty():
		_out_dir = "sky_probe"
	DirAccess.make_dir_recursive_absolute(_out_dir)

	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_camera.rotation_degrees = Vector3(CAMERA_PITCH_DEGREES, 0.0, 0.0)
	_camera.current = true
	add_child(_camera)

	_pm = PRESET_MANAGER.instantiate()
	# The probe owns the hour; nothing else may overwrite it per frame.
	_pm.follow_world_clock = false
	add_child(_pm)

	_run.call_deferred()


func _run() -> void:
	print("\n================= SKY PROBE =================")
	print("[SKY] writing to %s" % _out_dir)
	await _settle(20)

	for case: Dictionary in CASES:
		var weather := String(case["weather"])
		var hour := float(case["hour"])
		var size := float(case["size"])

		# The adapter keeps writing its composed look every tick, so a sweep
		# value has to be applied with the adapter STOPPED - otherwise the
		# override is overwritten before the frame is captured and the probe
		# reports a value it did not actually render.
		_pm.visual.set_process(true)
		_pm.apply_world_state_immediate(weather, hour)
		await _settle(30)
		if size >= 0.0:
			_pm.visual.set_process(false)
			_pm.skydome.clouds_cumulus_size = size
			await _settle(4)

		var label := "shipped" if size < 0.0 else "size%05.1f" % size
		var name := "%s-%04.1f-%s.png" % [weather.to_lower(), hour, label]
		await _save("%s/%s" % [_out_dir, name])
		print("[SKY] %-34s coverage=%.2f cumulus=%.2f size=%.1f intensity=%.2f" % [
			name, _pm.skydome.clouds_coverage, _pm.skydome.clouds_cumulus_coverage,
			_pm.skydome.clouds_cumulus_size, _pm.skydome.clouds_cumulus_intensity])

	print("[SKY] done, %d frames" % CASES.size())
	print("=============================================\n")
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
