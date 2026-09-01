class_name ACAUISound
extends RefCounted
## ROLE
## WHAT THE INTERFACE SOUNDS LIKE. One table of cues, the clips behind each, and
## the two rules that stop a set of sixteen short samples turning into an arcade
## cabinet.
##
## The same shape as `ACAMowerHandling` and `ACAMowerAudio`: a table plus the
## arithmetic that reads it, never instantiated, owning no state. The PLAYERS
## live on `AppUI`, which is already the authority for everything that sits over
## a screen; there is no new autoload here and no second place a sound can be
## started from.
##
## ---------------------------------------------------------------------------
## THE UI BUS WAS EMPTY
## ---------------------------------------------------------------------------
## `default_bus_layout.tres` has carried a `UI` bus since the mix was authored,
## commented `reserved; nothing plays on it yet`. It is not reserved any more.
## Everything here is routed to it, so the existing Master slider moves it and
## `ACAAudioMix` balances it against the machine and the weather in the one
## place that balance is decided.
##
## ---------------------------------------------------------------------------
## RESTRAINT IS THE DESIGN
## ---------------------------------------------------------------------------
## Two rules, and they matter more than the choice of clips:
##
##   A CUE HAS A FLOOR.  The same cue cannot retrigger within `REPEAT_GUARD`
##   seconds. Without it, dragging a cursor along a row of buttons fires the
##   hover cue thirty times a second, and a settings slider machine-guns.
##
##   VARIATION IS FREE.  Cues with more than one clip pick at random and never
##   the same clip twice running, and every cue is pitched by a few per cent.
##   Sixteen samples with that on top do not read as sixteen samples.
##
## THE LEVELS ARE PER RECORDING, NOT PER CUE, and they do not look like a set
## because the clips do not. Measured on the UI bus with every cue at the same
## authored level, the spread between the loudest and the quietest of them was
## THIRTY-SEVEN DECIBELS. The numbers in the table are what brings them level;
## reading them as a design intent rather than as a calibration is a mistake.
##
## HOVER IS DELIBERATELY QUIET - a tick under everything else, twelve decibels
## below a click. A hover cue at the same level as a press is the single
## fastest way to make an interface exhausting.
##
## PUBLIC API
##   ACAUISound.CUES                    the table
##   ACAUISound.clips(cue)              the paths for a cue
##   ACAUISound.clip_path(cue, i)
##   ACAUISound.level_db(cue)
##   ACAUISound.pitch_for(cue, rng)
##
## SIGNALS: None.
##
## PERSISTENCE OWNERSHIP: None. Authored constants; volume is `GameSettings`.

const UI_SOUNDS := "res://Assets/Sounds/UI/"

## Named cues, not file names. A screen asks for `&"confirm"`; which recording
## that is stays here, so re-picking a sound is one edit and never forty-six.
const HOVER := &"hover"
const CLICK := &"click"
const CONFIRM := &"confirm"
const CANCEL := &"cancel"
const ERROR := &"error"
const NOTIFY := &"notify"
const MONEY := &"money"
const COMPLETE := &"complete"

## ---------------------------------------------------------------------------
## THE CLIPS IN A CUE HAVE TO BE THE SAME LOUDNESS AS EACH OTHER
## ---------------------------------------------------------------------------
## Measured, one clip at a time, on the UI bus (a temporary runner, removed
## afterwards):
##
##     confirmation_001  -7.1    close_001   -7.3    error_003   -6.8
##     glass_004        -12.0    select_003 -14.0    bong_001   -14.7
##     rollover1        -14.2    rollover6  -18.7    toggle_001 -21.3
##     rollover4        -22.9    error_002  -31.2    rollover5  -35.7
##     glass_002        -38.9    drop_002   -41.1    click_001  -52.4
##
## WITHIN ONE CUE the spread reached THIRTY-FOUR DECIBELS - `cancel` was
## `close_001` at -7.3 or `drop_002` at -41.1, at random, so half its presses
## were inaudible. That is not variation, it is random loudness.
##
## Per-clip normalising gains were tried and ABANDONED: the peak meter
## under-reads short samples badly and inconsistently, so the gains derived from
## it threw the mix further out than the problem they were fixing - `error`
## measured +19.9 dBFS on one run and -7.0 on the next. What is reliable is
## which clips are CLOSE TO EACH OTHER, so a cue keeps only clips within a few
## decibels and the outliers are dropped.
##
## That leaves several cues with a single recording, and their variation is the
## pitch jitter alone. A cue that is always the same loudness and slightly
## different each time is better than one that is sometimes inaudible.
##
## CLIPS SHORTER THAN ABOUT 0.1 s ARE ALSO GONE, not because they are silent but
## because they cannot be measured at all: `rollover2` (57 ms), `tick_002`
## (23 ms), `select_001` (43 ms) and three of the five `click` samples read
## -200 dBFS, which is the meter's window rather than the file.
const CUES := {
	# Three, and the widest spread of any cue at 8.7 dB - acceptable on the one
	# sound that fires most often and matters least.
	HOVER: {
		"clips": ["res://Assets/Sounds/kenney_ui-audio (1)/Audio/rollover1.ogg",
			"res://Assets/Sounds/kenney_ui-audio (1)/Audio/rollover6.ogg",
			"res://Assets/Sounds/kenney_ui-audio (1)/Audio/rollover4.ogg"],
		"db": -11.0, "pitch": 0.05,
	},
	CLICK: {
		"clips": [UI_SOUNDS + "toggle_001.ogg"],
		"db": -3.0, "pitch": 0.04,
	},
	CONFIRM: {
		"clips": [UI_SOUNDS + "confirmation_001.ogg",
			UI_SOUNDS + "confirmation_002.ogg"],
		"db": -9.0, "pitch": 0.02,
	},
	CANCEL: {
		"clips": [UI_SOUNDS + "close_001.ogg"],
		"db": -15.0, "pitch": 0.03,
	},
	ERROR: {
		"clips": [UI_SOUNDS + "error_003.ogg"],
		"db": -12.0, "pitch": 0.02,
	},
	NOTIFY: {
		"clips": [UI_SOUNDS + "select_003.ogg"],
		"db": -8.0, "pitch": 0.03,
	},
	MONEY: {
		"clips": [UI_SOUNDS + "glass_004.ogg"],
		"db": -7.0, "pitch": 0.03,
	},
	COMPLETE: {
		"clips": [UI_SOUNDS + "bong_001.ogg"],
		"db": -4.0, "pitch": 0.01,
	},
}

## Seconds a cue must wait before it may sound again. Hover is the long one for
## the reason in the header; the rest are short enough that deliberate presses
## always sound and only a stuck key does not.
const REPEAT_GUARD := {
	HOVER: 0.09,
	CLICK: 0.05,
	CONFIRM: 0.12,
	CANCEL: 0.12,
	ERROR: 0.25,
	NOTIFY: 0.20,
	MONEY: 0.15,
	COMPLETE: 0.40,
}

## How many UI sounds may overlap. Small deliberately: past three, simultaneous
## interface sounds stop being feedback and become noise, and a fourth arriving
## in the same tenth of a second is a bug in a screen rather than something to
## be heard.
const VOICES := 3

const DEFAULT_GUARD := 0.10


static func has_cue(cue: StringName) -> bool:
	return CUES.has(cue)


static func clips(cue: StringName) -> Array:
	var entry: Dictionary = CUES.get(cue, {})
	return entry.get("clips", [])


static func clip_path(cue: StringName, index: int) -> String:
	var list: Array = clips(cue)
	if index < 0 or index >= list.size():
		return ""
	return String(list[index])


static func level_db(cue: StringName) -> float:
	var entry: Dictionary = CUES.get(cue, {})
	return float(entry.get("db", -12.0))


static func guard_seconds(cue: StringName) -> float:
	return float(REPEAT_GUARD.get(cue, DEFAULT_GUARD))


## A believable detune. Deliberately narrow: a UI click that swings a semitone
## reads as a broken sample rate, not as variety.
static func pitch_for(cue: StringName, rng: RandomNumberGenerator) -> float:
	var entry: Dictionary = CUES.get(cue, {})
	var spread := float(entry.get("pitch", 0.03))
	return 1.0 + rng.randf_range(-spread, spread)
