class_name ACAGameSession
extends Node
## THE application/host layer. Autoloaded as `GameSession`.
##
## Owns three things and nothing else:
##   1. Which screen the application is on, and every scene transition.
##   2. The durable session state that is not owned by another system
##      (money, whether a session is active, elapsed time on the active job).
##   3. THE ONE authoritative job-completion pathway.
##
## It deliberately does NOT own: job state (ACAJobManager does), world time or
## weather (ACAWorldClock does), the mowing grid (Custom_Gridmap does), or any
## presentation (the UI components do).
##
##     Main Menu --new_game--> Town --accept--> JobManager
##                              ^                    |
##                              |          begin_job_requested
##                       return_to_town               |
##                              |                     v
##                          Job Complete <-- Mowing (Custom_Gridmap)
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
const MOWING_SCENE := "res://Game/M.V.P/Minimum Viable Game.tscn"

const STARTING_MONEY := 250

# --------------------------------------------------------------------- state
var _screen: int = Screen.NONE
var _session_active: bool = false
var _money: int = 0
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

	# Player-facing notifications for real domain events. Deliberately few:
	# accepting work, new work arriving, and getting paid.
	JobManager.job_accepted.connect(_on_job_accepted)
	JobManager.job_generated.connect(_on_job_generated)


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
func start_new_game() -> void:
	JobManager.debug_clear_all()
	WorldClock.start_new_world()
	_set_money(STARTING_MONEY)
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


## Used by the save system when a load restores an in-progress session.
func mark_session_active(value: bool) -> void:
	_session_active = value


# ================================================================== navigation

func go_to_main_menu() -> void:
	_change_scene(MAIN_MENU_SCENE, Screen.MAIN_MENU)


func go_to_town() -> void:
	WorldClock.set_running(true)
	_change_scene(TOWN_SCENE, Screen.TOWN)


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

	screen_changed.emit(screen)
	AppUI.clear_transition_title()
	AppUI.reveal()
	_changing_scene = false


func _transition_title_for(screen: int) -> String:
	match screen:
		Screen.TOWN:
			return "RETURNING TO TOWN" if _screen == Screen.MOWING else "BUSINESS TOWN"
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


# ============================================================== the active job

## The accepted contract the player is currently working, or null. Identity is
## the ACAJob owned by ACAJobManager - this class never copies job data into a
## parallel object.
func current_job() -> ACAJob:
	var jobs := JobManager.current_jobs()
	return jobs[0] if not jobs.is_empty() else null


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
	AppUI.notify_success("Contract accepted", "%s - %s" % [job.job_site, job.pay_text()])


func _on_job_generated(job: ACAJob) -> void:
	# Only worth a toast while the player is in town and could act on it.
	if _screen != Screen.TOWN:
		return
	AppUI.notify_info("New job available", "%s - %s" % [job.job_site, job.lawn_size_name()])


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
func complete_current_job(completion: float, elapsed_seconds: float = -1.0) -> bool:
	var job := current_job()
	if job == null:
		push_warning("GameSession.complete_current_job: no active job")
		return false

	if elapsed_seconds >= 0.0:
		_job_elapsed_seconds = elapsed_seconds

	var job_id := job.id
	var job_name := job.job_site
	var job_size := job.lawn_size_name()
	var base_pay := job.base_pay
	var final_completion := clampf(completion, 0.0, 1.0)

	# The manager is the owner: it sets status, timestamps and history.
	JobManager.update_job_progress(job_id, final_completion)
	if not JobManager.complete_job(job_id):
		return false

	add_money(base_pay)
	AppUI.notify_money("Payment received", UITheme.format_money(base_pay))

	var summary := {
		"job_id": job_id,
		"job_name": job_name,
		"job_size": job_size,
		"completion": final_completion,
		"elapsed_seconds": _job_elapsed_seconds,
		"base_pay": base_pay,
		"bonus": 0,
		"total": base_pay,
	}
	job_settled.emit(summary)
	return true


## Give up on the active contract. The V1 Job System has no abandon concept, so
## this completes nothing and pays nothing - it drops the job out of Current and
## does not record it as business history.
func abandon_current_job() -> bool:
	var job := current_job()
	if job == null:
		return false
	JobManager.discard_current_job(job.id)
	_job_elapsed_seconds = 0.0
	return true


# ==================================================================== persistence

func to_save_dict() -> Dictionary:
	return {
		"money": _money,
		"screen": _screen,
		"session_active": _session_active,
		"job_elapsed_seconds": _job_elapsed_seconds,
	}


func from_save_dict(data: Dictionary) -> void:
	_set_money(int(data.get("money", STARTING_MONEY)))
	_session_active = bool(data.get("session_active", true))
	_job_elapsed_seconds = float(data.get("job_elapsed_seconds", 0.0))
	# `screen` is applied by the loader, which decides which scene to enter.
