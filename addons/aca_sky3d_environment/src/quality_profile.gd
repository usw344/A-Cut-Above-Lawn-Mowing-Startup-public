@tool
class_name ACAEnvQualityProfile
extends Resource
## WHAT THE MACHINE IS ALLOWED TO SPEND.
##
## A quality level in this package REMOVES WORK. It does not scale a number and
## hope. Each flag below switches off a whole GPU mechanism:
##
##   * `use_volumetric_fog`   — a froxel volume integrated every frame.
##   * `use_depth_fog`        — a full-screen Environment fog pass.
##   * `use_aerial`           — Sky3D's own screen-space scattering quad, which
##                              reads the depth and screen textures.
##   * `rain_layers`          — whole GPUParticles3D emitters, not ratios.
##
## The shipped three are measured, not asserted: `Weather Matrix` reports fps
## per weather per level, and the numbers are in the worklog. If two levels ever
## measure the same, one of them is a lie and should be deleted.

@export var id: StringName = &"High"
@export var display_name: String = "High"

@export_group("Fog mechanisms")
## Godot Environment depth + height fog. The one that carries RANGE, and the
## one with `fog_sky_affect`. Cheap; on at every level.
@export var use_depth_fog: bool = true
## Sky3D's `AtmFog.gdshader` quad. Moderate: a screen-space pass sampling the
## depth and screen textures. It is what makes distance the same COLOUR as the
## sky, so it is the last thing to go.
@export var use_aerial: bool = true
## Real light scattering through a froxel volume. Expensive.
@export var use_volumetric_fog: bool = false
@export_range(0.0, 4.0, 0.01) var volumetric_density_scale: float = 1.0
@export_range(16.0, 512.0, 1.0) var volumetric_length: float = 96.0
@export_range(0.5, 4.0, 0.1) var volumetric_detail_spread: float = 2.0

@export_group("Fog tuning")
## Scales the composed depth-fog density. Lets a lower level keep the LOOK of
## fog while integrating less of it.
@export_range(0.0, 4.0, 0.01) var depth_fog_density_scale: float = 1.0
## Scales height-fog density independently: it is the part that costs least and
## reads most, so it survives when the rest is trimmed.
@export_range(0.0, 4.0, 0.01) var height_fog_density_scale: float = 1.0

@export_group("Precipitation")
## 1 = near only, 2 = near + mid, 3 = near + mid + far. Whole emitters.
@export_range(0, 3, 1) var rain_layers: int = 3
@export_range(0.0, 2.0, 0.01) var rain_amount_scale: float = 1.0
## Short-lived ground impacts around the tracking target. A fourth emitter.
@export var rain_splash: bool = false

@export_group("Update rate")
## Seconds between recompositions. Sky3D itself updates at 0.1 s, so anything
## below that is spent for nothing.
@export_range(0.016, 0.5, 0.001) var update_interval: float = 0.05
