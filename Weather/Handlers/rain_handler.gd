#@tool # comment this out when debugging is done. 
extends Node3D
class_name Rain_Handler

@onready var near_rain: GPUParticles3D = $"Near Rain"
@onready var far_rain: GPUParticles3D = $"Far Rain"

@export var near_rain_max_ratio: float = 1.0
@export var far_rain_max_ratio: float = 0.6

@export var rain_transition_duration: float = 2.0

# for debugging
@export var toggle_rain_smooth:bool = false

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

var audio_transition_tween: Tween = null

# set a default value. Ideally this should be changed withing the first few frames of use
var mower_position: Vector3 = Vector3.ZERO

var rain_transition_tween: Tween = null
var is_raining: bool = false


func _ready() -> void:
	global_position = mower_position
	near_rain.local_coords = false
	far_rain.local_coords = false
	if near_rain:
		near_rain.amount_ratio = 0.0
		near_rain.emitting = false

	if far_rain:
		far_rain.amount_ratio = 0.0
		far_rain.emitting = false
	
	# handle audio
	if rain_audio:
		rain_audio.volume_db = rain_audio_silent_db
		if rain_audio.stream:
			rain_audio.play()


func _process(delta: float) -> void:
	if toggle_rain_smooth:
		toggle_rain_smooth = false
		if is_raining:
			stop_rain()
		else:
			start_rain()

func set_ambience_sound_player(ambience_stream_player:AudioStreamPlayer):
	base_ambience_audio = ambience_stream_player
	# Capture the AUTHORED level once. Everything after this is relative to it,
	# so Clear always returns to the mix the scene was authored with.
	if base_ambience_audio != null:
		ambience_base_db = base_ambience_audio.volume_db

@export var rain_offset: Vector3 = Vector3(0, 10, 0)

func set_mower_global_position(mower_global_pos: Vector3) -> void:
	mower_position = mower_global_pos
	global_position = mower_position + rain_offset

func _____RAIN_____():
	pass

func start_rain(duration: float = -1.0) -> void:
	_transition_rain(true, duration)
	_transition_rain_audio(true, duration)


func stop_rain(duration: float = -1.0) -> void:
	_transition_rain(false, duration)
	_transition_rain_audio(false, duration)


func _transition_rain(enable: bool, duration: float = -1.0) -> void:
	if duration < 0.0:
		duration = rain_transition_duration

	if rain_transition_tween:
		rain_transition_tween.kill()
		rain_transition_tween = null

	is_raining = enable

	if enable:
		if near_rain:
			near_rain.emitting = true
		if far_rain:
			far_rain.emitting = true

	rain_transition_tween = create_tween()
	rain_transition_tween.set_trans(Tween.TRANS_SINE)
	rain_transition_tween.set_ease(Tween.EASE_IN_OUT)
	rain_transition_tween.set_parallel(true)

	if near_rain:
		rain_transition_tween.tween_property(
			near_rain,
			"amount_ratio",
			near_rain_max_ratio if enable else 0.0,
			duration
		)

	if far_rain:
		rain_transition_tween.tween_property(
			far_rain,
			"amount_ratio",
			far_rain_max_ratio if enable else 0.0,
			duration
		)

	if not enable:
		rain_transition_tween.chain().tween_callback(_finish_stopping_rain)


func _finish_stopping_rain() -> void:
	if near_rain:
		near_rain.emitting = false
	if far_rain:
		far_rain.emitting = false


func start_rain_instant() -> void:
	if rain_transition_tween:
		rain_transition_tween.kill()
		rain_transition_tween = null

	is_raining = true

	if near_rain:
		near_rain.emitting = true
		near_rain.amount_ratio = near_rain_max_ratio

	if far_rain:
		far_rain.emitting = true
		far_rain.amount_ratio = far_rain_max_ratio


func stop_rain_instant() -> void:
	if rain_transition_tween:
		rain_transition_tween.kill()
		rain_transition_tween = null

	is_raining = false

	if near_rain:
		near_rain.amount_ratio = 0.0
		near_rain.emitting = false

	if far_rain:
		far_rain.amount_ratio = 0.0
		far_rain.emitting = false

	# Audio has to snap too, or a scene loaded in Clear could start ducked from
	# whatever the previous state was mid-tween.
	reset_ambience_level()


func _____AUDIO______():
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
