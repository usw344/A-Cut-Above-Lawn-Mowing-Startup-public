extends Control
class_name ConfirmationPrompt

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   show_confirmation(
#       title: String,
#       message: String,
#       confirm_text: String = "CONFIRM",
#       cancel_text: String = "CANCEL",
#       danger: bool = true)
#
#   hide_dialog()
#   is_open() -> bool
#
# `danger` styles the confirm button as destructive (muted red). Pass
# false for neutral confirmations so the confirm button reads as the
# normal green primary action.
#
# Signals emitted:
#
#   confirmed
#   cancelled
#
# Exactly ONE of the two fires per showing, and the dialog closes itself
# before emitting. Cancelling includes pressing Escape or clicking the
# dimmed background.
#
# Because the signals are generic, connect them per use with CONNECT_ONE_SHOT
# rather than wiring them once in _ready():
#
#   func _on_abandon_requested() -> void:
#       dialog.confirmed.connect(_abandon_the_job, CONNECT_ONE_SHOT)
#       dialog.cancelled.connect(_forget_it, CONNECT_ONE_SHOT)
#       dialog.show_confirmation("ABANDON JOB?",
#           "Progress on this contract may be lost.", "ABANDON", "CANCEL")
#
# hide_dialog() closes without emitting either signal - use it when the
# host needs to dismiss the dialog for its own reasons.
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing.
#
# Confirmation Dialog.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# NOTE FOR THE HOST: other components in res://UI/ that want a confirm
# step (Pause Menu in particular) deliberately do NOT preload this scene.
# The host owns the dialog instance and decides which actions need
# confirming. One instance can serve every confirmation in the game.
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# This is NOT a window manager. It is one modal card with two buttons.
# There is no stacking, no queue, and no result codes - show it, answer
# it, done. Showing it again while open just re-populates it.
#
# Keyboard: Escape cancels, Enter confirms. Both are handled in
# _unhandled_input and only while the dialog is open, so they never
# interfere with the host otherwise. The confirm button takes focus on
# open; cancel is one Tab away.
#
# process_mode is ALWAYS, so it works over a paused tree - which is the
# usual case, since it is normally opened from the pause menu.
#
# The root is a full-rect Control with mouse_filter STOP. It draws its
# own dim layer; put it above the pause menu in the host HUD so the
# dialog reads as being on top.
#
# ============================================================


signal confirmed()
signal cancelled()

## Clicking the dimmed area outside the card cancels. Turn off for
## confirmations the player must answer explicitly.
@export var cancel_on_click_outside: bool = true

@onready var _holder: Control = %CardHolder
@onready var _scrim_button: Button = %ScrimButton
@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _confirm: Button = %ConfirmButton
@onready var _cancel: Button = %CancelButton

var _open: bool = false
var _tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm.pressed.connect(_on_confirm)
	_cancel.pressed.connect(_on_cancel)
	_scrim_button.pressed.connect(func() -> void:
		if cancel_on_click_outside:
			_on_cancel())


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_confirm()
		get_viewport().set_input_as_handled()


# ==================================================================== show

func show_confirmation(title: String, message: String,
		confirm_text: String = "CONFIRM", cancel_text: String = "CANCEL",
		danger: bool = true) -> void:
	_title.text = title.to_upper()
	_message.text = message
	_message.visible = not message.is_empty()
	_confirm.text = confirm_text
	_cancel.text = cancel_text

	if danger:
		UITheme.style_danger_button(_confirm, 42.0, UITheme.FONT_BODY)
	else:
		UITheme.style_button(_confirm, true, 42.0, UITheme.FONT_BODY)

	_open = true
	visible = true
	_animate(1.0, 14.0, 0.0)
	_confirm.grab_focus()


## Close without answering. Emits neither signal.
func hide_dialog() -> void:
	if not _open:
		return
	_open = false
	_animate(0.0, 0.0, 8.0)


func is_open() -> bool:
	return _open


# ================================================================ internal

func _on_confirm() -> void:
	if not _open:
		return
	hide_dialog()
	confirmed.emit()


func _on_cancel() -> void:
	if not _open:
		return
	hide_dialog()
	cancelled.emit()


func _animate(target_alpha: float, from_offset: float, to_offset: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_holder.position.y = from_offset
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", target_alpha, UITheme.FADE_FAST)
	_tween.tween_property(_holder, "position:y", to_offset, UITheme.FADE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if target_alpha <= 0.0:
		_tween.set_parallel(false)
		_tween.tween_callback(func() -> void: visible = false)
