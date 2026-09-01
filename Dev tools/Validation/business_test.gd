extends Node
## DEVELOPMENT ONLY. The BUSINESS LAYER's contracts, asserted behaviourally.
##
##   godot --headless --path . "res://Dev tools/Validation/Business Test.tscn" \
##       -- "--save-root=<dir>"
##
## Targeted, not exhaustive. One assertion per thing that would be a real fault
## if it broke, and nothing that merely restates a constant back to itself.
##
## What is deliberately NOT here: how much a contract pays, how often a term is
## rolled, what a competitor's appetite is. Those are balance, they will move,
## and a test that pins them would have to be edited every time somebody tunes a
## number - which trains people to edit tests until they pass.

const KG_TOLERANCE := 0.001

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	_say("EQUIPMENT")
	_test_starting_ownership()
	_test_mower_purchase()
	_test_selection_follows_ownership()
	_test_legacy_ownership_inference()

	_say("CLIPPINGS")
	_test_bag_fills_from_fresh_cuts_only()
	_test_full_bag_stops_collecting_not_mowing()
	_test_unload_moves_it_to_the_yard()
	_test_selling_pays_once()
	_test_composting()

	_say("CONTRACT TERMS")
	_test_terms_are_derived_not_stored()
	_test_terms_score_against_measurements()

	_say("THE COMPANY")
	_test_reputation_moves_with_reviews()
	_test_review_is_derived_from_the_contract()
	_test_recurring_customer_keeps_the_seed()
	_test_market_share()
	_test_schedule()
	_test_yard_only_goes_up()

	_say("PERSISTENCE")
	_test_round_trip()
	_test_a_save_without_the_new_sections()

	print("[BUSINESS TEST] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ================================================================== equipment

func _test_starting_ownership() -> void:
	Equipment.reset_to_new_business()
	_check("a new business owns the Rider it has always driven",
		Equipment.owns("rider"))
	_check("and does not own the other two yet",
		not Equipment.owns("powered") and not Equipment.owns("push"))
	_check("the Rider is what goes to the first contract",
		String(Equipment.selected_mower()) == "rider")


func _test_mower_purchase() -> void:
	Equipment.reset_to_new_business()
	GameSession.add_money(100000 - GameSession.money())
	var before := GameSession.money()
	var cost := Equipment.purchase_cost("push")
	_check("an unowned machine has a price", cost > 0)
	_check("buying it succeeds", Equipment.try_purchase_mower("push"))
	_check("it is owned afterwards", Equipment.owns("push"))
	_check_eq("the money left exactly its price",
		GameSession.money(), before - cost)
	_check("an owned machine has no price", Equipment.purchase_cost("push") < 0)
	_check("and cannot be bought twice",
		not Equipment.try_purchase_mower("push"))


func _test_selection_follows_ownership() -> void:
	Equipment.reset_to_new_business()
	_check("a machine the business does not own cannot be selected",
		not Equipment.select_mower("powered"))
	Equipment.dev_grant_mower("powered")
	_check("one it does own can be", Equipment.select_mower("powered"))
	_check_eq("and that is what the next contract gets",
		String(Equipment.selected_mower()), "powered")
	# THE SELECTION CAN NEVER BE A MACHINE THAT IS NOT THERE. Nothing in the
	# game removes ownership today, but a selection that could go stale would
	# send the player to a contract with nothing to mow it.
	Equipment.reset_to_new_business()
	_check_eq("a reset falls back to an owned machine",
		String(Equipment.selected_mower()), "rider")


## A save from before ownership existed is not a business with one machine in a
## shed and three unaccounted for. It owned the Rider it always drove, PLUS
## anything it had plainly spent money improving.
func _test_legacy_ownership_inference() -> void:
	MowerUpgrades.reset_all()
	MowerUpgrades.dev_set_level("push", "bearings", 3)
	Equipment.from_save_dict({}, MowerUpgrades)
	_check("a legacy save keeps the Rider", Equipment.owns("rider"))
	_check("and the Push Mower it had bought upgrades for",
		Equipment.owns("push"))
	_check("but not one it never touched", not Equipment.owns("powered"))
	MowerUpgrades.reset_all()


# ================================================================== clippings

func _test_bag_fills_from_fresh_cuts_only() -> void:
	Clippings.reset_to_new_business()
	Clippings.start_new_job(90.0)
	_check_close("an empty machine starts empty", Clippings.bag_kilograms(), 0.0)
	var taken := Clippings.collect_from_cells(1000)
	_check_close("a thousand fresh cells is a thousand cells' worth",
		taken, 1000.0 * ACAClippings.KG_PER_CELL)
	# THE POINT OF THE WHOLE DESIGN: driving over ground that is already cut
	# reports NO cells, so it produces nothing. There is nothing to farm.
	var nothing := Clippings.collect_from_cells(0)
	_check_close("no cells cut produces nothing", nothing, 0.0)
	_check_close("and the bag did not move", Clippings.bag_kilograms(),
		1000.0 * ACAClippings.KG_PER_CELL)


func _test_full_bag_stops_collecting_not_mowing() -> void:
	Clippings.reset_to_new_business()
	Clippings.start_new_job(10.0)
	var filled := [false]
	Clippings.bag_filled.connect(func() -> void: filled[0] = true, CONNECT_ONE_SHOT)
	var huge := int(20.0 / ACAClippings.KG_PER_CELL)
	var taken := Clippings.collect_from_cells(huge)
	_check("the catcher announced itself full", filled[0])
	_check_close("it took exactly its capacity and no more", taken, 10.0)
	_check("the rest was left on the lawn", Clippings.spilled_this_job() > 0.0)
	# A FULL CATCHER DOES NOT STOP THE MOWING. The next call still reports the
	# grass as cut; it simply collects none of it.
	var after := Clippings.collect_from_cells(500)
	_check_close("a full catcher collects nothing more", after, 0.0)
	_check_close("and the bag stays exactly full", Clippings.bag_kilograms(), 10.0)

	# A MULCHING MACHINE collects nothing at all, and that is not the same as
	# being full - it never announces anything and never spills.
	Clippings.start_new_job(0.0)
	_check_close("a mulching machine collects nothing",
		Clippings.collect_from_cells(1000), 0.0)
	_check("and does not report a catcher at all", not Clippings.machine_collects())


func _test_unload_moves_it_to_the_yard() -> void:
	Clippings.reset_to_new_business()
	Clippings.start_new_job(90.0)
	Clippings.collect_from_cells(2000)
	var in_bag := Clippings.bag_kilograms()
	_check("there is something to unload", in_bag > 0.0)
	var moved := Clippings.unload_to_truck()
	_check_close("everything in the bag moved", moved, in_bag)
	_check_close("the bag is empty", Clippings.bag_kilograms(), 0.0)
	# THE MACHINE EMPTIES INTO THE TRAILER, not into the yard. A working day can
	# be several stops between one visit to a service lot and the next, so there
	# has to be somewhere on the truck for the grass to be in the meantime.
	_check_close("the trailer has it", Clippings.trailer_kilograms(), in_bag)
	_check_close("the yard does not, yet", Clippings.fresh_kilograms(), 0.0)
	var deposited := Clippings.deposit_trailer_at_yard()
	_check_close("arriving at a service lot empties the trailer", deposited, in_bag)
	_check_close("and the yard has it now", Clippings.fresh_kilograms(), in_bag)
	_check_close("with nothing left on the trailer",
		Clippings.trailer_kilograms(), 0.0)
	_check_close("and the contract counts it as delivered",
		Clippings.delivered_this_job(), in_bag)
	_check_close("unloading an empty bag moves nothing",
		Clippings.unload_to_truck(), 0.0)


func _test_selling_pays_once() -> void:
	Clippings.reset_to_new_business()
	Clippings.dev_add_fresh(200.0)
	var value := Clippings.fresh_sale_value()
	_check("a full yard is worth something", value > 0)
	var before := GameSession.money()
	var paid := Clippings.sell_fresh()
	_check_eq("it paid what it said it would", paid, value)
	_check_eq("and the balance moved by exactly that",
		GameSession.money(), before + value)
	_check_close("the yard is empty", Clippings.fresh_kilograms(), 0.0)
	# THE ONE THING A SHOP MUST NEVER DO.
	var again := Clippings.sell_fresh()
	_check_eq("selling again pays nothing", again, 0)
	_check_eq("and the balance did not move again",
		GameSession.money(), before + value)


func _test_composting() -> void:
	Clippings.reset_to_new_business()
	Clippings.dev_add_fresh(100.0)
	var started := Clippings.start_composting(10)
	_check_close("the whole fresh pile went on the heap", started, 100.0)
	_check_close("nothing fresh is left", Clippings.fresh_kilograms(), 0.0)
	_check_close("it is on the heap", Clippings.composting_kilograms(), 100.0)
	_check_close("and is not compost yet", Clippings.compost_kilograms(), 0.0)
	_check_eq("it is due in the stated number of days",
		Clippings.days_until_compost(10), ACAClippings.COMPOST_DAYS)

	_check_close("a day early is still not compost",
		Clippings.advance_to_day(10 + ACAClippings.COMPOST_DAYS - 1), 0.0)
	var finished := Clippings.advance_to_day(10 + ACAClippings.COMPOST_DAYS)
	_check_close("on the day, it is - lighter, as a heap is",
		finished, 100.0 * ACAClippings.COMPOST_YIELD)
	_check("and a kilogram of it is worth more than a fresh one",
		Clippings.compost_price_per_kg() > Clippings.fresh_price_per_kg())


# ============================================================= contract terms

## The whole reason terms are a pure function of the seed: nothing about them is
## saved, so nothing about them can be lost, migrated or disagreed about.
func _test_terms_are_derived_not_stored() -> void:
	var job := _make_job(4242)
	var first := ACAContractTerms.terms_for(job)
	var second := ACAContractTerms.terms_for(job)
	_check_eq("the same contract asks for the same things twice",
		int(first["flags"]), int(second["flags"]))

	# A DIFFERENT OBJECT WITH THE SAME SEED IS THE SAME CONTRACT. This is what
	# makes a save reload, and a recurring customer, ask for the same things.
	var rebuilt := _make_job(4242)
	_check_eq("and so does a contract rebuilt from the same seed",
		ACAContractTerms.flags_of(rebuilt), int(first["flags"]))

	var different := _make_job(4243)
	var differ := 0
	for candidate in range(4243, 4283):
		if ACAContractTerms.flags_of(_make_job(candidate)) != int(first["flags"]):
			differ += 1
	_check("different seeds ask for different things (%d of 40 differ)" % differ,
		differ > 5)
	_check("a null contract asks for nothing",
		ACAContractTerms.flags_of(null) == int(ACAContractTerms.Flag.NONE))


func _test_terms_score_against_measurements() -> void:
	# A contract that definitely collects, built by searching for one rather
	# than by asserting that a particular seed does - which would be a test of
	# the seed rather than of the scoring.
	var job := _find_job_with(int(ACAContractTerms.Flag.COLLECT))
	if job == null:
		_check("could not find a collection contract in 400 seeds", false)
		return
	var target := float(ACAContractTerms.terms_for(job)["collect_target_kg"])
	_check("a collection contract expects a real weight", target > 0.0)

	var met := ACAContractTerms.score(job, {
		"completion": 1.0, "collected_kg": target, "elapsed_minutes": 1.0,
		"ran_dry": false,
	})
	_check("delivering what was asked meets the term",
		(int(met["met"]) & int(ACAContractTerms.Flag.COLLECT)) != 0)
	_check("and pays a bonus", int(met["bonus"]) > 0)

	var missed := ACAContractTerms.score(job, {
		"completion": 1.0, "collected_kg": 0.0, "elapsed_minutes": 1.0,
		"ran_dry": false,
	})
	_check("delivering none of it misses the term",
		(int(missed["missed"]) & int(ACAContractTerms.Flag.COLLECT)) != 0)
	_check("and pays no bonus for it",
		int(missed["bonus"]) < int(met["bonus"]))


# =============================================================== the company

func _test_reputation_moves_with_reviews() -> void:
	Business.reset_to_new_business()
	var job := _make_job(777)
	var start := Business.reputation()

	Business.settle_completed_job(job, {
		"completion": 1.0, "collected_kg": 9999.0,
		"elapsed_minutes": 1.0, "ran_dry": false,
	}, 300)
	_check("a clean contract raises the business's standing",
		Business.reputation() > start)

	var high := Business.reputation()
	Business.settle_completed_job(_make_job(778), {
		"completion": 0.3, "collected_kg": 0.0,
		"elapsed_minutes": 9999.0, "ran_dry": true,
	}, 50)
	_check("a bad one lowers it", Business.reputation() < high)

	var before_abandon := Business.reputation()
	Business.record_abandoned_job(_make_job(779))
	_check("and walking away costs more than doing it badly",
		before_abandon - Business.reputation() > 2.5)


func _test_review_is_derived_from_the_contract() -> void:
	var job := _make_job(881)
	var good := {"completion": 1.0, "collected_kg": 99999.0,
		"elapsed_minutes": 0.5, "ran_dry": false}
	var bad := {"completion": 0.2, "collected_kg": 0.0,
		"elapsed_minutes": 99999.0, "ran_dry": true}
	_check("a finished, tidy contract rates well", ACABusiness.rate(job, good) >= 4)
	_check("an abandoned one rates badly", ACABusiness.rate(job, bad) <= 2)
	_check_eq("the same contract and outcome rate the same twice",
		ACABusiness.rate(job, good), ACABusiness.rate(job, good))

	var text := ACABusiness.review_text(job, 3, int(ACAContractTerms.Flag.COLLECT))
	_check("a missed term is named in the review",
		text.to_lower().contains("clippings"))
	_check_eq("and the same review is written twice", text,
		ACABusiness.review_text(job, 3, int(ACAContractTerms.Flag.COLLECT)))
	# NO PEOPLE. Not a stylistic preference - it is the project's standing art
	# direction, and a review is the one place a name could creep back in.
	for stars in range(1, 6):
		for line: String in ACABusiness.REVIEW_LINES[stars]:
			_check_quiet("no review names anybody: \"%s\"" % line,
				not line.contains("Mr") and not line.contains("Mrs")
				and not line.contains("'s "))


## THE POINT OF A RECURRING CUSTOMER: the contract that comes back rebuilds the
## same property, because it carries the same seed. A customer who returned as a
## different garden would be a different customer with the same label.
func _test_recurring_customer_keeps_the_seed() -> void:
	Business.reset_to_new_business()
	var job := _make_job(9001)
	_check("a property nobody has cut is not a returning customer",
		not Business.is_returning_customer(job))
	Business.settle_completed_job(job, {"completion": 1.0}, 200)
	_check("after one visit it is on the books",
		Business.is_returning_customer(job))
	_check_eq("with one service against it", Business.services_for(job), 1)

	var customers := Business.active_customers()
	_check("the customer book has it", customers.size() == 1)
	if customers.size() > 0:
		_check_eq("and it is stored against the contract's own seed",
			int(customers[0]["seed"]), job.seed)
		_check("with a day it is next due",
			int(customers[0]["next_day"]) > int(customers[0]["last_day"]))

	# A CONTRACT REBUILT FROM THAT SEED IS THE SAME CUSTOMER.
	_check("a fresh contract on the same seed is recognised",
		Business.is_returning_customer(_make_job(9001)))
	_check("and one on another seed is not",
		not Business.is_returning_customer(_make_job(9002)))


func _test_market_share() -> void:
	Business.reset_to_new_business()
	_check_close("a business that has done nothing holds nothing",
		Business.market_share(), 0.0)
	Business.settle_completed_job(_make_job(1201), {"completion": 1.0}, 500)
	_check_close("winning the only contract is the whole market",
		Business.market_share(), 1.0)
	_check("and that is leading it", Business.is_market_leader())

	# MEASURED BY VALUE. Four small contracts do not out-weigh one large one,
	# and a share that said they did would be a share worth ignoring.
	Business.reset_to_new_business()
	Business.settle_completed_job(_make_job(1301), {"completion": 1.0}, 100)
	Business._record_market_result(&"broadacre", 900)
	_check("a tenth of the value is a tenth of the market",
		absf(Business.market_share() - 0.1) < 0.02)
	_check("and is not leading it", not Business.is_market_leader())
	var table := Business.market_table()
	_check("the league table lists both", table.size() == 2)
	_check("biggest first", table.size() == 2 and not bool(table[0]["is_player"]))


func _test_schedule() -> void:
	Business.reset_to_new_business()
	_check("the day starts with nothing planned", Business.schedule_ids().is_empty())
	_check("a stop can be added", Business.add_to_schedule("job_a"))
	_check("but not twice", not Business.add_to_schedule("job_a"))
	Business.add_to_schedule("job_b")
	_check_eq("in the order they were added",
		Business.schedule_ids(), ["job_a", "job_b"] as Array[String])
	_check("a stop can be moved later", Business.reorder_schedule("job_a", 1))
	_check_eq("and the order followed",
		Business.schedule_ids(), ["job_b", "job_a"] as Array[String])
	_check("and removed", Business.remove_from_schedule("job_b"))
	_check_eq("leaving the rest", Business.schedule_ids(), ["job_a"] as Array[String])


## THE PREMISES ARE WHAT THE BUSINESS HAS BUILT. A quiet month should not
## demolish the garage.
func _test_yard_only_goes_up() -> void:
	Business.reset_to_new_business()
	Equipment.reset_to_new_business()
	_check_eq("a new business starts in a shed",
		Business.yard_tier(), ACABusiness.Yard.STARTER)
	_check("and is told what the next step needs",
		not Business.next_yard_requirement().is_empty())

	Business.dev_set_reputation(90.0)
	Business.dev_add_revenue(60000)
	Equipment.dev_grant_mower("powered")
	Equipment.dev_grant_mower("push")
	Equipment.dev_grant_autonomous("auto_compact")
	Equipment.dev_grant_autonomous("auto_grounds")
	Equipment.dev_grant_autonomous("auto_commercial")
	Business.dev_add_revenue(0)
	_check("meeting every gate improves the yard",
		Business.yard_tier() > ACABusiness.Yard.STARTER)

	var reached := Business.yard_tier()
	Business.dev_set_reputation(5.0)
	_check_eq("and a collapse in standing does not take the yard back",
		Business.yard_tier(), reached)


# ================================================================ persistence

func _test_round_trip() -> void:
	Equipment.reset_to_new_business()
	Clippings.reset_to_new_business()
	Business.reset_to_new_business()

	Equipment.dev_grant_mower("push")
	Equipment.select_mower("push")
	var uid := Equipment.dev_grant_autonomous("auto_grounds")
	Clippings.dev_add_fresh(140.0)
	Clippings.start_composting(3)
	Business.dev_set_reputation(71.5)
	Business.settle_completed_job(_make_job(5150), {"completion": 1.0}, 420)
	Business.add_to_schedule("job_x")
	# AFTER the contract settled, because settling one moves the number. The
	# expectation is that a save round trip does not change it, not that a
	# contract does not.
	var reputation := Business.reputation()

	var equipment := Equipment.to_save_dict()
	var clippings := Clippings.to_save_dict()
	var business := Business.to_save_dict()

	Equipment.reset_to_new_business()
	Clippings.reset_to_new_business()
	Business.reset_to_new_business()
	Equipment.from_save_dict(equipment, MowerUpgrades)
	Clippings.from_save_dict(clippings)
	Business.from_save_dict(business)

	_check("ownership survives a round trip", Equipment.owns("push"))
	_check_eq("and so does what was on the trailer",
		String(Equipment.selected_mower()), "push")
	_check_eq("and the autonomous machine", Equipment.autonomous_unit_count(), 1)
	_check("with its own name kept", Equipment.unit_label(uid).contains("Grounds"))
	_check_close("the heap is still on the heap",
		Clippings.composting_kilograms(), 140.0)
	_check_close("reputation survives", Business.reputation(), reputation)
	_check_eq("the customer book survives", Business.customer_count(), 1)
	_check("the customer is still the same property",
		Business.is_returning_customer(_make_job(5150)))
	_check_eq("and the day's plan survives",
		Business.schedule_ids(), ["job_x"] as Array[String])


## A save written before any of this existed. It is not broken, and it is not
## given a history it never had.
func _test_a_save_without_the_new_sections() -> void:
	MowerUpgrades.reset_all()
	Equipment.from_save_dict({}, MowerUpgrades)
	Clippings.from_save_dict({})
	Business.from_save_dict({})

	_check("it still has a machine to drive", Equipment.owned_mower_count() >= 1)
	_check("with one selected", Equipment.owns(String(Equipment.selected_mower())))
	_check_eq("nothing in the yard", Clippings.stored_total(), 0.0)
	_check_close("nothing in the bag", Clippings.bag_kilograms(), 0.0)
	_check_close("an unproven reputation rather than a ruined one",
		Business.reputation(), ACABusiness.STARTING_REPUTATION)
	_check_eq("no customers invented for it", Business.customer_count(), 0)
	_check_eq("no reviews invented for it", Business.recent_reviews(99).size(), 0)
	_check_eq("and no market history invented for it",
		Business.market_table().size(), 0)


# ===================================================================== helpers

## A real contract from the real generator, so every test above runs against the
## same objects the game does.
func _make_job(job_seed: int) -> ACAJob:
	return ACAJobGenerator.generate(job_seed, 0.0,
		ACAJobBalance.GENERATOR_VERSION, 1.0)


## The first seed whose contract carries `flag`. Searching for one rather than
## hard-coding a seed keeps the test about the SCORING rather than about which
## seed happens to roll what.
func _find_job_with(flag: int) -> ACAJob:
	for job_seed in range(1, 400):
		var job := _make_job(job_seed)
		if ACAContractTerms.flags_of(job) & flag:
			return job
	return null


func _say(section: String) -> void:
	print("[BUSINESS] -- %s" % section)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("[BUSINESS]  ok   %s" % label)
	else:
		_fail += 1
		print("[BUSINESS] FAIL  %s" % label)


## For an assertion made in a loop, where one line per iteration would bury the
## report. Only failures are printed.
func _check_quiet(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("[BUSINESS] FAIL  %s" % label)


func _check_eq(label: String, got: Variant, expected: Variant) -> void:
	_check("%s (got %s, expected %s)" % [label, got, expected] if got != expected
		else label, got == expected)


func _check_close(label: String, got: float, expected: float) -> void:
	var ok := absf(got - expected) <= KG_TOLERANCE
	_check("%s (got %.4f, expected %.4f)" % [label, got, expected] if not ok
		else label, ok)
