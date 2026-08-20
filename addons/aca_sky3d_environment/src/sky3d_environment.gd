@tool
class_name ACASky3DEnvironment
extends Node
## THE REUSABLE ADAPTER. Composes a time of day with a weather and writes the
## result to a VANILLA Sky3D installation.
##
##     host game state  (whatever owns your clock)
##            |
##       [ your integration layer ]
##            |
##       ACASky3DEnvironment   <- you are here
##            |
##       vanilla Sky3D  +  Godot Environment  +  ACAPrecipitationRig
##
## ---------------------------------------------------------------------------
## THE BOUNDARY
## ---------------------------------------------------------------------------
##
## THIS ADAPTER OWNS VISUAL COMPOSITION. THE GAME OWNS GAME STATE.
##
## Nothing in this package knows what a clock, a job, a save file or a player
## is. It is told an hour and a weather name and it makes the world look like
## that. Keep it that way: the moment this file imports something from a game,
## the package stops being reusable.
##
## It requires a vanilla `res://addons/sky_3d/` alongside it and MODIFIES
## NOTHING inside it. See `README.md` for the install order and the tested
## version.
##
## ---------------------------------------------------------------------------
## NO TWEENS
## ---------------------------------------------------------------------------
##
## Every value is driven by ONE per-tick exponential approach towards the
## composed target. There is deliberately no `Tween` in this file:
##
##   * time drifts continuously, so a fixed-duration tween would be restarted
##     forever and never finish;
##   * two overlapping weather changes cannot strand a stale tween writing old
##     values, because there is nothing left behind to strand;
##   * convergence is guaranteed from any state, including a mid-transition
##     save or load.
##
## `apply_immediate()` snaps instead, for scene load and restore.

signal weather_changed(id: StringName)
signal quality_changed(id: StringName)

const PROFILE_ROOT := "res://addons/aca_sky3d_environment/profiles"

@export_group("Profiles")
## Directory scanned for `ACAEnvTimeProfile` resources. Point it somewhere else
## to ship a different set of looks without touching this script.
@export_dir var time_profile_dir: String = PROFILE_ROOT + "/time"
@export_dir var weather_profile_dir: String = PROFILE_ROOT + "/weather"
@export_dir var quality_profile_dir: String = PROFILE_ROOT + "/quality"

## `[hour, profile_id]`. Which hours the time profiles sit at. These belong to
## the HOST's world, not to this package: a game with a compressed day or an
## unusual latitude will want its own, measured against its own sun.
@export var anchors: Array = [
	[0.0, "Night"], [4.8, "Night"], [7.0, "Morning"], [9.8, "Day"],
	[14.2, "Day"], [16.3, "Evening"], [18.2, "Night"], [24.0, "Night"],
]

@export_group("World")
## The world Y that counts as GROUND LEVEL.
##
## `ACAEnvWeatherProfile.fog_height` is authored RELATIVE to this, because
## Godot's `Environment.fog_height` is an absolute world coordinate and a host
## is under no obligation to build its level at the origin. A Cut Above's
## mowing lawn sits at about y = -508; left at zero, every surface in that
## scene is five hundred units "below" the fog layer, the height term
## saturates, and the entire frame renders as flat white. That is not a fog
## that needs tuning down — it is a fog measuring from the wrong place.
##
## Set it explicitly, or let `set_tracking_target()` infer it.
@export var ground_reference: float = 0.0
## Infer `ground_reference` from the tracking target when one is given.
@export var auto_ground_reference: bool = true
## Assumed distance from the tracking target down to the ground, used only by
## the inference above. A camera is not standing on the floor.
@export var tracking_eye_height: float = 2.0

@export_group("Transitions")
## Exponential approach towards the composed target, per second. ~1.2 settles a
## weather change in about two and a half seconds.
@export var blend_speed: float = 1.2

# --------------------------------------------------------------------- state
var composer := ACAEnvComposer.new()

var _sky: Node = null            ## the Sky3D node (a WorldEnvironment)
var _dome: Node = null           ## its Skydome child
var _env: Environment = null     ## the Environment Sky3D holds
var _rig: ACAPrecipitationRig = null

var _weather: String = "Clear"
var _hour: float = 12.0
var _quality: ACAEnvQualityProfile = null
var _qualities: Dictionary = {}

var _current: Dictionary = {}
var _target: Dictionary = {}
var _accumulator: float = 0.0
var _bound: bool = false
var _loaded: bool = false


func _ready() -> void:
	load_profiles()
	set_process(true)


# ======================================================================= setup

## Scans the profile directories. Safe to call again; it replaces nothing that
## was added by hand through `composer`.
func load_profiles() -> void:
	if _loaded:
		return
	_loaded = true
	composer.anchors = anchors
	for res in _load_dir(time_profile_dir):
		if res is ACAEnvTimeProfile:
			composer.add_time_profile(res)
	for res in _load_dir(weather_profile_dir):
		if res is ACAEnvWeatherProfile:
			composer.add_weather_profile(res)
	for res in _load_dir(quality_profile_dir):
		if res is ACAEnvQualityProfile:
			_qualities[String((res as ACAEnvQualityProfile).id)] = res
	if _quality == null and not _qualities.is_empty():
		_quality = _qualities.get("High", _qualities.values()[0])


func _load_dir(path: String) -> Array:
	var out: Array = []
	if path.is_empty():
		return out
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("ACASky3DEnvironment: profile directory not found: %s" % path)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension() == "tres":
			var res := ResourceLoader.load(path.path_join(name))
			if res != null:
				out.append(res)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## Bind to a vanilla Sky3D. `sky_node` is the `Sky3D` (WorldEnvironment) and
## `dome_node` its `Skydome` child; pass only the first and the second is found.
func bind(sky_node: Node, dome_node: Node = null) -> void:
	_sky = sky_node
	_dome = dome_node
	if _dome == null and _sky != null:
		_dome = _sky.get_node_or_null(^"Skydome")
	_env = null
	if _sky != null and _sky.get("environment") is Environment:
		_env = _sky.get("environment")
	_bound = _sky != null and _dome != null
	if _bound:
		_prepare_environment()
		_push_time()


func is_bound() -> bool:
	return _bound


## The Environment arrives configured for Sky3D's own sky and ambient. The only
## thing added here is the fog block, which Sky3D never touches: its own fog is
## the separate screen-space quad on the Skydome.
func _prepare_environment() -> void:
	if _env == null:
		return
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.volumetric_fog_temporal_reprojection_enabled = true


## Hand over a precipitation rig to drive. Optional: without one, the `fx:`
## half of the composition is simply not consumed.
func set_precipitation_rig(rig: ACAPrecipitationRig) -> void:
	_rig = rig
	if _rig != null and _quality != null:
		_rig.set_quality(_quality)


func precipitation_rig() -> ACAPrecipitationRig:
	return _rig


# ================================================================= public API

## The hour to present, 0.0 - 23.99. Visuals ease towards it.
##
## This also MOVES THE SUN. `Sky3D.current_time` is the addon's own entry
## point for time, and forwarding to it is what makes the sun, moon, stars and
## shadow direction agree with the composed look. An adapter that set only the
## colours would leave the sky painted like noon with the sun still below the
## horizon — which is exactly what a black-ground demo frame looks like.
func set_time_of_day(hour: float) -> void:
	_hour = clampf(hour, 0.0, 23.99)
	_push_time()
	_retarget()


## THE ONE WRITER for Sky3D's clock. Sky3D forwards this to `TimeOfDay`, which
## recomputes the sun and moon coordinates; it is not free, so it is written
## when the hour changes rather than on every composition tick.
func _push_time() -> void:
	if _sky != null:
		_sky.set(&"current_time", _hour)


## The weather to present. Unknown ids fall back to the first profile loaded
## rather than throwing, so a host cannot crash the sky with a typo.
func set_weather(id: StringName) -> void:
	var want := String(id)
	if not composer.has_weather(want):
		push_warning("ACASky3DEnvironment: unknown weather '%s'" % want)
		if composer.weather_ids().is_empty():
			return
		want = composer.weather_ids()[0]
	if _weather == want:
		return
	_weather = want
	_retarget()
	weather_changed.emit(StringName(_weather))


## Set state AND snap to it, with no transition. For scene load and restore.
func apply_immediate(id: StringName, hour: float) -> void:
	var want := String(id)
	if composer.has_weather(want):
		_weather = want
	_hour = clampf(hour, 0.0, 23.99)
	_push_time()
	_retarget()
	_current = _target.duplicate()
	_write(_current, true)
	if _rig != null:
		_rig.apply_immediate(float(_current.get("fx:rain_intensity", 0.0)))


## Choose a quality level by id. This switches whole GPU mechanisms on and off;
## see `quality_profile.gd`.
func set_quality(id: StringName) -> void:
	var want := String(id)
	if not _qualities.has(want):
		push_warning("ACASky3DEnvironment: unknown quality '%s'" % want)
		return
	_quality = _qualities[want]
	if _rig != null:
		_rig.set_quality(_quality)
	# A level that has just switched a mechanism off must not leave the last
	# value it wrote standing on the Environment.
	_write(_current, true)
	quality_changed.emit(StringName(want))


## What the rain follows. A camera usually reads better than a vehicle.
##
## Also fixes the fog's idea of where the ground is, unless the host has said
## otherwise. See `ground_reference`.
func set_tracking_target(node: Node3D) -> void:
	if _rig != null:
		_rig.set_tracking_target(node)
	if auto_ground_reference and node != null and node.is_inside_tree():
		set_ground_reference(node.global_position.y - tracking_eye_height)


## Declare where ground level is. Re-writes immediately: a fog measuring from
## the wrong height is not a subtle error.
func set_ground_reference(world_y: float) -> void:
	if is_equal_approx(ground_reference, world_y):
		return
	ground_reference = world_y
	_write(_current, true)


func set_transition_speed(per_second: float) -> void:
	blend_speed = maxf(per_second, 0.01)


## Media tooling. One extra `{"scale": {}, "set": {}}` layer composed after the
## weather, so a capture can have a look the shipped profiles do not ship.
func set_presentation_override(layer: Dictionary) -> void:
	composer.set_override(layer)
	_retarget()


func clear_presentation_override() -> void:
	set_presentation_override({})


func has_presentation_override() -> bool:
	return composer.has_override()


func presentation_override() -> Dictionary:
	return composer.override()


# ------------------------------------------------------------------ reading

func current_weather() -> String:
	return _weather


func current_hour() -> float:
	return _hour


func current_quality() -> String:
	return "" if _quality == null else String(_quality.id)


func quality_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _qualities:
		out.append(k)
	out.sort()
	return out


func quality_profile(id: String) -> ACAEnvQualityProfile:
	return _qualities.get(id, null)


func weather_ids() -> PackedStringArray:
	return composer.weather_ids()


func time_profile_ids() -> PackedStringArray:
	return composer.time_profile_ids()


func time_profile_at(hour: float) -> String:
	return composer.profile_at(hour)


## The composed look for a combination, without needing anything bound. Public
## so tooling and tests can inspect a look with no scene running.
func compose(weather_id: String, hour: float) -> Dictionary:
	load_profiles()
	return composer.compose(weather_id, hour)


func time_values(hour: float) -> Dictionary:
	load_profiles()
	return composer.time_values(hour)


## What is actually on screen right now, mid-transition included.
func current_visual_state() -> Dictionary:
	return {
		"weather": _weather,
		"hour": _hour,
		"quality": current_quality(),
		"time_profile": time_profile_at(_hour),
		"bound": _bound,
		"raining": _rig != null and _rig.is_raining(),
		"rain_intensity": 0.0 if _rig == null else _rig.current_intensity(),
		"values": _current.duplicate(),
	}


# ===================================================================== running

func _retarget() -> void:
	load_profiles()
	_target = composer.compose(_weather, _hour)


func _process(delta: float) -> void:
	if not _bound or _target.is_empty():
		return
	_accumulator += delta
	var interval := 0.05 if _quality == null else _quality.update_interval
	if _accumulator < interval:
		return
	var step := _accumulator
	_accumulator = 0.0

	if _current.is_empty():
		_current = _target.duplicate()
		_write(_current, true)
		return

	var t := 1.0 - exp(-blend_speed * step)
	for key: String in _target:
		if ACAEnvKeys.is_discrete(key):
			_current[key] = _target[key]
			continue
		_current[key] = ACAEnvComposer.lerp_value(
			_current.get(key, _target[key]), _target[key], t)
	_write(_current, false)


# ====================================================================== output

func _write(values: Dictionary, force: bool) -> void:
	if not _bound or values.is_empty():
		return
	for key: String in values:
		var target := ACAEnvKeys.target_for(key)
		if target == "":
			continue
		var value: Variant = _filtered(key, values[key])
		if value == null:
			continue
		var stepped := ACAEnvKeys.is_step_key(key) or value is bool
		if stepped and not force and not _step_should_write(key, value):
			continue
		_write_one(target, key, value)
	_write_fx(values)


## QUALITY IS APPLIED HERE, NOT IN THE PROFILES.
##
## A weather profile describes the weather; it does not know what machine it is
## running on. Returning `null` means "this level does not do that at all", and
## the key is skipped entirely rather than written with a token value.
func _filtered(key: String, value: Variant) -> Variant:
	# Applies with or without a quality profile: it is a correctness fix, not a
	# performance one.
	if key == "env:fog_height":
		return float(value) + ground_reference
	if _quality == null:
		return value
	match key:
		"env:fog_enabled":
			return bool(value) and _quality.use_depth_fog
		"env:fog_density":
			return float(value) * _quality.depth_fog_density_scale
		"env:fog_height_density":
			return float(value) * _quality.height_fog_density_scale
		"env:fog_height":
			return float(value) + ground_reference
		"env:volumetric_fog_enabled":
			return bool(value) and _quality.use_volumetric_fog
		"env:volumetric_fog_density":
			if not _quality.use_volumetric_fog:
				return 0.0
			return float(value) * _quality.volumetric_density_scale
		"dome:fog_density":
			# Switching the Sky3D quad off means density zero: the node has no
			# visibility flag this package is willing to fight Sky3D over.
			return float(value) if _quality.use_aerial else 0.0
	return value


func _write_one(target: String, key: String, value: Variant) -> void:
	var property := ACAEnvKeys.property_for(key)
	match target:
		"sky":
			if _sky != null:
				_sky.set(property, value)
		"dome":
			if _dome != null:
				_dome.set(property, value)
		"env":
			if _env != null:
				_env.set(property, value)
			if property == &"volumetric_fog_enabled" and bool(value) and _env != null:
				_env.volumetric_fog_length = _quality.volumetric_length \
					if _quality != null else 96.0
				_env.volumetric_fog_detail_spread = _quality.volumetric_detail_spread \
					if _quality != null else 2.0


func _write_fx(values: Dictionary) -> void:
	if _rig == null:
		return
	_rig.set_intensity(float(values.get("fx:rain_intensity", 0.0)))
	_rig.set_wind(Vector2(
		float(values.get("fx:wind_x", 0.0)),
		float(values.get("fx:wind_z", 0.0))))


## Step keys go through Sky3D setters that start their own Tween, so they are
## written only when the value has really moved. See `env_keys.gd`.
func _step_should_write(key: String, value: Variant) -> bool:
	var target := ACAEnvKeys.target_for(key)
	var node: Object = null
	match target:
		"sky": node = _sky
		"dome": node = _dome
		"env": node = _env
	if node == null:
		return false
	var current: Variant = node.get(ACAEnvKeys.property_for(key))
	if value is bool:
		return current != value
	if current is float or current is int:
		return absf(float(current) - float(value)) > ACAEnvKeys.STEP_DEADBAND
	return true
