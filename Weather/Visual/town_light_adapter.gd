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
## ---------------------------------------------------------------------------
## THE SUN GETS LOW NOW, AS WELL AS TURNING
## ---------------------------------------------------------------------------
## This adapter used to rotate the authored sun about world Y ONLY, which kept
## the town's authored shading angle at every hour. It also meant the sun was
## forty degrees above the horizon at half past four in the afternoon, so a hub
## at "evening" was a midday scene with warm light on it - the one thing about
## the regional screens that a render could not be argued out of.
##
## The pitch is now offset per time of day, applied about the light's OWN right
## axis so it lifts and drops the sun without disturbing the direction it comes
## from. Day is zero, which is the town exactly as authored.
const SUN_PITCH_KEY := "sun_pitch_offset_degrees"

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
## The same deadband, for the same reason, on the pitch.
const SUN_PITCH_DEADBAND_DEGREES := 0.25

## Fog density at `haze = 1.0`. Small: the point is to separate a horizon from
## a foreground, not to put weather in the air that the clock did not schedule.
const AIR_HAZE_DENSITY := 0.0016

## ---------------------------------------------------------------------------
## HOW MUCH OF THE FOG LANDS ON THE SKY
## ---------------------------------------------------------------------------
## Godot's `Environment.fog_sky_affect` DEFAULTS TO 1.0, which means fog thick
## enough to soften a horizon also paints the entire sky the fog's own colour.
## The first render of the regional hubs with region haze on them came out with
## a flat cream void behind the island where the sky should have been, and the
## Big Town skyline vanished into it in the rain.
##
## Every weather now states its own value, and the region's standing haze - which
## is about DISTANCE, not about weather - states zero. A fog that has swallowed
## the sky is not a fog, it is a background colour.
const AIR_HAZE_SKY_AFFECT := 0.0

## Time profiles. Small on purpose - a stylised town needs colour and intensity,
## not a simulation.
const TIME_PROFILES := {
	"Night": {
		"sun_color": Color(0.62, 0.72, 0.98),
		"sun_energy": 0.30,
		"sun_yaw_degrees": 80.0,
		"sun_pitch_offset_degrees": 14.0,
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
		"sun_pitch_offset_degrees": 21.0,
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
		"sun_pitch_offset_degrees": 0.0,
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
		"sun_pitch_offset_degrees": 24.0,
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
##
## EIGHT SKIES, THE SAME EIGHT `ACAWorldClock` SCHEDULES. The town is lit by a
## `ProceduralSkyMaterial` rather than by Sky3D, so these are not the same
## numbers as the mowing scene's weather profiles - but they are the same
## STATES, and the two screens agree about what the weather is because they read
## the same clock.
##
## The town camera sits about sixty units back from its subject, so a fog
## density that reads as atmospheric at mower height is a solid wall here. Every
## density below was measured from a render rather than copied from the sky
## adapter.
const WEATHER_LAYERS := {
	"Clear": {
		"scale": {},
		"set": {"fog_enabled": false, "fog_density": 0.0, "fog_sky_affect": 0.0},
	},
	"Partly Cloudy": {
		"scale": {
			"sun_energy": 0.94,
			"fill_energy": 1.06,
			"ambient_energy": 1.03,
		},
		"set": {"fog_enabled": true, "fog_density": 0.0009,
			"fog_sky_affect": 0.02},
	},
	# OVERCAST IS NOT A DIMMER. The sun goes soft and nearly shadowless, the
	# SKY does most of the lighting instead, and the whole scene loses contrast
	# rather than brightness - which is what an overcast day actually looks
	# like and why it is the one weather that reads as structurally different.
	"Overcast": {
		"scale": {
			"sun_energy": 0.46,
			"fill_energy": 1.75,
			"ambient_energy": 1.34,
			"tonemap_exposure": 1.05,
			"sun_color": 0.94,
			"sky_top_color": 0.80,
		},
		"set": {"fog_enabled": true, "fog_density": 0.0026,
			"fog_sky_affect": 0.16},
	},
	"Mist": {
		"scale": {
			"sun_energy": 0.78,
			"fill_energy": 1.22,
			"ambient_energy": 1.08,
			"tonemap_exposure": 1.02,
		},
		"set": {"fog_enabled": true, "fog_density": 0.0026,
			"fog_sky_affect": 0.26},
	},
	"Foggy": {
		"scale": {
			"sun_energy": 0.62,
			"fill_energy": 1.35,
			"ambient_energy": 1.12,
			"tonemap_exposure": 1.02,
		},
		"set": {"fog_enabled": true, "fog_density": 0.0045,
			"fog_sky_affect": 0.4},
	},
	"Light Rain": {
		"scale": {
			"sun_energy": 0.54,
			"fill_energy": 1.44,
			"ambient_energy": 1.18,
			"sun_color": 0.92,
			"sky_top_color": 0.80,
			"sky_horizon_color": 0.86,
		},
		"set": {"fog_enabled": true, "fog_density": 0.0018,
			"fog_sky_affect": 0.14},
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
		"set": {"fog_enabled": true, "fog_density": 0.0022,
			"fog_sky_affect": 0.2},
	},
	# THE SKY BREAKING UP. Brighter than clear at the horizon, still damp in the
	# distance, and the one weather in the game that is allowed to look pleased
	# with itself.
	"Clearing": {
		"scale": {
			"sun_energy": 1.06,
			"fill_energy": 0.94,
			"ambient_energy": 0.99,
			"sky_horizon_color": 1.05,
		},
		"set": {"fog_enabled": true, "fog_density": 0.0013,
			"fog_sky_affect": 0.05},
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
## Last pitch offset actually written, in degrees.
var _written_pitch: float = 0.0
var _current: Dictionary = {}
var _target: Dictionary = {}
var _accumulator: float = 0.0
var _enabled: bool = false
## ---------------------------------------------------------------------------
## THE REGION'S OWN AIR
## ---------------------------------------------------------------------------
## A LAST, SMALL MODIFIER, applied after the weather. It is NOT a second weather
## system and it never changes with the sky: it is the standing difference
## between one place and another - a trade park with more haze in it than a
## country park, a rural horizon that is clearer than a city one.
##
## It moves two things and nothing else: the sky's lower hemisphere, which is
## most of what a fixed isometric camera pointed at the ground actually sees,
## and the amount of distance fog on a clear day, which is what makes a far
## shelf read as far away rather than as a slab behind the island.
var _air_tint: Color = Color.WHITE
var _air_haze: float = 0.0


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


## Give this screen its region's air. Safe to call before or after `bind()`.
func set_region_air(tint: Color, haze: float) -> void:
	_air_tint = tint
	_air_haze = clampf(haze, 0.0, 1.0)
	if not _target.is_empty():
		_target = compose(_weather, _hour)


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
	return _with_region_air(values)


## The region modifier, applied last so nothing else has to know about it.
func _with_region_air(values: Dictionary) -> Dictionary:
	if _air_haze <= 0.0 and _air_tint.is_equal_approx(Color.WHITE):
		return values
	for key in ["ground_horizon_color", "ground_bottom_color", "fog_light_color"]:
		if not values.has(key):
			continue
		var c: Color = values[key]
		values[key] = Color(c.r * _air_tint.r, c.g * _air_tint.g,
			c.b * _air_tint.b, c.a)
	# A BASE HAZE EVEN IN CLEAR WEATHER. The far shelf a regional hub stands
	# in front of is thirty units behind the island; without this it is exactly
	# as sharp as the office in the foreground.
	var haze := AIR_HAZE_DENSITY * _air_haze
	if haze > 0.0 and haze > float(values.get("fog_density", 0.0)):
		values["fog_enabled"] = true
		values["fog_density"] = haze
		# The region's own haze is about how far you can SEE, so it never
		# touches the sky. A weather that wants the sky fogged says so itself.
		values["fog_sky_affect"] = AIR_HAZE_SKY_AFFECT
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
		var pitch_degrees := float(v.get(SUN_PITCH_KEY, 0.0))
		if is_nan(_written_yaw) 				or absf(yaw_degrees - _written_yaw) >= SUN_YAW_DEADBAND_DEGREES 				or absf(pitch_degrees - _written_pitch) >= SUN_PITCH_DEADBAND_DEGREES:
			_written_yaw = yaw_degrees
			_written_pitch = pitch_degrees
			# YAW IN WORLD SPACE, PITCH IN THE LIGHT'S OWN. Post-multiplying by
			# a rotation about local X lifts the sun towards the horizon along
			# the axis it is already pointing down, so the direction the light
			# comes FROM is unchanged and only its height moves.
			_sun.transform.basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees)) 				* _sun_basis * Basis(Vector3.RIGHT, deg_to_rad(pitch_degrees))
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
		_environment.fog_sky_affect = clampf(float(v.get("fog_sky_affect", 0.0)),
			0.0, 1.0)
		_environment.fog_light_color = v.get("fog_light_color", _environment.fog_light_color)
