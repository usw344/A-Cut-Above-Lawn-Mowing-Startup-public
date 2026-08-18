extends Control

const DEFAULT_COLOUR_SCHEME := preload("res://UI/Main Menu/radial_menu/default_colour_scheme.tres")

@export var colour_scheme: Resource = DEFAULT_COLOUR_SCHEME

## Hides the placeholder and requests a transparent game window where supported.
@export var transparent_background := false:
	set(value):
		transparent_background = value
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
		game_window.transparent_bg = transparent_background
