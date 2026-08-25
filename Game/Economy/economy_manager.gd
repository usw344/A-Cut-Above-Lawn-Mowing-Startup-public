class_name ACAEconomyManager
extends Node
## THE MARKET. Autoloaded as `Economy`.
##
## Owns the economic CONDITIONS the business operates in, and the prices that
## follow from them. It does NOT own money — `GameSession` does, and there is
## exactly one balance in this game. It does not own jobs, mowers, scenes or UI
## either; it answers questions about prices and nothing else.
##
##     WorldClock.day_changed
##            |
##     Economy.advance_to_day()      <- the ONLY thing that moves the market
##            |
##     condition + event + noise  ->  job index / fuel price / equipment index
##            |
##     JobManager (new offers)   Supply Store (fuel)   MowerUpgrades (costs)
##
## ---------------------------------------------------------------------------
## DAYS, NOT FRAMES
## ---------------------------------------------------------------------------
##
## Nothing here runs in `_process`. The market moves when the world day rolls
## over and at no other time, so it cannot drift with frame rate, cannot be
## affected by a pause, and costs nothing to have running.
##
## ---------------------------------------------------------------------------
## DETERMINISM
## ---------------------------------------------------------------------------
##
## Every day's rolls come from a seed derived from `(economy_seed, day_index)`,
## NOT from a running RNG stream. That is deliberate: a stream would have to
## have its internal state persisted exactly, and any divergence would silently
## reroll the economy on load. With day-derived seeds, replaying day 41 always
## produces day 41, whatever happened in between.
##
## `randomize()` is never called here.

# ------------------------------------------------------------------- signals
signal condition_changed(condition: int)
signal event_started(event_id: StringName)
signal event_ended(event_id: StringName)
signal day_advanced(day_index: int)
## Anything price-facing moved. UI listens to this rather than polling.
signal prices_changed()

enum Condition { STABLE, GROWTH, INFLATION, RECESSION }

# ----------------------------------------------------------------- constants

## Price of one unit of fuel in a completely neutral market, at the LEGACY
## difficulty. `MowerFuel` treats a tank as 100 units, so this is also "a full
## tank costs about $110".
##
## Read through `base_fuel_price()` rather than directly: the active difficulty
## profile supplies its own, and this is the fallback when none is set.
const BASE_FUEL_PRICE := 1.10

## Conditions last WEEKS, not days. The point of a regime is that the player
## can notice it and act on it; a market that flips every morning is noise.
## `min_days`/`max_days` are in whole world days.
const CONDITIONS := {
	Condition.STABLE: {
		"name": "Stable", "job": 1.00, "fuel": 1.00, "equipment": 1.00,
		"min_days": 8, "max_days": 20,
		"blurb": "Ordinary trading. Prices are close to their long-run average.",
	},
	Condition.GROWTH: {
		"name": "Growth", "job": 1.12, "fuel": 1.05, "equipment": 1.08,
		"min_days": 6, "max_days": 16,
		"blurb": "Work is plentiful and pays well. Equipment costs a little more.",
	},
	Condition.INFLATION: {
		"name": "Inflation", "job": 1.18, "fuel": 1.22, "equipment": 1.20,
		"min_days": 6, "max_days": 14,
		"blurb": "Every number is bigger — including the ones you pay.",
	},
	Condition.RECESSION: {
		"name": "Recession", "job": 0.84, "fuel": 0.92, "equipment": 0.90,
		"min_days": 6, "max_days": 16,
		"blurb": "Contracts are scarce and cheap. Equipment is a bargain.",
	},
}

## Where a condition can go next, and how likely. Weighted so STABLE is the
## common resting state and INFLATION does not follow RECESSION directly —
## the market has some memory rather than being a fair die every time.
const TRANSITIONS := {
	Condition.STABLE: {Condition.GROWTH: 3, Condition.RECESSION: 3, Condition.INFLATION: 2},
	Condition.GROWTH: {Condition.STABLE: 5, Condition.INFLATION: 3, Condition.RECESSION: 1},
	Condition.INFLATION: {Condition.STABLE: 5, Condition.RECESSION: 3, Condition.GROWTH: 1},
	Condition.RECESSION: {Condition.STABLE: 6, Condition.GROWTH: 3},
}

## Temporary events. ONE at a time by design: stacked modifiers become
## unreadable, and the player cannot act on a number they cannot explain.
const EVENTS := [
	{
		"id": &"fuel_shortage", "name": "Fuel Shortage", "weight": 4,
		"job": 1.00, "fuel": 1.24, "equipment": 1.00, "min_days": 2, "max_days": 5,
		"blurb": "Deliveries are short. Fuel is dear until it clears.",
	},
	{
		"id": &"fuel_surplus", "name": "Fuel Surplus", "weight": 3,
		"job": 1.00, "fuel": 0.84, "equipment": 1.00, "min_days": 2, "max_days": 5,
		"blurb": "A glut at the depot. Fill up while it lasts.",
	},
	{
		"id": &"high_demand", "name": "High Lawn-Care Demand", "weight": 4,
		"job": 1.16, "fuel": 1.00, "equipment": 1.00, "min_days": 3, "max_days": 7,
		"blurb": "Everyone wants their lawn done at once. Contracts pay more.",
	},
	{
		"id": &"slow_season", "name": "Slow Season", "weight": 3,
		"job": 0.87, "fuel": 1.00, "equipment": 1.00, "min_days": 3, "max_days": 7,
		"blurb": "Little grass growing. Contracts are thin and cheap.",
	},
	{
		"id": &"construction_boom", "name": "Local Construction Boom", "weight": 3,
		"job": 1.10, "fuel": 1.04, "equipment": 1.12, "min_days": 4, "max_days": 8,
		"blurb": "New lots everywhere. More work, but parts are spoken for.",
	},
	{
		"id": &"supply_delay", "name": "Supply Chain Delay", "weight": 3,
		"job": 1.00, "fuel": 1.00, "equipment": 1.18, "min_days": 3, "max_days": 6,
		"blurb": "Parts are slow to arrive. Upgrades cost more this week.",
	},
]

## Chance per day of an event starting, when none is running, at the LEGACY
## difficulty. Read through `event_daily_chance()`.
##
## THIS IS NOT A DIFFICULTY SLIDER and the profiles do not treat it as one.
## Events run both ways - a fuel surplus is as likely as a shortage - so a
## higher chance is more VOLATILITY rather than more hardship, which is why
## Hard has the most and Easy has slightly fewer than Medium.
const EVENT_DAILY_CHANCE := 0.11
## Days after an event ends before another can start. Stops back-to-back events
## reading as one long permanent modifier.
const EVENT_COOLDOWN_DAYS := 3

## Daily fuel noise. Mean-reverting rather than independent, so the price
## DRIFTS instead of jumping: single-digit percentages day to day, as a
## fuel price behaves.
const FUEL_NOISE_STEP := 0.035
const FUEL_NOISE_RETENTION := 0.72
const FUEL_NOISE_LIMIT := 0.09

## Hard bounds on the fuel multiplier, whatever the conditions and events
## conspire to produce. A market is allowed to be dramatic; it is not allowed
## to be absurd.
const FUEL_MULTIPLIER_MIN := 0.70
const FUEL_MULTIPLIER_MAX := 1.45

## Guard against a save from far in the future, or a dev fast-forward, walking
## the market a thousand days on one frame.
const MAX_CATCHUP_DAYS := 400

# --------------------------------------------------------------------- state
var _seed: int = 0
var _condition: int = Condition.STABLE
var _condition_days_left: int = 12
var _event_id: StringName = &""
var _event_days_left: int = 0
var _event_cooldown: int = 0
var _fuel_noise: float = 0.0
## Last world day this market has been simulated through.
var _last_day: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Days, not frames. Nothing here needs a tick.
	set_process(false)
	set_physics_process(false)
	var clock := get_node_or_null(^"/root/WorldClock")
	if clock != null:
		clock.day_changed.connect(_on_day_changed)


func _on_day_changed(day_index: int) -> void:
	advance_to_day(day_index)


# ================================================================== lifecycle

## Fresh market for a new game. `seed_value` of 0 picks one from the clock, so
## two new games differ; pass a value for a reproducible run.
func start_new_economy(seed_value: int = 0, day_index: int = 0) -> void:
	_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	_condition = Condition.STABLE
	_rng.seed = _day_seed(day_index)
	_condition_days_left = _roll_duration(CONDITIONS[Condition.STABLE])
	_event_id = &""
	_event_days_left = 0
	_event_cooldown = 0
	_fuel_noise = 0.0
	_last_day = day_index
	condition_changed.emit(_condition)
	prices_changed.emit()


## Walk the market forward to `day_index`. Safe to call with the current day
## (does nothing) or with a day far ahead (walks each one, so a regime that
## should have ended does).
func advance_to_day(day_index: int) -> void:
	if day_index <= _last_day:
		return
	var days := mini(day_index - _last_day, MAX_CATCHUP_DAYS)
	var start := day_index - days
	for d in range(start + 1, day_index + 1):
		_advance_one_day(d)
	_last_day = day_index
	prices_changed.emit()


## ONE day. Everything it rolls comes from this day's own seed.
func _advance_one_day(day: int) -> void:
	_rng.seed = _day_seed(day)

	# Fuel drifts rather than jumping: an AR(1) step, then clamped.
	_fuel_noise = clampf(
		_fuel_noise * FUEL_NOISE_RETENTION + _rng.randf_range(-FUEL_NOISE_STEP, FUEL_NOISE_STEP),
		-FUEL_NOISE_LIMIT, FUEL_NOISE_LIMIT)

	# The active event, if any, burns down first.
	if not _event_id.is_empty():
		_event_days_left -= 1
		if _event_days_left <= 0:
			var ended := _event_id
			_event_id = &""
			_event_days_left = 0
			_event_cooldown = EVENT_COOLDOWN_DAYS
			event_ended.emit(ended)
	elif _event_cooldown > 0:
		_event_cooldown -= 1
	elif _rng.randf() < event_daily_chance():
		_start_event(_pick_event())

	# Then the regime.
	_condition_days_left -= 1
	if _condition_days_left <= 0:
		_change_condition(_pick_next_condition())

	day_advanced.emit(day)


func _change_condition(next: int) -> void:
	_condition = next
	_condition_days_left = _roll_duration(CONDITIONS[next])
	condition_changed.emit(_condition)


func _start_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	_event_id = event["id"]
	_event_days_left = _rng.randi_range(int(event["min_days"]), int(event["max_days"]))
	event_started.emit(_event_id)


func _roll_duration(spec: Dictionary) -> int:
	return _rng.randi_range(int(spec["min_days"]), int(spec["max_days"]))


func _pick_next_condition() -> int:
	var weights: Dictionary = TRANSITIONS.get(_condition, {})
	if weights.is_empty():
		return Condition.STABLE
	var total := 0
	for k in weights:
		total += int(weights[k])
	var roll := _rng.randi_range(1, maxi(total, 1))
	var acc := 0
	for k in weights:
		acc += int(weights[k])
		if roll <= acc:
			return int(k)
	return Condition.STABLE


func _pick_event() -> Dictionary:
	var total := 0
	for e: Dictionary in EVENTS:
		total += int(e["weight"])
	var roll := _rng.randi_range(1, maxi(total, 1))
	var acc := 0
	for e: Dictionary in EVENTS:
		acc += int(e["weight"])
		if roll <= acc:
			return e
	return {}


## Stable per-day seed. Mixed rather than added so adjacent days do not produce
## adjacent RNG streams.
func _day_seed(day: int) -> int:
	return hash(Vector2i(_seed, day))


# =================================================================== reading

func condition() -> int:
	return _condition


func condition_name() -> String:
	return String(CONDITIONS[_condition]["name"])


func condition_blurb() -> String:
	return String(CONDITIONS[_condition]["blurb"])


func condition_days_remaining() -> int:
	return maxi(_condition_days_left, 0)


func has_event() -> bool:
	return not _event_id.is_empty()


func event_id() -> StringName:
	return _event_id


func event_days_remaining() -> int:
	return maxi(_event_days_left, 0)


func event_spec() -> Dictionary:
	for e: Dictionary in EVENTS:
		if e["id"] == _event_id:
			return e
	return {}


func event_name() -> String:
	var e := event_spec()
	return String(e.get("name", ""))


func event_blurb() -> String:
	var e := event_spec()
	return String(e.get("blurb", ""))


func economy_seed() -> int:
	return _seed


func last_processed_day() -> int:
	return _last_day


# ------------------------------------------------------- difficulty inputs
##
## THREE numbers the active difficulty profile supplies. They are read here,
## once each, rather than being scattered through the price functions, and each
## falls back to the constant above when no profile is set - which is what makes
## this class still work in a probe with no session around it.

## Dollars per unit of fuel before any market movement.
func base_fuel_price() -> float:
	return ACADifficulty.value("base_fuel_price", BASE_FUEL_PRICE)


## Chance per day that a temporary event starts, when none is running.
func event_daily_chance() -> float:
	return ACADifficulty.value("event_daily_chance", EVENT_DAILY_CHANCE)


func _modifier(key: String) -> float:
	var base := float(CONDITIONS[_condition].get(key, 1.0))
	# THE DOWNTURN'S DEPTH IS A DIFFICULTY SETTING, and it is the only condition
	# value that is. The profile scales how far Recession's payout DEVIATES from
	# neutral rather than the multiplier itself, so a scale of 1.0 reproduces
	# 0.84 exactly. See the note in `ACADifficulty`.
	if _condition == Condition.RECESSION and key == "job":
		base = ACADifficulty.recession_job_multiplier()
	var e := event_spec()
	return base * float(e.get(key, 1.0))


# ------------------------------------------------------------------ indices

## Multiplier applied to NEW job offers. Accepted contracts are never
## recomputed — see `ACAJobManager.pay_multiplier_provider`.
func job_index() -> float:
	return _modifier("job")


func equipment_index() -> float:
	return _modifier("equipment")


## The fuel multiplier including today's drift, clamped to something a player
## can believe.
func fuel_index() -> float:
	return clampf(_modifier("fuel") * (1.0 + _fuel_noise),
		FUEL_MULTIPLIER_MIN, FUEL_MULTIPLIER_MAX)


# ------------------------------------------------------------------- prices

## Dollars per unit of fuel. `MowerFuel` capacity is 100 units, so a full tank
## from empty is roughly a hundred times this.
func fuel_price_per_unit() -> float:
	return base_fuel_price() * fuel_index()


## What it costs to put `units` of fuel in a tank, rounded up to the cent.
func fuel_cost_for_units(units: float) -> int:
	if units <= 0.0:
		return 0
	return int(ceil(maxf(units, 0.0) * fuel_price_per_unit()))


## Apply the market to a base equipment price. Rounded to $5 so shop prices
## read as prices rather than as arithmetic.
func equipment_price(base_price: int) -> int:
	var value := float(base_price) * equipment_index()
	return maxi(int(round(value / 5.0)) * 5, 0)


## Apply the market to a base job reward. Rounded to $5 for the same reason.
func job_reward(base_reward: int) -> int:
	var value := float(base_reward) * job_index()
	return maxi(int(round(value / 5.0)) * 5, 0)


## Signed percentage for UI, e.g. "+8%".
static func format_index(index: float) -> String:
	var pct := int(round((index - 1.0) * 100.0))
	return "%+d%%" % pct


## Everything a dashboard needs, in one call.
func summary() -> Dictionary:
	return {
		"condition": _condition,
		"condition_name": condition_name(),
		"condition_blurb": condition_blurb(),
		"condition_days_remaining": condition_days_remaining(),
		"job_index": job_index(),
		"fuel_index": fuel_index(),
		"equipment_index": equipment_index(),
		"fuel_price": fuel_price_per_unit(),
		"has_event": has_event(),
		"event_id": _event_id,
		"event_name": event_name(),
		"event_blurb": event_blurb(),
		"event_days_remaining": event_days_remaining(),
		"day": _last_day,
	}


# =============================================================== persistence
## Plain built-in types only. Derived values (indices, prices) are NOT saved —
## they are recomputed from the state below, so they can never disagree with it.

func to_save_dict() -> Dictionary:
	return {
		"seed": _seed,
		"condition": _condition,
		"condition_days_left": _condition_days_left,
		"event_id": String(_event_id),
		"event_days_left": _event_days_left,
		"event_cooldown": _event_cooldown,
		"fuel_noise": _fuel_noise,
		"last_day": _last_day,
	}


## Restores exactly. Note what is NOT here: no `randomize()`, no re-roll, no
## `advance_to_day()`. Loading a save must reproduce the market the player left,
## and the day-derived seeding above is what makes that true even after the
## clock moves on.
func from_save_dict(data: Dictionary) -> void:
	_seed = int(data.get("seed", 0))
	_condition = clampi(int(data.get("condition", Condition.STABLE)),
		0, Condition.size() - 1)
	_condition_days_left = int(data.get("condition_days_left", 10))
	_event_id = StringName(String(data.get("event_id", "")))
	_event_days_left = int(data.get("event_days_left", 0))
	_event_cooldown = int(data.get("event_cooldown", 0))
	_fuel_noise = float(data.get("fuel_noise", 0.0))
	_last_day = int(data.get("last_day", 0))

	# An id that no longer exists (a removed event in a newer build) must not
	# leave a phantom modifier applied forever.
	if not _event_id.is_empty() and event_spec().is_empty():
		_event_id = &""
		_event_days_left = 0

	condition_changed.emit(_condition)
	prices_changed.emit()


# ================================================================ development

## DEVELOPMENT AND VALIDATION ONLY. Put the market into a condition now, through
## the same `_change_condition()` a natural transition uses, so the behaviour
## that FOLLOWS a downturn can be tested without waiting for one to be rolled.
##
## It does not touch the seed or the day, so the market carries on from here
## exactly as it would have if this condition had come up on its own.
func debug_force_condition(next: int) -> void:
	if not CONDITIONS.has(next):
		push_warning("[ECONOMY] unknown condition %s" % next)
		return
	_change_condition(next)
	prices_changed.emit()


## An OLD SAVE with no economy section at all. Rather than refusing to load,
## the market starts fresh at the save's own day, so the contract the player
## had open still makes sense next to it.
func initialise_for_legacy_save(day_index: int) -> void:
	start_new_economy(0, day_index)
