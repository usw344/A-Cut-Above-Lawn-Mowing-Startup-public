class_name ACAGameplayUI
extends ACAPauseLayer
## The gameplay screen's UI stack, and the only place the mowing scene and the
## polished UI components know about each other.
##
## Extends ACAPauseLayer, which owns the shared pause stack (Pause Menu,
## Settings, Controls Help, Confirmation Dialog) and the tree-pause/cursor
## handling that goes with it. The Town uses the same class through
## `Pause Layer.tscn`, so there is exactly one pause menu implementation.
##
## What THIS class adds is the gameplay-only part: the HUD, the contract intro,
## the results screen, and restarting a contract.
##
## Every component here stays presentation-only. This script is the integration
## boundary: it reads state (GameSession / JobManager / WorldClock / the mowing
## host) and pushes it into the components, and it turns component signals back
## into calls on the systems that own the state.
##
## It never mutates job state directly - completion goes through
## GameSession.complete_current_job(), which the mowing host calls.

## The mowing scene root. Must provide:
##   mowing_progress() -> float        0.0 - 1.0
##   mower_fuel_fraction() -> float    0.0 - 1.0
##   restart_current_job() -> void
##   dev_toggle_debug_hud() -> void
@export var gameplay_host: Node

## Seconds the contract introduction stays up before gameplay starts.
@export var intro_seconds: float = 2.4

@onready var _hud: GameplayHUD = $"Gameplay HUD"
@onready var _minimap: MinimapPanel = get_node_or_null(^"Minimap")
@onready var _intro: JobIntroScreen = $"Job Intro"
@onready var _results: JobCompleteScreen = $"Job Complete"

## Set while the results screen is up, so the HUD stops fighting it for updates.
var _finished: bool = false
## Whether the map has been given the property yet. See `_bind_minimap()`.
var _minimap_bound: bool = false


func _ready() -> void:
	super._ready()
	_wire_hud()
	_wire_results()

	# Restarting a contract needs the mowing host, so the shared stack asks.
	restart_job_requested.connect(_restart_job)

	GameSession.job_settled.connect(_on_job_settled)
	WorldClock.weather_changed.connect(func(_p: String) -> void: _refresh_environment())

	var job := GameSession.current_job()
	set_pause_context(job.job_site if job != null else "")
	set_job_actions_available(job != null)

	_populate_from_job()
	_refresh_environment()
	_bind_minimap()
	_hud.show_hud()
	_play_intro()


## The mowing bindings, not the town's.
func control_bindings() -> PackedStringArray:
	return ACAControlBindings.MOWING


func _process(_delta: float) -> void:
	if _finished or gameplay_host == null:
		return
	var progress: float = gameplay_host.call(&"mowing_progress")
	_hud.set_progress(progress)
	_hud.set_fuel(gameplay_host.call(&"mower_fuel_fraction"))
	_refresh_environment()
	_refresh_site_readout()
	_refresh_business_readout()
	if not _minimap_bound:
		_bind_minimap()
	_track_mower_on_minimap(progress)


# =================================================================== contract

func _populate_from_job() -> void:
	var job := GameSession.current_job()
	if job == null:
		_hud.set_job_name("Practice Lawn")
		_hud.set_job_size("")
		_hud.set_property_type("")
		_hud.set_reward(0)
		return
	_hud.set_job_name(job.job_site)
	_hud.set_job_size(job.lawn_size_name())
	_hud.set_property_type(job.property_type_name())
	_hud.set_reward(job.base_pay)
	_hud.set_status("Mow the entire lawn")
	# WHAT THIS CUSTOMER ASKED FOR, on the same checklist as everything else.
	# Derived from the contract's own seed, so it is the same list the work
	# order showed before the player accepted it.
	_hud.set_contract_terms(ACAContractTerms.describe(job))


## ---------------------------------------------------------------------------
## WHAT THE MOWING SCENE TELLS THE HUD
## ---------------------------------------------------------------------------
## Three readings, all of them decided elsewhere: the ground condition comes
## from `ACAGroundConditions`, the configuration from `ACAEquipment`, and the
## requested finish from the contract's own seed. This layer only forwards them.
func set_ground_condition(state: int) -> void:
	if _hud != null and _hud.has_method(&"set_ground_condition"):
		_hud.call(&"set_ground_condition", state)


func set_mowing_mode(mode: int) -> void:
	if _hud != null and _hud.has_method(&"set_mowing_mode"):
		_hud.call(&"set_mowing_mode", mode)


func set_requested_pattern(pattern: int) -> void:
	if _hud != null and _hud.has_method(&"set_requested_pattern"):
		_hud.call(&"set_requested_pattern", pattern)


## The mowing scene hands the zones straight to the minimap through
## `_bind_minimap()`; this exists so the scene has one place to talk to.
func set_conservation_zones(zones: Array) -> void:
	if _minimap != null and _minimap.has_method(&"set_protected_zones"):
		_minimap.call(&"set_protected_zones", zones)


func _refresh_environment() -> void:
	_hud.set_game_time(WorldClock.clock_text())
	_hud.set_weather(WorldClock.weather_preset())
	_hud.set_day("Day %d" % WorldClock.day_number())


## THE CHECKLIST NUMBERS, and they come from the property rather than from the
## contract: the lawn's own mowable total is what completion is measured
## against, and what is standing on the ground is whatever the feature set
## actually built. A card that read those off the job would eventually promise a
## pond the property does not have.
func _refresh_site_readout() -> void:
	var property := _property()
	if property == null or not property.is_built():
		return
	var lawn := property.lawn()
	if lawn != null:
		_hud.set_area(lawn.mowed_item_count(), lawn.total_item_count())
	var features := property.features()
	if features == null:
		return
	var pond := false
	var obstacles := 0
	for feature in features.features():
		if feature is ACAPondFeature:
			pond = true
		elif feature is ACALawnObstacles:
			obstacles = (feature as ACALawnObstacles).count()
	_hud.set_site_notes(pond, obstacles)


## ---------------------------------------------------------------------------
## THE BUSINESS READOUTS
## ---------------------------------------------------------------------------
## The catcher, the contract's terms and the machine working beside the player.
## All three are read from their own authority every frame rather than pushed at
## the HUD when something happens: a gauge that is only correct when a signal
## fired is a gauge that is wrong after a load.
func _refresh_business_readout() -> void:
	_hud.set_bag(Clippings.bag_kilograms(), Clippings.bag_capacity())

	var job := GameSession.current_job()
	if job != null:
		_hud.set_term_states(_terms_met_so_far(job))

	if gameplay_host != null and gameplay_host.has_method(&"autonomous_status_text"):
		_hud.set_autonomous_status(String(
			gameplay_host.call(&"autonomous_status_text")))


## WHICH TERMS ARE ALREADY SATISFIED, scored against the SAME measurements the
## completion pathway will use - so a line that says "done" on the card is a
## line that will still say done on the results sheet.
##
## The two that can only be known at the end (the service window, which has not
## run out yet, and the dry tank, which has not happened yet) are shown as met
## while they still are, which is what a checklist is for.
func _terms_met_so_far(job: ACAJob) -> int:
	var elapsed := GameSession.job_elapsed_seconds() \
		* maxf(WorldClock.game_minutes_per_real_second, 0.001)
	var scored := ACAContractTerms.score(job, {
		"completion": _hud.progress(),
		"collected_kg": Clippings.delivered_this_job(),
		"elapsed_minutes": elapsed,
		"ran_dry": gameplay_host != null \
			and gameplay_host.get(&"_ran_dry") == true,
	})
	return int(scored["met"])


# ==================================================================== minimap
##
## THE MAP IS FED FROM THE PROPERTY, ONCE. Everything static about it - the
## playable rectangle, the lawn, the pond outline, the obstacles, the cut mask -
## is handed over at the start of the contract and never rebuilt, because none
## of it changes while the player mows. The only per-frame call is where the
## machine is.
##
## Every one of those is the AUTHORITATIVE object: the boundary's own rectangle,
## the shoreline the pond's collision ring was traced from, the obstacle list
## the exclusion queries read, and the lawn's own cut mask texture. The map
## cannot be wrong about the property without the game being wrong about it too.

## CHILDREN ARE READY BEFORE THEIR PARENT, and that is why this is retried from
## `_process` rather than done once in `_ready()`.
##
## This UI stack is a child of the mowing scene, so `_ready()` here runs BEFORE
## the mowing scene's own `_ready()` - which means before its `@onready` node
## references are assigned and long before it has generated a property. Asking
## for the property at that moment gets null back, and the first attempt at this
## responded by hiding the map, permanently. The screenshot showed an empty
## corner and no error anywhere, which is exactly the kind of bug that survives
## a green test suite.
##
## So the map binds on the first frame the property is actually there, and the
## check costs one boolean per frame afterwards.
func _bind_minimap() -> void:
	if _minimap == null:
		return
	var property := _property()
	if property == null or not property.is_built():
		_minimap.visible = false
		return
	_minimap_bound = true
	_minimap.visible = true
	_minimap.set_property_rect(property.playable_rect())

	var lawn := property.lawn()
	if lawn != null:
		var centre := lawn.lawn_centre()
		var half := lawn.lawn_half_extent()
		_minimap.set_lawn_rect(Rect2(centre.x - half, centre.z - half,
			half * 2.0, half * 2.0))
		_minimap.set_cut_mask(lawn.cut_mask(),
			Vector2(centre.x, centre.z), half * 2.0)

	var features := property.features()
	if features != null:
		for feature in features.features():
			if feature is ACAPondFeature:
				_minimap.set_pond(
					(feature as ACAPondFeature).shoreline_points(property.terrain()))
			elif feature is ACALawnObstacles:
				_minimap.set_obstacles((feature as ACALawnObstacles).obstacles())
			elif feature is ACAConservationZone:
				# THE GROUND THE CONTRACT SAYS NOT TO CUT. Asked for through the
				# same feature interface as the pond and the rocks - the minimap
				# does not know what a conservation zone is either.
				_minimap.set_protected_zones(
					(feature as ACAConservationZone).zones())

	var job := GameSession.current_job()
	_minimap.set_caption(job.job_site if job != null else "Property")


func _track_mower_on_minimap(progress: float) -> void:
	if _minimap == null or not _minimap.visible:
		return
	var mower := _mower()
	if mower == null:
		return
	var at := mower.global_position
	_minimap.set_mower(Vector2(at.x, at.z), mower.global_rotation.y)
	_minimap.set_progress(progress)


func _property() -> ACAProperty:
	if gameplay_host == null or not gameplay_host.has_method(&"property"):
		return null
	return gameplay_host.call(&"property")


func _mower() -> Node3D:
	if gameplay_host == null:
		return null
	var mower := gameplay_host.get(&"current_mower") as Node3D
	return mower if mower != null and is_instance_valid(mower) else null


# ====================================================================== intro

func _play_intro() -> void:
	var job := GameSession.current_job()
	if job == null:
		return
	_intro.set_contract_type(_contract_type_line(job))
	_intro.set_site_notes(_site_sentence())
	# WHAT THE CUSTOMER ASKED FOR, and WHAT IS ON THE TRAILER. Both were decided
	# in town, and this is the last screen before the machine is unloaded - so
	# this is the place a player finds out that the contract they took collects
	# and the machine they brought does not.
	_intro.set_requirements(ACAContractTerms.describe(job))
	_intro.set_equipment_line(_equipment_line(job))
	_intro.show_job(
		job.job_site,
		job.lawn_size_name(),
		job.base_pay,
		int(round(JobManager.estimated_time_minutes(job))))
	_intro.set_status("Preparing equipment...")
	_dismiss_intro_after(intro_seconds)


## The line above the site name. A property the business has cut before says so:
## that is the whole point of a recurring customer, and the player should know
## it before they arrive rather than recognising the garden and wondering.
func _contract_type_line(job: ACAJob) -> String:
	# WHAT KIND OF WORK IT IS. A rescue contract says so first: it is a
	# different job from a cut, it pays a premium for being one, and the player
	# should meet the lawn already knowing why it looks like that.
	var label := ACAPropertyCondition.contract_label(
		Business.condition_stage_for(job))
	var kind := label if not label.is_empty() \
		else "%s Contract" % job.property_type_name()
	# ...and WHICH MARKET it is in, once the business works more than one.
	var region := ACAServiceTerritory.region_for_job(job)
	if Territory.has_expanded():
		kind = "%s - %s" % [kind, ACAServiceTerritory.region_name(region)]

	var visits := Business.services_for(job)
	if visits <= 0:
		return kind
	if visits == 1:
		return "%s - repeat customer" % kind
	return "%s - %d previous visits" % [kind, visits]


## What the business brought, and whether it suits. Never a refusal - the player
## may take any machine they own anywhere - but a collection contract worked
## with a mulching machine is worth one sentence before the ramp comes down.
func _equipment_line(job: ACAJob) -> String:
	var mower_id := String(Equipment.selected_mower())
	var machine := ACAMowerUpgrades.mower_name(mower_id)
	var escort := ""
	if Equipment.escort_unit_uid() != 0:
		escort = ", with the %s" % Equipment.unit_label(Equipment.escort_unit_uid())
	# WHAT IS BOLTED ON, and how the machine is set up. Both were decided at the
	# service lot and both change what happens on this lawn, so this is the last
	# place to notice a mismatch before the ramp comes down.
	var mode := ACAMowingMode.mode_name(Equipment.mowing_mode()).to_lower()
	var fitted := PackedStringArray()
	for id in Equipment.fitted_attachments():
		fitted.append(ACAAttachments.display_name(id).to_lower())
	var kit := "" if fitted.is_empty() else ", %s" % ", ".join(fitted)

	var advice := ACAMowingMode.advice_for(Equipment.mowing_mode(), job)
	if not advice.is_empty():
		return "On the trailer: %s%s%s, set to %s. %s" % [
			machine, escort, kit, mode, advice]
	return "On the trailer: %s%s%s, set to %s." % [machine, escort, kit, mode]


## One plain sentence about what is on the ground, read off the GENERATED
## property. Empty while the property is still building, which is the honest
## answer - the intro is up during exactly that window, so the line appears when
## there is something true to put in it.
func _site_sentence() -> String:
	var property := _property()
	if property == null or not property.is_built():
		return ""
	var features := property.features()
	if features == null:
		return ""
	var pond := false
	var obstacles := 0
	var conservation: ACAConservationZone = null
	for feature in features.features():
		if feature is ACAPondFeature:
			pond = true
		elif feature is ACALawnObstacles:
			obstacles = (feature as ACALawnObstacles).count()
		elif feature is ACAConservationZone:
			conservation = feature as ACAConservationZone
	var parts := PackedStringArray()
	if pond:
		parts.append("a pond")
	if obstacles == 1:
		parts.append("one obstacle to mow around")
	elif obstacles > 1:
		parts.append("%d obstacles to mow around" % obstacles)

	var sentence := "Open ground, nothing in the way." if parts.is_empty() \
		else "On site: %s." % " and ".join(parts)

	# PROTECTED PLANTING GETS ITS OWN SENTENCE, and it goes last so it is the
	# thing the player is still reading when the card comes down. It is the one
	# site note that is an instruction rather than a description.
	if conservation != null and conservation.count() > 0:
		sentence += "  %s" % conservation.description()

	# ...and what the ground is doing, which decides how heavy the work is.
	var ground := ACAGroundConditions.current(property.params().dryness)
	sentence += "  %s" % ACAGroundConditions.summary_line(ground)
	return sentence


## How long before the card says it can be skipped. Not how long before it CAN
## be: that is immediately. The mowing scene builds its property inside its own
## `_ready()`, so by the first frame the player sees there is a lawn to drive
## on - the pause is a briefing, not a loading screen.
const INTRO_READY_DELAY := 0.5


func _dismiss_intro_after(seconds: float) -> void:
	await get_tree().create_timer(INTRO_READY_DELAY, false).timeout
	if is_instance_valid(self) and _intro.is_open():
		_intro.set_status("Ready - press any key")
	await get_tree().create_timer(maxf(seconds - INTRO_READY_DELAY, 0.0),
		false).timeout
	if not is_instance_valid(self) or not _intro.is_open():
		return
	_intro.set_status("Ready")
	_intro.hide_intro()


## THE CONTRACT CARD IS A BRIEFING, NOT A CUTSCENE.
##
## It comes down on its own after `intro_seconds`, and it comes down the moment
## the player does anything that says they have read it - which on a screen
## whose entire purpose is driving is usually the throttle. Nothing is skipped
## by skipping it: every term on the card is on the HUD and on the results
## sheet, and the property is already standing.
##
## ESCAPE and H are deliberately let through. The pause stack and the developer
## debugger have to behave identically whether or not the card is up, and a
## player reaching for pause is not asking to start mowing.
func _unhandled_input(event: InputEvent) -> void:
	if _intro == null or not _intro.is_open():
		return
	var key := event as InputEventKey
	if key != null:
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ESCAPE or key.keycode == KEY_H:
			return
	else:
		var click := event as InputEventMouseButton
		if click == null or not click.pressed:
			return
	_intro.set_status("Ready")
	_intro.hide_intro()
	get_viewport().set_input_as_handled()


# ======================================================================== HUD

func _wire_hud() -> void:
	_hud.pause_requested.connect(open_pause)
	# TWO fuel messages and no more. The HUD raises `low_fuel_entered` once per
	# crossing of its threshold, and MowerFuel raises `emptied` once per
	# transition into empty, so neither can repeat while the level sits still.
	_hud.low_fuel_entered.connect(func() -> void:
		# Already dry: "Out of fuel" is about to say something stronger, and two
		# stacked fuel toasts is exactly the spam this is meant to avoid. In
		# normal play the tank crosses 20% minutes before it empties.
		if not _fuel_matters() or MowerFuel.is_empty():
			return
		AppUI.notify_warning("Fuel low", "Finish up or head back to refuel."))
	MowerFuel.emptied.connect(_on_fuel_emptied)


## Whether a fuel message makes sense right now. It does not for a manual mower
## (the Push Mower burns nothing), and it does not while the development Auto
## Refuel helper is on, because the tank is about to fill itself.
func _fuel_matters() -> bool:
	if MowerFuel.auto_refuel():
		return false
	if gameplay_host != null and gameplay_host.has_method("current_mower_is_powered"):
		return bool(gameplay_host.call(&"current_mower_is_powered"))
	return true


func _on_fuel_emptied() -> void:
	if _finished or not _fuel_matters():
		return
	AppUI.notify_warning("Out of fuel", "The engine has cut out. Refuel to keep mowing.")


func _restart_job() -> void:
	if gameplay_host == null:
		return
	gameplay_host.call(&"restart_current_job")
	_finished = false
	_hud.set_progress_immediate(0.0)


# ==================================================================== results

func _wire_results() -> void:
	_results.return_to_town_requested.connect(_on_return_to_town)
	_results.next_stop_requested.connect(_on_next_stop)


## STRAIGHT ON TO THE NEXT CONTRACT, without returning to the yard. Everything
## that persists between stops - the tank, the catcher, the trailer's load, the
## loadout - carries over, because none of it is reset by anything except a
## visit to a service lot.
func _on_next_stop() -> void:
	AppUI.release_mouse(AppUI.MOUSE_HOLD_RESULTS)
	_results.hide_results()
	if not GameSession.go_to_next_stop():
		GameSession.go_to_town()


## GameSession has already completed the job and paid out; this is presentation.
func _on_job_settled(summary: Dictionary) -> void:
	_finished = true
	# The results screen owns the screen from here. Anything still up from the
	# pause stack would otherwise draw on top of it.
	close_pause_stack()
	set_escape_pause_enabled(false)
	get_tree().paused = false
	# The results screen has a button on it, and the mowing screen's cursor
	# context is CAPTURED. Hold it visible until the player leaves.
	AppUI.hold_mouse(AppUI.MOUSE_HOLD_RESULTS)
	_hud.set_progress_immediate(summary.get("completion", 1.0))
	_hud.hide_hud()
	if _minimap != null:
		var fade := create_tween()
		fade.tween_property(_minimap, "modulate:a", 0.0, UITheme.FADE)
	if _intro.is_open():
		_intro.hide_intro()
	_results.show_results(
		String(summary.get("job_name", "")),
		float(summary.get("completion", 1.0)),
		float(summary.get("elapsed_seconds", 0.0)),
		int(summary.get("base_pay", 0)),
		int(summary.get("bonus", 0)))
	# Everything the contract MEASURED, on the same sheet. Additive: the five
	# figures above are the card the results screen has always shown.
	_results.show_details(summary)

	# THE DAY'S NEXT STOP, when there is one. `GameSession` decides whether
	# there is; this only prints the offer.
	var next := StringName(String(summary.get("next_stop", "")))
	var next_job := JobManager.get_job(next) if not String(next).is_empty() else null
	_results.show_next_stop(next_job.job_site if next_job != null else "")


func _on_return_to_town() -> void:
	_results.hide_results()
	GameSession.go_to_town()
