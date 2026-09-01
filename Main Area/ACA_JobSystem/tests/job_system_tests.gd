extends Node
## Headless assertion suite for the portable Job System - development only.
##
##     godot --headless --path <project> res://Main Area/ACA_JobSystem/tests/JobSystemTests.tscn
##
## Exits with a non-zero code when anything fails, so it can be wired into CI.
## Nothing in job_system/ depends on this folder.

var _passed := 0
var _failed := 0
var _failures: Array[String] = []
var _log_file: FileAccess


## Mirrors every line to user://job_system_tests.log, flushed as it goes, so a
## hung or crashed run still shows exactly how far it got.
func _say(text: String) -> void:
	print(text)
	if _log_file != null:
		_log_file.store_line(text)
		_log_file.flush()


func _ready() -> void:
	_log_file = FileAccess.open("user://job_system_tests.log", FileAccess.WRITE)
	_say("=== A Cut Above Job System - test suite ===")
	await _run_all()
	_say("")
	_say("PASSED %d   FAILED %d" % [_passed, _failed])
	for f in _failures:
		_say("  FAIL: " + f)
	_say("=== done ===")
	if _log_file != null:
		_log_file.close()
	get_tree().quit(1 if _failed > 0 else 0)


func _run_all() -> void:
	_test_job_is_data_not_node()
	_test_generator_determinism()
	_test_generated_sizes_and_pools()
	_test_pay_rules()
	_test_market_strength_table()
	_test_capacity_matches_strength()
	_test_gradual_arrival()
	_test_offer_expiry()
	_test_accepted_jobs_do_not_expire()
	_test_accept_flow()
	_test_current_job_capacity()
	_test_begin_new_job()
	_test_progress_and_completion()
	_test_falling_demand_keeps_offers()
	_test_rising_demand_does_not_fill()
	_test_drought_stops_new_offers()
	await _test_ui_board()


# ================================================================== harness

## A manager driven manually by the test, with a frozen clock.
func _make_manager(season: int = ACAJobEnums.Season.SPRING,
		economy: int = ACAJobEnums.Economy.NORMAL,
		climate: int = ACAJobEnums.Climate.NORMAL,
		market_seed: int = 12345) -> Array:
	var clock := ACAJobDebugTimeProvider.new(8.0 * 60.0)
	clock.set_paused(true)
	clock.set_season(season)
	var manager := ACAJobManager.new()
	manager.auto_evaluate = false
	manager.market_seed = market_seed
	manager.economy = economy
	manager.climate = climate
	add_child(manager)
	manager.set_time_provider(clock)
	return [manager, clock]


func _drop(manager: ACAJobManager) -> void:
	remove_child(manager)
	manager.queue_free()


func _check(condition: bool, label: String) -> bool:
	if condition:
		_passed += 1
		_say("  ok   " + label)
	else:
		_failed += 1
		_failures.append(label)
		_say("  FAIL " + label)
	return condition


func _check_eq(actual: Variant, expected: Variant, label: String) -> bool:
	return _check(actual == expected, "%s (got %s, expected %s)" % [label, actual, expected])


# ==================================================================== tests

func _test_job_is_data_not_node() -> void:
	_say("- job data is data")
	var job := ACAJob.new()
	var as_object: Object = job
	_check(as_object is Resource, "ACAJob is a Resource")
	_check(not (as_object is Node), "ACAJob is not a Node (cannot own timers or _process)")
	var script_source := FileAccess.get_file_as_string("res://Main Area/ACA_JobSystem/job_system/data/job.gd")
	_check(not script_source.contains("Timer.new()"), "job.gd creates no Timer")
	_check(not script_source.contains("_process("), "job.gd has no _process")
	_check(not script_source.contains("_physics_process("), "job.gd has no _physics_process")
	var manager_source := FileAccess.get_file_as_string(
		"res://Main Area/ACA_JobSystem/job_system/manager/job_manager.gd")
	_check(not manager_source.contains("_physics_process("),
		"job_manager.gd has no _physics_process")


func _test_generator_determinism() -> void:
	_say("- deterministic seeds")
	var a := ACAJobGenerator.generate_core(928471, 1)
	var b := ACAJobGenerator.generate_core(928471, 1)
	_check(a == b, "seed 928471 v1 reproduces the same core")

	var job_1 := ACAJobGenerator.generate(928471, 100.0, 1)
	var job_2 := ACAJobGenerator.generate(928471, 5000.0, 1)
	_check(job_1.job_site == job_2.job_site
		and job_1.property_type == job_2.property_type
		and job_1.lawn_size == job_2.lawn_size
		and job_1.base_pay == job_2.base_pay
		and is_equal_approx(job_1.offer_duration_minutes, job_2.offer_duration_minutes),
		"same seed at different world times gives the same contract")
	_check(not is_equal_approx(job_1.expiry_game_time, job_2.expiry_game_time),
		"absolute expiry still depends on when the offer entered the market")
	_check_eq(job_1.expiry_game_time, 100.0 + job_1.offer_duration_minutes,
		"expiry = created + generated offer duration")
	_check(job_1.id != job_2.id, "ids differ for offers created at different times")

	var different := ACAJobGenerator.generate_core(11111, 1)
	_check(different != a, "a different seed gives a different contract")
	_say("    seed 928471 -> %s / %s / %s / $%d / %.0f min offer" % [
		ACAJobEnums.property_type_name(a["property_type"]), a["job_site"],
		ACAJobEnums.lawn_size_name(a["lawn_size"]), a["base_pay"],
		a["offer_duration_minutes"]])


func _test_generated_sizes_and_pools() -> void:
	_say("- lawn sizes and property pools")
	var sizes_seen := {}
	var ok_pool := true
	var ok_grid := true
	var ok_size := true
	for i in 400:
		var core := ACAJobGenerator.generate_core(i * 7919 + 3, 1)
		var size: int = core["lawn_size"]
		sizes_seen[size] = true
		if not ACAJobBalance.GENERATED_LAWN_SIZES.has(size):
			ok_size = false
		if not ACAJobCatalog.size_pool(core["property_type"]).has(size):
			ok_pool = false
		if core["grid_size"] != ACAJobBalance.LAWN_GRID[size]:
			ok_grid = false
		if not ACAJobCatalog.site_names(core["property_type"]).has(core["job_site"]):
			ok_pool = false
	_check(ok_size, "V1 generation only rolls Small/Medium/Large")
	_check(ok_pool, "sizes and site names always come from the property type's pools")
	_check(ok_grid, "grid size matches the lawn size table")
	_check_eq(sizes_seen.size(), 3, "all three V1 sizes appear")
	_check_eq(ACAJobBalance.LAWN_GRID[ACAJobEnums.LawnSize.SMALL], Vector2i(96, 96), "small = 96x96")
	_check_eq(ACAJobBalance.LAWN_GRID[ACAJobEnums.LawnSize.MEDIUM], Vector2i(144, 144), "medium = 144x144")
	_check_eq(ACAJobBalance.LAWN_GRID[ACAJobEnums.LawnSize.LARGE], Vector2i(192, 192), "large = 192x192")
	_check(ACAJobEnums.lawn_size_name(ACAJobEnums.LawnSize.LARGE) == "Large Lawn",
		"player-facing size wording hides the grid dimension")


func _test_pay_rules() -> void:
	_say("- pay")
	var ok_range := true
	var ok_round := true
	for i in 400:
		var core := ACAJobGenerator.generate_core(i * 104729 + 17, 1)
		var base: int = ACAJobBalance.BASE_PAY[core["lawn_size"]]
		var pay: int = core["base_pay"]
		# Rounding to the nearest $5 can land half a step outside the raw band.
		var slack := float(ACAJobBalance.PAY_ROUNDING) / 2.0
		if pay < base * ACAJobBalance.PAY_VARIATION_MIN - slack \
				or pay > base * ACAJobBalance.PAY_VARIATION_MAX + slack:
			ok_range = false
		if pay % ACAJobBalance.PAY_ROUNDING != 0:
			ok_round = false
	_check(ok_range, "pay stays inside 0.85x - 1.15x of the size base value")
	_check(ok_round, "pay rounds to the nearest $5")
	_check_eq(ACAJobBalance.BASE_PAY[ACAJobEnums.LawnSize.SMALL], 100, "small base pay $100")
	_check_eq(ACAJobBalance.BASE_PAY[ACAJobEnums.LawnSize.MEDIUM], 225, "medium base pay $225")
	_check_eq(ACAJobBalance.BASE_PAY[ACAJobEnums.LawnSize.LARGE], 400, "large base pay $400")


func _test_market_strength_table() -> void:
	_say("- market strength")
	var E := ACAJobEnums
	_check_eq(ACAJobMarket.market_strength(E.Season.SPRING, E.Economy.NORMAL, E.Climate.NORMAL),
		4, "spring/normal/normal = 4")
	_check_eq(ACAJobMarket.market_strength(E.Season.SPRING, E.Economy.BOOMING, E.Climate.WET),
		5, "spring/booming/wet = 5 (clamped)")
	_check_eq(ACAJobMarket.market_strength(E.Season.SUMMER, E.Economy.SLOW, E.Climate.DRY),
		1, "summer/slow/dry = 1")
	_check_eq(ACAJobMarket.market_strength(E.Season.AUTUMN, E.Economy.RECESSION, E.Climate.NORMAL),
		0, "autumn/recession/normal = 0 (clamped)")
	_check_eq(ACAJobMarket.market_strength(E.Season.WINTER, E.Economy.BOOMING, E.Climate.WET),
		2, "winter/booming/wet = 2")
	_check_eq(ACAJobMarket.market_strength(E.Season.SPRING, E.Economy.BOOMING, E.Climate.DROUGHT),
		0, "drought is a hard zero")
	var ok_bounds := true
	for season in [E.Season.SPRING, E.Season.SUMMER, E.Season.AUTUMN, E.Season.WINTER]:
		for economy in [E.Economy.RECESSION, E.Economy.SLOW, E.Economy.NORMAL, E.Economy.BOOMING]:
			for climate in [E.Climate.WET, E.Climate.NORMAL, E.Climate.DRY, E.Climate.DROUGHT]:
				var s := ACAJobMarket.market_strength(season, economy, climate)
				if s < 0 or s > 5:
					ok_bounds = false
	_check(ok_bounds, "every season/economy/climate combination stays within 0-5")


func _test_capacity_matches_strength() -> void:
	_say("- capacity")
	var ok := true
	for strength in range(0, 6):
		if ACAJobMarket.capacity_for(strength) != strength:
			ok = false
	_check(ok, "maximum available jobs == market strength for 0-5")

	var pair := _make_manager(ACAJobEnums.Season.WINTER)
	var manager: ACAJobManager = pair[0]
	_check_eq(manager.market_strength(), 0, "winter/normal/normal gives strength 0")
	_check_eq(manager.max_available_jobs(), 0, "strength 0 gives capacity 0")
	manager.evaluate_now()
	manager.evaluate_now()
	_check_eq(manager.available_jobs().size(), 0, "no offers are generated at capacity 0")
	_drop(manager)


func _test_gradual_arrival() -> void:
	_say("- gradual job arrival")
	var pair := _make_manager(ACAJobEnums.Season.SPRING, ACAJobEnums.Economy.BOOMING,
		ACAJobEnums.Climate.WET)
	var manager: ACAJobManager = pair[0]
	var clock: ACAJobDebugTimeProvider = pair[1]
	_check_eq(manager.max_available_jobs(), 5, "spring/booming/wet gives capacity 5")

	var most_per_step := 0
	var previous := 0
	for step in 40:
		clock.advance_minutes(20.0)
		manager.evaluate_now()
		var count := manager.available_jobs().size()
		most_per_step = maxi(most_per_step, count - previous)
		previous = count
	_check(previous > 0, "offers arrive over game time (%d on the board)" % previous)
	_check(previous <= 5, "the board never exceeds capacity")
	_check(most_per_step <= 1, "at most one offer arrives per evaluation")
	_drop(manager)


func _test_offer_expiry() -> void:
	_say("- offer expiry uses game time")
	# Winter/normal/normal closes the market (strength 0), so no arriving offer
	# can race the assertions: the injected offer is the only one on the board.
	var pair := _make_manager(ACAJobEnums.Season.WINTER)
	var manager: ACAJobManager = pair[0]
	var clock: ACAJobDebugTimeProvider = pair[1]
	var job := manager.debug_add_offer_with_seed(4242)
	var expired: Array[ACAJob] = []
	manager.job_expired.connect(func(j: ACAJob) -> void: expired.append(j))

	clock.advance_minutes(job.offer_duration_minutes - 1.0)
	manager.evaluate_now()
	_check_eq(manager.available_jobs().size(), 1, "offer survives until its expiry time")

	clock.advance_minutes(2.0)
	manager.evaluate_now()
	_check_eq(manager.available_jobs().size(), 0, "offer is removed once game time passes expiry")
	_check_eq(expired.size(), 1, "job_expired fired")
	_check_eq(manager.past_jobs().size(), 0, "expired offers never enter Past Jobs")
	_check_eq(job.status, ACAJobEnums.Status.EXPIRED, "status is EXPIRED")
	_drop(manager)


func _test_accepted_jobs_do_not_expire() -> void:
	_say("- accepted jobs ignore offer expiry")
	var pair := _make_manager()
	var manager: ACAJobManager = pair[0]
	var clock: ACAJobDebugTimeProvider = pair[1]
	var job := manager.debug_add_offer_with_seed(777)
	_check(manager.accept_job(job.id), "accepted")
	clock.advance_minutes(job.offer_duration_minutes + 10000.0)
	manager.evaluate_now()
	_check_eq(manager.current_jobs().size(), 1, "accepted job is still current long after expiry")
	_check(not job.is_offer_expiry_active(), "offer expiry no longer applies once accepted")
	_drop(manager)


func _test_accept_flow() -> void:
	_say("- accept moves Available to Current")
	var pair := _make_manager()
	var manager: ACAJobManager = pair[0]
	var a := manager.debug_add_offer_with_seed(1001)
	var b := manager.debug_add_offer_with_seed(1002)
	var c := manager.debug_add_offer_with_seed(1003)
	_check_eq(manager.available_jobs().size(), 3, "three offers on the board")

	var accepted: Array[ACAJob] = []
	manager.job_accepted.connect(func(j: ACAJob) -> void: accepted.append(j))
	_check(manager.accept_job(a.id), "accept_job returned true")
	_check_eq(manager.available_jobs().size(), 2, "other offers survive acceptance")
	_check_eq(manager.current_jobs().size(), 1, "job moved to Current")
	_check_eq(a.status, ACAJobEnums.Status.ACCEPTED, "status is ACCEPTED")
	_check_eq(accepted.size(), 1, "job_accepted fired once")
	var ids := [manager.available_jobs()[0].id, manager.available_jobs()[1].id]
	_check(ids.has(b.id) and ids.has(c.id), "jobs B and C are untouched")
	_drop(manager)


## TWO SEPARATE LIMITS, and this is the test that they are separate.
##
## The manager's own capacity is the BUSINESS's - how many contracts a company
## may have open at once. It was 1 while the player was the only thing that
## could mow; it is 5 now that a host can put owned machines on contracts.
##
## How many the PLAYER may personally hold is a different question, it is 1, and
## it belongs to the host - so it is asked for through `player_capacity_provider`
## and NOT hard-coded here. This package must keep working for a host that has no
## such limit at all, which is what the first half asserts.
func _test_current_job_capacity() -> void:
	_say("- business capacity, and the host's player limit")
	var pair := _make_manager()
	var manager: ACAJobManager = pair[0]
	_check_eq(manager.max_current_jobs(), 5,
		"max_current_jobs is the BUSINESS capacity")

	# --- with no host gate, the business may hold several ---
	var a := manager.debug_add_offer_with_seed(2001)
	var b := manager.debug_add_offer_with_seed(2002)
	_check(manager.accept_job(a.id), "first accept succeeds")
	_check(manager.accept_job(b.id),
		"a second accept succeeds when no host limits the player")
	_check_eq(manager.current_jobs().size(), 2, "the business holds two")
	_drop(manager)

	# --- with a host gate of one, the second is refused, with a reason ---
	var gated := _make_manager()
	var limited: ACAJobManager = gated[0]
	limited.player_capacity_provider = func() -> Dictionary:
		if limited.current_jobs().size() < 1:
			return {"allowed": true, "reason": ""}
		return {"allowed": false, "reason": "Finish the contract you are on."}
	var c := limited.debug_add_offer_with_seed(2003)
	var d := limited.debug_add_offer_with_seed(2004)
	_check(limited.accept_job(c.id), "first accept succeeds under the gate")
	var reasons: Array[String] = []
	limited.job_accept_failed.connect(func(_id: StringName, reason: String) -> void:
		reasons.append(reason))
	_check(not limited.accept_job(d.id), "second accept is refused by the host gate")
	_check_eq(limited.current_jobs().size(), 1, "still one current job")
	_check_eq(limited.available_jobs().size(), 1, "the refused offer stays available")
	_check(reasons.size() == 1 and not reasons[0].is_empty(),
		"a player-facing reason is supplied: \"%s\"" % (reasons[0] if reasons.size() > 0 else ""))

	# --- and a MACHINE is not the player, so the gate does not apply to it ---
	_check(limited.accept_job(d.id, true),
		"the same offer is accepted when it is taken for a machine")
	_check_eq(limited.current_jobs().size(), 2,
		"the business now holds the driven contract and the machine's")
	_drop(limited)


func _test_begin_new_job() -> void:
	_say("- begin_new_job")
	var pair := _make_manager()
	var manager: ACAJobManager = pair[0]
	_check(manager.has_method("begin_new_job"), "JobManager.begin_new_job() exists")
	var scene_before := get_tree().current_scene
	var job := manager.debug_add_offer_with_seed(3001)
	manager.accept_job(job.id)
	var requested: Array[ACAJob] = []
	manager.begin_job_requested.connect(func(j: ACAJob) -> void: requested.append(j))
	_check(manager.begin_new_job(job.id), "begin_new_job returned true")
	_check_eq(requested.size(), 1, "begin_job_requested emitted once")
	_check_eq(job.status, ACAJobEnums.Status.IN_PROGRESS, "job is IN_PROGRESS")
	_check(get_tree().current_scene == scene_before, "begin_new_job did not change scenes")
	_check(not manager.begin_new_job(&"not_a_real_job"), "unknown job id is rejected")
	_drop(manager)


func _test_progress_and_completion() -> void:
	_say("- progress and completion")
	var pair := _make_manager()
	var manager: ACAJobManager = pair[0]
	var job := manager.debug_add_offer_with_seed(4001)
	manager.accept_job(job.id)
	manager.begin_new_job(job.id)

	_check(manager.update_job_progress(job.id, 0.42), "external progress update accepted")
	_check_eq(job.progress_percent(), 42, "progress is 42%")
	_check(job.is_partially_complete(), "partially complete drives RETURN TO JOB wording")
	manager.update_job_progress(job.id, 5.0)
	_check_eq(job.progress, 1.0, "progress is clamped to 1.0")

	var completed: Array[ACAJob] = []
	manager.job_completed.connect(func(j: ACAJob) -> void: completed.append(j))
	_check(manager.complete_job(job.id), "complete_job returned true")
	_check_eq(manager.current_jobs().size(), 0, "removed from Current")
	_check_eq(manager.past_jobs().size(), 1, "added to Past")
	_check_eq(job.status, ACAJobEnums.Status.COMPLETED, "status is COMPLETED")
	_check_eq(job.progress, 1.0, "progress is 100%")
	_check_eq(completed.size(), 1, "job_completed fired")
	_check(manager.has_current_capacity(), "capacity frees up after completion")
	_drop(manager)


func _test_falling_demand_keeps_offers() -> void:
	_say("- falling demand keeps existing offers")
	var pair := _make_manager(ACAJobEnums.Season.SPRING, ACAJobEnums.Economy.BOOMING,
		ACAJobEnums.Climate.WET)
	var manager: ACAJobManager = pair[0]
	var clock: ACAJobDebugTimeProvider = pair[1]
	for i in 5:
		manager.debug_add_offer_with_seed(5000 + i)
	_check_eq(manager.available_jobs().size(), 5, "five offers on the board at strength 5")

	manager.set_economy(ACAJobEnums.Economy.SLOW)
	clock.set_season(ACAJobEnums.Season.AUTUMN)
	manager.evaluate_now()
	_check_eq(manager.market_strength(), 2, "market strength fell to 2")
	_check_eq(manager.available_jobs().size(), 5, "all five offers are kept")

	clock.advance_minutes(30.0)
	manager.evaluate_now()
	_check_eq(manager.available_jobs().size(), 5, "no new offers while over capacity")
	_drop(manager)


func _test_rising_demand_does_not_fill() -> void:
	_say("- rising demand does not fill the board instantly")
	var pair := _make_manager(ACAJobEnums.Season.AUTUMN, ACAJobEnums.Economy.SLOW,
		ACAJobEnums.Climate.NORMAL)
	var manager: ACAJobManager = pair[0]
	var clock: ACAJobDebugTimeProvider = pair[1]
	_check_eq(manager.market_strength(), 1, "starting strength is 1")

	# Run a long stretch at capacity 1 so no arrival backlog can build up.
	# (Offers come and go here: they arrive at the strength-1 rate and lapse.)
	for i in 30:
		clock.advance_minutes(60.0)
		manager.evaluate_now()
	var before := manager.available_jobs().size()
	_check(before <= 1, "board never exceeds capacity 1 (%d on the board)" % before)

	clock.set_season(ACAJobEnums.Season.SPRING)
	manager.evaluate_now()
	_check_eq(manager.market_strength(), 3, "strength rose to 3")
	_check_eq(manager.max_available_jobs(), 3, "capacity rose to 3")
	_check(manager.available_jobs().size() <= before + 1,
		"raising demand does not instantly fill the new slots")

	clock.advance_minutes(5.0)
	manager.evaluate_now()
	_check(manager.available_jobs().size() <= before + 1,
		"the new slots still fill one offer at a time")

	# Given enough game time the board does reach the higher capacity.
	var peak := 0
	for i in 60:
		clock.advance_minutes(30.0)
		manager.evaluate_now()
		peak = maxi(peak, manager.available_jobs().size())
	_check(peak >= 2, "the market eventually supplies more offers at strength 3 (peak %d)" % peak)
	_check(peak <= 3, "and never exceeds the new capacity")
	_drop(manager)


func _test_drought_stops_new_offers() -> void:
	_say("- drought")
	var pair := _make_manager(ACAJobEnums.Season.SPRING, ACAJobEnums.Economy.BOOMING,
		ACAJobEnums.Climate.WET)
	var manager: ACAJobManager = pair[0]
	var clock: ACAJobDebugTimeProvider = pair[1]
	manager.debug_add_offer_with_seed(7001)
	manager.debug_add_offer_with_seed(7002)

	manager.set_climate(ACAJobEnums.Climate.DROUGHT)
	manager.evaluate_now()
	_check_eq(manager.market_strength(), 0, "drought forces strength 0")
	_check_eq(manager.available_jobs().size(), 2, "existing contracts are not deleted")

	for i in 20:
		clock.advance_minutes(60.0)
		manager.evaluate_now()
	_check(manager.available_jobs().size() <= 2, "no new offers arrive during drought")
	_check(is_inf(manager.minutes_until_next_arrival()), "no arrival is scheduled at strength 0")
	_drop(manager)


func _test_ui_board() -> void:
	_say("- job board UI")
	var pair := _make_manager()
	var manager: ACAJobManager = pair[0]
	var scene: PackedScene = load("res://Main Area/ACA_JobSystem/job_system/ui/JobBoard.tscn")
	if not _check(scene != null, "JobBoard.tscn loads"):
		_drop(manager)
		return
	var board := scene.instantiate() as ACAJobBoard
	if not _check(board != null, "JobBoard root is an ACAJobBoard"):
		_drop(manager)
		return
	add_child(board)
	board.set_manager(manager)

	var a := manager.debug_add_offer_with_seed(8001)
	manager.debug_add_offer_with_seed(8002)
	board.open()
	await get_tree().process_frame
	_check_eq(board.list_container.get_child_count(), 2, "Available tab lists both offers")

	var card := board.list_container.get_child(0) as ACAJobCard
	_check(card != null and card.title_label.text == a.job_site.to_upper(),
		"card shows the job site")
	_check(card.footer_label.text.begins_with("Offer expires in"),
		"card shows the offer countdown: \"%s\"" % card.footer_label.text)
	_check(card.action_button.text == "ACCEPT", "Available card offers ACCEPT")

	# Press the real Accept button.
	card.action_button.pressed.emit()
	await get_tree().process_frame
	_check_eq(manager.current_jobs().size(), 1, "pressing ACCEPT accepted the job")
	_check_eq(board.current_tab(), ACAJobBoard.Tab.CURRENT, "board switched to the Current tab")
	_check_eq(board.list_container.get_child_count(), 1, "Current tab shows the accepted job")

	var current_card := board.list_container.get_child(0) as ACAJobCard
	_check(current_card.action_button.text == "BEGIN JOB", "Current card offers BEGIN JOB")
	var requested: Array[ACAJob] = []
	manager.begin_job_requested.connect(func(j: ACAJob) -> void: requested.append(j))
	current_card.action_button.pressed.emit()
	await get_tree().process_frame
	_check_eq(requested.size(), 1, "BEGIN JOB reaches begin_job_requested")

	manager.update_job_progress(a.id, 0.5)
	await get_tree().process_frame
	current_card = board.list_container.get_child(0) as ACAJobCard
	_check(current_card.action_button.text == "RETURN TO JOB",
		"a partially completed job reads RETURN TO JOB")

	# The board greys ACCEPT against the PLAYER's limit, which the host supplies.
	# Without a host there is no such limit, so one is supplied here - that is
	# exactly how the real application does it.
	manager.player_capacity_provider = func() -> Dictionary:
		if manager.current_jobs().is_empty():
			return {"allowed": true, "reason": ""}
		return {"allowed": false, "reason": "Finish the contract you are on."}
	board.show_tab(ACAJobBoard.Tab.AVAILABLE)
	await get_tree().process_frame
	var blocked_card := board.list_container.get_child(0) as ACAJobCard
	_check(blocked_card.action_button.disabled,
		"Accept is blocked while the player holds a contract")

	manager.complete_job(a.id)
	board.show_tab(ACAJobBoard.Tab.PAST)
	await get_tree().process_frame
	_check_eq(board.list_container.get_child_count(), 1, "Past tab lists the completed job")
	var past_card := board.list_container.get_child(0) as ACAJobCard
	_check(past_card.row_b_key.text == "Completed", "Past card shows completion")

	var opened := [false]
	var closed := [false]
	board.opened.connect(func() -> void: opened[0] = true)
	board.closed.connect(func() -> void: closed[0] = true)
	board.close()
	board.open()
	_check(opened[0] and closed[0], "board emits opened/closed for host modal handling")

	board.queue_free()
	_drop(manager)
