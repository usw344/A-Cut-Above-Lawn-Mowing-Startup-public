extends Node
## DEVELOPMENT ONLY. Pause stack, cursor ownership and mower look controls.
##
##   godot --headless --path <project> "res://Dev tools/Validation/Pause Test.tscn" -- "--save-root=<dir>"
##
## Covers the things Milestone 5 changed and the older suites do not touch:
##
##   * one pause stack, used in BOTH the mowing scene and the Town
##   * the cursor is released while paused and restored to the CONTEXT of the
##     screen being resumed - CAPTURED in mowing, VISIBLE in town
##   * Settings and Controls Help open and close without stranding the stack
##   * saving from the pause menu
##   * the results screen is not covered by pause and keeps a usable cursor
##   * Invert Y exists, defaults OFF, and round-trips through GameSettings
##   * all three canonical mower scenes instantiate
##
## Cursor assertions read AppUI.effective_mouse_mode(), which is the LOGICAL
## state. Input.mouse_mode itself is never written on a headless DisplayServer,
## so asserting on it would prove nothing here.

const STEP_FRAMES := 4

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n================ PAUSE TEST ================")

	await _step()
	await _test_settings_invert_y()
	_test_mower_scenes()
	await _test_town_pause()
	await _test_mowing_pause()
	await _test_look_direction()
	await _test_results_not_covered()

	print("============================================")
	print("[PAUSE TEST] %d passed, %d failed" % [_passes, _failures])
	print("============================================\n")
	get_tree().quit(0 if _failures == 0 else 1)


# =========================================================== settings / mowers

func _test_settings_invert_y() -> void:
	_check("Settings: invert_look_y exists", ACAGameSettings.DEFAULTS.has("invert_look_y"))
	_check("Settings: invert_look_y defaults to OFF", not GameSettings.invert_look_y())

	GameSettings.set_value("invert_look_y", true)
	_check("Settings: invert_look_y can be turned on", GameSettings.invert_look_y())
	_check("Settings: invert_look_y is in values()",
		GameSettings.values().get("invert_look_y", false) == true)
	GameSettings.set_value("invert_look_y", false)
	_check("Settings: invert_look_y can be turned off again",
		not GameSettings.invert_look_y())

	# The component must be able to show and report it, or the setting is
	# unreachable for the player.
	var settings: SettingsMenu = load("res://UI/Settings/Settings.tscn").instantiate()
	add_child(settings)
	await _step()
	settings.set_values({"invert_look_y": true})
	_check("Settings component: invert_look_y round-trips",
		settings.values().get("invert_look_y", false) == true)
	settings.queue_free()
	await _step()


func _test_mower_scenes() -> void:
	for path in [
		"res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn",
		"res://Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn",
		"res://Assets/Vehicles and Mowers/Mowers/Push Mower.tscn",
	]:
		var packed: PackedScene = load(path)
		var scene_name: String = path.get_file().get_basename()
		if packed == null:
			_fail("Mower scene loads: %s" % scene_name)
			continue
		var mower: Node = packed.instantiate()
		var ok: bool = mower != null and mower is CharacterBody3D
		# Every controller must expose the shared look convention.
		ok = ok and mower.has_method("look_sensitivity")
		ok = ok and mower.get("mouse_yaw_smoothing") != null
		ok = ok and mower.get("mouse_pitch_smoothing") != null
		_check("Mower scene instantiates with look tuning: %s" % scene_name, ok)
		if mower != null:
			mower.free()


# ==================================================================== the town

func _test_town_pause() -> void:
	GameSession.start_new_game()
	await _step(8)
	await _wait_for_screen(ACAGameSession.Screen.TOWN)

	var layer := _town_pause_layer()
	_check("Town: pause layer present", layer != null)
	if layer == null:
		return

	_check("Town: cursor context is VISIBLE",
		AppUI.mouse_context() == Input.MOUSE_MODE_VISIBLE)
	_check("Town: RESTART is not offered", not layer.is_pause_option_enabled(&"restart"))

	layer.open_pause()
	await _step()
	_check("Town: pause opens", layer.is_pause_open())
	_check("Town: pause pauses the tree", get_tree().paused)
	_check("Town: cursor is free while paused",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)

	# Settings from the town, then back to the pause menu.
	layer._open_settings()
	await _step()
	_check("Town: settings open from pause", layer.pause_stack_open() and not layer.is_pause_open())
	_check("Town: tree still paused behind settings", get_tree().paused)

	# Controls Help on top of Settings, then closed again.
	layer._open_help()
	await _step()
	_check("Town: controls help opens over settings", layer.pause_stack_open())
	layer._help.close()
	await _step()
	_check("Town: closing controls help leaves settings up", layer._settings.is_open())
	_check("Town: closing controls help does not resume", get_tree().paused)

	layer._close_settings()
	await _step()
	_check("Town: back from settings returns to the pause menu", layer.is_pause_open())

	# Saving from the pause menu.
	layer._save_game()
	await _step()
	_check("Town: save from pause succeeded", SaveService.has_any_save())

	layer.close_pause()
	await _step()
	_check("Town: resume closes the stack", not layer.pause_stack_open())
	_check("Town: resume unpauses", not get_tree().paused)
	_check("Town: resume restores the TOWN cursor, not a captured one",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)


# ================================================================== the mowing

func _test_mowing_pause() -> void:
	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		_fail("Mowing: could not get a contract to test with")
		return

	var job: ACAJob = offers[0]
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	await _wait_for_screen(ACAGameSession.Screen.MOWING)
	await _step(6)

	var ui := _gameplay_ui()
	_check("Mowing: gameplay UI present", ui != null)
	if ui == null:
		return

	_check("Mowing: cursor context is CAPTURED",
		AppUI.mouse_context() == Input.MOUSE_MODE_CAPTURED)
	_check("Mowing: cursor really is captured before pausing",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	_check("Mowing: contract actions are offered", ui.is_pause_option_enabled(&"abandon"))

	ui.open_pause()
	await _step()
	_check("Mowing: pause opens", ui.is_pause_open())
	_check("Mowing: pause pauses the tree", get_tree().paused)
	_check("Mowing: PAUSE RELEASES THE MOUSE",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)

	ui._open_settings()
	await _step()
	_check("Mowing: settings open from pause", ui._settings.is_open())
	_check("Mowing: cursor still free in settings",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
	ui._open_help()
	await _step()
	ui._help.close()
	await _step()
	_check("Mowing: closing controls help does NOT reopen the pause menu",
		not ui.is_pause_open() and ui._settings.is_open())
	ui._close_settings()
	await _step()
	_check("Mowing: back from settings returns to the pause menu", ui.is_pause_open())

	ui._save_game()
	await _step()
	_check("Mowing: save from pause succeeded", SaveService.has_any_save())

	ui.close_pause()
	await _step()
	_check("Mowing: resume unpauses", not get_tree().paused)
	_check("Mowing: RESUME RESTORES THE CAPTURED MOUSE",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_CAPTURED)

	# ENTER must not steal the cursor back while a menu holds it.
	ui.open_pause()
	await _step()
	AppUI.toggle_mouse_capture()
	_check("Mowing: ENTER cannot capture the cursor while paused",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)
	ui.close_pause()
	await _step()


## The two things a player actually complained about: which way the camera goes,
## and how long it takes to get there.
##
## The direction half needs a real DisplayServer - the controllers only read the
## mouse while the cursor is CAPTURED, and a headless DisplayServer never is.
## The responsiveness half is just numbers, so it always runs.
func _test_look_direction() -> void:
	var scene := get_tree().current_scene
	var mower: Node = scene.get(&"current_mower") if scene != null else null
	if mower == null:
		_fail("Look: no mower in the mowing scene")
		return

	# Guard against a slide back to the old cinematic values.
	_check("Look: yaw smoothing is responsive, not cinematic",
		float(mower.get(&"mouse_yaw_smoothing")) >= 14.0)
	_check("Look: pitch smoothing is more immediate than yaw",
		float(mower.get(&"mouse_pitch_smoothing"))
		> float(mower.get(&"mouse_yaw_smoothing")))

	if DisplayServer.get_name() == "headless":
		print("[PAUSE TEST] Look direction: SKIPPED (needs a real DisplayServer)")
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _step()

	# CONVENTIONAL (Invert Y off): mouse up looks up. relative.y is negative
	# when the mouse moves up; camera pitch is positive when looking up.
	GameSettings.set_value("invert_look_y", false)
	mower.set(&"target_camera_pitch", 0.0)
	mower.set(&"target_body_yaw", 0.0)
	mower.call(&"_input", _mouse_motion(Vector2(0.0, -50.0)))
	_check("Look: mouse UP pitches the camera UP",
		float(mower.get(&"target_camera_pitch")) > 0.0)

	mower.set(&"target_camera_pitch", 0.0)
	mower.call(&"_input", _mouse_motion(Vector2(0.0, 50.0)))
	_check("Look: mouse DOWN pitches the camera DOWN",
		float(mower.get(&"target_camera_pitch")) < 0.0)

	# Invert Y flips exactly that and nothing else.
	GameSettings.set_value("invert_look_y", true)
	mower.set(&"target_camera_pitch", 0.0)
	mower.call(&"_input", _mouse_motion(Vector2(0.0, -50.0)))
	_check("Look: Invert Y makes mouse UP pitch the camera DOWN",
		float(mower.get(&"target_camera_pitch")) < 0.0)
	GameSettings.set_value("invert_look_y", false)

	# Steering is unaffected by Invert Y and follows the usual convention.
	mower.set(&"target_body_yaw", 0.0)
	mower.call(&"_input", _mouse_motion(Vector2(50.0, 0.0)))
	_check("Look: mouse RIGHT turns the mower right",
		float(mower.get(&"target_body_yaw")) < 0.0)

	# Pitch is clamped, so the camera can never flip over.
	mower.set(&"target_camera_pitch", 0.0)
	for i in 200:
		mower.call(&"_input", _mouse_motion(Vector2(0.0, -200.0)))
	_check("Look: pitch stays clamped below vertical",
		absf(float(mower.get(&"target_camera_pitch"))) < PI * 0.5)
	mower.set(&"target_camera_pitch", 0.0)
	mower.set(&"target_body_yaw", float(mower.rotation.y))


func _mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	return event


func _test_results_not_covered() -> void:
	var ui := _gameplay_ui()
	if ui == null:
		_fail("Results: skipped, no gameplay UI")
		return

	# Leave the pause menu up on purpose - completing must clear it.
	ui.open_pause()
	await _step()

	var scene := get_tree().current_scene
	scene.call(&"dev_complete_current_job")
	await _step(4)

	var results: JobCompleteScreen = ui.get_node_or_null(^"Job Complete")
	_check("Results: results screen is up", results != null and results.is_open())
	_check("Results: pause stack was closed by completion", not ui.pause_stack_open())
	_check("Results: escape can no longer reopen pause",
		not ui._pause.open_on_escape)
	_check("Results: tree is running again", not get_tree().paused)
	_check("Results: cursor is usable for the RETURN button",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)

	# Back to town: the transition must hand the cursor to the town's context.
	if results != null:
		results.hide_results()
	GameSession.go_to_town()
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	await _step(6)
	_check("Transition: no stale cursor hold survived the scene change",
		not AppUI.is_mouse_held())
	_check("Transition: town cursor restored after mowing",
		AppUI.effective_mouse_mode() == Input.MOUSE_MODE_VISIBLE)


# ===================================================================== helpers

func _town_pause_layer() -> ACAPauseLayer:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(^"Pause Layer") as ACAPauseLayer


func _gameplay_ui() -> ACAGameplayUI:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(^"Gameplay UI") as ACAGameplayUI


func _wait_for_screen(screen: int, max_frames: int = 600) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1
	_fail("Timed out waiting for screen %d" % screen)


func _step(frames: int = STEP_FRAMES) -> void:
	for i in frames:
		await get_tree().process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[PAUSE TEST] %s: PASS" % label)
	else:
		_failures += 1
		printerr("[PAUSE TEST] %s: FAIL" % label)


func _fail(label: String) -> void:
	_check(label, false)
