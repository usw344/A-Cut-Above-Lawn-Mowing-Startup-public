class_name ACAPauseLayer
extends CanvasLayer
## THE pause stack. One implementation, used by every screen that can pause.
##
## Expects four children, by name, all instances of the shared UI components:
##
##     Pause Menu   Settings   Controls Help   Confirmation Dialog
##
## `Pause Layer.tscn` supplies them for the Town; `Gameplay UI.tscn` already had
## them, so `ACAGameplayUI` inherits this class instead of duplicating it.
##
## RESPONSIBILITIES
##   * open/close the pause menu and pause/unpause the tree
##   * own the cursor while the stack is up (through AppUI.hold_mouse)
##   * settings, controls help, save game, quit-to-menu, abandon contract
##
## NOT its business: anything scene-specific. Restarting a contract needs the
## mowing host, so this class only emits `restart_job_requested`.
##
## MOUSE: the stack takes ONE hold (AppUI.MOUSE_HOLD_PAUSE) while anything in it
## is open and releases it when everything is closed. AppUI then restores
## whatever the current screen declared - CAPTURED in mowing, VISIBLE in town.
## That is why resume does the right thing in both places without either screen
## knowing about the other.

## The pause menu was opened.
signal pause_opened()
## The whole stack closed and control went back to the screen.
signal pause_closed()
## The player asked to restart the current contract and confirmed it. Only the
## mowing host can service this.
signal restart_job_requested()

@onready var _pause: PauseMenu = get_node_or_null(^"Pause Menu")
@onready var _settings: SettingsMenu = get_node_or_null(^"Settings")
@onready var _help: ControlsHelp = get_node_or_null(^"Controls Help")
@onready var _confirm: ConfirmationPrompt = get_node_or_null(^"Confirmation Dialog")

## True while this stack owns the tree pause, so it never unpauses a tree it did
## not pause.
var _owns_tree_pause: bool = false

## DEVELOPMENT. The H overlay. Mounted here rather than on each screen because
## this class is already the one thing the Town and the mowing Gameplay UI have
## in common - so there is one debugger implementation, not two.
var _debugger: ACADeveloperDebugger = null


func _ready() -> void:
	_wire_pause_stack()
	_mount_developer_debugger()


# ================================================================== wiring

func _wire_pause_stack() -> void:
	if _pause == null:
		push_error("ACAPauseLayer: no Pause Menu child.")
		return

	_pause.opened.connect(_on_pause_opened)
	_pause.closed.connect(_on_pause_closed)

	_pause.resume_requested.connect(_resume)
	_pause.save_game_requested.connect(_save_game)
	_pause.settings_requested.connect(_open_settings)
	_pause.restart_job_requested.connect(_confirm_restart)
	_pause.abandon_job_requested.connect(_confirm_abandon)
	_pause.quit_to_menu_requested.connect(_confirm_quit_to_menu)

	if _settings != null:
		_settings.set_values(GameSettings.values())
		_settings.value_changed.connect(func(key: String, value: Variant) -> void:
			GameSettings.set_value(key, value))
		_settings.apply_requested.connect(func(values: Dictionary) -> void:
			GameSettings.apply(values)
			SaveService.save_settings()
			AppUI.notify_success("Settings applied"))
		_settings.controls_requested.connect(_open_help)
		_settings.back_requested.connect(_close_settings)

	if _help != null:
		_help.set_title("Controls")
		_help.set_bindings(control_bindings())


## Override in a subclass to list the bindings that make sense on that screen.
func control_bindings() -> PackedStringArray:
	return ACAControlBindings.TOWN


# ========================================================== super debugger (H)
##
## DEVELOPMENT ONLY. Hidden on launch; H opens and closes it. The overlay owns
## its own cursor hold and no game state - see the class docs.
##
## `_unhandled_key_input` deliberately, not `_input`: it runs AFTER the GUI, so
## typing an "h" into the debugger's money field cannot close the debugger.
## The pause stack takes precedence, so H is inert while anything in it is up.

func _mount_developer_debugger() -> void:
	_debugger = ACADeveloperDebugger.new()
	_debugger.name = "Super Debugger"
	add_child(_debugger)


func developer_debugger() -> ACADeveloperDebugger:
	return _debugger


func _unhandled_key_input(event: InputEvent) -> void:
	if _debugger == null:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_H:
		return
	if pause_stack_open():
		return
	_debugger.toggle()
	get_viewport().set_input_as_handled()


# ============================================================ open / close

func open_pause() -> void:
	if _pause != null:
		_pause.open()


func close_pause() -> void:
	if _pause != null:
		_pause.close()


func is_pause_open() -> bool:
	return _pause != null and _pause.is_open()


## True while ANY part of the stack is up, not just the menu itself.
func pause_stack_open() -> bool:
	if _pause != null and _pause.is_open():
		return true
	if _settings != null and _settings.is_open():
		return true
	if _help != null and _help.is_open():
		return true
	if _confirm != null and _confirm.is_open():
		return true
	return false


## Subtitle under "PAUSED", e.g. the contract being worked.
func set_pause_context(text: String) -> void:
	if _pause != null:
		_pause.set_context(text)


## Grey out the two contract actions when there is no contract to act on. This
## is what makes one pause menu correct in the town as well as in gameplay.
func set_job_actions_available(available: bool) -> void:
	set_pause_option_enabled(&"restart", available)
	set_pause_option_enabled(&"abandon", available)


## Keys: resume, restart, save, settings, abandon, quit.
func set_pause_option_enabled(option: StringName, enabled: bool) -> void:
	if _pause != null:
		_pause.set_option_enabled(option, enabled)


func is_pause_option_enabled(option: StringName) -> bool:
	return _pause != null and _pause.is_option_enabled(option)


func set_escape_pause_enabled(enabled: bool) -> void:
	if _pause != null:
		_pause.open_on_escape = enabled


## Shut everything and give the screen back. Used when something else takes the
## screen over (the results screen).
func close_pause_stack() -> void:
	if _confirm != null and _confirm.is_open():
		_confirm.hide_dialog()
	if _help != null and _help.is_open():
		_help.close()
	if _settings != null and _settings.is_open():
		_settings.close()
	if _pause != null and _pause.is_open():
		_pause.close()
	_release_screen()


func _on_pause_opened() -> void:
	# The debugger draws above the pause stack, so it gets out of the way
	# rather than sitting on top of the menu. Its cursor hold goes with it.
	if _debugger != null:
		_debugger.close()
	AppUI.hold_mouse(AppUI.MOUSE_HOLD_PAUSE)
	if not get_tree().paused:
		get_tree().paused = true
		_owns_tree_pause = true
	pause_opened.emit()


func _on_pause_closed() -> void:
	# Something else in the stack usually opens in the same frame (Settings, a
	# confirmation); only really give control back when nothing is left.
	_release_screen()


func _resume() -> void:
	_release_screen()


## Unpause and hand the cursor back to the screen - but only when the whole
## stack is closed. AppUI decides what "back" means for the current screen.
func _release_screen() -> void:
	if pause_stack_open():
		return
	if _owns_tree_pause:
		get_tree().paused = false
		_owns_tree_pause = false
	AppUI.release_mouse(AppUI.MOUSE_HOLD_PAUSE)
	pause_closed.emit()


# ================================================================= actions

func _save_game() -> void:
	if SaveService.save_game():
		AppUI.notify_success("Game saved")
	else:
		AppUI.notify_warning("Could not save", "See the log for details.")


## ORDER MATTERS in this whole section. Closing the pause menu emits `closed`,
## which asks whether the stack is empty; if the replacement panel is not open
## yet the answer is "yes" and the screen resumes underneath it. Always open the
## incoming panel BEFORE closing the outgoing one.
func _open_settings() -> void:
	if _settings == null:
		return
	_settings.set_values(GameSettings.values())
	_settings.open()
	close_pause()


func _close_settings() -> void:
	if _settings == null:
		return
	open_pause()
	_settings.close()


func _open_help() -> void:
	if _help != null:
		_help.open()


# ================================================== destructive confirmations

func _confirm_restart() -> void:
	ask("Restart job?",
		"The lawn goes back to how you found it. Progress on this contract is lost.",
		"RESTART",
		func() -> void:
			restart_job_requested.emit()
			open_pause())


func _confirm_abandon() -> void:
	ask("Abandon contract?",
		"You walk away with no pay, and the contract does not go into your history.",
		"ABANDON",
		func() -> void:
			GameSession.abandon_current_job()
			AppUI.notify_warning("Contract abandoned")
			_force_unpause()
			GameSession.go_to_town())


func _confirm_quit_to_menu() -> void:
	ask("Quit to main menu?",
		"This session is not saved yet. Anything since your last save is lost.",
		"QUIT",
		func() -> void:
			_force_unpause()
			GameSession.end_session()
			GameSession.go_to_main_menu())


## One confirmation flow: ask, run `on_confirm` if accepted, reopen pause if not.
func ask(title: String, message: String, confirm_text: String,
		on_confirm: Callable) -> void:
	if _confirm == null:
		on_confirm.call()
		return
	for connection in _confirm.confirmed.get_connections():
		_confirm.confirmed.disconnect(connection["callable"])
	for connection in _confirm.cancelled.get_connections():
		_confirm.cancelled.disconnect(connection["callable"])

	_confirm.confirmed.connect(on_confirm, CONNECT_ONE_SHOT)
	_confirm.cancelled.connect(func() -> void: open_pause(), CONNECT_ONE_SHOT)
	# Up first, then the pause menu goes away - see the note above _open_settings.
	_confirm.show_confirmation(title, message, confirm_text)
	close_pause()


## Leaving the screen entirely: the stack is going away with it, so drop the
## pause and the cursor hold whether or not something is still nominally open.
func _force_unpause() -> void:
	get_tree().paused = false
	_owns_tree_pause = false
	AppUI.release_mouse(AppUI.MOUSE_HOLD_PAUSE)
