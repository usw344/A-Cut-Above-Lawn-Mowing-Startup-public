extends Node
## DEVELOPMENT ONLY. The economy, the shops and the mower upgrades.
##
##   godot --headless --path <project> "res://Dev tools/Validation/Economy Test.tscn" \
##     -- "--save-root=../Test User Data/<dir>"
##
## Needs the autoloads, so it runs as a scene rather than as a `--script`.
##
## The suite is in two halves. The first is ordinary assertions. The second is a
## **90-day simulation with a fixed seed** that prints what the market actually
## did — because a set of green unit tests proves the economy is CONSISTENT and
## says nothing at all about whether it is any good to live in.

const SIM_DAYS := 90
const SIM_SEED := 20260820

var _pass := 0
var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	_test_market_progression()
	_test_regime_and_event_durations()
	_test_determinism()
	_test_money_api()
	_test_fuel_purchase()
	_test_upgrades()
	_test_upgrade_effects()
	_test_job_pricing_and_lock()
	await _test_persistence()
	_test_difficulty_profiles()
	_test_difficulty_prices()
	await _test_difficulty_persistence()
	await _test_recession_market_bridge()
	_simulate_ninety_days()
	_sweep_seeds()

	print("[ECONOMY TEST] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ================================================================== the market

func _test_market_progression() -> void:
	Economy.start_new_economy(SIM_SEED, 0)
	_check("Market: a new economy starts Stable",
		Economy.condition() == ACAEconomyManager.Condition.STABLE)
	_check("Market: a new economy has no event", not Economy.has_event())
	_check("Market: day 0 is the last processed day", Economy.last_processed_day() == 0)

	# Days, not frames: nothing moves until the world day rolls over.
	var before := Economy.fuel_price_per_unit()
	for i in range(50):
		await_nothing()
	_check("Market: prices do not drift without a day passing",
		is_equal_approx(Economy.fuel_price_per_unit(), before))

	Economy.advance_to_day(1)
	_check("Market: advancing a day is recorded", Economy.last_processed_day() == 1)

	# Walking forward from far behind must not be skipped, or a regime that
	# should have ended never does.
	Economy.advance_to_day(30)
	_check("Market: a multi-day jump is walked, not skipped",
		Economy.last_processed_day() == 30)
	Economy.advance_to_day(20)
	_check("Market: the market never runs backwards",
		Economy.last_processed_day() == 30)


func await_nothing() -> void:
	pass


func _test_regime_and_event_durations() -> void:
	# Regimes must last WEEKS. A market that flips every morning is noise the
	# player cannot act on.
	Economy.start_new_economy(SIM_SEED, 0)
	var runs: Array[int] = []
	var current := Economy.condition()
	var run := 0
	var event_runs: Array[int] = []
	var event_run := 0
	var last_event := Economy.event_id()

	for day in range(1, 365):
		Economy.advance_to_day(day)
		if Economy.condition() == current:
			run += 1
		else:
			runs.append(run + 1)
			current = Economy.condition()
			run = 0
		if Economy.event_id() == last_event:
			event_run += 1
		else:
			if not last_event.is_empty():
				event_runs.append(event_run + 1)
			last_event = Economy.event_id()
			event_run = 0

	var shortest := 9999
	for r in runs:
		shortest = mini(shortest, r)
	_check("Market: %d regime changes in a year, shortest %d days"
		% [runs.size(), shortest], runs.size() >= 8 and runs.size() <= 60)
	_check("Market: no regime is shorter than five days (shortest %d)" % shortest,
		shortest >= 5)

	var longest_event := 0
	for r in event_runs:
		longest_event = maxi(longest_event, r)
	_check("Market: events are temporary (longest %d days)" % longest_event,
		longest_event <= 12)
	_check("Market: only one event runs at a time",
		not Economy.has_event() or not Economy.event_spec().is_empty())


## Loading a save must not reroll the market, and replaying the same days from
## the same state must produce the same market. Day-derived seeding is what
## makes both true; this is the assertion that keeps it that way.
func _test_determinism() -> void:
	Economy.start_new_economy(SIM_SEED, 0)
	for day in range(1, 41):
		Economy.advance_to_day(day)
	var first := Economy.to_save_dict()
	var first_price := Economy.fuel_price_per_unit()

	Economy.start_new_economy(SIM_SEED, 0)
	for day in range(1, 41):
		Economy.advance_to_day(day)
	_check("Determinism: the same seed replays the same 40 days",
		Economy.to_save_dict() == first
		and is_equal_approx(Economy.fuel_price_per_unit(), first_price))

	# A different seed must actually differ, or the seed is decorative.
	Economy.start_new_economy(SIM_SEED + 991, 0)
	for day in range(1, 41):
		Economy.advance_to_day(day)
	_check("Determinism: a different seed produces a different market",
		Economy.to_save_dict() != first)


# ======================================================================= money

func _test_money_api() -> void:
	GameSession.start_new_game()
	var start := GameSession.money()
	_check("Money: a new game starts with %s" % UITheme.format_money(start), start > 0)
	_check("Money: can_afford is true for what is there", GameSession.can_afford(start))
	_check("Money: can_afford is false for a dollar more",
		not GameSession.can_afford(start + 1))

	_check("Money: spending more than you have is refused",
		not GameSession.try_spend(start + 1))
	_check("Money: a refused purchase changes nothing", GameSession.money() == start)

	_check("Money: spending what you have succeeds", GameSession.try_spend(start))
	_check("Money: THE BALANCE NEVER GOES NEGATIVE", GameSession.money() == 0)
	_check("Money: a negative price is refused", not GameSession.try_spend(-50))

	GameSession.add_money(500)
	_check("Money: there is exactly ONE balance",
		GameSession.money() == 500)


# ======================================================================== fuel

func _test_fuel_purchase() -> void:
	Economy.start_new_economy(SIM_SEED, 0)
	GameSession.start_new_game()
	GameSession.add_money(10000)
	MowerFuel.dev_drain()

	var price := Economy.fuel_price_per_unit()
	_check("Fuel: a price exists and is plausible ($%.2f/unit)" % price,
		price > 0.4 and price < 2.2)

	var full_cost := Economy.fuel_cost_for_units(MowerFuel.capacity())
	_check("Fuel: a full tank costs %s" % UITheme.format_money(full_cost),
		full_cost > 0)

	# Partial purchase.
	var before_money := GameSession.money()
	var part_cost := Economy.fuel_cost_for_units(40.0)
	_check("Fuel: a partial fill costs less than a full one", part_cost < full_cost)
	GameSession.try_spend(part_cost)
	var added := MowerFuel.refuel(40.0)
	_check("Fuel: 40 units really went in (%.0f)" % added, absf(added - 40.0) < 0.01)
	_check("Fuel: the exact cost was deducted",
		GameSession.money() == before_money - part_cost)

	# Full purchase from partial.
	var missing := MowerFuel.capacity() - MowerFuel.fuel()
	var top_up := Economy.fuel_cost_for_units(missing)
	GameSession.try_spend(top_up)
	MowerFuel.refuel(missing)
	_check("Fuel: refuelling to full reaches capacity",
		absf(MowerFuel.fuel() - MowerFuel.capacity()) < 0.01)

	# Insufficient funds.
	MowerFuel.dev_drain()
	GameSession.try_spend(GameSession.money())
	_check("Fuel: with no money the tank cannot be filled",
		not GameSession.try_spend(Economy.fuel_cost_for_units(MowerFuel.capacity())))
	_check("Fuel: a failed purchase leaves the tank empty", MowerFuel.fuel() < 0.01)
	_check("Fuel: and the balance at zero, not below", GameSession.money() == 0)

	# The development controls are NOT the economy, and still work.
	MowerFuel.refuel_full()
	_check("Fuel: the F7 development refuel still works, free",
		MowerFuel.fuel() >= MowerFuel.capacity() - 0.01 and GameSession.money() == 0)


# ==================================================================== upgrades

func _test_upgrades() -> void:
	Economy.start_new_economy(SIM_SEED, 0)
	MowerUpgrades.reset_all()
	GameSession.start_new_game()
	GameSession.add_money(500000)

	_check("Upgrades: the three canonical mowers are known",
		ACAMowerUpgrades.MOWER_IDS.size() == 3
		and ACAMowerUpgrades.is_valid_mower("rider")
		and ACAMowerUpgrades.is_valid_mower("powered")
		and ACAMowerUpgrades.is_valid_mower("push"))

	# THE PUSH MOWER HAS NO FUEL SYSTEM, because it has no fuel.
	var push_cats := ACAMowerUpgrades.categories_for("push")
	_check("Upgrades: the push mower has no fuel upgrade",
		not push_cats.has("fuel_system"))
	_check("Upgrades: the push mower still has real upgrades (%s)" % str(push_cats),
		push_cats.size() >= 2)
	_check("Upgrades: powered mowers DO have a fuel system",
		ACAMowerUpgrades.categories_for("rider").has("fuel_system")
		and ACAMowerUpgrades.categories_for("powered").has("fuel_system"))

	# Buying.
	var cost := MowerUpgrades.next_cost("rider", "drive")
	var money_before := GameSession.money()
	_check("Upgrades: a first level has a price (%s)" % UITheme.format_money(cost),
		cost > 0)
	_check("Upgrades: purchase succeeds", MowerUpgrades.try_purchase("rider", "drive"))
	_check("Upgrades: the level went up", MowerUpgrades.level("rider", "drive") == 1)
	_check("Upgrades: the money was taken exactly once",
		GameSession.money() == money_before - cost)

	# PER MOWER, not global.
	_check("Upgrades: the powered walk-behind did NOT get it too",
		MowerUpgrades.level("powered", "drive") == 0)
	_check("Upgrades: and its speed multiplier is untouched",
		is_equal_approx(MowerUpgrades.speed_multiplier("powered"), 1.0))

	# Cost rises with level.
	var second := MowerUpgrades.next_cost("rider", "drive")
	_check("Upgrades: level 2 costs more than level 1 (%d > %d)" % [second, cost],
		second > cost)

	# Max.
	var max_level := ACAMowerUpgrades.max_level("drive")
	for i in range(max_level):
		MowerUpgrades.try_purchase("rider", "drive")
	_check("Upgrades: a category can be maxed (%d)" % max_level,
		MowerUpgrades.is_maxed("rider", "drive"))
	_check("Upgrades: a maxed category reports no next price",
		MowerUpgrades.next_cost("rider", "drive") == -1)
	_check("Upgrades: a maxed category cannot be bought again",
		not MowerUpgrades.try_purchase("rider", "drive"))

	# Insufficient funds.
	MowerUpgrades.reset_all()
	GameSession.try_spend(GameSession.money())
	_check("Upgrades: with no money nothing can be bought",
		not MowerUpgrades.try_purchase("rider", "steering"))
	_check("Upgrades: and the level did not move",
		MowerUpgrades.level("rider", "steering") == 0)

	# The market moves equipment prices.
	MowerUpgrades.reset_all()
	var neutral := ACAMowerUpgrades.base_cost("drive", 1)
	var priced := Economy.equipment_price(neutral)
	_check("Upgrades: the market is applied to equipment prices (%d -> %d)"
		% [neutral, priced], priced > 0)
	_check("Upgrades: base costs are deterministic",
		ACAMowerUpgrades.base_cost("drive", 1) == neutral)


## PROVE THE MOWER CHANGES. An upgrade whose number moves but whose machine does
## not is the specific failure this asserts against.
func _test_upgrade_effects() -> void:
	MowerUpgrades.reset_all()
	_check("Effects: a stock mower has multipliers of exactly 1.0",
		is_equal_approx(MowerUpgrades.speed_multiplier("rider"), 1.0)
		and is_equal_approx(MowerUpgrades.fuel_multiplier("rider"), 1.0)
		and is_equal_approx(MowerUpgrades.handling_multiplier("rider"), 1.0))

	MowerUpgrades.dev_set_level("rider", "drive", ACAMowerUpgrades.max_level("drive"))
	var speed := MowerUpgrades.speed_multiplier("rider")
	_check("Effects: a maxed drive makes the rider faster (x%.2f)" % speed,
		speed > 1.15)
	_check("Effects: but not absurdly faster (x%.2f)" % speed, speed < 1.6)

	MowerUpgrades.dev_set_level("rider", "fuel_system",
		ACAMowerUpgrades.max_level("fuel_system"))
	var fuel := MowerUpgrades.fuel_multiplier("rider")
	_check("Effects: a maxed fuel system BURNS LESS (x%.2f)" % fuel, fuel < 0.85)
	_check("Effects: and does not make fuel free (x%.2f)" % fuel, fuel > 0.5)

	MowerUpgrades.dev_set_level("rider", "steering",
		ACAMowerUpgrades.max_level("steering"))
	_check("Effects: a maxed steering upgrade tightens response",
		MowerUpgrades.handling_multiplier("rider") > 1.2)

	# The push mower must never acquire a fuel modifier, whatever is set on it.
	MowerUpgrades.dev_set_level("push", "fuel_system", 4)
	_check("Effects: the push mower CANNOT gain a fuel modifier",
		is_equal_approx(MowerUpgrades.fuel_multiplier("push"), 1.0))

	MowerUpgrades.dev_set_level("push", "frame", ACAMowerUpgrades.max_level("frame"))
	_check("Effects: the push mower's frame upgrade is real",
		MowerUpgrades.speed_multiplier("push") > 1.1)

	# And the mower controllers really read them.
	var rider_source := FileAccess.open(
		"res://Assets/Vehicles and Mowers/Mowers/mower_rider.gd", FileAccess.READ)
	var text := "" if rider_source == null else rider_source.get_as_text()
	_check("Effects: the rider's controller applies the speed multiplier",
		text.contains("MowerUpgrades.speed_multiplier(MOWER_ID)"))
	_check("Effects: the rider's controller applies the fuel multiplier",
		text.contains("MowerUpgrades.fuel_multiplier(MOWER_ID)"))
	_check("Effects: the rider's controller applies the handling multiplier",
		text.contains("MowerUpgrades.handling_multiplier(MOWER_ID)"))
	MowerUpgrades.reset_all()


# ======================================================================== jobs

## THE PRICE LOCK. The single most important economy rule: what a contract pays
## is decided when it is OFFERED and never again.
func _test_job_pricing_and_lock() -> void:
	Economy.start_new_economy(SIM_SEED, 0)
	GameSession.start_new_game()

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(2)
		offers = JobManager.available_jobs()
	_check("Jobs: offers exist", not offers.is_empty())
	if offers.is_empty():
		return

	var job: ACAJob = offers[0]
	var agreed := job.base_pay
	_check("Jobs: an offer records what the market did (base %d x %.2f -> %d)"
		% [job.market_base_pay, job.market_multiplier, job.base_pay],
		job.market_base_pay > 0)
	_check("Jobs: the offered pay is a round number", job.base_pay % 5 == 0)

	JobManager.accept_job(job.id)

	# Now wreck the economy and check the handshake held.
	for day in range(1, 120):
		Economy.advance_to_day(day)
	_check("Jobs: ACCEPTED PAY IS LOCKED across %.0f days of market movement"
		% 120.0, job.base_pay == agreed)

	# THE GUARANTEE IS ABOUT `base_pay`, NOT ABOUT THE TOTAL.
	#
	# This used to assert that completing a contract moved the balance by
	# EXACTLY the agreed figure, which is only true of a contract that earns no
	# bonus at all - and which of the board's offers that happens to be moves
	# whenever anything about generation changes. It broke the first time the
	# board's contents changed for an unrelated reason, and it was right to,
	# because it was measuring the wrong thing.
	#
	# What the game actually promises is that `base_pay` is what the board said
	# and is never rewritten. Everything above it is a BONUS, itemised on the
	# results sheet - contract terms met, and the premium for a rescue.
	var money_before := GameSession.money()
	# MERGED, NOT ASSIGNED. A GDScript lambda captures a local by VALUE, so
	# `settled = summary` inside one leaves the outer dictionary empty; merging
	# into it mutates the object both sides are holding.
	var settled := {}
	var listener := func(summary: Dictionary) -> void: settled.merge(summary, true)
	GameSession.job_settled.connect(listener)
	JobManager.begin_new_job(job.id)
	GameSession.complete_current_job(1.0, 60.0)
	GameSession.job_settled.disconnect(listener)

	var paid := GameSession.money() - money_before
	var bonus := int(settled.get("bonus", 0))
	_check("Jobs: the sheet's base pay IS the agreed figure (%d)" % agreed,
		int(settled.get("base_pay", -1)) == agreed)
	_check("Jobs: the balance moved by the agreed figure plus the itemised "
		+ "bonus (%d = %d + %d)" % [paid, agreed, bonus],
		paid == agreed + bonus)
	_check("Jobs: and the sheet's total agrees with the balance (%d)" % paid,
		int(settled.get("total", -1)) == paid)


# ================================================================ persistence

func _test_persistence() -> void:
	# `save_game()` refuses from anywhere but Town or Mowing, and
	# `start_new_game()` changes scene asynchronously - so the arrival has to be
	# waited for rather than assumed.
	GameSession.start_new_game()
	await _await_screen(ACAGameSession.Screen.TOWN)
	Economy.start_new_economy(SIM_SEED, 0)
	for day in range(1, 37):
		Economy.advance_to_day(day)
	MowerUpgrades.reset_all()
	GameSession.add_money(50000)
	MowerUpgrades.try_purchase("rider", "drive")
	MowerUpgrades.try_purchase("rider", "drive")
	MowerUpgrades.try_purchase("push", "bearings")

	var condition := Economy.condition()
	var price := Economy.fuel_price_per_unit()
	var event := Economy.event_id()
	var event_days := Economy.event_days_remaining()
	var rider_level := MowerUpgrades.level("rider", "drive")

	_check("Save: wrote a slot", SaveService.save_game())
	await get_tree().process_frame

	# Corrupt live state as thoroughly as possible before loading it back.
	Economy.start_new_economy(SIM_SEED + 12345, 0)
	Economy.advance_to_day(9)
	MowerUpgrades.reset_all()

	_check("Load: read the slot back", SaveService.load_most_recent())
	await get_tree().process_frame

	_check("Load: the economic CONDITION came back", Economy.condition() == condition)
	_check("Load: THE MARKET WAS NOT REROLLED (fuel $%.4f)" % price,
		is_equal_approx(Economy.fuel_price_per_unit(), price))
	_check("Load: the active event came back", Economy.event_id() == event)
	_check("Load: with its remaining duration",
		Economy.event_days_remaining() == event_days)
	_check("Load: per-mower upgrade levels came back",
		MowerUpgrades.level("rider", "drive") == rider_level
		and MowerUpgrades.level("push", "bearings") == 1)
	_check("Load: and did not leak between mowers",
		MowerUpgrades.level("powered", "drive") == 0)

	# OLD SAVE MIGRATION. A save written before the economy existed must load.
	var legacy := {
		"save_format_version": SaveService.SAVE_FORMAT_VERSION,
		"world": WorldClock.to_save_dict(),
		"jobs": JobManager.save_state(),
		"session": GameSession.to_save_dict(),
		"mower": {},
	}
	_check("Migration: a legacy save has no economy section",
		not legacy.has("economy") and not legacy.has("upgrades"))
	var path := SaveService.storage_root().path_join("legacy_test.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(legacy, "\t"))
		f.close()
	_check("Migration: an old save without economy data still loads",
		SaveService.load_game("legacy_test"))
	await get_tree().process_frame
	_check("Migration: and it gets a working market rather than a broken one",
		Economy.fuel_price_per_unit() > 0.0 and not Economy.condition_name().is_empty())
	_check("Migration: with upgrades defaulted to stock",
		is_equal_approx(MowerUpgrades.speed_multiplier("rider"), 1.0))


# ============================================================ the long simulation

## NINETY DAYS, FIXED SEED, AND THE NUMBERS PRINTED.
##
## Unit tests prove the economy is consistent. They cannot tell anyone whether
## fuel spends three months at the ceiling, or whether a recession arrives every
## other week. This prints what actually happened so a human can look at it, and
## fails on values that are plainly absurd rather than merely debatable.
func _simulate_ninety_days() -> void:
	Economy.start_new_economy(SIM_SEED, 0)

	var fuel_min := 999.0
	var fuel_max := 0.0
	var fuel_total := 0.0
	var job_min := 999.0
	var job_max := 0.0
	var equip_min := 999.0
	var equip_max := 0.0
	var condition_days := {}
	var events: Array[String] = []
	var event_days := 0
	var biggest_drift := 0.0
	var biggest_step := 0.0
	var previous_fuel := Economy.fuel_price_per_unit()
	var previous_event := Economy.event_id()
	var previous_condition := Economy.condition()
	var upgrade_min := 999999
	var upgrade_max := 0

	for day in range(1, SIM_DAYS + 1):
		Economy.advance_to_day(day)
		var fuel := Economy.fuel_price_per_unit()
		fuel_min = minf(fuel_min, fuel)
		fuel_max = maxf(fuel_max, fuel)
		fuel_total += fuel
		# Three kinds of day, and only one of them is drift.
		#
		# An event starting or ending is a STEP - the depot's price really does
		# change overnight when a shortage is announced. A REGIME changing is a
		# step for the same reason. Everything else is DRIFT, and drift is the
		# thing that has to stay gentle; measuring all three together only
		# proves that events exist.
		var move := absf(fuel - previous_fuel) / maxf(previous_fuel, 0.01)
		var stepped := Economy.event_id() != previous_event 			or Economy.condition() != previous_condition
		if stepped:
			biggest_step = maxf(biggest_step, move)
		else:
			biggest_drift = maxf(biggest_drift, move)
		previous_event = Economy.event_id()
		previous_condition = Economy.condition()
		previous_fuel = fuel

		job_min = minf(job_min, Economy.job_index())
		job_max = maxf(job_max, Economy.job_index())
		equip_min = minf(equip_min, Economy.equipment_index())
		equip_max = maxf(equip_max, Economy.equipment_index())

		var upgrade := Economy.equipment_price(ACAMowerUpgrades.base_cost("drive", 3))
		upgrade_min = mini(upgrade_min, upgrade)
		upgrade_max = maxi(upgrade_max, upgrade)

		var name := Economy.condition_name()
		condition_days[name] = int(condition_days.get(name, 0)) + 1
		if Economy.has_event():
			event_days += 1
			var e := Economy.event_name()
			if events.is_empty() or events[-1] != e:
				events.append(e)

	var fuel_mean := fuel_total / float(SIM_DAYS)

	print("\n[ECONOMY] ---- %d-day simulation, seed %d ----" % [SIM_DAYS, SIM_SEED])
	print("[ECONOMY] fuel price      min $%.2f   mean $%.2f   max $%.2f"
		% [fuel_min, fuel_mean, fuel_max])
	print("[ECONOMY] biggest daily drift  %.1f%%   biggest event step  %.1f%%"
		% [biggest_drift * 100.0, biggest_step * 100.0])
	print("[ECONOMY] job index       %.2f .. %.2f" % [job_min, job_max])
	print("[ECONOMY] equipment index %.2f .. %.2f" % [equip_min, equip_max])
	print("[ECONOMY] a level-3 drive upgrade cost $%d .. $%d over the run"
		% [upgrade_min, upgrade_max])
	print("[ECONOMY] days per condition: %s" % str(condition_days))
	print("[ECONOMY] %d event days across %d events: %s"
		% [event_days, events.size(), ", ".join(events)])

	# Absurdity guards, not taste. These are the values that would make the
	# system unplayable rather than merely unbalanced.
	_check("Sim: fuel never collapses (min $%.2f)" % fuel_min, fuel_min > 0.55)
	_check("Sim: fuel never explodes (max $%.2f)" % fuel_max, fuel_max < 2.20)
	_check("Sim: fuel averages near its base (mean $%.2f vs base $%.2f)"
		% [fuel_mean, ACAEconomyManager.BASE_FUEL_PRICE],
		absf(fuel_mean - ACAEconomyManager.BASE_FUEL_PRICE) < 0.30)
	_check("Sim: fuel DRIFTS gently day to day (max %.1f%%)"
		% (biggest_drift * 100.0), biggest_drift < 0.08)
	_check("Sim: an event or regime change moves fuel by a believable step (max %.1f%%)"
		% (biggest_step * 100.0), biggest_step < 0.28)
	_check("Sim: job pay stays within reason (%.2f .. %.2f)" % [job_min, job_max],
		job_min > 0.60 and job_max < 1.60)
	_check("Sim: equipment stays within reason (%.2f .. %.2f)"
		% [equip_min, equip_max], equip_min > 0.70 and equip_max < 1.60)
	_check("Sim: the market is not permanently in crisis (%d of %d days evented)"
		% [event_days, SIM_DAYS], event_days < SIM_DAYS / 2)
	_check("Sim: something actually happened (%d events)" % events.size(),
		events.size() >= 2)
	_check("Sim: more than one condition was visited (%d)" % condition_days.size(),
		condition_days.size() >= 2)


## A LONGER, WIDER look. One 90-day run with one seed can be lucky; this walks
## several seeds a full year each and reports the extremes, so a pathology that
## only shows up in some markets has somewhere to appear.
##
## Assertions here are on the WORST case across every seed, not on an average.
func _sweep_seeds() -> void:
	var days := _int_arg("--economy-days=", 365)
	var seeds := _int_arg("--economy-seeds=", 6)

	print("
[ECONOMY] ---- sweep: %d seeds x %d days ----" % [seeds, days])
	var worst_low := 99.0
	var worst_high := 0.0
	var worst_drift := 0.0
	var worst_event_share := 0.0
	var worst_regime_share := 0.0

	for i in range(seeds):
		var seed_value := SIM_SEED + i * 7919
		Economy.start_new_economy(seed_value, 0)
		var low := 99.0
		var high := 0.0
		var drift := 0.0
		var event_days := 0
		var condition_days := {}
		var previous := Economy.fuel_price_per_unit()
		var previous_event := Economy.event_id()
		var previous_condition := Economy.condition()

		for day in range(1, days + 1):
			Economy.advance_to_day(day)
			var fuel := Economy.fuel_price_per_unit()
			low = minf(low, fuel)
			high = maxf(high, fuel)
			var stepped := Economy.event_id() != previous_event 				or Economy.condition() != previous_condition
			if not stepped:
				drift = maxf(drift, absf(fuel - previous) / maxf(previous, 0.01))
			previous = fuel
			previous_event = Economy.event_id()
			previous_condition = Economy.condition()
			if Economy.has_event():
				event_days += 1
			var name := Economy.condition_name()
			condition_days[name] = int(condition_days.get(name, 0)) + 1

		# The share of the year spent in the single most common condition. A
		# market stuck in one regime for a year is not a market.
		var most := 0
		for key: String in condition_days:
			most = maxi(most, int(condition_days[key]))
		var regime_share := float(most) / float(days)
		var event_share := float(event_days) / float(days)

		print("[ECONOMY] seed %-10d fuel $%.2f-$%.2f  drift %.1f%%  events %.0f%%  top regime %.0f%% %s"
			% [seed_value, low, high, drift * 100.0, event_share * 100.0,
				regime_share * 100.0, str(condition_days)])

		worst_low = minf(worst_low, low)
		worst_high = maxf(worst_high, high)
		worst_drift = maxf(worst_drift, drift)
		worst_event_share = maxf(worst_event_share, event_share)
		worst_regime_share = maxf(worst_regime_share, regime_share)

	_check("Sweep: fuel never collapses in ANY market (worst $%.2f)" % worst_low,
		worst_low > 0.55)
	_check("Sweep: fuel never explodes in ANY market (worst $%.2f)" % worst_high,
		worst_high < 2.20)
	_check("Sweep: drift stays gentle in ANY market (worst %.1f%%)"
		% (worst_drift * 100.0), worst_drift < 0.09)
	_check("Sweep: no market is permanently evented (worst %.0f%% of days)"
		% (worst_event_share * 100.0), worst_event_share < 0.55)
	_check("Sweep: no market is stuck in one regime for a year (worst %.0f%%)"
		% (worst_regime_share * 100.0), worst_regime_share < 0.85)


func _int_arg(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return int(arg.trim_prefix(prefix))
	return fallback


# ==================================================================== helpers

func _await_screen(screen: int) -> void:
	var guard := 0
	while GameSession.current_screen() != screen and guard < 600:
		await get_tree().process_frame
		guard += 1
	for i in range(4):
		await get_tree().process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[ECON] %s: PASS" % label)
	else:
		_fail += 1
		printerr("[ECON] %s: FAIL" % label)


# ================================================================== difficulty

## The profile TABLE, before anything reads a price from it. Every one of these
## is a claim the balance report makes, so every one of them is asserted rather
## than trusted.
func _test_difficulty_profiles() -> void:
	_check("difficulty: three profiles are offered to a new game",
		ACADifficulty.PLAYER_IDS.size() == 3
			and ACADifficulty.PLAYER_IDS.has(&"easy")
			and ACADifficulty.PLAYER_IDS.has(&"medium")
			and ACADifficulty.PLAYER_IDS.has(&"hard"))
	_check("difficulty: legacy exists and is NOT offered to a new game",
		ACADifficulty.is_valid(ACADifficulty.LEGACY_ID)
			and not ACADifficulty.PLAYER_IDS.has(ACADifficulty.LEGACY_ID))
	_check("difficulty: medium is the default", ACADifficulty.DEFAULT_ID == &"medium")

	# LEGACY IS THE SHIPPED GAME. If any of these drift, an old save's economy
	# has been changed underneath it, which is the one thing this profile exists
	# to prevent.
	var legacy: Dictionary = ACADifficulty.profile(ACADifficulty.LEGACY_ID)
	_check("difficulty: legacy money is the shipped constant",
		int(legacy["starting_money"]) == ACAGameSession.STARTING_MONEY)
	_check("difficulty: legacy fuel price is the shipped constant",
		is_equal_approx(float(legacy["base_fuel_price"]),
			ACAEconomyManager.BASE_FUEL_PRICE))
	_check("difficulty: legacy event chance is the shipped constant",
		is_equal_approx(float(legacy["event_daily_chance"]),
			ACAEconomyManager.EVENT_DAILY_CHANCE))
	_check("difficulty: legacy tank is the shipped constant",
		is_equal_approx(float(legacy["full_tank_driving_seconds"]),
			ACAMowerFuel.FULL_TANK_DRIVING_SECONDS))
	_check("difficulty: legacy scales nothing",
		is_equal_approx(float(legacy["job_pay_scale"]), 1.0)
			and is_equal_approx(float(legacy["upgrade_cost_scale"]), 1.0)
			and is_equal_approx(float(legacy["recession_job_scale"]), 1.0))

	# The recession scale is a scale on the DEVIATION. This is the formula the
	# report documents, checked against the production condition table.
	_check("difficulty: the recession base matches the production condition",
		is_equal_approx(ACADifficulty.RECESSION_BASE_JOB,
			float(ACAEconomyManager.CONDITIONS[
				ACAEconomyManager.Condition.RECESSION]["job"])))
	var restore := ACADifficulty.active_id()
	var effective := {}
	for id: StringName in [&"easy", &"medium", &"hard"]:
		ACADifficulty.set_active(id)
		effective[id] = ACADifficulty.recession_job_multiplier()
	ACADifficulty.set_active(restore)
	_check("difficulty: medium reproduces the shipped recession multiplier exactly",
		is_equal_approx(float(effective[&"medium"]), 0.84))
	_check("difficulty: the downturn deepens Easy -> Medium -> Hard (%.3f / %.3f / %.3f)"
		% [effective[&"easy"], effective[&"medium"], effective[&"hard"]],
		float(effective[&"easy"]) > float(effective[&"medium"])
			and float(effective[&"medium"]) > float(effective[&"hard"]))

	# A profile that does not exist must not silently become an empty one.
	ACADifficulty.set_active(&"nonsense")
	_check("difficulty: an unknown id falls back to the default",
		ACADifficulty.active_id() == ACADifficulty.DEFAULT_ID)
	ACADifficulty.set_active(restore)


## The prices themselves, read through the same public API the shops use.
func _test_difficulty_prices() -> void:
	var restore := ACADifficulty.active_id()
	var fuel := {}
	var upgrade := {}
	for id: StringName in [&"easy", &"medium", &"hard"]:
		ACADifficulty.set_active(id)
		fuel[id] = Economy.base_fuel_price()
		upgrade[id] = MowerUpgrades.base_cost("fuel_system", 1) \
			* ACADifficulty.value("upgrade_cost_scale", 1.0)
	ACADifficulty.set_active(restore)

	_check("difficulty: fuel gets dearer Easy -> Medium -> Hard ($%.2f / $%.2f / $%.2f)"
		% [fuel[&"easy"], fuel[&"medium"], fuel[&"hard"]],
		float(fuel[&"easy"]) < float(fuel[&"medium"])
			and float(fuel[&"medium"]) < float(fuel[&"hard"]))
	_check("difficulty: equipment gets dearer Easy -> Medium -> Hard",
		float(upgrade[&"easy"]) < float(upgrade[&"medium"])
			and float(upgrade[&"medium"]) < float(upgrade[&"hard"]))

	# THE SHOP MUST CHARGE WHAT IT SHOWS. `next_cost()` is the only price in the
	# game, and it already has both the difficulty and the market on it, so a UI
	# that applies either again would be wrong twice over.
	ACADifficulty.set_active(&"hard")
	var shown := MowerUpgrades.next_cost("rider", "fuel_system")
	var before := GameSession.money()
	GameSession.add_money(shown + 500)
	var bought := MowerUpgrades.try_purchase("rider", "fuel_system")
	var spent := (before + shown + 500) - GameSession.money()
	_check("difficulty: the price charged is exactly the price shown ($%d)" % shown,
		bought and spent == shown)
	MowerUpgrades.reset_all()
	ACADifficulty.set_active(restore)


## The difficulty is part of the save, an old save keeps the economy it was
## played on, and neither costs a save format version.
func _test_difficulty_persistence() -> void:
	var restore := GameSession.difficulty()

	GameSession.start_new_game(&"hard")
	await _await_screen(ACAGameSession.Screen.TOWN)
	_check("difficulty: a new game starts on the profile it was asked for",
		GameSession.difficulty() == &"hard")
	_check("difficulty: the opening float comes from the profile ($%d)"
		% GameSession.money(),
		GameSession.money() == int(ACADifficulty.profile(&"hard")["starting_money"]))
	var written := GameSession.to_save_dict()
	_check("difficulty: it is written into the session block",
		String(written.get("difficulty", "")) == "hard")

	GameSession.from_save_dict(written)
	_check("difficulty: it round trips through a save",
		GameSession.difficulty() == &"hard")

	# A SAVE FROM BEFORE ANY OF THIS EXISTED.
	var old_save := {"money": 900, "session_active": true, "job_elapsed_seconds": 0.0}
	GameSession.from_save_dict(old_save)
	_check("difficulty: a save with no difficulty loads as legacy",
		GameSession.difficulty() == ACADifficulty.LEGACY_ID)
	_check("difficulty: ...and legacy restores the shipped fuel price",
		is_equal_approx(Economy.base_fuel_price(), ACAEconomyManager.BASE_FUEL_PRICE))
	_check("difficulty: ...and the save's own money is untouched",
		GameSession.money() == 900)

	GameSession.start_new_game(restore)
	await _await_screen(ACAGameSession.Screen.TOWN)


## THE RECESSION MARKET BRIDGE. `Economy` says there is a downturn; the Job
## System reduces how many contracts are on the board. Neither knows about the
## other, so what is under test is the application layer that joins them.
func _test_recession_market_bridge() -> void:
	var normal_strength := JobManager.market_strength()
	_check("recession: ordinary trading leaves the market at full strength (%d)"
		% normal_strength, normal_strength == 4)

	# Drive the CONDITION, not the market, and let the bridge do the rest.
	Economy.debug_force_condition(ACAEconomyManager.Condition.RECESSION)
	await get_tree().process_frame
	var recession_strength := JobManager.market_strength()
	_check("recession: a downturn cuts offer capacity from 4 to 2 (got %d)"
		% recession_strength, recession_strength == 2)
	_check("recession: the Job System was told through its own economy input",
		int(JobManager.economy) == int(ACAJobEnums.Economy.RECESSION))

	Economy.debug_force_condition(ACAEconomyManager.Condition.STABLE)
	await get_tree().process_frame
	_check("recession: capacity comes back when the downturn ends (%d)"
		% JobManager.market_strength(), JobManager.market_strength() == 4)
	_check("recession: ...and so does the Job System's economy input",
		int(JobManager.economy) == int(ACAJobEnums.Economy.NORMAL))
