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
var cut_audio: ACAMowerCutAudio = null
var environment_audio: ACAEnvironmentAudio = null

## THE BUSINESS'S PRESENCE ON THE PROPERTY. The truck and trailer at the arrival
## point, and the autonomous machine working a section beside the player when
## one has been deployed. Both are created here and owned by this scene: an
## escort is a decision about ONE contract, so nothing about either is saved.
var work_truck: ACAWorkTruck = null
var auto_mower: ACAAutoMower = null

## What this contract measured, for its terms and its results sheet. Every field
## is a real reading rather than an estimate - see `_job_outcome()`.
var _fuel_at_start: float = 100.0
var _ran_dry: bool = false

## ---------------------------------------------------------------------------
## THE EXPANSION'S RUNTIME STATE
## ---------------------------------------------------------------------------
## Everything here is per contract and none of it is saved: the ground condition
## is derived from the clock, the conservation record lives in `ACALawn` with
## the rest of the cut state, and the loadout belongs to `ACAEquipment`.
##
## What the ground is doing, and what the machine went out configured to do.
var _ground_state: int = ACAGroundConditions.State.DAMP
var _mowing_mode: int = ACAMowingMode.Mode.BAG
## The finish this customer asked for, derived from the contract's own seed.
var _requested_pattern: int = ACAFinishPattern.Pattern.NONE
## Whether the player has already been told they are cutting protected ground.
## ONE warning a contract: a toast every time the deck touches a meadow would be
## the game shouting at somebody who has already understood.
var _conservation_warned: bool = false
## What is bolted to the machine, as geometry.
var _attachments: ACAMowerAttachment = null
## The establishing camera, and the before-shot it took on arrival.
var _portfolio_camera: ACAPortfolioCamera = null
## Spare fuel left on the trailer's drawbar, this contract.
var _fuel_reserve: float = 0.0

## PRESENTATION ONLY. Clippings thrown by the deck, and the pollen and insects
## in the air. Neither has any effect on the cut, the contract or the save;
## both follow the machine and are re-bound with it.
var effects: ACAMowingEffects = null
var ambient: ACAAmbientLife = null


## The old MVP HUD. Kept as a development/diagnostics layer, not player UI:
## hidden on load and no longer bound to a key - the Developer Debugger (H)
## replaced it as the normal developer interface. See dev_toggle_debug_hud(),
## which the screenshot tour still drives.
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

	# WHICH MACHINE THE BUSINESS BROUGHT. The scene ships with the Rider in it,
	# which was right when the Rider was the only machine there was. The
	# business owns machines now and the player chose one before leaving town,
	# so the scene's node is replaced when it is not the one that was picked.
	_use_selected_mower()

	# The machine arrives at the property rather than being dropped on to it.
	_place_mower(property_node.mower_start_transform())
	original_mower_transform = current_mower.transform

	# The work truck, at the arrival point, before the machine drives off it.
	work_truck = ACAWorkTruck.new()
	work_truck.name = "Work Truck"
	add_child(work_truck)
	work_truck.place(property_node)
	work_truck.set_watched_mower(current_mower)

	cutter = ACAMowerCutter.new()
	cutter.name = "Mower Cutter"
	add_child(cutter)

	effects = ACAMowingEffects.new()
	effects.name = "Mowing Effects"
	add_child(effects)
	# WHAT CUTTING SOUNDS LIKE, on the same signal the clippings ride. One
	# player for the whole contract; see `ACAMowerCutAudio`.
	cut_audio = ACAMowerCutAudio.new()
	cut_audio.name = "Mower Cut Audio"
	add_child(cut_audio)
	# THE AIR. Wind, wildlife and the far half of a shower, mixed from the sky
	# the scene is already reading. It owns no weather; see `ACAEnvironmentAudio`.
	environment_audio = ACAEnvironmentAudio.new()
	environment_audio.name = "Environment Audio"
	add_child(environment_audio)
	environment_audio.bind(property_node.params() if property_node != null else null)
	ambient = ACAAmbientLife.new()
	ambient.name = "Ambient Life"
	add_child(ambient)

	_bind_mower_to_lawn()
	_bind_ambient_life()
	_read_ground_conditions()
	_fit_attachments()
	_setup_clipping_bag()
	_setup_conservation()
	_deploy_escort_unit()
	_take_spare_fuel()

	## to manage sound effect of rain and stuff
	preset_manager_object.set_audio_player(sound)
	# Rain follows the LENS, not the machine: the drops the player sees are the
	# ones near the camera. Every canonical mower carries its own Camera3D.
	_track_weather_to_camera()
	
	# Player-facing UI is the Gameplay UI stack; the MVP HUD is dev tooling.
	hud.visible = false
	
	_setup_job_runtime()
	_watch_fuel()
	# THE ARRIVAL SHOT, last of all: the property is built, the machine is on
	# it, and nothing has been cut. See `_setup_portfolio()`.
	_setup_portfolio()

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		# DEVELOPMENT ONLY - see the Dev Only Helpers section at the bottom.
		if event.keycode == KEY_F10:
			dev_complete_current_job()
			return
		# F3 used to open the legacy HUD below. The Developer Debugger (H) is
		# the normal developer interface now, so this HUD has no keyboard
		# toggle; `dev_toggle_debug_hud()` stays for the tooling that calls it.
		# DEVELOPMENT ONLY. The same two controls the old HUD offers, bound to
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

	# WHERE IN THE WORLD THIS CONTRACT IS. It scales how far the player can see
	# and nothing else; the sky itself is whatever `WorldClock` scheduled, in
	# every region, at the same moment. See `ACARegionalContext`.
	# Read from the SESSION rather than from `_active_job`, which this scene
	# does not pick up until `_setup_job_runtime()` further down `_ready()`.
	var job: ACAJob = GameSession.current_job() if _has_session() else null
	preset_manager_object.set_weather_region(
		ACAServiceTerritory.region_for_job(job) if job != null else -1)


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
	_fit_attachments()
	_setup_clipping_bag()
	_deploy_escort_unit()
	_track_weather_to_camera()
	# The truck watches for the machine coming back to unload, and it was still
	# watching the one this just replaced. Left unbound it asks a freed node for
	# its transform every frame, which is an error per frame for the rest of the
	# contract. The production path binds the truck after `_use_selected_mower()`;
	# this development switcher never did.
	if work_truck != null:
		work_truck.set_watched_mower(current_mower)
	AppUI.set_mouse_context(current_mouse_context)


## RESTART JOB. The property is NOT regenerated: the player asked to start the
## contract again, not to be sent to a different address. Only the cut state is
## put back, which is also why this is now instant instead of a rebuild.
func _on_mvp_hud_reset_map_and_location() -> void:
	property_node.lawn().reset()
	_place_mower(property_node.mower_start_transform())
	if cutter != null:
		cutter.resync()
		# The lawn is back to how it was found, so the record of how it was cut
		# goes back with it.
		cutter.reset_counters()

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

	# AND THE SOUND OF IT, off the same signal for the same reason: the machine
	# cannot sound like it is cutting over ground that is already cut.
	if cut_audio != null:
		cut_audio.bind(current_mower, cutter)
		if not cutter.cut.is_connected(cut_audio.on_cut):
			cutter.cut.connect(cut_audio.on_cut)


## Pollen and insects follow the LENS, like the rain does, because what matters
## is the air the player is looking through rather than the air around the
## machine. They are switched off in rain: the sky already has something in it.
func _bind_ambient_life() -> void:
	if ambient == null or current_mower == null:
		return
	var cam := current_mower.get_node_or_null(^"Camera3D") as Node3D
	ambient.follow(cam if cam != null else current_mower)
	ambient.set_density(_ambient_density())
	ambient.set_enabled(not ACAWorldClock.is_rain(WorldClock.weather_preset()))


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

	# WHAT FINISH THIS CUSTOMER ASKED FOR. Derived from the contract's own seed,
	# so a resumed contract asks for the same thing it asked for this morning.
	_requested_pattern = ACAFinishPattern.pattern_for(_active_job)
	if _requested_pattern != ACAFinishPattern.Pattern.NONE:
		print("[MOWING] Finish requested: %s"
			% ACAFinishPattern.pattern_name(_requested_pattern))
		if gameplay_ui != null and gameplay_ui.has_method(&"set_requested_pattern"):
			gameplay_ui.call(&"set_requested_pattern", _requested_pattern)

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
	# THE GROUND FOLLOWS THE SKY. A shower that arrives halfway through a
	# contract makes the rest of it heavier, which is the whole reason the
	# forecast is worth reading before choosing a job.
	_read_ground_conditions()
	preset_manager_object.apply_weather_preset(preset)
	if ambient != null:
		ambient.set_enabled(not ACAWorldClock.is_rain(preset))


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


## THE TANK, WATCHED RATHER THAN POLLED. `MowerFuel` already announces reaching
## empty; a contract that asks the player not to run dry is scored on whether
## that ever fired on THIS property, which is why the flag is reset per contract
## rather than read off the tank at the end.
func _watch_fuel() -> void:
	_fuel_at_start = MowerFuel.fuel()
	_ran_dry = MowerFuel.fraction() <= 0.0
	if not MowerFuel.emptied.is_connected(_on_tank_emptied):
		MowerFuel.emptied.connect(_on_tank_emptied)


func _on_tank_emptied() -> void:
	_ran_dry = true


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
	print("[MOWING] Completing contract %s (%s)" % [_active_job.id, reason])
	# WHAT ACTUALLY HAPPENED ON THIS PROPERTY, measured rather than estimated.
	# If a MANDATORY term was missed the contract is not settled and the player
	# is still on it - so `_job_finished` is only set once the settlement has
	# really been accepted.
	# The settlement publishes its summary through `GameSession.job_settled`,
	# and the portfolio files the after shot with the payout and the review on
	# it. Listening for it here rather than rebuilding it is what keeps one
	# description of what a finished contract was worth.
	if not GameSession.job_settled.is_connected(_on_job_settled_summary):
		GameSession.job_settled.connect(_on_job_settled_summary)
	if not GameSession.complete_current_job(completion,
			GameSession.job_elapsed_seconds(), _job_outcome()):
		_report_unmet_requirement()
		return
	_job_finished = true
	_on_job_settled()


## THE READINGS. Every one comes from a system that was already keeping it:
## the clipping ledger, the fuel authority and the escort. Nothing here is
## computed from the contract, because a number derived from the contract would
## be the contract marking its own homework.
func _job_outcome() -> Dictionary:
	var clippings := get_node_or_null(^"/root/Clippings")
	var this_lawn := lawn()
	# THE REQUESTED FINISH, measured off the lawn's own heading record. Nothing
	# is tracked while the player mows; the record was always being kept,
	# because it is what draws the stripes.
	var pattern := ACAFinishPattern.score(this_lawn, _requested_pattern,
		ACAAttachments.pattern_bonus(Equipment.fitted_attachments()))
	return {
		"collected_kg": float(clippings.call(&"delivered_this_job")) if clippings != null else 0.0,
		"spilled_kg": float(clippings.call(&"spilled_this_job")) if clippings != null else 0.0,
		"fuel_used": maxf(_fuel_at_start - MowerFuel.fuel(), 0.0),
		"ran_dry": _ran_dry,
		"autonomous_cells": autonomous_cells_cut(),
		"autonomous_name": auto_mower.display_name() if has_autonomous_escort() else "",
		# --- the expansion's readings, every one of them measured on the ground
		"mowing_mode": _mowing_mode,
		"mode_name": ACAMowingMode.mode_name(_mowing_mode),
		"machine_name": ACAMowerUpgrades.mower_name(_mower_id_of(current_mower)),
		"ground_state": _ground_state,
		"ground_name": ACAGroundConditions.state_name(_ground_state),
		"pattern": int(pattern["pattern"]),
		"pattern_met": bool(pattern["met"]),
		"pattern_score": float(pattern["score"]),
		"pattern_share": float(pattern["share"]),
		"pattern_note": String(pattern["note"]),
		"protected_cells": this_lawn.protected_cell_count() if this_lawn != null else 0,
		"protected_damaged": this_lawn.damaged_cell_count() if this_lawn != null else 0,
		"protected_damage": this_lawn.protected_damage_fraction() if this_lawn != null else 0.0,
		# HOW WELL IT WAS DRIVEN, measured by the cutter as it cut. Recognition
		# only: nothing here is a term of the contract and nothing here is paid.
		"coverage": cutter.coverage() if cutter != null else 0.0,
		"contacts": cutter.contacts() if cutter != null else 0,
	}


func _on_job_settled_summary(summary: Dictionary) -> void:
	_last_summary = summary.duplicate()


## A contract the customer will not sign off. Only ever a collection term, and
## only on the contracts that make it mandatory - so the message can say exactly
## what is wrong and exactly what fixes it.
func _report_unmet_requirement() -> void:
	var clippings := get_node_or_null(^"/root/Clippings")
	var in_bag: float = clippings.call(&"bag_kilograms") if clippings != null else 0.0
	if in_bag > 0.0:
		AppUI.notify_info("Contract not finished",
			"This customer wants the clippings taken away. Unload at the truck.")
	else:
		AppUI.notify_info("Contract not finished",
			"This customer wanted the clippings collected.")


## The Job Complete screen (Gameplay UI) listens to GameSession.job_settled and
## drives the return to town from its button. Nothing more to do here.
##
## Standalone fallback: with no Gameplay UI in the scene there is nothing to
## show the results, so return to town directly rather than stranding the player.
func _on_job_settled() -> void:
	# THE FINISHED SHOT, from exactly the viewpoint the arrival shot was taken
	# from. Deliberately after the settlement: a contract that was refused for a
	# missed mandatory term is not finished, and photographing it would put a
	# job the player has not done into the portfolio.
	_capture_portfolio(false)
	if gameplay_ui == null:
		GameSession.go_to_town()


func _____Business_Equipment_____():
	pass

## ---------------------------------------------------------------------------
## THE MACHINE THE BUSINESS BROUGHT
## ---------------------------------------------------------------------------
## `Equipment` owns which machines the business has and which one was chosen for
## this contract. This scene owns putting it on the property. The scene file
## still ships with the Rider parented in it, because a scene has to contain
## SOMETHING for the editor and for the standalone bench - so the rule is simply
## that if the chosen machine is not the one in the scene, the one in the scene
## is replaced.
##
## Nothing else changes. The replacement goes through the same `mowers_scene_list`
## the F3 development switcher has always used, so fuel, upgrades, the deck and
## the cutter binding all behave exactly as they do when a tester swaps machines
## by hand.
func _use_selected_mower() -> void:
	var equipment := get_node_or_null(^"/root/Equipment")
	if equipment == null or current_mower == null:
		return
	var wanted := String(equipment.call(&"selected_mower"))
	if wanted == _mower_id_of(current_mower):
		return
	var scene: PackedScene = mowers_scene_list.get(wanted)
	if scene == null:
		push_warning("[MOWING] no scene for mower '%s'; keeping the one in the scene." % wanted)
		return
	var replacement := scene.instantiate() as CharacterBody3D
	if replacement == null:
		return
	var previous := current_mower
	replacement.transform = previous.transform
	remove_child(previous)
	previous.queue_free()
	add_child(replacement)
	current_mower = replacement
	print("[MOWING] Machine for this contract: %s" % ACAMowerUpgrades.mower_name(wanted))


## Which of the three canonical machines a node is, by matching it against the
## same table the switcher uses. Asked of the NODE rather than assumed from the
## scene, so this stays right if the scene's default machine is ever changed.
func _mower_id_of(mower: Node) -> String:
	if mower == null:
		return ""
	var path := mower.scene_file_path
	for id: String in mowers_scene_list:
		var scene: PackedScene = mowers_scene_list[id]
		if scene != null and scene.resource_path == path:
			return id
	return ""


func _____Clippings_____():
	pass

## ---------------------------------------------------------------------------
## THE CATCHER
## ---------------------------------------------------------------------------
## Clippings ride the SAME signal the cut does, exactly as the cosmetic ones do.
## `ACAMowerCutter.cut` carries the number of cells that went from UNCUT to CUT,
## so driving over ground that is already mown produces nothing - which is both
## the behaviour a player expects and the only version that cannot be farmed.
##
## The ledger is `Clippings`. This scene only reports what was cut.
func _setup_clipping_bag() -> void:
	var clippings := get_node_or_null(^"/root/Clippings")
	var equipment := get_node_or_null(^"/root/Equipment")
	if clippings == null or equipment == null:
		return
	var capacity: float = equipment.call(&"bag_capacity", _mower_id_of(current_mower))
	# A RESUMED CONTRACT KEEPS WHAT IS IN THE BAG. `begin_contract` clamps the
	# restored load to the machine's capacity and leaves it alone otherwise;
	# `start_new_job` is what empties it, and only a fresh contract does that.
	if _pending_mowing.is_empty():
		clippings.call(&"start_new_job", capacity)
	else:
		clippings.call(&"begin_contract", capacity)

	if cutter != null and not cutter.cut.is_connected(_on_cells_cut):
		cutter.cut.connect(_on_cells_cut)
	if work_truck != null and not work_truck.mower_arrived.is_connected(_on_truck_reached):
		work_truck.mower_arrived.connect(_on_truck_reached)
	if not clippings.bag_filled.is_connected(_on_bag_filled):
		clippings.bag_filled.connect(_on_bag_filled)


func _on_cells_cut(cells: int) -> void:
	var clippings := get_node_or_null(^"/root/Clippings")
	if clippings != null:
		clippings.call(&"collect_from_cells", cells)


## A FULL CATCHER DOES NOT STOP THE MOWING. It stops the COLLECTING: the machine
## keeps cutting and what it cuts is left on the lawn. The contract still
## finishes; what the player loses is the collection, which is the thing a
## collection contract is scored on. One rule, and this is where it is announced.
func _on_bag_filled() -> void:
	AppUI.notify_info("Catcher full",
		"Clippings are being left on the lawn. Return to the truck to unload.")


## Back at the truck. Unloading is immediate and needs no button: the player has
## already crossed the property to get here, and a confirmation dialogue at the
## end of that is a dialogue asking them whether they meant to do the thing they
## just spent forty seconds doing.
func _on_truck_reached() -> void:
	var clippings := get_node_or_null(^"/root/Clippings")
	if clippings == null:
		return
	# THE SPARE FUEL IS AT THE TRUCK TOO. Pulling up is one visit, not two, so
	# the tank is topped up in the same stop the catcher is emptied in.
	_refuel_from_trailer()
	var moved: float = clippings.call(&"unload_to_truck")
	if moved <= 0.0:
		return
	var note := "%s on the trailer." % ACAClippings.format_kg(moved)
	if bool(clippings.call(&"trailer_is_full")):
		note += " The trailer is full - anything more is left on the lawn."
	AppUI.notify_success("Clippings unloaded", note)


func _____Ground_Conditions_____():
	pass

## ---------------------------------------------------------------------------
## WHAT THE GROUND IS DOING
## ---------------------------------------------------------------------------
## Read ONCE when the contract starts, and again whenever the sky changes. It is
## a pure function of the clock and this property's own dryness - see
## `ACAGroundConditions` - so there is no moisture value being integrated behind
## the player and nothing to save.
##
## Three things read it: the clipping ledger (wet grass is heavier), the deck's
## dust (there is none in the wet), and the HUD.
func _read_ground_conditions() -> void:
	var dryness: float = property_node.params().dryness if property_node != null else 0.24
	_ground_state = ACAGroundConditions.current(dryness)
	var clippings := get_node_or_null(^"/root/Clippings")
	if clippings != null:
		clippings.call(&"set_yield_multiplier",
			ACAGroundConditions.clipping_multiplier(_ground_state))
	if effects != null:
		effects.set_dust_scale(ACAGroundConditions.dust_multiplier(_ground_state))
	if gameplay_ui != null and gameplay_ui.has_method(&"set_ground_condition"):
		gameplay_ui.call(&"set_ground_condition", _ground_state)
	# ...AND IT IS VISIBLE. The clipping rate, the dust and the grip already
	# moved with the ground condition; until this line the lawn itself did not,
	# so a real mechanic read as an invisible one. Presentation only - see
	# `ACAGroundWetness`.
	ACAGroundWetness.apply(property_node, _ground_state)


func ground_condition() -> int:
	return _ground_state


func ground_condition_name() -> String:
	return ACAGroundConditions.state_name(_ground_state)


func _____Conservation_____():
	pass

## ---------------------------------------------------------------------------
## THE GROUND THAT IS NOT TO BE CUT
## ---------------------------------------------------------------------------
## `ACALawn` does the measuring: protected cells are swept by the deck exactly
## as lawn cells are and what they record is damage rather than progress. All
## this scene does is tell the player, once, that they have started cutting
## something they were asked to leave.
func _setup_conservation() -> void:
	var this_lawn := lawn()
	if this_lawn == null or not this_lawn.has_protected_area():
		return
	if not this_lawn.protected_damaged.is_connected(_on_protected_damaged):
		this_lawn.protected_damaged.connect(_on_protected_damaged)
	var zone := property_node.conservation()
	if zone != null:
		print("[MOWING] %d protected cells across %d zones."
			% [this_lawn.protected_cell_count(), zone.count()])
	if gameplay_ui != null and gameplay_ui.has_method(&"set_conservation_zones"):
		gameplay_ui.call(&"set_conservation_zones",
			zone.zones() if zone != null else [])


func _on_protected_damaged(_cells: int) -> void:
	if _conservation_warned:
		return
	_conservation_warned = true
	AppUI.notify_warning("That is protected planting",
		"It does not count towards the contract, and the customer will notice.")


func has_protected_ground() -> bool:
	var this_lawn := lawn()
	return this_lawn != null and this_lawn.has_protected_area()


func protected_damage_fraction() -> float:
	var this_lawn := lawn()
	return this_lawn.protected_damage_fraction() if this_lawn != null else 0.0


func _____Loadout_On_Site_____():
	pass

## ---------------------------------------------------------------------------
## WHAT THE BUSINESS BROUGHT, ON THE MACHINE
## ---------------------------------------------------------------------------
## `ACAEquipment` decided all of this at the service lot. This scene bolts the
## geometry on and reads the mode; it never chooses either.
func _fit_attachments() -> void:
	var equipment := get_node_or_null(^"/root/Equipment")
	if equipment == null or current_mower == null:
		return
	_mowing_mode = int(equipment.call(&"mowing_mode"))
	var fitted: Array = equipment.call(&"fitted_attachments")
	_attachments = ACAMowerAttachment.fit_to(current_mower, fitted)
	if effects != null:
		effects.set_mowing_mode(_mowing_mode)
	if _attachments != null and _attachments.visible_count() > 0:
		print("[MOWING] %d attachment(s) on the machine, set to %s."
			% [_attachments.visible_count(), ACAMowingMode.mode_name(_mowing_mode)])
	if gameplay_ui != null and gameplay_ui.has_method(&"set_mowing_mode"):
		gameplay_ui.call(&"set_mowing_mode", _mowing_mode)


func mowing_mode() -> int:
	return _mowing_mode


## THE JERRY CAN ON THE DRAWBAR. A bigger trailer carries spare fuel, and this
## is where it becomes something the player can feel: pulling up at the truck
## with a low tank tops it up, once, out of what is on board.
func _take_spare_fuel() -> void:
	var equipment := get_node_or_null(^"/root/Equipment")
	_fuel_reserve = float(equipment.call(&"trailer_fuel_reserve")) \
		if equipment != null else 0.0


func _refuel_from_trailer() -> void:
	if _fuel_reserve <= 0.0:
		return
	var missing := 100.0 - MowerFuel.fuel()
	# Not worth a message for a splash. A quarter of a tank is the point at
	# which topping up is a thing that happened.
	if missing < 25.0:
		return
	var poured: float = minf(missing, _fuel_reserve)
	poured = MowerFuel.refuel(poured)
	if poured <= 0.0:
		return
	_fuel_reserve -= poured
	AppUI.notify_success("Topped up from the trailer",
		"%d units in, %d left on board." % [int(round(poured)), int(round(_fuel_reserve))])


func trailer_fuel_remaining() -> float:
	return _fuel_reserve


func _____Portfolio_____():
	pass

## ---------------------------------------------------------------------------
## THE BEFORE SHOT
## ---------------------------------------------------------------------------
## One standardised photograph on arrival, taken through `ACAPortfolioCamera`'s
## own small viewport rather than off the player's screen - so the HUD is not in
## it and nothing flickers. The after shot is taken from exactly the same
## viewpoint when the contract settles.
##
## EVERY STEP IS OPTIONAL. No camera, no viewport, a headless run: the contract
## settles, the money is paid, and the portfolio simply has one fewer pair in
## it. Nothing in the completion pathway depends on any of this working.
func _setup_portfolio() -> void:
	if _active_job == null or not _has_session():
		return
	_portfolio_camera = ACAPortfolioCamera.new()
	_portfolio_camera.name = "Portfolio Camera"
	add_child(_portfolio_camera)
	_portfolio_camera.frame(property_node)
	_capture_portfolio(true)


func _capture_portfolio(before: bool) -> void:
	if _portfolio_camera == null or not is_instance_valid(_portfolio_camera):
		return
	var portfolio := get_node_or_null(^"/root/Portfolio")
	if portfolio == null or _active_job == null:
		return
	var viewport: Viewport = await _portfolio_camera.capture()
	if viewport == null:
		return
	if before:
		portfolio.call(&"capture_before", _active_job, viewport)
	else:
		portfolio.call(&"capture_after", _active_job, viewport, _last_summary)


## The completion summary, kept so the after shot can be filed with the payout
## and the review on it rather than with a second copy of either.
var _last_summary: Dictionary = {}


func _____Autonomous_Escort_____():
	pass

## ---------------------------------------------------------------------------
## THE MACHINE THAT CAME WITH THE PLAYER
## ---------------------------------------------------------------------------
## One owned autonomous unit, working a band on the far side of the property.
## It is created only when the player asked for it in town AND the unit is rated
## for the contract - a machine that cannot finish the section it is given is
## worse than no machine at all.
##
## THE ESCORT IS CLEARED WHEN THE CONTRACT STARTS. Bringing a unit is a decision
## about one job, and leaving it set would silently send it to the next one too.
func _deploy_escort_unit() -> void:
	var equipment := get_node_or_null(^"/root/Equipment")
	if equipment == null or _active_job_for_escort() == null:
		return
	var uid: int = equipment.call(&"escort_unit_uid")
	if uid == 0:
		return
	var entry: Dictionary = equipment.call(&"unit", uid)
	if entry.is_empty():
		return

	var escort := ACAAutoMower.new()
	escort.name = "Autonomous Mower"
	add_child(escort)
	if not escort.deploy(property_node, String(entry["tier"])):
		escort.queue_free()
		return
	if work_truck != null:
		escort.set_unload_point(work_truck.service_point())
	auto_mower = escort
	equipment.call(&"clear_escort_unit")
	print("[MOWING] %s deployed alongside the player." % escort.display_name())
	AppUI.notify_success("Machine deployed",
		"%s is working the far side." % escort.display_name())


## The contract, read the same way `_setup_job_runtime` reads it. Called before
## that runs, which is why it does not use `_active_job`.
func _active_job_for_escort() -> ACAJob:
	return GameSession.current_job() if _has_session() else null


## What the escort contributed, for the results sheet. Zero when none came.
func autonomous_cells_cut() -> int:
	return auto_mower.cells_cut() if auto_mower != null and is_instance_valid(auto_mower) else 0


func autonomous_status_text() -> String:
	if auto_mower == null or not is_instance_valid(auto_mower):
		return ""
	return "%s · %s" % [auto_mower.display_name(), auto_mower.status_text()]


func has_autonomous_escort() -> bool:
	return auto_mower != null and is_instance_valid(auto_mower)


## Whether the tank reached empty on THIS property. A contract that asks the
## player not to run dry is scored on the event, not on the level: refilling
## afterwards does not un-strand the machine on the customer's lawn.
func tank_ran_dry() -> bool:
	return _ran_dry


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


## The old MVP HUD is development tooling, hidden by default and with no
## keyboard toggle of its own since the Developer Debugger (H) took over. Kept
## because the screenshot tour and other tooling still call it.
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
