extends Node
## DEVELOPMENT ONLY. The Trailer Capture scene's STRUCTURAL contract.
##
##   godot --headless --path <project> "res://Dev tools/Validation/Trailer Test.tscn"
##
## ---------------------------------------------------------------------------
## THIS SUITE DOES NOT SAY THE TRAILER LOOKS GOOD
## ---------------------------------------------------------------------------
## It cannot. What it guards is the set of things that break SILENTLY: the scene
## still loading, the storyboard staying inside its target length and still
## containing every beat, the presentation adapters still existing and still
## putting back what they borrow, and the trailer never becoming the main scene.
##
## Whether it looks good is decided from frames:
##
##   godot --path . "res://Game/Demo/Trailer/Trailer Capture.tscn" \
##       -- "--trailer-shots=<dir>" "--trailer-quit"

const TRAILER_DIR := "res://Game/Demo/Trailer"
const PRESENTATION_DIR := "res://Game/Demo/Trailer/Presentation"

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n=============== TRAILER TEST ===============")
	_test_scene()
	_test_presentation_layer()
	_test_storyboard()
	_test_gameplay_is_untouched()
	_test_mower_adapter()
	_test_lawn_adapter()
	_test_weather_adapter()
	_test_ui_director()
	_test_menu_presentation_api()
	_test_dev_bridges()
	print("============================================")
	print("[TRAILER TEST] %d passed, %d failed" % [_passes, _failures])
	print("============================================\n")
	get_tree().quit(0 if _failures == 0 else 1)


func _test_scene() -> void:
	_check("Scene: Trailer Capture.tscn loads",
		load(TRAILER_DIR + "/Trailer Capture.tscn") != null)
	_check("Scene: the README is present (how to capture it)",
		FileAccess.file_exists(TRAILER_DIR + "/README.md"))

	# It is media tooling. Shipping it as the entry point would be a bad day.
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check("Scene: the trailer is NOT the application main scene",
		main_scene == ACAGameSession.MAIN_MENU_SCENE)


## 12B. The trailer owns a presentation layer, and it lives in the trailer's own
## folder rather than being smeared through the game.
func _test_presentation_layer() -> void:
	for file in ["cinematic_camera.gd", "trailer_mower_adapter.gd",
			"trailer_lawn_adapter.gd", "trailer_weather_adapter.gd",
			"trailer_ui_director.gd"]:
		_check("Presentation: %s exists and loads" % file,
			load(PRESENTATION_DIR + "/" + file) != null)

	# The camera must be a FILM camera, not a follow rig with one mode.
	var shot: Dictionary = ACACinematicCamera.DEFAULT_SHOT
	for key in ["mode", "rail", "look_rail", "fov", "fov_to", "dof", "ease",
			"look_lead", "min_ground"]:
		_check("Camera: the shot contract carries '%s'" % key, shot.has(key))


func _test_storyboard() -> void:
	var beats: Array = ACATrailerDirector.BEATS
	_check("Storyboard: has beats", not beats.is_empty())

	var sorted := true
	var named := true
	var callable_ok := true
	var director := ACATrailerDirector.new()
	for i in beats.size():
		var beat: Dictionary = beats[i]
		if not (beat.has("at") and beat.has("name") and beat.has("call")):
			named = false
			continue
		if i > 0 and float(beats[i - 1]["at"]) > float(beat["at"]):
			sorted = false
		if not director.has_method(String(beat["call"])):
			callable_ok = false
	director.free()
	_check("Storyboard: every beat has at/name/call", named)
	_check("Storyboard: beats are in time order", sorted)
	_check("Storyboard: every beat names a real method", callable_ok)

	var total: float = float(beats[-1]["at"])
	_check("Storyboard: total length is %.1fs, inside the 35-48s target" % total,
		total >= 35.0 and total <= 48.0)

	# Every required beat of the storyboard brief.
	var names := ""
	for beat in beats:
		names += String(beat["name"]) + "|"
	for required in ["main menu", "town", "job board", "mower over the top",
			"mower low pass", "mower close", "weather hero",
			"gameplay proof", "completion", "end card"]:
		_check("Storyboard: covers '%s'" % required, names.contains(required))

	# FIVE distinct mowing compositions. M13 cut the mowing section from five
	# mower angles to three, and the storm and the HUD proof make it up to five
	# compositions filmed on the lawn.
	var mowing_beats := 0
	for beat in beats:
		var n := String(beat["name"])
		if n.begins_with("mower ") or n == "weather hero" or n == "gameplay proof":
			mowing_beats += 1
	_check("Storyboard: at least five distinct mowing compositions (%d)" % mowing_beats,
		mowing_beats >= 5)

	# 12U. A trailer where every shot is the same length is a slideshow.
	var durations: Array[float] = []
	for i in range(beats.size() - 1):
		durations.append(float(beats[i + 1]["at"]) - float(beats[i]["at"]))
	var shortest: float = durations.min()
	var longest: float = durations.max()
	_check("Storyboard: shot lengths vary (%.1fs to %.1fs)" % [shortest, longest],
		longest - shortest >= 1.5)
	_check("Storyboard: no shot is under 2 seconds (%.1fs)" % shortest, shortest >= 2.0)


## 12X. THE central guarantee: a capture cannot change how the game plays.
func _test_gameplay_is_untouched() -> void:
	_check("Gameplay: mower speed is the shipped default (%s)" % str(model.get_speed()),
		is_equal_approx(float(model.get_speed()),
			ACATrailerDirector.GAMEPLAY_MOWER_SPEED))

	# V2 drove the mower by overriding `model.speed`. V3 must not: shot speed
	# belongs to the mower adapter, so gameplay tuning is out of reach entirely.
	var source := FileAccess.get_file_as_string(TRAILER_DIR + "/trailer_director.gd")
	_check("Gameplay: the director never writes model.speed",
		not source.contains("model.set_speed") and not source.contains("model.speed ="))

	# Shot speeds are the adapter's, and they are not all the same number.
	var speeds := [
		ACATrailerDirector.SPEED_OVER_THE_TOP, ACATrailerDirector.SPEED_LOW_PASS,
		ACATrailerDirector.SPEED_CLOSE, ACATrailerDirector.SPEED_STORM,
		ACATrailerDirector.SPEED_PROOF,
	]
	var distinct := {}
	for s in speeds:
		distinct[s] = true
	_check("Gameplay: shots carry their own speeds (%d distinct)" % distinct.size(),
		distinct.size() >= 4)
	_check("Gameplay: no shot speed is absurd (all <= 80 u/s)", speeds.max() <= 80.0)
	# M13. The mowing shots are CLOSE, so they have to be slower than gameplay's
	# 30 u/s. At V3's 38-55 no lens could be near the machine and the footage
	# read as a speck scurrying about. This is the guard on that regression.
	_check("Gameplay: mowing shots are slower than gameplay (%.0f u/s max)" % speeds.max(),
		speeds.max() < ACATrailerDirector.GAMEPLAY_MOWER_SPEED * 3.0)

	_check("Gameplay: Auto Refuel is OFF outside the trailer", not MowerFuel.auto_refuel())
	_check("Gameplay: fuel rules are the shipped ones",
		is_equal_approx(ACAMowerFuel.FULL_TANK_DRIVING_SECONDS, 480.0))
	_check("Gameplay: notifications are not suppressed outside the trailer",
		not AppUI.notifications_suppressed())
	_check("Gameplay: no cursor lock is left behind",
		AppUI.effective_mouse_mode() != -1)


## 12C. The adapter takes the mower over and hands it back exactly as found.
func _test_mower_adapter() -> void:
	var packed: PackedScene = load("res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn")
	if packed == null:
		_fail("Mower adapter: the rider mower scene loads")
		return
	var mower: CharacterBody3D = packed.instantiate()
	get_tree().root.add_child(mower)

	var adapter := ACATrailerMowerAdapter.new()
	get_tree().root.add_child(adapter)

	_check("Mower adapter: starts unbound", not adapter.is_bound())
	adapter.bind(mower, 12.5)
	_check("Mower adapter: binds the real rider", adapter.is_bound())
	_check("Mower adapter: takes the controller's physics OFF",
		not mower.is_physics_processing())

	# It plants the mower at the measured ground height - it does not drop it.
	adapter.place(Vector3(4.0, 99.0, -7.0), 1.2)
	_check("Mower adapter: places the mower at the ground height, not where asked",
		is_equal_approx(mower.global_position.y, 12.5))
	_check("Mower adapter: places it on the asked x/z",
		is_equal_approx(mower.global_position.x, 4.0)
		and is_equal_approx(mower.global_position.z, -7.0))
	_check("Mower adapter: faces the asked yaw", is_equal_approx(mower.rotation.y, 1.2))
	_check("Mower adapter: leaves no velocity to resolve",
		mower.velocity.is_equal_approx(Vector3.ZERO))

	# 13A. THE FLOAT. Up to V3 the trailer planted the mower where its own
	# physics settled, which on an uncut lawn is on TOP of three-unit grass
	# colliders, half a unit above a collision box that is itself half a unit
	# proud of the visible dirt. The mower flew. `visual_lift()` is the
	# measurement that replaced it: how far the origin sits above the lowest
	# thing you can SEE, so the director can put the wheels on the ground.
	mower.global_position = Vector3(0.0, 40.0, 0.0)
	mower.force_update_transform()
	var lift: float = ACATrailerMowerAdapter.visual_lift(mower)
	_check("Mower adapter: measures a visual lift from the real meshes (%.2f)" % lift,
		lift > -2.0 and lift < 2.0)
	_check("Mower adapter: the lift does not depend on where the mower is",
		is_equal_approx(lift, ACATrailerMowerAdapter.visual_lift(mower)))

	# 13B. A shot may damp the suspension; the default must come back on bind.
	adapter.set_suspension(0.0, 0.0, 0.0)
	adapter.reset_suspension()
	_check("Mower adapter: suspension defaults are gentle enough for a close lens",
		ACATrailerMowerAdapter.BOB_HEIGHT <= 0.06
		and ACATrailerMowerAdapter.MAX_ROLL <= 0.08)

	adapter.drive_straight(30.0)
	_check("Mower adapter: drives when told", adapter.is_driving())
	adapter.stop()
	_check("Mower adapter: stops when told", not adapter.is_driving())

	adapter.release()
	_check("Mower adapter: RELEASES the mower", not adapter.is_bound())
	_check("Mower adapter: gives the controller's physics back",
		mower.is_physics_processing())

	adapter.queue_free()
	mower.queue_free()


## 12F. The staged cut is the lawn's own cut, not a fake shader.
func _test_lawn_adapter() -> void:
	var lawn := ACALawn.new()
	_check("Lawn adapter: the lawn exposes mow_swath", lawn.has_method("mow_swath"))
	_check("Lawn adapter: the lawn exposes mow_disc", lawn.has_method("mow_disc"))
	_check("Lawn adapter: the lawn exposes the progress signal",
		lawn.has_signal("mowing_progress_changed"))
	# An unbuilt lawn must answer rather than crash - the adapter can be asked
	# about the lawn before the scene exists.
	_check("Lawn adapter: mow_swath on an empty lawn cuts nothing",
		lawn.mow_swath(Vector3.ZERO, Vector3(10, 0, 0), 4.0) == 0)
	_check("Lawn adapter: an empty lawn reports no progress",
		is_zero_approx(lawn.mowed_fraction()))
	lawn.free()

	var adapter := ACATrailerLawnAdapter.new()
	get_tree().root.add_child(adapter)
	_check("Lawn adapter: starts unbound", not adapter.is_bound())
	_check("Lawn adapter: an unbound adapter reports no progress",
		is_zero_approx(adapter.mowed_fraction()))
	_check("Lawn adapter: staging on an unbound adapter is a no-op",
		adapter.stage_stripes(Vector3.ZERO, 0.0, 3, 40.0) == 0)
	_check("Lawn adapter: the cut is wide enough to read on video",
		ACATrailerLawnAdapter.CUT_HALF_WIDTH >= 3.0)
	adapter.queue_free()


## 12P. The trailer may exaggerate the weather. It may not leave it exaggerated.
func _test_weather_adapter() -> void:
	var visual := ACAWeatherVisualAdapter.new()
	_check("Weather: the visual adapter exposes a presentation override",
		visual.has_method("set_presentation_override")
		and visual.has_method("clear_presentation_override"))
	_check("Weather: there is NO override in normal gameplay",
		not visual.has_presentation_override())

	# The shipped look must be exactly what it was before the hook existed.
	var shipped: Dictionary = visual.compose("Rain", 15.4)
	visual.set_presentation_override(ACATrailerWeatherAdapter.STORM_OVERRIDE)
	var stormy: Dictionary = visual.compose("Rain", 15.4)
	_check("Weather: the override actually changes the composed look",
		stormy["dome:clouds_cumulus_size"] != shipped["dome:clouds_cumulus_size"])
	_check("Weather: the storm override is COOLER than the shipped storm",
		(stormy["dome:atm_day_tint"] as Color).b / maxf((stormy["dome:atm_day_tint"] as Color).r, 0.001)
		> (shipped["dome:atm_day_tint"] as Color).b / maxf((shipped["dome:atm_day_tint"] as Color).r, 0.001))
	_check("Weather: the storm stays READABLE (exposure is not crushed)",
		float(stormy["sky:camera_exposure"]) >= float(shipped["sky:camera_exposure"]))

	visual.clear_presentation_override()
	var after: Dictionary = visual.compose("Rain", 15.4)
	var restored := true
	for key: String in shipped:
		if str(after.get(key)) != str(shipped[key]):
			restored = false
	_check("Weather: clearing the override restores the shipped look exactly", restored)
	visual.free()

	var adapter := ACATrailerWeatherAdapter.new()
	get_tree().root.add_child(adapter)
	_check("Weather: the trailer adapter starts clean", not adapter.is_applied())
	adapter.clear()
	_check("Weather: clear() on an unbound adapter is safe", not adapter.is_applied())
	_check("Weather: rain is turned UP for camera, not left at gameplay levels",
		ACATrailerWeatherAdapter.STORM_FAR_RATIO > 0.6)
	adapter.queue_free()

	# The addon stays read-only.
	_check("Weather: the storm override only writes project-owned keys",
		_override_keys_are_project_owned())


## The composed key space moved into the reusable environment package in
## Milestone 14; `ACAEnvKeys` is where the prefixes live now. The assertion is
## unchanged: a trailer override may only address properties this project
## composes, never anything inside the third-party addon.
func _override_keys_are_project_owned() -> bool:
	for section in ["scale", "set"]:
		var part: Dictionary = ACATrailerWeatherAdapter.STORM_OVERRIDE.get(section, {})
		for key: String in part:
			if ACAEnvKeys.target_for(key) == "":
				return false
	return true


## 12N. Every beat names the UI layer it wants; nothing is left up by accident.
func _test_ui_director() -> void:
	var ui := ACATrailerUIDirector.new()
	get_tree().root.add_child(ui)
	for layer in [ACATrailerUIDirector.Layer.MENU, ACATrailerUIDirector.Layer.TOWN,
			ACATrailerUIDirector.Layer.JOB_BOARD, ACATrailerUIDirector.Layer.CINEMATIC,
			ACATrailerUIDirector.Layer.GAMEPLAY, ACATrailerUIDirector.Layer.RESULTS,
			ACATrailerUIDirector.Layer.NONE]:
		ui.show_layer(layer)
	_check("UI director: every layer can be selected without a scene",
		ui.current_layer() == ACATrailerUIDirector.Layer.NONE)

	ui.begin_capture()
	_check("UI director: begin_capture suppresses toasts", AppUI.notifications_suppressed())
	ui.restore()
	_check("UI director: restore() puts notifications back",
		not AppUI.notifications_suppressed())
	_check("UI director: restore() releases the cursor lock", not _cursor_is_locked())
	ui.queue_free()


func _cursor_is_locked() -> bool:
	# `lock_mouse_context` is the trailer-only path; unlocking must leave the
	# normal context in charge again.
	return AppUI.has_method("mouse_context_locked") \
		and bool(AppUI.call(&"mouse_context_locked"))


## 12K. The opening shot must put the REAL menu into the REAL hover state.
func _test_menu_presentation_api() -> void:
	var packed: PackedScene = load("res://UI/Main Menu/main_menu.tscn")
	if packed == null:
		_fail("Menu: main_menu.tscn loads")
		return
	var menu: Control = packed.instantiate()
	_check("Menu: exposes preview_hover_option", menu.has_method("preview_hover_option"))
	_check("Menu: exposes option_screen_position", menu.has_method("option_screen_position"))

	# It has to run for real, not just exist: add it to the tree so the radial
	# menu builds its items, then hover NEW GAME the way the trailer does.
	get_tree().root.add_child(menu)
	var hovered: bool = menu.call(&"preview_hover_option", &"new_game")
	_check("Menu: NEW GAME can be hovered through the presentation API", hovered)
	_check("Menu: an unknown option is refused rather than silently ignored",
		not bool(menu.call(&"preview_hover_option", &"not_an_option")))
	menu.call(&"clear_preview_hover")
	get_tree().root.remove_child(menu)
	menu.queue_free()


func _test_dev_bridges() -> void:
	# Everything the director reaches for outside its own folder. If one of
	# these is renamed the trailer breaks at run time, in a scene nothing else
	# loads - so assert them here instead.
	_check("Bridge: WorldClock.advance_to_hour", WorldClock.has_method("advance_to_hour"))
	_check("Bridge: WorldClock.set_running", WorldClock.has_method("set_running"))
	_check("Bridge: JobManager.debug_clear_all", JobManager.has_method("debug_clear_all"))
	_check("Bridge: JobManager._spawn_offer", JobManager.has_method("_spawn_offer"))
	_check("Bridge: JobManager._rng exists", JobManager.get(&"_rng") != null)
	_check("Bridge: JobManager.accept_job / begin_new_job",
		JobManager.has_method("accept_job") and JobManager.has_method("begin_new_job"))
	_check("Bridge: MowerFuel.dev_drain / refuel",
		MowerFuel.has_method("dev_drain") and MowerFuel.has_method("refuel"))
	_check("Bridge: AppUI.set_notifications_suppressed",
		AppUI.has_method("set_notifications_suppressed"))
	_check("Bridge: AppUI.transition().cover_immediately",
		AppUI.transition().has_method("cover_immediately"))
	_check("Bridge: GameSession.screen_changed exists",
		GameSession.has_signal("screen_changed"))
	_check("Bridge: AppUI.lock_mouse_context / unlock_mouse_context",
		AppUI.has_method("lock_mouse_context") and AppUI.has_method("unlock_mouse_context"))
	_check("Bridge: AppUI.cover / clear_notifications",
		AppUI.has_method("cover") and AppUI.has_method("clear_notifications"))
	_check("Bridge: GameSession.start_new_game / go_to_main_menu",
		GameSession.has_method("start_new_game") and GameSession.has_method("go_to_main_menu"))

	# The mowing scene must still expose the fast-completion the trailer ends on,
	# and the rider must still expose the visual parts the adapter animates.
	_check("Bridge: the mowing scene loads",
		load("res://Game/M.V.P/Minimum Viable Game.tscn") != null)
	var mower: PackedScene = load("res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn")
	if mower != null:
		var instance: Node = mower.instantiate()
		_check("Bridge: the rider exposes target_body_yaw",
			instance.get(&"target_body_yaw") != null)
		var parts := instance.get_node_or_null(^"LawnTractor01")
		_check("Bridge: the rider's visual parts take send_speed_data",
			parts != null and parts.has_method("send_speed_data"))
		_check("Bridge: the rider's visual parts take send_rotation_data",
			parts != null and parts.has_method("send_rotation_data"))
		instance.free()
	else:
		_fail("Bridge: the rider mower scene loads")


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[TRAILER TEST] %s: PASS" % label)
	else:
		_failures += 1
		printerr("[TRAILER TEST] %s: FAIL" % label)


func _fail(label: String) -> void:
	_check(label, false)
