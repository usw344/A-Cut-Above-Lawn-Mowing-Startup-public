class_name ACAGameSettings
extends Node
## Presentation settings. Autoloaded as `GameSettings`.
##
## Holds the current values and applies the ones this project can actually
## service through ordinary Godot mechanisms. It is deliberately small: this is
## not an options framework, and anything it cannot honestly apply is left as a
## stored value rather than pretending.
##
## Keys match the Settings component's dictionary exactly, so
## `settings.set_values(GameSettings.values())` and
## `GameSettings.apply(settings.values())` both just work.
##
## Persistence lives with the save system so both honour the same storage root
## override; see SaveService.

signal changed(key: String, value: Variant)
signal applied(values: Dictionary)

const DEFAULTS := {
	"mouse_sensitivity": 1.0,
	"invert_look_y": false,
	"quality": 2,          # index into the Settings component's QUALITY_OPTIONS
	"fullscreen": false,
	"resolution": 0,       # index into RESOLUTION_OPTIONS
	"master_volume": 0.8,
	"ambience_volume": 0.7,
	"mower_volume": 0.8,
}

## 3D render scale per quality index. The one graphics control this project can
## apply honestly without touching the renderer setup.
const QUALITY_RENDER_SCALE: PackedFloat32Array = [0.6, 0.8, 1.0, 1.0]

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
]

var _values: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = DEFAULTS.duplicate()
	apply(_values)


# ===================================================================== values

func values() -> Dictionary:
	return _values.duplicate()


func get_value(key: String, fallback: Variant = null) -> Variant:
	return _values.get(key, fallback if fallback != null else DEFAULTS.get(key))


## Store and apply a single value. Called live as the player drags a slider.
func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	_values[key] = value
	_apply_one(key, value)
	changed.emit(key, value)


## Store and apply a whole dictionary. Unknown keys are ignored, so the
## component's `values()` output can be passed straight in.
func apply(new_values: Dictionary) -> void:
	for key: String in DEFAULTS:
		if new_values.has(key):
			_values[key] = new_values[key]
	for key: String in DEFAULTS:
		_apply_one(key, _values[key])
	applied.emit(values())


# =================================================================== applying

func _apply_one(key: String, value: Variant) -> void:
	match key:
		"master_volume":
			_set_bus_volume(ACAAudioMix.MASTER, float(value))
		"ambience_volume":
			# ONE setting drives both environment buses. There is no separate
			# Weather slider because there is no case for turning the rain down
			# but not the birds; Weather simply follows Ambience.
			_set_bus_volume(ACAAudioMix.AMBIENCE, float(value))
			_set_bus_volume(ACAAudioMix.WEATHER, float(value))
		"mower_volume":
			_set_bus_volume(ACAAudioMix.MOWER, float(value))
		"fullscreen":
			_set_fullscreen(bool(value))
		"resolution":
			_set_resolution(int(value))
		"quality":
			_set_quality(int(value))
		"mouse_sensitivity", "invert_look_y":
			# Both are read by the mower controllers on demand, through
			# mouse_sensitivity_scale() and invert_look_y(). Nothing to push.
			pass


## Mouse look multiplier for the mower controllers. 1.0 is the authored feel.
## The quality index as a NAME, for systems that reason about quality levels
## rather than about render scale. The environment adapter maps these on to its
## own profile set (`ACAWeatherVisualAdapter.QUALITY_FOR_SETTING`).
##
## Index order matches the Settings component's QUALITY_OPTIONS and
## QUALITY_RENDER_SCALE above.
const QUALITY_NAMES: PackedStringArray = ["low", "medium", "high", "ultra"]


func graphics_quality() -> String:
	var i := clampi(int(get_value("quality", 2)), 0, QUALITY_NAMES.size() - 1)
	return QUALITY_NAMES[i]


func mouse_sensitivity_scale() -> float:
	return clampf(float(_values.get("mouse_sensitivity", 1.0)), 0.1, 3.0)


## Vertical look inversion. OFF by default: mouse up looks up. Read by every
## mower controller; the convention is never hard-coded in a controller.
func invert_look_y() -> bool:
	return bool(_values.get("invert_look_y", false))


## The mix itself - which buses exist and how they are balanced against each
## other - belongs to `ACAAudioMix`, not to the settings screen. This only
## carries the player's number across.
func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	# A missing bus is not an error: the value stays stored and applies if the
	# bus is ever added. Every bus this project expects is in
	# res://default_bus_layout.tres.
	ACAAudioMix.apply_volume(bus_name, linear)


func _set_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if enabled
		else DisplayServer.WINDOW_MODE_WINDOWED)


func _set_resolution(index: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Resizing a fullscreen window does nothing useful; leave it alone.
	if bool(_values.get("fullscreen", false)):
		return
	var i := clampi(index, 0, RESOLUTIONS.size() - 1)
	DisplayServer.window_set_size(RESOLUTIONS[i])


func _set_quality(index: int) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var i := clampi(index, 0, QUALITY_RENDER_SCALE.size() - 1)
	tree.root.scaling_3d_scale = QUALITY_RENDER_SCALE[i]


# ================================================================ persistence

func to_save_dict() -> Dictionary:
	return values()


func from_save_dict(data: Dictionary) -> void:
	apply(data)
