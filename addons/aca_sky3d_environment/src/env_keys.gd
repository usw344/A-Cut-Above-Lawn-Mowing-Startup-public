class_name ACAEnvKeys
extends RefCounted
## THE VANILLA SKY3D COMPATIBILITY MAP.
##
## Everything this package knows about the third-party addon lives in this one
## file. `res://addons/sky_3d/` is READ-ONLY: nothing here modifies it, and the
## only contract relied on is its public exported properties.
##
## Tested against **Sky3D 2.1-dev** (`Sky3D.version`) on Godot 4.6.
##
## ---------------------------------------------------------------------------
## THREE TARGETS, THREE PREFIXES
## ---------------------------------------------------------------------------
##
##   "sky:<property>"  -> the Sky3D node itself (a WorldEnvironment subclass)
##   "dome:<property>" -> its Skydome child
##   "env:<property>"  -> the Godot `Environment` resource Sky3D is holding
##   "fx:<name>"       -> this package's own effects (precipitation). Never
##                        written to a Sky3D node.
##
## The `env:` space is the important addition. Sky3D's own fog is a screen-space
## quad and Godot's Environment fog is a separate, complementary mechanism; see
## the FOG note below.
##
## ---------------------------------------------------------------------------
## WHAT IS EXPENSIVE, AND WHAT MUST NOT BE WRITTEN EVERY FRAME
## ---------------------------------------------------------------------------
##
## Measured by reading `Sky3D.gd` and `Skydome.gd`, not assumed:
##
## * `Sky3D.set_ambient_energy`, `set_sky_contribution` and `set_night_ambient_min`
##   all call `update_day_night(true)`, which CREATES A TWEEN on the Environment
##   every time it is called. Driving them per tick spawns tweens per tick.
##   They are in STEP_KEYS and are written only when the value has really moved.
## * Every `Skydome` setter early-returns on an unchanged value and otherwise
##   calls `set_shader_parameter`. That is cheap and safe continuously.
## * `Skydome.set_sun_altitude` / `set_sun_azimuth` defer a coordinate update;
##   this package never writes them. TIME drives the sun, through
##   `Sky3D.current_time`, exactly as the addon intends.
## * `Skydome.update_atm_quality()` REASSIGNS THE SHADER. It is called only from
##   `_ready()`. Nothing here calls it, so no shader recompilation occurs.
##
## ---------------------------------------------------------------------------
## FOG: TWO INDEPENDENT MECHANISMS, DELIBERATELY USED FOR DIFFERENT JOBS
## ---------------------------------------------------------------------------
##
## 1. SKY3D AERIAL (`dome:fog_*`) is a full-screen quad running
##    `AtmFog.gdshader`. It tints by the same atmospheric-scattering model as
##    the sky, so its colour is always coherent with the sky — which is exactly
##    what aerial perspective should be.
##
##    Its limitation is structural: the line that would exclude the sky,
##    `ALPHA = depthRaw < 0.999999999999 ? fogColor.a : 0.0;`, IS COMMENTED OUT
##    IN THE SHIPPED SHADER. Density high enough to hide a treeline therefore
##    also washes the sky, and that is the white wall. Because Sky3D is
##    read-only, the fix is not to push this harder — it is to keep it SUBTLE
##    and let something else carry the range.
##
## 2. GODOT ENVIRONMENT FOG (`env:fog_*`) carries the range. It has the three
##    controls the Sky3D quad does not:
##      * `fog_sky_affect`  — keep the sky out of it entirely;
##      * `fog_depth_begin` / `_end` / `_curve` — an explicit near-clear,
##        mid-loss, far-gone ramp;
##      * `fog_height` / `fog_height_density` — fog that sits on the ground and
##        leaves silhouettes standing in it.
##
## 3. VOLUMETRIC (`env:volumetric_fog_*`) is real light-scattering depth, and is
##    the genuinely expensive one. It is a QUALITY decision, never a default.

const SKY_PREFIX := "sky:"
const DOME_PREFIX := "dome:"
const ENV_PREFIX := "env:"
const FX_PREFIX := "fx:"

## Sky3D setters that start their own Tween. Write on change only.
const STEP_KEYS: PackedStringArray = [
	"sky:ambient_energy", "sky:sky_contribution", "sky:night_ambient_min",
]
## How far a step key must move before it is worth a tween.
const STEP_DEADBAND := 0.03

## Properties Sky3D or Godot range-limit to 0..1. Composition can multiply past
## the limit, so the composed value is clamped rather than the profile.
const CLAMPED_01: PackedStringArray = [
	"sky:sky_contribution", "sky:night_ambient_min", "sky:sun_shadow_opacity",
	"dome:atm_darkness", "dome:clouds_coverage", "dome:clouds_cumulus_coverage",
	"dome:clouds_sky_tint_fade",
	"env:fog_sky_affect", "env:fog_aerial_perspective", "env:fog_sun_scatter",
	"env:volumetric_fog_sky_affect", "env:volumetric_fog_ambient_inject",
	"fx:rain_intensity", "fx:wetness",
]

## Keys that are booleans or ints and must never be interpolated.
const DISCRETE_KEYS: PackedStringArray = [
	"dome:clouds_visible", "dome:clouds_cumulus_visible",
	"env:fog_enabled", "env:fog_mode", "env:volumetric_fog_enabled",
	"env:adjustment_enabled",
]


## Which node a composed key is written to. `fx:` keys belong to this package
## and are returned as an empty string.
static func target_for(key: String) -> String:
	if key.begins_with(SKY_PREFIX):
		return "sky"
	if key.begins_with(DOME_PREFIX):
		return "dome"
	if key.begins_with(ENV_PREFIX):
		return "env"
	return ""


static func property_for(key: String) -> StringName:
	return StringName(key.substr(key.find(":") + 1))


static func is_step_key(key: String) -> bool:
	return STEP_KEYS.has(key)


static func is_discrete(key: String) -> bool:
	return DISCRETE_KEYS.has(key)
