class_name ACATrailerWeatherAdapter
extends Node
## DEVELOPMENT / MEDIA TOOLING. Pushes the real weather system further than the
## game ships it, for the length of one shot, and puts it back.
##
## ---------------------------------------------------------------------------
## WHAT IT DOES NOT DO
## ---------------------------------------------------------------------------
## It does not replace the weather system, and it does not touch
## `res://addons/sky_3d/`. The look on screen is still composed by
## `ACAWeatherVisualAdapter` from the shipped TIME_PROFILES and WEATHER_LAYERS.
## This installs ONE extra layer on top through that adapter's own
## `set_presentation_override()`, and restores the rain emitters it turned up.
##
## ---------------------------------------------------------------------------
## THE STORM BIAS, AND WHY IT IS A TRAILER DECISION
## ---------------------------------------------------------------------------
## The shipped composition rule SCALES the time profile rather than replacing
## it, so "evening rain" keeps the evening's golden hue, multiplied down. That
## rule is right for the game -- it is what stops the weather from flattening
## every hour into the same grey -- and it is why the storm reads warm (R-020).
##
## For ONE trailer shot the opposite is wanted: a blue-grey storm. So the
## override drives the warm keys down further and SETS the tints cool outright.
## The game's own balance is untouched, and `clear()` removes the layer.

## The blue-grey storm. `scale` multiplies whatever the shipped Rain layer
## produced; `set` replaces it. Judge this from frames, not from the numbers.
const STORM_OVERRIDE := {
	"scale": {
		# Keep the frame READABLE. A storm that swallows the mower is not a hero
		# shot -- the first cut of this look read as NIGHT, with the mower lost
		# in it -- so ambient and exposure go UP as the tint goes cold. Cold and
		# dark is a different picture from cold and moody, and only one of them
		# is usable.
		"sky:ambient_energy": 1.45,
		"sky:camera_exposure": 1.30,
		"sky:tonemap_exposure": 1.18,
		"sky:skydome_energy": 1.10,
		"sky:night_ambient_min": 0.80,
	},
	"set": {
		# THE COLOUR HAS TO BE `set`, NOT `scale`.
		#
		# `scale` multiplies every channel of a Color by the same factor, so it
		# can only make a tint DARKER - it cannot make it bluer. The shipped
		# Rain layer already scales these as far as scaling can take them
		# (R-020), and the result is still a dim warm sky. Replacing them
		# outright is the only thing that produces blue-grey, and it is
		# precisely the shipped composition rule this override exists to break
		# for one shot.
		"dome:atm_day_tint": Color(0.50, 0.57, 0.68),
		"dome:atm_horizon_light_tint": Color(0.52, 0.60, 0.72),
		"dome:sun_horizon_light_color": Color(0.66, 0.72, 0.84),
		"dome:clouds_cumulus_horizon_light_color": Color(0.50, 0.57, 0.70),
		# Cool, heavy, and with enough contrast between core and edge that the
		# deck reads as layered cloud rather than as one grey sheet.
		"dome:atm_night_tint": Color(0.24, 0.30, 0.42),
		"dome:sun_light_color": Color(0.72, 0.79, 0.92),
		"dome:clouds_cumulus_day_color": Color(0.62, 0.68, 0.79),
		"dome:clouds_cumulus_night_color": Color(0.20, 0.24, 0.33),
		"dome:clouds_coverage": 0.84,
		"dome:clouds_absorption": 3.2,
		"dome:clouds_intensity": 3.2,
		"dome:clouds_speed": 0.180,
		"dome:clouds_cumulus_coverage": 0.68,
		"dome:clouds_cumulus_absorption": 4.6,
		"dome:clouds_cumulus_thickness": 0.052,
		"dome:clouds_cumulus_intensity": 0.40,
		"dome:clouds_cumulus_mie_intensity": 0.28,
		"dome:clouds_cumulus_speed": 0.150,
		# Sky3D samples the cumulus noise at `point * size * 0.0212`. Lower is
		# BIGGER cloud masses; the shipped Rain value is 2.0, and a hero shot
		# wants fewer, larger, more dramatic forms.
		"dome:clouds_cumulus_size": 1.5,
		"dome:atm_thickness": 0.94,
	},
}

## Rain has to be unmistakable on compressed video. These are emitter ratios,
## not new particle systems.
const STORM_NEAR_RATIO := 1.0
const STORM_FAR_RATIO := 1.0
## The Near Rain emitter is authored at scale 3. Bigger streaks over a wider
## column, so the rain crosses the frame instead of hiding behind the mower.
const STORM_NEAR_SCALE := 4.6

var _preset_manager: Node = null
var _visual: ACAWeatherVisualAdapter = null
var _rain: Rain_Handler = null

var _applied: bool = false
var _saved_near_ratio: float = 1.0
var _saved_far_ratio: float = 0.6
var _saved_near_scale: Vector3 = Vector3.ONE
var _saved_rain_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(preset_manager_node: Node) -> void:
	clear()
	_preset_manager = preset_manager_node
	if _preset_manager == null:
		return
	_visual = _preset_manager.get(&"visual") as ACAWeatherVisualAdapter
	_rain = _preset_manager.get(&"rain_handler") as Rain_Handler


func is_bound() -> bool:
	return _visual != null and is_instance_valid(_visual)


## Install the storm look. The caller is expected to have already asked
## `WorldClock` for Rain -- this only exaggerates what the real system produces.
func apply_storm() -> void:
	if not is_bound() or _applied:
		return
	_visual.set_presentation_override(STORM_OVERRIDE)
	if _rain != null and is_instance_valid(_rain):
		_saved_near_ratio = _rain.near_rain_max_ratio
		_saved_far_ratio = _rain.far_rain_max_ratio
		_saved_rain_offset = _rain.rain_offset
		_rain.near_rain_max_ratio = STORM_NEAR_RATIO
		_rain.far_rain_max_ratio = STORM_FAR_RATIO
		var near := _rain.get_node_or_null(^"Near Rain") as GPUParticles3D
		if near != null:
			_saved_near_scale = near.scale
			near.scale = Vector3.ONE * STORM_NEAR_SCALE
	_applied = true


## Put every value back. Safe to call when nothing was applied.
func clear() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.clear_presentation_override()
	if _applied and _rain != null and is_instance_valid(_rain):
		_rain.near_rain_max_ratio = _saved_near_ratio
		_rain.far_rain_max_ratio = _saved_far_ratio
		_rain.rain_offset = _saved_rain_offset
		var near := _rain.get_node_or_null(^"Near Rain") as GPUParticles3D
		if near != null:
			near.scale = _saved_near_scale
	_applied = false


func is_applied() -> bool:
	return _applied


## NOTE on where the rain IS: `MVP._physics_process` hands the mower's position
## to the rain handler every physics tick, so the rain column follows the mower
## and nothing here needs to move it. What a parked camera fifty units away
## needs instead is a WIDER column, which is what STORM_NEAR_SCALE buys.


## What the sky is ACTUALLY doing, for the run log. Printed rather than assumed:
## the first version of this shot appeared to have no clouds, and the question
## was whether the adapter had not composed them or the camera was not pointing
## at any sky. It was the camera.
func describe() -> String:
	if _preset_manager == null:
		return "no preset manager"
	var dome = _preset_manager.get(&"skydome")
	if dome == null:
		return "no skydome"
	return "weather=%s hour=%.2f coverage=%.2f cumulus=%.2f size=%.1f raining=%s override=%s" % [
		_preset_manager.current_weather_preset,
		_preset_manager.current_time_of_day,
		float(dome.get(&"clouds_coverage")),
		float(dome.get(&"clouds_cumulus_coverage")),
		float(dome.get(&"clouds_cumulus_size")),
		str(_rain.is_raining) if _rain != null else "?",
		str(_applied),
	]
