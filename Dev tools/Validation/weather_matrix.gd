extends Node
## DEVELOPMENT ONLY. Renders the whole time-of-day x weather matrix in the REAL
## mowing scene and writes one screenshot per combination, so the weather look
## is judged from pixels rather than from numbers.
##
##   godot --path <project> "res://Dev tools/Validation/Weather Matrix.tscn" -- "--matrix-output=<dir>"
##
## Needs a real renderer; it captures the viewport.
##
## Four times x three weathers = twelve shots, each from a fixed camera pose so
## two runs are comparable side by side. It drives the SAME public API the game
## uses (`WorldClock.advance_to_hour`, `WorldClock.set_weather`) - nothing is
## poked into Sky3D directly.

const DEFAULT_OUTPUT_DIR := "user://weather_matrix"

## Hours, chosen to sit inside each named profile rather than on a blend edge.
const TIMES := [
	["morning", 7.0],
	["day", 12.0],
	["evening", 16.3],
	["night", 22.0],
]
const WEATHERS := ["Clear", "Foggy", "Rain"]

## Frames to let the adapter settle and the rain fade in before capturing.
const SETTLE_FRAMES := 150

var _dir: String = DEFAULT_OUTPUT_DIR


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = _output_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	print("[MATRIX] writing to %s" % _dir)
	_run.call_deferred()


func _output_dir() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--matrix-output="):
			return arg.trim_prefix("--matrix-output=")
	return DEFAULT_OUTPUT_DIR


func _run() -> void:
	GameSession.start_new_game()
	await _await_screen(ACAGameSession.Screen.TOWN)
	await _settle(60)

	await _capture_town()

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		await _settle(10)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		printerr("[MATRIX] no offers; cannot enter the mowing scene")
		get_tree().quit(1)
		return

	var job: ACAJob = offers[0]
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	await _await_screen(ACAGameSession.Screen.MOWING)
	await _settle(60)

	# The gameplay HUD and any toast would sit over every shot; this is a look
	# review, not a UI review.
	var ui := get_tree().current_scene.get_node_or_null(^"Gameplay UI")
	if ui != null:
		ui.visible = false
	AppUI.clear_notifications()

	# A fixed pose, so two runs line up and a regression is obvious.
	var camera := _pose_camera()
	if camera == null:
		printerr("[MATRIX] no camera in the mowing scene")
		get_tree().quit(1)
		return

	for weather in WEATHERS:
		WorldClock.set_weather(weather)
		for entry in TIMES:
			var label: String = entry[0]
			var hour: float = entry[1]
			WorldClock.advance_to_hour(hour)
			await _settle_measured(SETTLE_FRAMES, "%s %s" % [weather, label])
			await _capture("%s-%s" % [weather.to_lower(), label])

	print("[MATRIX] done, %d shots" % (WEATHERS.size() * TIMES.size()))
	get_tree().quit(0)


## The town, driven by the same world clock through ACATownLightAdapter. A
## representative subset rather than the full matrix - the town is a lighting
## pass only, it has no rain particles or sky dome of its own.
const TOWN_SHOTS := [
	["clear", "morning", 7.0],
	["clear", "day", 12.0],
	["clear", "evening", 16.3],
	["clear", "night", 22.0],
	["foggy", "day", 12.0],
	["rain", "evening", 16.3],
]


func _capture_town() -> void:
	var town_hud := get_tree().current_scene.get_node_or_null(^"BusinessTown/BusinessHUD")
	if town_hud != null:
		town_hud.visible = false
	for shot in TOWN_SHOTS:
		WorldClock.set_weather(String(shot[0]).capitalize())
		WorldClock.advance_to_hour(float(shot[2]))
		AppUI.clear_notifications()
		await _settle(SETTLE_FRAMES)
		AppUI.clear_notifications()
		await _capture("town-%s-%s" % [shot[0], shot[1]])
	if town_hud != null:
		town_hud.visible = true
	WorldClock.set_weather("Clear")


## Park the mower's own camera at a fixed spot looking across the lawn. Using
## the real camera keeps the shot representative of what the player sees.
func _pose_camera() -> Camera3D:
	var scene := get_tree().current_scene
	var mower: Node3D = scene.get(&"current_mower")
	if mower == null:
		return null
	var camera: Camera3D = mower.get_node_or_null(^"Camera3D")
	if camera == null:
		return null
	# Stop the mower drifting and point it in a consistent direction.
	mower.set(&"target_body_yaw", 0.6)
	mower.rotation.y = 0.6
	camera.rotation.x = deg_to_rad(-8.0)
	if mower.has_method("set_physics_process"):
		mower.set_physics_process(false)
	return camera


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	image.save_png(path)
	print("[MATRIX] %s" % path)


func _await_screen(screen: int, max_frames: int = 900) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1
	printerr("[MATRIX] timed out waiting for screen %d" % screen)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## Same wait, but it reports frame rate. Weather is the one visual system in
## this project that runs every frame on modest hardware, so the cost of a look
## is worth printing next to the picture of it.
func _settle_measured(frames: int, label: String) -> void:
	var samples: Array[float] = []
	for i in frames:
		await get_tree().process_frame
		# Skip the first few: the preset is still easing in and the renderer is
		# still warming up its shaders.
		if i > frames / 3:
			samples.append(Performance.get_monitor(Performance.TIME_FPS))
	if samples.is_empty():
		return
	var total := 0.0
	var lowest := samples[0]
	for value in samples:
		total += value
		lowest = minf(lowest, value)
	print("[MATRIX] %-16s avg %5.1f fps, min %5.1f fps" % [label, total / samples.size(), lowest])
