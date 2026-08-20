extends Control
class_name SettingsMenu

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   open()
#   close()
#   is_open() -> bool
#
#   set_values(values: Dictionary)   # populate the controls
#   values() -> Dictionary           # read the current control state
#
# Signals emitted:
#
#   apply_requested(settings: Dictionary)   # APPLY pressed
#   back_requested                          # BACK pressed or Escape
#   controls_requested                      # VIEW CONTROLS pressed
#   value_changed(key: String, value: Variant)   # any control moved
#
# THE SETTINGS DICTIONARY - the whole contract between this screen and
# the host. set_values() accepts any subset; missing keys are left alone.
#
#   "mouse_sensitivity"  float   0.1 - 3.0   (1.0 = default)
#   "quality"            int     0-3 index into QUALITY_OPTIONS
#   "fullscreen"         bool
#   "resolution"         int     0-2 index into RESOLUTION_OPTIONS
#   "master_volume"      float   0.0 - 1.0
#   "ambience_volume"    float   0.0 - 1.0
#   "mower_volume"       float   0.0 - 1.0
#
# Convenience read-only extras included in values() but ignored by
# set_values(), so the host can log or display them directly:
#
#   "quality_name"       String  e.g. "High"
#   "resolution_name"    String  e.g. "1920 x 1080"
#
# Volumes are 0.0 - 1.0, NOT 0 - 100 and NOT decibels. Convert with
# linear_to_db() on the host side if you are driving an AudioServer bus.
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing - not even the Controls Help overlay. It
# emits controls_requested and lets the host show it, so the two
# components stay independently copyable.
#
# Settings.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# PRESENTATION ONLY. This screen does not touch DisplayServer,
# ProjectSettings, AudioServer, Input or any config file. It shows values
# and reports what the player chose. Nothing changes until the host acts
# on apply_requested.
#
# The only exception is deliberate and local: the Resolution dropdown is
# disabled while Fullscreen is on, because that combination is
# meaningless. That is layout logic, not a graphics setting.
#
#   settings.apply_requested.connect(func(s: Dictionary) -> void:
#       game_config.mouse_sensitivity = s["mouse_sensitivity"]
#       AudioServer.set_bus_volume_db(master_bus,
#           linear_to_db(s["master_volume"]))
#       DisplayServer.window_set_mode(...)
#       game_config.save())
#
# The dropdown contents are plain constants at the top of this script
# (QUALITY_OPTIONS / RESOLUTION_OPTIONS). Edit them there; the host does
# not need to populate them.
#
# process_mode is ALWAYS so it works over a paused tree - it is normally
# opened from the pause menu, which does not unpause.
#
# ============================================================


signal apply_requested(settings: Dictionary)
signal back_requested()
signal controls_requested()
signal value_changed(key: String, value: Variant)

## Dropdown contents. Change them here; the host does not supply them.
const QUALITY_OPTIONS: PackedStringArray = ["Low", "Medium", "High", "Ultra"]
const RESOLUTION_OPTIONS: PackedStringArray = [
	"1920 x 1080", "1600 x 900", "1280 x 720"
]

@onready var _holder: Control = %CardHolder
@onready var _sensitivity: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _invert_y: CheckButton = %InvertYToggle
@onready var _quality: OptionButton = %QualityOption
@onready var _fullscreen: CheckButton = %FullscreenToggle
@onready var _resolution: OptionButton = %ResolutionOption
@onready var _master: HSlider = %MasterSlider
@onready var _master_value: Label = %MasterValue
@onready var _ambience: HSlider = %AmbienceSlider
@onready var _ambience_value: Label = %AmbienceValue
@onready var _mower: HSlider = %MowerSlider
@onready var _mower_value: Label = %MowerValue
@onready var _controls_button: Button = %ControlsButton
@onready var _back: Button = %BackButton
@onready var _apply: Button = %ApplyButton

var _open: bool = false
var _tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	for option in QUALITY_OPTIONS:
		_quality.add_item(option)
	for option in RESOLUTION_OPTIONS:
		_resolution.add_item(option)
	_quality.selected = 2
	_resolution.selected = 0

	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	_invert_y.toggled.connect(func(pressed: bool) -> void:
		value_changed.emit("invert_look_y", pressed))
	_master.value_changed.connect(_on_volume_changed.bind("master_volume", _master_value))
	_ambience.value_changed.connect(_on_volume_changed.bind("ambience_volume", _ambience_value))
	_mower.value_changed.connect(_on_volume_changed.bind("mower_volume", _mower_value))
	_quality.item_selected.connect(func(index: int) -> void:
		value_changed.emit("quality", index))
	_resolution.item_selected.connect(func(index: int) -> void:
		value_changed.emit("resolution", index))
	_fullscreen.toggled.connect(_on_fullscreen_toggled)

	_controls_button.pressed.connect(func() -> void: controls_requested.emit())
	_back.pressed.connect(func() -> void: back_requested.emit())
	_apply.pressed.connect(func() -> void: apply_requested.emit(values()))

	_refresh_readouts()


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


# ============================================================ open / close

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_animate(1.0, 16.0, 0.0)
	_sensitivity.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_animate(0.0, 0.0, 10.0)


func is_open() -> bool:
	return _open


# ================================================================== values

## Accepts any subset of the documented keys. Unknown keys are ignored,
## so the host can pass its whole config dictionary straight in.
func set_values(new_values: Dictionary) -> void:
	if new_values.has("mouse_sensitivity"):
		_sensitivity.value = float(new_values["mouse_sensitivity"])
	if new_values.has("invert_look_y"):
		_invert_y.button_pressed = bool(new_values["invert_look_y"])
	if new_values.has("quality"):
		_quality.selected = clampi(int(new_values["quality"]), 0,
			QUALITY_OPTIONS.size() - 1)
	if new_values.has("fullscreen"):
		_fullscreen.button_pressed = bool(new_values["fullscreen"])
	if new_values.has("resolution"):
		_resolution.selected = clampi(int(new_values["resolution"]), 0,
			RESOLUTION_OPTIONS.size() - 1)
	if new_values.has("master_volume"):
		_master.value = float(new_values["master_volume"])
	if new_values.has("ambience_volume"):
		_ambience.value = float(new_values["ambience_volume"])
	if new_values.has("mower_volume"):
		_mower.value = float(new_values["mower_volume"])
	_refresh_readouts()


func values() -> Dictionary:
	return {
		"mouse_sensitivity": _sensitivity.value,
		"invert_look_y": _invert_y.button_pressed,
		"quality": _quality.selected,
		"quality_name": QUALITY_OPTIONS[_quality.selected],
		"fullscreen": _fullscreen.button_pressed,
		"resolution": _resolution.selected,
		"resolution_name": RESOLUTION_OPTIONS[_resolution.selected],
		"master_volume": _master.value,
		"ambience_volume": _ambience.value,
		"mower_volume": _mower.value,
	}


# ================================================================ internals

func _on_sensitivity_changed(value: float) -> void:
	_sensitivity_value.text = "%.2f" % value
	value_changed.emit("mouse_sensitivity", value)


func _on_volume_changed(value: float, key: String, readout: Label) -> void:
	readout.text = UITheme.percent_text(value)
	value_changed.emit(key, value)


func _on_fullscreen_toggled(pressed: bool) -> void:
	# Local layout logic only: picking a windowed resolution while
	# fullscreen is on would not mean anything.
	_resolution.disabled = pressed
	value_changed.emit("fullscreen", pressed)


func _refresh_readouts() -> void:
	_sensitivity_value.text = "%.2f" % _sensitivity.value
	_master_value.text = UITheme.percent_text(_master.value)
	_ambience_value.text = UITheme.percent_text(_ambience.value)
	_mower_value.text = UITheme.percent_text(_mower.value)
	_resolution.disabled = _fullscreen.button_pressed


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
