extends Node
## DEVELOPMENT ONLY. Repeatable end-to-end test of the application loop.
##
##   godot --headless --path <project> "res://Dev tools/Validation/Flow Test.tscn"
##
## Runs as a real scene rather than with --script, because --script replaces the
## main loop and the autoloads (WorldClock / JobManager / GameSession) never get
## created. The boot scene parents this runner directly to /root so it survives
## the scene changes it is testing.
##
## It drives the REAL application pathways - the same autoloads, the same
## ACAJobManager API the Job Board calls, the same GameSession transitions the
## buttons trigger, and the same completion path natural 100% mowing uses.
## It never writes private state to force a PASS.
##
## The one thing it does not do is click pixels: it calls the public methods
## the UI calls. Visual behaviour is verified by launching the project normally.

const STEP_FRAMES := 4

var _passes: int = 0
var _failures: int = 0
var _job_id: StringName = &""
var _completed_pay: int = 0
var _completed_job_name: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n================ FLOW TEST ================")

	await _step()
	await _test_boot()
	await _test_new_game()
	await _test_town()
	await _test_offers()
	await _test_accept()
	await _test_begin()
	await _test_gameplay_scene()
	await _test_world_state_preserved()
	await _test_gameplay_ui()
	await _test_completion()
	await _test_results_screen()
	await _test_return_to_town()
	await _test_completed_retained()

	print("===========================================")
	print("[FLOW TEST] %d passed, %d failed" % [_passes, _failures])
	print("===========================================\n")
	get_tree().quit(0 if _failures == 0 else 1)


# ==================================================================== steps

func _test_boot() -> void:
	_check("Autoloads present",
		get_tree().root.get_node_or_null(^"WorldClock") != null
		and get_tree().root.get_node_or_null(^"JobManager") != null
		and get_tree().root.get_node_or_null(^"GameSession") != null)

	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check("Main menu is the configured entry point",
		main_scene == ACAGameSession.MAIN_MENU_SCENE)

	_check("Job System is on the world clock",
		JobManager.time_provider() is ACAWorldClockTimeProvider)


func _test_new_game() -> void:
	GameSession.start_new_game()
	await _step()
	_check("New game: session active", GameSession.is_session_active())
	_check("New game: world clock running", WorldClock.is_running())
	# Starts at 08:00 and is already ticking, so assert the window rather than an
	# exact string - a slow first frame legitimately advances a few game minutes.
	var minutes := WorldClock.game_minutes()
	_check("New game: clock starts at the morning epoch",
		minutes >= ACAWorldClock.NEW_GAME_START_MINUTES
		and minutes < ACAWorldClock.NEW_GAME_START_MINUTES + 60.0)
	_check("New game: starting funds",
		GameSession.money() == ACAGameSession.STARTING_MONEY)


func _test_town() -> void:
	var arrived := await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen")
	_check("Town: screen is TOWN", arrived
		and GameSession.current_screen() == ACAGameSession.Screen.TOWN)
	var scene := get_tree().current_scene
	_check("Town: scene loaded", scene != null and scene.name == "Town Screen")
	_check("Town: BusinessTown present",
		scene != null and scene.get_node_or_null(^"BusinessTown") != null)


func _test_offers() -> void:
	# Give the market a moment in case seeding raced the clock.
	var tries := 0
	while JobManager.available_jobs().is_empty() and tries < 40:
		JobManager.evaluate_now()
		await _step()
		tries += 1

	var offers := JobManager.available_jobs()
	_check("Job offers: at least one real generated offer", not offers.is_empty())
	if offers.is_empty():
		return
	var job: ACAJob = offers[0]
	_job_id = job.id
	_check("Job offers: offer has a generated site", not job.job_site.is_empty())
	_check("Job offers: offer has a real grid size",
		job.grid_size.x > 0 and job.grid_size.y > 0)
	_check("Job offers: offer has pay", job.base_pay > 0)
	print("           -> %s" % job)


func _test_accept() -> void:
	if _job_id == &"":
		_fail("Job accepted: skipped, no offer")
		return
	# Exactly what ACAJobBoard._on_accept_pressed() calls.
	var ok: bool = JobManager.accept_job(_job_id)
	await _step()
	_check("Job accepted: manager accepted", ok)
	_check("Job accepted: job is the current contract",
		GameSession.current_job_id() == _job_id)
	_check("Job accepted: no longer on the available board",
		_find_in(JobManager.available_jobs(), _job_id) == null)


func _test_begin() -> void:
	if _job_id == &"":
		_fail("Begin job: skipped")
		return
	# Exactly what ACAJobBoard._on_begin_pressed() calls.
	var ok: bool = JobManager.begin_new_job(_job_id)
	_check("Begin job: handoff emitted", ok)
	await _step(4)


func _test_gameplay_scene() -> void:
	# The mowing scene builds a full grass grid behind a fullscreen transition.
	var arrived := await _await_screen(
		ACAGameSession.Screen.MOWING, "Minimum Viable Game")
	_check("Gameplay loaded: screen is MOWING", arrived
		and GameSession.current_screen() == ACAGameSession.Screen.MOWING)

	var scene := get_tree().current_scene
	_check("Gameplay loaded: mowing scene is current",
		scene != null and scene.name == "Minimum Viable Game")

	# The mowing scene exposes its lawn rather than being reached into by node
	# name, so this asks the same question the save system does.
	var lawn: ACALawn = scene.call(&"lawn") \
		if scene != null and scene.has_method(&"lawn") else null
	_check("Gameplay loaded: lawn built",
		lawn != null and lawn.total_item_count() > 0)
	if lawn != null:
		print("           -> %d mowable cells, %.1f%% mowed"
			% [lawn.total_item_count(), lawn.mowed_fraction() * 100.0])

	var job := GameSession.current_job()
	_check("Gameplay loaded: same accepted job is still current",
		job != null and job.id == _job_id)
	_check("Gameplay loaded: job is IN_PROGRESS",
		job != null and job.status == ACAJobEnums.Status.IN_PROGRESS)
	if job != null and lawn != null:
		_check("Gameplay loaded: lawn matches the contract size",
			lawn.cell_count() == job.grid_size.x)


func _test_gameplay_ui() -> void:
	var ui := _gameplay_ui()
	_check("Gameplay UI: stack present in the mowing scene", ui != null)
	if ui == null:
		return

	var hud: GameplayHUD = ui.get_node_or_null(^"Gameplay HUD")
	var intro: JobIntroScreen = ui.get_node_or_null(^"Job Intro")
	var pause: PauseMenu = ui.get_node_or_null(^"Pause Menu")
	var results: JobCompleteScreen = ui.get_node_or_null(^"Job Complete")

	_check("Gameplay UI: production HUD is up", hud != null and hud.is_hud_visible())

	var job := GameSession.current_job()
	if hud != null and job != null:
		# ASKED, NOT WALKED. This used to read `%JobName` and friends out of the
		# HUD's scene tree, and it silently stopped running the moment the HUD
		# was laid out in code instead - eight checks vanished from this suite
		# and it still reported zero failures. The component answers now.
		_check("Gameplay UI: HUD shows the real contract",
			hud.job_name_text() == job.job_site.to_upper())
		_check("Gameplay UI: HUD shows the real reward",
			hud.reward_text() == UITheme.format_money(job.base_pay))
		_check("Gameplay UI: HUD shows the world clock",
			hud.game_time_text() == WorldClock.clock_text())

	_check("Gameplay UI: job intro played", intro != null and intro.is_open())

	# The old MVP HUD is development tooling and must not be player-facing.
	var scene := get_tree().current_scene
	var mvp_hud: Node = scene.get_node_or_null(^"CanvasLayer/MVP_HUD") if scene != null else null
	_check("Gameplay UI: legacy debug HUD hidden by default",
		mvp_hud != null and not mvp_hud.visible)

	# Pause opens and closes through its real API.
	if pause != null:
		pause.open()
		await _step(2)
		_check("Gameplay UI: pause opens and pauses the tree",
			pause.is_open() and get_tree().paused)
		pause.close()
		await _step(2)
		_check("Gameplay UI: pause closes and resumes",
			not pause.is_open() and not get_tree().paused)

	_check("Gameplay UI: results screen starts closed",
		results != null and not results.is_open())

	# Let the intro finish so it is not competing with the results screen.
	var frames := 0
	while intro != null and intro.is_open() and frames < 600:
		await get_tree().process_frame
		frames += 1


func _test_results_screen() -> void:
	var ui := _gameplay_ui()
	if ui == null:
		_fail("Job Complete: skipped, no gameplay UI")
		return
	var results: JobCompleteScreen = ui.get_node_or_null(^"Job Complete")
	_check("Job Complete: results screen opened", results != null and results.is_open())
	if results == null:
		return

	results.finish_animation()
	await _step(2)
	_check("Job Complete: shows the real customer",
		results.get_node(^"%CustomerName").text == _completed_job_name.to_upper())
	_check("Job Complete: shows the real payout",
		results.get_node(^"%TotalValue").text == UITheme.format_money(_completed_pay))

	# Press the actual button the player presses.
	var button: Button = results.get_node(^"%ReturnButton")
	button.pressed.emit()
	await _step(2)


func _gameplay_ui() -> ACAGameplayUI:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(^"Gameplay UI") as ACAGameplayUI


func _test_world_state_preserved() -> void:
	_check("Time preserved: clock still running across the transition",
		WorldClock.is_running())
	_check("Time preserved: time advanced past 08:00",
		WorldClock.game_minutes() > ACAWorldClock.NEW_GAME_START_MINUTES)
	print("           -> %s" % WorldClock.timestamp_text())

	# Change weather from inside gameplay and confirm it lives in world state.
	WorldClock.set_weather("Rain")
	await _step(2)
	_check("Weather preserved: world state holds the current preset",
		WorldClock.weather_preset() == "Rain")

	var scene := get_tree().current_scene
	var preset_manager := scene.get_node_or_null(^"PresetManager (Sky3D)") if scene != null else null
	_check("Weather preserved: Preset Manager applied it",
		preset_manager != null and preset_manager.current_weather_preset == "Rain")


func _test_completion() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("dev_complete_current_job"):
		_fail("Completion: mowing scene has no dev completion helper")
		return

	var money_before := GameSession.money()
	var job := GameSession.current_job()
	var pay := job.base_pay if job != null else 0
	_completed_pay = pay
	_completed_job_name = job.job_site if job != null else ""

	# The development fast-completion path. It routes through the same
	# GameSession.complete_current_job() that natural 100% mowing uses.
	scene.call("dev_complete_current_job")
	await _step(2)

	_check("Completion: no active contract left", not GameSession.has_active_job())
	var past := JobManager.past_jobs()
	var completed := _find_in(past, _job_id)
	_check("Completion: job recorded in business history", completed != null)
	if completed != null:
		_check("Completion: status is COMPLETED",
			completed.status == ACAJobEnums.Status.COMPLETED)
		_check("Completion: progress is 100%", completed.progress >= 1.0)
		_check("Completion: completion timestamped in game time",
			completed.completed_game_time > 0.0)
	_check("Completion: contract value paid out",
		GameSession.money() == money_before + pay)


func _test_return_to_town() -> void:
	var arrived := await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen")
	_check("Return town: screen is TOWN", arrived
		and GameSession.current_screen() == ACAGameSession.Screen.TOWN)
	_check("Return town: town scene reloaded",
		get_tree().current_scene != null and get_tree().current_scene.name == "Town Screen")


func _test_completed_retained() -> void:
	await _step(4)
	var completed := _find_in(JobManager.past_jobs(), _job_id)
	_check("Completed job retained: still in history after returning",
		completed != null)
	_check("Completed job retained: not active again",
		GameSession.current_job_id() != _job_id)
	_check("Completed job retained: application still usable",
		get_tree().current_scene != null and is_instance_valid(get_tree().current_scene))
	_check("Completed job retained: world clock survived the round trip",
		WorldClock.is_running()
		and WorldClock.game_minutes() > ACAWorldClock.NEW_GAME_START_MINUTES)
	_check("Completed job retained: weather survived the round trip",
		WorldClock.weather_preset() == "Rain")


# ================================================================== helpers

func _step(frames: int = STEP_FRAMES) -> void:
	for _i in range(frames):
		await get_tree().process_frame


## Wait until the application has actually settled on `screen` with its scene
## built. Scene changes run through a fullscreen transition now, so a fixed
## frame count is not a reliable wait.
func _await_screen(screen: int, scene_name: String, max_frames: int = 900) -> bool:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen 				and not GameSession.is_changing_scene() 				and get_tree().current_scene != null 				and get_tree().current_scene.name == scene_name:
			# A couple more frames so the new scene _ready() work has landed.
			await _step(3)
			return true
		await get_tree().process_frame
		frames += 1
	return false


func _find_in(list: Array, job_id: StringName) -> ACAJob:
	for job: ACAJob in list:
		if job.id == job_id:
			return job
	return null


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[FLOW TEST] %s: PASS" % label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	print("[FLOW TEST] %s: FAIL" % label)
