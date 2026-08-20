extends Node
## DEVELOPMENT ONLY. Walks the real application loop and saves a screenshot at
## each screen, so UI layout and overlap can actually be looked at.
##
##   godot --path <project> "res://Dev tools/Validation/Screenshot Tour.tscn"
##
## Needs a real renderer - it captures the viewport, so it does NOT work under
## --headless.
##
## Output goes to OUTPUT_DIR. Override it with:
##   --tour-output=<absolute path>

const DEFAULT_OUTPUT_DIR := "user://ui_tour"

var _dir: String = DEFAULT_OUTPUT_DIR
var _shot: int = 0
var _job_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = _output_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	print("[TOUR] writing to %s" % _dir)
	_run.call_deferred()


func _output_dir() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--tour-output="):
			return arg.trim_prefix("--tour-output=")
	return DEFAULT_OUTPUT_DIR


func _run() -> void:
	# This tour scene is the entry point, so go to the real main menu first.
	GameSession.go_to_main_menu()
	await _await_screen(ACAGameSession.Screen.MAIN_MENU, "Main Menu Screen")
	await _settle(60)
	await _capture("01-main-menu")

	# Load Game picker, populated from the real save list.
	var menu_ui := get_tree().current_scene.get_node_or_null(^"Menu UI")
	var load_menu: LoadGameScreen = menu_ui.get_node_or_null(^"Load Game") if menu_ui != null else null
	if load_menu != null:
		load_menu.set_saves(SaveService.list_saves())
		load_menu.open()
		await _settle(30)
		await _capture("01b-load-game")
		load_menu.close()
		await _settle(20)

	# Credits, the data-driven Main Menu screen.
	var credits: CreditsScreen = menu_ui.get_node_or_null(^"Credits") if menu_ui != null else null
	if credits != null:
		credits.open()
		await _settle(30)
		await _capture("01c-credits")
		credits.close()
		await _settle(20)

	GameSession.start_new_game()
	await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen")
	await _settle(45)
	await _capture("02-town")

	# Open the Job Board the way the town does.
	var town := get_tree().current_scene.get_node_or_null(^"BusinessTown") as ACABusinessTown
	if town != null and town.hud != null:
		town.hud.open_jobs()
		await _settle(30)
		await _capture("03-job-board")

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		await _settle(10)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		print("[TOUR] no offers; stopping")
		get_tree().quit(1)
		return

	_job_id = offers[0].id
	JobManager.accept_job(_job_id)
	await _settle(30)
	await _capture("04-job-accepted")

	JobManager.begin_new_job(_job_id)
	await _await_screen(ACAGameSession.Screen.MOWING, "Minimum Viable Game")
	await _settle(20)
	await _capture("05-job-intro")

	var ui := _gameplay_ui()
	var intro: JobIntroScreen = ui.get_node_or_null(^"Job Intro") if ui != null else null
	var frames := 0
	while intro != null and intro.is_open() and frames < 900:
		await get_tree().process_frame
		frames += 1
	await _settle(30)
	await _capture("06-mowing-hud")

	# Weather readout under a different preset.
	WorldClock.set_weather("Rain")
	await _settle(120)
	await _capture("07-mowing-rain")

	# FUEL. Three frames, because fuel is the one gameplay state a screenshot
	# can actually judge: a full gauge, the empty gauge with its warning, and
	# the F3 development row that owns the Auto Refuel cheat.
	WorldClock.set_weather("Clear")
	MowerFuel.set_auto_refuel(false)
	MowerFuel.dev_drain()
	await _settle(45)
	await _capture("07b-mowing-fuel-empty")

	var mowing_scene := get_tree().current_scene
	if mowing_scene != null and mowing_scene.has_method("dev_toggle_debug_hud"):
		mowing_scene.call("dev_toggle_debug_hud")
		await _settle(20)
		await _capture("07c-dev-hud-fuel-row")
		mowing_scene.call("dev_toggle_debug_hud")
		await _settle(15)
	MowerFuel.refuel_full()
	await _settle(30)

	var pause: PauseMenu = ui.get_node_or_null(^"Pause Menu") if ui != null else null
	if pause != null:
		pause.open()
		await _settle(25)
		await _capture("08-pause-menu")
		pause.close()
		get_tree().paused = false
		await _settle(20)

	var settings: SettingsMenu = ui.get_node_or_null(^"Settings") if ui != null else null
	if settings != null:
		settings.open()
		await _settle(25)
		await _capture("09-settings")
		settings.close()
		await _settle(20)

	var help: ControlsHelp = ui.get_node_or_null(^"Controls Help") if ui != null else null
	if help != null:
		help.open()
		await _settle(25)
		await _capture("10-controls-help")
		help.close()
		await _settle(20)
		if pause != null and pause.is_open():
			pause.close()
			get_tree().paused = false
			await _settle(15)

	var confirm: ConfirmationPrompt = ui.get_node_or_null(^"Confirmation Dialog") if ui != null else null
	if confirm != null:
		confirm.show_confirmation("Abandon contract?",
			"You walk away with no pay, and the contract does not go into your history.",
			"ABANDON")
		await _settle(25)
		await _capture("11-confirmation")
		confirm.hide_dialog()
		await _settle(20)

	AppUI.notify_success("Contract accepted", "Riverside Bungalow - $240")
	AppUI.notify_money("Payment received", "$240")
	await _settle(25)
	await _capture("12-notifications")

	var scene := get_tree().current_scene
	if scene != null and scene.has_method("dev_complete_current_job"):
		scene.call("dev_complete_current_job")
	await _settle(150)
	await _capture("13-job-complete")

	GameSession.go_to_town()
	await _await_screen(ACAGameSession.Screen.TOWN, "Town Screen")
	await _settle(45)

	# Past tab, to show the completed contract is really recorded.
	town = get_tree().current_scene.get_node_or_null(^"BusinessTown") as ACABusinessTown
	if town != null and town.hud != null:
		town.hud.open_jobs()
		await _settle(20)
		var board := _find_board(town.hud)
		if board != null:
			board.show_tab(ACAJobBoard.Tab.PAST)
			await _settle(25)
	await _capture("14-town-past-jobs")

	print("[TOUR] done, %d screenshots" % _shot)
	get_tree().quit(0)


# ================================================================== helpers

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_shot += 1
	var path := "%s/%s.png" % [_dir, label]
	var err := image.save_png(path)
	if err != OK:
		print("[TOUR] FAILED to write %s (error %d)" % [path, err])
	else:
		print("[TOUR] %s" % path)


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _await_screen(screen: int, scene_name: String, max_frames: int = 900) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen \
				and not GameSession.is_changing_scene() \
				and get_tree().current_scene != null \
				and get_tree().current_scene.name == scene_name:
			return
		await get_tree().process_frame
		frames += 1


func _gameplay_ui() -> ACAGameplayUI:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(^"Gameplay UI") as ACAGameplayUI


func _find_board(hud: ACABusinessHUD) -> ACAJobBoard:
	for node in hud.find_children("*", "ACAJobBoard", true, false):
		return node as ACAJobBoard
	return null
