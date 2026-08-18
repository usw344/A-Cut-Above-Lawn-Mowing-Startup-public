class_name RadialMainMenu
extends Control

## Emitted with a stable option ID when a menu item is activated.
signal menu_option_selected(option_id: StringName)

## Allows the host scene to disable Continue without save-system dependencies.
@export var continue_enabled: bool = true:
	set(value):
		continue_enabled = value
		if is_node_ready():
			_apply_continue_enabled()

## Shared palette used by every surface, line, icon, and label in this scene.
@export var colour_scheme: Resource = preload(
	"res://UI/Main Menu/radial_menu/default_colour_scheme.tres"
	
)

@export_group("Polish")
@export var opening_animation_enabled := true
@export var selection_transition_enabled := true
@export_range(0.32, 0.80, 0.01) var selection_transition_duration := 0.48
@export var decorative_orbit_enabled := true:
	set(value):
		decorative_orbit_enabled = value
		if is_node_ready():
			set_process(value)
			queue_redraw()

const REFERENCE_SIZE := Vector2(1600.0, 900.0)
const BASE_RING_RADIUS := 250.0
const BASE_NODE_DIAMETER := 84.0
const BASE_HUB_DIAMETER := 196.0
const MENU_POSITION_RATIO := Vector2(0.29, 0.55)
const RADIAL_MENU_ITEM_SCRIPT := preload("res://UI/Main Menu/radial_menu/radial_menu_item.gd")

const OPTION_DEFINITIONS: Array[Dictionary] = [
	{
		"node_name": &"Continue",
		"option_id": &"continue",
		"display_name": "CONTINUE",
		"description": "Return to your latest mowing job",
	},
	{
		"node_name": &"NewGame",
		"option_id": &"new_game",
		"display_name": "NEW GAME",
		"description": "Start a new mowing business",
	},
	{
		"node_name": &"LoadGame",
		"option_id": &"load_game",
		"display_name": "LOAD GAME",
		"description": "Choose an existing save",
	},
	{
		"node_name": &"Options",
		"option_id": &"options",
		"display_name": "OPTIONS",
		"description": "Graphics, audio and controls",
	},
	{
		"node_name": &"Credits",
		"option_id": &"credits",
		"display_name": "CREDITS",
		"description": "View project credits",
	},
	{
		"node_name": &"Quit",
		"option_id": &"quit",
		"display_name": "QUIT",
		"description": "Exit A Cut Above",
	},
]

@onready var _centre_hub: Control = %CentreHub
@onready var _menu_nodes: Control = %MenuNodes
@onready var _title_area: Control = %TitleArea
@onready var _title_kicker: Label = %TitleKicker
@onready var _title_main: Label = %TitleMain
@onready var _title_build: Label = %TitleBuild
@onready var _title_separator: ColorRect = %TitleSeparator
@onready var _hub_kicker: Label = %HubKicker
@onready var _hub_title: Label = %HubTitle
@onready var _hub_description: Label = %HubDescription
@onready var _hub_divider: ColorRect = %HubDivider
@onready var _bottom_info: Label = %BottomInfo
@onready var _controls_hint: Label = %ControlsHint

var _menu_items: Array[Control] = []
var _menu_centre := Vector2.ZERO
var _ring_radius := BASE_RING_RADIUS
var _design_scale := 1.0
var _hovered_index := -1
var _selected_index := -1
var _hub_tween: Tween
var _opening_tween: Tween
var _transition_tween: Tween
var _orbit_phase := 0.0
var _structure_alpha := 1.0
var _transitioning := false


func _ready() -> void:
	_create_menu_items()
	_connect_colour_scheme()
	_apply_colour_scheme()
	resized.connect(_layout_radial_menu)
	_layout_radial_menu()
	_apply_continue_enabled()
	var initial_index := 0 if _is_option_enabled(0) else _find_next_enabled(0, 1)
	_set_selected_index(initial_index)
	set_process(decorative_orbit_enabled)
	play_opening_animation()


func _process(delta: float) -> void:
	_orbit_phase = fmod(_orbit_phase + delta * 0.22, TAU)
	queue_redraw()


func play_opening_animation() -> void:
	if _opening_tween != null and _opening_tween.is_valid():
		_opening_tween.kill()
	modulate = Color.WHITE
	_menu_nodes.scale = Vector2.ONE
	if not opening_animation_enabled:
		return

	modulate.a = 0.0
	_menu_nodes.scale = Vector2.ONE * 0.90
	_opening_tween = create_tween()
	_opening_tween.set_parallel(true)
	_opening_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_opening_tween.tween_property(self, "modulate", Color.WHITE, 0.35)
	_opening_tween.tween_property(_menu_nodes, "scale", Vector2.ONE, 0.35)


## Restores this menu after a completed transition without reinstantiating it.
func reset_menu(play_opening: bool = true) -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transitioning = false
	_structure_alpha = 1.0
	_hovered_index = -1
	modulate = Color.WHITE
	_menu_nodes.scale = Vector2.ONE
	_title_area.modulate = Color.WHITE
	_centre_hub.modulate = Color.WHITE
	_bottom_info.modulate = Color.WHITE
	_controls_hint.modulate = Color.WHITE

	for item: Control in _menu_items:
		item.call("reset_transition_visuals")

	_show_selected_copy()
	set_process(decorative_orbit_enabled)
	queue_redraw()
	if play_opening:
		play_opening_animation()


func set_colour_scheme(new_scheme: Resource) -> void:
	if new_scheme == null:
		return
	if colour_scheme != new_scheme and colour_scheme != null:
		if colour_scheme.changed.is_connected(_apply_colour_scheme):
			colour_scheme.changed.disconnect(_apply_colour_scheme)
	colour_scheme = new_scheme
	if is_node_ready():
		_connect_colour_scheme()
		_apply_colour_scheme()


func _connect_colour_scheme() -> void:
	if colour_scheme != null and not colour_scheme.changed.is_connected(_apply_colour_scheme):
		colour_scheme.changed.connect(_apply_colour_scheme)


func _apply_colour_scheme() -> void:
	if colour_scheme == null or not is_node_ready():
		return

	_title_kicker.add_theme_color_override("font_color", _scheme_colour(&"secondary_text"))
	_title_main.add_theme_color_override("font_color", _scheme_colour(&"primary_text"))
	_title_build.add_theme_color_override("font_color", _scheme_colour(&"secondary_text"))
	_title_separator.color = _scheme_colour(&"outline")
	_hub_kicker.add_theme_color_override("font_color", _scheme_colour(&"secondary_text"))
	_hub_title.add_theme_color_override("font_color", _scheme_colour(&"primary_text"))
	_hub_description.add_theme_color_override("font_color", _scheme_colour(&"secondary_text"))
	_hub_divider.color = _scheme_colour(&"highlight")
	_bottom_info.add_theme_color_override("font_color", _scheme_colour(&"secondary_text"))
	_controls_hint.add_theme_color_override("font_color", _scheme_colour(&"secondary_text"))

	for item: Control in _menu_items:
		item.call("set_colour_scheme", colour_scheme)
	queue_redraw()


func _scheme_colour(property_name: StringName) -> Color:
	var value: Variant = colour_scheme.get(property_name)
	if value is Color:
		return value
	return Color.WHITE


func _create_menu_items() -> void:
	for index: int in OPTION_DEFINITIONS.size():
		var definition: Dictionary = OPTION_DEFINITIONS[index]
		var item := RADIAL_MENU_ITEM_SCRIPT.new()
		item.name = definition["node_name"]
		item.setup(definition["option_id"], definition["display_name"])
		_menu_nodes.add_child(item)
		item.mouse_entered.connect(_on_item_mouse_entered.bind(index))
		item.mouse_exited.connect(_on_item_mouse_exited.bind(index))
		item.gui_input.connect(_on_item_gui_input.bind(index))
		item.pressed.connect(_on_item_pressed.bind(index))
		_menu_items.append(item)


func _unhandled_key_input(event: InputEvent) -> void:
	if _transitioning:
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var handled := true
	match key_event.keycode:
		KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S:
			_move_selection(1)
		KEY_LEFT, KEY_UP, KEY_A, KEY_W:
			_move_selection(-1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_take_keyboard_control()
			_activate_index(_selected_index)
		KEY_ESCAPE:
			_take_keyboard_control()
			_set_selected_index(5)
		_:
			handled = false

	if handled:
		get_viewport().set_input_as_handled()


func _move_selection(direction: int) -> void:
	_take_keyboard_control()
	var next_index := _find_next_enabled(_selected_index, direction)
	if next_index >= 0:
		_set_selected_index(next_index)


func _take_keyboard_control() -> void:
	if _hovered_index < 0:
		return
	_menu_items[_hovered_index].call("set_mouse_hovered", false)
	_hovered_index = -1
	_show_selected_copy()
	queue_redraw()


func _find_next_enabled(start_index: int, direction: int) -> int:
	if _menu_items.is_empty():
		return -1
	for step: int in _menu_items.size():
		var index := posmod(start_index + direction * (step + 1), _menu_items.size())
		if _is_option_enabled(index):
			return index
	return -1


func _is_option_enabled(index: int) -> bool:
	if index < 0 or index >= _menu_items.size():
		return false
	return index != 0 or continue_enabled


func _set_selected_index(index: int) -> void:
	if not _is_option_enabled(index):
		return
	if _selected_index == index:
		if _hovered_index < 0:
			_show_selected_copy()
		return
	if _selected_index >= 0:
		_menu_items[_selected_index].call("set_keyboard_selected", false)
	_selected_index = index
	_menu_items[_selected_index].call("set_keyboard_selected", true)
	if _hovered_index < 0:
		_show_selected_copy()
	queue_redraw()


func _show_selected_copy() -> void:
	if _selected_index < 0 or _selected_index >= OPTION_DEFINITIONS.size():
		_set_hub_copy("MOW & GROW", "SELECT AN OPTION")
		return
	var definition: Dictionary = OPTION_DEFINITIONS[_selected_index]
	_set_hub_copy(definition["display_name"], definition["description"])


func _apply_continue_enabled() -> void:
	if _menu_items.is_empty():
		return
	_menu_items[0].call("set_disabled_state", not continue_enabled)
	if not continue_enabled and _selected_index == 0:
		var next_index := _find_next_enabled(0, 1)
		_selected_index = -1
		if next_index >= 0:
			_set_selected_index(next_index)
	queue_redraw()


func _on_item_gui_input(event: InputEvent, index: int) -> void:
	if _transitioning:
		return
	if event is InputEventMouseMotion and _hovered_index != index:
		_on_item_mouse_entered(index)


func _on_item_mouse_entered(index: int) -> void:
	if _transitioning:
		return
	if not _is_option_enabled(index):
		return
	if _hovered_index >= 0 and _hovered_index != index:
		_menu_items[_hovered_index].call("set_mouse_hovered", false)
	_hovered_index = index
	_menu_items[index].call("set_mouse_hovered", true)
	var definition: Dictionary = OPTION_DEFINITIONS[index]
	_set_hub_copy(definition["display_name"], definition["description"])
	queue_redraw()


func _on_item_mouse_exited(index: int) -> void:
	if _transitioning:
		return
	if index < 0 or index >= _menu_items.size():
		return
	_menu_items[index].call("set_mouse_hovered", false)
	if _hovered_index != index:
		return
	_hovered_index = -1
	_show_selected_copy()
	queue_redraw()


func _on_item_pressed(index: int) -> void:
	if _transitioning:
		return
	if not _is_option_enabled(index):
		return
	_set_selected_index(index)
	_activate_index(index)


func _activate_index(index: int) -> void:
	if _transitioning or not _is_option_enabled(index):
		return
	var definition: Dictionary = OPTION_DEFINITIONS[index]
	var option_id: StringName = definition["option_id"]
	var readable_name := String(definition["display_name"]).capitalize()
	print("Main Menu: %s selected" % readable_name)
	if not selection_transition_enabled:
		menu_option_selected.emit(option_id)
		return
	_begin_selection_transition(index, option_id)


func _begin_selection_transition(index: int, option_id: StringName) -> void:
	_transitioning = true
	if _opening_tween != null and _opening_tween.is_valid():
		_opening_tween.kill()
	if _hub_tween != null and _hub_tween.is_valid():
		_hub_tween.kill()
	modulate = Color.WHITE
	_menu_nodes.scale = Vector2.ONE

	if _hovered_index >= 0:
		_menu_items[_hovered_index].call("set_mouse_hovered", false)
	_hovered_index = -1
	_set_hub_copy_alpha(1.0)

	for item_index: int in _menu_items.size():
		_menu_items[item_index].call("prepare_for_transition", item_index == index)

	var duration := selection_transition_duration
	var supporting_fade_duration := duration * 0.56
	var selected_item: Control = _menu_items[index]
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_method(
		_set_structure_alpha,
		_structure_alpha,
		0.0,
		supporting_fade_duration
	)

	for control: Control in [_title_area, _centre_hub, _bottom_info, _controls_hint]:
		_transition_tween.tween_property(
			control,
			"modulate:a",
			0.0,
			supporting_fade_duration
		)

	for item_index: int in _menu_items.size():
		var item: Control = _menu_items[item_index]
		if item_index == index:
			_transition_tween.tween_property(item, "scale", Vector2.ONE * 1.70, duration)
			_transition_tween.tween_method(
				Callable(item, "set_activation_progress"),
				0.0,
				1.0,
				duration * 0.66
			)
			_transition_tween.tween_property(
				item,
				"modulate:a",
				0.0,
				duration * 0.24
			).set_delay(duration * 0.70)
		else:
			_transition_tween.tween_property(
				item,
				"modulate:a",
				0.0,
				supporting_fade_duration * 0.82
			)
			_transition_tween.tween_property(
				item,
				"scale",
				Vector2.ONE * 0.88,
				supporting_fade_duration
			)

	_transition_tween.chain().tween_callback(_complete_selection_transition.bind(option_id))


func _set_structure_alpha(alpha: float) -> void:
	_structure_alpha = alpha
	queue_redraw()


func _complete_selection_transition(option_id: StringName) -> void:
	set_process(false)
	menu_option_selected.emit(option_id)


func _set_hub_copy(title: String, description: String) -> void:
	if _hub_tween != null and _hub_tween.is_valid():
		_hub_tween.kill()

	var current_alpha := _hub_title.modulate.a
	_hub_tween = create_tween()
	_hub_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hub_tween.tween_method(_set_hub_copy_alpha, current_alpha, 0.0, 0.05)
	_hub_tween.tween_callback(_assign_hub_copy.bind(title, description))
	_hub_tween.tween_method(_set_hub_copy_alpha, 0.0, 1.0, 0.10)


func _assign_hub_copy(title: String, description: String) -> void:
	_hub_title.text = title
	_hub_description.text = description


func _set_hub_copy_alpha(alpha: float) -> void:
	var copy_modulate := Color(1.0, 1.0, 1.0, alpha)
	_hub_title.modulate = copy_modulate
	_hub_description.modulate = copy_modulate


func _layout_radial_menu() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or _menu_items.is_empty():
		return

	_design_scale = minf(size.x / REFERENCE_SIZE.x, size.y / REFERENCE_SIZE.y)
	_design_scale = clampf(_design_scale, 0.65, 1.6)
	_menu_centre = Vector2(size.x * MENU_POSITION_RATIO.x, size.y * MENU_POSITION_RATIO.y)
	_ring_radius = BASE_RING_RADIUS * _design_scale

	var node_diameter := BASE_NODE_DIAMETER * _design_scale
	var angle_step := TAU / float(_menu_items.size())

	for index: int in _menu_items.size():
		var angle := -PI / 2.0 + angle_step * float(index)
		var direction := Vector2(cos(angle), sin(angle))
		var item: Control = _menu_items[index]
		item.call("apply_geometry", node_diameter, direction, _design_scale)
		item.position = _menu_centre + direction * _ring_radius - item.size * 0.5

	var hub_diameter := BASE_HUB_DIAMETER * _design_scale
	_centre_hub.position = _menu_centre - Vector2.ONE * hub_diameter * 0.5
	_centre_hub.size = Vector2.ONE * hub_diameter
	_menu_nodes.pivot_offset = _menu_centre
	_layout_typography()
	queue_redraw()


func _layout_typography() -> void:
	_title_area.position = Vector2(58.0, 44.0) * _design_scale
	_title_area.size = Vector2(370.0, 116.0) * _design_scale
	_title_kicker.add_theme_font_size_override("font_size", maxi(11, roundi(14.0 * _design_scale)))
	_title_main.add_theme_font_size_override("font_size", maxi(24, roundi(40.0 * _design_scale)))
	_title_build.add_theme_font_size_override("font_size", maxi(9, roundi(11.0 * _design_scale)))

	_hub_kicker.add_theme_font_size_override("font_size", maxi(8, roundi(9.0 * _design_scale)))
	_hub_title.add_theme_font_size_override("font_size", maxi(14, roundi(20.0 * _design_scale)))
	_hub_description.add_theme_font_size_override("font_size", maxi(8, roundi(9.0 * _design_scale)))

	_bottom_info.position = Vector2(58.0 * _design_scale, size.y - 49.0 * _design_scale)
	_bottom_info.size = Vector2(300.0, 24.0) * _design_scale
	_bottom_info.add_theme_font_size_override("font_size", maxi(9, roundi(10.0 * _design_scale)))
	_controls_hint.position = Vector2(
		size.x - 358.0 * _design_scale,
		size.y - 49.0 * _design_scale
	)
	_controls_hint.size = Vector2(300.0, 24.0) * _design_scale
	_controls_hint.add_theme_font_size_override("font_size", maxi(9, roundi(10.0 * _design_scale)))


func _draw() -> void:
	if colour_scheme == null or _menu_items.is_empty():
		return

	for layer: int in 5:
		var atmosphere_colour := _draw_colour(&"menu_atmosphere")
		atmosphere_colour.a *= 0.45 + float(layer) * 0.14
		var atmosphere_radius := _ring_radius * (1.34 - float(layer) * 0.13)
		draw_circle(_menu_centre, atmosphere_radius, atmosphere_colour)

	var hub_radius := BASE_HUB_DIAMETER * _design_scale * 0.5
	var node_radius := BASE_NODE_DIAMETER * _design_scale * 0.5
	var line_width := maxf(1.0, _design_scale)
	var angle_step := TAU / float(_menu_items.size())

	for index: int in _menu_items.size():
		var angle := -PI / 2.0 + angle_step * float(index)
		var direction := Vector2(cos(angle), sin(angle))
		var line_start := _menu_centre + direction * (hub_radius + 5.0 * _design_scale)
		var line_end := _menu_centre + direction * (
			_ring_radius - node_radius - 7.0 * _design_scale
		)
		var connector_colour := _scheme_colour(&"connector")
		var connector_width := line_width
		if index == _hovered_index:
			connector_colour = connector_colour.lerp(_scheme_colour(&"highlight"), 0.62)
			connector_colour.a = 0.68
			connector_width = maxf(1.5, 1.7 * _design_scale)
		elif index == _selected_index:
			connector_colour = connector_colour.lerp(_scheme_colour(&"highlight"), 0.30)
			connector_colour.a = 0.38
			connector_width = maxf(1.0, 1.25 * _design_scale)
		connector_colour.a *= _structure_alpha
		draw_line(line_start, line_end, connector_colour, connector_width, true)

	draw_arc(
		_menu_centre,
		_ring_radius,
		0.0,
		TAU,
		160,
		_draw_colour(&"outline"),
		line_width,
		true
	)

	var hub_halo := _draw_colour(&"menu_atmosphere")
	hub_halo.a *= 1.7
	draw_circle(_menu_centre, hub_radius + 15.0 * _design_scale, hub_halo)
	draw_circle(_menu_centre, hub_radius, _draw_colour(&"hub_fill"))
	draw_arc(
		_menu_centre,
		hub_radius,
		0.0,
		TAU,
		96,
		_draw_colour(&"outline"),
		maxf(1.0, 1.5 * _design_scale),
		true
	)
	draw_arc(
		_menu_centre,
		hub_radius - 10.0 * _design_scale,
		0.0,
		TAU,
		96,
		_draw_colour(&"connector"),
		line_width,
		true
	)

	if decorative_orbit_enabled:
		var orbit_radius := hub_radius - 16.0 * _design_scale
		for dot_index: int in 3:
			var dot_angle := _orbit_phase + TAU * float(dot_index) / 3.0
			var dot_position := _menu_centre + Vector2(cos(dot_angle), sin(dot_angle)) * orbit_radius
			var dot_colour := _scheme_colour(&"highlight")
			dot_colour.a = (0.34 - float(dot_index) * 0.055) * _structure_alpha
			var dot_radius := maxf(1.25, (1.8 - float(dot_index) * 0.16) * _design_scale)
			draw_circle(dot_position, dot_radius, dot_colour)


func _draw_colour(property_name: StringName) -> Color:
	var colour := _scheme_colour(property_name)
	colour.a *= _structure_alpha
	return colour
