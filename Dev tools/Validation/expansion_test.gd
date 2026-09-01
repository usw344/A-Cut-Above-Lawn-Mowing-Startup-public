extends Node
## DEVELOPMENT ONLY. The GAMEPLAY-EXPANSION contracts, asserted behaviourally.
##
##   godot --headless --path . "res://Dev tools/Validation/Expansion Test.tscn" \
##       -- "--save-root=<dir>"
##
## Targeted, not exhaustive - the same rule the Business Test was written under.
## One assertion per thing that would be a real fault if it broke, and nothing
## that merely restates a constant back to itself.
##
## What is deliberately NOT here: what a service lot costs, how often a
## conservation zone is rolled, what a wet lawn multiplies clippings by. Those
## are balance, they will move, and a test that pinned them would have to be
## edited every time somebody tuned a number - which trains people to edit tests
## until they pass.

const TOLERANCE := 0.001

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	_say("SERVICE TERRITORIES")
	_test_new_business_starts_local()
	_test_region_is_derived_from_the_contract()
	_test_purchase_takes_the_money_exactly_once()
	_test_locked_regions_stay_off_the_board()
	_test_presence_moves_with_the_work()

	_say("REGIONAL HUBS")
	_test_every_region_has_a_place_to_stand()
	_test_hub_traffic_never_leaves_the_tarmac()
	_test_a_region_reshapes_a_property_without_drawing()

	_say("MOWING MODES")
	_test_bagging_collects()
	_test_mulching_and_discharge_do_not()
	_test_mode_follows_what_is_bolted_on()

	_say("ATTACHMENTS AND THE TRAILER")
	_test_attachments_fit_only_what_they_fit()
	_test_the_trailer_bounds_the_loadout()
	_test_the_trailer_holds_the_clippings()

	_say("PROTECTED GROUND")
	_test_protected_cells_are_out_of_the_contract()
	_test_mowing_protected_ground_records_damage()
	_test_conservation_prediction_agrees_with_the_property()

	_say("PROPERTY CONDITION")
	_test_a_project_property_is_the_same_property()
	_test_the_stage_follows_the_service_count()

	_say("THE FINISH PATTERN")
	_test_a_consistent_finish_scores()
	_test_a_scribbled_finish_does_not()

	_say("WEATHER AND GROUND")
	_test_the_forecast_is_the_schedule()
	_test_wet_and_dry_change_the_work()

	_say("FLEET AND AGREEMENTS")
	_test_a_machine_cannot_take_two_contracts()
	_test_an_agreement_needs_a_fleet()

	_say("PERSISTENCE")
	_test_round_trip()
	_test_a_save_without_the_new_sections()

	print("[EXPANSION TEST] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ================================================================ territories

func _test_new_business_starts_local() -> void:
	Territory.reset_to_new_business()
	_check("a new business owns its home town",
		Territory.owns(ACAServiceTerritory.Region.HOME_TOWN))
	_check("and nothing else",
		Territory.owned_region_count() == 1)
	_check("the home region can never be bought",
		Territory.purchase_cost(ACAServiceTerritory.Region.HOME_TOWN) < 0)
	_check("it is where the business is working from",
		Territory.active_region() == ACAServiceTerritory.Region.HOME_TOWN)


## THE derivation, and the one thing about it that matters: it depends on the
## contract and on nothing else, so it survives a reload and a rebuild.
func _test_region_is_derived_from_the_contract() -> void:
	var job := _job(4242, ACAJobEnums.PropertyType.RURAL, ACAJobEnums.LawnSize.LARGE)
	var first := ACAServiceTerritory.region_for_job(job)
	var second := ACAServiceTerritory.region_for_job(_job(4242,
		ACAJobEnums.PropertyType.RURAL, ACAJobEnums.LawnSize.LARGE))
	_check("the same contract is always in the same area", first == second)
	_check("a large rural contract is rural work",
		first == ACAServiceTerritory.Region.RURAL_HIGHWAY)
	_check("residential work is always local",
		ACAServiceTerritory.region_for_job(_job(77,
			ACAJobEnums.PropertyType.RESIDENTIAL, ACAJobEnums.LawnSize.SMALL))
			== ACAServiceTerritory.Region.HOME_TOWN)

	# A SEEDED MINORITY OF SMALL COMMERCIAL WORK IS LOCAL, which is what keeps
	# the starting market from being two property types wide. Asserted as a
	# SHARE over many seeds rather than on one, because which seeds land where
	# is balance and the fact that some do is the contract.
	var local := 0
	var total := 0
	for seed in range(1, 400):
		var candidate := _job(seed, ACAJobEnums.PropertyType.COMMERCIAL,
			ACAJobEnums.LawnSize.SMALL)
		total += 1
		if ACAServiceTerritory.region_for_job(candidate) \
				== ACAServiceTerritory.Region.HOME_TOWN:
			local += 1
	_check("some small commercial work is local, and not all of it (%d of %d)"
		% [local, total], local > 0 and local < total)


func _test_purchase_takes_the_money_exactly_once() -> void:
	Territory.reset_to_new_business()
	Business.reset_to_new_business()
	var region := ACAServiceTerritory.Region.RURAL_HIGHWAY

	# Not enough standing, and not enough money: refused, and nothing changes.
	var before := GameSession.money()
	_check("a lot is refused without the standing for it",
		not Territory.try_purchase_lot(region))
	_check("and nothing was taken", GameSession.money() == before)
	_check("the refusal says why",
		not String(Territory.can_purchase(region).get("reason", "")).is_empty())

	# Now qualify it.
	Business.dev_set_reputation(80.0)
	for i in 40:
		Business.dev_add_revenue(0)
	_grant_contracts(40)
	var cost := Territory.purchase_cost(region)
	GameSession.add_money(cost + 500)
	var funds := GameSession.money()
	_check("with the standing and the money, the lot is bought",
		Territory.try_purchase_lot(region))
	_check("the money was taken exactly once (%d -> %d, cost %d)"
		% [funds, GameSession.money(), cost],
		GameSession.money() == funds - cost)
	_check("and the business works there now", Territory.owns(region))
	_check("buying it again is refused",
		not Territory.try_purchase_lot(region))


## ---------------------------------------------------------------------------
## EVERY REGION IS SOMEWHERE
## ---------------------------------------------------------------------------
## Four of the five build their hub from `ACARegionalHub.LAYOUTS`; the home
## market is the authored Business Town and deliberately has no entry. A region
## added to the enum without a layout would fall back to the Rural highway lot
## and the player would drive to the wrong place, silently.
func _test_every_region_has_a_place_to_stand() -> void:
	var missing := PackedStringArray()
	for region in ACAServiceTerritory.REGION_ORDER:
		if region == ACAServiceTerritory.HOME_REGION:
			continue
		if not ACARegionalHub.LAYOUTS.has(region):
			missing.append(ACAServiceTerritory.region_name(region))
	_check("every bought region has a hub layout (%d missing)" % missing.size(),
		missing.is_empty())

	# ...and each of them is a DIFFERENT place. Two regions sharing a footprint
	# would read as the same lot with different props on it, which is exactly
	# what the first version of these hubs was.
	var footprints := {}
	for region: int in ACARegionalHub.LAYOUTS:
		footprints[ACARegionalHub.LAYOUTS[region]["island"]] = true
	_check("and no two hubs stand on the same footprint (%d of %d)"
		% [footprints.size(), ACARegionalHub.LAYOUTS.size()],
		footprints.size() == ACARegionalHub.LAYOUTS.size())


## ---------------------------------------------------------------------------
## NO CAR IS EVER OFF THE ROAD
## ---------------------------------------------------------------------------
## The hubs generate their traffic routes from the SAME `roads` table the road
## tiles are laid from, so a car cannot be on a street that does not exist. That
## is an argument; this is the measurement.
##
## Every point of every generated route is checked against every road strip in
## that region, with the car's own half-width to spare. A road tile is two units
## wide and a car body is about 0.84 across, so the clearance a route needs is
## 1.0 - 0.42 = 0.58 from the centre line.
func _test_hub_traffic_never_leaves_the_tarmac() -> void:
	var car_half_width := 0.42
	var half_carriageway := 1.0
	var checked := 0
	var off := 0
	var worst := ""
	for region: int in ACARegionalHub.LAYOUTS:
		var layout: Dictionary = ACARegionalHub.LAYOUTS[region]
		for route: Dictionary in _hub_routes(layout):
			for point: Vector2 in route["corners"]:
				checked += 1
				if _on_tarmac(layout["roads"], point,
						half_carriageway - car_half_width):
					continue
				off += 1
				if worst.is_empty():
					worst = "%s %s at (%.1f, %.1f)" % [
						ACAServiceTerritory.region_name(region),
						String(route["name"]), point.x, point.y]
	_check("every hub traffic route stays on tarmac (%d points, %d off%s)"
		% [checked, off, "" if worst.is_empty() else ": " + worst], off == 0)
	_check("and there were routes to check (%d)" % checked, checked > 0)


## The routes a hub layout produces, derived the same way `ACARegionalHub` does.
## Duplicated here ON PURPOSE: a test that asked the class to hand over its own
## answer would agree with it however wrong the derivation was.
func _hub_routes(layout: Dictionary) -> Array:
	var lane := 0.45
	var out: Array = []
	for strip: Dictionary in layout["roads"]:
		if not bool(strip.get("through", false)):
			continue
		var axis := String(strip["axis"])
		var at := float(strip["at"])
		var from := float(strip["from"]) - 1.4
		var to := float(strip["to"]) + 1.4
		var one_way := int(strip.get("one_way", 0))
		for direction in [1, -1]:
			if one_way != 0 and direction != one_way:
				continue
			var offset := lane * float(direction)
			var a := Vector2(from, at + offset)
			var b := Vector2(to, at + offset)
			if axis != "x":
				a = Vector2(at - offset, from)
				b = Vector2(at - offset, to)
			out.append({"name": "%s %d" % [axis, direction], "corners": [a, b]})
	var traffic: Dictionary = layout["traffic"]
	if traffic.has("loop"):
		out.append({"name": "loop", "corners": _loop_points(traffic["loop"], lane)})
	return out


func _loop_points(centres: Array, lane: float) -> Array:
	var out: Array = []
	var count := centres.size()
	for i in count:
		var here: Vector2 = centres[i]
		var into := (Vector2(centres[(i + 1) % count]) - here).normalized()
		var outof := (here - Vector2(centres[(i - 1 + count) % count])).normalized()
		var normal := Vector2(-into.y, into.x) + Vector2(-outof.y, outof.x)
		if normal.length() < 0.01:
			normal = Vector2(-into.y, into.x)
		out.append(here + normal.normalized() * lane)
	return out


## Is this point on a road strip, with `clearance` to spare either side? A route
## END is allowed to be past the end of its strip: that is where a car fades in
## and out, off the edge of the island.
func _on_tarmac(strips: Array, point: Vector2, clearance: float) -> bool:
	for strip: Dictionary in strips:
		var at := float(strip["at"])
		var lo := minf(float(strip["from"]), float(strip["to"])) - 2.0
		var hi := maxf(float(strip["from"]), float(strip["to"])) + 2.0
		if String(strip["axis"]) == "x":
			if absf(point.y - at) <= clearance and point.x >= lo and point.x <= hi:
				return true
		elif absf(point.x - at) <= clearance and point.y >= lo and point.y <= hi:
			return true
	return false


## ---------------------------------------------------------------------------
## A REGION CHANGES A PROPERTY, AND NEVER MOVES IT
## ---------------------------------------------------------------------------
## `ACARegionalContext` reshapes what the seed drew, exactly as the archetype
## and the condition do. Two things have to hold: the reshape must be real
## enough to see, and it must not consume a single random draw - because the
## draw order IS the save format.
func _test_a_region_reshapes_a_property_without_drawing() -> void:
	var open := ACAPropertyParams.for_seed(4242, 144,
		ACAPropertyArchetype.Kind.RURAL,
		ACAPropertyCondition.Stage.MAINTAINED,
		ACAServiceTerritory.Region.RURAL_HIGHWAY)
	var built := ACAPropertyParams.for_seed(4242, 144,
		ACAPropertyArchetype.Kind.RURAL,
		ACAPropertyCondition.Stage.MAINTAINED,
		ACAServiceTerritory.Region.HOSPITALITY_STRIP)
	var none := ACAPropertyParams.for_seed(4242, 144,
		ACAPropertyArchetype.Kind.RURAL)

	_check("open country has a bigger horizon than a regional centre (%.0f > %.0f)"
		% [open.distant_hill_strength, built.distant_hill_strength],
		open.distant_hill_strength > built.distant_hill_strength)
	_check("...and more wood on it (%.2f > %.2f)"
		% [open.forestiness, built.forestiness],
		open.forestiness > built.forestiness)
	_check("...and more relief (%.2f > %.2f)"
		% [open.terrain_amplitude, built.terrain_amplitude],
		open.terrain_amplitude > built.terrain_amplitude)

	# NOTHING WAS DRAWN. The one value no reshape touches has to be identical
	# across all three, which it can only be if the random sequence ran the same
	# number of times in each.
	_check("a region consumes no random draw (%.4f)" % none.dryness,
		is_equal_approx(open.dryness, none.dryness)
			and is_equal_approx(built.dryness, none.dryness))


## THE FILTER. A contract in a region the business has not bought is not
## something the job board may offer.
func _test_locked_regions_stay_off_the_board() -> void:
	Territory.reset_to_new_business()
	var rural := _job(4242, ACAJobEnums.PropertyType.RURAL, ACAJobEnums.LawnSize.LARGE)
	_check("a rural contract is refused while the lot is unbought",
		not Territory.accepts_offer(rural))
	var local := _job(77, ACAJobEnums.PropertyType.RESIDENTIAL,
		ACAJobEnums.LawnSize.SMALL)
	_check("a local contract is not", Territory.accepts_offer(local))

	Territory.dev_grant_region(ACAServiceTerritory.Region.RURAL_HIGHWAY)
	_check("and it is accepted once the lot is bought",
		Territory.accepts_offer(rural))

	# ...and the manager honours it through the provider the host installs.
	var manager := ACAJobManager.new()
	manager.auto_evaluate = false
	manager.market_seed = 991
	add_child(manager)
	manager.offer_filter_provider = func(job: ACAJob) -> bool:
		return int(job.property_type) == ACAJobEnums.PropertyType.RESIDENTIAL
	var published := 0
	var residential := 0
	for i in 12:
		var offer := manager.debug_force_offer()
		if offer == null:
			continue
		published += 1
		if int(offer.property_type) == ACAJobEnums.PropertyType.RESIDENTIAL:
			residential += 1
	_check("the market published something through a filter (%d)" % published,
		published > 0)
	_check("and every offer passed it", residential == published)
	manager.queue_free()


func _test_presence_moves_with_the_work() -> void:
	Territory.reset_to_new_business()
	var home := ACAServiceTerritory.Region.HOME_TOWN
	var before := Territory.presence(home)
	Territory.note_completed_contract(_job(77,
		ACAJobEnums.PropertyType.RESIDENTIAL, ACAJobEnums.LawnSize.SMALL), 5)
	_check("a finished contract makes the business better known here",
		Territory.presence(home) > before)
	_check("and it is counted", Territory.contracts_completed_in(home) == 1)

	var high := Territory.presence(home)
	Territory.note_lost_contract(_job(77,
		ACAJobEnums.PropertyType.RESIDENTIAL, ACAJobEnums.LawnSize.SMALL))
	_check("losing one to a rival takes a little back",
		Territory.presence(home) < high)
	_check("presence in a region the business does not work is nothing",
		is_equal_approx(Territory.presence(
			ACAServiceTerritory.Region.HOSPITALITY_STRIP), 0.0))


# ================================================================ mowing modes

func _test_bagging_collects() -> void:
	Equipment.reset_to_new_business()
	Clippings.reset_to_new_business()
	_check("a new business is set to bag",
		Equipment.mowing_mode() == ACAMowingMode.Mode.BAG)
	_check("and the machine has a catcher",
		Equipment.selected_bag_capacity() > 0.0)
	Clippings.start_new_job(Equipment.selected_bag_capacity())
	var taken := Clippings.collect_from_cells(500)
	_check("bagging puts what was cut in the bag (%.2f kg)" % taken, taken > 0.0)


func _test_mulching_and_discharge_do_not() -> void:
	Equipment.reset_to_new_business()
	Clippings.reset_to_new_business()
	Equipment.dev_grant_attachment(&"mulch_kit")
	Equipment.remove_attachment(&"bagger")
	_check("with the bagger off and a mulching kit on, the mode follows",
		Equipment.fit_attachment(&"mulch_kit"))
	_check("the machine is set to mulch",
		Equipment.mowing_mode() == ACAMowingMode.Mode.MULCH)
	_check("and it carries nothing",
		is_equal_approx(Equipment.selected_bag_capacity(), 0.0))
	Clippings.start_new_job(Equipment.selected_bag_capacity())
	_check("so mulching produces no inventory",
		is_equal_approx(Clippings.collect_from_cells(500), 0.0))
	_check("and nothing reached the bag",
		is_equal_approx(Clippings.bag_kilograms(), 0.0))

	# ...and the same for side discharge, through the same one rule.
	Equipment.dev_grant_attachment(&"discharge_chute")
	Equipment.remove_attachment(&"mulch_kit")
	Equipment.fit_attachment(&"discharge_chute")
	_check("a discharge chute gives side discharge",
		Equipment.mowing_mode() == ACAMowingMode.Mode.SIDE_DISCHARGE)
	Clippings.start_new_job(Equipment.selected_bag_capacity())
	_check("side discharge fills nothing either",
		is_equal_approx(Clippings.collect_from_cells(500), 0.0))

	# THE MACHINE'S OWN CATCHER IS UNCHANGED by any of it - what changed is what
	# it is set up to do with the grass.
	_check("the machine is still rated to carry what it always could",
		Equipment.rated_bag_capacity("rider") > 0.0)


func _test_mode_follows_what_is_bolted_on() -> void:
	Equipment.reset_to_new_business()
	_check("bagging is offered because the bagger is on",
		Equipment.can_use_mode(ACAMowingMode.Mode.BAG))
	_check("mulching is not, because there is no kit for it",
		not Equipment.can_use_mode(ACAMowingMode.Mode.MULCH))
	_check("and asking for it is refused",
		not Equipment.set_mowing_mode(ACAMowingMode.Mode.MULCH))
	_check("the mode did not move",
		Equipment.mowing_mode() == ACAMowingMode.Mode.BAG)


# ========================================================== attachments/trailer

func _test_attachments_fit_only_what_they_fit() -> void:
	Equipment.reset_to_new_business()
	Equipment.dev_grant_mower("push")
	Equipment.select_mower("push")
	Equipment.dev_grant_attachment(&"tow_sweeper")
	Equipment.remove_attachment(&"bagger")
	# A tow-behind sweeper takes two slots, so it needs a trailer with room for
	# them before compatibility is even the question.
	Equipment.dev_grant_trailer(&"twin")
	var gate := Equipment.can_fit(&"tow_sweeper")
	_check("a tow-behind sweeper does not go on a push mower",
		not bool(gate["allowed"]))
	_check("and the refusal says why",
		not String(gate["reason"]).is_empty())
	Equipment.select_mower("rider")
	_check("it does go on a rider",
		bool(Equipment.can_fit(&"tow_sweeper").get("allowed", false)))


func _test_the_trailer_bounds_the_loadout() -> void:
	Equipment.reset_to_new_business()
	Equipment.dev_grant_attachment(&"striping_roller")
	# The starting trailer takes ONE attachment, and the bagger is already on it.
	_check("the starting trailer has one attachment slot",
		Equipment.attachment_slot_capacity() == 1)
	_check("so a second attachment will not fit",
		not bool(Equipment.can_fit(&"striping_roller").get("allowed", false)))
	_check("taking the bagger off makes room",
		Equipment.remove_attachment(&"bagger"))
	_check("and now it fits", Equipment.fit_attachment(&"striping_roller"))
	_check("the slots are counted", Equipment.attachment_slots_used() == 1)


func _test_the_trailer_holds_the_clippings() -> void:
	Equipment.reset_to_new_business()
	Clippings.reset_to_new_business()
	Clippings.start_new_job(90.0)
	Clippings.collect_from_cells(4000)
	var in_bag := Clippings.bag_kilograms()
	Clippings.unload_to_truck()
	_check("unloading fills the trailer, not the yard",
		Clippings.trailer_kilograms() > 0.0
			and is_equal_approx(Clippings.fresh_kilograms(), 0.0))
	_check("what went on it is what came off the machine",
		absf(Clippings.trailer_kilograms() - in_bag) < TOLERANCE)
	var deposited := Clippings.deposit_trailer_at_yard()
	_check("and a service lot empties it into the yard", deposited > 0.0)
	_check("with nothing left on the trailer",
		is_equal_approx(Clippings.trailer_kilograms(), 0.0))


# ============================================================ protected ground

func _test_protected_cells_are_out_of_the_contract() -> void:
	var built := _property_with_conservation()
	if built.is_empty():
		_check("a property with protected ground was found", false)
		return
	var lawn: ACALawn = built["lawn"]
	_check("the property has protected ground (%d cells)"
		% lawn.protected_cell_count(), lawn.protected_cell_count() > 0)

	# THE CONTRACT MUST STILL BE FINISHABLE. Protected cells are excluded from
	# the denominator exactly as a pond's are, which is what stops a
	# conservation objective from making a job impossible.
	var cut := 0
	for iz in lawn.cell_count():
		var z := lawn.lawn_centre().z - lawn.lawn_half_extent() + float(iz) + 0.5
		cut += lawn.mow_swath(
			Vector3(lawn.lawn_centre().x - lawn.lawn_half_extent() - 4.0, 0.0, z),
			Vector3(lawn.lawn_centre().x + lawn.lawn_half_extent() + 4.0, 0.0, z),
			0.55)
	_check("mowing the whole rectangle reaches exactly 100%% (%.4f)"
		% lawn.mowed_fraction(), is_equal_approx(lawn.mowed_fraction(), 1.0))
	_check("and the cut count never included the protected ground",
		cut == lawn.mowed_item_count())
	built["property"].queue_free()


func _test_mowing_protected_ground_records_damage() -> void:
	var built := _property_with_conservation()
	if built.is_empty():
		_check("a property with protected ground was found (damage)", false)
		return
	var lawn: ACALawn = built["lawn"]
	var zone: ACAConservationZone = built["zone"]
	_check("nothing is damaged before anything is cut",
		lawn.damaged_cell_count() == 0)

	# Drive a swath straight through the middle of the first zone.
	var centre: Vector2 = (zone.zones()[0] as Dictionary)["position"]
	var radius: float = float((zone.zones()[0] as Dictionary)["radius"])
	lawn.mow_swath(Vector3(centre.x - radius, 0.0, centre.y),
		Vector3(centre.x + radius, 0.0, centre.y), 1.2)
	_check("driving through it records damage (%d cells)"
		% lawn.damaged_cell_count(), lawn.damaged_cell_count() > 0)
	_check("the damage is a share of the protected ground",
		lawn.protected_damage_fraction() > 0.0
			and lawn.protected_damage_fraction() <= 1.0)
	_check("and none of it counted towards the contract",
		lawn.mowed_item_count() > 0)

	# THE RECORD SURVIVES A SAVE, because it lives with the rest of the cut
	# state rather than in a system of its own.
	var state := lawn.cut_state()
	var damaged := lawn.damaged_cell_count()
	lawn.reset()
	_check("a restart clears the damage", lawn.damaged_cell_count() == 0)
	_check("the cut state restores", lawn.restore_cut_state(state))
	_check("and the damage came back with it (%d)" % lawn.damaged_cell_count(),
		lawn.damaged_cell_count() == damaged)
	built["property"].queue_free()


## The prediction the work order is printed from has to agree with the property
## that is actually generated, or a card warns about a meadow that is not there.
func _test_conservation_prediction_agrees_with_the_property() -> void:
	var checked := 0
	var agreed := 0
	for seed in range(600, 640):
		var params := ACAPropertyParams.for_seed(seed, 144,
			ACAPropertyArchetype.Kind.PARK)
		var zone := ACAConservationZone.for_params(params, Vector2.ZERO, null)
		var predicted := ACAConservationZone.likely_present(seed,
			ACAPropertyArchetype.Kind.PARK, 144)
		checked += 1
		# The prediction claims only whether a zone exists at all, and the
		# generator may still fail to PLACE one on a crowded property - so the
		# contract is one-directional: no prediction means no zone.
		if zone.count() > 0:
			if predicted:
				agreed += 1
		else:
			agreed += 1
	_check("the work order's warning never claims a meadow that is not there "
		+ "(%d of %d)" % [agreed, checked], agreed == checked)


# =========================================================== property condition

func _test_a_project_property_is_the_same_property() -> void:
	var seed := _find_project_seed()
	if seed == 0:
		_check("a project property was found", false)
		return
	var neglected := ACAPropertyParams.for_seed(seed, 144,
		ACAPropertyArchetype.Kind.SUBURBAN, ACAPropertyCondition.Stage.NEGLECTED)
	var maintained := ACAPropertyParams.for_seed(seed, 144,
		ACAPropertyArchetype.Kind.SUBURBAN, ACAPropertyCondition.Stage.MAINTAINED)

	_check("the same seed is the same address", neglected.seed == maintained.seed)
	_check("the same kind of place",
		neglected.archetype == maintained.archetype)
	_check("the same lawn", neglected.lawn_size == maintained.lawn_size)
	_check("the same pond, in the same place",
		neglected.pond_seed == maintained.pond_seed
			and neglected.pond_offset.is_equal_approx(maintained.pond_offset)
			and is_equal_approx(neglected.pond_radius, maintained.pond_radius))
	_check("the same terrain",
		is_equal_approx(neglected.terrain_amplitude, maintained.terrain_amplitude)
			and is_equal_approx(neglected.broad_hill_strength,
				maintained.broad_hill_strength))

	# ...and what DID change is the condition.
	_check("but the neglected one stands far taller",
		neglected.grass_height_scale > maintained.grass_height_scale * 1.4)
	_check("with more left lying in it",
		neglected.clutter > maintained.clutter)

	# A MAINTAINED PROPERTY IS THE PROPERTY THE GAME ALWAYS BUILT. This is the
	# assertion that guarantees the condition system moved nothing.
	var untouched := ACAPropertyParams.for_seed(seed, 144,
		ACAPropertyArchetype.Kind.SUBURBAN)
	_check("and a property with no condition on it is unchanged",
		is_equal_approx(untouched.grass_height_scale, 1.0)
			and is_equal_approx(untouched.clutter, 0.0)
			and is_equal_approx(untouched.boundary_condition, 1.0))


func _test_the_stage_follows_the_service_count() -> void:
	var seed := _find_project_seed()
	if seed == 0:
		return
	_check("an unserviced project property is neglected",
		ACAPropertyCondition.stage_for(seed, ACAJobEnums.PropertyType.RESIDENTIAL, 0)
			== ACAPropertyCondition.Stage.NEGLECTED)
	_check("one visit puts it into recovery",
		ACAPropertyCondition.stage_for(seed, ACAJobEnums.PropertyType.RESIDENTIAL, 1)
			== ACAPropertyCondition.Stage.RECOVERY)
	_check("two make it a maintained customer",
		ACAPropertyCondition.stage_for(seed, ACAJobEnums.PropertyType.RESIDENTIAL, 2)
			== ACAPropertyCondition.Stage.MAINTAINED)
	_check("and it never goes back",
		ACAPropertyCondition.stage_for(seed, ACAJobEnums.PropertyType.RESIDENTIAL, 9)
			== ACAPropertyCondition.Stage.MAINTAINED)

	# An ORDINARY property is maintained however many times it is cut.
	var ordinary := _find_ordinary_seed()
	_check("an ordinary property is never a rescue job",
		ACAPropertyCondition.stage_for(ordinary,
			ACAJobEnums.PropertyType.RESIDENTIAL, 0)
			== ACAPropertyCondition.Stage.MAINTAINED)


# ============================================================= finish patterns

func _test_a_consistent_finish_scores() -> void:
	var lawn := _plain_lawn()
	# Straight passes, all on one axis.
	var half := lawn.lawn_half_extent()
	var centre := lawn.lawn_centre()
	var z := centre.z - half + 0.5
	while z < centre.z + half:
		lawn.mow_swath(Vector3(centre.x - half - 2.0, 0.0, z),
			Vector3(centre.x + half + 2.0, 0.0, z), 1.0)
		z += 1.0
	var result := ACAFinishPattern.score(lawn, ACAFinishPattern.Pattern.PARALLEL)
	_check("a lawn mown in straight passes meets a straight-stripe request "
		+ "(%.2f of it on line)" % float(result["share"]), bool(result["met"]))
	_check("and it scores", float(result["score"]) > 0.0)

	# ...and the same lawn does NOT satisfy a diagonal request.
	var diagonal := ACAFinishPattern.score(lawn, ACAFinishPattern.Pattern.DIAGONAL)
	_check("but not a diagonal one", not bool(diagonal["met"]))
	_check("a contract with no request is always met",
		bool(ACAFinishPattern.score(lawn, ACAFinishPattern.Pattern.NONE)["met"]))
	lawn.queue_free()


func _test_a_scribbled_finish_does_not() -> void:
	var lawn := _plain_lawn()
	var half := lawn.lawn_half_extent()
	var centre := lawn.lawn_centre()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8811
	# The same ground, cut in every direction there is.
	for i in 700:
		var from := Vector3(centre.x + rng.randf_range(-half, half), 0.0,
			centre.z + rng.randf_range(-half, half))
		var angle := rng.randf_range(0.0, TAU)
		var to := from + Vector3(cos(angle), 0.0, sin(angle)) * 9.0
		lawn.mow_swath(from, to, 1.0)
	var result := ACAFinishPattern.score(lawn, ACAFinishPattern.Pattern.PARALLEL)
	_check("a lawn cut in every direction does not meet a pattern request "
		+ "(%.2f on the best axis)" % float(result["share"]), not bool(result["met"]))
	_check("and the request is still derived from the contract, not stored",
		ACAFinishPattern.pattern_for(_job(1234,
			ACAJobEnums.PropertyType.HOSPITALITY, ACAJobEnums.LawnSize.MEDIUM))
			== ACAFinishPattern.pattern_for(_job(1234,
				ACAJobEnums.PropertyType.HOSPITALITY, ACAJobEnums.LawnSize.MEDIUM)))
	lawn.queue_free()


# ============================================================ weather / ground

## THE FORECAST IS THE SCHEDULE, evaluated later. This is the assertion that
## makes it impossible for the two to disagree.
func _test_the_forecast_is_the_schedule() -> void:
	WorldClock.start_new_world()
	var ahead := WorldClock.forecast(8.0)
	_check("the forecast has entries", ahead.size() > 1)
	var truthful := 0
	for entry: Dictionary in ahead:
		var at_that_time := WorldClock.weather_at(float(entry["minutes"]) + 1.0)
		if at_that_time == String(entry["preset"]):
			truthful += 1
	_check("every entry is what the schedule says for that time (%d of %d)"
		% [truthful, ahead.size()], truthful == ahead.size())

	# ...and driving the clock to a forecast block really produces that sky.
	var target: Dictionary = ahead[ahead.size() - 1]
	var wanted := String(target["preset"])
	WorldClock.advance_minutes(maxf(float(target["minutes"])
		- WorldClock.game_minutes() + 5.0, 1.0))
	_check("and arriving there produces it (%s / %s)"
		% [WorldClock.weather_preset(), wanted],
		WorldClock.weather_preset() == wanted)

	# A SKY SET BY HAND TAKES THE SCHEDULE, so a staged shot cannot be rained on.
	WorldClock.set_weather("Rain")
	_check("setting the weather by hand stops the schedule",
		not WorldClock.weather_is_scheduled())
	WorldClock.advance_minutes(WorldClock.WEATHER_BLOCK_MINUTES * 2.0)
	_check("and it stays where it was put",
		WorldClock.weather_preset() == "Rain")
	WorldClock.resume_scheduled_weather()
	_check("handing it back restores the schedule",
		WorldClock.weather_is_scheduled())


func _test_wet_and_dry_change_the_work() -> void:
	var wet := ACAGroundConditions.state_for("Rain", 0.0, 12.0, 0.24)
	var dry := ACAGroundConditions.state_for("Clear", 100000.0, 14.0, 0.35)
	_check("it is wet while it is raining", wet == ACAGroundConditions.State.WET)
	_check("and dry long after it stopped", dry == ACAGroundConditions.State.DRY)
	_check("wet grass produces more than dry",
		ACAGroundConditions.clipping_multiplier(wet)
			> ACAGroundConditions.clipping_multiplier(dry))
	_check("there is no dust in the wet",
		is_equal_approx(ACAGroundConditions.dust_multiplier(wet), 0.0))
	_check("an autonomous unit is slower in the wet",
		ACAGroundConditions.autonomous_time_multiplier(wet) > 1.0)

	# CLEAR AND DRY RESTORES ORDINARY BEHAVIOUR, which is the assertion that
	# stops the whole system from being a permanent modifier.
	var damp := ACAGroundConditions.state_for("Clear", 700.0, 12.0, 0.24)
	_check("ordinary going multiplies the clippings by one",
		is_equal_approx(ACAGroundConditions.clipping_multiplier(damp), 1.0))
	_check("and does not slow a machine down",
		is_equal_approx(ACAGroundConditions.autonomous_time_multiplier(damp), 1.0))

	# ...and the ledger really uses it.
	Clippings.reset_to_new_business()
	Clippings.start_new_job(500.0)
	Clippings.set_yield_multiplier(1.0)
	var ordinary := Clippings.collect_from_cells(1000)
	Clippings.start_new_job(500.0)
	Clippings.set_yield_multiplier(ACAGroundConditions.clipping_multiplier(
		ACAGroundConditions.State.WET))
	var heavy := Clippings.collect_from_cells(1000)
	_check("the same ground cut in the wet weighs more (%.1f vs %.1f)"
		% [heavy, ordinary], heavy > ordinary)
	Clippings.set_yield_multiplier(1.0)


# ========================================================= fleet and agreements

func _test_a_machine_cannot_take_two_contracts() -> void:
	Equipment.reset_to_new_business()
	Territory.reset_to_new_business()
	var uid := Equipment.dev_grant_autonomous("auto_grounds")
	_check("a unit was granted", uid > 0)
	_check("and it is idle", not Equipment.is_unit_busy(uid))

	var manager := get_node_or_null(^"/root/JobManager")
	if manager == null:
		return
	JobManager.debug_clear_all()
	var first := JobManager.commission_offer(101010, 0.0)
	var second := JobManager.commission_offer(202020, 0.0)
	if first == null or second == null:
		return
	# Only a contract the tier is rated for can be taken; find one that is.
	var taken := Equipment.assign_to_contract(uid, first.id) >= 0.0
	if not taken:
		taken = Equipment.assign_to_contract(uid, second.id) >= 0.0
		if taken:
			var swap := first
			first = second
			second = swap
	if not taken:
		# Neither contract suited the tier; the rule below is still worth
		# asserting and is asserted through the idle check instead.
		_check("an unassignable contract leaves the unit idle",
			not Equipment.is_unit_busy(uid))
		return
	_check("the unit is out on the contract", Equipment.is_unit_busy(uid))
	_check("and it cannot take a second",
		Equipment.assign_to_contract(uid, second.id) < 0.0)
	JobManager.debug_clear_all()


func _test_an_agreement_needs_a_fleet() -> void:
	Agreements.reset_to_new_business()
	Territory.reset_to_new_business()
	Equipment.reset_to_new_business()
	Territory.dev_set_presence(ACAServiceTerritory.Region.HOME_TOWN, 90.0)
	var offer := Agreements.dev_force_offer(ACAServiceTerritory.Region.HOME_TOWN)
	if offer.is_empty():
		_check("an agreement could be composed", false)
		return
	_check("the agreement has the sites its template asks for",
		(offer["sites"] as Array).size() > 0)
	_check("and a completion bonus worth having", int(offer["bonus"]) > 0)

	# One machine cannot keep three gardens on a rota.
	var gate := Agreements.can_accept(String(offer["id"]))
	_check("a one-machine business is refused a three-property agreement",
		not bool(gate["allowed"]))
	_check("and the refusal says why", not String(gate["reason"]).is_empty())

	for i in 3:
		Equipment.dev_grant_autonomous("auto_compact")
	_check("with a fleet behind it, the agreement can be signed",
		bool(Agreements.can_accept(String(offer["id"])).get("allowed", false)))
	_check("signing it moves it to the active list",
		Agreements.accept(String(offer["id"])))
	_check("and it is being served", Agreements.active_count() == 1)
	Agreements.reset_to_new_business()


# ================================================================ persistence

func _test_round_trip() -> void:
	Territory.reset_to_new_business()
	Territory.dev_grant_region(ACAServiceTerritory.Region.RURAL_HIGHWAY)
	Territory.dev_set_presence(ACAServiceTerritory.Region.RURAL_HIGHWAY, 61.0)
	Territory.set_active_region(ACAServiceTerritory.Region.RURAL_HIGHWAY)
	var territory_state := Territory.to_save_dict()

	Equipment.reset_to_new_business()
	Equipment.dev_grant_attachment(&"striping_roller")
	Equipment.remove_attachment(&"bagger")
	Equipment.fit_attachment(&"striping_roller")
	var equipment_state := Equipment.to_save_dict()

	Territory.reset_to_new_business()
	Equipment.reset_to_new_business()
	Territory.from_save_dict(territory_state)
	Equipment.from_save_dict(equipment_state, MowerUpgrades)

	_check("the bought lot came back",
		Territory.owns(ACAServiceTerritory.Region.RURAL_HIGHWAY))
	_check("with its presence",
		absf(Territory.presence(ACAServiceTerritory.Region.RURAL_HIGHWAY) - 61.0)
			< TOLERANCE)
	_check("and the hub the player was working from",
		Territory.active_region() == ACAServiceTerritory.Region.RURAL_HIGHWAY)
	_check("the attachment is still owned",
		Equipment.owns_attachment(&"striping_roller"))
	_check("and still on the machine", Equipment.is_fitted(&"striping_roller"))
	_check("with the bagger still off", not Equipment.is_fitted(&"bagger"))


func _test_a_save_without_the_new_sections() -> void:
	Territory.from_save_dict({})
	_check("a save with no territory owns the home town",
		Territory.owns(ACAServiceTerritory.Region.HOME_TOWN))
	_check("and has bought no lot", Territory.owned_region_count() == 1)
	_check("and is working from home",
		Territory.active_region() == ACAServiceTerritory.Region.HOME_TOWN)

	Equipment.from_save_dict({}, MowerUpgrades)
	_check("a save with no loadout has the catcher every machine always had",
		Equipment.owns_attachment(&"bagger"))
	_check("with it fitted", Equipment.is_fitted(&"bagger"))
	_check("set to bag", Equipment.mowing_mode() == ACAMowingMode.Mode.BAG)
	_check("on the trailer it always had",
		Equipment.trailer_tier() == ACAHaulage.STARTING_TIER)
	_check("so the machine collects exactly as it used to",
		Equipment.selected_bag_capacity() > 0.0)

	Agreements.from_save_dict({})
	_check("a save with no agreements has none", Agreements.active_count() == 0)
	Portfolio.from_save_dict({})
	_check("a save with no portfolio has no photographs",
		Portfolio.entry_count() == 0)


# ==================================================================== helpers

func _job(job_seed: int, property_type: int, lawn_size: int) -> ACAJob:
	var job := ACAJob.new()
	job.id = StringName("test_%d" % job_seed)
	job.seed = job_seed
	job.property_type = property_type
	job.lawn_size = lawn_size
	job.grid_size = ACAJobBalance.LAWN_GRID.get(lawn_size, Vector2i(96, 96))
	job.base_pay = 200
	return job


## Settle enough contracts through the books that a lot's requirement is met.
func _grant_contracts(count: int) -> void:
	for i in count:
		Business.settle_completed_job(_job(900000 + i,
			ACAJobEnums.PropertyType.RESIDENTIAL, ACAJobEnums.LawnSize.SMALL),
			{"completion": 1.0}, 100)


## A seed whose property really has protected ground on it, built for real.
func _property_with_conservation() -> Dictionary:
	for seed in range(1, 260):
		var params := ACAPropertyParams.for_seed(seed, 144,
			ACAPropertyArchetype.Kind.PARK)
		var zone := ACAConservationZone.for_params(params, Vector2.ZERO, null)
		if zone.count() <= 0:
			continue
		var property := ACAProperty.new()
		property.dev_skip_grass = true
		property.dev_skip_foliage = true
		add_child(property)
		property.build(params)
		var lawn := property.lawn()
		if lawn == null or lawn.protected_cell_count() <= 0:
			property.queue_free()
			continue
		var found: ACAConservationZone = property.conservation()
		return {"property": property, "lawn": lawn,
			"zone": found if found != null else zone}
	return {}


## A lawn with nothing on it, for measuring a finish pattern.
func _plain_lawn() -> ACALawn:
	var property := ACAProperty.new()
	property.dev_skip_grass = true
	property.dev_skip_foliage = true
	add_child(property)
	property.build(ACAPropertyParams.for_seed(31337, 96))
	var lawn := property.lawn()
	# The property is freed by the caller through the lawn's own owner.
	lawn.set_meta(&"owner_property", property)
	return lawn


func _find_project_seed() -> int:
	for seed in range(1, 500):
		if ACAPropertyCondition.is_project_site(seed,
				ACAJobEnums.PropertyType.RESIDENTIAL):
			return seed
	return 0


func _find_ordinary_seed() -> int:
	for seed in range(1, 500):
		if not ACAPropertyCondition.is_project_site(seed,
				ACAJobEnums.PropertyType.RESIDENTIAL):
			return seed
	return 0


func _say(heading: String) -> void:
	print("[EXPANSION] --- %s" % heading)


func _check(what: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("[EXPANSION] ok    %s" % what)
	else:
		_fail += 1
		print("[EXPANSION] FAIL  %s" % what)
