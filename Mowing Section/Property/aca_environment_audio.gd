class_name ACAEnvironmentAudio
extends Node
## ROLE
## THE AIR. Wind, wildlife and the far half of the rain, mixed from whatever the
## sky is currently doing and from the property standing under it.
##
## ---------------------------------------------------------------------------
## WHAT THIS IS NOT
## ---------------------------------------------------------------------------
## Not a weather authority. It never decides what the weather is, never sets it,
## and never keeps a state of its own: it listens to `WorldClock.weather_changed`
## and reads `WorldClock.weather_preset()`, which is the same chain the sky, the
## ground wetness and the rain particles are already driven from.
##
## Not a second ambience owner either. The mowing scene's existing ambience bed
## and the `Rain_Handler`'s near-rain layer both keep doing exactly what they
## did; this adds the layers NOTHING owned - wind, and rain heard at a distance.
##
## And not music. Every source here is a recording of moving air or falling
## water. There is no tonal material in this project and there must not be.
##
## ---------------------------------------------------------------------------
## THREE BEDS, CROSS-FADED
## ---------------------------------------------------------------------------
##   WIND        under everything, quietest on a still clear morning and
##               strongest in rain. It is what makes an overcast lawn sound
##               different from a bright one when neither has anything falling.
##   WILDLIFE    birds and insects. Loud in the clear, gone in heavy rain -
##               which is what actually happens, and doing it makes the weather
##               audible even with the machine switched off.
##   FAR RAIN    the DEPTH of a shower. `Rain_Handler` owns rain heard from
##               under it; this is rain heard across a field, so `Light Rain`
##               is mostly this and `Rain` is both.
##
## Every level crosses over a fade rather than switching, so a block boundary in
## the weather schedule is a change in the air rather than an edit.
##
## ---------------------------------------------------------------------------
## THE PROPERTY COLOURS IT
## ---------------------------------------------------------------------------
## A wooded property is full of birds and sheltered from the wind; an open one
## is the other way round. Both numbers already exist on `ACAPropertyParams` and
## are what the FOLIAGE is generated from, so the sound of a place and the look
## of it come from the same two values and cannot disagree.
##
## PUBLIC API
##   bind(params)      set the property colouring; safe to call with null
##   set_muted(on)     for the trailer and the probes
##
## SIGNALS: None.
##
## INVARIANTS
##   * THREE AudioStreamPlayers, for the whole contract. Nothing is spawned.
##   * Every player is routed to a bus the player's own volume sliders already
##     move - Ambience for wind and wildlife, Weather for far rain.
##
## PERSISTENCE OWNERSHIP: None.

const SOUNDS := "res://Assets/Sounds/"

const WIND_STREAM := SOUNDS + "freesound_community-a-gentle-breeze-wind-1-14813.mp3"
const WILDLIFE_STREAM := SOUNDS + "chribonn-nature-216798.mp3"
const FAR_RAIN_STREAM := SOUNDS + "freesound_community-soft-rain-on-a-tile-roof-14515.mp3"

## Level at full weight, in decibels, per bed. Beds, not events: all three sit
## under the machine, and the mower is the loudest thing in the game while it is
## running. `ACAAudioMix` owns the balance between the FAMILIES; these are the
## levels inside this one.
const WIND_FULL_DB := -9.0
const WILDLIFE_FULL_DB := -13.0
const FAR_RAIN_FULL_DB := -8.0

## Below this weight a bed is silent rather than very quiet. A bed nobody can
## hear is still a voice being mixed.
const SILENT_DB := -60.0
const AUDIBLE_WEIGHT := 0.02

## How fast a bed crosses to a new level, in decibels per second. Slow enough
## that a weather block boundary is a change in the air rather than an edit, and
## fast enough that arriving in a shower does not take ten seconds to hear.
##
## Measured rather than guessed: at 6.0 the far-rain bed took EIGHT SECONDS to
## climb from silence to its level, against the `Rain_Handler`'s own two-second
## fade on the near layer - so the two halves of the same shower arrived at
## visibly different times. At 12.0 the far layer is up in about four.
const FADE_DB_PER_SECOND := 12.0

## ---------------------------------------------------------------------------
## THE MIX, PER SKY
## ---------------------------------------------------------------------------
## `[wind, wildlife, far rain]`, each 0 - 1. Read against the eight presets
## `ACAWorldClock` can actually schedule; an unknown one falls back to Clear
## rather than to silence.
##
## The shape of this table is the argument for it. Wind RISES monotonically with
## how unsettled the sky is; wildlife FALLS; rain appears only where there is
## water in the air. Nothing is dramatic, and `Clearing` - the bright block
## after a wet one - is deliberately the loudest wildlife in the game, because a
## garden after rain is.
const MIX := {
	"Clear": [0.22, 1.00, 0.0],
	"Partly Cloudy": [0.34, 0.88, 0.0],
	"Overcast": [0.58, 0.42, 0.0],
	"Mist": [0.30, 0.34, 0.0],
	"Foggy": [0.26, 0.22, 0.0],
	"Light Rain": [0.44, 0.14, 0.80],
	"Rain": [0.76, 0.04, 1.00],
	"Clearing": [0.40, 1.00, 0.18],
}

var _wind: AudioStreamPlayer = null
var _wildlife: AudioStreamPlayer = null
var _far_rain: AudioStreamPlayer = null

## `[wind, wildlife, far rain]` weights the property applies on top of the sky.
var _place := Vector3(1.0, 1.0, 1.0)
var _muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_wind = _make_player("Wind", WIND_STREAM, ACAAudioMix.AMBIENCE)
	_wildlife = _make_player("Wildlife", WILDLIFE_STREAM, ACAAudioMix.AMBIENCE)
	_far_rain = _make_player("Far Rain", FAR_RAIN_STREAM, ACAAudioMix.WEATHER)
	# START WHERE THE SKY ALREADY IS. Fading up from silence on arrival would
	# make every contract begin in a dead world for two seconds.
	_apply(_weights(), true)
	var clock := get_node_or_null(^"/root/WorldClock")
	if clock != null and not clock.weather_changed.is_connected(_on_weather_changed):
		clock.weather_changed.connect(_on_weather_changed)


func _exit_tree() -> void:
	var clock := get_node_or_null(^"/root/WorldClock")
	if clock != null and clock.weather_changed.is_connected(_on_weather_changed):
		clock.weather_changed.disconnect(_on_weather_changed)


## HOW THIS PLACE SOUNDS, before the weather is applied. Wooded properties are
## full of birds and sheltered; open ones are windy and quieter. Both values are
## the ones the foliage was generated from.
func bind(params: ACAPropertyParams) -> void:
	if params == null:
		_place = Vector3(1.0, 1.0, 1.0)
		return
	var forest := clampf(params.forestiness, 0.0, 1.0)
	_place = Vector3(
		lerpf(1.25, 0.72, forest),   # wind: open ground carries it
		lerpf(0.70, 1.30, forest),   # wildlife: a wood is where the birds are
		1.0)                          # rain falls the same everywhere


func set_muted(value: bool) -> void:
	_muted = value
	_apply(_weights(), true)


func _on_weather_changed(_preset: String) -> void:
	# Nothing to do beyond letting `_process` walk the levels across. The signal
	# is connected so this node does not have to poll the clock.
	pass


func _process(delta: float) -> void:
	_apply(_weights(), false, delta)


## The sky's row, multiplied by the place. Clamped, because a wooded property
## in `Clearing` would otherwise ask for 1.3 of a full-weight bed.
func _weights() -> Vector3:
	if _muted:
		return Vector3.ZERO
	var clock := get_node_or_null(^"/root/WorldClock")
	var preset := "Clear"
	if clock != null:
		preset = String(clock.call(&"weather_preset"))
	var row: Array = MIX.get(preset, MIX["Clear"])
	return Vector3(
		clampf(float(row[0]) * _place.x, 0.0, 1.0),
		clampf(float(row[1]) * _place.y, 0.0, 1.0),
		clampf(float(row[2]) * _place.z, 0.0, 1.0))


func _apply(weights: Vector3, immediate: bool, delta: float = 0.0) -> void:
	_set_bed(_wind, weights.x, WIND_FULL_DB, immediate, delta)
	_set_bed(_wildlife, weights.y, WILDLIFE_FULL_DB, immediate, delta)
	_set_bed(_far_rain, weights.z, FAR_RAIN_FULL_DB, immediate, delta)


## A bed's level, walked at a fixed decibels per second rather than lerped, so
## the time a cross-fade takes is a number rather than a consequence of the
## frame rate. A bed at zero weight is STOPPED, not merely quiet: an inaudible
## loop is still a voice and still a decode.
func _set_bed(player: AudioStreamPlayer, weight: float, full_db: float,
		immediate: bool, delta: float) -> void:
	if player == null:
		return
	var audible := weight > AUDIBLE_WEIGHT
	var wanted: float = SILENT_DB
	if audible:
		# Weight applied in decibels, so a half-weight bed is half as loud
		# rather than 6 dB down from full and still dominant.
		wanted = full_db + linear_to_db(clampf(weight, 0.0, 1.0))

	if immediate:
		player.volume_db = wanted
	else:
		player.volume_db = move_toward(player.volume_db, wanted,
			FADE_DB_PER_SECOND * delta)

	if audible and not player.playing:
		player.play()
	elif not audible and player.playing and player.volume_db <= SILENT_DB + 0.5:
		player.stop()


func _make_player(node_name: String, path: String,
		bus: StringName) -> AudioStreamPlayer:
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("[ENV AUDIO] could not load %s" % path)
		return null
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.bus = bus
	player.volume_db = SILENT_DB
	add_child(player)
	return player
