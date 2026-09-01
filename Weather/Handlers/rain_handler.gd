extends Node3D
class_name Rain_Handler
## A Cut Above's rain: the PACKAGE's precipitation rig, plus this project's own
## audio.
##
## ---------------------------------------------------------------------------
## WHAT CHANGED, AND WHY THE PARTICLES ARE NOT IN THE SCENE ANY MORE
## ---------------------------------------------------------------------------
##
## This used to own two authored `GPUParticles3D` nodes, `Near Rain` and
## `Far Rain`. `Far Rain` was the SAME particle scene as `Near Rain` scaled by
## **24**, and the draw pass was a `RibbonTrailMesh` 0.2 units wide — so every
## distant drop was a four-and-a-half-metre white ribbon. Rendered, that is the
## curtain of white rods across the baseline frames: dead vertical, evenly
## spaced, straight through the trees and the ground.
##
## The particles are now `ACAPrecipitationRig` from
## `res://addons/aca_sky3d_environment/`, built in code as three layers whose
## distance is expressed in ALPHA AND COUNT rather than in size, and oriented
## along their own velocity so wind tilts them.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE STILL OWNS
## ---------------------------------------------------------------------------
##
## The AUDIO, which is deliberately not in the package: `Assets/Sounds/` has
## unresolved attribution (R-016) and must not be bundled into something
## redistributable. What IS and IS NOT established is now written down, per
## file, in `Credits/Audio_credits.txt` - the near-rain layer this file plays is
## in its "unresolved" section. The package accepts a player it is handed and fades it; the
## ambience duck below is ours.
##
## The public API is unchanged. `preset_manager`, `MVP`, the trailer's weather
## adapter and `Weather Test` all call exactly what they called before.

# ------------------------------------------------------------------- AUDIO
#
# The rain stream plays on the **Weather** bus and the ambience bed on
# **Ambience** (see Game/App/audio_mix.gd). The balance between rain, ambience
# and the mower engine is a BUS TRIM, not a value here. What this file owns is
# only the fade in and out, and a gentle duck of the ambience while it rains.
#
# Changed 2026-08-19 (Milestone 9): the duck used to write ABSOLUTE decibels on
# to the ambience player - `ambience_clear_db = 0.0`. The ambience is authored
# at -16.855 dB, so the first Rain -> Clear transition raised it by nearly 17 dB
# and left it there permanently. The duck is now RELATIVE to whatever the
# player was authored at, which is captured once when it is handed over.
@onready var rain_audio: AudioStreamPlayer = $AudioStreamPlayer
var base_ambience_audio: AudioStreamPlayer
## The ambience player's authored level, captured on hand-over. The duck is
## always relative to this, so Clear always returns to exactly the authored mix.
var ambience_base_db: float = 0.0

@export var rain_audio_target_db: float = -6.0
@export var rain_audio_silent_db: float = -40.0
## How far the ambience bed steps down underneath heavy rain. Relative.
@export var ambience_rain_duck_db: float = -7.0

# ---------------------------------------------------------------- INTENSITY
## Rain intensity at full strength. Kept as an export because the trailer's
## weather adapter raises it for one shot.
@export var near_rain_max_ratio: float = 1.0
## COMPATIBILITY. The rig has no separate far emitter ratio — distance is a
## property of its layers, not a second slider. Retained so the trailer adapter
## and anything else that saved and restored it keeps working.
@export var far_rain_max_ratio: float = 0.6

@export var rain_transition_duration: float = 2.0

# for debugging
@export var toggle_rain_smooth: bool = false

## Where the rig sits relative to whatever it is following.
@export var rain_offset: Vector3 = Vector3(0, 10, 0)

## The rain rig, created in code so there is no particle scene to keep in sync.
var rig: ACAPrecipitationRig = null

# set a default value. Ideally this should be changed within the first few
# frames of use.
var mower_position: Vector3 = Vector3.ZERO

var audio_transition_tween: Tween = null
var is_raining: bool = false


func _ready() -> void:
	global_position = mower_position

	rig = ACAPrecipitationRig.new()
	rig.name = "Precipitation"
	add_child(rig)
	rig.apply_immediate(0.0)

	# handle audio
	if rain_audio:
		rain_audio.volume_db = rain_audio_silent_db
		if rain_audio.stream:
			rain_audio.play()


func _process(_delta: float) -> void:
	if toggle_rain_smooth:
		toggle_rain_smooth = false
		if is_raining:
			stop_rain()
		else:
			start_rain()


func set_ambience_sound_player(ambience_stream_player: AudioStreamPlayer) -> void:
	base_ambience_audio = ambience_stream_player
	# Capture the AUTHORED level once. Everything after this is relative to it,
	# so Clear always returns to the mix the scene was authored with.
	if base_ambience_audio != null:
		ambience_base_db = base_ambience_audio.volume_db


## What the rain follows. The mowing scene passes its CAMERA: the drops the
## player sees are the ones near the lens, not the ones near the machine.
func set_tracking_target(node: Node3D) -> void:
	if rig != null:
		rig.set_tracking_target(node)


## Quality comes from the environment adapter, which owns the profile set.
func set_quality(profile: ACAEnvQualityProfile) -> void:
	if rig != null:
		rig.set_quality(profile)


func set_mower_global_position(mower_global_pos: Vector3) -> void:
	mower_position = mower_global_pos
	# Only meaningful when nothing else is tracking; the rig repositions itself
	# when it has a target. Kept because `Weather Test` reads `mower_position`
	# to prove the rain is following the machine rather than the origin.
	global_position = mower_position + rain_offset


func _____RAIN_____() -> void:
	pass


func start_rain(duration: float = -1.0) -> void:
	is_raining = true
	_apply_intensity(duration)
	_transition_rain_audio(true, duration)


func stop_rain(duration: float = -1.0) -> void:
	is_raining = false
	_apply_intensity(duration)
	_transition_rain_audio(false, duration)


## The rig eases on its own exponential approach rather than on a tween, so a
## "duration" here is converted to an equivalent rate. Two overlapping weather
## changes therefore cannot leave a stale tween writing old values.
func _apply_intensity(duration: float) -> void:
	if rig == null:
		return
	if duration < 0.0:
		duration = rain_transition_duration
	rig.fade_speed = 3.0 / maxf(duration, 0.05)
	rig.set_intensity(near_rain_max_ratio if is_raining else 0.0)


func start_rain_instant() -> void:
	is_raining = true
	if rig != null:
		rig.apply_immediate(near_rain_max_ratio)


func stop_rain_instant() -> void:
	is_raining = false
	if rig != null:
		rig.apply_immediate(0.0)

	# Audio has to snap too, or a scene loaded in Clear could start ducked from
	# whatever the state was mid-tween.
	reset_ambience_level()


func _____AUDIO______() -> void:
	pass


func _transition_rain_audio(enable: bool, duration: float = -1.0) -> void:
	if duration < 0.0:
		duration = rain_transition_duration

	if audio_transition_tween:
		audio_transition_tween.kill()
		audio_transition_tween = null

	audio_transition_tween = create_tween()
	audio_transition_tween.set_trans(Tween.TRANS_SINE)
	audio_transition_tween.set_ease(Tween.EASE_IN_OUT)
	audio_transition_tween.set_parallel(true)

	if rain_audio:
		audio_transition_tween.tween_property(
			rain_audio,
			"volume_db",
			rain_audio_target_db if enable else rain_audio_silent_db,
			duration
		)

	if base_ambience_audio:
		audio_transition_tween.tween_property(
			base_ambience_audio,
			"volume_db",
			ambience_base_db + (ambience_rain_duck_db if enable else 0.0),
			duration
		)


## Put the ambience bed back to its authored level with no transition. Used by
## the instant paths, so a scene that loads in Clear never starts ducked.
func reset_ambience_level() -> void:
	if audio_transition_tween:
		audio_transition_tween.kill()
		audio_transition_tween = null
	if base_ambience_audio != null:
		base_ambience_audio.volume_db = ambience_base_db
	if rain_audio != null:
		rain_audio.volume_db = rain_audio_silent_db
