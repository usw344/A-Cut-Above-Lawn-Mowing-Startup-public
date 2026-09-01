class_name ACAMowerCutAudio
extends Node3D
## ROLE
## WHAT CUTTING SOUNDS LIKE. The blade-and-grass layer over the engine, and the
## load figure that makes the engine itself bog.
##
## The exact companion to `ACAMowingEffects`, and deliberately the same shape:
## bound to the same machine and the same cutter, driven by the same
## `ACAMowerCutter.cut` signal, and owning nothing the game reads. Removing this
## node changes no cut, no contract and no save - it changes what the player
## hears.
##
## ---------------------------------------------------------------------------
## LOAD IS A FRACTION, NOT A RATE
## ---------------------------------------------------------------------------
## The obvious signal is cells per second, and it is the wrong one: a rider at
## full speed cuts twice what a push mower does over the same grass, so a rate
## would make the rider sound permanently under heavier load than the push
## mower on the identical lawn.
##
## What the blades actually feel is HOW MUCH OF THE GROUND THEY JUST SWEPT WAS
## STANDING GRASS. So the load is
##
##     cells cut  /  (deck width x distance travelled)
##
## which is dimensionless, is 1.0 for a machine of any size driving through
## uncut grass, and is 0.0 for one crossing ground it has already cut. That is
## exactly the difference a player should be able to hear between working and
## travelling.
##
## A mowing cell is one square world unit, so cells and swept square units are
## directly comparable - the same fact `ACAMowerCutter.coverage()` relies on.
##
## PUBLIC API
##   bind(mower, cutter) / unbind()
##   on_cut(cells)                  the signal target
##   load() -> float                what the engine is being told, 0 - 1
##
## SIGNALS: None.
##
## INVARIANTS
##   * ONE AudioStreamPlayer3D, for the whole property, for the whole contract.
##     Nothing here is spawned per cell, per tuft or per cut.
##   * Nothing is read by gameplay. `set_cut_load()` reaches only presentation.
##
## PERSISTENCE OWNERSHIP: None.

## Further than a machine travels in one physics step at any sane speed. A jump
## larger than this is a placement - a save being restored, a shot being staged
## - and cutting a stripe of load out of it would be wrong for the same reason
## `ACAMowerCutter` refuses to cut across one.
const REPOSITION_DISTANCE := 6.0

## Below this the machine is effectively stationary and the fraction's
## denominator is noise. The load simply decays instead.
const MIN_TRAVEL := 0.02

## ---------------------------------------------------------------------------
## THE RATIO IS MEASURED OVER A WINDOW, NOT OVER A FRAME
## ---------------------------------------------------------------------------
## `ACAMowerCutter.cut` arrives in BURSTS. Measured on a rider driving flat out
## through standing grass: about SEVEN emissions per hundred and twenty rendered
## frames, each carrying several cells at once. So on any single frame the ratio
## is either zero - because no burst landed in it - or enormous, and neither is
## the answer.
##
## Over a fifth of a second the same drive reads 0.78 to 1.12, which is the
## right answer and a stable one. That is what this window is: long enough to
## contain several bursts, short enough that coming off standing grass is heard
## immediately.
##
## The first implementation divided per frame and produced a load of 0.025 on a
## machine cutting a whole lawn.
const WINDOW_SECONDS := 0.2

var _mower: Node3D = null
var _cutter: ACAMowerCutter = null
var _player: AudioStreamPlayer3D = null

## Cells reported and ground swept since the last envelope step. Both are reset
## every step, so this is a rate over one frame rather than a running total.
var _cells := 0.0
var _swept := 0.0
## Seconds accumulated into the current window, and the ratio the last window
## produced.
var _window := 0.0
var _target := 0.0
var _previous := Vector3.ZERO
var _has_previous := false

## The eased load. `ACAMowerAudio` owns the attack and release rates.
var _load := 0.0
var _profile: Dictionary = ACAMowerAudio.FALLBACK


func _ready() -> void:
	set_process(true)


func bind(mower: Node3D, cutter: ACAMowerCutter) -> void:
	unbind()
	_mower = mower
	_cutter = cutter
	if mower == null or cutter == null:
		return

	var id := StringName(String(mower.get(&"MOWER_ID")))
	_profile = ACAMowerAudio.profile(id)

	_player = AudioStreamPlayer3D.new()
	_player.name = "Cut Layer"
	_player.stream = ACAMowerAudio.cut_stream()
	# THE SAME BUS AS THE ENGINE. This is the machine making a noise, so the
	# player's Mower slider has to move it, and `ACAAudioMix` has to balance it
	# against everything else in the same place it balances the engine.
	_player.bus = ACAAudioMix.MOWER
	_player.pitch_scale = float(_profile["cut_pitch"])
	_player.volume_db = ACAMowerAudio.ENGINE_OFF_DB
	# It comes from under the deck, so it is heard from where the cutting is.
	var deck := cutter.deck()
	_player.position = Vector3(0.0, 0.05, deck.forward_offset)
	add_child(_player)
	_player.play()

	_previous = mower.global_position
	_has_previous = true


func unbind() -> void:
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
	_mower = null
	_cutter = null
	_load = 0.0
	_cells = 0.0
	_swept = 0.0
	_has_previous = false


func load_amount() -> float:
	return _load


## The cutter's own signal. It arrives in bursts at the physics rate and stops
## dead between passes; accumulating here and reading once per frame is what
## turns that into something an envelope can follow.
func on_cut(cells: int) -> void:
	_cells += float(maxi(cells, 0))


func _process(delta: float) -> void:
	if _mower == null or not is_instance_valid(_mower):
		return

	_accumulate_travel()
	_window += delta
	if _window >= WINDOW_SECONDS:
		# The ratio over the WHOLE window, not over one frame. See WINDOW_SECONDS.
		_target = clampf(_cells / _swept, 0.0, 1.0) if _swept > 0.0 else 0.0
		_cells = 0.0
		_swept = 0.0
		_window = 0.0

	_load = ACAMowerAudio.settle_load(_load, _target, delta)

	# THE MACHINE IS TOLD, AND IT DOES THE REST. The engine's bog and its extra
	# body are `ACAMowerAudio`'s arithmetic inside the controller; this only
	# supplies the number, which keeps one description of how a mower sounds.
	if _mower.has_method(&"set_cut_load"):
		_mower.call(&"set_cut_load", _load)

	if _player == null:
		return
	_player.global_position = _mower.global_position + Vector3(0.0, 0.05, 0.0)
	var wanted := ACAMowerAudio.cut_volume_db(_profile, _load)
	# The layer chases at the machine's own response rate, so a rider's blade
	# noise swells in the way a rider's engine does.
	_player.volume_db = lerpf(_player.volume_db, wanted,
		clampf(float(_profile["response"]) * delta, 0.0, 1.0))


## Ground swept since the last frame: the deck's width times how far the machine
## moved. The distance is measured on the XZ plane, because a machine cresting a
## rise has not swept the vertical part of it.
func _accumulate_travel() -> void:
	var here := _mower.global_position
	if not _has_previous:
		_previous = here
		_has_previous = true
		return
	var moved := Vector2(here.x - _previous.x, here.z - _previous.z).length()
	_previous = here
	if moved > REPOSITION_DISTANCE or moved < MIN_TRAVEL:
		return
	var deck := _cutter.deck() if _cutter != null else null
	var width: float = deck.half_width * 2.0 if deck != null else 1.0
	_swept += moved * maxf(width, 0.1)
