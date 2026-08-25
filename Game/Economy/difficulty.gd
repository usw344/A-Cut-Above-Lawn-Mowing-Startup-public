class_name ACADifficulty
extends RefCounted
## THE economy difficulty profiles, and the one place their numbers live.
##
## ---------------------------------------------------------------------------
## WHAT A DIFFICULTY IS HERE
## ---------------------------------------------------------------------------
## It is an ECONOMY setting, not a graphics setting. It is chosen when a game is
## started, it is saved with that game, and it changes seven numbers:
##
##   starting money            what the business opens with
##   job pay scale             applied to a NEW offer, with the market
##   base fuel price           dollars per unit before the market
##   event daily chance        how often a temporary event starts
##   recession job scale       how hard a downturn bites - see below
##   upgrade cost scale        equipment prices before the market
##   full tank driving seconds how far a tank of fuel goes
##
## Nothing else. It does not touch mowing, the property, the clock, the weather,
## the job generator's seeded variation, or the rule that an accepted contract's
## payout can never change.
##
## ---------------------------------------------------------------------------
## WHERE THE NUMBERS CAME FROM
## ---------------------------------------------------------------------------
## A 1,000-run Monte Carlo study of the shipped economy, then a bounded
## multivariate search, then 1,000-run validation populations for each candidate.
## The search returned values like 1.0832462525422788; what is below are ROUND
## numbers chosen to be maintainable, and then RE-VALIDATED at 1,000 runs each
## rather than assumed to behave the same. Measured outcomes over a 365 day year:
##
##   | profile | survival | median cash | median fuel share | reasonable families |
##   |---------|---------:|------------:|------------------:|--------------------:|
##   | Easy    |    90.5% |     $24,845 |             37.0% |                100% |
##   | Medium  |    82.9% |     $15,808 |             53.4% |                100% |
##   | Hard    |    74.7% |      $6,032 |             75.3% |               91.6% |
##
## "Reasonable families" excludes the two deliberately reckless strategy
## families the study models. Those are the difference between the columns: on
## Medium a sensible operator never fails and a reckless one fails 80-90% of the
## time, which is the shape a difficulty is supposed to have.
##
## See `ECONOMY_REBALANCE_REPORT.md` at the workspace root.
##
## ---------------------------------------------------------------------------
## RECESSION SCALE IS NOT THE MULTIPLIER
## ---------------------------------------------------------------------------
## `recession_job_scale` scales the DEVIATION from neutral, not the multiplier:
##
##     effective recession payout = 1.0 + (0.84 - 1.0) * scale
##
## So 0.75 gives 0.88 (a mild downturn), 1.00 gives 0.84 (exactly what the game
## has always done) and 1.25 gives 0.80 (a sharp one). This was READ OUT OF THE
## SIMULATOR rather than assumed from the parameter's name, because the name
## reads as though it were the multiplier itself and it is not.
##
## PUBLIC API
##   ACADifficulty.PLAYER_IDS / DEFAULT_ID / LEGACY_ID
##   ACADifficulty.set_active(id) / active_id() / active()
##   ACADifficulty.profile(id) / is_valid(id) / display_name(id)
##   ACADifficulty.description(id) / characteristics(id)
##   ACADifficulty.recession_job_multiplier()
##
## SIGNALS: None. `GameSession.difficulty_changed` is the signal.
##
## INVARIANTS
##   * `GameSession` is the ONLY thing that calls `set_active()`. It owns the
##     session state; this class owns the numbers. Everything else reads.
##   * `active()` is always a valid profile. An unknown id falls back to Medium
##     with a warning rather than returning an empty dictionary.
##   * `legacy` is never offered to a player. It exists so a save written before
##     difficulty existed keeps the exact economy it was played on.
##
## PERSISTENCE OWNERSHIP
##   None. The id is one string inside `GameSession.to_save_dict()`.

## The production Recession payout multiplier the scale is applied to. It lives
## in `ACAEconomyManager.CONDITIONS`; this is here so the formula above can be
## written down once, and it is asserted against the real one by Economy Test.
const RECESSION_BASE_JOB := 0.84

const LEGACY_ID := &"legacy"
const DEFAULT_ID := &"medium"

## What a NEW GAME may choose. `legacy` is deliberately absent.
const PLAYER_IDS: Array[StringName] = [&"easy", &"medium", &"hard"]

const PROFILES := {
	# NOT OFFERED TO PLAYERS. Exactly the constants the game shipped with before
	# difficulty existed, so loading an old save cannot silently change the
	# economy that save was played under. See `GameSession.from_save_dict()`.
	&"legacy": {
		"name": "Standard",
		"description": "The business balance this save was started under.",
		"characteristics": [],
		"starting_money": 250,
		"job_pay_scale": 1.00,
		"base_fuel_price": 1.10,
		"event_daily_chance": 0.11,
		"recession_job_scale": 1.00,
		"upgrade_cost_scale": 1.00,
		"full_tank_driving_seconds": 480.0,
	},
	&"easy": {
		"name": "Steady",
		"description": "Forgiving business conditions, with room to make a "
			+ "mistake and trade your way back out of it.",
		"characteristics": [
			"A larger opening float",
			"Cheaper fuel, and a tank that goes further",
			"Contracts pay a little over the odds",
			"Downturns are shallow",
		],
		"starting_money": 320,
		"job_pay_scale": 1.15,
		"base_fuel_price": 0.90,
		"event_daily_chance": 0.10,
		"recession_job_scale": 0.75,
		"upgrade_cost_scale": 0.85,
		"full_tank_driving_seconds": 560.0,
	},
	&"medium": {
		"name": "Working",
		"description": "The balance the game is designed around. Fuel is your "
			+ "biggest bill and the job you take is the decision that matters.",
		"characteristics": [
			"Contracts pay what they are worth",
			"Fuel is about half of what you earn",
			"Upgrades are worth saving for",
			"A bad run of decisions can be recovered from",
		],
		"starting_money": 250,
		"job_pay_scale": 1.00,
		"base_fuel_price": 1.00,
		"event_daily_chance": 0.11,
		"recession_job_scale": 1.00,
		"upgrade_cost_scale": 1.00,
		"full_tank_driving_seconds": 500.0,
	},
	&"hard": {
		"name": "Lean Season",
		"description": "Thin margins and little slack. Reserves and job "
			+ "selection decide whether the business is still here in a year.",
		"characteristics": [
			"A thin opening float",
			"Expensive fuel, and a tank that does not last",
			"Contracts pay under the odds",
			"Downturns bite, and equipment is dear",
		],
		"starting_money": 200,
		"job_pay_scale": 0.88,
		"base_fuel_price": 1.15,
		"event_daily_chance": 0.15,
		"recession_job_scale": 1.25,
		"upgrade_cost_scale": 1.15,
		"full_tank_driving_seconds": 430.0,
	},
}

## THE active profile.
##
## A static var rather than an autoload, on purpose. Fuel burn is read every
## physics frame at 576 Hz and job pay on every offer, so the read has to be
## free; and a difficulty is not a system with behaviour, it is seven numbers.
## `GameSession` is the only writer, which is what keeps this from becoming a
## second place session state lives.
static var _active_id: StringName = DEFAULT_ID


static func is_valid(id: StringName) -> bool:
	return PROFILES.has(id)


## Called by `GameSession` and by nothing else.
static func set_active(id: StringName) -> void:
	if not is_valid(id):
		push_warning("[DIFFICULTY] unknown profile '%s'; using %s" % [id, DEFAULT_ID])
		_active_id = DEFAULT_ID
		return
	_active_id = id


static func active_id() -> StringName:
	return _active_id


static func active() -> Dictionary:
	return PROFILES.get(_active_id, PROFILES[DEFAULT_ID])


static func profile(id: StringName) -> Dictionary:
	return PROFILES.get(id, PROFILES[DEFAULT_ID])


static func value(key: String, fallback: float) -> float:
	return float(active().get(key, fallback))


static func display_name(id: StringName) -> String:
	return String(profile(id).get("name", "Working"))


static func description(id: StringName) -> String:
	return String(profile(id).get("description", ""))


static func characteristics(id: StringName) -> Array:
	return (profile(id).get("characteristics", []) as Array).duplicate()


## The effective Recession payout multiplier under the active profile. See the
## note at the top: the profile stores a scale on the DEVIATION, not this.
static func recession_job_multiplier() -> float:
	return 1.0 + (RECESSION_BASE_JOB - 1.0) * value("recession_job_scale", 1.0)
