extends Control
class_name PauseMenu

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   open()
#   close()
#   toggle()
#   is_open() -> bool
#   set_context(job_name: String)   # optional subtitle under "PAUSED"
#
# Signals emitted:
#
#   opened                  # the overlay became visible
#   closed                  # the overlay became hidden
#
#   resume_requested
#   restart_job_requested
#   settings_requested
#   abandon_job_requested
#   quit_to_menu_requested
#
# PAUSE THE GAME ON `opened`, UNPAUSE ON `closed`. Those two signals are
# the only ones tied to visibility; the five *_requested signals are pure
# intent and never change what the menu shows.
#
# RESUME is the one exception that is also a visibility action: pressing it
# closes the menu (which fires `closed`) and emits resume_requested.
#
# The other four leave the menu open on purpose, because the host usually
# wants to layer something over it:
#
#   settings_requested      -> host opens Settings.tscn on top
#   restart_job_requested   -> host opens a Confirmation Dialog on top
#   abandon_job_requested   -> host opens a Confirmation Dialog on top
#   quit_to_menu_requested  -> host opens a Confirmation Dialog on top
#
# ...then calls close() itself once the player has actually committed.
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing - not even the Confirmation Dialog. The
# host decides whether an action needs confirming.
#
# Pause Menu.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# If that path changes after copying, update it HERE (root node of the
# scene).
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# ESCAPE HANDLING - read this before integrating.
#
# By default this menu reads the "ui_cancel" action (Escape) itself, in
# _unhandled_input, and toggles itself. Two exported flags control it:
#
#   open_on_escape   (default true)  - Escape opens the menu when closed
#   close_on_escape  (default true)  - Escape closes the menu when open
#
# Set BOTH to false in the inspector if the host game already owns Escape
# (very likely in a production game that also uses Escape to release the
# mouse). The menu then only responds to open() / close() / toggle().
#
# Input is consumed with get_viewport().set_input_as_handled() only when
# the menu actually acts on it, so an unhandled Escape still reaches the
# host.
#
# PAUSING: this component never sets get_tree().paused. It only tells you
# when it opened and closed. Its own process_mode is ALWAYS, so it keeps
# animating and accepting clicks while the host has the tree paused.
#
# MOUSE: a production mower game probably captures the mouse. Release it
# on `opened` and re-capture on `closed`:
#
#   pause_menu.opened.connect(func() -> void:
#       get_tree().paused = true
#       Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
#   pause_menu.closed.connect(func() -> void:
#       get_tree().paused = false
#       Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
#
# ============================================================


signal opened()
signal closed()

signal resume_requested()
signal restart_job_requested()
signal save_game_requested()
signal settings_requested()
signal abandon_job_requested()
signal quit_to_menu_requested()

## Escape opens the menu when it is closed. Turn off if the host owns Escape.
@export var open_on_escape: bool = true
## Escape closes the menu when it is open. Turn off if the host owns Escape.
@export var close_on_escape: bool = true

@onready var _holder: Control = %CardHolder
@onready var _context: Label = %ContextLabel
@onready var _resume: Button = %ResumeButton
@onready var _restart: Button = %RestartButton
@onready var _save: Button = %SaveButton
@onready var _settings: Button = %SettingsButton
@onready var _abandon: Button = %AbandonButton
@onready var _quit: Button = %QuitButton

var _open: bool = false
var _tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	_resume.pressed.connect(_on_resume_pressed)
	_restart.pressed.connect(func() -> void: restart_job_requested.emit())
	_save.pressed.connect(func() -> void: save_game_requested.emit())
	_settings.pressed.connect(func() -> void: settings_requested.emit())
	_abandon.pressed.connect(func() -> void: abandon_job_requested.emit())
	_quit.pressed.connect(func() -> void: quit_to_menu_requested.emit())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _open and close_on_escape:
		close()
		resume_requested.emit()
		get_viewport().set_input_as_handled()
	elif not _open and open_on_escape:
		open()
		get_viewport().set_input_as_handled()


# ============================================================ open / close

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_animate(1.0, 0.0, 18.0)
	_resume.grab_focus()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_animate(0.0, 10.0, 0.0)
	closed.emit()


func toggle() -> void:
	if _open:
		close()
		resume_requested.emit()
	else:
		open()


func is_open() -> bool:
	return _open


## Optional line under the title, e.g. the job the player is paused inside.
func set_context(job_name: String) -> void:
	_context.text = job_name
	_context.visible = not job_name.is_empty()


## Grey out an option the host cannot service right now, rather than leaving a
## button that emits a signal nothing can act on.
## Keys: resume, restart, save, settings, abandon, quit.
func set_option_enabled(option: StringName, enabled: bool) -> void:
	var button := _button_for(option)
	if button == null:
		push_warning("PauseMenu: unknown option %s" % option)
		return
	button.disabled = not enabled


func is_option_enabled(option: StringName) -> bool:
	var button := _button_for(option)
	return button != null and not button.disabled


func _button_for(option: StringName) -> Button:
	match option:
		&"resume":
			return _resume
		&"restart":
			return _restart
		&"save":
			return _save
		&"settings":
			return _settings
		&"abandon":
			return _abandon
		&"quit":
			return _quit
	return null


# ================================================================ internal

func _on_resume_pressed() -> void:
	close()
	resume_requested.emit()


func _animate(target_alpha: float, from_offset: float, to_offset: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_holder.position.y = from_offset
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", target_alpha, UITheme.FADE)
	_tween.tween_property(_holder, "position:y", to_offset, UITheme.FADE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if target_alpha <= 0.0:
		_tween.set_parallel(false)
		_tween.tween_callback(func() -> void: visible = false)
