class_name ACAPlaceholderScreen
extends Control
## Stand-in destination screen. The real A Cut Above systems replace this later;
## for now it only proves the Business Town's navigation flow end to end.

signal closed()

@export var title_label: Label
@export var subtitle_label: Label
@export var back_button: Button
@export var accent_bar: ColorRect

const FADE_TIME := 0.2

var _tween: Tween


func _ready() -> void:
	modulate.a = 0.0
	visible = false
	if back_button != null:
		back_button.pressed.connect(close)


func open(display_name: String, accent: Color) -> void:
	if title_label != null:
		title_label.text = display_name.to_upper()
	if subtitle_label != null:
		subtitle_label.text = "Coming Soon"
	if accent_bar != null:
		accent_bar.color = accent
	visible = true
	_fade(1.0)
	if back_button != null:
		back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	_fade(0.0)
	closed.emit()


func is_open() -> bool:
	return visible and modulate.a > 0.5


func _fade(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"modulate:a", target, FADE_TIME)
	if target <= 0.0:
		_tween.tween_callback(func() -> void: visible = false)
