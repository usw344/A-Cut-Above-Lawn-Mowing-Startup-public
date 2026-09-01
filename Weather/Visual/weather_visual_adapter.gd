class_name ACAWeatherVisualAdapter
extends Node
## A CUT ABOVE's INTEGRATION LAYER over the reusable environment package.
##
##     WorldClock          (authoritative game time + weather STATE)
##          |
##     preset_manager      (the project-facing weather API scenes call)
##          |
##     ACAWeatherVisualAdapter   <- you are here. Game-side. Thin.
##          |
##     ACASky3DEnvironment       <- res://addons/aca_sky3d_environment/
##          |
##     vanilla Sky3D  +  Godot Environment  +  ACAPrecipitationRig
##
## ---------------------------------------------------------------------------
## WHAT MOVED, AND WHY THIS FILE IS NOW SHORT
## ---------------------------------------------------------------------------
##
## This file used to BE the weather system: seven hard-coded tables, the
## composition rule, the Sky3D property map and the write loop, all in one
## place. All of that is now in `res://addons/aca_sky3d_environment/`, which
## knows nothing about A Cut Above and can be copied into any project that has
## a vanilla Sky3D.
##
## What is left here is the part that is genuinely OURS:
##
##   * the ANCHOR HOURS, which are measured against THIS Skydome's sun (see
##     the note below) and are shared with the Town's light adapter;
##   * the binding to `preset_manager`'s scene nodes;
##   * the quality mapping from `GameSettings`;
##   * the public API `preset_manager`, the trailer, the probes and the tests
##     already call, kept EXACTLY as it was.
##
## The look itself — every colour, every fog number, every cloud value — lives
## in the package's profile resources under `profiles/`. Change how something
## looks THERE, not here.

## Hour -> profile. The only "times of day" that exist; everything else is a
## blend of two neighbours.
##
## MEASURED, not guessed. `Dev tools/Validation/Sun Probe.tscn` prints Sky3D's
## sun altitude per half hour for THIS Skydome configuration (realistic mode,
## latitude 16): the sun is up from about **06:35 to 17:05**, highest at 12:00.
## Anchors outside that window put "Evening" after dark — the first attempt
## used 18.4 and rendered a black screen with stars.
##
## MORNING WAS AT 7.0 AND IS AT 8.2. Seven o'clock is twenty-five minutes after
## sunrise: the sun is barely off the horizon, Sky3D is painting the whole dome
## with its horizon tint, and the render came out as a pink scene in which the
## grass could not be read. Eight-twelve is an hour and a half up, which is
## what "morning" means, and it is also when the player's working day starts.
## The 5.2 -> 8.2 span is dawn, and it is a blend rather than a look.
##
## If the Skydome's latitude, date or celestial mode ever change, re-run the
## probe and move these. `ACATownLightAdapter` reads this same constant, so the
## two screens can never disagree about when it is morning.
const TIME_ANCHORS := [
	[0.0, "Night"], [5.2, "Night"], [8.2, "Morning"], [10.4, "Day"],
	[14.2, "Day"], [16.3, "Evening"], [18.2, "Night"], [24.0, "Night"],
]

## Weather names this project uses. THE AUTHORITY IS `ACAWorldClock`: this used
## to be a second copy of the list, and the two could disagree. Now a preset the
## clock can schedule is a preset this adapter will present, and there is one
## place to add the ninth.
const WEATHER_NAMES: PackedStringArray = ACAWorldClock.WEATHER_PRESETS

## `GameSettings` graphics quality -> environment quality profile id.
const QUALITY_FOR_SETTING := {
	"low": "Low", "medium": "Medium", "high": "High", "ultra": "High",
}

@export var blend_speed: float = 1.2: set = set_blend_speed
@export var update_interval: float = 0.05

var _env: ACASky3DEnvironment = null
var _enabled: bool = false


func _ready() -> void:
	_ensure_env()


## The adapter is created without a scene by tests and tooling, which then call
## `compose()` straight away. Building the package object lazily means both
## paths work and nothing has to be initialised in a particular order.
func _ensure_env() -> ACASky3DEnvironment:
	if _env != null:
		return _env
	_env = ACASky3DEnvironment.new()
	_env.name = "Sky3D Environment"
	_env.anchors = TIME_ANCHORS
	_env.blend_speed = blend_speed
	_env.load_profiles()
	return _env


func set_blend_speed(value: float) -> void:
	blend_speed = value
	if _env != null:
		_env.blend_speed = value


# ================================================================== lifecycle

## Bind the addon nodes. Called by `preset_manager`; nothing else should.
##
## The package node is added as a child ONLY here, not in `_ready()`. A bare
## adapter used for composition has no children at all, which is what
## `Weather Test` asserts when it checks that nothing stale is left running on
## the sky.
func bind(sky_node: Node, dome_node: Node) -> void:
	_ensure_env()
	if _env.get_parent() == null:
		add_child(_env)
	_env.bind(sky_node, dome_node)
	_enabled = _env.is_bound()


func is_bound() -> bool:
	return _enabled


## Hand the package the rain rig owned by the scene's Rain Handler.
func set_precipitation_rig(rig: ACAPrecipitationRig) -> void:
	_ensure_env().set_precipitation_rig(rig)


## What the rain follows. The mowing scene passes its camera.
##
## This also tells the environment where GROUND LEVEL is, which matters here
## more than in most projects: the mowing lawn is authored at about y = -508,
## and height fog measured from the world origin renders that scene as a flat
## white screen.
func set_tracking_target(node: Node3D) -> void:
	_ensure_env().set_tracking_target(node)


## Declare ground level explicitly, when the scene knows better than the
## camera's height can imply.
func set_ground_reference(world_y: float) -> void:
	_ensure_env().set_ground_reference(world_y)


## Apply the player's graphics setting. Unknown values leave the current level
## alone rather than guessing.
func apply_quality_setting(setting: String) -> void:
	var id: String = QUALITY_FOR_SETTING.get(setting.to_lower(), "")
	if id.is_empty():
		return
	_ensure_env().set_quality(StringName(id))


func current_quality() -> String:
	return _ensure_env().current_quality()


func environment() -> ACASky3DEnvironment:
	return _env


# ================================================================== driving

## Set the state to present. Visuals ease towards it.
func set_state(weather: String, hour: float) -> void:
	var env := _ensure_env()
	env.set_weather(StringName(weather if WEATHER_NAMES.has(weather) else "Clear"))
	env.set_time_of_day(hour)


## Set the state AND snap to it. For scene load and save restore, where easing
## in from whatever the previous scene looked like would be a visible glitch.
func apply_immediate(weather: String, hour: float) -> void:
	_ensure_env().apply_immediate(
		StringName(weather if WEATHER_NAMES.has(weather) else "Clear"), hour)


func current_weather() -> String:
	return _ensure_env().current_weather()


func current_hour() -> float:
	return _ensure_env().current_hour()


## The blended time profile name for `hour`, for tests and tooling.
func time_profile_at(hour: float) -> String:
	return _ensure_env().time_profile_at(hour)


# ---------------------------------------------------------- THE PLACE
#
# WHERE IN THE WORLD THIS SCENE IS, as a standing layer on the composed look.
# It is set when a level loads and left alone: a region says how much air is
# between the player and the horizon, and nothing else. It is NOT a second
# weather system - the sky `ACAWorldClock` scheduled is the sky in every region
# at the same moment - and it lives in its own slot rather than in the
# presentation override, so a trailer capture cannot clear it by accident.

## Hand the adapter a region. -1, or a region with no air of its own, clears it.
func set_region(region: int) -> void:
	_ensure_env().set_place_layer(ACARegionalContext.air_layer(region))


func clear_region() -> void:
	_ensure_env().clear_place_layer()


func place_layer() -> Dictionary:
	return _ensure_env().place_layer()


# ---------------------------------------------- PRESENTATION OVERRIDE
#
# DEVELOPMENT / MEDIA TOOLING. One extra layer composed ON TOP of the shipped
# look, in the same `scale` / `set` shape the composed key space uses.
#
# `Trailer Capture` uses it to push the storm further than the game ships it
# for one shot. It is EMPTY in normal gameplay, it eases in and out through the
# same per-tick approach as everything else, and `Trailer Test` asserts it is
# empty again after a capture.

func set_presentation_override(layer: Dictionary) -> void:
	_ensure_env().set_presentation_override(layer)


func clear_presentation_override() -> void:
	_ensure_env().clear_presentation_override()


func presentation_override() -> Dictionary:
	return _ensure_env().presentation_override()


func has_presentation_override() -> bool:
	return _ensure_env().has_presentation_override()


# ============================================================== composition

## The composed look for a combination. Public so tooling and tests can inspect
## a combination without a running scene.
func compose(weather: String, hour: float) -> Dictionary:
	return _ensure_env().compose(weather, hour)


## The pure time-of-day look, with no weather applied.
func time_values(hour: float) -> Dictionary:
	return _ensure_env().time_values(hour)


## What is on screen right now, mid-transition included.
func current_visual_state() -> Dictionary:
	return _ensure_env().current_visual_state()


## The package's own profile objects, for tests that assert on the DATA rather
## than on a composed result.
func time_profile(id: String) -> ACAEnvTimeProfile:
	return _ensure_env().composer.time_profile(id)


func weather_profile(id: String) -> ACAEnvWeatherProfile:
	return _ensure_env().composer.weather_profile(id)


func weather_ids() -> PackedStringArray:
	return _ensure_env().weather_ids()


func time_profile_ids() -> PackedStringArray:
	return _ensure_env().time_profile_ids()
