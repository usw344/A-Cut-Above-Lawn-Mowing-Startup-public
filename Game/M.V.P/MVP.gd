extends Node3D
## ROLE
## The mowing runtime. It reads the accepted contract, builds the property for
## it, puts a machine on it, reports progress, and hands completion to
## GameSession. It owns no grass, no terrain and no mowing state; ACAProperty
## owns those and this scene composes them.
##
## PUBLIC API
##   property() -> ACAProperty          the generated property
##   lawn() -> ACALawn                  the mowing state, for saves and tooling
##   mowing_progress() -> float
##   mower_fuel_fraction() / current_mower_is_powered()
##   restart_current_job()
##   dev_* helpers, development only
##
## SIGNALS: None of its own.
##
## PERSISTENCE OWNERSHIP
##   None. SaveService asks `property()` and `lawn()` for their own blocks.


## THE property. Generated in _ready() from the accepted contract.
@onready var property_node: ACAProperty = $Property
@onready var sound:AudioStreamPlayer = $AudioStreamPlayer
@onready var current_mower:CharacterBody3D = $"Rider Mower"

# define scenes of the mower

var rider_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn")
var powered_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn")
var push_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Push Mower.tscn")

var mowers_scene_list = {"push":push_mower_scene,
"powered":powered_mower_scene,"rider":rider_mower_scene}

var original_mower_transform = null # for reset use

## The join between the machine and the lawn. Created here, bound to whichever
## mower is current, and re-bound when the player switches machines.
var cutter: ACAMowerCutter = null

## PRESENTATION ONLY. Clippings thrown by the deck, and the pollen and insects
## in the air. Neither has any effect on the cut, the contract or the save;
## both follow the machine and are re-bound with it.
var effects: ACAMowingEffects = null
var ambient: ACAAmbientLife = null


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
	# A resumed save carries the property it was saved on. Taking the handoff
	# BEFORE the property is generated is what lets a reload rebuild the same
	# address rather than a new one that happens to share a seed.
	_take_pending_state()

	# THE PROPERTY IS BUILT AT THE ORIGIN. The old lawn was authored five hundred
	# units below it, which is why the weather system had to be told where the
	# ground was by hand; a generated property has no reason to be anywhere else.
	property_node.build(_property_params_for_this_visit())
	_report_property()

	sound.play() # start background ambience sound

	# The machine arrives at the property rather than being dropped on to it.
	_place_mower(property_node.mower_start_transform())
	original_mower_transform = current_mower.transform

	cutter = ACAMowerCutter.new()
	cutter.name = "Mower Cutter"
	add_child(cutter)

	effects = ACAMowingEffects.new()
	effects.name = "Mowing Effects"
	add_child(effects)
	ambient = ACAAmbientLife.new()
	ambient.name = "Ambient Life"
	add_child(ambient)

	_bind_mower_to_lawn()
	_bind_ambient_life()

	## to manage sound effect of rain and stuff
	preset_manager_object.set_audio_player(sound)
	# Rain follows the LENS, not the machine: the drops the player sees are the
	# ones near the camera. Every canonical mower carries its own Camera3D.
	_track_weather_to_camera()
	
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


## Point the weather system's precipitation at the active mower's camera.
## Falls back to the mower body if a mower ever ships without one.
func _track_weather_to_camera() -> void:
	if preset_manager_object == null or current_mower == null:
		return
	var cam := current_mower.get_node_or_null(^"Camera3D") as Node3D
	preset_manager_object.set_weather_tracking_target(
		cam if cam != null else current_mower)

	# Height fog is measured from an ABSOLUTE world Y. It comes from the terrain
	# itself now - the height at the middle of the lawn - rather than from a
	# stand-in plane, so it stays right on ground that is no longer flat.
	if property_node != null and property_node.is_built():
		var centre := property_node.lawn().lawn_centre()
		preset_manager_object.set_weather_ground_reference(
			property_node.ground_height_at(centre.x, centre.z))


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
	# Each machine has its own deck, so switching mowers re-resolves the cut
	# footprint rather than carrying the previous one over.
	_bind_mower_to_lawn()
	_bind_ambient_life()
	_track_weather_to_camera()
	AppUI.set_mouse_context(current_mouse_context)


## RESTART JOB. The property is NOT regenerated: the player asked to start the
## contract again, not to be sent to a different address. Only the cut state is
## put back, which is also why this is now instant instead of a rebuild.
func _on_mvp_hud_reset_map_and_location() -> void:
	property_node.lawn().reset()
	_place_mower(property_node.mower_start_transform())
	if cutter != null:
		cutter.resync()

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

## How often progress is pushed into the Job System, in seconds. The lawn emits
## on every cut; the manager does not need that resolution.
const PROGRESS_REPORT_INTERVAL := 0.5

var _active_job: ACAJob = null
var _job_finished: bool = false
var _progress_report_accumulator: float = 0.0
var _last_reported_progress: float = -1.0

## The save handoff, taken once in _ready() because the property has to be
## generated from it before anything else can be restored on to it.
var _pending_mowing: Dictionary = {}


func _has_session() -> bool:
	return get_node_or_null(^"/root/GameSession") != null


## ONE-SHOT. Anything left here after _ready() is for the current contract.
func _take_pending_state() -> void:
	_pending_mowing = {}
	var save_service := get_node_or_null(^"/root/SaveService")
	if save_service == null:
		return
	var state: Dictionary = save_service.call(&"take_pending_mowing_state")
	if state.is_empty():
		return
	var job: ACAJob = GameSession.current_job() if _has_session() else null
	if job == null or String(state.get("job_id", "")) != String(job.id):
		push_warning("[MOWING] Saved mowing state is for a different contract; ignoring.")
		return
	_pending_mowing = state


## The property to build. A resumed contract rebuilds the SAVED property, so a
## later change to how a seed is turned into a property cannot move the player
## to a different address mid-job. A fresh contract derives its property from
## the contract's own seed.
func _property_params_for_this_visit() -> ACAPropertyParams:
	var saved: Variant = _pending_mowing.get("property", null)
	if saved is Dictionary:
		return ACAPropertyParams.from_dictionary(saved as Dictionary)
	return ACAPropertyParams.for_job(
		GameSession.current_job() if _has_session() else null)


## THE property this scene is standing on.
func property() -> ACAProperty:
	return property_node


## THE mowing state. SaveService and the trailer's lawn adapter ask for this
## rather than reaching for a node by name.
func lawn() -> ACALawn:
	return property_node.lawn() if property_node != null else null


func _report_property() -> void:
	var stats := property_node.statistics()
	var params := property_node.params()
	print("[MOWING] Property seed %d | lawn %d | forestiness %.2f | pond %s"
		% [params.seed, params.lawn_size, params.forestiness, params.pond_enabled])
	print("[MOWING] built in %.0f ms | %d mowable cells of %d | %d grass, %d foliage instances"
		% [stats["total_ms"], stats["lawn_mowable"], stats["lawn_cells"],
			stats["grass"]["instances"], stats["foliage"]["instances"]])


## Put the machine somewhere without disturbing the scale it was authored at.
func _place_mower(where: Transform3D) -> void:
	if current_mower == null:
		return
	var scale := current_mower.transform.basis.get_scale()
	current_mower.global_transform = Transform3D(
		where.basis.scaled(scale), where.origin)


## Hand the current machine to the cutter, and route its blade signal there.
##
## `collided` fires every physics frame while the engine is running and stops
## when the tank is empty. That contract is unchanged from the old lawn, which
## is why no mower controller had to be told the grass moved.
func _bind_mower_to_lawn() -> void:
	if cutter == null or current_mower == null or property_node == null:
		return
	cutter.bind(current_mower, property_node.lawn())
	if not current_mower.collided.is_connected(cutter.on_blades_active):
		current_mower.collided.connect(cutter.on_blades_active)

	# The clippings ride the SAME signal the cut does, which is what guarantees
	# they can never appear over ground that was already mown: `cut` is emitted
	# only when a sweep turned uncut cells into cut ones.
	if effects != null:
		effects.bind(current_mower, cutter, property_node.params())
		if not cutter.cut.is_connected(effects.on_cut):
			cutter.cut.connect(effects.on_cut)


## Pollen and insects follow the LENS, like the rain does, because what matters
## is the air the player is looking through rather than the air around the
## machine. They are switched off in rain: the sky already has something in it.
func _bind_ambient_life() -> void:
	if ambient == null or current_mower == null:
		return
	var cam := current_mower.get_node_or_null(^"Camera3D") as Node3D
	ambient.follow(cam if cam != null else current_mower)
	ambient.set_density(_ambient_density())
	ambient.set_enabled(WorldClock.weather_preset() != "Rain")


## The player's graphics setting decides how much of it there is. Low turns it
## off; see `ACAAmbientLife.set_density()`.
func _ambient_density() -> float:
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings == null or not settings.has_method(&"graphics_quality"):
		return 1.0
	match String(settings.call(&"graphics_quality")):
		"low":
			return 0.0
		"medium":
			return 0.6
		_:
			return 1.0


func _setup_job_runtime() -> void:
	_active_job = GameSession.current_job() if _has_session() else null

	# World state first, so the sky is already correct on the first frame.
	_apply_world_state()
	WorldClock.weather_changed.connect(_on_world_weather_changed)

	property_node.lawn().mowing_progress_changed.connect(_on_mowing_progress_changed)

	if _active_job == null:
		print("[MOWING] No active contract - running as a standalone mowing bench.")
		return

	print("[MOWING] Contract %s | %s | %s | lawn %dx%d | $%d" % [
		_active_job.id, _active_job.job_site, _active_job.lawn_size_name(),
		_active_job.grid_size.x, _active_job.grid_size.y, _active_job.base_pay,
	])

	# A job resumed from a save arrives with progress already on it.
	_last_reported_progress = _active_job.progress

	_restore_saved_mowing_state()


## If this scene was entered by loading a save, put the lawn and the mower back
## the way they were. The handoff is one-shot, so simply re-entering the same
## contract later never re-applies stale state.
##
## Two formats are accepted. The current one is a compact cut mask; the older
## one is the per-blade list the previous lawn wrote, which is translated by
## `ACALawn.apply_legacy_mowed_items()` rather than discarded.
func _restore_saved_mowing_state() -> void:
	var state := _pending_mowing
	if state.is_empty():
		return

	var this_lawn := property_node.lawn()
	var cut_state: Variant = state.get("cut_state", null)
	if cut_state is Dictionary:
		if this_lawn.restore_cut_state(cut_state as Dictionary):
			print("[MOWING] Restored cut state, lawn is %.1f%% mown."
				% (this_lawn.mowed_fraction() * 100.0))
	else:
		var names := PackedStringArray(state.get("mowed_items", []))
		if names.size() > 0:
			var legacy_size := int(state.get("grid_size", _active_job.grid_size.x))
			var applied := this_lawn.apply_legacy_mowed_items(names, legacy_size)
			print("[MOWING] Migrated %d legacy cut records into %d cells (%.1f%%)."
				% [names.size(), applied, this_lawn.mowed_fraction() * 100.0])

	var pos: Array = state.get("mower_position", [])
	var rot: Array = state.get("mower_rotation", [])
	if pos.size() == 3:
		_restore_mower_position(Vector3(pos[0], pos[1], pos[2]),
			Vector3(rot[0], rot[1], rot[2]) if rot.size() == 3 else Vector3.ZERO)
	elif rot.size() == 3:
		current_mower.rotation = Vector3(rot[0], rot[1], rot[2])
	if cutter != null:
		cutter.resync()

	_last_reported_progress = this_lawn.mowed_fraction()


## A SAVED POSITION IS NOT ALWAYS A POSITION.
##
## The property now has a fence round it, and a machine put down outside that
## fence cannot get back in. Two saves can do exactly that:
##
##   * A LEGACY save. The lawn this game used to have was authored about five
##     hundred units from the origin; a generated property is built AT it. A
##     mid-contract save from that era carries a coordinate from a world that no
##     longer exists, and restoring it faithfully lands the machine four hundred
##     units out in the scenery with a fence between it and the contract. The
##     Legacy Save Test found precisely this.
##   * A CURRENT save taken with the machine pressed against the fence, where
##     float error either way could put the restored transform a hair outside it.
##
## So a restored position is checked against the property it is being restored
## on to. A small overshoot is pulled back inside; anything further out is not a
## position at all, and the machine arrives the way it would for a fresh
## contract instead. The CUT STATE is untouched by any of this - the player keeps
## every square unit of progress either way.

## How far outside the boundary a restored position is quietly pulled back in,
## in world units, before it is treated as belonging to a different world.
const RESTORE_NUDGE_LIMIT := 12.0
## ...and how far inside the fence it is put when it is pulled back.
const RESTORE_INSET := 3.0


func _restore_mower_position(saved: Vector3, saved_rotation: Vector3) -> void:
	var boundary := property_node.boundary() if property_node != null else null
	var outside: float = boundary.distance_outside(saved.x, saved.z) 		if boundary != null else 0.0

	if outside > RESTORE_NUDGE_LIMIT:
		var start := property_node.mower_start_transform()
		_place_mower(start)
		push_warning("[MOWING] The saved machine position is %.0f units outside "
			% outside
			+ "this property; it belongs to an older world. Arriving at the "
			+ "property instead. The cut state is unaffected.")
		return

	var at := saved
	if outside > 0.0 and boundary != null:
		# Pull it back to just inside the fence, keeping the direction it was in.
		var centre := boundary.centre()
		var half: float = boundary.half_extent() - RESTORE_INSET
		at.x = clampf(at.x, centre.x - half, centre.x + half)
		at.z = clampf(at.z, centre.z - half, centre.z + half)
		at.y = property_node.ground_height_at(at.x, at.z) + ACAProperty.ARRIVAL_CLEARANCE
	current_mower.global_position = at
	current_mower.rotation = saved_rotation


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
	if ambient != null:
		ambient.set_enabled(preset != "Rain")


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

	var fraction := property_node.lawn().mowed_fraction()
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
	return property_node.lawn().mowed_fraction()


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
