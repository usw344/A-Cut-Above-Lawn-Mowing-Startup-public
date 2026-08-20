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
@onready var _intro: JobIntroScreen = $"Job Intro"
@onready var _results: JobCompleteScreen = $"Job Complete"

## Set while the results screen is up, so the HUD stops fighting it for updates.
var _finished: bool = false


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
	_hud.show_hud()
	_play_intro()


## The mowing bindings, not the town's.
func control_bindings() -> PackedStringArray:
	return ACAControlBindings.MOWING


func _process(_delta: float) -> void:
	if _finished or gameplay_host == null:
		return
	_hud.set_progress(gameplay_host.call(&"mowing_progress"))
	_hud.set_fuel(gameplay_host.call(&"mower_fuel_fraction"))
	_refresh_environment()


# =================================================================== contract

func _populate_from_job() -> void:
	var job := GameSession.current_job()
	if job == null:
		_hud.set_job_name("Practice Lawn")
		_hud.set_job_size("")
		_hud.set_reward(0)
		return
	_hud.set_job_name(job.job_site)
	_hud.set_job_size(job.lawn_size_name())
	_hud.set_reward(job.base_pay)
	_hud.set_status("Mowing")


func _refresh_environment() -> void:
	_hud.set_game_time(WorldClock.clock_text())
	_hud.set_weather(WorldClock.weather_preset())


# ====================================================================== intro

func _play_intro() -> void:
	var job := GameSession.current_job()
	if job == null:
		return
	_intro.set_contract_type("%s Contract" % job.property_type_name())
	_intro.show_job(
		job.job_site,
		job.lawn_size_name(),
		job.base_pay,
		int(round(JobManager.estimated_time_minutes(job))))
	_intro.set_status("Preparing equipment...")
	_dismiss_intro_after(intro_seconds)


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
