extends Node
## Host for the Main Menu. Turns menu intent into application flow.
##
## The menu component stays presentation-only; every decision about what an
## option *means* lives here.
##
## Save/load is looked up at runtime (`/root/SaveService`) rather than
## referenced statically, so this screen works whether or not the save system
## autoload is present.

@onready var _settings: SettingsMenu = $"Menu UI/Settings"
@onready var _help: ControlsHelp = $"Menu UI/Controls Help"
@onready var _load_menu: LoadGameScreen = $"Menu UI/Load Game"
@onready var _credits: CreditsScreen = $"Menu UI/Credits"
@onready var _new_game: NewGameScreen = $"Menu UI/New Game"

var _menu: MainMenuScreen


func _ready() -> void:
	AppUI.set_mouse_context(Input.MOUSE_MODE_VISIBLE)

	# The menu is composed inside the scenery scene, so find it by type rather
	# than by a path that the scenery package owns.
	_menu = _find_menu()
	if _menu == null:
		push_error("Main Menu Screen: no MainMenuScreen found in the scene.")
		return

	_menu.menu_option_selected.connect(_on_option_selected)
	_menu.set_continue_enabled(_has_save())

	_settings.set_values(GameSettings.values())
	_settings.value_changed.connect(func(key: String, value: Variant) -> void:
		GameSettings.set_value(key, value))
	_settings.apply_requested.connect(func(values: Dictionary) -> void:
		GameSettings.apply(values)
		SaveService.save_settings()
		AppUI.notify_success("Settings applied"))
	_help.set_title("Controls")
	_help.set_bindings(ACAControlBindings.MENU)
	_settings.controls_requested.connect(func() -> void: _help.open())
	_settings.back_requested.connect(_close_settings)

	_credits.back_requested.connect(_close_credits)

	# NEW GAME leads into the difficulty choice rather than straight into a
	# session. The component knows nothing about what a difficulty does; this
	# host reads the profile table and acts on the answer.
	_new_game.set_options(_difficulty_options())
	_new_game.select(ACADifficulty.DEFAULT_ID)
	_new_game.difficulty_chosen.connect(_on_difficulty_chosen)
	_new_game.back_requested.connect(_close_new_game)

	_load_menu.load_requested.connect(_on_load_requested)
	_load_menu.delete_requested.connect(_on_delete_requested)
	_load_menu.back_requested.connect(_close_load_menu)


func _find_menu() -> MainMenuScreen:
	for node in find_children("*", "MainMenuScreen", true, false):
		return node as MainMenuScreen
	return null


func _on_option_selected(option_id: StringName) -> void:
	match option_id:
		&"new_game":
			_open_new_game()
		&"continue":
			_continue_latest()
		&"load_game":
			_open_load_menu()
		&"options":
			_open_settings()
		&"credits":
			_credits.open()
		&"quit":
			get_tree().quit()
		_:
			push_warning("Main Menu: unhandled option %s" % option_id)


# ================================================================== new game

## The player-facing profiles, in the order `ACADifficulty` lists them, turned
## into the plain dictionaries the component expects. No multipliers cross this
## line: what the player is shown is a name, a sentence and a few
## characteristics, because the numbers underneath are a designer's business.
func _difficulty_options() -> Array:
	var out: Array = []
	for id: StringName in ACADifficulty.PLAYER_IDS:
		out.append({
			"id": id,
			"name": ACADifficulty.display_name(id),
			"description": ACADifficulty.description(id),
			"characteristics": ACADifficulty.characteristics(id),
		})
	return out


## THE RADIAL MENU GOES AWAY while the difficulty is being chosen. The first
## capture of this screen showed both at once - the radial ring reading straight
## through the cards and the two titles overlapping in the top left - because
## the difficulty screen is a full-screen decision rather than a panel over the
## menu, and nothing had said so.
func _open_new_game() -> void:
	_menu.visible = false
	_new_game.open()


func _on_difficulty_chosen(id: StringName) -> void:
	_new_game.close()
	_menu.visible = true
	GameSession.start_new_game(id)


func _close_new_game() -> void:
	_new_game.close()
	_menu.visible = true
	_menu.reset_menu(false)


# ================================================================== save/load
##
## SaveService is looked up at runtime rather than referenced statically, so this
## screen still works if the autoload is ever absent.

func _save_service() -> Node:
	return get_node_or_null(^"/root/SaveService")


func _has_save() -> bool:
	var svc := _save_service()
	return svc != null and svc.call(&"has_any_save")


## CONTINUE goes straight into the most recent save without a picker.
func _continue_latest() -> void:
	var svc := _save_service()
	if svc == null or not _has_save():
		_unavailable("No saved games found.")
		return
	if not svc.call(&"load_most_recent"):
		_unavailable("That save could not be loaded.")


## LOAD GAME shows the picker.
func _open_load_menu() -> void:
	var svc := _save_service()
	if svc == null:
		_unavailable("Save system unavailable.")
		return
	_load_menu.set_saves(svc.call(&"list_saves"))
	_load_menu.open()


func _close_load_menu() -> void:
	_load_menu.close()
	_menu.reset_menu(false)


func _on_load_requested(slot_name: String) -> void:
	var svc := _save_service()
	if svc == null:
		return
	_load_menu.close()
	if not svc.call(&"load_game", slot_name):
		_unavailable("Save '%s' could not be loaded." % slot_name)


func _on_delete_requested(slot_name: String) -> void:
	var svc := _save_service()
	if svc == null:
		return
	svc.call(&"delete_save", slot_name)
	_load_menu.set_saves(svc.call(&"list_saves"))
	_menu.set_continue_enabled(_has_save())
	AppUI.notify_info("Save deleted", slot_name)


func _close_credits() -> void:
	_credits.close()
	_menu.reset_menu(false)


func _open_settings() -> void:
	_settings.open()


func _close_settings() -> void:
	_settings.close()
	_menu.reset_menu(false)


func _unavailable(message: String) -> void:
	print("[MAIN MENU] %s" % message)
	# Re-arm the menu so the player can pick something else.
	_menu.reset_menu(false)
