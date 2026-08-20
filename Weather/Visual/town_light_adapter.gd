class_name ACATownLightAdapter
extends Node
## PROJECT-OWNED time/weather presentation for the Business Town.
##
## Closes review flag R-013: world time and weather were coherent as STATE
## everywhere, but only the mowing scene looked like it.
##
## WHAT IT DOES NOT DO, on purpose:
##   * it does not replace `BusinessTown.tscn` or edit it;
##   * it does not put Sky3D in the town - the town's `ProceduralSkyMaterial`,
##     SSAO, tonemap and colour grading are what give it its stylised look, and
##     they are left exactly as authored;
##   * it does not move geometry, add particles, or touch the camera rig.
##
## All it changes is LIGHT: the two directional lights' colour/energy, the
## procedural sky gradient, ambient energy, exposure and distance fog. Every
## resource it writes is DUPLICATED first, so the authored sub-resources in the
## scene file are never mutated.
##
## The DAY profile below is the town exactly as authored. Day therefore looks
## identical to how it looked before this adapter existed; the other three are
## departures from that reference.
##
## Bound and driven by `Game/App/town_screen.gd`. Set `enabled = false` there to
## put the town back to its authored lighting with no other change.

const SUN_YAW_KEY := "sun_yaw_degrees"

## Degrees the sun must actually turn before its basis is rewritten.
##
## MEASURED, in Milestone 15. `_write()` used to set `_sun.transform.basis` on
## every tick of its own 20 Hz `_process`, and the yaw it wrote came from an
## exponential approach that never reaches its target — so the town sun
## micro-rotated twenty times a second, forever, even with the world clock
## stopped. `Flicker Probe` measured the result: with a stationary camera and a
## STOPPED clock the frame-to-frame difference was 0.039, against 0.022 for a
## running clock with no shadows at all.
##
## The town's yaw sweeps about 122 degrees across a four-minute day, so a
## quarter-degree deadband steps roughly twice a second and is invisible in the
## shading while removing the churn entirely.
const SUN_YAW_DEADBAND_DEGREES := 0.25

## Time profiles. Small on purpose - a stylised town needs colour and intensity,
## not a simulation.
const TIME_PROFILES := {
	"Night": {
		"sun_color": Color(0.62, 0.72, 0.98),
		"sun_energy": 0.30,
		"sun_yaw_degrees": 80.0,
		"fill_color": Color(0.45, 0.55, 0.82),
		"fill_energy": 0.30,
		"sky_top_color": Color(0.055, 0.075, 0.165),
		"sky_horizon_color": Color(0.145, 0.185, 0.300),
		"ground_horizon_color": Color(0.150, 0.170, 0.235),
		"ground_bottom_color": Color(0.100, 0.115, 0.155),
		"ambient_energy": 1.55,
		"tonemap_exposure": 1.18,
		"fog_light_color": Color(0.16, 0.20, 0.32),
	},
	"Morning": {
		"sun_color": Color(1.00, 0.90, 0.78),
		"sun_energy": 1.20,
		"sun_yaw_degrees": -42.0,
		"fill_color": Color(0.72, 0.80, 0.95),
		"fill_energy": 0.36,
		"sky_top_color": Color(0.360, 0.540, 0.800),
		"sky_horizon_color": Color(0.950, 0.845, 0.760),
		"ground_horizon_color": Color(0.740, 0.760, 0.740),
		"ground_bottom_color": Color(0.430, 0.450, 0.430),
		"ambient_energy": 0.98,
		"tonemap_exposure": 1.06,
		"fog_light_color": Color(0.90, 0.85, 0.82),
	},
	"Day": {
		# EXACTLY the authored town. Do not "improve" these four lines without
		# looking at the scene file - they are its reference look.
		"sun_color": Color(1.000, 0.945, 0.851),
		"sun_energy": 1.50,
		"sun_yaw_degrees": 0.0,
		"fill_color": Color(0.706, 0.788, 0.902),
		"fill_energy": 0.30,
		"sky_top_color": Color(0.290, 0.478, 0.729),
		"sky_horizon_color": Color(0.796, 0.851, 0.878),
		"ground_horizon_color": Color(0.769, 0.808, 0.820),
		"ground_bottom_color": Color(0.451, 0.478, 0.451),
		"ambient_energy": 0.90,
		"tonemap_exposure": 1.05,
		"fog_light_color": Color(0.82, 0.86, 0.90),
	},
	"Evening": {
		"sun_color": Color(1.00, 0.80, 0.60),
		"sun_energy": 1.30,
		"sun_yaw_degrees": 46.0,
		"fill_color": Color(0.62, 0.70, 0.90),
		"fill_energy": 0.34,
		"sky_top_color": Color(0.300, 0.360, 0.640),
		"sky_horizon_color": Color(0.980, 0.760, 0.620),
		"ground_horizon_color": Color(0.700, 0.660, 0.640),
		"ground_bottom_color": Color(0.400, 0.380, 0.360),
		"ambient_energy": 1.00,
		"tonemap_exposure": 1.08,
		"fog_light_color": Color(0.92, 0.78, 0.70),
	},
}

## Same anchor hours as the sky adapter, so the two screens agree about when it
## is morning. See the measurement note in `weather_visual_adapter.gd`.
const TIME_ANCHORS := ACAWeatherVisualAdapter.TIME_ANCHORS

## Weather layers. `scale` multiplies, `set` replaces - same rule as the sky.
const WEATHER_LAYERS := {
	"Clear": {
		"scale": {},
		"set": {"fog_enabled": false, "fog_density": 0.0},
	},
	"Foggy": {
		"scale": {
			"sun_energy": 0.62,
			"fill_energy": 1.35,
			"ambient_energy": 1.12,
			"tonemap_exposure": 1.02,
		},
		# The town camera sits ~60 units back, so a density that reads as
		# "atmospheric" at mower height is a solid white wall here. Measured
		# from the screenshot pass, not copied from the sky adapter.
		"set": {"fog_enabled": true, "fog_density": 0.0045},
	},
	"Rain": {
		"scale": {
			"sun_energy": 0.42,
			"fill_energy": 1.30,
			"ambient_energy": 1.20,
			"sun_color": 0.86,
			"sky_top_color": 0.72,
			"sky_horizon_color": 0.80,
		},
		"set": {"fog_enabled": true, "fog_density": 0.0022},
	},
}

@export var blend_speed: float = 1.2
@export var update_interval: float = 0.05

var _environment: Environment = null
var _sky_material: ProceduralSkyMaterial = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
## The sun basis exactly as the scene authored it. Time of day rotates AROUND
## this rather than replacing it, so the town keeps its authored shadow feel.
var _sun_basis: Basis = Basis.IDENTITY

var _weather: String = "Clear"
var _hour: float = 12.0
## Last yaw actually written, in degrees. NAN means "never written".
var _written_yaw: float = NAN
var _current: Dictionary = {}
var _target: Dictionary = {}
var _accumulator: float = 0.0
var _enabled: bool = false


## Duplicates the environment and sky material so the authored sub-resources in
## `BusinessTown.tscn` are never written to.
func bind(world_environment: WorldEnvironment, sun: DirectionalLight3D,
		fill: DirectionalLight3D) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	_environment = world_environment.environment.duplicate(true)
	world_environment.environment = _environment
	if _environment.sky != null and _environment.sky.sky_material is ProceduralSkyMaterial:
		_environment.sky = _environment.sky.duplicate(true)
		_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial
	_sun = sun
	_fill = fill
	if _sun != null:
		_sun_basis = _sun.transform.basis
	_enabled = true


func is_bound() -> bool:
	return _enabled


func set_state(weather: String, hour: float) -> void:
	_weather = weather if WEATHER_LAYERS.has(weather) else "Clear"
	_hour = clampf(hour, 0.0, 23.99)
	_target = compose(_weather, _hour)


func apply_immediate(weather: String, hour: float) -> void:
	set_state(weather, hour)
	_current = _target.duplicate()
	# A snap must land exactly, deadband or not.
	_written_yaw = NAN
	_write(_current)


func _process(delta: float) -> void:
	if not _enabled or _target.is_empty():
		return
	_accumulator += delta
	if _accumulator < update_interval:
		return
	var step := _accumulator
	_accumulator = 0.0

	if _current.is_empty():
		_current = _target.duplicate()
		_write(_current)
		return

	var t := 1.0 - exp(-blend_speed * step)
	for key: String in _target:
		_current[key] = _lerp_value(_current.get(key, _target[key]), _target[key], t)
	_write(_current)


# ============================================================== composition

func compose(weather: String, hour: float) -> Dictionary:
	var values := time_values(hour)
	var layer: Dictionary = WEATHER_LAYERS.get(weather, WEATHER_LAYERS["Clear"])
	for key: String in layer["scale"]:
		if values.has(key):
			values[key] = _scaled(values[key], float(layer["scale"][key]))
	for key: String in layer["set"]:
		values[key] = layer["set"][key]
	return values


func time_values(hour: float) -> Dictionary:
	var h := clampf(hour, 0.0, 23.999)
	var a_name: String = TIME_ANCHORS[0][1]
	var b_name: String = TIME_ANCHORS[0][1]
	var t := 0.0
	for i in range(TIME_ANCHORS.size() - 1):
		var start: float = TIME_ANCHORS[i][0]
		var end: float = TIME_ANCHORS[i + 1][0]
		if h >= start and h <= end:
			a_name = TIME_ANCHORS[i][1]
			b_name = TIME_ANCHORS[i + 1][1]
			t = (h - start) / maxf(end - start, 0.0001)
			break
	var a: Dictionary = TIME_PROFILES[a_name]
	var b: Dictionary = TIME_PROFILES[b_name]
	var eased := smoothstep(0.0, 1.0, t)
	var out := {}
	for key: String in a:
		out[key] = _lerp_value(a[key], b.get(key, a[key]), eased)
	return out


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

func _write(v: Dictionary) -> void:
	if _sun != null:
		# Colour and energy are cheap and continuous: a smooth day/night ramp is
		# the whole point of this adapter and neither can shimmer.
		_sun.light_color = v.get("sun_color", _sun.light_color)
		_sun.light_energy = float(v.get("sun_energy", _sun.light_energy))
		# The BASIS is the expensive one — see SUN_YAW_DEADBAND_DEGREES. Rotate
		# the AUTHORED basis about world Y, so the sun sweeps across the sky
		# without losing the pitch the scene was lit with.
		var yaw_degrees := float(v.get(SUN_YAW_KEY, 0.0))
		if is_nan(_written_yaw) 				or absf(yaw_degrees - _written_yaw) >= SUN_YAW_DEADBAND_DEGREES:
			_written_yaw = yaw_degrees
			_sun.transform.basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * _sun_basis
	if _fill != null:
		_fill.light_color = v.get("fill_color", _fill.light_color)
		_fill.light_energy = float(v.get("fill_energy", _fill.light_energy))
	if _sky_material != null:
		_sky_material.sky_top_color = v.get("sky_top_color", _sky_material.sky_top_color)
		_sky_material.sky_horizon_color = v.get(
			"sky_horizon_color", _sky_material.sky_horizon_color)
		_sky_material.ground_horizon_color = v.get(
			"ground_horizon_color", _sky_material.ground_horizon_color)
		_sky_material.ground_bottom_color = v.get(
			"ground_bottom_color", _sky_material.ground_bottom_color)
	if _environment != null:
		_environment.ambient_light_energy = float(
			v.get("ambient_energy", _environment.ambient_light_energy))
		_environment.tonemap_exposure = float(
			v.get("tonemap_exposure", _environment.tonemap_exposure))
		_environment.fog_enabled = bool(v.get("fog_enabled", false))
		_environment.fog_density = float(v.get("fog_density", 0.0))
		_environment.fog_light_color = v.get("fog_light_color", _environment.fog_light_color)
