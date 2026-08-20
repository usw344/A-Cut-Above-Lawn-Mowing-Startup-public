class_name ACAEnvComposer
extends RefCounted
## PURE COMPOSITION. No nodes, no scene, no Sky3D.
##
## Given a set of profiles, an hour and a weather id, produce the complete
## composed key dictionary. That is all it does, and because it needs nothing
## running it can be unit-tested, diffed and printed without a renderer.
##
##     time profiles + anchors --> the hour's look
##                                      |
##                            weather: multiply, bias, set
##                                      |
##                            presentation override (optional)
##                                      |
##                                 clamp + derive
##                                      |
##                              composed key dictionary
##
## The output key space is documented in `env_keys.gd`.

## `[hour, profile_id]`, sorted. Between two anchors the two profiles are
## smoothstep-blended, so these are the only times of day that exist and every
## other hour is a mixture.
var anchors: Array = []

var _time: Dictionary = {}      ## id -> ACAEnvTimeProfile
var _weather: Dictionary = {}   ## id -> ACAEnvWeatherProfile
var _override: Dictionary = {}


func add_time_profile(profile: ACAEnvTimeProfile) -> void:
	if profile != null:
		_time[String(profile.id)] = profile


func add_weather_profile(profile: ACAEnvWeatherProfile) -> void:
	if profile != null:
		_weather[String(profile.id)] = profile


func time_profile_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _time:
		out.append(k)
	out.sort()
	return out


func weather_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _weather:
		out.append(k)
	out.sort()
	return out


func has_weather(id: String) -> bool:
	return _weather.has(id)


func time_profile(id: String) -> ACAEnvTimeProfile:
	return _time.get(id, null)


func weather_profile(id: String) -> ACAEnvWeatherProfile:
	return _weather.get(id, null)


func is_ready() -> bool:
	return not _time.is_empty() and not _weather.is_empty() and anchors.size() >= 2


# ------------------------------------------------------- presentation override
#
# One extra layer in the same `{"scale": {...}, "set": {...}}` shape, composed
# LAST. This exists for media tooling: a capture may want a look the shipped
# profiles deliberately do not ship, without editing the profiles. It is empty
# in normal use.

func set_override(layer: Dictionary) -> void:
	_override = layer.duplicate(true) if layer != null and not layer.is_empty() else {}


func override() -> Dictionary:
	return _override


func has_override() -> bool:
	return not _override.is_empty()


# ================================================================== composition

## THE composed look for this combination.
func compose(weather_id: String, hour: float) -> Dictionary:
	var values := time_values(hour)
	var profile: ACAEnvWeatherProfile = _weather.get(weather_id, null)
	if profile == null and not _weather.is_empty():
		profile = _weather.values()[0]
	if profile == null:
		return values

	# 1. MULTIPLY. Energies and exposures compose correctly at any hour.
	var scale := profile.to_scale_values()
	for key: String in scale:
		if values.has(key):
			values[key] = _scaled(values[key], float(scale[key]))

	# 2. BIAS. `lerp` towards a target, so a colour can be pulled COOLER and not
	#    only darker. This is the operation the single-rule version lacked.
	for entry: Array in profile.to_bias_values():
		var key: String = entry[0]
		var weight: float = float(entry[2])
		if weight <= 0.0 or not values.has(key):
			continue
		var from: Variant = values[key]
		if from is Color:
			values[key] = (from as Color).lerp(entry[1], clampf(weight, 0.0, 1.0))

	# 3. SET. Things the weather owns outright.
	var absolute := profile.to_set_values()
	for key: String in absolute:
		values[key] = absolute[key]

	# 4. The override, last, so tooling can bias a decision the profiles made.
	if not _override.is_empty():
		var over_scale: Dictionary = _override.get("scale", {})
		for key: String in over_scale:
			if values.has(key):
				values[key] = _scaled(values[key], float(over_scale[key]))
		var over_set: Dictionary = _override.get("set", {})
		for key: String in over_set:
			values[key] = over_set[key]

	_derive(values)

	for key: String in ACAEnvKeys.CLAMPED_01:
		if values.has(key) and (values[key] is float or values[key] is int):
			values[key] = clampf(float(values[key]), 0.0, 1.0)
	return values


## The time-of-day look with no weather on it.
func time_values(hour: float) -> Dictionary:
	var blend := anchor_blend(hour)
	var a: ACAEnvTimeProfile = _time.get(String(blend[0]), null)
	var b: ACAEnvTimeProfile = _time.get(String(blend[1]), null)
	if a == null:
		return {}
	if b == null:
		b = a
	var va := a.to_values()
	var vb := b.to_values()
	var t: float = smoothstep(0.0, 1.0, float(blend[2]))

	var out := {}
	for key: String in va:
		out[key] = lerp_value(va[key], vb.get(key, va[key]), t)
	return out


## -> `[profile_a, profile_b, t]`
func anchor_blend(hour: float) -> Array:
	var h := clampf(hour, 0.0, 23.999)
	for i in range(anchors.size() - 1):
		var start: float = anchors[i][0]
		var end: float = anchors[i + 1][0]
		if h >= start and h <= end:
			var span := maxf(end - start, 0.0001)
			return [anchors[i][1], anchors[i + 1][1], (h - start) / span]
	if anchors.is_empty():
		return ["", "", 0.0]
	return [anchors[0][1], anchors[0][1], 0.0]


## The dominant profile name at `hour`.
func profile_at(hour: float) -> String:
	var blend := anchor_blend(hour)
	return String(blend[0]) if float(blend[2]) < 0.5 else String(blend[1])


# ==================================================================== derived
#
# Values nobody authors, because they are a CONSEQUENCE of the composed look.

func _derive(values: Dictionary) -> void:
	# THE DEPTH FOG TAKES ITS COLOUR FROM THE SKY IT IS STANDING IN.
	#
	# This is the whole reason a fogged evening is warm and a fogged night is
	# blue without either being authored twice. The profile's `fog_tint` is the
	# base; the composed atmosphere tints are mixed into it, so the fog follows
	# every change made to the sky above it — including the weather's own colour
	# bias, because this runs AFTER the bias step.
	if values.has("env:fog_light_color"):
		var base: Color = values["env:fog_light_color"]
		var day: Color = values.get("dome:atm_day_tint", base)
		var horizon: Color = values.get("dome:atm_horizon_light_tint", base)
		# Weighted towards the day tint: the horizon band is a narrow part of
		# the sky, and letting it dominate is what makes an orange fog.
		var sky_mix: Color = day.lerp(horizon, 0.28)
		values["env:fog_light_color"] = base.lerp(sky_mix, 0.55)

	# Volumetric and grading are only ever ON because something asked for them.
	values["env:volumetric_fog_enabled"] = float(
		values.get("env:volumetric_fog_density", 0.0)) > 0.0001
	var sat: float = float(values.get("env:adjustment_saturation", 1.0))
	var con: float = float(values.get("env:adjustment_contrast", 1.0))
	values["env:adjustment_enabled"] = (
		absf(sat - 1.0) > 0.002 or absf(con - 1.0) > 0.002)
	values["env:adjustment_brightness"] = 1.0


# ===================================================================== helpers

func _scaled(value: Variant, factor: float) -> Variant:
	if value is Color:
		var c: Color = value
		return Color(c.r * factor, c.g * factor, c.b * factor, c.a)
	if value is float or value is int:
		return float(value) * factor
	return value


## Interpolates anything the key space can hold. Discrete values step.
static func lerp_value(from: Variant, to: Variant, t: float) -> Variant:
	if from is Color and to is Color:
		return (from as Color).lerp(to, t)
	if to is bool:
		return to
	if (from is float or from is int) and (to is float or to is int):
		return lerpf(float(from), float(to), t)
	return to
