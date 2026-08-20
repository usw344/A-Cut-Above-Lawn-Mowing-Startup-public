extends Node3D


@onready var custom_gridmap_object:Custom_Gridmap = $"Custom Gridmap"
@onready var sound:AudioStreamPlayer = $AudioStreamPlayer
@onready var current_mower:CharacterBody3D = $"Rider Mower"

# define scenes of the mower 

var rider_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn")
var powered_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn")
var push_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Push Mower.tscn")

var mowers_scene_list = {"push":push_mower_scene, 
"powered":powered_mower_scene,"rider":rider_mower_scene} 

var original_mower_transform = null # for reset use
var custom_gridmap_scene = preload("res://Mowing Section/Mowing Area/Mowing Ground/Custom Gridmap solution/custom_gridmap.tscn") # for reset use


## The old MVP HUD. Kept as a development/diagnostics layer, not player UI:
## hidden on load, toggled with F3. See dev_toggle_debug_hud().
@onready var hud = $CanvasLayer/MVP_HUD
@onready var preset_manager_object:preset_manager = $"PresetManager (Sky3D)"
## The polished player-facing UI stack. Null when this scene is opened on its
## own from the editor, which is why every use below is guarded.
@onready var gameplay_ui: ACAGameplayUI = get_node_or_null(^"Gameplay UI")


func _physics_process(delta: float) -> void:
	# this allows the rain gpu emitter to be set correctly Here -> preset manager -> Rain handler
	preset_manager_object.get_and_set_mower_global_position(current_mower.global_position)
	_tick_job_runtime(delta)


func _ready() -> void:
	# in case this gets moved around. This current Hardcoded value works.
	custom_gridmap_object.position = Vector3(-311.935,-492.234,-140.184)
	
	# Grid size comes from the accepted contract when there is one; the old
	# hard-coded 256 stays as the standalone fallback so this scene can still be
	# opened on its own from the editor.
	custom_gridmap_object.test_custom_gridmap(_grid_size_for_current_job())
	sound.play() # start background ambience sound
	original_mower_transform = current_mower.transform
	
	## now we can move the mower around without concern. This line will snap it to the correct start position
	custom_gridmap_object.reset_start_area_global_position()
	 # add a small margin in on the y
	current_mower.global_position = custom_gridmap_object.get_mower_inital_position() + Vector3(0,2,0)

	## to manage sound effect of rain and stuff
	preset_manager_object.set_audio_player(sound)
	
	# Player-facing UI is the Gameplay UI stack; the MVP HUD is dev tooling.
	hud.visible = false
	
	_setup_job_runtime()

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		# DEVELOPMENT ONLY - see the Dev Only Helpers section at the bottom.
		if event.keycode == KEY_F10:
			dev_complete_current_job()
			return
		if event.keycode == KEY_F3:
			dev_toggle_debug_hud()
			return
		# DEVELOPMENT ONLY. The same two controls the F3 HUD offers, bound to
		# keys as well because the cursor is captured while mowing.
		if event.keycode == KEY_F7:
			dev_refuel_now()
			return
		if event.keycode == KEY_F8:
			dev_toggle_auto_refuel()
			return
		# Time of day, like weather, goes through the persistent world state.
		# Writing it to the scene only would be undone by the next world-clock
		# tick, and would not survive a transition.
		if event.keycode == KEY_1:
			dev_set_time_of_day("Morning")
		if event.keycode == KEY_2:
			dev_set_time_of_day("Day")
		if event.keycode == KEY_3:
			dev_set_time_of_day("Evening")
		if event.keycode == KEY_4:
			dev_set_time_of_day("Night")
		
		# Weather goes through the persistent world state so the choice survives
		# the next scene change instead of dying with this scene.
		if event.keycode == KEY_7:
			WorldClock.set_weather("Clear")
		if event.keycode == KEY_8:
			WorldClock.set_weather("Foggy")
		if event.keycode == KEY_9:
			WorldClock.set_weather("Rain")


func _____Debug_Functions_____():
	pass
func _on_mvp_hud_mower_change_selected(mower_id: Variant) -> void:
	var current_transform = current_mower.transform
	# The new mower's _ready() declares a CAPTURED cursor context; put back
	# whatever the screen was actually using (the dev HUD needs a free cursor).
	var current_mouse_context: int = AppUI.mouse_context()
	remove_child(current_mower)
	
	#get the new mower type
	var new_mower:CharacterBody3D = mowers_scene_list.get(mower_id).instantiate()
	new_mower.transform = current_transform
	add_child(new_mower)
	current_mower = new_mower
	current_mower.collided.connect(custom_gridmap_object.custom_grid_map_collision_handler)
	AppUI.set_mouse_context(current_mouse_context)

func _on_mvp_hud_reset_map_and_location() -> void:
	# since for MVP I moved the gridmap to its location I need to store it here
	var old_gridmap_transform = custom_gridmap_object.transform
	custom_gridmap_object.queue_free() # delete old gridmap
	
	#make a new one and add it
	custom_gridmap_object = custom_gridmap_scene.instantiate()
	add_child(custom_gridmap_object)
	
	# the test gridmap function makes the new gridmap and mowing area
	custom_gridmap_object.test_custom_gridmap(_grid_size_for_current_job())
	custom_gridmap_object.mowing_progress_changed.connect(_on_mowing_progress_changed)
	
	#now move the gridmap back to orignal place
	custom_gridmap_object.transform =old_gridmap_transform
	current_mower.transform = original_mower_transform
	current_mower.collided.connect(custom_gridmap_object.custom_grid_map_collision_handler)

# control the speed of the mower using a slider
func _on_mvp_hud_ms_slider_value_changed(value: Variant) -> void:
	# get the speed which is set in the model and used in the Mower speed
	var current_speed = model.get_speed()
	
	# calculate the current speed
	current_speed = value
	
	# set the speed back in the model
	model.set_speed(current_speed)

func _____Dev_Fuel_Controls_____():
	pass

## DEVELOPMENT fuel row on the F3 HUD. See the Dev Only Helpers section.
func _on_mvp_hud_auto_refuel_toggled(enabled: bool) -> void:
	MowerFuel.set_auto_refuel(enabled)
	print("[MOWING] dev AUTO REFUEL: %s" % MowerFuel.auto_refuel_text())


func _on_mvp_hud_refuel_requested() -> void:
	dev_refuel_now()


func _on_mvp_hud_drain_fuel_requested() -> void:
	dev_drain_fuel()


func ______Time_Functions_____():
	pass

func _on_mvp_hud_tod_day_requested() -> void:
	dev_set_time_of_day("Day")
	
func _on_mvp_hud_tod_evening_requested() -> void:
	dev_set_time_of_day("Evening")

func _on_mvp_hud_tod_night_requested() -> void:
	dev_set_time_of_day("Night")
	
# gets signal from MVP_HUD and changes time of day in Sky3d
func _on_mvp_hud_tod_slider_value_changed(value: Variant) -> void:
	WorldClock.advance_to_hour(float(value))
	

func ____Weather_Functions____():
	pass
func _on_mvp_hud_weather_clear_requested() -> void:
	WorldClock.set_weather("Clear")

func _on_mvp_hud_weather_foggy_requested() -> void:
	WorldClock.set_weather("Foggy")

func _on_mvp_hud_weather_rain_requested() -> void:
	WorldClock.set_weather("Rain")


func _____Job_Integration_____():
	pass

## ---------------------------------------------------------------------------
## JOB / WORLD INTEGRATION
##
## This scene is the mowing runtime. It reads the accepted contract from
## GameSession (which owns the application flow) and the world state from
## WorldClock, and it reports progress back into ACAJobManager. It never
## mutates job state directly and it never changes scenes itself.
##
## Standalone use still works: with no active job the fallbacks below keep the
## old MVP behaviour so the scene can be run from the editor on its own.
## ---------------------------------------------------------------------------

const FALLBACK_GRID_SIZE := 256

## How often progress is pushed into the Job System, in seconds. The grid emits
## on every cut; the manager does not need that resolution.
const PROGRESS_REPORT_INTERVAL := 0.5

var _active_job: ACAJob = null
var _job_finished: bool = false
var _progress_report_accumulator: float = 0.0
var _last_reported_progress: float = -1.0


func _grid_size_for_current_job() -> int:
	var job: ACAJob = GameSession.current_job() if _has_session() else null
	if job == null or job.grid_size.x <= 0:
		return FALLBACK_GRID_SIZE
	return job.grid_size.x


func _has_session() -> bool:
	return get_node_or_null(^"/root/GameSession") != null


func _setup_job_runtime() -> void:
	_active_job = GameSession.current_job() if _has_session() else null

	# World state first, so the sky is already correct on the first frame.
	_apply_world_state()
	WorldClock.weather_changed.connect(_on_world_weather_changed)

	custom_gridmap_object.mowing_progress_changed.connect(_on_mowing_progress_changed)

	if _active_job == null:
		print("[MOWING] No active contract - running as a standalone mowing bench.")
		return

	print("[MOWING] Contract %s | %s | %s | grid %dx%d | $%d" % [
		_active_job.id, _active_job.job_site, _active_job.lawn_size_name(),
		_active_job.grid_size.x, _active_job.grid_size.y, _active_job.base_pay,
	])

	# A job resumed from a save arrives with progress already on it.
	_last_reported_progress = _active_job.progress

	_restore_saved_mowing_state()


## If this scene was entered by loading a save, put the lawn and the mower back
## the way they were. The handoff is one-shot, so simply re-entering the same
## contract later never re-applies stale state.
func _restore_saved_mowing_state() -> void:
	var save_service := get_node_or_null(^"/root/SaveService")
	if save_service == null:
		return
	var state: Dictionary = save_service.call(&"take_pending_mowing_state")
	if state.is_empty():
		return

	if String(state.get("job_id", "")) != String(_active_job.id):
		push_warning("[MOWING] Saved mowing state is for a different contract; ignoring.")
		return

	var names := PackedStringArray(state.get("mowed_items", []))
	var applied := custom_gridmap_object.restore_mowed_items(names)
	print("[MOWING] Restored %d/%d cut items (%.1f%%)" % [
		applied, names.size(), custom_gridmap_object.mowed_fraction() * 100.0])

	var pos: Array = state.get("mower_position", [])
	if pos.size() == 3:
		current_mower.global_position = Vector3(pos[0], pos[1], pos[2])
	var rot: Array = state.get("mower_rotation", [])
	if rot.size() == 3:
		current_mower.rotation = Vector3(rot[0], rot[1], rot[2])

	_last_reported_progress = custom_gridmap_object.mowed_fraction()


## Time of day comes from the authoritative clock; weather comes from the
## persistent weather preset. Both go through the Preset Manager, which stays
## the project-facing adapter over Sky3D / Rain Handler.
func _apply_world_state() -> void:
	# Immediate, not eased: the first frame of a new scene must already look
	# right rather than fading in from whatever the last scene looked like.
	preset_manager_object.apply_world_state_immediate(
		WorldClock.weather_preset(), WorldClock.hour_of_day())


func _on_world_weather_changed(preset: String) -> void:
	preset_manager_object.apply_weather_preset(preset)


## Runs from _physics_process. Accumulates the contract stopwatch and pushes
## progress into the Job System at a coarse interval.
func _tick_job_runtime(delta: float) -> void:
	if _active_job == null or _job_finished:
		return

	GameSession.add_job_elapsed(delta)

	_progress_report_accumulator += delta
	if _progress_report_accumulator < PROGRESS_REPORT_INTERVAL:
		return
	_progress_report_accumulator = 0.0

	var fraction := custom_gridmap_object.mowed_fraction()
	if is_equal_approx(fraction, _last_reported_progress):
		return
	_last_reported_progress = fraction
	JobManager.update_job_progress(_active_job.id, fraction)


func _on_mowing_progress_changed(fraction: float) -> void:
	if _job_finished:
		return
	if fraction >= 1.0:
		_finish_job(1.0, "100% mowed")


## THE ONE completion entry point for this scene. Natural completion and the
## development helper below both come through here, and both end up in
## GameSession.complete_current_job() - the authoritative pathway.
func _finish_job(completion: float, reason: String) -> void:
	if _job_finished:
		return
	if _active_job == null:
		print("[MOWING] Completion requested (%s) but there is no active contract." % reason)
		return
	_job_finished = true
	print("[MOWING] Completing contract %s (%s)" % [_active_job.id, reason])
	GameSession.complete_current_job(completion, GameSession.job_elapsed_seconds())
	_on_job_settled()


## The Job Complete screen (Gameplay UI) listens to GameSession.job_settled and
## drives the return to town from its button. Nothing more to do here.
##
## Standalone fallback: with no Gameplay UI in the scene there is nothing to
## show the results, so return to town directly rather than stranding the player.
func _on_job_settled() -> void:
	if gameplay_ui == null:
		GameSession.go_to_town()


func _____Gameplay_UI_Interface_____():
	pass

## ---------------------------------------------------------------------------
## Read-only accessors used by the Gameplay UI. Keeping them here means the UI
## never reaches into the grid, the mower or the model itself.
## ---------------------------------------------------------------------------

## 0.0 - 1.0 of the lawn cut.
func mowing_progress() -> float:
	return custom_gridmap_object.mowed_fraction()


## 0.0 - 1.0 of the tank, straight from the fuel authority. This is the REAL
## value the powered mowers burn and the save file stores - the HUD gauge is
## never fed anything else.
func mower_fuel_fraction() -> float:
	return MowerFuel.fraction()


## Whether the mower currently in the scene runs on gasoline at all. The Push
## Mower is manual, so the fuel gauge is meaningless while it is selected.
func current_mower_is_powered() -> bool:
	if current_mower == null or not is_instance_valid(current_mower):
		return true
	if current_mower.has_method("is_powered"):
		return bool(current_mower.call(&"is_powered"))
	return true


## Put the lawn and the mower back to the start of this contract. Uses the same
## rebuild the MVP reset control has always used.
func restart_current_job() -> void:
	_on_mvp_hud_reset_map_and_location()
	if _active_job != null:
		JobManager.update_job_progress(_active_job.id, 0.0)
		_last_reported_progress = 0.0
	GameSession.set_job_elapsed(0.0)
	_job_finished = false


## The old MVP HUD is development tooling, hidden by default. F3 toggles it.
## Its controls need a usable cursor, so showing it takes a cursor hold.
func dev_toggle_debug_hud() -> void:
	hud.visible = not hud.visible
	if hud.visible:
		AppUI.hold_mouse(&"debug_hud")
	else:
		AppUI.release_mouse(&"debug_hud")


func _____Dev_Only_Helpers_____():
	pass

## ---------------------------------------------------------------------------
## DEVELOPMENT ONLY - NOT RELEASE GAMEPLAY
##
## Finishing a real 192x192 lawn means cutting ~37,000 grass instances. These
## helpers exist so the application loop can be tested without doing that.
##
## They do NOT fake completion state: they call the same _finish_job() that
## natural 100% mowing calls, which calls the same
## GameSession.complete_current_job() the whole application uses. The only
## thing skipped is the driving.
## ---------------------------------------------------------------------------

## Complete the active contract immediately through the real completion path.
func dev_complete_current_job() -> void:
	_finish_job(1.0, "dev fast-completion")


## Move the world clock to a named time of day. The clock is authoritative, so
## the choice survives the next scene change and the HUD readout agrees with the
## sky. Forward only - `advance_to_hour` never runs the clock backwards.
func dev_set_time_of_day(preset_name: String) -> void:
	var hours: Dictionary = preset_manager.TIME_PRESET_HOURS
	if not hours.has(preset_name):
		push_warning("[MOWING] unknown time preset %s" % preset_name)
		return
	WorldClock.advance_to_hour(float(hours[preset_name]))
	print("[MOWING] dev time of day -> %s (%s)" % [preset_name, WorldClock.clock_text()])


## ---------------------------------------------------------------------------
## FUEL - DEVELOPMENT CONTROLS (F7 / F8, and the F3 HUD)
##
## Real fuel rules are the default. These exist so a long automated run - the
## trailer, a soak test, a demonstration - is not stopped by an empty tank, and
## so a human tester can recover a dry mower without reloading.
##
## Auto Refuel is NOT a fuel lock. The tank still drains normally; it is topped
## up ONCE each time it actually reaches empty, so the gauge keeps moving.
## Default OFF. The production Gameplay HUD never exposes any of this.
## ---------------------------------------------------------------------------

## Fill the tank now, through the real refuel interface.
func dev_refuel_now() -> void:
	var added := MowerFuel.refuel_full()
	print("[MOWING] dev refuel: +%.0f -> %.0f%%" % [added, MowerFuel.fraction() * 100.0])
	AppUI.notify_info("Refuelled", "Tank filled (development).")


func dev_toggle_auto_refuel() -> void:
	MowerFuel.toggle_auto_refuel()
	print("[MOWING] dev AUTO REFUEL: %s" % MowerFuel.auto_refuel_text())
	AppUI.notify_info("Auto refuel", "%s (development)" % MowerFuel.auto_refuel_text())


## Empty the tank now, so zero-fuel behaviour can be seen without waiting eight
## minutes for it.
func dev_drain_fuel() -> void:
	MowerFuel.dev_drain()
	print("[MOWING] dev drained the tank -> %.0f%%" % (MowerFuel.fraction() * 100.0))


## Report an arbitrary partial progress value without cutting grass. Used to
## create a non-zero mowing state for save/resume testing.
func dev_set_reported_progress(fraction: float) -> void:
	if _active_job == null:
		return
	JobManager.update_job_progress(_active_job.id, clampf(fraction, 0.0, 1.0))
	_last_reported_progress = _active_job.progress
	print("[MOWING] dev progress set to %d%%" % _active_job.progress_percent())
