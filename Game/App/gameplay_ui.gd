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
	_intro.set_contract_type("%s Contract" % job.property_type_name())
	_intro.set_site_notes(_site_sentence())
	_intro.show_job(
		job.job_site,
		job.lawn_size_name(),
		job.base_pay,
		int(round(JobManager.estimated_time_minutes(job))))
	_intro.set_status("Preparing equipment...")
	_dismiss_intro_after(intro_seconds)


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
	for feature in features.features():
		if feature is ACAPondFeature:
			pond = true
		elif feature is ACALawnObstacles:
			obstacles = (feature as ACALawnObstacles).count()
	var parts := PackedStringArray()
	if pond:
		parts.append("a pond")
	if obstacles == 1:
		parts.append("one obstacle to mow around")
	elif obstacles > 1:
		parts.append("%d obstacles to mow around" % obstacles)
	if parts.is_empty():
		return "Open ground, nothing in the way."
	return "On site: %s." % " and ".join(parts)


func _dismiss_intro_after(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout
	if not is_instance_valid(self) or not _intro.is_open():
		return
	_intro.set_status("Ready")
	_intro.hide_intro()


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


func _on_return_to_town() -> void:
	_results.hide_results()
	GameSession.go_to_town()
