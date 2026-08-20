extends Control
class_name MainMenuScreen
## Presentation only. It shows the radial menu and re-emits the player choice;
## it never routes, never loads a scene and never touches game systems.
## The host (Game/App/main_menu_screen.gd) decides what an option means.

## Forwarded from the radial menu. Option ids: continue, new_game, load_game,
## options, credits, quit.
signal menu_option_selected(option_id: StringName)

const DEFAULT_COLOUR_SCHEME := preload("res://UI/Main Menu/radial_menu/default_colour_scheme.tres")

@export var colour_scheme: Resource = DEFAULT_COLOUR_SCHEME

## Hides the flat placeholder fill so whatever is behind the menu shows through
## (the 3D menu scenery, or a live world).
@export var transparent_background := false:
	set(value):
		transparent_background = value
		if is_node_ready():
			_apply_background_mode()

## Requests an OS-level transparent game window. This was how the UI sandbox
## previewed the menu with no background of its own; it is NOT wanted once the
## menu sits over real 3D content, because a transparent viewport also disables
## sub-surface scattering and depth of field. Leave it off in the game.
@export var request_transparent_window := false:
	set(value):
		request_transparent_window = value
		if is_node_ready():
			_apply_background_mode()

## Darkens only the left side when a world or placeholder background is visible.
@export var readability_gradient_enabled := true:
	set(value):
		readability_gradient_enabled = value
		if is_node_ready():
			_apply_background_mode()

@onready var _background_placeholder: ColorRect = %BackgroundPlaceholder
@onready var _readability_gradient: ColorRect = %ReadabilityGradient
@onready var _radial_menu: Control = %RadialMenu


func _ready() -> void:
	if colour_scheme == null:
		colour_scheme = DEFAULT_COLOUR_SCHEME
	if not colour_scheme.changed.is_connected(_apply_colour_scheme):
		colour_scheme.changed.connect(_apply_colour_scheme)
	_apply_colour_scheme()
	_apply_background_mode()
	_radial_menu.connect(&"menu_option_selected", _on_menu_option_selected)


func _on_menu_option_selected(option_id: StringName) -> void:
	menu_option_selected.emit(option_id)


## Greys out CONTINUE when there is nothing to continue.
func set_continue_enabled(value: bool) -> void:
	_radial_menu.set(&"continue_enabled", value)


## Re-arm the menu after returning to it, so its opening animation and input
## state are fresh.
func reset_menu(play_opening: bool = true) -> void:
	_radial_menu.call(&"reset_menu", play_opening)


# ======================================================= PRESENTATION API
##
## Forwarded from the radial menu, for screenshots and Trailer Capture. They put
## the REAL menu into the REAL hover state; nothing here fakes a look.

## Show `option_id` as the hovered/selected item. Returns false if it is unknown
## or disabled (CONTINUE with no save, for instance).
func preview_hover_option(option_id: StringName) -> bool:
	return bool(_radial_menu.call(&"preview_hover_option", option_id))


func clear_preview_hover() -> void:
	_radial_menu.call(&"clear_preview_hover")


## Screen position of an option, for placing a real cursor on it.
func option_screen_position(option_id: StringName) -> Vector2:
	return _radial_menu.call(&"option_screen_position", option_id)


func _apply_colour_scheme() -> void:
	var background_colour: Color = colour_scheme.get(&"prototype_background")
	var overlay_colour: Color = colour_scheme.get(&"readability_overlay")
	_background_placeholder.color = background_colour
	var gradient_material := _readability_gradient.material as ShaderMaterial
	if gradient_material != null:
		gradient_material.set_shader_parameter(&"tint_colour", overlay_colour)
	_radial_menu.call("set_colour_scheme", colour_scheme)


func _apply_background_mode() -> void:
	_background_placeholder.visible = not transparent_background
	_readability_gradient.visible = readability_gradient_enabled and not transparent_background
	var game_window := get_window()
	if game_window != null:
		game_window.transparent_bg = request_transparent_window
