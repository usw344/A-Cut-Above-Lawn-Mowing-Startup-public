class_name ACABuildingPanel
extends PanelContainer
## Location information card shown when a building is selected.
##
## Lives under a plain Control (not a Container) so it can own its own position and
## slide in from the right without a layout pass fighting the tween.

signal open_pressed()
signal back_pressed()

const SLIDE := 40.0
const FADE_TIME := 0.22

@export var title_label: Label
@export var description_label: Label
@export var status_label: Label
@export var open_button: Button
@export var back_button: Button
@export var accent_bar: ColorRect

var _tween: Tween
var _shown := false
var _rest_x := 0.0


func _ready() -> void:
	_rest_x = position.x
	modulate.a = 0.0
	visible = false
	if open_button != null:
		open_button.pressed.connect(func() -> void: open_pressed.emit())
	if back_button != null:
		back_button.pressed.connect(func() -> void: back_pressed.emit())


func show_building(display_name: String, description: String, action_label: String,
		accent: Color, is_enabled: bool) -> void:
	if title_label != null:
		title_label.text = display_name.to_upper()
	if description_label != null:
		description_label.text = description
	if accent_bar != null:
		accent_bar.color = accent
	if open_button != null:
		open_button.text = action_label
	if status_label != null:
		status_label.visible = not is_enabled
	_animate(true)


func hide_panel() -> void:
	_animate(false)


func is_shown() -> bool:
	return _shown


func _animate(to_shown: bool) -> void:
	if _shown == to_shown:
		return
	_shown = to_shown
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if to_shown:
		visible = true
		position.x = _rest_x + SLIDE
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"modulate:a", 1.0 if to_shown else 0.0, FADE_TIME)
	_tween.tween_property(self, ^"position:x", _rest_x if to_shown else _rest_x + SLIDE, FADE_TIME)
	if not to_shown:
		_tween.set_parallel(false)
		_tween.tween_callback(func() -> void: visible = false)
