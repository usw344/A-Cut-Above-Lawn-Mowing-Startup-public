class_name ACATrailerDirector
extends Node
## DEVELOPMENT / MEDIA TOOLING. Runs an automatic ~44 second trailer through the
## REAL game and stops on an end card. Open `Trailer Capture.tscn`, start OBS,
## press Play.
##
## NOT the application main scene and never should be. See README.md.
##
## ===========================================================================
## THE TRAILER IS A PRESENTATION SYSTEM
## ===========================================================================
##
## It is not a gameplay recording, a physics benchmark or a proof that anything
## can be driven. Trailer V2 tried to be all three and the footage suffered for
## it: every shot had to be composed around what the gameplay controller would
## actually do, and at 1.4x speed the mower could be caught mid-fall the instant
## it was repositioned.
##
## V3 splits the job in two.
##
##   REAL GAME CONTENT           -- required, and all of it is real
##     the menu and its hover state, the Business Town, `ACAJobManager`
##     generating and awarding a contract, the Job Board's own buttons, the
##     transition and Job Intro screens, the canonical rider mower and its
##     model / wheels / steering wheel / engine audio, the mowing GRID really
##     losing the grass that disappears, the weather system, the real fuel
##     system, the production HUD, and `GameSession.complete_current_job()`.
##
##   NORMAL GAMEPLAY SIMULATION  -- not required, and deliberately not used
##     the mower's transform is owned by `ACATrailerMowerAdapter` during a shot;
##     the swath it cuts is applied by `ACATrailerLawnAdapter` through the
##     grid's own api; the storm is exaggerated by `ACATrailerWeatherAdapter`;
##     the camera is a film camera on rails.
##
## Every one of those adapters restores what it touched, and `Trailer Test`
## asserts it. `model.speed` is NOT written at all any more -- shot speed
## belongs to the mower adapter, so the trailer cannot affect gameplay tuning
## even by accident.
##
## ===========================================================================
## PRESENTATION IS EXPLICIT
## ===========================================================================
## Nothing is left on screen and hoped away by a fade. Every beat that changes
## state does the same thing:
##
##     UI dismissed -> screen COVERED -> state changed -> hidden PRE-ROLL to
##     settle -> reveal
##
## `_hold_clock()` stops the storyboard clock during that hidden setup, so the
## visible running time is all footage.
##
## ===========================================================================
## CONTROLS
## ===========================================================================
##   R      restart from the top
##   SPACE  pause / resume (freezes the whole tree)
##   ESC    quit
##
## None are needed for a capture: it auto-runs and HOLDS on the end card, so OBS
## can be stopped at leisure. It never quits Godot on its own.
##
##   --trailer-shots=<dir>   review PNGs through the run
##   --trailer-quit          quit when the trailer ends, for an automated check

const TITLE := "A CUT ABOVE"
const SUBTITLE := "MOW & GROW"

## One fixed seed. Same contract, same lawn, same everything, every run.
const TRAILER_SEED := 20260819

# ------------------------------------------------------- TRAILER-ONLY TUNING
#
# NORMAL GAMEPLAY IS NOT CHANGED BY ANY OF THIS.

## Shot speeds, world units per second, owned by the mower adapter. Gameplay is
## 30 u/s (`model.speed` 10 x 3) and is neither read nor written here.
##
## THE MOWING SHOTS ARE SLOWER THAN GAMEPLAY, AND THAT IS THE POINT (M13).
## V3 ran them at 38-55 u/s so that a DISTANT camera would have something
## crossing its frame. The cost was the whole mowing section: at those speeds no
## lens can be close, so the mower was a speck in a field, and what motion you
## could see read as scurrying. Close, deliberate footage needs the opposite --
## a machine that takes four or five seconds to cross its own frame.
##
## They are still not one number, because a shot decides its own pace.
const SPEED_OVER_THE_TOP := 16.0
const SPEED_LOW_PASS := 21.0
const SPEED_CLOSE := 13.0
const SPEED_STORM := 22.0
const SPEED_PROOF := 24.0
## What the game ships, for the assertion in `Trailer Test`. Never written.
const GAMEPLAY_MOWER_SPEED := 10.0

## Hours the trailer moves the world clock to, placed against the measured sun
## curve in `weather_visual_adapter.gd`. Day one starts at 08:00, so the opening
## hour has to be after that or `advance_to_hour` (forward only) lands on day
## two.
const OPENING_HOUR := 8.2
const MOWING_HOUR := 11.6
## Late afternoon, well before the 17:05 sunset measured for this Skydome, so
## the storm reads as a storm and not as night.
const STORM_HOUR := 15.4

## Distances are in WORLD units, and this world is big -- the grass is about
## three units tall and the rider about eight units long. Camera offsets that
## look sane next to a 2 m character put the lens inside the bodywork here.
const SCALE := 2.4

## WHICH WAY IS SCREEN-LEFT ON THE LAWN.
##
## Every mowing shot drives the mower along +X (`yaw = PI * 0.5`). Its LOCAL +x
## is then world -Z, so a camera given a positive local `offset.x` sits on the
## -Z side of the lane. Get that sign wrong and the lens ends up nose-deep in
## uncut grass, which is what happened to the first cut of every low shot ever
## composed in this file. `MOWING_YAW` and `CUT_SIDE` name it once.
const MOWING_YAW := PI * 0.5
## World Z offset of the side the staged cut lanes are laid on, per unit of
## local camera x. Negative: local +x is world -Z.
const CUT_SIDE := -1.0

## Lane pitch for staged cut lanes, world units. Slightly under twice the
## adapter's cut half-width, so neighbouring lanes OVERLAP and the staged area
## reads as finished lawn rather than as a comb with grass between the teeth.
const LANE_PITCH := 9.5

## Seconds a storm is allowed to settle BEHIND A COVERED SCREEN before it is
## revealed. The visual adapter eases at 1.2 e-foldings per second and the rain
## fades over 2.0 s, so a cut straight to Rain shows a half-transition. Hidden
## time is not part of the visible running time.
const WEATHER_PREROLL_SECONDS := 3.4

## The tank the production HUD shows in the gameplay-proof shot. The real fuel
## system holds it and really burns it from there; this only decides where it
## starts, so the gauge reads like a contract in progress rather than like a
## mower that has just left the shed.
const OPENING_FUEL := 68.0

## THE STORYBOARD. `at` is seconds of VISIBLE footage from the first frame.
## Durations are deliberately uneven -- a trailer where every shot is four
## seconds long is a slideshow.
const BEATS: Array = [
	{"at": 0.0, "name": "main menu", "call": "_beat_main_menu"},
	{"at": 4.0, "name": "town", "call": "_beat_town"},
	{"at": 9.0, "name": "job board", "call": "_beat_job_board"},
	{"at": 11.8, "name": "accept", "call": "_beat_accept"},
	# THREE mowing shots, not five. M13: the mowing section was the weak part of
	# the trailer and the fix was fewer, closer, slower shots rather than more
	# angles on the same problem.
	{"at": 14.0, "name": "mower over the top", "call": "_beat_over_the_top"},
	{"at": 19.0, "name": "mower low pass", "call": "_beat_low_pass"},
	{"at": 23.0, "name": "mower close", "call": "_beat_close"},
	{"at": 26.6, "name": "weather hero", "call": "_beat_storm"},
	{"at": 31.6, "name": "gameplay proof", "call": "_beat_proof"},
	{"at": 35.0, "name": "completion", "call": "_beat_completion"},
	{"at": 38.4, "name": "end card", "call": "_beat_end_card"},
	{"at": 41.8, "name": "hold", "call": "_beat_hold"},
]

var _elapsed: float = 0.0
var _next_beat: int = 0
var _running: bool = false
var _paused: bool = false
## Storyboard time is frozen while a beat prepares a shot behind a covered
## screen, so hidden setup never counts as footage.
var _clock_held: bool = false
var _shot_dir: String = ""
var _quit_at_end: bool = false

var _camera: ACACinematicCamera = null
var _mowers: ACATrailerMowerAdapter = null
var _lawn: ACATrailerLawnAdapter = null
var _weather: ACATrailerWeatherAdapter = null
var _ui: ACATrailerUIDirector = null

## Lawn geometry, measured from the real grid once the mowing scene exists, so
## shot positions are in the actual scene's units rather than guessed.
var _lawn_centre: Vector3 = Vector3.ZERO
var _lawn_half: float = 90.0
## The Y the mower's ORIGIN is planted at, so its wheels touch the lawn you can
## see. Measured in `_measure_ground_y()`, which is where the M13 float was.
var _ground_y: float = 0.0

var _title_layer: CanvasLayer = null
var _title_root: Control = null
var _title_tween: Tween = null

## Set while a beat wants the screen to stay black through a scene swap, so
## GameSession's own reveal does not expose an unprepared shot.
var _suppress_reveal: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--trailer-shots="):
			_shot_dir = arg.trim_prefix("--trailer-shots=")
			DirAccess.make_dir_recursive_absolute(_shot_dir)
		elif arg == "--trailer-quit":
			_quit_at_end = true

	_mowers = ACATrailerMowerAdapter.new()
	_mowers.name = "Trailer Mower Adapter"
	add_child(_mowers)
	_lawn = ACATrailerLawnAdapter.new()
	_lawn.name = "Trailer Lawn Adapter"
	add_child(_lawn)
	_weather = ACATrailerWeatherAdapter.new()
	_weather.name = "Trailer Weather Adapter"
	add_child(_weather)
	_ui = ACATrailerUIDirector.new()
	_ui.name = "Trailer UI Director"
	add_child(_ui)
	_mowers.moved.connect(_lawn.on_mower_moved)

	_build_title_card()
	# GameSession reveals the moment a swap finishes. When a beat is preparing a
	# shot, snap the cover back before that reveal can render a single frame -
	# deferred, so it lands at the end of the same frame the reveal starts in.
	GameSession.screen_changed.connect(_on_screen_changed)
	start.call_deferred()


# ==================================================================== control

func start() -> void:
	print("\n=============== TRAILER V3 ===============")
	print("[TRAILER] seed %d | R restart | SPACE pause | ESC quit" % TRAILER_SEED)
	_running = false
	_elapsed = 0.0
	_next_beat = 0
	_paused = false
	_clock_held = false
	_hide_title(0.0)
	await _setup_world()
	# Only now does 00:00 begin: the first frame of footage, not of loading.
	_elapsed = 0.0
	_next_beat = 0
	_running = true


func restart() -> void:
	_running = false
	_restore_everything()
	if _camera != null and is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null
	start()


## Every trailer-only change, undone. Called on R, on ESC and at the end of an
## automated run.
func _restore_everything() -> void:
	if _mowers != null:
		_mowers.release()
	if _weather != null:
		_weather.clear()
	if _ui != null:
		_ui.restore()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			print("[TRAILER] restart")
			restart()
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			_paused = not _paused
			get_tree().paused = _paused
			print("[TRAILER] %s at %s" % ["paused" if _paused else "resumed", _stamp()])
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			print("[TRAILER] quit")
			_restore_everything()
			get_tree().quit(0)


# ==================================================================== the run

## Deterministic starting state. Everything the trailer shows is generated from
## here, so two runs produce the same contract on the same lawn.
func _setup_world() -> void:
	_ui.begin_capture()
	# The tank the HUD will show later. The real fuel system holds it and the
	# mower adapter really burns it; this only picks the starting point.
	MowerFuel.dev_drain()
	MowerFuel.refuel(OPENING_FUEL)

	GameSession.go_to_main_menu()
	await _await_screen(ACAGameSession.Screen.MAIN_MENU)
	_ui.show_layer(ACATrailerUIDirector.Layer.MENU)
	# A moment for the scenic backdrop to settle before the first frame counts.
	await _wait(0.7)


## Deterministic contract market. Called right after the real NEW GAME so it
## overwrites whatever `start_new_game()` seeded.
func _seed_market() -> void:
	# DEVELOPMENT BRIDGE: pin the job market's RNG so the board is the same
	# every run. `_rng` is the manager's own; nothing else reaches into it.
	JobManager.debug_clear_all()
	JobManager._rng.seed = TRAILER_SEED
	# `seed_initial_offers` respects the market's capacity, which on day one is
	# one contract - a board with a single row is a poor shot. `_spawn_offer`
	# puts a real generated offer up regardless.
	for _i in 3:
		JobManager._spawn_offer(JobManager.now())


## The world clock is FROZEN for the whole trailer and the hour is set
## explicitly at the beats that want it. Two reasons: the run is repeatable to
## the frame, and 44 seconds at six game-minutes per real second would otherwise
## drift four hours and end after dark.
func _freeze_clock(hour: float = -1.0) -> void:
	if hour >= 0.0:
		WorldClock.set_running(true)
		WorldClock.advance_to_hour(hour)
	WorldClock.set_running(false)


func _await_screen(screen: int, max_frames: int = 900) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1


func _process(delta: float) -> void:
	if not _running or _paused or _clock_held:
		return
	_elapsed += delta
	while _next_beat < BEATS.size() and _elapsed >= float(BEATS[_next_beat]["at"]):
		var beat: Dictionary = BEATS[_next_beat]
		_next_beat += 1
		print("[TRAILER] %s  %s" % [_stamp(), beat["name"]])
		call(String(beat["call"]))
		if not _shot_dir.is_empty():
			_capture(String(beat["name"]))


# =============================================================== presentation

## Stop the storyboard clock. Hidden setup does not count against the visible
## running time.
func _hold_clock(held: bool) -> void:
	_clock_held = held


## Cover the screen and wait until it is actually black.
func _cover_and_wait(duration: float = 0.45) -> void:
	if AppUI.is_covered():
		return
	AppUI.cover(duration)
	var frames := 0
	while not AppUI.is_covered() and frames < 300:
		await get_tree().process_frame
		frames += 1


func _on_screen_changed(_screen: int) -> void:
	# GameSession calls AppUI.reveal() immediately after this signal. When a beat
	# is still preparing the shot, put the cover straight back - deferred, so the
	# reveal tween is killed before it has advanced a single frame.
	if _suppress_reveal:
		AppUI.transition().cover_immediately.call_deferred()


# ====================================================================== beats

## 0:00 - THE REAL MAIN MENU, with NEW GAME deliberately hovered.
##
## Not a title card over a scenic plate: this is the menu the player sees, with
## its own game title, its own hover animation, and a real cursor on the option.
## The scenery's own slow camera drift is already running, so the shot breathes
## without the trailer adding anything.
func _beat_main_menu() -> void:
	var menu := _find_main_menu()
	if menu == null:
		push_warning("[TRAILER] no main menu found for the opening shot")
		return
	menu.modulate.a = 1.0
	if menu.has_method("preview_hover_option"):
		if not menu.call(&"preview_hover_option", &"new_game"):
			push_warning("[TRAILER] NEW GAME could not be hovered")
	if menu.has_method("option_screen_position"):
		var where: Vector2 = menu.call(&"option_screen_position", &"new_game")
		if where.x >= 0.0:
			Input.warp_mouse(where)


## 0:04 - THE TOWN, as an establishing shot rather than as a diorama.
##
## A single five-second dolly from a high three-quarter view down to street
## level, ending on a push toward the Job Office. The lens narrows from 48 to 40
## across the move, which reads as a push rather than as a zoom.
func _beat_town() -> void:
	_town_sequence.call_deferred()


func _town_sequence() -> void:
	_hold_clock(true)
	_suppress_reveal = true
	await _cover_and_wait(0.5)

	# The real NEW GAME pathway, which is what takes the player to the town.
	GameSession.start_new_game()
	_seed_market()
	_freeze_clock(OPENING_HOUR)
	WorldClock.set_weather("Clear")

	await _await_screen(ACAGameSession.Screen.TOWN)
	await _wait(0.6)
	# The establishing shot carries no UI at all. The business HUD comes back
	# with the Job Board, which is the beat it belongs to.
	_ui.show_layer(ACATrailerUIDirector.Layer.CINEMATIC)

	var scene := get_tree().current_scene
	var town := scene.get_node_or_null(^"BusinessTown")
	if town != null:
		var jobs := town.get_node_or_null(^"Destinations/JobOffice") as Node3D
		var jobs_at: Vector3 = jobs.global_position if jobs != null else Vector3(-11.9, 0.0, -2.0)
		_camera = _spawn_camera(scene)
		# The town is a floating diorama about forty units across. Anything high
		# and distant fills half the frame with the grey behind it, so the rail
		# comes DOWN and IN: it starts high enough to read as an establishing
		# shot and finishes at street level with the buildings as the backdrop.
		# THE TOWN IS A FLOATING ISLAND thirty units across, sitting in the
		# procedural sky's flat grey ground colour. Anything high or distant
		# frames that void, and the first cut of this shot did exactly that -
		# half the picture was grey nothing.
		#
		# So the rail runs WEST DOWN THE MAIN STREET at roof-lower-storey height,
		# aimed at the shopfront row on the north side. Those buildings are ten
		# units tall and only six to eight units away, so they fill past the top
		# of the frame and the horizon never gets into shot at all.
		#
		# The ROAD is the corridor, not the pavement: every lamp post, bench,
		# hydrant and tree in this town is on the pavement, and the road's three
		# parked cars are under a unit tall, so a lens at 3 units clears them.
		# THIS TOWN IS A MINIATURE. Its buildings are TWO world units wide and
		# four or five tall -- next to a mower lawn where the grass alone is
		# three units, that is a doll's house. Every camera height that sounds
		# reasonable is above the rooftops, which is what put a band of empty
		# grey between the town and the horizon in the first two cuts.
		#
		# So the lens sits at 1.9 units, lower than the shopfront awnings, and
		# runs WEST down the main street a metre off the north kerb. At that
		# height and that range the buildings are forty degrees tall and there
		# is no horizon left to see.
		_camera.cut_to({
			"mode": "rail",
			"rail": [
				Vector3(12.5, 2.1, -0.2),
				Vector3(5.5, 2.0, -0.2),
				Vector3(-2.5, 2.0, 0.4),
				Vector3(-7.2, 2.0, 1.2),
			],
			# The aim travels too, so the move ARRIVES at the Job Office instead
			# of pivoting around the middle of the town the whole way.
			#
			# It stays SHORT -- five or six units ahead, not twenty. A building
			# only overflows the top of the frame while it is nearer than about
			# seven units, and a shot of this town with any horizon in it has
			# grey void in it.
			"look_rail": [
				Vector3(7.0, 1.3, -2.6),
				Vector3(0.0, 1.3, -2.6),
				Vector3(-8.0, 1.4, -2.4),
				# The last leg turns to face the Job Office nearly head on. Aimed
				# any further west and the frame fills with the empty grey past
				# the west edge of the island.
				jobs_at + Vector3(-0.1, 1.6, -0.4),
			],
			"duration": 5.0,
			"ease": "in_out",
			# A LONG LENS on a miniature. These buildings are two units wide, so
			# a normal 45-degree lens frames the whole diorama and the emptiness
			# around it; a narrow one frames a street.
			"fov": 40.0,
			"fov_to": 34.0,
			"damp": 0.0,
			"look_damp": 0.0,
			"min_ground": 1.2,
		})
	await _wait(0.2)

	_suppress_reveal = false
	AppUI.reveal(0.5)
	_hold_clock(false)


## 0:09 - THE JOB BOARD. Real generated offers, a real cursor landing on the
## contract the trailer takes. The camera slows almost to a stop so the panel is
## readable over a calm plate.
func _beat_job_board() -> void:
	var scene := get_tree().current_scene
	var town := scene.get_node_or_null(^"BusinessTown") as ACABusinessTown
	if town != null and town.hud != null:
		town.hud.open_jobs()
		# The overview hint chip is gameplay furniture and sits under the board.
		var hint := town.hud.get_node_or_null(^"Root/HintChip")
		if hint != null:
			hint.set(&"visible", false)
	_ui.show_layer(ACATrailerUIDirector.Layer.JOB_BOARD)
	if _camera != null:
		_camera.ease_to({
			"mode": "static",
			"position": _camera.global_position,
			"drift": Vector3(-0.35, 0.10, -0.15),
			"look_at": _camera.global_position + -_camera.global_transform.basis.z * 12.0,
			"fov": 40.0,
			"damp": 0.0,
			"look_damp": 0.0,
		})
	_point_at_chosen_contract.call_deferred()


## Make the selection deliberate: the cursor lands on the ACCEPT button of the
## contract the trailer takes, a second before it is pressed.
func _point_at_chosen_contract() -> void:
	await _wait(0.9)
	var card := _card_for(_pick_contract())
	if card != null and card.action_button != null:
		_ui.point_at(card.action_button)


## 0:11.8 - ACCEPT through the board's OWN button, then begin the contract.
func _beat_accept() -> void:
	_accept_sequence.call_deferred()


func _accept_sequence() -> void:
	var job := _pick_contract()
	if job == null:
		push_warning("[TRAILER] no contract available; the trailer will be short")
		return
	print("[TRAILER]   contract: %s | %s | $%d" % [
		job.job_site, job.lawn_size_name(), job.base_pay])

	# The REAL accept: the card's own button, not JobManager.accept_job().
	var card := _card_for(job)
	if card != null and card.action_button != null:
		card.action_button.pressed.emit()
	else:
		JobManager.accept_job(job.id)
	await _wait(0.7)

	# ...and the real BEGIN JOB on the CURRENT tab, which is what asks
	# GameSession to change scene.
	_ui.show_layer(ACATrailerUIDirector.Layer.TOWN)
	var begin := _card_for(job)
	if begin != null and begin.action_button != null:
		begin.action_button.pressed.emit()
	else:
		JobManager.begin_new_job(job.id)

	await _await_screen(ACAGameSession.Screen.MOWING)
	await _wait(0.4)
	await _bind_mowing_scene()
	# The Job Intro is the shot here - the contract's name, size and payout over
	# the lawn. It comes off before the first cinematic shot, so no two panels
	# are ever fading over each other.
	_ui.show_layer(ACATrailerUIDirector.Layer.GAMEPLAY)
	_freeze_clock(MOWING_HOUR)

	if _camera != null and _mowers.is_bound():
		_camera.set_target(_mowers.mower())
		_camera.cut_to({
			"mode": "follow",
			"offset": Vector3(5.5, 2.4, 11.0) * SCALE,
			"look_offset": Vector3(0.0, 1.0, 0.0) * SCALE,
			"fov": 48.0,
			"damp": 2.2,
			"look_damp": 5.0,
		})


## 0:14 - OVER THE MOWER. The hero shot of the mowing section.
##
## THE DRIVING SEAT. The lens sits where an operator's head would be, just above
## and behind the steering wheel, looking forward over the bonnet into the lawn.
## The bodywork fills the bottom of the frame, the wheel is in shot and turning,
## and the grass comes at the camera and disappears under the deck. It is the
## closest thing to a first-person view this game has without a first-person
## camera being added to it.
##
## WHY THIS REPLACED THE WIDE ESTABLISHING PLATE. The V3 opener was a plate
## thirty units up looking down at a mower doing 46 u/s. It framed the lawn
## beautifully and the mower was four percent of the frame width -- a speck
## scuttling across a green field, which is exactly the "comical" the review
## called out. A trailer establishes a mowing game by showing the mowing.
##
## The camera is nearly rigid on purpose (damp 16) so it reads as MOUNTED rather
## than as a chase that keeps losing its subject, and the mower's suspension is
## damped almost flat for the same reason: at this range the default bob is
## camera shake.
func _beat_over_the_top() -> void:
	_over_the_top_sequence.call_deferred()


func _over_the_top_sequence() -> void:
	_hold_clock(true)
	await _cover_and_wait(0.4)
	_ui.show_layer(ACATrailerUIDirector.Layer.CINEMATIC)

	# STAGED PROGRESS, LAID SO THE LENS CAN SEE IT. A Large Lawn is 36,864
	# blades and no amount of footage cuts a visible fraction of it by driving,
	# so the shot is given a lawn that is already part done. The cut is real --
	# the grid loses the grass, the counter moves, the HUD percentage is true.
	#
	# The lanes go IMMEDIATELY BESIDE the mower's own, not off across the lawn.
	# From this seat the finished work fills the left of the frame, the uncut
	# grass fills the right, and the mower runs the line between them. That
	# boundary is the whole reason the shot reads as mowing rather than as
	# driving: the first cut of it staged the lanes twenty-six units away and
	# they registered as nothing more than a thin patch near the horizon.
	var lane_z: float = _lawn_centre.z + 4.0
	_lawn.stage_stripes(Vector3(_lawn_centre.x, 0.0, lane_z + CUT_SIDE * LANE_PITCH * 2.0),
		MOWING_YAW, 3, _lawn_half * 1.9, LANE_PITCH)

	# The mower enters with a trail ALREADY cut behind it. The lens looks down
	# that trail for the whole shot, so a mower that has just been placed would
	# be sitting at the head of nothing.
	var start_x: float = _lawn_centre.x - _lawn_half * 0.55
	_lawn.cut_line(Vector3(_lawn_centre.x - _lawn_half * 1.6, 0.0, lane_z),
		Vector3(start_x, 0.0, lane_z))
	_mowers.place(Vector3(start_x, 0.0, lane_z), MOWING_YAW)
	# Almost flat. A mounted lens turns bob into shake.
	_mowers.set_suspension(0.015, 1.8, 0.10)

	_camera.set_target(_mowers.mower())
	_camera.cut_to({
		"mode": "follow",
		# Local frame: +z is AHEAD of the mower, so a small negative z is just
		# behind the wheel. Head height for someone sitting on it.
		"offset": Vector3(0.0, 2.45, -0.7) * SCALE,
		# The aim goes a long way down the lane, which tips the treeline into
		# the top third and leaves the lawn filling the frame. Aimed any nearer
		# and the shot is a lens staring at its own bonnet.
		"look_offset": Vector3(0.0, 0.35, 0.0) * SCALE,
		"look_lead": 34.0,
		"duration": 5.0,
		# A slow push that lands on the lawn ahead rather than on the machine,
		# so the shot ends looking at the work.
		"fov": 62.0,
		"fov_to": 55.0,
		# Nearly rigid: this is a camera BOLTED to the mower, not chasing it.
		"damp": 16.0,
		"look_damp": 9.0,
	})

	await _wait(0.2)
	AppUI.reveal(0.5)
	# A whisper of a turn, so the world swings very slightly through the shot
	# and the frame is not a still photograph with moving grass in it.
	_mowers.drive_straight(SPEED_OVER_THE_TOP, 0.03)
	_hold_clock(false)


## 0:19 - LOW FRONT-QUARTER PASS. The camera sits LOW on the finished lawn,
## ahead of the mower and off to the cut side, looking back at it as it comes on
## along the boundary between mowed and unmowed.
##
## THE COMPOSITION IS THE BOUNDARY. Cut lawn in the foreground, the machine on
## the line, and a wall of uncut grass behind it. A shot framed anywhere else
## is a mower standing in a field: the first cut of this one was beautifully
## lit, perfectly steady, and showed no mowing at all.
##
## "Low" means about four units, not grass height -- the blades are three units
## tall, so a lens under about two is filming a wall. The camera's own lane is
## part of the staged cut, which is what lets it sit this low.
func _beat_low_pass() -> void:
	_low_pass_sequence.call_deferred()


func _low_pass_sequence() -> void:
	_hold_clock(true)
	await _cover_and_wait(0.35)

	var lane_z: float = _lawn_centre.z - 8.0
	# Three overlapping lanes on the cut side, the middle one directly under the
	# camera. Overlapping, because a comb of lanes with uncut ridges between
	# them puts a line of blades across the mower's wheels from a lens this low.
	var cut_centre: float = lane_z + CUT_SIDE * LANE_PITCH * 1.3
	_lawn.stage_stripes(Vector3(_lawn_centre.x, 0.0, cut_centre), MOWING_YAW,
		3, _lawn_half * 1.9, LANE_PITCH)

	var start_x: float = _lawn_centre.x - _lawn_half * 0.5
	_lawn.cut_line(Vector3(_lawn_centre.x - _lawn_half * 1.6, 0.0, lane_z),
		Vector3(start_x, 0.0, lane_z))
	_mowers.place(Vector3(start_x, 0.0, lane_z), MOWING_YAW)
	_mowers.set_suspension(0.05, 2.4, 0.16)

	_camera.set_target(_mowers.mower())
	_camera.cut_to({
		"mode": "follow",
		# Local +x is the CUT side, so this is over the finished lawn, low, and
		# a little ahead. Looking back, the machine comes on towards the lens.
		"offset": Vector3(4.3, 1.75, 5.8) * SCALE,
		"look_offset": Vector3(0.0, 0.75, 0.0) * SCALE,
		"duration": 4.0,
		# A long lens on a close subject: it compresses the lawn behind the
		# mower into the frame instead of letting it run off to a vanishing
		# point, and it keeps the treeline out of the top of the shot.
		"fov": 42.0,
		"fov_to": 38.0,
		# A slow crane, half a unit across the shot. Enough for the frame to
		# breathe; not enough to notice as a move.
		"drift": Vector3(0.0, 0.14, 0.0),
		# Tight, but not rigid. At 21 u/s a soft follow lags by speed/damp world
		# units, which on a shot framed this close is straight out of frame.
		"damp": 11.0,
		"look_damp": 12.0,
	})

	await _wait(0.15)
	AppUI.reveal(0.4)
	_mowers.drive_straight(SPEED_LOW_PASS)
	_hold_clock(false)


## 0:23 - THE SLOW CLOSE PASS. Front three-quarter, close enough to read the
## bodywork and the wheels, with the lawn thrown gently soft behind. The slowest
## thing in the trailer: 13 u/s, so the machine drifts through frame.
##
## This is the shot the review liked the composition of and hated the behaviour
## in. The composition is kept; the speed is halved, the suspension is damped,
## the staged cut has moved to the side the lens is actually on, and the mower
## is finally on the ground.
func _beat_close() -> void:
	_close_sequence.call_deferred()


func _close_sequence() -> void:
	_hold_clock(true)
	_mowers.stop()
	await _cover_and_wait(0.35)

	var c := _lawn_centre
	var lane_z: float = c.z + 14.0
	# This lens is on the -x side of the mower, so the finished lawn has to be
	# on the OTHER side from the previous shot or the camera is stood in grass
	# and the cut is behind the machine where it cannot be seen.
	var cut_centre: float = lane_z - CUT_SIDE * LANE_PITCH * 1.3
	_lawn.stage_stripes(Vector3(c.x, 0.0, cut_centre), MOWING_YAW, 3,
		_lawn_half * 1.6, LANE_PITCH)
	var start_x: float = c.x - 26.0
	_lawn.cut_line(Vector3(c.x - 80.0, 0.0, lane_z), Vector3(start_x, 0.0, lane_z))
	_mowers.place(Vector3(start_x, 0.0, lane_z), MOWING_YAW)
	_mowers.set_suspension(0.035, 2.2, 0.16)

	_camera.set_target(_mowers.mower())
	_camera.cut_to({
		"mode": "follow",
		# Ahead, low and to the side, far enough back that the whole machine is
		# in frame - an earlier cut of this shot sliced the mower in half at the
		# frame edge.
		"offset": Vector3(-4.6, 1.9, 8.4) * SCALE,
		"look_offset": Vector3(0.0, 0.9, 0.2) * SCALE,
		"duration": 3.6,
		"fov": 36.0,
		"fov_to": 33.0,
		# Subtle. Enough to separate the mower from the treeline, not enough to
		# read as a filter.
		"dof": {"target": true, "amount": 0.05, "transition": 26.0, "target_scale": 1.25},
		"damp": 7.0,
		"look_damp": 8.0,
	})

	await _wait(0.15)
	AppUI.reveal(0.35)
	_mowers.drive_straight(SPEED_CLOSE, -0.03)
	_hold_clock(false)


## 0:26.6 - THE STORM HERO. The one shot that is not attached to the mower.
##
## Prepared entirely behind a cover: the hour and the weather are set, the
## trailer weather adapter biases the look blue-grey and turns the rain up, the
## adapter is given WEATHER_PREROLL_SECONDS to converge, and only then is it
## revealed. Cutting straight to it shows a half-finished transition.
##
## The camera is PARKED, perpendicular to the mower's travel and far enough back
## that the frame is about a hundred units wide at that depth. The mower crosses
## it at a deliberately slower 26 u/s, because a parked camera can only hold a
## subject that takes three seconds or so to cross.
func _beat_storm() -> void:
	_storm_sequence.call_deferred()


func _storm_sequence() -> void:
	_hold_clock(true)
	_mowers.stop()
	await _cover_and_wait(0.5)

	_freeze_clock(STORM_HOUR)
	WorldClock.set_weather("Rain")
	_weather.apply_storm()
	await _wait(WEATHER_PREROLL_SECONDS)
	print("[TRAILER]   sky: %s" % _weather.describe())

	var c := _lawn_centre
	var yaw := PI * 0.5
	var across := Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(cos(yaw), 0.0, -sin(yaw))
	var start: Vector3 = c - across * 40.0 + Vector3(0.0, 0.0, 6.0)
	# A finished pass running away behind it, so even the storm shot shows work.
	_lawn.cut_line(start - across * 40.0, start)
	_mowers.place(start, yaw)

	# THE SKY IS THE SUBJECT, and this lawn sits in a bowl ringed by trees
	# twenty-odd units tall - a level camera sees only treeline. So the lens is
	# low, wide, and aimed well ABOVE the mower, with a slow crane so more sky
	# arrives through the shot.
	#
	# It is a SLOW TRACK rather than a parked plate. Parked, the geometry does
	# not work: a lens near enough for the mower to read is one the mower is
	# through in a second and a half, and a lens that holds it for five seconds
	# turns it into a speck against the weather. Following in world axes with
	# slack damping keeps the horizon level and the composition still, while the
	# mower runs ahead of the lens and stays a readable subject the whole beat.
	#
	# HOW MUCH SKY IS ACTUALLY AVAILABLE. From inside this bowl the treeline
	# starts about sixteen degrees up, so sky and a ground-level subject compete
	# for the same frame: aim high enough for half a frame of sky and the mower
	# falls out of the bottom. The compromise is deliberate - the lens aims two
	# and a half units above the mower, which puts the treeline about a third of
	# the way down and leaves the mower sitting in the lower third under the
	# weather, which is the composition this shot wanted anyway.
	_mowers.set_suspension(0.05, 2.4, 0.16)
	_camera.set_target(_mowers.mower())
	_camera.cut_to({
		"mode": "follow",
		"world_offset": side * -26.0 + across * -6.0 + Vector3(0.0, 3.4, 0.0),
		"look_offset": Vector3(0.0, 3.6, 0.0) * SCALE,
		"drift": Vector3(0.0, 0.25, 0.0),
		"duration": 5.0,
		"fov": 50.0,
		"damp": 5.0,
		"look_damp": 5.5,
	})

	await _wait(0.15)
	AppUI.reveal(0.6)
	_mowers.drive_straight(SPEED_STORM, 0.02)
	_hold_clock(false)


## 0:31.6 - THE GAMEPLAY PROOF. The real production HUD over a partly finished
## lawn, so the trailer says "this is a game" rather than only "this is pretty".
func _beat_proof() -> void:
	_proof_sequence.call_deferred()


func _proof_sequence() -> void:
	_hold_clock(true)
	_mowers.stop()
	await _cover_and_wait(0.3)

	# THE STORM HAS TO STOP BEHIND THE COVER, and this is now the beat that
	# follows it. The rain fades over two seconds and the sky eases, so cutting
	# straight to Clear leaves rain falling out of a blue sky.
	_weather.clear()
	_freeze_clock(MOWING_HOUR)
	WorldClock.set_weather("Clear")
	await _wait(2.6)

	# The lawn the HUD is reporting on. By this beat it should look like most of
	# a contract, because the HUD is about to put a number on it.
	var c := _lawn_centre
	_lawn.stage_stripes(c + Vector3(0.0, 0.0, -12.0), PI * 0.5, 7, _lawn_half * 1.8, 11.0)
	_lawn.stage_stripes(c + Vector3(0.0, 0.0, 62.0), PI * 0.5, 4, _lawn_half * 1.5, 11.0)

	var lane_z: float = c.z + 40.0
	var start_x: float = c.x - 46.0
	_lawn.cut_line(Vector3(c.x - _lawn_half, 0.0, lane_z), Vector3(start_x, 0.0, lane_z))
	_mowers.place(Vector3(start_x, 0.0, lane_z), PI * 0.5)

	_mowers.set_suspension(0.05, 2.4, 0.16)
	_ui.show_layer(ACATrailerUIDirector.Layer.GAMEPLAY)
	# A rear THREE-QUARTER, not a shot straight down the lane: from directly
	# behind, every staged stripe runs away from the lens and the lawn reads as
	# untouched. Off to the side they cross the frame and the work shows.
	_camera.set_target(_mowers.mower())
	_camera.cut_to({
		"mode": "follow",
		# HIGHER AND FURTHER BACK than V3's. From close behind, the grass box
		# is a black slab across half the frame and the HUD has nothing to
		# report on; from up here the lawn and its finished lanes are the shot
		# and the mower is what is working on it.
		"offset": Vector3(-2.6, 3.4, -6.2) * SCALE,
		"look_offset": Vector3(0.4, 0.4, 0.0) * SCALE,
		"look_lead": 16.0,
		"fov": 48.0,
		"damp": 9.5,
		"look_damp": 10.5,
	})

	await _wait(0.15)
	AppUI.reveal(0.35)
	_mowers.drive_straight(SPEED_PROOF, 0.03)
	_hold_clock(false)
	print("[TRAILER]   lawn %.0f%% mowed" % (_lawn.mowed_fraction() * 100.0))


## 0:35 - THE REAL Job Complete screen with the real payout, over a lawn that
## has visibly been finished.
##
## Behind the cover the remaining lanes are cut, so the plate under the results
## panel is the FINISHED job rather than the patch of dirt the mower happened to
## stop on. The lawn is taken to most of the way, never to 100%: the mowing grid
## fires its own completion at 1.0 and would settle the contract before the
## trailer got to press the button itself.
func _beat_completion() -> void:
	_completion_sequence.call_deferred()


func _completion_sequence() -> void:
	_hold_clock(true)
	_mowers.stop()
	await _cover_and_wait(0.4)
	_ui.show_layer(ACATrailerUIDirector.Layer.CINEMATIC)

	var c := _lawn_centre
	_lawn.stage_stripes(c, PI * 0.5, 15, _lawn_half * 1.9, 11.0)
	print("[TRAILER]   lawn finished at %.0f%%" % (_lawn.mowed_fraction() * 100.0))

	# The mower parked on the finished lawn, and a composed plate looking across
	# the stripes with the treeline behind. Static, because a results panel over
	# a moving camera is unreadable.
	_mowers.place(Vector3(c.x + 26.0, 0.0, c.z + 20.0), PI * 0.72)
	_camera.set_target(_mowers.mower())
	_camera.cut_to({
		"mode": "static",
		"position": c + Vector3(-2.0, 11.0, 46.0),
		"look_at": c + Vector3(18.0, 1.2, 16.0),
		"drift": Vector3(0.5, 0.1, -0.3),
		"duration": 3.4,
		"fov": 44.0,
		"damp": 0.0,
		"look_damp": 0.0,
	})

	# THE REAL completion pathway - the same one natural 100% mowing takes.
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("dev_complete_current_job"):
		scene.call(&"dev_complete_current_job")
	_ui.show_layer(ACATrailerUIDirector.Layer.RESULTS)

	await _wait(0.2)
	AppUI.reveal(0.45)
	_hold_clock(false)


## 0:38.4 - fade the game out from UNDER the card. The title only appears once
## the screen is black, so the results panel and the end card never share a
## frame.
func _beat_end_card() -> void:
	_end_card_sequence.call_deferred()


func _end_card_sequence() -> void:
	await _cover_and_wait(0.9)
	_mowers.stop()
	_ui.show_layer(ACATrailerUIDirector.Layer.NONE)
	await _wait(0.25)
	_show_title(1.0, TITLE, SUBTITLE)


func _beat_hold() -> void:
	_running = false
	print("[TRAILER] %s  end (holding on the title card)" % _stamp())
	print("==========================================\n")
	if _quit_at_end:
		_quit_after_capture.call_deferred()


func _quit_after_capture() -> void:
	if not _shot_dir.is_empty():
		await _wait(0.8)
		await _save("%s/%02d-hold.png" % [_shot_dir, _next_beat])
	_restore_everything()
	get_tree().quit(0)


# ============================================================ scene binding

## Measure the lawn from the real grid and hand the mower to the adapter.
##
## THE MOWER IS PLANTED, NOT SETTLED. See `_measure_ground_y()`.
func _bind_mowing_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var grid := scene.get_node_or_null(^"Custom Gridmap") as Custom_Gridmap
	if grid != null:
		_lawn.bind(grid)
		_measure_lawn(grid)

	var mower := scene.get(&"current_mower") as CharacterBody3D
	if mower == null:
		push_warning("[TRAILER] no mower in the mowing scene")
		return
	# Let its own gravity run first: the mower is authored two units up, and the
	# adapter must not take the wheel mid-fall. Where it comes to rest is NOT
	# where the trailer plants it -- see `_measure_ground_y()`.
	await _wait(0.8)
	_ground_y = _measure_ground_y(grid, mower)
	_mowers.bind(mower, _ground_y)
	# THE LAWN IS NOT AT THE ORIGIN. `MVP._ready()` parks the whole grid at
	# roughly (-312, -492, -140), so every shot position in this file is written
	# relative to `_lawn_centre` and that centre has to carry the real height or
	# each camera ends up five hundred units above the grass.
	_lawn_centre.y = _ground_y

	var pm := scene.get_node_or_null(^"PresetManager (Sky3D)")
	if pm != null:
		_weather.bind(pm)

	if _camera == null:
		_camera = _spawn_camera(scene)
	print("[TRAILER]   lawn centre %s half %.0f ground y %.2f"
		% [_lawn_centre, _lawn_half, _ground_y])


## WHERE THE GROUND ACTUALLY IS. This is the Milestone 13 fix.
##
## Up to V3 the trailer let the mower's own physics settle and used the height
## it came to rest at. That height is wrong twice over, and the mowing footage
## showed it: the machine hung in the air with a gap of daylight under every
## wheel, which is the "flying" and "bouncing" the review called out.
##
##   1. EVERY BLADE OF GRASS IS A REAL `StaticBody3D`, about three units tall.
##      A mower dropped on to an uncut lawn does not land on the lawn. It lands
##      on the grass, and stays there.
##   2. THE GROUND YOU CAN SEE IS NOT THE GROUND PHYSICS USES. `Mowing Area` is
##      a `PlaneMesh` at the body's own origin with a 50 x 1 x 50 `BoxShape3D`
##      centred on it, so its collision surface stands HALF A UNIT proud of the
##      visible dirt even where the grass has been cut.
##
## So neither the settle nor a downward ray answers the question. Both parts are
## measured instead: the visible plane from the grid's own node, and how far the
## mower's origin sits above its lowest visible point from its own meshes. The
## sum plants the wheels on the dirt the camera can see.
##
## Falls back to the settled height if the grid is not shaped as expected, which
## is worse footage but never a mower under the lawn.
func _measure_ground_y(grid: Custom_Gridmap, mower: Node3D) -> float:
	var settled: float = mower.global_position.y
	var lift: float = ACATrailerMowerAdapter.visual_lift(mower)
	var ground := grid.get_node_or_null(^"Mowing Area") as Node3D if grid != null else null
	if ground == null:
		push_warning("[TRAILER] no Mowing Area to measure; using the settled height")
		return settled
	var planted: float = ground.global_position.y + lift
	print("[TRAILER]   ground: plane %.2f + mower lift %.2f = %.2f  (settled %.2f, %+.2f)"
		% [ground.global_position.y, lift, planted, settled, planted - settled])
	return planted


## The lawn's real extent, taken from where the chunks actually are rather than
## from the grid's display radius - the two are not the same number and shots
## composed on the wrong one run off the edge into the dirt border.
func _measure_lawn(grid: Custom_Gridmap) -> void:
	var min_p := Vector3(INF, 0.0, INF)
	var max_p := Vector3(-INF, 0.0, -INF)
	var found := false
	for id in grid.chunk_id_to_chunk_dictionary:
		var chunk: Multi_Mesh_Chunk = grid.chunk_id_to_chunk_dictionary[id]
		var node: Node3D = chunk.multimesh_instance_unmowed
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var p := node.global_position
		min_p.x = minf(min_p.x, p.x)
		min_p.z = minf(min_p.z, p.z)
		max_p.x = maxf(max_p.x, p.x)
		max_p.z = maxf(max_p.z, p.z)
		found = true
	if not found:
		return
	_lawn_centre = Vector3((min_p.x + max_p.x) * 0.5, 0.0, (min_p.z + max_p.z) * 0.5)
	_lawn_half = minf(max_p.x - min_p.x, max_p.z - min_p.z) * 0.5


# =================================================================== helpers

## The most attractive of the seeded offers: best paying, so the Job Intro and
## the results screen both show a number worth putting in a trailer.
func _pick_contract() -> ACAJob:
	var best: ACAJob = null
	for job in JobManager.available_jobs():
		if best == null or job.base_pay > best.base_pay:
			best = job
	if best == null:
		var current := JobManager.current_jobs()
		if not current.is_empty():
			best = current[0]
	return best


## The board's own card for a contract, so its own ACCEPT / BEGIN JOB button can
## be pressed rather than the manager being called behind the UI's back.
func _card_for(job: ACAJob) -> ACAJobCard:
	if job == null:
		return null
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for node in scene.find_children("*", "ACAJobCard", true, false):
		var card := node as ACAJobCard
		if card != null and card.job_id() == job.id:
			return card
	return null


func _spawn_camera(parent: Node) -> ACACinematicCamera:
	if _camera != null and is_instance_valid(_camera):
		_camera.queue_free()
	var camera := ACACinematicCamera.new()
	camera.name = "Trailer Camera"
	camera.near = 0.08
	camera.far = 4000.0
	parent.add_child(camera)
	camera.current = true
	return camera


func _find_main_menu() -> Control:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for node in scene.find_children("*", "MainMenuScreen", true, false):
		return node as Control
	return null


## Real seconds, unaffected by the tree being paused.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _stamp() -> String:
	return "%02d:%02d" % [int(_elapsed) / 60, int(_elapsed) % 60]


# ================================================================ review shots

## THREE frames per beat, spread across the shot, and none of them taken while
## the screen is covered - a beat that prepares its shot behind black would
## otherwise produce three black frames and a review pass that reviews nothing.
## Beats that are DELIBERATELY over black opt out of the wait.
const CAPTURE_OVER_BLACK: PackedStringArray = ["end card", "hold"]

func _capture(name: String) -> void:
	var index := _next_beat
	var slug := name.replace(" ", "-")
	if not CAPTURE_OVER_BLACK.has(name):
		# Two frames first: a beat that prepares a shot does it in a DEFERRED
		# call, so nothing has covered the screen yet at the instant the beat
		# returns. Without this the wait below sees a clear screen, exits
		# immediately, and shoots into the fade that is about to start.
		await get_tree().process_frame
		await get_tree().process_frame
		var waited := 0.0
		while waited < 20.0 and (AppUI.is_covered() or _clock_held
				or AppUI.transition().is_busy()):
			await _wait(0.1)
			waited += 0.1
	# Spread across THIS beat's own length rather than at fixed offsets. The
	# beats run from 2.6 to 5 seconds, and fixed offsets left the last third of
	# every long shot unreviewed -- which is exactly where a dolly arrives at
	# the thing it was moving towards.
	var span: float = 3.0
	if index < BEATS.size():
		span = float(BEATS[index]["at"]) - float(BEATS[index - 1]["at"])
	await _wait(span * 0.10)
	await _save("%s/%02d-%s-a.png" % [_shot_dir, index, slug])
	await _wait(span * 0.40)
	await _save("%s/%02d-%s-b.png" % [_shot_dir, index, slug])
	await _wait(span * 0.38)
	await _save("%s/%02d-%s-c.png" % [_shot_dir, index, slug])


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[TRAILER]   %s%s" % [path.get_file(), _framing()])


## WHERE THE SUBJECT ACTUALLY IS, as numbers.
##
## Composing these shots by reading screenshots and adjusting offsets by feel is
## slow and keeps missing: an offset is in the mower's local frame, the aim is
## somewhere else again, and the follow damping adds a lag that depends on the
## shot's speed. Projecting the mower back on to the screen answers the only
## questions that matter -- is it IN frame, where in frame, and how big -- in
## one line per review shot.
##
## x/y are fractions of the viewport, 0.5/0.5 being dead centre. `size` is the
## mower's apparent width as a fraction of the frame.
func _framing() -> String:
	if _camera == null or not is_instance_valid(_camera) or not _mowers.is_bound():
		return ""
	var mower := _mowers.mower()
	var view: Vector2 = get_viewport().get_visible_rect().size
	if view.x <= 0.0:
		return ""
	# The VISUAL bounds, not the node origin. The rider's origin sits at the
	# base of its collision body, well below and behind the machine, so a close
	# shot that frames the bodywork beautifully still reports its origin off the
	# bottom of the screen.
	var visual := mower.get_node_or_null(^"LawnTractor01") as MeshInstance3D
	var box: AABB = mower.global_transform * AABB(Vector3(-2, 0, -4), Vector3(4, 3, 8))
	if visual != null and visual.mesh != null:
		box = visual.global_transform * visual.mesh.get_aabb()
	var middle: Vector3 = box.get_center()
	if _camera.is_position_behind(middle):
		return "  mower BEHIND CAMERA"
	var centre: Vector2 = _camera.unproject_position(middle)
	var left: float = INF
	var right: float = -INF
	var top: float = INF
	var bottom: float = -INF
	for i in 8:
		var corner: Vector2 = _camera.unproject_position(box.get_endpoint(i))
		left = minf(left, corner.x)
		right = maxf(right, corner.x)
		top = minf(top, corner.y)
		bottom = maxf(bottom, corner.y)
	return "  mower %.2f,%.2f  w %.2f h %.2f%s" % [
		centre.x / view.x, centre.y / view.y,
		(right - left) / view.x, (bottom - top) / view.y,
		"  OFF FRAME" if (right < 0.0 or left > view.x
			or bottom < 0.0 or top > view.y) else "",
	]


# ================================================================ title card

func _build_title_card() -> void:
	_title_layer = CanvasLayer.new()
	_title_layer.name = "Trailer Title"
	_title_layer.layer = 200
	add_child(_title_layer)

	_title_root = Control.new()
	_title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.modulate.a = 0.0
	_title_layer.add_child(_title_root)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(centre)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	centre.add_child(column)

	var top := UITheme.label(column, "Title", TITLE, UITheme.FONT_TITLE, UITheme.INK)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var rule := ColorRect.new()
	rule.color = UITheme.ACCENT
	rule.custom_minimum_size = Vector2(90, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(rule)

	var bottom := UITheme.label(column, "Subtitle", SUBTITLE, UITheme.FONT_DISPLAY,
		UITheme.INK)
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _show_title(duration: float, title: String, subtitle: String) -> void:
	(_title_root.find_child("Title", true, false) as Label).text = title
	(_title_root.find_child("Subtitle", true, false) as Label).text = subtitle
	_fade_title(1.0, duration)


func _hide_title(duration: float) -> void:
	_fade_title(0.0, duration)


func _fade_title(target: float, duration: float) -> void:
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	if duration <= 0.0:
		_title_root.modulate.a = target
		return
	_title_tween = create_tween()
	_title_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_tween.tween_property(_title_root, ^"modulate:a", target, duration)
