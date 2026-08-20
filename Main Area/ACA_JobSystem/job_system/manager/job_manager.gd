class_name ACAJobManager
extends Node
## THE authoritative owner of every job in the game.
##
## available_jobs / current_jobs / past_jobs live here and nowhere else. The UI
## reads from this manager and keeps no database of its own; gameplay reports
## into it through the public API below. There is no job state in job nodes, in
## global dictionaries, or in accepted-job subclasses - that duplication is
## exactly what this design replaces.
##
##     World state (time, season, economy, climate)
##             |
##             v
##         ACAJobManager        <- single source of truth
##             |
##             v
##          Job UI              <- read-only view
##
## Threading: this is business simulation, not gameplay. It runs on the main
## thread, does no physics, and has no _physics_process. The host project's
## multithreaded 3D physics is irrelevant to it - keep it that way. When
## begin_job_requested is eventually wired into the mowing scene, that boundary
## belongs on the host side, using deferred/main-thread calls as needed.

# ------------------------------------------------------------------- signals
## Collection changed - rebuild the matching tab.
signal available_jobs_changed()
signal current_jobs_changed()
signal past_jobs_changed()

## Individual lifecycle events, for sound, notifications and analytics.
signal job_generated(job: ACAJob)
signal job_expired(job: ACAJob)
signal job_accepted(job: ACAJob)
signal job_completed(job: ACAJob)

## Accept was refused - `reason` is player-facing text.
signal job_accept_failed(job_id: StringName, reason: String)

signal market_strength_changed(strength: int)

## THE GAMEPLAY HANDOFF. begin_new_job() emits this and stops. The host project
## listens and does the actual mowing-scene transition; the Job System never
## changes scenes itself.
signal begin_job_requested(job: ACAJob)

# ------------------------------------------------------------------- exports
## Evaluate the market automatically using an internal poll timer. Turn this
## off to drive the manager manually with evaluate_now() (the tests do).
@export var auto_evaluate: bool = true

## Seed for the market's own RNG: which job seeds get rolled and when offers
## arrive. 0 randomises on startup.
@export var market_seed: int = 0

## World inputs the future economy/climate systems will supply. Season comes
## from the time provider instead, because it is calendar-driven.
@export var economy: ACAJobEnums.Economy = ACAJobEnums.Economy.NORMAL:
	set = set_economy
@export var climate: ACAJobEnums.Climate = ACAJobEnums.Climate.NORMAL:
	set = set_climate

## INTEGRATION POINT - estimated mowing time.
## Optional Callable taking (job: ACAJob) and returning real minutes. Leave it
## unset and the manager uses the placeholder rate in ACAJobBalance. Set it
## once the mower system exists:
##     manager.estimated_time_provider = func(job): return mower.estimate(job)
## The manager never touches mower nodes itself.
var estimated_time_provider: Callable = Callable()

# --------------------------------------------------------------------- state
var _time: ACAJobTimeProvider = ACAJobTimeProvider.new()
var _rng := RandomNumberGenerator.new()

var _available: Array[ACAJob] = []
var _current: Array[ACAJob] = []
var _past: Array[ACAJob] = []

var _market_strength: int = 0
var _next_arrival_time: float = INF
var _last_seen_time: float = 0.0
var _timer: Timer


func _ready() -> void:
	_rng.seed = market_seed if market_seed != 0 else randi()
	_last_seen_time = _time.game_minutes()
	_market_strength = _compute_strength()
	_schedule_next_arrival(_last_seen_time)
	if auto_evaluate:
		_timer = Timer.new()
		_timer.name = "MarketTick"
		_timer.wait_time = ACAJobBalance.EVALUATION_INTERVAL_SECONDS
		_timer.autostart = true
		_timer.timeout.connect(evaluate_now)
		add_child(_timer)


# =========================================================== world boundaries

## INTEGRATION POINT - world time. Hand in the game's authoritative clock
## wrapped in an ACAJobTimeProvider subclass. Until then the manager uses a
## stopped default clock and nothing happens.
func set_time_provider(provider: ACAJobTimeProvider) -> void:
	if provider == null:
		push_warning("ACAJobManager: null time provider ignored")
		return
	_time = provider
	_last_seen_time = _time.game_minutes()
	_schedule_next_arrival(_last_seen_time)
	_refresh_market_strength()


func time_provider() -> ACAJobTimeProvider:
	return _time


func now() -> float:
	return _time.game_minutes()


func set_economy(value: ACAJobEnums.Economy) -> void:
	economy = value
	_refresh_market_strength()


func set_climate(value: ACAJobEnums.Climate) -> void:
	climate = value
	_refresh_market_strength()


# ================================================================ market view

func market_strength() -> int:
	return _market_strength


## maximum_available_jobs == market_strength. A capacity, not a quota to fill.
func max_available_jobs() -> int:
	return ACAJobMarket.capacity_for(_market_strength)


func market_summary() -> String:
	return ACAJobMarket.describe(_time.season(), economy, climate)


# =========================================================== collection views
## Copies on purpose: callers may iterate freely, but only this manager mutates
## the collections. The ACAJob objects themselves are shared references.

func available_jobs() -> Array[ACAJob]:
	return _available.duplicate()


func current_jobs() -> Array[ACAJob]:
	return _current.duplicate()


func past_jobs() -> Array[ACAJob]:
	return _past.duplicate()


func max_current_jobs() -> int:
	return ACAJobBalance.MAX_CURRENT_JOBS


func has_current_capacity() -> bool:
	return _current.size() < ACAJobBalance.MAX_CURRENT_JOBS


func get_job(job_id: StringName) -> ACAJob:
	var lists: Array = [_available, _current, _past]
	for list in lists:
		for job: ACAJob in list:
			if job.id == job_id:
				return job
	return null


# ========================================================== market evaluation

## Evaluate expiry, market strength and arrivals against the current world
## time. Called by the internal poll timer; call it directly after jumping the
## clock so the market catches up immediately.
func evaluate_now() -> void:
	var t := _time.game_minutes()
	_last_seen_time = t
	_expire_offers(t)
	_refresh_market_strength()
	_process_arrivals(t)


func _expire_offers(t: float) -> void:
	var lapsed: Array[ACAJob] = []
	for job in _available:
		if job.is_expired_at(t):
			lapsed.append(job)
	if lapsed.is_empty():
		return
	for job in lapsed:
		_available.erase(job)
		job.status = ACAJobEnums.Status.EXPIRED
		# Expired offers are NOT business history - they never reach past_jobs.
		job_expired.emit(job)
	available_jobs_changed.emit()


func _compute_strength() -> int:
	return ACAJobMarket.market_strength(_time.season(), economy, climate)


func _refresh_market_strength() -> void:
	var strength := _compute_strength()
	if strength == _market_strength:
		return
	_market_strength = strength
	# Falling demand never deletes existing offers. They expire or get accepted
	# on their own; new offers simply stop until the board falls below capacity.
	market_strength_changed.emit(_market_strength)


func _process_arrivals(t: float) -> void:
	var capacity := max_available_jobs()
	if capacity <= 0 or _available.size() >= capacity:
		# Board full or market closed: keep the next arrival relative to now so
		# no backlog builds up. Rising demand then waits a fresh interval
		# instead of dumping several offers at once.
		_schedule_next_arrival(t)
		return
	if t < _next_arrival_time:
		return
	_spawn_offer(t)
	_schedule_next_arrival(t)


func _schedule_next_arrival(t: float) -> void:
	var gap := ACAJobMarket.next_arrival_gap(max_available_jobs(), _rng)
	_next_arrival_time = INF if is_inf(gap) else t + gap


## Game minutes until the next potential offer. INF when the market is closed.
func minutes_until_next_arrival() -> float:
	if is_inf(_next_arrival_time):
		return INF
	return maxf(_next_arrival_time - _time.game_minutes(), 0.0)


func _spawn_offer(t: float) -> void:
	var job := ACAJobGenerator.generate(_rng.randi() & 0x7FFFFFFF, t)
	while get_job(job.id) != null:
		job = ACAJobGenerator.generate(_rng.randi() & 0x7FFFFFFF, t)
	job.status = ACAJobEnums.Status.AVAILABLE
	_available.append(job)
	job_generated.emit(job)
	available_jobs_changed.emit()


## Put offers on the board immediately, ignoring the arrival interval, up to
## the market's current capacity. Called once when a world starts or loads so
## the player never walks into an empty board on day one. Normal arrivals
## continue on their own interval afterwards.
func seed_initial_offers(count: int = 2) -> void:
	var t := _time.game_minutes()
	var capacity := max_available_jobs()
	var wanted: int = mini(count, capacity - _available.size())
	for _i in range(maxi(wanted, 0)):
		_spawn_offer(t)
	_schedule_next_arrival(t)


# ============================================================= player actions

## Move an offer from Available to Current. Accepting one offer must never
## disturb the others.
func accept_job(job_id: StringName) -> bool:
	var job := _find(_available, job_id)
	if job == null:
		job_accept_failed.emit(job_id, "That job offer is no longer available.")
		return false
	if job.is_expired_at(_time.game_minutes()):
		_expire_offers(_time.game_minutes())
		job_accept_failed.emit(job_id, "That offer has expired.")
		return false
	if not has_current_capacity():
		job_accept_failed.emit(job_id, _capacity_message())
		return false

	_available.erase(job)
	job.status = ACAJobEnums.Status.ACCEPTED  # offer expiry stops applying here
	job.accepted_game_time = _time.game_minutes()
	_current.append(job)

	job_accepted.emit(job)
	available_jobs_changed.emit()
	current_jobs_changed.emit()
	return true


func _capacity_message() -> String:
	if ACAJobBalance.MAX_CURRENT_JOBS == 1:
		return "Finish your current job before accepting another."
	return "You can only hold %d jobs at once." % ACAJobBalance.MAX_CURRENT_JOBS


## THE GAMEPLAY HANDOFF - deliberately boilerplate.
##
## Validates the current job, marks it IN_PROGRESS and emits
## begin_job_requested(job). It does NOT change scenes, load the mowing scene,
## build a grass grid, pick a mower, touch physics or touch the Town. The host
## project connects begin_job_requested and does all of that itself.
func begin_new_job(job_id: StringName) -> bool:
	var job := _find(_current, job_id)
	if job == null:
		push_warning("ACAJobManager.begin_new_job: no current job with id %s" % job_id)
		return false
	if job.status != ACAJobEnums.Status.IN_PROGRESS:
		job.status = ACAJobEnums.Status.IN_PROGRESS
		current_jobs_changed.emit()
	begin_job_requested.emit(job)
	return true


## INTEGRATION POINT - progress reporting. Gameplay calls this; the manager
## never inspects the mowing grid. `value` is 0.0 - 1.0.
func update_job_progress(job_id: StringName, value: float) -> bool:
	var job := _find(_current, job_id)
	if job == null:
		push_warning("ACAJobManager.update_job_progress: no current job with id %s" % job_id)
		return false
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, job.progress):
		return true
	job.progress = clamped
	current_jobs_changed.emit()
	return true


## Drop a current job WITHOUT completing it. Used by the host when the player
## abandons a contract. The job is not business history, so it never reaches
## past_jobs; it simply stops existing.
func discard_current_job(job_id: StringName) -> bool:
	var job := _find(_current, job_id)
	if job == null:
		push_warning("ACAJobManager.discard_current_job: no current job with id %s" % job_id)
		return false
	_current.erase(job)
	job.status = ACAJobEnums.Status.EXPIRED
	current_jobs_changed.emit()
	return true


## Move a current job to business history. Payment, trust, bonuses and saving
## are future systems and deliberately not done here.
func complete_job(job_id: StringName) -> bool:
	var job := _find(_current, job_id)
	if job == null:
		push_warning("ACAJobManager.complete_job: no current job with id %s" % job_id)
		return false
	_current.erase(job)
	job.status = ACAJobEnums.Status.COMPLETED
	job.progress = 1.0
	job.completed_game_time = _time.game_minutes()
	_past.append(job)

	job_completed.emit(job)
	current_jobs_changed.emit()
	past_jobs_changed.emit()
	return true


# ============================================================= estimated time

## Real minutes the job is expected to take. Uses estimated_time_provider when
## the host has supplied one, otherwise the placeholder rate in ACAJobBalance.
func estimated_time_minutes(job: ACAJob) -> float:
	if job == null:
		return 0.0
	if estimated_time_provider.is_valid():
		return float(estimated_time_provider.call(job))
	var cells := float(job.grid_size.x * job.grid_size.y)
	var minutes := cells / maxf(ACAJobBalance.PLACEHOLDER_CELLS_PER_REAL_MINUTE, 0.001)
	return maxf(minutes, ACAJobBalance.PLACEHOLDER_ESTIMATE_MIN_MINUTES)


func estimated_time_text(job: ACAJob) -> String:
	return ACAGameTime.format_estimate(estimated_time_minutes(job))


# =================================================================== helpers

func _find(list: Array[ACAJob], job_id: StringName) -> ACAJob:
	for job in list:
		if job.id == job_id:
			return job
	return null


# ================================================================ persistence
## The manager owns every job, so it also owns their serialisation. Plain
## built-in types only, so this round-trips through JSON.
##
## `_next_arrival_time` is absolute game time and is stored as null when INF
## (a closed market), because JSON has no infinity.

func save_state() -> Dictionary:
	var out := {
		"generator_version": ACAJobBalance.GENERATOR_VERSION,
		"market_strength": _market_strength,
		"economy": int(economy),
		"climate": int(climate),
		"next_arrival_time": null if is_inf(_next_arrival_time) else _next_arrival_time,
		"available": [],
		"current": [],
		"past": [],
	}
	for job in _available:
		out["available"].append(job.to_dict())
	for job in _current:
		out["current"].append(job.to_dict())
	for job in _past:
		out["past"].append(job.to_dict())
	return out


## Replace every collection from a save. Emits the collection signals so any
## bound UI rebuilds itself.
func load_state(data: Dictionary) -> void:
	_available.clear()
	_current.clear()
	_past.clear()

	_available.assign(_jobs_from(data.get("available", [])))
	_current.assign(_jobs_from(data.get("current", [])))
	_past.assign(_jobs_from(data.get("past", [])))

	economy = int(data.get("economy", ACAJobEnums.Economy.NORMAL))
	climate = int(data.get("climate", ACAJobEnums.Climate.NORMAL))
	_market_strength = _compute_strength()

	var t := _time.game_minutes()
	_last_seen_time = t
	var arrival: Variant = data.get("next_arrival_time", null)
	if arrival == null:
		_next_arrival_time = INF
	else:
		# Clamp into the future: a save loaded after the stored arrival would
		# otherwise dump an offer on the first tick.
		_next_arrival_time = maxf(float(arrival), t)

	available_jobs_changed.emit()
	current_jobs_changed.emit()
	past_jobs_changed.emit()
	market_strength_changed.emit(_market_strength)


func _jobs_from(raw: Variant) -> Array[ACAJob]:
	var out: Array[ACAJob] = []
	if not (raw is Array):
		return out
	for entry in raw:
		if entry is Dictionary:
			out.append(ACAJob.from_dict(entry))
	return out


# ============================================================== debug support
## Used by the demo and the test suite. Not part of normal gameplay flow.

## Force one offer onto the board immediately, ignoring the arrival interval.
func debug_force_offer(respect_capacity: bool = false) -> ACAJob:
	var t := _time.game_minutes()
	if respect_capacity and _available.size() >= max_available_jobs():
		return null
	_spawn_offer(t)
	return _available.back()


## Inject a job built from an explicit seed - used to verify determinism.
func debug_add_offer_with_seed(job_seed: int) -> ACAJob:
	var job := ACAJobGenerator.generate(job_seed, _time.game_minutes())
	job.status = ACAJobEnums.Status.AVAILABLE
	_available.append(job)
	job_generated.emit(job)
	available_jobs_changed.emit()
	return job


func debug_clear_all() -> void:
	_available.clear()
	_current.clear()
	_past.clear()
	available_jobs_changed.emit()
	current_jobs_changed.emit()
	past_jobs_changed.emit()
