class_name ACAWeatherVisualAdapter
extends Node
## PROJECT-OWNED presentation layer over Sky3D. Nothing under `res://addons/`
## is modified, or may be; this reads its public properties and writes them.
##
##     WorldClock  (authoritative time + weather STATE)
##          |
##     preset_manager  (the project-facing weather API scenes already call)
##          |
##     ACAWeatherVisualAdapter   <- you are here
##          |
##     Sky3D / Skydome public properties
##
## ---------------------------------------------------------------------------
## HOW A LOOK IS BUILT
## ---------------------------------------------------------------------------
##
## A look is a TIME profile composed with a WEATHER layer. There are only four
## time profiles (Night / Morning / Day / Evening) and three weather layers
## (Clear / Foggy / Rain) - twelve combinations from seven small tables, not
## twelve hand-written presets.
##
##   1. TIME: the hour picks a point on TIME_ANCHORS and the two neighbouring
##      profiles are blended, so 07:00 -> 10:00 is a gradual sunrise rather than
##      a step.
##   2. WEATHER, in two parts:
##        `scale` MULTIPLIES the time value  -> evening rain is still evening
##        `set`   REPLACES it outright       -> clouds and fog are weather's job
##      Scale is applied first, then set.
##
## That composition rule is the whole design. "Rain + Evening" keeps the golden
## sun tint and warm cloud colour and multiplies them down, rather than throwing
## the evening away and pasting a grey storm over it.
##
## ---------------------------------------------------------------------------
## NO TWEENS
## ---------------------------------------------------------------------------
##
## Every property is driven by ONE per-tick exponential approach towards the
## composed target. There is deliberately no Tween anywhere in this file:
##
##   * time drifts continuously, so a fixed-duration tween would be restarted
##     forever and never finish;
##   * two overlapping weather changes cannot leave a stale tween writing old
##     values, because there is nothing to leave behind;
##   * convergence is guaranteed from any state, including a mid-transition
##     save/load.
##
## `apply_immediate()` snaps instead, for scene load and save restore.
##
## ---------------------------------------------------------------------------
## STEP KEYS
## ---------------------------------------------------------------------------
##
## `Sky3D.set_ambient_energy` / `set_sky_contribution` / `set_night_ambient_min`
## each start their OWN internal Tween on the Environment. Driving them 60 times
## a second would spawn 60 tweens a second. They are applied with a deadband
## instead - written only when the target has actually moved.

# ------------------------------------------------------------------- keys
##  "sky:<property>"  -> the Sky3D WorldEnvironment node
##  "dome:<property>" -> its Skydome child
const SKY_PREFIX := "sky:"
const DOME_PREFIX := "dome:"

## Properties whose setters spawn an internal tween. Written on change only.
const STEP_KEYS: PackedStringArray = [
	"sky:ambient_energy", "sky:sky_contribution", "sky:night_ambient_min",
]
const STEP_DEADBAND := 0.03

## Properties Sky3D range-limits. Composition can multiply past the limit.
const CLAMPED_01: PackedStringArray = [
	"sky:sky_contribution", "sky:night_ambient_min",
	"dome:atm_darkness", "dome:clouds_coverage", "dome:clouds_cumulus_coverage",
	"dome:clouds_sky_tint_fade", "sky:sun_shadow_opacity",
]

# =========================================================== TIME PROFILES
#
# A cozy low-poly game. Readable beats dramatic: nothing here is allowed to
# reach black, and nothing is allowed to blow out. Every profile carries the
# SAME key set so blending between any two is total.

const TIME_PROFILES := {
	"Night": {
		# Night is lifted deliberately. `night_ambient_min` is the important one:
		# Sky3D lowers ambient_light_sky_contribution to it after dark, and a
		# LOWER value means more neutral fill light, i.e. a readable night.
		"sky:camera_exposure": 1.30,
		"sky:tonemap_exposure": 1.10,
		"sky:skydome_energy": 1.00,
		"sky:moon_energy": 0.85,
		"sky:ambient_energy": 1.25,
		"sky:sky_contribution": 0.95,
		"sky:night_ambient_min": 0.42,
		"dome:atm_darkness": 0.30,
		"dome:atm_sun_intensity": 14.0,
		"dome:atm_day_tint": Color(0.55, 0.66, 0.85),
		"dome:atm_horizon_light_tint": Color(0.42, 0.52, 0.72),
		"dome:atm_night_tint": Color(0.22, 0.28, 0.40),
		"dome:atm_mie": 0.070,
		"dome:ground_color": Color(0.055, 0.065, 0.085),
		"dome:sun_light_color": Color(0.75, 0.82, 1.00),
		"dome:sun_horizon_light_color": Color(0.60, 0.60, 0.80),
		"dome:moon_light_color": Color(0.62, 0.76, 0.98),
		"dome:sun_disk_intensity": 22.0,
		"dome:fog_density": 0.0011,
		"dome:fog_start": 0.0,
		"dome:fog_end": 780.0,
		"dome:fog_rayleigh_depth": 0.130,
		"dome:fog_mie_depth": 0.00016,
		"dome:fog_falloff": 2.6,
		"dome:clouds_cumulus_day_color": Color(0.42, 0.48, 0.60),
		"dome:clouds_cumulus_horizon_light_color": Color(0.34, 0.40, 0.55),
		"dome:clouds_cumulus_night_color": Color(0.17, 0.20, 0.28),
	},
	"Morning": {
		# Not "day but darker": cooler sky, warm low sun, and a little haze that
		# day does not have.
		"sky:camera_exposure": 1.06,
		"sky:tonemap_exposure": 1.02,
		"sky:skydome_energy": 1.00,
		"sky:moon_energy": 0.35,
		"sky:ambient_energy": 1.05,
		"sky:sky_contribution": 0.95,
		"sky:night_ambient_min": 0.60,
		"dome:atm_darkness": 0.40,
		"dome:atm_sun_intensity": 16.0,
		"dome:atm_day_tint": Color(0.84, 0.90, 1.00),
		"dome:atm_horizon_light_tint": Color(1.00, 0.72, 0.50),
		"dome:atm_night_tint": Color(0.22, 0.28, 0.40),
		"dome:atm_mie": 0.085,
		"dome:ground_color": Color(0.16, 0.17, 0.16),
		"dome:sun_light_color": Color(1.00, 0.94, 0.86),
		"dome:sun_horizon_light_color": Color(1.00, 0.72, 0.48),
		"dome:moon_light_color": Color(0.62, 0.76, 0.98),
		"dome:sun_disk_intensity": 30.0,
		"dome:fog_density": 0.0019,
		"dome:fog_start": 0.0,
		"dome:fog_end": 560.0,
		"dome:fog_rayleigh_depth": 0.140,
		"dome:fog_mie_depth": 0.00030,
		"dome:fog_falloff": 2.4,
		"dome:clouds_cumulus_day_color": Color(0.95, 0.95, 1.00),
		"dome:clouds_cumulus_horizon_light_color": Color(1.00, 0.63, 0.38),
		"dome:clouds_cumulus_night_color": Color(0.17, 0.20, 0.28),
	},
	"Day": {
		# The reference look. Bright, clean, good contrast on the foliage.
		"sky:camera_exposure": 1.00,
		"sky:tonemap_exposure": 1.00,
		"sky:skydome_energy": 1.00,
		"sky:moon_energy": 0.30,
		"sky:ambient_energy": 1.00,
		"sky:sky_contribution": 1.00,
		"sky:night_ambient_min": 0.70,
		"dome:atm_darkness": 0.48,
		"dome:atm_sun_intensity": 18.0,
		"dome:atm_day_tint": Color(0.81, 0.91, 1.00),
		"dome:atm_horizon_light_tint": Color(0.98, 0.68, 0.50),
		"dome:atm_night_tint": Color(0.22, 0.28, 0.40),
		"dome:atm_mie": 0.070,
		"dome:ground_color": Color(0.24, 0.25, 0.23),
		"dome:sun_light_color": Color(1.00, 0.98, 0.94),
		"dome:sun_horizon_light_color": Color(0.98, 0.60, 0.36),
		"dome:moon_light_color": Color(0.62, 0.76, 0.98),
		"dome:sun_disk_intensity": 30.0,
		"dome:fog_density": 0.00075,
		"dome:fog_start": 0.0,
		"dome:fog_end": 1100.0,
		"dome:fog_rayleigh_depth": 0.115,
		"dome:fog_mie_depth": 0.00012,
		"dome:fog_falloff": 3.0,
		"dome:clouds_cumulus_day_color": Color(0.86, 0.90, 1.00),
		"dome:clouds_cumulus_horizon_light_color": Color(0.98, 0.55, 0.28),
		"dome:clouds_cumulus_night_color": Color(0.17, 0.20, 0.28),
	},
	"Evening": {
		# The screenshot profile. `sun_horizon_light_color` is what actually
		# puts golden light on the mower, not the sky tint.
		"sky:camera_exposure": 1.12,
		"sky:tonemap_exposure": 1.02,
		"sky:skydome_energy": 1.05,
		"sky:moon_energy": 0.40,
		"sky:ambient_energy": 1.20,
		"sky:sky_contribution": 0.95,
		"sky:night_ambient_min": 0.50,
		"dome:atm_darkness": 0.40,
		"dome:atm_sun_intensity": 17.0,
		"dome:atm_day_tint": Color(0.96, 0.86, 0.80),
		"dome:atm_horizon_light_tint": Color(1.00, 0.64, 0.44),
		"dome:atm_night_tint": Color(0.22, 0.28, 0.40),
		"dome:atm_mie": 0.085,
		"dome:ground_color": Color(0.22, 0.20, 0.18),
		"dome:sun_light_color": Color(1.00, 0.86, 0.68),
		"dome:sun_horizon_light_color": Color(1.00, 0.74, 0.52),
		"dome:moon_light_color": Color(0.62, 0.76, 0.98),
		"dome:sun_disk_intensity": 34.0,
		"dome:fog_density": 0.0016,
		"dome:fog_start": 0.0,
		"dome:fog_end": 680.0,
		"dome:fog_rayleigh_depth": 0.135,
		"dome:fog_mie_depth": 0.00028,
		"dome:fog_falloff": 2.4,
		"dome:clouds_cumulus_day_color": Color(1.00, 0.90, 0.82),
		"dome:clouds_cumulus_horizon_light_color": Color(1.00, 0.60, 0.36),
		"dome:clouds_cumulus_night_color": Color(0.17, 0.20, 0.28),
	},
}

## Hour -> profile. Between two anchors the profiles are smoothstep-blended, so
## these are the only "times of day" that exist and everything else is a mix.
##
## MEASURED, not guessed. `Dev tools/Validation/Sun Probe.tscn` prints Sky3D's
## sun altitude per half hour for THIS Skydome configuration (realistic mode,
## latitude 16): the sun is up from about **06:35 to 17:05**, highest at 12:00.
## Anchors outside that window put "Evening" after dark - the first attempt used
## 18.4 and rendered a black screen with stars.
##
## If the Skydome's latitude/date/celestial mode ever change, re-run the probe
## and move these.
const TIME_ANCHORS := [
	[0.0, "Night"], [4.8, "Night"], [7.0, "Morning"], [9.8, "Day"],
	[14.2, "Day"], [16.3, "Evening"], [18.2, "Night"], [24.0, "Night"],
]

# ========================================================== WEATHER LAYERS
#
# `scale` multiplies the composed time value; `set` replaces it. A key must
# never appear in both for the same weather.

const WEATHER_LAYERS := {
	"Clear": {
		"scale": {},
		"set": {
			"sky:cloud_intensity": 0.62,
			"sky:sun_energy": 1.05,
			"sky:sun_shadow_opacity": 0.92,
			"dome:atm_turbidity": 0.0010,
			"dome:atm_thickness": 0.70,
			"dome:clouds_visible": true,
			"dome:clouds_coverage": 0.42,
			"dome:clouds_absorption": 2.0,
			"dome:clouds_sky_tint_fade": 0.45,
			"dome:clouds_intensity": 10.0,
			"dome:clouds_speed": 0.055,
			"dome:clouds_cumulus_visible": true,
			"dome:clouds_cumulus_coverage": 0.44,
			"dome:clouds_cumulus_absorption": 1.9,
			"dome:clouds_cumulus_thickness": 0.026,
			"dome:clouds_cumulus_noise_freq": 2.7,
			"dome:clouds_cumulus_intensity": 0.62,
			"dome:clouds_cumulus_mie_intensity": 1.00,
			"dome:clouds_cumulus_speed": 0.045,
			# CLOUD SCALE. See the note on this key in the Rain layer - it is
			# the difference between clouds and a featureless wash. Measured
			# with Sky Probe: scattered fair-weather cumulus.
			"dome:clouds_cumulus_size": 5.0,
		},
	},
	"Foggy": {
		# Atmospheric depth, NOT a white wall: `fog_start` keeps the near field
		# clear so the mower and the lawn in front of it stay readable, and the
		# exposure goes UP rather than down.
		"scale": {
			"sky:camera_exposure": 1.04,
			"sky:skydome_energy": 0.96,
			"sky:ambient_energy": 1.14,
			"sky:moon_energy": 1.10,
			"dome:atm_darkness": 1.15,
			"dome:sun_light_color": 0.92,
			"dome:clouds_cumulus_day_color": 0.94,
		},
		"set": {
			"sky:cloud_intensity": 0.52,
			"sky:sun_energy": 0.72,
			"sky:sun_shadow_opacity": 0.38,
			"dome:atm_turbidity": 0.0026,
			"dome:atm_thickness": 0.90,
			"dome:clouds_visible": true,
			"dome:clouds_coverage": 0.62,
			"dome:clouds_absorption": 2.3,
			"dome:clouds_sky_tint_fade": 0.68,
			"dome:clouds_intensity": 6.0,
			"dome:clouds_speed": 0.050,
			"dome:clouds_cumulus_visible": true,
			"dome:clouds_cumulus_coverage": 0.70,
			"dome:clouds_cumulus_absorption": 2.3,
			"dome:clouds_cumulus_thickness": 0.034,
			"dome:clouds_cumulus_noise_freq": 2.5,
			"dome:clouds_cumulus_intensity": 0.52,
			"dome:clouds_cumulus_mie_intensity": 0.85,
			"dome:clouds_cumulus_speed": 0.040,
			# Tighter than Clear: a dense mackerel overcast. Measured with Sky
			# Probe.
			"dome:clouds_cumulus_size": 9.0,
			"dome:fog_density": 0.0042,
			"dome:fog_start": 14.0,
			"dome:fog_end": 240.0,
			"dome:fog_rayleigh_depth": 0.160,
			"dome:fog_mie_depth": 0.00065,
			"dome:fog_falloff": 1.9,
		},
	},
	"Rain": {
		# Moodier than Clear, but the mood comes from the CLOUDS and the sun
		# being blocked - not from crushing the exposure. Ambient goes up so the
		# mower is never lost in a dark frame, which is what the old preset did.
		"scale": {
			"sky:camera_exposure": 1.02,
			"sky:skydome_energy": 0.82,
			"sky:ambient_energy": 1.22,
			"sky:moon_energy": 1.35,
			"sky:night_ambient_min": 0.85,
			"dome:atm_darkness": 1.18,
			# Greyer than the old 0.80 / 0.85. With the clouds now actually
			# rendering, a late-afternoon storm was still reading as a warm
			# sunset haze; these pull the warmth out of the scattering without
			# replacing the evening hue outright (the RULE - see the header).
			"dome:atm_day_tint": 0.66,
			"dome:atm_horizon_light_tint": 0.72,
			"dome:sun_light_color": 0.80,
			"dome:sun_horizon_light_color": 0.85,
			"dome:clouds_cumulus_day_color": 0.72,
			"dome:clouds_cumulus_horizon_light_color": 0.80,
		},
		"set": {
			"sky:cloud_intensity": 0.34,
			"sky:sun_energy": 0.46,
			"sky:sun_shadow_opacity": 0.22,
			"dome:atm_turbidity": 0.0034,
			"dome:atm_thickness": 0.85,
			# STORM CLOUDS HAVE TO HAVE SHAPE.
			#
			# Fixed 2026-08-19 (Milestone 10). The old values asked for
			# near-total cover (`clouds_cumulus_coverage` 0.90) with a high sky
			# tint fade, which in Sky3D's shader is an OPAQUE, GAPLESS sheet
			# tinted towards the sky colour. Rendered, that is not a storm - it
			# is a smooth haze gradient with no cloud in it at all, which is
			# why "evening rain" appeared to have no clouds. Coverage is now
			# broken up, the noise carries more detail, the cores are darker
			# and less of the sun's mie glow is allowed through.
			#
			# Judge this from `Weather Matrix.tscn`, not from the numbers.
			"dome:clouds_visible": true,
			"dome:clouds_coverage": 0.78,
			"dome:clouds_absorption": 2.7,
			"dome:clouds_sky_tint_fade": 0.55,
			"dome:clouds_intensity": 4.0,
			"dome:clouds_speed": 0.130,
			"dome:clouds_cumulus_visible": true,
			"dome:clouds_cumulus_coverage": 0.62,
			"dome:clouds_cumulus_absorption": 4.0,
			"dome:clouds_cumulus_thickness": 0.046,
			"dome:clouds_cumulus_noise_freq": 2.8,
			"dome:clouds_cumulus_intensity": 0.45,
			"dome:clouds_cumulus_mie_intensity": 0.35,
			"dome:clouds_cumulus_speed": 0.100,
			# CLOUD SCALE - THE key nobody was setting, and the actual reason
			# "evening rain" appeared to have no clouds.
			#
			# Sky3D samples its cumulus noise at
			# `intersection_point * clouds_cumulus_size * 0.0212`, and at the
			# shipped default of 0.5 the dominant octave barely changes across
			# the whole dome: the layer renders as a smooth, featureless wash
			# that reads as haze. Low values give BIG shapes, high values give
			# fine stipple. 2.0 is broken storm masses with gaps of sky.
			#
			# Measured, not guessed: `Dev tools/Validation/Sky Probe.tscn`
			# renders the sky alone across a sweep of this value.
			"dome:clouds_cumulus_size": 2.0,
			"dome:fog_density": 0.0027,
			"dome:fog_start": 8.0,
			"dome:fog_end": 400.0,
			"dome:fog_rayleigh_depth": 0.150,
			"dome:fog_mie_depth": 0.00050,
			"dome:fog_falloff": 1.9,
		},
	},
}

# ------------------------------------------------------------------ tuning
## Exponential approach rate towards the composed target, per second. ~1.2
## settles a weather change in roughly two and a half seconds.
@export var blend_speed: float = 1.2
## Seconds between recomposition ticks. Sky3D updates itself at 0.1 s.
@export var update_interval: float = 0.05

# ------------------------------------------------------------------- state
var _sky: Node = null
var _dome: Node = null
var _weather: String = "Clear"
var _hour: float = 12.0
## What is on screen right now, blending towards _target.
var _current: Dictionary = {}
var _target: Dictionary = {}
var _accumulator: float = 0.0
var _enabled: bool = false


func _ready() -> void:
	set_process(true)


## Bind the addon nodes. Called by preset_manager; nothing else should.
func bind(sky_node: Node, dome_node: Node) -> void:
	_sky = sky_node
	_dome = dome_node
	_enabled = _sky != null and _dome != null


func is_bound() -> bool:
	return _enabled


# ================================================================== driving

## Set the state to present. Visuals ease towards it.
func set_state(weather: String, hour: float) -> void:
	_weather = weather if WEATHER_LAYERS.has(weather) else "Clear"
	_hour = clampf(hour, 0.0, 23.99)
	_target = compose(_weather, _hour)


## Set the state AND snap to it. For scene load and save restore, where easing
## in from whatever the previous scene looked like would be a visible glitch.
func apply_immediate(weather: String, hour: float) -> void:
	set_state(weather, hour)
	_current = _target.duplicate()
	_write(_current, true)


func current_weather() -> String:
	return _weather


func current_hour() -> float:
	return _hour


## The blended time profile name pair for `hour`, for tests and tooling.
func time_profile_at(hour: float) -> String:
	var blend := _anchor_blend(hour)
	return String(blend[0]) if blend[2] < 0.5 else String(blend[1])


# ---------------------------------------------- PRESENTATION OVERRIDE
#
# DEVELOPMENT / MEDIA TOOLING. One extra layer, composed ON TOP of the shipped
# look and in the same `scale` / `set` shape as WEATHER_LAYERS.
#
# `Trailer Capture` uses it to bias the storm blue-grey and thicken the cloud
# deck for camera. That is a PRESENTATION choice, not a balance change: the
# composition rule the game ships with deliberately SCALES the time profile so
# evening rain stays evening (R-020), and the trailer wants the opposite for one
# shot. Overriding here keeps that argument out of the shipped tables.
#
# It is EMPTY in normal gameplay, it eases in and out through the same per-tick
# approach as everything else, and `Trailer Test` asserts it is empty again
# after a capture.
var _override: Dictionary = {}


## Install the override layer. `{}` clears it. Recomposes immediately; the
## visuals ease across rather than snapping.
func set_presentation_override(layer: Dictionary) -> void:
	_override = layer.duplicate(true) if layer != null and not layer.is_empty() else {}
	_target = compose(_weather, _hour)


func clear_presentation_override() -> void:
	set_presentation_override({})


func presentation_override() -> Dictionary:
	return _override


func has_presentation_override() -> bool:
	return not _override.is_empty()


func _process(delta: float) -> void:
	if not _enabled:
		return
	_accumulator += delta
	if _accumulator < update_interval:
		return
	var step := _accumulator
	_accumulator = 0.0

	if _current.is_empty():
		_current = _target.duplicate()
		_write(_current, true)
		return

	var t := 1.0 - exp(-blend_speed * step)
	for key: String in _target:
		_current[key] = _lerp_value(_current.get(key, _target[key]), _target[key], t)
	_write(_current, false)


# ============================================================== composition

## The look for this combination. Public so tooling and tests can inspect a
## combination without a running scene.
func compose(weather: String, hour: float) -> Dictionary:
	var values := time_values(hour)
	var layer: Dictionary = WEATHER_LAYERS.get(weather, WEATHER_LAYERS["Clear"])

	var scale: Dictionary = layer["scale"]
	for key: String in scale:
		if values.has(key):
			values[key] = _scaled(values[key], float(scale[key]))

	var absolute: Dictionary = layer["set"]
	for key: String in absolute:
		values[key] = absolute[key]

	# The presentation override is LAST, so a trailer shot can bias a look the
	# shipped weather layer has already decided. Empty in normal gameplay.
	if not _override.is_empty():
		var over_scale: Dictionary = _override.get("scale", {})
		for key: String in over_scale:
			if values.has(key):
				values[key] = _scaled(values[key], float(over_scale[key]))
		var over_set: Dictionary = _override.get("set", {})
		for key: String in over_set:
			values[key] = over_set[key]

	for key: String in CLAMPED_01:
		if values.has(key) and values[key] is float:
			values[key] = clampf(values[key], 0.0, 1.0)
	return values


## The pure time-of-day look, with no weather applied.
func time_values(hour: float) -> Dictionary:
	var blend := _anchor_blend(hour)
	var a: Dictionary = TIME_PROFILES[blend[0]]
	var b: Dictionary = TIME_PROFILES[blend[1]]
	var t: float = smoothstep(0.0, 1.0, float(blend[2]))

	var out := {}
	for key: String in a:
		out[key] = _lerp_value(a[key], b.get(key, a[key]), t)
	return out


## -> [profile_a, profile_b, t]
func _anchor_blend(hour: float) -> Array:
	var h := clampf(hour, 0.0, 23.999)
	for i in range(TIME_ANCHORS.size() - 1):
		var start: float = TIME_ANCHORS[i][0]
		var end: float = TIME_ANCHORS[i + 1][0]
		if h >= start and h <= end:
			var span := maxf(end - start, 0.0001)
			return [TIME_ANCHORS[i][1], TIME_ANCHORS[i + 1][1], (h - start) / span]
	return [TIME_ANCHORS[0][1], TIME_ANCHORS[0][1], 0.0]


func _scaled(value: Variant, factor: float) -> Variant:
	if value is Color:
		var c: Color = value
		return Color(c.r * factor, c.g * factor, c.b * factor, c.a)
	if value is float or value is int:
		return float(value) * factor
	return value


func _lerp_value(from: Variant, to: Variant, t: float) -> Variant:
	if from is Color and to is Color:
		return (from as Color).lerp(to, t)
	if to is bool:
		return to
	if (from is float or from is int) and (to is float or to is int):
		return lerpf(float(from), float(to), t)
	return to


# =================================================================== output

func _write(values: Dictionary, force: bool) -> void:
	for key: String in values:
		var value: Variant = values[key]
		var is_step := STEP_KEYS.has(key) or value is bool
		if is_step and not force and not _step_should_write(key, value):
			continue
		_write_one(key, value)


## Step keys go through setters that start their own Tween, so they are only
## written when the value has really moved.
func _step_should_write(key: String, value: Variant) -> bool:
	var node := _node_for(key)
	if node == null:
		return false
	var current: Variant = node.get(_property_for(key))
	if value is bool:
		return current != value
	if current is float or current is int:
		return absf(float(current) - float(value)) > STEP_DEADBAND
	return true


func _write_one(key: String, value: Variant) -> void:
	var node := _node_for(key)
	if node != null:
		node.set(_property_for(key), value)


func _node_for(key: String) -> Node:
	if key.begins_with(SKY_PREFIX):
		return _sky
	if key.begins_with(DOME_PREFIX):
		return _dome
	return null


func _property_for(key: String) -> StringName:
	return StringName(key.substr(key.find(":") + 1))
