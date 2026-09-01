class_name ACAGameSession
extends Node
## THE application/host layer. Autoloaded as `GameSession`.
##
## Owns three things and nothing else:
##   1. Which screen the application is on, and every scene transition.
##   2. The durable session state that is not owned by another system
##      (money, the economy DIFFICULTY, whether a session is active, elapsed
##      time on the active job).
##   3. THE ONE authoritative job-completion pathway.
##
## It deliberately does NOT own: job state (ACAJobManager does), world time or
## weather (ACAWorldClock does), the mowing state (ACALawn does), or any
## presentation (the UI components do).
##
##     Main Menu --new_game--> Town --accept--> JobManager
##                              ^                    |
##                              |          begin_job_requested
##                       return_to_town               |
##                              |                     v
##                          Job Complete <-- Mowing (ACAProperty / ACALawn)
##
## The Job System's boundary is preserved exactly: ACAJobManager emits
## begin_job_requested and stops; THIS class performs the scene transition.

# ------------------------------------------------------------------- signals
## The application arrived on a new screen. `context` is one of Screen.
signal screen_changed(screen: int)
## A session started (new game or loaded save).
signal session_started()
signal session_ended()
signal money_changed(amount: int)
## The session's economy difficulty changed. Emitted on a new game and on a load.
signal difficulty_changed(id: StringName)

## THE completion result, emitted after the job has really been completed in
## ACAJobManager. Carries everything a results screen needs so the UI never has
## to reach back into job internals. Keys:
##   job_id, job_name, job_size, completion, elapsed_seconds, base_pay, bonus, total
signal job_settled(summary: Dictionary)

## Emitted the moment a scene change is requested, before the screen is covered.
## GameSession drives the transition itself; this is for anything else that
signal scene_change_started(target_screen: int)

enum Screen { NONE, MAIN_MENU, TOWN, MOWING }

# ---------------------------------------------------------------------- paths
const MAIN_MENU_SCENE := "res://Game/App/Main Menu Screen.tscn"
const TOWN_SCENE := "res://Game/App/Town Screen.tscn"
## EVERY REGION EXCEPT HOME. One scene, told which territory it is standing in;
## see `ACARegionalHub` for why five hubs are one screen and not five.
const HUB_SCENE := "res://Main Area/ACA_RegionalHubs/Regional Hub Screen.tscn"
const MOWING_SCENE := "res://Game/M.V.P/Minimum Viable Game.tscn"

## The float a new business opens with when no difficulty says otherwise. It is
## also exactly `ACADifficulty`'s Medium and legacy value, so this constant and
## the profile table can never quietly disagree; Economy Test asserts it.
const STARTING_MONEY := 250

# --------------------------------------------------------------------- state
var _screen: int = Screen.NONE
var _session_active: bool = false
var _money: int = 0
## THE economy difficulty for this session. `ACADifficulty` owns the numbers;
## this owns WHICH profile is in force, because that is session state and
## session state is this class's job. Nothing else writes it.
var _difficulty: StringName = ACADifficulty.DEFAULT_ID
## Real seconds spent inside the current mowing job. Accumulated by the mowing
## scene through add_job_elapsed(); reset when a job begins.
var _job_elapsed_seconds: float = 0.0
var _time_provider: ACAWorldClockTimeProvider
var _changing_scene: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Quick save/load is an application-level concern, and the Town has no pause
	# menu of its own, so the binding lives here rather than in a screen.
	set_process_unhandled_input(true)

	# Give the Job System the real clock. Until this happens the manager runs on
	# a stopped default clock and no offers ever arrive.
	_time_provider = ACAWorldClockTimeProvider.new(WorldClock)
	JobManager.set_time_provider(_time_provider)

	# THE GAMEPLAY HANDOFF. The Job System never changes scenes; we do.
	JobManager.begin_job_requested.connect(_on_begin_job_requested)

	# WHAT KIND OF PLACE A CONTRACT IS, on its work order. The Job System knows a
	# property type; the mowing side knows what that type turns into on the
	# ground. This layer is where the two meet, exactly as it is for the clock
	# and for the market, and it is the SAME derivation the generator uses - so a
	# card that says "House and garden" is a card whose property has a house on
	# it.
	JobManager.site_note_provider = func(job: ACAJob) -> String:
		var note := ACAPropertyArchetype.short_description_of(
			ACAPropertyArchetype.for_property_type(job.property_type, job.seed))
		# ...and WHAT CONDITION IT IS IN, when that is worth saying. Empty on
		# every ordinary contract, so this adds nothing to the great majority of
		# work orders and is unmissable on the few it does.
		var label := ACAPropertyCondition.contract_label(
			Business.condition_stage_for(job))
		return note if label.is_empty() else "%s - %s" % [label, note]

	# The Job System does not know the economy exists. The APPLICATION layer
	# connects them, the same way it hands over the clock — so a new offer is
	# priced by the market, and an ACCEPTED contract never is again.
	#
	# The DIFFICULTY's pay scale rides along here rather than in the generator,
	# for exactly the same reason the market does: it is applied ONCE, when an
	# offer is created, and an accepted contract's payout is never recomputed.
	JobManager.pay_multiplier_provider = func() -> float:
		return Economy.job_index() * ACADifficulty.value("job_pay_scale", 1.0)

	# WHERE THE BUSINESS IS ALLOWED TO WORK. The Job System rolls contracts out
	# of the whole catalogue and asks this layer whether each one is work this
	# company could actually take; a region whose service lot has not been
	# bought never reaches the board. Same shape as every other provider - the
	# package still has no idea a map exists.
	JobManager.offer_filter_provider = func(job: ACAJob) -> bool:
		return Territory.accepts_offer(job)

	# ...and HOW THE BOARD GROUPS WHAT IT SHOWS. The Job Board draws a filter row
	# from whatever groups come back, so the row appears the day the business
	# opens its second territory and not before.
	JobManager.job_group_provider = func(job: ACAJob) -> Dictionary:
		var region := ACAServiceTerritory.region_for_job(job)
		return {
			"id": ACAServiceTerritory.region_id(region),
			"label": ACAServiceTerritory.region_short_name(region),
			"colour": ACAServiceTerritory.region_colour(region),
		}

	# THE RECESSION MARKET BRIDGE. `Economy` owns the condition; `ACAJobManager`
	# owns the market. Neither knows about the other, and neither should: this
	# layer connects them, through the Job System's own public `set_economy()`
	# and the recession modifier `ACAJobMarket` has always had.
	#
	# Under the current Spring / Normal world that turns offer capacity from 4
	# into 4 - 2 = 2 for as long as the downturn lasts. Fewer contracts on the
	# board is what makes a recession something the player has to plan around
	# rather than a number in a tooltip.
	Economy.condition_changed.connect(_on_economy_condition_changed)
	_apply_economy_to_market(Economy.condition())

	# HOW MANY CONTRACTS THE PLAYER MAY HOLD THEMSELVES.
	#
	# The Job System's own capacity is the BUSINESS's - five, so every machine a
	# fully equipped company owns can be out at once. That is not the same
	# question as how many gardens a contractor can stand in, which is one, and
	# which is a fact about the player rather than about the job market. So the
	# Job System asks, and this layer answers.
	JobManager.player_capacity_provider = func() -> Dictionary:
		if _player_contract_count() < max_player_contracts():
			return {"allowed": true, "reason": ""}
		return {
			"allowed": false,
			"reason": "Finish the contract you are on before taking another. A machine can take one for you.",
		}

	# SENDING A MACHINE INSTEAD OF GOING. The Job System renders a second button
	# on an offer and asks the host what it should say; this layer answers, and
	# handles it when it is pressed. The package still has no idea what a mower
	# is - see `ACAJobManager.offer_action_provider`.
	JobManager.offer_action_provider = _offer_action_for
	JobManager.offer_action_requested.connect(_on_offer_action)

	# Player-facing notifications for real domain events. Deliberately few:
	# accepting work, new work arriving, and getting paid.
	JobManager.job_accepted.connect(_on_job_accepted)
	JobManager.job_generated.connect(_on_job_generated)

	# THE BUSINESS LAYER'S HEARTBEAT.
	#
	# `Business`, `Equipment` and `Clippings` all have work that happens because
	# TIME PASSED - the competition looking at the board, an autonomous machine
	# finishing a contract, a compost heap coming good, a customer becoming due.
	# None of them runs a clock of its own, deliberately: two clocks in a game
	# always drift, and the one that matters is `WorldClock`. So this layer
	# drives all three from the clock's own signals, exactly as it already
	# drives the market and the job board.
	WorldClock.time_changed.connect(_on_world_time_changed)
	WorldClock.day_changed.connect(_on_world_day_changed)
	Business.offer_lost.connect(_on_offer_lost)
	# An offer that lapsed on its own is a customer who was not called back.
	JobManager.job_expired.connect(_on_job_expired)


## F5 quick-save, F9 quick-load. Available on any screen with a live session.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_F5:
		if SaveService.save_game():
			AppUI.notify_success("Game saved")
		get_viewport().set_input_as_handled()
	elif key == KEY_F9:
		if SaveService.load_most_recent():
			AppUI.notify_info("Game loaded")
		get_viewport().set_input_as_handled()


# ============================================================ session lifecycle

## Fresh game. Milestone 1 scope: whatever initialisation a coherent new session
## needs. Profile/save handling belongs to the save system, not here.
func start_new_game(difficulty: StringName = ACADifficulty.DEFAULT_ID) -> void:
	# BEFORE anything reads a price. The starting float, the first offers' pay
	# and the market's first fuel price all come from the profile, so it has to
	# be in force before the world, the economy or the job board exist.
	_set_difficulty(difficulty if ACADifficulty.is_valid(difficulty)
		else ACADifficulty.DEFAULT_ID)
	JobManager.debug_clear_all()
	WorldClock.start_new_world()
	Economy.start_new_economy(0, WorldClock.day_index())
	MowerUpgrades.reset_all()
	Equipment.reset_to_new_business()
	Clippings.reset_to_new_business()
	Business.reset_to_new_business()
	Territory.reset_to_new_business()
	Agreements.reset_to_new_business()
	Portfolio.reset_to_new_business()
	_set_money(int(ACADifficulty.value("starting_money", STARTING_MONEY)))
	_job_elapsed_seconds = 0.0
	_session_active = true

	# The market schedules its first arrival from "now"; re-anchor it against the
	# clock that just started so offers arrive relative to the new world, then
	# put a couple of contracts up so day one is not an empty board.
	JobManager.set_time_provider(_time_provider)
	JobManager.seed_initial_offers(2)

	session_started.emit()
	go_to_town()


func end_session() -> void:
	_session_active = false
	WorldClock.set_running(false)
	session_ended.emit()


func is_session_active() -> bool:
	return _session_active


# ================================================================== difficulty

## The economy difficulty in force. Always a valid `ACADifficulty` id.
func difficulty() -> StringName:
	return _difficulty


func difficulty_name() -> String:
	return ACADifficulty.display_name(_difficulty)


## Private on purpose: a difficulty is chosen when a game STARTS and restored
## when one loads, and is not a setting the player toggles mid-business.
func _set_difficulty(id: StringName) -> void:
	_difficulty = id
	ACADifficulty.set_active(id)
	difficulty_changed.emit(id)


# ========================================================= the recession bridge

func _on_economy_condition_changed(condition: int) -> void:
	_apply_economy_to_market(condition)


## Map the market CONDITION on to the Job System's own economy input. The Job
## System's enum is older and coarser than `Economy.Condition`, which is why
## this is a mapping rather than a cast: only Recession has a meaningful
## counterpart, and everything else is ordinary trading as far as the number of
## contracts on the board is concerned.
func _apply_economy_to_market(condition: int) -> void:
	var value := ACAJobEnums.Economy.RECESSION \
		if condition == ACAEconomyManager.Condition.RECESSION \
		else ACAJobEnums.Economy.NORMAL
	if int(JobManager.economy) != int(value):
		JobManager.set_economy(value)


## Used by the save system when a load restores an in-progress session.
func mark_session_active(value: bool) -> void:
	_session_active = value


# ================================================================== navigation

func go_to_main_menu() -> void:
	_change_scene(MAIN_MENU_SCENE, Screen.MAIN_MENU)


## THE BUSINESS'S BASE, whichever one that is. The home region is the authored
## Business Town; every other is the procedural regional hub.
##
## Deliberately still `Screen.TOWN`. A regional hub IS the town for every
## purpose the application layer has - it is where the job board is, where the
## competition bids, where a save is written from and where a contract returns
## to - and inventing a second screen state for it would mean auditing every
## comparison in the project for a case that behaves identically.
func go_to_town() -> void:
	WorldClock.set_running(true)
	_change_scene(_base_scene_for(Territory.active_region()), Screen.TOWN)


static func _base_scene_for(region: int) -> String:
	return TOWN_SCENE if region == ACAServiceTerritory.HOME_REGION else HUB_SCENE


## MOVE THE BUSINESS TO ANOTHER OF ITS SERVICE LOTS.
##
## Travel is a scene change and an hour of the working day, not a drive: there
## is no road between the regions and building one would be a driving game
## bolted to a mowing game. The hour is what stops a player hopping between
## five markets in a morning to skim the best contract off each.
func travel_to_region(region: int) -> bool:
	if not Territory.owns(region) or _changing_scene:
		return false
	if Territory.active_region() == region:
		return true
	Territory.set_active_region(region)
	WorldClock.advance_minutes(TRAVEL_MINUTES)
	AppUI.notify_info("On the road",
		"%s. The trip takes about an hour." % ACAServiceTerritory.region_name(region))
	go_to_town()
	return true


## Game minutes a move between service lots costs. One working hour.
const TRAVEL_MINUTES := 60.0


func go_to_mowing() -> void:
	WorldClock.set_running(true)
	_change_scene(MOWING_SCENE, Screen.MOWING)


func current_screen() -> int:
	return _screen


## True while a transition is covering the screen and swapping scenes. Requests
## to change scene are ignored during this window.
func is_changing_scene() -> bool:
	return _changing_scene


func _change_scene(path: String, screen: int) -> void:
	if _changing_scene:
		return
	_changing_scene = true
	scene_change_started.emit(screen)
	_swap_scene(path, screen)


## Cover the screen, swap, reveal. Awaiting the transition here is what keeps
## the scene change from being visible; the UI layer decides how it looks.
func _swap_scene(path: String, screen: int) -> void:
	# Cursor holds belong to the screen that took them, and that screen is about
	# to be freed. The incoming screen declares its own context in _ready().
	AppUI.clear_mouse_holds()
	AppUI.set_transition_title(_transition_title_for(screen))
	AppUI.cover()
	await AppUI.screen_covered

	_screen = screen
	# Deferred: this is frequently reached from a signal emitted during a button
	# press inside the scene being replaced.
	get_tree().call_deferred("change_scene_to_file", path)

	# One frame for the swap, one for the new scene to run _ready().
	await get_tree().process_frame
	await get_tree().process_frame

	# BACK AT A SERVICE LOT. Everything on the trailer goes into the yard, which
	# is what ends a route: the clipping capacity of the trailer is a limit that
	# only exists BETWEEN visits to a lot, and this is the visit.
	if screen == Screen.TOWN:
		var deposited: float = Clippings.deposit_trailer_at_yard()
		if deposited > 0.0:
			AppUI.notify_success("Trailer emptied",
				"%s into the yard." % ACAClippings.format_kg(deposited))

	screen_changed.emit(screen)
	AppUI.clear_transition_title()
	AppUI.reveal()
	_changing_scene = false


func _transition_title_for(screen: int) -> String:
	match screen:
		Screen.TOWN:
			var region := Territory.active_region()
			if _screen == Screen.MOWING:
				return "RETURNING TO %s" % ACAServiceTerritory.region_name(region).to_upper()
			return ACAServiceTerritory.region_name(region).to_upper()
		Screen.MOWING:
			var job := current_job()
			return job.job_site.to_upper() if job != null else "MOWING"
		Screen.MAIN_MENU:
			return ""
	return ""


# ======================================================================= money

func money() -> int:
	return _money


func _set_money(amount: int) -> void:
	if _money == amount:
		return
	_money = amount
	money_changed.emit(_money)


func add_money(amount: int) -> void:
	_set_money(_money + amount)


## THE transaction API. `Economy` and `MowerUpgrades` price things; this is the
## only place a price is ever PAID, so there is exactly one balance in the game
## and it can never go negative.
func can_afford(amount: int) -> bool:
	return amount >= 0 and _money >= amount


## Take `amount` if it is there. Returns false and changes nothing otherwise —
## callers must not assume success.
func try_spend(amount: int) -> bool:
	if amount < 0 or not can_afford(amount):
		return false
	_set_money(_money - amount)
	return true


# ============================================================== the active job

## The accepted contract the player is currently working, or null. Identity is
## the ACAJob owned by ACAJobManager - this class never copies job data into a
## parallel object.
## THE contract the PLAYER is working, or null.
##
## The current list holds every contract the BUSINESS has open, which since the
## autonomous fleet arrived can be several - so the first entry is no longer
## necessarily the player's. A contract an owned machine is out on belongs to
## the machine, and the mowing scene must never be built for one: the player
## would be driven to a property their own equipment is already finishing.
func current_job() -> ACAJob:
	for job in JobManager.current_jobs():
		if not _is_machine_contract(job.id):
			return job
	return null


## How many contracts the player may personally hold. One, and it is a fact
## about a contractor rather than about the market - see the provider above.
func max_player_contracts() -> int:
	return 1


func _player_contract_count() -> int:
	var count := 0
	for job in JobManager.current_jobs():
		if not _is_machine_contract(job.id):
			count += 1
	return count


## Whether an owned autonomous machine is out on this contract. Asked of
## `Equipment`, which owns the assignments; nothing here keeps a second copy.
func _is_machine_contract(job_id: StringName) -> bool:
	for entry: Dictionary in Equipment.autonomous_units():
		if StringName(String(entry["job_id"])) == job_id:
			return true
	return false


## Every contract an owned machine is currently out on. For the Job Office, so a
## card can say who is working it.
func machine_contract_ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in Equipment.autonomous_units():
		var id := String(entry["job_id"])
		if not id.is_empty():
			out.append(id)
	return out


func current_job_id() -> StringName:
	var job := current_job()
	return job.id if job != null else &""


func has_active_job() -> bool:
	return current_job() != null


func job_elapsed_seconds() -> float:
	return _job_elapsed_seconds


func set_job_elapsed(seconds: float) -> void:
	_job_elapsed_seconds = maxf(seconds, 0.0)


func add_job_elapsed(delta: float) -> void:
	_job_elapsed_seconds += maxf(delta, 0.0)


## ACAJobManager emitted begin_job_requested. Do the transition it deliberately
## refuses to do itself.
func _on_job_accepted(job: ACAJob) -> void:
	if _dev_quiet:
		return
	AppUI.notify_success("Contract accepted", "%s - %s" % [job.job_site, job.pay_text()])


func _on_job_generated(job: ACAJob) -> void:
	# Only worth a toast while the player is in town and could act on it.
	if _screen != Screen.TOWN or _dev_quiet:
		return
	AppUI.notify_info("New job available", "%s - %s" % [job.job_site, job.lawn_size_name()])


## THE BUSINESS TICK. Everything that happens because game minutes passed.
##
## Deliberately cheap: two comparisons and an early return on almost every call.
## `consider_competition` and `resolve_finished_work` both do their own interval
## and deadline checks, so this does not need a timer, an accumulator or a
## schedule of its own.
##
## NOT while a scene change is in flight: a contract settling into a results
## screen that is being torn down is the one ordering this cannot survive.
func _on_world_time_changed(minutes: float) -> void:
	if not _session_active or _changing_scene:
		return
	Equipment.resolve_finished_work(minutes)
	# The competition only bids while the player is somewhere they could have
	# taken the work themselves. Losing a contract to a rival during the twenty
	# minutes the player spent mowing a different one is not a decision they
	# made, it is a number that moved behind their back.
	if _screen == Screen.TOWN:
		Business.consider_competition(minutes)


func _on_world_day_changed(day_index: int) -> void:
	if not _session_active:
		return
	Clippings.advance_to_day(day_index)
	Agreements.advance_to_day(day_index)
	Business.prune_schedule()
	var returning := Business.advance_to_day(day_index)
	if returning > 0 and _screen == Screen.TOWN:
		AppUI.notify_info("Repeat customers",
			"%d propert%s due for another service." % [
				returning, "y is" if returning == 1 else "ies are"])


## ---------------------------------------------------------------------------
## SENDING A MACHINE
## ---------------------------------------------------------------------------
## The button an offer card shows beside ACCEPT. It appears only when the
## business owns an autonomous machine at all, so a player who has not bought one
## never sees a control for a system they do not have.
##
## The REASON it is disabled is always given, because "greyed out with no
## explanation" is the worst possible answer to "why can I not do this".
func _offer_action_for(job: ACAJob) -> Dictionary:
	if not Equipment.has_autonomous_units():
		return {}
	var idle := Equipment.idle_units()
	if idle.is_empty():
		return {"text": "SEND A MACHINE", "enabled": false,
			"note": "Every machine is already out on a contract."}

	# The best machine that is RATED for this contract. Cheapest capable first,
	# so a commercial unit is not sent to a small garden while a compact one
	# stands in the yard.
	var chosen := _best_unit_for(job, idle)
	if chosen.is_empty():
		return {"text": "SEND A MACHINE", "enabled": false,
			"note": "No idle machine is rated for a %s contract."
				% job.lawn_size_name().to_lower()}
	var spec := ACAEquipment.tier_spec(String(chosen["tier"]))
	if ACAContractTerms.requires_collection(job) and float(spec["bag_kg"]) <= 0.0:
		return {"text": "SEND A MACHINE", "enabled": false,
			"note": "This contract collects, and that machine mulches."}

	var minutes := Equipment.estimated_minutes_now(String(chosen["tier"]), job)
	return {
		"text": "SEND A MACHINE",
		"enabled": true,
		"note": "%s - about %d minutes." % [
			Equipment.unit_label(int(chosen["uid"])), int(round(minutes))],
	}


## The CHEAPEST idle machine rated for this contract. Cheapest rather than best,
## so the fleet is used the way a business would use it.
func _best_unit_for(job: ACAJob, idle: Array) -> Dictionary:
	var best := {}
	var best_rate := INF
	for entry: Dictionary in idle:
		var spec := ACAEquipment.tier_spec(String(entry["tier"]))
		if spec.is_empty() or int(job.lawn_size) > int(spec["max_size"]):
			continue
		if ACAContractTerms.requires_collection(job) and float(spec["bag_kg"]) <= 0.0:
			continue
		var rate := float(spec["cells_per_minute"])
		if rate < best_rate:
			best_rate = rate
			best = entry
	return best


func _on_offer_action(job: ACAJob) -> void:
	if job == null:
		return
	var chosen := _best_unit_for(job, Equipment.idle_units())
	if chosen.is_empty():
		AppUI.notify_warning("No machine for that",
			"Nothing idle is rated for this contract.")
		return
	var uid := int(chosen["uid"])
	var finish := Equipment.assign_to_contract(uid, job.id)
	if finish < 0.0:
		AppUI.notify_warning("Could not send it",
			"That contract is no longer available.")
		return
	var minutes := Equipment.estimated_minutes_now(String(chosen["tier"]), job)
	AppUI.notify_success("Machine sent",
		"%s is on %s - about %d minutes." % [
			Equipment.unit_label(uid), job.job_site, int(round(minutes))])


func _on_offer_lost(job_site: String, competitor_name: String) -> void:
	# ONE TOAST, and only in town. A notification per lost contract while the
	# player is mowing would be the game interrupting itself to report something
	# they cannot act on.
	if _screen != Screen.TOWN:
		return
	AppUI.notify_info("Contract taken", "%s went to %s." % [job_site, competitor_name])


func _on_job_expired(job: ACAJob) -> void:
	# A returning customer whose offer nobody took has been let down, whether it
	# lapsed or a rival picked it up. `Business` knows which of its customers
	# this was; a contract that was never one of them is ignored.
	Business.note_offer_lapsed(job)


func _on_begin_job_requested(job: ACAJob) -> void:
	if job == null:
		return
	# Only reset the stopwatch for a job that has not been started yet, so
	# returning to a partially mowed job later keeps its accumulated time.
	if job.progress <= 0.0:
		_job_elapsed_seconds = 0.0
	go_to_mowing()


# ====================================================== authoritative completion

## THE ONE completion pathway.
##
## Real 100% mowing and the development fast-completion helper both end up
## here, and so will any future completion trigger. It moves the job to history
## through ACAJobManager (the owner), settles pay, and publishes a summary for
## the results UI. It does NOT change scene - the results screen decides when
## the player returns to town.
##
## Returns false if there was no active job to complete.
## `outcome` is what the mowing runtime MEASURED, and every field is optional so
## a caller that has nothing to say about a term simply does not mention it:
##   collected_kg     clippings delivered to the truck
##   spilled_kg       cut grass the machine had nowhere to put
##   fuel_used        tank units burned on this property
##   ran_dry          whether the tank reached empty here
##   autonomous_uid   the escort unit that helped, 0 for none
##   autonomous_cells cells the escort cut
func complete_current_job(completion: float, elapsed_seconds: float = -1.0,
		outcome: Dictionary = {}) -> bool:
	var job := current_job()
	if job == null:
		push_warning("GameSession.complete_current_job: no active job")
		return false

	if elapsed_seconds >= 0.0:
		_job_elapsed_seconds = elapsed_seconds

	var job_id := job.id
	var final_completion := clampf(completion, 0.0, 1.0)

	# WHAT THE CONTRACT ASKED FOR, scored against what actually happened. The
	# terms are derived from the contract's own seed, so this needs nothing from
	# the save file and nothing from the Job System.
	var measured := outcome.duplicate()
	measured["completion"] = final_completion
	measured["elapsed_minutes"] = _elapsed_game_minutes()
	var scored := ACAContractTerms.score(job, measured)

	# A MANDATORY TERM MISSED IS NOT A COMPLETION. Only collection is ever
	# mandatory, and only on about a third of the contracts that ask for it -
	# but where it is, leaving the clippings on the lawn means the job was not
	# what was agreed, and the contract is not settled.
	if int(scored["mandatory_missed"]) != 0 and final_completion >= 1.0:
		return false

	# WHAT A RESCUE IS WORTH. A neglected property is heavier work and produces
	# far more to carry away, and the customer pays for that.
	#
	# IT IS A BONUS, NOT A REPRICING. `base_pay` is what the board promised and
	# is never rewritten by anything - that invariant is older than this system
	# and is what makes an accepted contract a contract. A premium earned by the
	# state the ground turned out to be in is exactly what the bonus line is
	# for, and it appears on the results sheet beside the contract's own terms.
	var base_pay := job.base_pay
	var stage := Business.condition_stage_for(job)
	var rescue := int(round(float(base_pay)
		* (ACAPropertyCondition.pay_multiplier(stage) - 1.0)))
	var bonus := int(scored["bonus"]) + rescue

	# The manager is the owner: it sets status, timestamps and history.
	JobManager.update_job_progress(job_id, final_completion)
	if not JobManager.complete_job(job_id):
		return false

	var paid := base_pay + bonus
	add_money(paid)
	AppUI.notify_money("Payment received", UITheme.format_money(paid))

	# THE COMPANY'S BOOKS. Reputation, the review, the customer record and the
	# market window all move here, once, after the contract is really finished.
	var review := Business.settle_completed_job(job, measured, paid)

	var summary := {
		"job_id": job_id,
		"job_name": job.job_site,
		"job_size": job.lawn_size_name(),
		"completion": final_completion,
		"elapsed_seconds": _job_elapsed_seconds,
		"base_pay": base_pay,
		"bonus": bonus,
		"total": paid,
		# --- additive, and every one of them measured rather than invented ---
		"terms_met": int(scored["met"]),
		"terms_missed": int(scored["missed"]),
		"collected_kg": float(measured.get("collected_kg", 0.0)),
		"spilled_kg": float(measured.get("spilled_kg", 0.0)),
		"fuel_used": float(measured.get("fuel_used", 0.0)),
		"review_stars": int(review.get("stars", 0)),
		"review_text": String(review.get("text", "")),
		"reputation_change": float(review.get("reputation_change", 0.0)),
		"reputation": Business.reputation(),
		"loyalty": Business.loyalty_for(job),
		"services": Business.services_for(job),
		"autonomous_cells": int(measured.get("autonomous_cells", 0)),
		"autonomous_name": String(measured.get("autonomous_name", "")),
		# --- the expansion's readings, passed straight through. Every one of
		# them was MEASURED by the mowing runtime or DERIVED from the contract's
		# own seed; nothing here computes anything the sheet then reports as a
		# fact about the job.
		"region": int(ACAServiceTerritory.region_for_job(job)),
		"region_name": ACAServiceTerritory.region_name(
			ACAServiceTerritory.region_for_job(job)),
		"machine_name": String(measured.get("machine_name", "")),
		"mode_name": String(measured.get("mode_name", "")),
		"service_name": String(measured.get("mode_name", "")),
		"ground_name": String(measured.get("ground_name", "")),
		"pattern": int(measured.get("pattern", ACAFinishPattern.Pattern.NONE)),
		"pattern_met": bool(measured.get("pattern_met", false)),
		"pattern_score": float(measured.get("pattern_score", 0.0)),
		"pattern_note": String(measured.get("pattern_note", "")),
		"protected_cells": int(measured.get("protected_cells", 0)),
		"protected_damage": float(measured.get("protected_damage", 0.0)),
		"coverage": float(measured.get("coverage", 0.0)),
		"contacts": int(measured.get("contacts", 0)),
		"condition_stage_before": int(review.get("condition_stage_before",
			ACAPropertyCondition.Stage.MAINTAINED)),
		"condition_stage_after": int(review.get("condition_stage_after",
			ACAPropertyCondition.Stage.MAINTAINED)),
		"condition_stage_change": int(review.get("condition_stage_after", 0))
			- int(review.get("condition_stage_before", 0)),
		"recovery_premium": rescue,
		# Whether there is another stop on the day's list. See `next_scheduled_job()`.
		"next_stop": String(next_scheduled_job_id()),
	}
	job_settled.emit(summary)
	return true


## GAME minutes spent on this contract. The service window is expressed in game
## minutes because that is the clock the contract was written against; the
## stopwatch runs in real seconds because that is what a scene can measure. One
## conversion, in one place, so the two can never disagree.
func _elapsed_game_minutes() -> float:
	return _job_elapsed_seconds * _game_minutes_per_real_second()


## THE CLOCK OWNS ITS OWN RATE, and it is a tunable rather than a constant. Read
## rather than copied, so changing the world's pace cannot leave a second,
## stale conversion factor behind in this file.
func _game_minutes_per_real_second() -> float:
	return maxf(WorldClock.game_minutes_per_real_second, 0.001)


## ---------------------------------------------------------------------------
## A CONTRACT FINISHED BY A MACHINE THE PLAYER DID NOT DRIVE
## ---------------------------------------------------------------------------
## Same pathway, same payment, same review, same books - the only difference is
## that nobody was in the scene, so the outcome is DERIVED from the unit's own
## rated capability rather than measured from a lawn.
##
## It is deliberately not a second completion function with its own rules: it
## assembles an outcome and calls the one above. `Equipment` owns the timing and
## the fleet; this owns completion, exactly as it does for the player.
func complete_autonomous_job(job_id: StringName, quality: float,
		minutes: float, unit_uid: int, bag_kg: float,
		fuel_per_minute: float) -> bool:
	var job := JobManager.get_job(job_id)
	if job == null or not job.is_active():
		return false

	# The active job for the completion call has to be THIS one. An autonomous
	# contract and a driven contract can be live at the same time, so the
	# completion below is given the id explicitly rather than assuming.
	var was_elapsed := _job_elapsed_seconds
	_job_elapsed_seconds = minutes / _game_minutes_per_real_second()

	var outcome := {
		"autonomous": true,
		"autonomous_quality": quality,
		"autonomous_name": Equipment.unit_label(unit_uid),
		# A rated machine collects what the contract expects of it, up to what it
		# can carry across the trips it makes. A mulching unit collects nothing,
		# which is why it is refused a collection contract in the first place.
		"collected_kg": ACAContractTerms.expected_yield_kg(job) if bag_kg > 0.0 else 0.0,
		"spilled_kg": 0.0,
		"fuel_used": fuel_per_minute * minutes,
		"ran_dry": false,
	}
	if bag_kg > 0.0:
		var delivered: float = Clippings.deliver_direct(float(outcome["collected_kg"]))
		outcome["collected_kg"] = delivered

	# OFF-SCREEN WORK COSTS WHAT ON-SCREEN WORK COSTS. The machine burns fuel,
	# and the fuel is paid for at the market's price, exactly as the player's is.
	# There is no wage, no tax and no premium: it is owned equipment.
	var fuel_bill := Economy.fuel_cost_for_units(float(outcome["fuel_used"]))
	if fuel_bill > 0:
		try_spend(fuel_bill)
	outcome["fuel_cost"] = fuel_bill

	var settled := _complete_job_by_id(job_id, 1.0, outcome)
	_job_elapsed_seconds = was_elapsed
	if settled:
		AppUI.notify_success("Contract finished",
			"%s completed %s." % [Equipment.unit_label(unit_uid), job.job_site])
	return settled


## `complete_current_job` for a contract that may not be the one at the front of
## the current list. The Job System keeps current jobs in a list precisely so
## more than one can be live; this is what lets an autonomous contract settle
## while the player is standing on a different lawn.
func _complete_job_by_id(job_id: StringName, completion: float,
		outcome: Dictionary) -> bool:
	var jobs := JobManager.current_jobs()
	if jobs.is_empty():
		return false
	if jobs[0].id == job_id:
		return complete_current_job(completion, -1.0, outcome)
	# Not at the front: settle it directly through the same steps, so there is
	# still exactly one description of what completing a contract means.
	var job := JobManager.get_job(job_id)
	if job == null:
		return false
	var measured := outcome.duplicate()
	measured["completion"] = clampf(completion, 0.0, 1.0)
	measured["elapsed_minutes"] = _elapsed_game_minutes()
	var scored := ACAContractTerms.score(job, measured)
	if int(scored["mandatory_missed"]) != 0:
		return false
	JobManager.update_job_progress(job_id, clampf(completion, 0.0, 1.0))
	if not JobManager.complete_job(job_id):
		return false
	var paid := job.base_pay + int(scored["bonus"])
	add_money(paid)
	AppUI.notify_money("Payment received", UITheme.format_money(paid))
	Business.settle_completed_job(job, measured, paid)
	return true


## Give up on the active contract. The V1 Job System has no abandon concept, so
## this completes nothing and pays nothing - it drops the job out of Current and
## does not record it as business history.
## ---------------------------------------------------------------------------
## THE DAY AS A ROUTE
## ---------------------------------------------------------------------------
## `ACABusiness` owns the schedule - the queue of contracts the player means to
## do next. This is what turns that queue into a ROUTE: when a contract settles
## and there is another accepted one on the list, the results sheet can offer to
## drive straight to it instead of returning to the yard.
##
## What that changes is everything that persists between stops: the tank, the
## catcher, the trailer's load and the loadout all carry over, and the trailer
## is only emptied when the player actually goes back to a service lot. That is
## the whole of why a bigger trailer is worth buying.
##
## Returns the id of the next contract the player could drive to, or an empty
## name. A contract a machine is out on is never offered.
func next_scheduled_job_id() -> StringName:
	for id: String in Business.schedule_ids():
		var job := JobManager.get_job(StringName(id))
		if job == null or not job.is_active():
			continue
		if _is_machine_contract(job.id):
			continue
		return job.id
	# Nothing scheduled: any other accepted contract the player holds will do.
	for job in JobManager.current_jobs():
		if job.is_active() and not _is_machine_contract(job.id):
			return job.id
	return &""


func has_next_stop() -> bool:
	return not String(next_scheduled_job_id()).is_empty()


## DRIVE STRAIGHT TO THE NEXT STOP. Same handoff the job board uses, so there is
## one description of what beginning a contract means.
func go_to_next_stop() -> bool:
	var id := next_scheduled_job_id()
	if String(id).is_empty():
		return false
	return JobManager.begin_new_job(id)


func abandon_current_job() -> bool:
	var job := current_job()
	if job == null:
		return false
	JobManager.discard_current_job(job.id)
	_job_elapsed_seconds = 0.0
	return true


# ==================================================================== persistence

# ==================================================== development completions
## ---------------------------------------------------------------------------
## SYNTHETIC COMPLETED CONTRACTS, for the Super Debugger
## ---------------------------------------------------------------------------
## Reaching the parts of the game that only open after twenty or forty
## contracts should not cost an afternoon of mowing. This puts contracts through
## THE PRODUCTION PATH - the same one `complete_current_job()` uses - so every
## book a real contract writes in is written in here too, by the same call:
##
##   JobManager   commission_offer -> accept_job -> complete_job, so the
##                contract exists, is held, and lands in past jobs.
##   Business     settle_completed_job: the review, reputation, the customer
##                record, `contracts_completed`, lifetime revenue and the
##                market window - and it is Business that then tells
##                `Territory` and `Agreements`, exactly as it always does.
##
## THERE IS NO SECOND COUNTER. Nothing here writes a total; it finishes
## contracts and lets the totals follow.
##
## THE ONE DELIBERATE DIFFERENCE: `add_money()` is NOT called. The Super
## Debugger sets the balance directly, so paying for these as well would make
## every progression jump a money cheat the developer did not ask for. The
## FIGURE is still handed to `settle_completed_job()`, so lifetime revenue and
## the market's share of the week stay coherent - the contract earned its fee,
## the balance simply was not credited with it.
##
## The offers are drawn through `JobManager.offer_is_acceptable()`, the same
## filter the board publishes through, so synthetic work lands in the markets
## the business actually owns and regional presence moves where it should.

## Attempts per contract before giving up on finding an offer this business
## would have been shown. A business working one small market refuses most of
## what the generator produces; this is the same bounded reroll the board uses.
const DEV_OFFER_ATTEMPTS := 24

## Suppresses the "contract accepted" / "new job available" toasts while a batch
## of synthetic contracts goes through. Ten contracts is twenty notifications
## nobody asked for.
var _dev_quiet: bool = false


## DEVELOPMENT ONLY. Finish `count` contracts as though they had been driven.
## Returns how many actually settled.
func dev_add_completed_contracts(count: int) -> int:
	var wanted := clampi(count, 0, 200)
	if wanted <= 0:
		return 0
	var settled := 0
	_dev_quiet = true
	for _i in wanted:
		if not JobManager.has_current_capacity():
			break
		if not _dev_settle_one_contract():
			break
		settled += 1
	_dev_quiet = false
	return settled


func _dev_settle_one_contract() -> bool:
	var job := _dev_commission_offer()
	if job == null:
		return false
	if not JobManager.accept_job(job.id, true):
		return false
	JobManager.update_job_progress(job.id, 1.0)
	if not JobManager.complete_job(job.id):
		return false
	Business.settle_completed_job(job, _dev_clean_outcome(job), job.base_pay)
	return true


## An offer this business would have been shown, published on the board so the
## ordinary accept path can take it. Bounded, and null when the market has
## nothing for this business.
func _dev_commission_offer() -> ACAJob:
	for _attempt in DEV_OFFER_ATTEMPTS:
		var job_seed := randi() & 0x7FFFFFFF
		var candidate := ACAJobGenerator.generate(job_seed,
			WorldClock.game_minutes(), ACAJobBalance.GENERATOR_VERSION)
		if not JobManager.offer_is_acceptable(candidate):
			continue
		# Commission REGENERATES from the seed with the market's own pay
		# multiplier, so the published contract is priced exactly as a real
		# arrival with this seed would have been.
		var published := JobManager.commission_offer(job_seed)
		if published != null:
			return published
	return null


## A CLEAN JOB, measured the way a real one is. Every term this contract asks
## for is read from `ACAContractTerms` and then met, rather than a dictionary of
## guessed keys - so a term added to the game later is met here too, and a
## mandatory one is never accidentally missed.
func _dev_clean_outcome(job: ACAJob) -> Dictionary:
	var terms := ACAContractTerms.terms_for(job)
	return {
		"completion": 1.0,
		"elapsed_minutes": float(terms.get("window_minutes", 60.0)) * 0.5,
		"collected_kg": float(terms.get("collect_target_kg", 0.0)),
		"spilled_kg": 0.0,
		"fuel_used": 0.0,
		"ran_dry": false,
		"pattern_met": true,
		"pattern_score": 0.85,
		"protected_damage": 0.0,
		"autonomous": false,
	}


func to_save_dict() -> Dictionary:
	return {
		"money": _money,
		"screen": _screen,
		"session_active": _session_active,
		"job_elapsed_seconds": _job_elapsed_seconds,
		# WHICH HUB THE PLAYER WAS WORKING FROM. `Territory` owns which regions
		# the business has; this owns which of its screens the application was
		# on, exactly as it already owns `screen`.
		"region": String(ACAServiceTerritory.region_id(Territory.active_region())),
		# ONE ADDITIVE FIELD, and no save version bump. A build that does not
		# know about it ignores it; a save that does not carry it is handled
		# below. See project-docs/systems/save-and-load.md.
		"difficulty": String(_difficulty),
	}


func from_save_dict(data: Dictionary) -> void:
	_set_money(int(data.get("money", STARTING_MONEY)))
	_session_active = bool(data.get("session_active", true))
	_job_elapsed_seconds = float(data.get("job_elapsed_seconds", 0.0))
	# A SAVE WITH NO DIFFICULTY IN IT WAS PLAYED WITHOUT ONE, and the honest
	# thing to do with it is to keep playing it without one. `legacy` is exactly
	# the constants that save was created under, so a business a player has run
	# for a hundred in-game days does not have its fuel price and its contract
	# rates moved underneath it by a patch. It is never offered to a new game.
	var saved := StringName(String(data.get("difficulty", "")))
	_set_difficulty(saved if ACADifficulty.is_valid(saved) else ACADifficulty.LEGACY_ID)
	# `screen` is applied by the loader, which decides which scene to enter.
