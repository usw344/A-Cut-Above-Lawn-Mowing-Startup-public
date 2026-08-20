extends Node
## DEVELOPMENT ONLY. Instantiates every component in res://UI/ and exercises its
## public API, so a missing @onready node or a broken resource path shows up as
## a failure instead of a crash mid-game.
##
##   godot --headless --path <project> "res://Dev tools/Validation/UI Smoke Test.tscn"

const COMPONENTS: Array[String] = [
	"res://UI/Theme/Game UI.theme.tres",
	"res://UI/Gameplay HUD/Gameplay HUD.tscn",
	"res://UI/Job Intro/Job Intro.tscn",
	"res://UI/Job Complete/Job Complete.tscn",
	"res://UI/Pause Menu/Pause Menu.tscn",
	"res://UI/Settings/Settings.tscn",
	"res://UI/Controls Help/Controls Help.tscn",
	"res://UI/Dialogs/Confirmation Dialog.tscn",
	"res://UI/Notifications/Notifications.tscn",
	"res://UI/Notifications/Notification Toast.tscn",
	"res://UI/Transitions/Transition.tscn",
	"res://UI/Load Game/Load Game.tscn",
	"res://UI/Credits/Credits.tscn",
	"res://UI/Demo/UI Demo.tscn",
	"res://UI/Main Menu/main_menu.tscn",
	"res://UI/Main Menu/radial_menu/radial_menu.tscn",
	"res://UI/Scenic Background for Menus/scenery/scenes/main_menu_scenery.tscn",
	"res://UI/Scenic Background for Menus/scenery_wind/scenes/scenery_wind_controller.tscn",
	"res://UI/Scenic Background for Menus/scenery_wind/scenes/wind_preview.tscn",
	"res://Main Area/ACA_JobSystem/job_system/ui/JobBoard.tscn",
	"res://Main Area/ACA_JobSystem/job_system/ui/JobCard.tscn",
	"res://Game/App/Gameplay UI.tscn",
	"res://Game/App/Pause Layer.tscn",
]

var _passes: int = 0
var _failures: int = 0
var _host: CanvasLayer


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n============== UI SMOKE TEST ==============")

	_host = CanvasLayer.new()
	add_child(_host)

	for path in COMPONENTS:
		await _load_and_instantiate(path)

	await _exercise_apis()

	print("===========================================")
	print("[UI SMOKE] %d passed, %d failed" % [_passes, _failures])
	print("===========================================\n")
	get_tree().quit(0 if _failures == 0 else 1)


func _load_and_instantiate(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res == null:
		_fail("Load %s" % path.get_file())
		return
	_pass("Load %s" % path.get_file())

	if not (res is PackedScene):
		return

	var node := (res as PackedScene).instantiate()
	if node == null:
		_fail("Instantiate %s" % path.get_file())
		return
	_host.add_child(node)
	# One frame so every @onready resolves and _ready() runs for real.
	await get_tree().process_frame
	if is_instance_valid(node):
		_pass("Instantiate %s" % path.get_file())
		node.queue_free()
	else:
		_fail("Instantiate %s" % path.get_file())
	await get_tree().process_frame


## Drive the public API of the components the game actually uses, with values in
## the documented ranges.
func _exercise_apis() -> void:
	var hud: GameplayHUD = _spawn("res://UI/Gameplay HUD/Gameplay HUD.tscn")
	if hud != null:
		hud.set_job_name("Riverside Bungalow")
		hud.set_job_size("Medium Lawn")
		hud.set_reward(240)
		hud.set_progress_immediate(0.42)
		hud.set_fuel(0.15)
		hud.set_status("Mowing")
		hud.set_game_time("09:41")
		hud.set_weather("Rain")
		hud.show_hud()
		await get_tree().process_frame
		_check("Gameplay HUD reports what it was given",
			is_equal_approx(hud.progress(), 0.42) and hud.is_hud_visible())

	var intro: JobIntroScreen = _spawn("res://UI/Job Intro/Job Intro.tscn")
	if intro != null:
		intro.set_contract_type("Residential Contract")
		intro.show_job("Riverside Bungalow", "Medium Lawn", 240, 12)
		intro.set_status("Preparing equipment...")
		await get_tree().process_frame
		_check("Job Intro opens", intro.is_open())
		intro.hide_intro()

	var results: JobCompleteScreen = _spawn("res://UI/Job Complete/Job Complete.tscn")
	if results != null:
		results.show_results("Riverside Bungalow", 1.0, 522.0, 240, 0)
		results.finish_animation()
		await get_tree().process_frame
		_check("Job Complete opens and totals", results.is_open()
			and results.get_node(^"%TotalValue").text == UITheme.format_money(240))
		results.hide_results()

	var pause: PauseMenu = _spawn("res://UI/Pause Menu/Pause Menu.tscn")
	if pause != null:
		pause.set_context("Riverside Bungalow")
		pause.open()
		await get_tree().process_frame
		_check("Pause Menu opens", pause.is_open())
		pause.set_option_enabled(&"abandon", false)
		_check("Pause Menu can disable an unsupported option",
			not pause.is_option_enabled(&"abandon"))
		pause.close()
		await get_tree().process_frame
		_check("Pause Menu closes", not pause.is_open())

	var settings: SettingsMenu = _spawn("res://UI/Settings/Settings.tscn")
	if settings != null:
		settings.open()
		settings.set_values(GameSettings.values())
		await get_tree().process_frame
		_check("Settings opens and round-trips its values",
			settings.is_open() and settings.values().has("mouse_sensitivity"))
		settings.close()

	var help: ControlsHelp = _spawn("res://UI/Controls Help/Controls Help.tscn")
	if help != null:
		help.set_title("Controls")
		help.set_bindings(ACAControlBindings.MOWING)
		help.open()
		await get_tree().process_frame
		_check("Controls Help opens with the project bindings", help.is_open())
		help.close()
		await get_tree().process_frame
		_check("Controls Help closes", not help.is_open())

	var dialog: ConfirmationPrompt = _spawn("res://UI/Dialogs/Confirmation Dialog.tscn")
	if dialog != null:
		dialog.show_confirmation("Abandon contract?", "No pay, no history.", "ABANDON")
		await get_tree().process_frame
		_check("Confirmation Dialog opens", dialog.is_open())
		dialog.hide_dialog()

	var toasts: NotificationCenter = _spawn("res://UI/Notifications/Notifications.tscn")
	if toasts != null:
		toasts.success("Contract accepted", "Riverside Bungalow - $240")
		toasts.money("Payment received", "$240")
		toasts.warning("Fuel low", "18% remaining")
		await get_tree().process_frame
		await get_tree().process_frame
		_check("Notification queue drains", toasts.pending_count() == 0)
		toasts.clear_all()

	var transition: TransitionLayer = _spawn("res://UI/Transitions/Transition.tscn")
	if transition != null:
		transition.set_title("RETURNING TO TOWN")
		transition.cover_immediately()
		await get_tree().process_frame
		_check("Transition covers", transition.is_covered())
		transition.reveal_immediately()
		await get_tree().process_frame
		_check("Transition reveals", not transition.is_covered())

	# The live autoload layer, not a fresh instance.
	AppUI.notify_info("Smoke test", "AppUI is alive")
	_check("AppUI notification centre is live", AppUI.notifications() != null)
	_check("AppUI transition layer is live", AppUI.transition() != null)


func _spawn(path: String) -> Node:
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		_fail("Spawn %s" % path.get_file())
		return null
	var node := scene.instantiate()
	_host.add_child(node)
	return node


func _pass(label: String) -> void:
	_passes += 1
	print("[UI SMOKE] %s: PASS" % label)


func _fail(label: String) -> void:
	_failures += 1
	print("[UI SMOKE] %s: FAIL" % label)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass(label)
	else:
		_fail(label)
