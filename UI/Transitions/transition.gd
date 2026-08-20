extends CanvasLayer
class_name TransitionLayer

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   fade_to_black(duration: float = -1.0)     # cover the screen
#   fade_from_black(duration: float = -1.0)   # reveal the screen
#   fade_out_and_in(hold: float = 0.15)       # cover, wait, reveal
#
#   cover_immediately()      # snap to covered, no tween, no signal delay
#   reveal_immediately()     # snap to clear
#   is_covered() -> bool
#   is_busy() -> bool        # a fade is currently running
#
#   set_title(title: String, subtitle: String = "")   # shown while covered
#   clear_title()
#
# Passing -1.0 as a duration uses the exported default_duration.
#
# Signals emitted:
#
#   screen_covered        # the screen is FULLY black - swap content now
#   transition_finished   # the screen is fully clear again
#
# THE INTEGRATION CONTRACT:
#
#   1. Host calls fade_to_black()
#   2. Transition reaches fully covered state
#   3. screen_covered emits
#   4. Host changes game content (change scene, move player, load job)
#   5. Host calls fade_from_black()
#   6. transition_finished emits
#
# fade_out_and_in() does the same thing but performs step 5 itself after
# `hold` seconds - use it when the host work in step 4 is instant.
#
# Example:
#
#   transition.screen_covered.connect(_swap_to_job_scene, CONNECT_ONE_SHOT)
#   transition.fade_to_black()
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing.
#
# Transition.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (on the Screen child Control)
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# THIS COMPONENT MUST NOT DECIDE WHICH SCENE COMES NEXT, and it does not:
# it only paints over the viewport and tells you when it is safe to swap.
#
# The root is a CanvasLayer (layer 128) rather than a Control, so it draws
# over every other CanvasLayer in the host HUD without depending on node
# order. Add it as a child of anything - the host root works fine.
#
# While covered it sets mouse_filter STOP on its Screen child, so clicks
# cannot reach whatever is being swapped underneath; while clear, IGNORE.
#
# process_mode is ALWAYS, so a transition still runs if the host has
# paused the tree (common when transitioning out of a pause menu).
#
# The cover colour is the palette near-black, NOT pure black, so it
# matches the rest of the UI. Change `cover_colour` in the inspector or
# the Fill node in Transition.tscn.
#
# ============================================================


signal screen_covered()
signal transition_finished()

## Seconds for one direction of the fade when the caller passes -1.0.
@export var default_duration: float = 0.35
## Painted over the screen. Palette near-black rather than pure black.
@export var cover_colour: Color = Color(0.043, 0.059, 0.067, 1.0):
	set(value):
		cover_colour = value
		if is_node_ready():
			_fill.color = Color(value.r, value.g, value.b, 1.0)

@onready var _screen: Control = %Screen
@onready var _fill: ColorRect = %Fill
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle

var _covered: bool = false
var _tween: Tween


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The whole Screen fades as one, so an optional title fades with the
	# cover instead of floating on top of it. The fill itself stays opaque.
	_fill.color = Color(cover_colour.r, cover_colour.g, cover_colour.b, 1.0)
	_screen.modulate.a = 0.0
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.visible = false
	clear_title()


# ================================================================== fading

func fade_to_black(duration: float = -1.0) -> void:
	var time := default_duration if duration < 0.0 else duration
	_kill()
	_screen.visible = true
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_tween = create_tween()
	_tween.tween_property(_screen, "modulate:a", 1.0, time)
	_tween.tween_callback(func() -> void:
		_covered = true
		screen_covered.emit())


func fade_from_black(duration: float = -1.0) -> void:
	var time := default_duration if duration < 0.0 else duration
	_kill()
	_screen.visible = true
	_tween = create_tween()
	_tween.tween_property(_screen, "modulate:a", 0.0, time)
	_tween.tween_callback(func() -> void:
		_covered = false
		_screen.visible = false
		_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clear_title()
		transition_finished.emit())


## Cover, hold, reveal. screen_covered still fires at the covered moment,
## so the host can swap content during the hold.
func fade_out_and_in(hold: float = 0.15) -> void:
	var time := default_duration
	_kill()
	_screen.visible = true
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_tween = create_tween()
	_tween.tween_property(_screen, "modulate:a", 1.0, time)
	_tween.tween_callback(func() -> void:
		_covered = true
		screen_covered.emit())
	_tween.tween_interval(hold)
	_tween.tween_property(_screen, "modulate:a", 0.0, time)
	_tween.tween_callback(func() -> void:
		_covered = false
		_screen.visible = false
		_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clear_title()
		transition_finished.emit())


func cover_immediately() -> void:
	_kill()
	_screen.visible = true
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.modulate.a = 1.0
	_covered = true


func reveal_immediately() -> void:
	_kill()
	_screen.modulate.a = 0.0
	_screen.visible = false
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_covered = false


func is_covered() -> bool:
	return _covered


func is_busy() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


# =================================================================== title

## Optional text shown centred while the screen is covered. Useful for
## "TRAVELLING TO A RESIDENCE" style beats between scenes.
func set_title(title: String, subtitle: String = "") -> void:
	_title.text = title.to_upper()
	_title.visible = not title.is_empty()
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()


func clear_title() -> void:
	_title.text = ""
	_title.visible = false
	_subtitle.text = ""
	_subtitle.visible = false


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
