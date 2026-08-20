class_name ACAAudioMix
## THE project's audio mix. Bus names, the static balance between them, and the
## one function that applies a player's volume setting to a bus.
##
## Not a node and not an autoload - there is no per-frame audio logic in this
## project and there must not be. A source's level is authored once, the balance
## between families of sources is a BUS TRIM here, and the player's sliders
## scale a bus on top of that.
##
## ---------------------------------------------------------------------------
## THE BUSES  (res://default_bus_layout.tres)
## ---------------------------------------------------------------------------
##
##     Master
##       |- Mower       every mower's AudioStreamPlayer3D
##       |- Ambience    the mowing scene's ambience bed
##       |- Weather     rain, and any future precipitation audio
##       +- UI          reserved; nothing plays on it yet
##
## Routing is set on the AudioStreamPlayer nodes in their own scenes, not in
## code. Adding a sound means picking its bus in the scene, never adding a
## volume rule somewhere.
##
## ---------------------------------------------------------------------------
## WHY THE TRIMS LIVE HERE AND NOT IN THE .tres
## ---------------------------------------------------------------------------
## `AudioServer` has exactly one volume per bus, and `GameSettings` writes it
## from the player's slider. If the authored balance also lived in the layout
## resource the first settings apply would wipe it. So the layout ships every
## bus at 0 dB and the balance is applied WITH the slider value, here.

const MASTER := &"Master"
const MOWER := &"Mower"
const AMBIENCE := &"Ambience"
const WEATHER := &"Weather"
const UI := &"UI"

## Every bus this project expects, in layout order.
const BUSES: Array[StringName] = [MASTER, MOWER, AMBIENCE, WEATHER, UI]

# ---------------------------------------------------------------------- TRIMS
##
## THE MIX. Decibels applied to a whole family of sources, on top of whatever
## the player's slider asks for. Measured, not guessed: run
##
##     Dev tools/Validation/Audio Mix Probe.tscn
##
## which plays the real scene in each weather state and prints the peak level
## each bus actually reaches. The targets it asserts are in that file.
##
## The mower is the loudest thing in the game while it is running, because it is
## what the player is doing. Rain has to read as heavy weather without burying
## it, and the ambience bed sits under both.
## Measured 2026-08-19 with the probe at the shipped default sliders
## (master 0.8, mower 0.8, ambience 0.7). Raw source peaks in the mowing scene
## were mower -23.4 dBFS, ambience -21.4 dBFS, rain -22.4 dBFS - everything was
## quiet, and the mix sat around -25 dBFS on Master with nothing on top of
## anything. The trims lift the whole thing into useful headroom AND set the
## relationship, which is the part that matters:
##
##     mowing engine   about -11 dBFS   <- the loudest thing, in every weather
##     heavy rain      about -15 dBFS   <- clearly heavy, about 4 dB under it
##     idling engine   about -20 dBFS
##     clear ambience  about -19 dBFS   <- a bed, never a competitor
const TRIM_DB := {
	MASTER: 0.0,
	MOWER: 14.0,
	AMBIENCE: 5.0,
	WEATHER: 10.0,
	UI: 0.0,
}


## Apply a 0.0 - 1.0 setting to a bus, combined with that bus's trim.
## A missing bus is not an error: the value is simply stored by GameSettings and
## takes effect if the bus is ever added.
static func apply_volume(bus: StringName, linear: float) -> bool:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return false
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(index, v <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.001)) + trim_db(bus))
	return true


static func trim_db(bus: StringName) -> float:
	return float(TRIM_DB.get(bus, 0.0))


static func has_bus(bus: StringName) -> bool:
	return AudioServer.get_bus_index(bus) >= 0


## Every expected bus exists. Asserted by the Weather Test - a bus that quietly
## disappears would silently make two volume sliders inert again.
static func all_buses_present() -> bool:
	for bus: StringName in BUSES:
		if not has_bus(bus):
			return false
	return true
