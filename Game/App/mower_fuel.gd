class_name ACAMowerFuel
extends Node
## THE authority for mower fuel RULES. Autoloaded as `MowerFuel`.
##
## ---------------------------------------------------------------------------
## OWNERSHIP
## ---------------------------------------------------------------------------
## STORAGE stays on `model` (`mower_fuel`, 0-100). That is what SaveService
## already persists and what the HUD accessor already reads, so nothing about
## save/load had to change. This node owns everything ELSE about fuel:
##
##   * the burn rates, and the fact that they are TIME based
##   * what "empty" means and when it is announced
##   * the refuel interface
##   * the development-only Auto Refuel helper
##
## No controller, HUD or scene may implement a burn rate of its own.
##
## ---------------------------------------------------------------------------
## POWERED vs MANUAL
## ---------------------------------------------------------------------------
## Only POWERED mowers burn gasoline. Each canonical controller declares its own
## `POWERED` constant and simply never calls `consume()` when it is false. The
## Push Mower is a manual reel mower - it is silent when stopped and its blades
## are driven by its wheels - so it has no fuel behaviour at all.
##
## ---------------------------------------------------------------------------
## WHY TIME BASED
## ---------------------------------------------------------------------------
## The old implementation added a fixed amount to a counter every PHYSICS TICK.
## This project runs physics at **576 ticks per second**, so a full tank emptied
## in about four seconds while driving. Everything here is per-second and
## multiplied by `delta`; nothing may go back to counting ticks.

# ------------------------------------------------------------------- signals
## Emitted whenever the level changes, including refuels. Cheap listeners only.
signal fuel_changed(fuel: float)
## Emitted ONCE on the transition into empty.
signal emptied()
## Emitted after any refuel. `amount` is how much actually went in.
signal refuelled(amount: float, fuel: float)
## Development-only Auto Refuel was switched on or off.
signal auto_refuel_changed(enabled: bool)

# -------------------------------------------------------------------- TUNING
##
## THE ONLY PLACE FUEL RATES ARE DEFINED. Three numbers; everything else is
## derived from them.

## Tank size. `model.mower_fuel` is in these units and the HUD divides by it.
const CAPACITY := 100.0

## Seconds of CONTINUOUS powered mowing (throttle held down) that a full tank
## lasts at the LEGACY difficulty. Eight real minutes, chosen against the Job
## System's own estimates: a Small lawn is estimated at 4.6 minutes and a Large
## lawn at 18.4, so one tank comfortably covers a small contract and a big one
## genuinely needs a refuel. See project-docs/systems/mowers-and-controls.md.
##
## Read through `full_tank_driving_seconds()`, which is where the active
## difficulty profile is applied - and it is applied THERE, once, rather than in
## the mower controllers. Each controller already multiplies `delta` by its own
## `MowerUpgrades.fuel_multiplier()`; if difficulty were applied there too the
## two would be tangled together in three places and a future mower would be
## able to forget one of them.
const FULL_TANK_DRIVING_SECONDS := 480.0

## Idle burn as a fraction of the driving burn. A powered mower left running
## still empties, but takes about 17.8 minutes to do it.
const IDLE_BURN_FRACTION := 0.45

## Below this the tank counts as empty. Guards float dust, nothing more.
const EMPTY_EPSILON := 0.0001

## How far the level has to move before `fuel_changed` is worth emitting. See
## the note in consume() - this is a signal rate limit, never a burn threshold.
const SIGNAL_DEADBAND := 0.05

# --------------------------------------------------------------------- state
## DEVELOPMENT ONLY. When on, a powered mower that reaches empty is refuelled
## once, immediately, so a long automated run (the trailer, a soak test) is not
## stopped by an empty tank. It is NOT a fuel lock: the bar still drains
## normally between top-ups. Default OFF; the production HUD never exposes it.
var _auto_refuel: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ======================================================================= read

func capacity() -> float:
	return CAPACITY


## Current level, 0 - CAPACITY. Always read through `model`, never cached, so a
## save restore or a test writing `model.set_mower_fuel()` is seen immediately.
func fuel() -> float:
	return clampf(float(model.get_mower_fuel()), 0.0, CAPACITY)


## 0.0 - 1.0. What the production HUD gauge shows.
func fraction() -> float:
	return clampf(fuel() / CAPACITY, 0.0, 1.0)


func is_empty() -> bool:
	return fuel() <= EMPTY_EPSILON


## The one question a powered mower asks before it does anything.
func has_fuel() -> bool:
	return not is_empty()


## Fuel per second at a given throttle. `throttle` is 0.0 (idling) to 1.0
## (driving). Exposed so validation can assert the rate without a scene.
## How long a full tank lasts under the active difficulty. THE one place fuel
## economy is scaled.
func full_tank_driving_seconds() -> float:
	return maxf(ACADifficulty.value("full_tank_driving_seconds",
		FULL_TANK_DRIVING_SECONDS), 1.0)


func burn_rate_per_second(throttle: float) -> float:
	var driving := CAPACITY / maxf(full_tank_driving_seconds(), 0.001)
	return lerpf(driving * IDLE_BURN_FRACTION, driving, clampf(throttle, 0.0, 1.0))


## Seconds of runtime left at a given throttle. Used by the documentation and by
## the fuel test rather than being recomputed by hand.
func seconds_remaining(throttle: float) -> float:
	return fuel() / maxf(burn_rate_per_second(throttle), 0.001)


# ==================================================================== burning

## Burn `delta` seconds of fuel at `throttle` (0 idling .. 1 driving).
##
## Called ONLY by powered mower controllers, from `_physics_process`, with the
## real frame delta. Never from `_process` as well, or the tank burns twice.
func consume(delta: float, throttle: float) -> void:
	if delta <= 0.0:
		return

	var before := fuel()
	if before <= EMPTY_EPSILON:
		# Already dry. Auto Refuel still gets its chance, so a run that was
		# empty before the toggle went on can recover.
		_auto_refuel_if_enabled()
		return

	var after := maxf(before - burn_rate_per_second(throttle) * delta, 0.0)
	model.set_mower_fuel(after)

	# The LEVEL always moves; the SIGNAL does not. One physics tick at 576 Hz
	# burns about 0.0004 units, so announcing every tick would be 576 useless
	# emissions a second. Anything that needs the live value polls `fraction()`.
	# (An earlier version skipped the burn itself when the step was this small,
	# with `is_equal_approx` - which meant the tank never emptied at all.)
	if before - after >= SIGNAL_DEADBAND or after <= EMPTY_EPSILON:
		fuel_changed.emit(after)

	if after <= EMPTY_EPSILON and before > EMPTY_EPSILON:
		emptied.emit()
		_auto_refuel_if_enabled()


# ===================================================================== refuel
##
## THE gameplay refuel interface. There is no gas can, store or fuel economy
## yet - deliberately. This exists so the mower can make the round trip
##
##     HAS FUEL -> EMPTY -> REFUELLED -> WORKING AGAIN
##
## and so whatever mechanic eventually sells fuel has exactly one call to make.

## Add `amount` units. Returns how much actually fitted in the tank.
func refuel(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := fuel()
	var after := minf(before + amount, CAPACITY)
	var added := after - before
	if added <= 0.0:
		return 0.0
	model.set_mower_fuel(after)
	fuel_changed.emit(after)
	refuelled.emit(added, after)
	return added


## Fill the tank. Returns how much went in.
func refuel_full() -> float:
	return refuel(CAPACITY)


## Empty the tank deliberately. Development and validation only - there is no
## gameplay reason to dump fuel on the lawn.
func dev_drain() -> void:
	if is_empty():
		return
	model.set_mower_fuel(0.0)
	fuel_changed.emit(0.0)
	emptied.emit()
	_auto_refuel_if_enabled()


# ================================================================ auto refuel
##
## DEVELOPMENT ONLY. Reached from the F3 development HUD and from the Trailer
## Capture director. The production Gameplay HUD must never offer it.

func auto_refuel() -> bool:
	return _auto_refuel


func set_auto_refuel(enabled: bool) -> void:
	if _auto_refuel == enabled:
		return
	_auto_refuel = enabled
	auto_refuel_changed.emit(_auto_refuel)
	# Turning it on while already dry should recover immediately rather than
	# waiting for a burn tick that a dead engine will never produce.
	if _auto_refuel:
		_auto_refuel_if_enabled()


func toggle_auto_refuel() -> bool:
	set_auto_refuel(not _auto_refuel)
	return _auto_refuel


## "ON" / "OFF", for the development HUD and log lines.
func auto_refuel_text() -> String:
	return "ON" if _auto_refuel else "OFF"


## Refill ONCE on reaching empty, rather than pinning the tank at full every
## frame - the point of the trailer and of a soak test is to still SEE the gauge
## move.
func _auto_refuel_if_enabled() -> void:
	if not _auto_refuel:
		return
	if not is_empty():
		return
	refuel_full()
