extends Node3D
## DEVELOPMENT ONLY. A standalone scene that builds ONE REAL PROPERTY at a size
## chosen in the Inspector, so the production lawn architecture can be measured
## far past the sizes any contract asks for.
##
## Nothing here reimplements the game. The property is `ACAProperty`, the
## ground is `ACATerrain`, the mowing state is `ACALawn`, the turf is
## `ACALawnGrass`, the wood is `ACAForest` and the machine is the canonical
## Rider Mower cutting through `ACAMowerCutter`. The only thing this scene owns
## is the size, the toggles, the camera and the numbers.
##
## HOW TO USE IT
##   Open `Dev tools/Validation/Large Lawn Stress Test.tscn`, set
##   `lawn_size_meters` on the root node, press Play. Drive with WASD, look
##   with the mouse, press F2 for the overview camera, F3 for the HUD.
##
## FROM THE COMMAND LINE (the sweep)
##   godot --path . "res://Dev tools/Validation/Large Lawn Stress Test.tscn" -- \
##     "--stress-size=1000" "--stress-benchmark"
##
## Arguments (each one overrides the Inspector)
##   --stress-size=<int>      lawn side in world units
##   --stress-seed=<int>      property seed
##   --stress-no-grass        build without ACALawnGrass
##   --stress-no-forest       build without ACAForest
##   --stress-no-rocks        rock density to zero
##   --stress-no-pond         never roll a pond
##   --stress-forestiness=<f> override the seeded forestiness, 0 - 1
##   --stress-drive           hold the throttle down, report that mowing works
##   --stress-benchmark       measure from fixed viewpoints, append a row, quit
##   --stress-unsafe          build even if the estimate exceeds the safe cap
##   --stress-profile=<name>  system_baseline | production_clear | production_heavy
##   --stress-mode=<name>     static | drive | camera
##   --stress-weather=<name>  Clear | Foggy | Rain  (production profiles only)
##   --stress-hour=<float>    hour of day, 0 - 24   (production profiles only)
##   --stress-seconds=<float> measurement window per viewpoint, in seconds
##   --stress-label=<text>    a build/revision tag written into the CSV
##
## PROFILER 2.0
##   The three ENVIRONMENT PROFILES answer three different questions, and the
##   answers are not interchangeable:
##
##     SYSTEM_BASELINE    a bare sun and a procedural sky. What the property
##                        architecture costs on its own: terrain, lawn, grass,
##                        foliage, with none of the production presentation on
##                        top of it. This is the profile every historical
##                        measurement in `performance.md` was taken with, and
##                        it is unchanged so those numbers stay comparable.
##     PRODUCTION_CLEAR   the REAL `Weather/Preset Manager` scene - the
##                        project's own Sky3D integration, its lighting, its
##                        atmosphere - held at a clear day. What a player
##                        actually sees on a fine morning.
##     PRODUCTION_HEAVY   the same production stack under a legitimately
##                        expensive condition a player will meet: rain, with
##                        its precipitation rig and its heavier atmosphere.
##                        NOT an everything-maximised torture test; a real
##                        weather preset the game ships.
##
##   The three BENCHMARK MODES decide what moves while the frames are counted:
##     STATIC   a parked machine and a fixed camera
##     CAMERA   a repeatable camera path across the property
##     DRIVE    the real mower on a repeatable route, cutting real grass
##
##   Everything else is held constant: seed, size, graphics setting, resolution,
##   route and measurement window. See `docs`/`performance.md`.
##
## WHAT IT IS NOT
##   Not a gameplay scene, not the main scene, and not a promise that giant
##   properties are supported. It is a measuring instrument.
##
## PUBLIC API: None. Everything is exported state or a key press.

# ---------------------------------------------------------------- safe limits
##
## THE UPPER BOUND IS NOT A GUESS, and it is not the texture limit either. It is
## where the MEASURED cost of the near-field grass lands. The placer walks a
## 0.71 unit lattice over the lawn plus its 44 unit margin, so tufts grow as
## (size + 88)^2, and the sweep in the documentation measured every one of them
## at roughly 240 bytes of resident memory and eight microseconds of build time:
##
##     1000 m   2.1 M tufts   20 s to build    0.6 GB
##     1500 m   4.7 M tufts   42 s to build    1.3 GB
##     2000 m   8.3 M tufts   75 s to build    2.2 GB
##
## 2048 is therefore the Inspector's ceiling: it is the last size whose build
## still finishes inside about a minute and a half and fits in something a
## developer machine plausibly has spare. Frame rate is NOT what stops it -
## 2000 m still ran at over a hundred - so a cap chosen on frame rate would be
## the wrong cap.
const MAX_LAWN_SIZE := 2048
const MIN_LAWN_SIZE := 64

## Measured costs, used to predict a build before it runs. Both come from the
## sweep in `validation-and-dev-tools.md` and are checked against the real
## numbers afterwards, so they cannot rot silently.
const BYTES_PER_TUFT := 240
const BYTES_PER_TERRAIN_SAMPLE := 80
## Everything that does not scale with the size: the meshes, the shaders, the
## machine and the engine's own footprint for this scene.
const FIXED_BYTES := 40 << 20

## A build predicted to need more than this is refused outright. Well past the
## 2.2 GB a full 2000 m property really took, and still far enough below a
## typical developer machine to leave it usable.
const MEMORY_BUDGET := 3221225472
## ...and refused as well if the prediction would eat more than this share of
## the memory the machine actually has free RIGHT NOW, which is the check that
## does the work on a smaller machine than the one the numbers above came from.
const AVAILABLE_MEMORY_SHARE := 0.6

# --------------------------------------------------------- placement constants
## Copied from the systems being measured so the ESTIMATE can be made before
## anything is built. They are asserted against the real numbers after the
## build, and a drift is reported, so these can never rot silently.
const GRASS_SPACING := 0.71
const GRASS_MARGIN := 44.0
const TERRAIN_CORE_MARGIN := 22.0
## Share of the placement lattice that survives the meadow thinning, the slope
## test and the feature exclusions. Measured between 0.71 at 256 m and 0.91 at
## 1000 m, because a bigger property is proportionally more kept lawn and less
## thinned meadow.
const TUFT_SURVIVAL := 0.85

const MOWER_SCENE := "res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn"
const PRESET_MANAGER_SCENE := "res://Weather/Preset Manager/Preset Manager.tscn"

## The ORIGINAL results file, still written in its original schema so every
## measurement taken before Profiler 2.0 stays directly comparable with every
## measurement taken after it. Nothing was removed from it.
const RESULTS_FILE := "user://large_lawn_stress_results.csv"
## Profiler 2.0's own file, with the profile, the mode, the frame-time
## percentiles and the rest. A superset, in a separate file, because widening
## the original would have made its history unreadable.
const PROFILE_RESULTS_FILE := "user://profiler2_results.csv"

## How many frames each benchmark viewpoint is held for, and how many are thrown
## away first. The discarded ones are shader compilation, not the scene.
## Profiler 2.0 measures for a fixed DURATION instead; these two remain the
## warm-up policy and the floor on how many frames a window must contain.
const BENCH_FRAMES := 120
const BENCH_WARMUP := 45

## Default measurement window per viewpoint, in seconds. A duration rather than
## a frame count, so a slow configuration and a fast one are given the same
## amount of wall clock and their percentiles mean the same thing.
const MEASURE_SECONDS := 4.0

## Frames discarded at the start of every measurement window, on top of the
## warm-up pass. Covers the first-frame cost of a camera that has just moved.
const SETTLE_FRAMES := 10

enum EnvironmentProfile {
	## A bare sun and a procedural sky. The property, and nothing else.
	SYSTEM_BASELINE,
	## The real production weather/sky stack, held at a clear day.
	PRODUCTION_CLEAR,
	## The same production stack under a real, expensive shipped weather preset.
	PRODUCTION_HEAVY,
}

enum BenchmarkMode {
	## Parked machine, fixed camera positions.
	STATIC,
	## The real mower driving a repeatable route, cutting real grass.
	DRIVE,
	## A repeatable camera path across the property.
	CAMERA,
}

## What PRODUCTION_HEAVY means, unless `--stress-weather=` says otherwise. Rain
## is the most expensive preset the game ships: it carries the precipitation
## rig, the heaviest atmosphere and the darkest sky in one condition a player
## meets on an ordinary contract.
const HEAVY_WEATHER := "Rain"
const CLEAR_WEATHER := "Clear"

enum SizePreset {
	## Use `lawn_size_meters` below. This is the authority; the presets are a
	## convenience and nothing is hard-coded to them.
	INSPECTOR_VALUE,
	M_256,
	M_512,
	M_1000,
	M_1500,
	M_2000,
}

# =============================================================== the controls

@export_group("Size")
## Side of the generated mowable square, in world units. One world unit is one
## logical mowing cell, so this is also the cell count per side.
@export_range(64, 2048, 1) var lawn_size_meters: int = 256
## A shortcut for the common test sizes. INSPECTOR_VALUE leaves the field above
## in charge.
@export var size_preset: SizePreset = SizePreset.INSPECTOR_VALUE
## The property seed. Everything generated is a function of this and the size.
@export var property_seed: int = 20260823
## Build even if the estimate is over the documented budgets. Read the printed
## estimate first.
@export var allow_beyond_safe_limits: bool = false

@export_group("Cost groups")
## Build `ACALawnGrass`. Off leaves the logical lawn, the ground and the wood,
## which is how the turf's share of a size is isolated.
@export var enable_grass: bool = true
## Build `ACAForest` at all: trees, shrubs, reeds and rocks.
@export var enable_forest: bool = true
## Scatter rocks. Ignored when `enable_forest` is off.
@export var enable_rocks: bool = true
## Allow this property to have a pond. Off forces one that the seed rolled to
## be dropped, so the lawn is a plain rectangle.
@export var enable_pond: bool = true
## Override the seeded woodland character. Negative leaves the seed's own draw.
@export_range(-1.0, 1.0, 0.01) var forestiness: float = -1.0

@export_group("Benchmark")
## WHICH PRESENTATION is standing on top of the property while it is measured.
## See the Profiler 2.0 note in the header: the three profiles are not
## interchangeable and a number is meaningless without the profile it came from.
@export var environment_profile: EnvironmentProfile = EnvironmentProfile.SYSTEM_BASELINE
## What MOVES while the frames are counted.
@export var benchmark_mode: BenchmarkMode = BenchmarkMode.STATIC
## Weather preset for the production profiles. Empty follows the profile's own
## default: Clear for PRODUCTION_CLEAR, Rain for PRODUCTION_HEAVY.
@export var benchmark_weather: String = ""
## Hour of day for the production profiles, 0 - 24. Midday by default, because
## a shadow-casting sun overhead is the honest case rather than the cheap one.
@export_range(0.0, 24.0, 0.25) var benchmark_hour: float = 12.0
## Seconds of frames collected per viewpoint, after the warm-up and the settle.
@export_range(0.5, 60.0, 0.5) var measure_seconds: float = MEASURE_SECONDS
## Free text written into the Profiler 2.0 CSV, so a row can be tied back to a
## build. Anything: a backup number, a date, a description of the change.
@export var build_label: String = ""

@export_group("Scene")
## Put the canonical Rider Mower on the property and bind it to the lawn.
@export var spawn_mower: bool = true
## Start on the overview camera rather than in the machine.
@export var start_in_free_camera: bool = false
## Show the measurement overlay from the first frame.
@export var show_hud: bool = true

# ==================================================================== runtime

var _property: ACAProperty = null
var _mower: Node3D = null
var _cutter: ACAMowerCutter = null
var _free_camera: Camera3D = null
var _hud: Label = null
var _hud_layer: CanvasLayer = null

var _size := 256
var _estimate := {}
var _report := {}
var _refused := ""

var _free_camera_active := false
var _free_camera_pitch := 0.0
var _free_camera_yaw := 0.0

## Cells cut in the last second, so the HUD can show that mowing is still
## happening on a lawn far too big to see the progress bar move.
var _recent_cut := 0
var _recent_cut_window := 0.0
var _recent_cut_rate := 0

var _benchmark := false
var _drive_test := false
## The production presentation stack, when a production profile asked for one.
var _preset_manager: Node3D = null
## The weather actually applied. "none" under SYSTEM_BASELINE, which has no
## weather stack at all rather than a clear one.
var _applied_weather := "none"
## One entry per measurement window: the summary of that viewpoint.
var _windows: Array[Dictionary] = []
## CAMERA mode's route, held so `_aim_camera_route` can be passed as a Callable.
var _camera_route: Array[Dictionary] = []
var _progress_ticks := 0
var _progress_seen := 0.0
var _hud_clock := 0.0


func _ready() -> void:
	_read_arguments()
	_size = _resolved_size()

	_build_hud()
	_build_environment()

	_estimate = _estimate_cost(_size)
	_print_estimate()
	_refused = _refusal_reason(_estimate)
	if _refused != "":
		push_warning("[STRESS] %s" % _refused)
		print("[STRESS] REFUSED. Nothing was generated. %s" % _refused)
		print("[STRESS] Set `allow_beyond_safe_limits` (or pass --stress-unsafe) "
			+ "to build it anyway.")
		_update_hud()
		if _benchmark:
			get_tree().quit(1)
		return

	_build_property()
	_build_free_camera()
	if spawn_mower:
		_build_mower()
	_bind_production_environment()
	_free_camera_active = start_in_free_camera or not spawn_mower
	_apply_camera()
	_print_report()
	_append_results_row()
	_append_profile_row()
	_update_hud()

	if _drive_test or _benchmark:
		_run_unattended.call_deferred()


func _process(delta: float) -> void:
	_recent_cut_window += delta
	if _recent_cut_window >= 1.0:
		_recent_cut_rate = _recent_cut
		_recent_cut = 0
		_recent_cut_window = 0.0
	if _free_camera_active:
		_drive_free_camera(delta)
	_hud_clock += delta
	if _hud_clock >= 0.25:
		_hud_clock = 0.0
		_update_hud()


# ================================================================== the build

## The size actually used: the preset when one is chosen, the Inspector field
## otherwise, clamped to the documented range in both cases.
func _resolved_size() -> int:
	var chosen := lawn_size_meters
	match size_preset:
		SizePreset.M_256: chosen = 256
		SizePreset.M_512: chosen = 512
		SizePreset.M_1000: chosen = 1000
		SizePreset.M_1500: chosen = 1500
		SizePreset.M_2000: chosen = 2000
		_: chosen = lawn_size_meters
	if chosen < MIN_LAWN_SIZE or chosen > MAX_LAWN_SIZE:
		# CLAMPED, and said out loud. The refusal path below is for a size that
		# is inside the range and still too expensive; this is for one that is
		# outside the range the Inspector itself documents.
		print("[STRESS] requested %d is outside %d - %d; using %d."
			% [chosen, MIN_LAWN_SIZE, MAX_LAWN_SIZE,
				clampi(chosen, MIN_LAWN_SIZE, MAX_LAWN_SIZE)])
	return clampi(chosen, MIN_LAWN_SIZE, MAX_LAWN_SIZE)


## What this size is going to cost, worked out from the placement constants of
## the systems being measured, BEFORE any of them runs.
func _estimate_cost(size: int) -> Dictionary:
	var cells := size * size
	var near_span := float(size) + GRASS_MARGIN * 2.0
	var candidates := int(pow(near_span / GRASS_SPACING, 2.0))
	var tufts := int(float(candidates) * TUFT_SURVIVAL) if enable_grass else 0
	var core_side := float(size) + TERRAIN_CORE_MARGIN * 2.0
	var triangles := int(core_side * core_side * 2.0)
	var samples := int(pow(near_span + 1.0, 2.0))
	var memory := FIXED_BYTES + tufts * BYTES_PER_TUFT 		+ samples * BYTES_PER_TERRAIN_SAMPLE
	return {
		"cells": cells,
		"lawn_bytes": cells * 2 + cells * 4,
		"grass_instances": tufts,
		"terrain_triangles": triangles,
		"terrain_samples": samples,
		"memory": memory,
	}


## Empty when the build may go ahead.
func _refusal_reason(estimate: Dictionary) -> String:
	if allow_beyond_safe_limits:
		return ""
	var predicted := int(estimate["memory"])
	if predicted > MEMORY_BUDGET:
		return "predicted %s of memory is over the %s debug budget" % [
			_bytes(predicted), _bytes(MEMORY_BUDGET)]
	var available := int(OS.get_memory_info().get("available", 0))
	if available > 0 and float(predicted) > float(available) * AVAILABLE_MEMORY_SHARE:
		return "predicted %s of memory is over %d%% of the %s this machine has free" % [
			_bytes(predicted), int(AVAILABLE_MEMORY_SHARE * 100.0), _bytes(available)]
	return ""


func _print_estimate() -> void:
	print("[STRESS] --------------------------------------------------------")
	print("[STRESS] lawn %d x %d, seed %d" % [_size, _size, property_seed])
	print("[STRESS] estimate: %s logical cells (%s of lawn state)" % [
		_thousands(int(_estimate["cells"])), _bytes(int(_estimate["lawn_bytes"]))])
	print("[STRESS] estimate: %s ground triangles, %s height samples" % [
		_thousands(int(_estimate["terrain_triangles"])),
		_thousands(int(_estimate["terrain_samples"]))])
	print("[STRESS] estimate: %s grass tufts, %s of memory in total (machine has %s free)"
		% [_thousands(int(_estimate["grass_instances"])),
			_bytes(int(_estimate["memory"])),
			_bytes(int(OS.get_memory_info().get("available", 0)))])
	print("[STRESS] groups: grass %s | forest %s | rocks %s | pond %s" % [
		enable_grass, enable_forest, enable_rocks, enable_pond])
	print("[STRESS] profile %s | mode %s | window %.1fs | %s" % [
		profile_name(environment_profile), mode_name(benchmark_mode),
		measure_seconds, _graphics_setting_name()])


## THE REAL PROPERTY, built from real parameters. The only thing the toggles do
## is move parameters the game already has, plus the two development skips on
## ACAProperty itself.
func _build_property() -> void:
	var params := ACAPropertyParams.for_seed(property_seed, _size)
	if forestiness >= 0.0:
		params.forestiness = forestiness
	if not enable_rocks:
		params.rock_density = 0.0
	if not enable_pond:
		params.pond_enabled = false

	_property = ACAProperty.new()
	_property.name = "Property"
	_property.dev_skip_grass = not enable_grass
	_property.dev_skip_foliage = not enable_forest
	add_child(_property)

	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var t0 := Time.get_ticks_usec()
	_property.build(params)
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))

	var stats := _property.statistics()
	var grass: Dictionary = stats.get("grass", {})
	var foliage: Dictionary = stats.get("foliage", {})
	var terrain: Dictionary = stats.get("terrain", {})
	_report = {
		"size": _size,
		"seed": property_seed,
		"grass_enabled": enable_grass,
		"forest_enabled": enable_forest,
		"cells": int(stats.get("lawn_cells", 0)),
		"mowable": int(stats.get("lawn_mowable", 0)),
		"terrain_ms": float(stats.get("terrain_ms", 0.0)),
		"lawn_ms": float(stats.get("lawn_ms", 0.0)),
		"grass_ms": float(stats.get("grass_ms", 0.0)),
		"foliage_ms": float(stats.get("foliage_ms", 0.0)),
		"feature_ms": float(stats.get("features_ms", 0.0))
			+ float(stats.get("feature_nodes_ms", 0.0)),
		"total_ms": build_ms,
		"grass_instances": int(grass.get("instances", 0)),
		"grass_nodes": int(grass.get("nodes", 0)),
		"grass_tiles": int(grass.get("tiles", 0)),
		"foliage_instances": int(foliage.get("instances", 0)),
		"foliage_nodes": int(foliage.get("nodes", 0)),
		"core_triangles": int(terrain.get("core_triangles", 0)),
		"ring_triangles": int(terrain.get("ring_triangles", 0)),
		"terrain_samples": int(terrain.get("samples", 0)),
		"nodes": _count_nodes(_property),
		"bodies": _count_bodies(_property),
		"memory_delta": memory_after - memory_before,
		"memory_after": memory_after,
	}


## The production weather stack has two things it can only be told once the
## property and the machine exist: where the ground is (height fog is measured
## from an absolute world Y) and what the rain should follow. The mowing scene
## does exactly this; a benchmark that skipped it would be measuring fog at the
## wrong altitude and rain in the wrong place.
func _bind_production_environment() -> void:
	if _preset_manager == null:
		return
	var centre := _property.lawn().lawn_centre()
	_preset_manager.call(&"set_weather_ground_reference",
		_property.ground_height_at(centre.x, centre.z))
	var follow: Node3D = _free_camera
	if _mower != null:
		var cam := _mower.get_node_or_null(^"Camera3D") as Node3D
		follow = cam if cam != null else _mower
	if follow != null:
		_preset_manager.call(&"set_weather_tracking_target", follow)


## The canonical machine, arriving where a contract would put it, cutting
## through the same `ACAMowerCutter` the mowing scene uses.
func _build_mower() -> void:
	var packed := load(MOWER_SCENE) as PackedScene
	if packed == null:
		push_warning("[STRESS] no mower at %s" % MOWER_SCENE)
		return
	_mower = packed.instantiate() as Node3D
	add_child(_mower)
	var start := _property.mower_start_transform()
	var scale := _mower.transform.basis.get_scale()
	_mower.global_transform = Transform3D(start.basis.scaled(scale), start.origin)
	# The controller smooths the body's yaw towards a target it captured in its
	# own _ready(), which is the yaw it had BEFORE it was placed here. The
	# mowing scene never notices because its mower is authored already facing
	# the way a property is arrived at; a mower instantiated from the file is
	# not, and without this it spends its first second turning back to face the
	# way the .tscn left it and drives off the property sideways.
	if _mower.get(&"target_body_yaw") != null:
		_mower.set(&"target_body_yaw", _mower.rotation.y)

	_cutter = ACAMowerCutter.new()
	_cutter.name = "Mower Cutter"
	add_child(_cutter)
	_cutter.bind(_mower, _property.lawn())
	if _mower.has_signal(&"collided"):
		_mower.connect(&"collided", _cutter.on_blades_active)
	_cutter.cut.connect(_on_cut)
	print("[STRESS] mower placed at %v, deck %.1f x %.1f" % [
		start.origin, _cutter.deck().half_width * 2.0,
		_cutter.deck().half_length * 2.0])


func _on_cut(cells: int) -> void:
	_recent_cut += cells


# ================================================================ environment

## Which presentation the property is measured underneath. See the Profiler 2.0
## note in the header: SYSTEM_BASELINE is deliberately NOT production, and
## production is deliberately not an approximation of itself.
func _build_environment() -> void:
	match environment_profile:
		EnvironmentProfile.PRODUCTION_CLEAR:
			_build_production_environment(_resolved_weather(CLEAR_WEATHER))
		EnvironmentProfile.PRODUCTION_HEAVY:
			_build_production_environment(_resolved_weather(HEAVY_WEATHER))
		_:
			_build_baseline_environment()


## The weather preset a production profile runs at: the Inspector/command line
## override when one was given, the profile's own default otherwise.
func _resolved_weather(fallback: String) -> String:
	var chosen := benchmark_weather.strip_edges()
	return chosen if not chosen.is_empty() else fallback


## THE REAL THING. `Weather/Preset Manager.tscn` is the project's own Sky3D
## integration - its lighting, its atmosphere, its precipitation rig - and it is
## instantiated here rather than imitated, because an approximation of the
## production environment would measure the approximation.
##
## `follow_world_clock` is switched OFF and the state is applied immediately.
## Two runs of the same profile must light the property identically; a benchmark
## that drifts with the world clock is measuring the time of day.
func _build_production_environment(weather: String) -> void:
	var packed := load(PRESET_MANAGER_SCENE) as PackedScene
	if packed == null:
		push_warning("[STRESS] could not load %s; falling back to the bare sun."
			% PRESET_MANAGER_SCENE)
		_build_baseline_environment()
		return
	_preset_manager = packed.instantiate() as Node3D
	_preset_manager.name = "PresetManager (Sky3D)"
	_preset_manager.set(&"follow_world_clock", false)
	add_child(_preset_manager)
	# _ready() has run by the time add_child returns, so the adapter exists and
	# the state below is applied on top of a bound sky rather than before it.
	_preset_manager.call(&"apply_world_state_immediate", weather,
		clampf(benchmark_hour, 0.0, 24.0))
	_applied_weather = weather
	print("[STRESS] environment: PRODUCTION %s at %04.1f:00" % [weather, benchmark_hour])


## A BARE SUN, on purpose. The weather stack is a large cost of its own and
## measuring it here would blur the thing being measured. What this profile
## reports is the property.
func _build_baseline_environment() -> void:
	_applied_weather = "none"
	print("[STRESS] environment: SYSTEM_BASELINE (bare sun, procedural sky)")
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.0
	var world := WorldEnvironment.new()
	world.name = "Environment"
	world.environment = environment
	add_child(world)


# ===================================================================== camera

## A development overview camera, so a kilometre of lawn can be looked at
## without driving to the far corner. It is a SEPARATE Camera3D; the mower's own
## camera and its controller are untouched.
func _build_free_camera() -> void:
	_free_camera = Camera3D.new()
	_free_camera.name = "Overview Camera"
	_free_camera.fov = 65.0
	# Far enough to see the whole distant landscape at every test size.
	_free_camera.far = 14000.0
	add_child(_free_camera)

	var centre := _property.lawn().lawn_centre()
	var half := _property.lawn().lawn_half_extent()
	var height := _property.ground_height_at(centre.x, centre.z) + half * 1.15 + 30.0
	_free_camera.global_position = Vector3(
		centre.x - half * 1.2, height, centre.z - half * 1.2)
	_free_camera.look_at(Vector3(centre.x, _property.ground_height_at(
		centre.x, centre.z), centre.z), Vector3.UP)
	_free_camera_yaw = _free_camera.rotation.y
	_free_camera_pitch = _free_camera.rotation.x


## While the overview camera is flying, the machine is PAUSED rather than left
## running: the mower steers off mouse motion, and a shared mouse would drive
## it in circles somewhere behind the camera.
func _apply_camera() -> void:
	if _free_camera != null:
		_free_camera.current = _free_camera_active
	if _mower != null:
		_mower.process_mode = Node.PROCESS_MODE_DISABLED if _free_camera_active \
			else Node.PROCESS_MODE_INHERIT
		var mower_camera := _mower.get_node_or_null(^"Camera3D") as Camera3D
		if mower_camera != null and not _free_camera_active:
			mower_camera.current = true
	if _cutter != null and not _free_camera_active:
		# The machine has not moved while the camera was away, but the cutter
		# does not know that; measuring from where it now is costs nothing and
		# cannot stamp a stripe across the property.
		_cutter.resync()
	_set_mouse_captured(true)


func _drive_free_camera(delta: float) -> void:
	if _free_camera == null:
		return
	var speed := 40.0
	if Input.is_key_pressed(KEY_SHIFT):
		speed = 320.0
	if Input.is_key_pressed(KEY_ALT):
		speed = 8.0
	var direction := Vector3.ZERO
	if Input.is_action_pressed(&"move_forward"):
		direction -= _free_camera.global_transform.basis.z
	if Input.is_action_pressed(&"move_back"):
		direction += _free_camera.global_transform.basis.z
	if Input.is_action_pressed(&"move_left"):
		direction -= _free_camera.global_transform.basis.x
	if Input.is_action_pressed(&"move_right"):
		direction += _free_camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL):
		direction -= Vector3.UP
	if direction.length_squared() > 0.0:
		_free_camera.global_position += direction.normalized() * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_F2:
				_free_camera_active = not _free_camera_active
				_apply_camera()
				print("[STRESS] camera: %s" % ("overview" if _free_camera_active
					else "mower"))
			KEY_F3:
				show_hud = not show_hud
				_update_hud()
			KEY_F5:
				_print_report()
			KEY_ESCAPE:
				_set_mouse_captured(Input.get_mouse_mode()
					!= Input.MOUSE_MODE_CAPTURED)
	if _free_camera_active and event is InputEventMouseMotion \
			and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_free_camera_yaw -= motion.relative.x * 0.0025
		_free_camera_pitch = clampf(
			_free_camera_pitch - motion.relative.y * 0.0025, -1.5, 1.5)
		_free_camera.rotation = Vector3(_free_camera_pitch, _free_camera_yaw, 0.0)


func _set_mouse_captured(captured: bool) -> void:
	var mode := Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	var app_ui := get_node_or_null(^"/root/AppUI")
	if app_ui != null and app_ui.has_method(&"set_mouse_context"):
		app_ui.call(&"set_mouse_context", mode)
	else:
		Input.set_mouse_mode(mode)


# ======================================================================== HUD

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "Stress HUD"
	add_child(_hud_layer)
	_hud = Label.new()
	_hud.name = "Readout"
	_hud.position = Vector2(16.0, 16.0)
	_hud.add_theme_color_override(&"font_color", Color(1, 1, 1))
	_hud.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override(&"outline_size", 6)
	_hud_layer.add_child(_hud)


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.visible = show_hud
	if not show_hud:
		return
	if _refused != "":
		_hud.text = "LARGE LAWN STRESS TEST\nREFUSED: %s\nNothing generated." % _refused
		return
	if _property == null:
		return

	var lawn := _property.lawn()
	var lines := PackedStringArray()
	lines.append("LARGE LAWN STRESS TEST     F2 camera   F3 hud   F5 reprint")
	lines.append("fps %6.1f   draw calls %s   primitives %s" % [
		Performance.get_monitor(Performance.TIME_FPS),
		_thousands(int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))),
		_thousands(int(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))])
	lines.append("static memory %s   video memory %s" % [
		_bytes(int(Performance.get_monitor(Performance.MEMORY_STATIC))),
		_bytes(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))])
	lines.append("")
	lines.append("lawn %d x %d m   cells %s   mowable %s   cut %.3f%%" % [
		_size, _size, _thousands(int(_report.get("cells", 0))),
		_thousands(lawn.total_item_count()), lawn.mowed_fraction() * 100.0])
	lines.append("property nodes %s   property bodies %d   cells cut/s %s" % [
		_thousands(int(_report.get("nodes", 0))), int(_report.get("bodies", 0)),
		_thousands(_recent_cut_rate)])
	lines.append("grass %s tufts in %s MultiMesh nodes (%s tiles)" % [
		_thousands(int(_report.get("grass_instances", 0))),
		_thousands(int(_report.get("grass_nodes", 0))),
		_thousands(int(_report.get("grass_tiles", 0)))])
	lines.append("foliage %s instances in %s nodes   ground %s triangles" % [
		_thousands(int(_report.get("foliage_instances", 0))),
		_thousands(int(_report.get("foliage_nodes", 0))),
		_thousands(int(_report.get("core_triangles", 0)))])
	lines.append("")
	lines.append("build: terrain %.0f | lawn %.0f | grass %.0f | foliage %.0f"
		% [_report.get("terrain_ms", 0.0), _report.get("lawn_ms", 0.0),
			_report.get("grass_ms", 0.0), _report.get("foliage_ms", 0.0)])
	lines.append("build total %.0f ms   memory added by build %s" % [
		_report.get("total_ms", 0.0), _bytes(int(_report.get("memory_delta", 0)))])
	_hud.text = "\n".join(lines)


# =================================================================== the report

func _print_report() -> void:
	if _report.is_empty():
		return
	print("[STRESS] --------------------------------------------------------")
	print("[STRESS] BUILT %d x %d in %.0f ms" % [_size, _size,
		_report["total_ms"]])
	print("[STRESS]   terrain %8.1f ms   %s samples, %s core + %s ring triangles"
		% [_report["terrain_ms"], _thousands(int(_report["terrain_samples"])),
			_thousands(int(_report["core_triangles"])),
			_thousands(int(_report["ring_triangles"]))])
	print("[STRESS]   lawn    %8.1f ms   %s cells, %s mowable (%.1f%% excluded)"
		% [_report["lawn_ms"], _thousands(int(_report["cells"])),
			_thousands(int(_report["mowable"])),
			100.0 * (1.0 - float(_report["mowable"])
				/ maxf(float(_report["cells"]), 1.0))])
	print("[STRESS]   grass   %8.1f ms   %s tufts, %s nodes, %s tiles"
		% [_report["grass_ms"], _thousands(int(_report["grass_instances"])),
			_thousands(int(_report["grass_nodes"])),
			_thousands(int(_report["grass_tiles"]))])
	print("[STRESS]   foliage %8.1f ms   %s instances, %s nodes"
		% [_report["foliage_ms"], _thousands(int(_report["foliage_instances"])),
			_thousands(int(_report["foliage_nodes"]))])
	print("[STRESS]   features%8.1f ms" % _report["feature_ms"])
	print("[STRESS]   nodes %s, physics bodies %d, static memory %s (+%s)"
		% [_thousands(int(_report["nodes"])), int(_report["bodies"]),
			_bytes(int(_report["memory_after"])),
			_bytes(int(_report["memory_delta"]))])
	_report_estimate_drift()


## The estimate exists to refuse a build BEFORE it runs, which is only worth
## anything if it resembles what the build then does. Any large disagreement is
## printed, because it means the placement constants copied at the top of this
## file have moved in the systems they were copied from.
## The memory prediction is calibrated on runs WITH A RENDERER. A headless build
## allocates no GPU-side buffers and lands at roughly half of it, which is not a
## drift and is not worth warning about.
func _report_estimate_drift() -> void:
	print("[STRESS]   predicted %s of memory, measured %s (x%.2f)%s" % [
		_bytes(int(_estimate["memory"])), _bytes(int(_report["memory_delta"])),
		float(_report["memory_delta"]) / maxf(float(_estimate["memory"]), 1.0),
		" - headless, no GPU buffers" if DisplayServer.get_name() == "headless"
			else ""])
	if not enable_grass or int(_estimate["grass_instances"]) <= 0:
		return
	var predicted := float(_estimate["grass_instances"])
	var actual := float(_report["grass_instances"])
	var ratio := actual / maxf(predicted, 1.0)
	if ratio < 0.6 or ratio > 1.5:
		print("[STRESS] NOTE: estimated %s tufts, built %s (x%.2f). The "
			% [_thousands(int(predicted)), _thousands(int(actual)), ratio]
			+ "constants at the top of this script may be out of date.")


## One row per run, so two sizes can be compared without reading two logs.
func _append_results_row() -> void:
	var exists := FileAccess.file_exists(RESULTS_FILE)
	var file := FileAccess.open(RESULTS_FILE,
		FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return
	if exists:
		file.seek_end()
	else:
		file.store_line("timestamp,size,seed,grass,forest,cells,mowable,"
			+ "terrain_ms,lawn_ms,grass_ms,foliage_ms,total_ms,grass_instances,"
			+ "grass_nodes,foliage_instances,core_triangles,nodes,bodies,"
			+ "memory_delta,bench_avg_fps,bench_min_fps")
	file.store_line("%s,%d,%d,%s,%s,%d,%d,%.1f,%.1f,%.1f,%.1f,%.1f,%d,%d,%d,%d,%d,%d,%d,%s,%s"
		% [Time.get_datetime_string_from_system(), _size, property_seed,
			enable_grass, enable_forest, int(_report["cells"]),
			int(_report["mowable"]), _report["terrain_ms"], _report["lawn_ms"],
			_report["grass_ms"], _report["foliage_ms"], _report["total_ms"],
			int(_report["grass_instances"]), int(_report["grass_nodes"]),
			int(_report["foliage_instances"]), int(_report["core_triangles"]),
			int(_report["nodes"]), int(_report["bodies"]),
			int(_report["memory_delta"]),
			_report.get("bench_avg_fps", ""), _report.get("bench_min_fps", "")])
	file.close()


## PROFILER 2.0's own row. A superset of the original: everything needed to
## compare two runs without reading two logs, including the things that decide
## whether a comparison is legitimate at all - the environment profile, the
## benchmark mode, the weather, the resolution and the measurement window. Two
## rows whose held-constant columns differ are not each other's before and after.
const PROFILE_HEADER := "timestamp,build_label,seed,lawn_size,profile,mode,weather,hour," \
	+ "resolution,graphics,duration_s,frames,grass,forest,rocks,pond," \
	+ "terrain_ms,lawn_ms,grass_ms,foliage_ms,feature_ms,total_ms," \
	+ "static_memory,memory_delta,video_memory," \
	+ "avg_fps,min_fps,median_ms,p95_ms,p99_ms,draw_calls,primitives," \
	+ "grass_tufts,grass_multimeshes,foliage_instances,ground_triangles," \
	+ "cells,mowable,nodes,bodies"


func _append_profile_row() -> void:
	var exists := FileAccess.file_exists(PROFILE_RESULTS_FILE)
	var file := FileAccess.open(PROFILE_RESULTS_FILE,
		FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return
	if exists:
		file.seek_end()
	else:
		file.store_line(PROFILE_HEADER)
	file.store_line(_profile_row())
	file.close()


func _profile_row() -> String:
	var window := DisplayServer.window_get_size()
	return ",".join(PackedStringArray([
		Time.get_datetime_string_from_system(),
		_csv_text(build_label),
		str(property_seed),
		str(_size),
		profile_name(environment_profile),
		mode_name(benchmark_mode),
		_applied_weather,
		"%.2f" % benchmark_hour,
		"%dx%d" % [window.x, window.y],
		_csv_text(_graphics_setting_name()),
		"%.2f" % measure_seconds,
		str(int(_report.get("bench_frames", 0))),
		str(enable_grass), str(enable_forest), str(enable_rocks), str(enable_pond),
		"%.1f" % float(_report.get("terrain_ms", 0.0)),
		"%.1f" % float(_report.get("lawn_ms", 0.0)),
		"%.1f" % float(_report.get("grass_ms", 0.0)),
		"%.1f" % float(_report.get("foliage_ms", 0.0)),
		"%.1f" % float(_report.get("feature_ms", 0.0)),
		"%.1f" % float(_report.get("total_ms", 0.0)),
		str(int(_report.get("memory_after", 0))),
		str(int(_report.get("memory_delta", 0))),
		str(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))),
		str(_report.get("bench_avg_fps", "")),
		str(_report.get("bench_min_fps", "")),
		_optional_float(_report.get("bench_median_ms", null)),
		_optional_float(_report.get("bench_p95_ms", null)),
		_optional_float(_report.get("bench_p99_ms", null)),
		str(int(_report.get("bench_draw_calls", 0))),
		str(int(_report.get("bench_primitives", 0))),
		str(int(_report.get("grass_instances", 0))),
		str(int(_report.get("grass_nodes", 0))),
		str(int(_report.get("foliage_instances", 0))),
		str(int(_report.get("core_triangles", 0))),
		str(int(_report.get("cells", 0))),
		str(int(_report.get("mowable", 0))),
		str(int(_report.get("nodes", 0))),
		str(int(_report.get("bodies", 0))),
	]))


## The row is written before the benchmark has any numbers, so the frame-time
## columns are filled in by replacing it rather than by appending a second one.
func _rewrite_last_profile_row() -> void:
	var text := ""
	if FileAccess.file_exists(PROFILE_RESULTS_FILE):
		var reader := FileAccess.open(PROFILE_RESULTS_FILE, FileAccess.READ)
		if reader != null:
			text = reader.get_as_text()
			reader.close()
	var lines := text.split("\n", false)
	if lines.size() > 0:
		lines.remove_at(lines.size() - 1)
	var writer := FileAccess.open(PROFILE_RESULTS_FILE, FileAccess.WRITE)
	if writer == null:
		return
	for line in lines:
		writer.store_line(line)
	writer.store_line(_profile_row())
	writer.close()


## The player-facing graphics level this run was measured at, so a row taken on
## Low is never mistaken for one taken on High.
func _graphics_setting_name() -> String:
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings == null or not settings.has_method(&"graphics_quality"):
		return "default"
	return String(settings.call(&"graphics_quality"))


static func _optional_float(value: Variant) -> String:
	return "" if value == null else "%.3f" % float(value)


## Commas and quotes would break the row; free text is the only field that can
## contain either.
static func _csv_text(value: String) -> String:
	return value.replace(",", ";").replace("\"", "'").strip_edges()


# ================================================================ drive check

## THE ONE THING A BENCHMARK CANNOT TELL YOU: whether the machine still drives
## on this ground and still cuts it. So this holds the real `move_forward`
## action down through the real controller, on the real terrain collision, and
## reports what moved and what got cut.
##
## It presses an INPUT ACTION rather than writing the transform, because writing
## the transform would prove nothing about the collision, the fuel or the cutter
## and would happily "pass" on a property with no ground at all.
func _run_drive_test() -> void:
	if _mower == null:
		print("[STRESS DRIVE] no mower in the scene; skipped")
		return
	_free_camera_active = false
	_apply_camera()
	_set_mouse_captured(false)
	# Let the machine settle on to the ground before anything is measured.
	for i in 30:
		await get_tree().process_frame

	var lawn := _property.lawn()
	var start: Vector3 = _mower.global_position
	var cut_before := lawn.mowed_item_count()
	var progress_before := lawn.mowed_fraction()
	var ground_error := 0.0
	# A METHOD, not a lambda: GDScript closures capture locals by value, so a
	# counter incremented inside one is a counter nobody ever reads.
	_progress_ticks = 0
	_progress_seen = progress_before
	lawn.mowing_progress_changed.connect(_on_progress_changed)

	Input.action_press(&"move_forward")
	for i in 300:
		await get_tree().process_frame
		var here: Vector3 = _mower.global_position
		ground_error = maxf(ground_error, absf(here.y
			- _property.ground_height_at(here.x, here.z)))
	Input.action_release(&"move_forward")
	await get_tree().process_frame
	lawn.mowing_progress_changed.disconnect(_on_progress_changed)

	var travelled: float = Vector2(_mower.global_position.x - start.x,
		_mower.global_position.z - start.z).length()
	var cells: int = lawn.mowed_item_count() - cut_before
	print("[STRESS DRIVE] %v -> %v, on the lawn: %s" % [start,
		_mower.global_position, lawn.is_mowable(_mower.global_position)])
	print("[STRESS DRIVE] travelled %.1f units, cut %s cells, progress %.4f%% -> %.4f%% in %d updates"
		% [travelled, _thousands(cells), progress_before * 100.0,
			lawn.mowed_fraction() * 100.0, _progress_ticks])
	print("[STRESS DRIVE] machine stayed within %.2f units of the terrain surface"
		% ground_error)
	print("[STRESS DRIVE] physics bodies in the whole scene: %d (the ground, the "
		% _count_bodies(self) + "machine and its parts - no per-grass bodies)")
	if travelled < 1.0:
		push_warning("[STRESS DRIVE] the machine did not move")
	if cells <= 0:
		push_warning("[STRESS DRIVE] nothing was cut")


## How many times the lawn reported a REAL change in progress while the drive
## test held the throttle down.
func _on_progress_changed(fraction: float) -> void:
	if not is_equal_approx(fraction, _progress_seen):
		_progress_seen = fraction
		_progress_ticks += 1


func _run_unattended() -> void:
	if _drive_test:
		await _run_drive_test()
	if _benchmark:
		await _run_benchmark()
	else:
		get_tree().quit(0)


# ================================================================= benchmark
##
## PROFILER 2.0 METHODOLOGY
##
##     warm-up  ->  settle  ->  fixed measurement window  ->  summary
##
## The warm-up pass visits every viewpoint once with nothing recorded, because
## the first frame from a new angle compiles shader variants and a percentile
## taken across that reports the compiler. The settle discards the first few
## frames of each window for the same reason at a smaller scale. The window
## itself is a DURATION, not a frame count, so a heavy configuration and a light
## one are given the same wall clock and their p95 means the same thing.
##
## Frame TIMES are collected, not frame rates. A rate is the reciprocal of the
## thing that actually varies, and averaging reciprocals hides exactly the
## spikes a p99 exists to find.

## The repeatable set of viewpoints. STATIC holds each in turn; CAMERA flies
## between them. Both are pure functions of the lawn geometry, so the same seed
## and size always looks at the same things.
func _benchmark_viewpoints() -> Array[Dictionary]:
	var lawn := _property.lawn()
	var centre := lawn.lawn_centre()
	var half := lawn.lawn_half_extent()
	var ground := _property.ground_height_at(centre.x, centre.z)
	var shots: Array[Dictionary] = [
		{
			"name": "mower-eye",
			"from": Vector3(centre.x - half + 6.0,
				_property.ground_height_at(centre.x - half + 6.0, centre.z) + 4.0,
				centre.z),
			"at": Vector3(centre.x, ground + 2.0, centre.z),
		},
		{
			"name": "mid-lawn",
			"from": Vector3(centre.x, ground + 4.0, centre.z),
			"at": Vector3(centre.x + half, ground + 2.0, centre.z),
		},
		{
			"name": "overview",
			"from": Vector3(centre.x - half * 1.2, ground + half * 1.15 + 30.0,
				centre.z - half * 1.2),
			"at": Vector3(centre.x, ground, centre.z),
		},
	]
	return shots


func _run_benchmark() -> void:
	_set_mouse_captured(false)
	var shots := _benchmark_viewpoints()

	# EVERY VIEWPOINT IS VISITED ONCE WITH NOTHING RECORDED.
	_free_camera_active = true
	_apply_camera()
	for shot in shots:
		_aim_free_camera(shot["from"], shot["at"])
		for i in BENCH_WARMUP:
			await get_tree().process_frame

	match benchmark_mode:
		BenchmarkMode.DRIVE:
			await _benchmark_drive(shots)
		BenchmarkMode.CAMERA:
			await _benchmark_camera(shots)
		_:
			await _benchmark_static(shots)

	_summarise_windows()
	_rewrite_last_results_row()
	_rewrite_last_profile_row()
	print("[STRESS] benchmark done (%s / %s)"
		% [profile_name(environment_profile), mode_name(benchmark_mode)])
	get_tree().quit(0)


func _aim_free_camera(from: Vector3, at: Vector3) -> void:
	_free_camera.global_position = from
	_free_camera.look_at(at, Vector3.UP)


## STATIC: each viewpoint held still for its own window.
func _benchmark_static(shots: Array[Dictionary]) -> void:
	for shot in shots:
		_aim_free_camera(shot["from"], shot["at"])
		await _measure_window(String(shot["name"]), Callable())


## CAMERA: one continuous window while the camera walks the same path through
## the viewpoints, at a speed set by the elapsed fraction of the window rather
## than by a per-frame step, so the route is identical whatever the frame rate.
func _benchmark_camera(shots: Array[Dictionary]) -> void:
	if shots.size() < 2:
		await _benchmark_static(shots)
		return
	_camera_route = shots
	_aim_camera_route(0.0)
	await _measure_window("camera-path", _aim_camera_route)


## CAMERA mode's route, as a method rather than a lambda so it can be handed to
## `_measure_window` as a Callable without capturing anything by value.
func _aim_camera_route(t: float) -> void:
	var legs: int = _camera_route.size() - 1
	if legs <= 0:
		return
	var scaled: float = clampf(t, 0.0, 0.9999) * float(legs)
	var leg: int = clampi(int(floor(scaled)), 0, legs - 1)
	var f: float = scaled - float(leg)
	var a: Dictionary = _camera_route[leg]
	var b: Dictionary = _camera_route[leg + 1]
	_aim_free_camera(
		(a["from"] as Vector3).lerp(b["from"] as Vector3, f),
		(a["at"] as Vector3).lerp(b["at"] as Vector3, f))


## DRIVE: the REAL machine on the REAL controller, throttle held down, measured
## through its own camera. This is the only mode whose frames include the cost
## of cutting grass, because it is the only one where any is being cut.
func _benchmark_drive(shots: Array[Dictionary]) -> void:
	if _mower == null:
		print("[STRESS] DRIVE mode asked for with no mower; measuring STATIC instead.")
		await _benchmark_static(shots)
		return
	_free_camera_active = false
	_apply_camera()
	# The machine is put back at the arrival transform so the route is the same
	# route every run, whatever a previous phase left it doing.
	var start := _property.mower_start_transform()
	var mower_scale := _mower.transform.basis.get_scale()
	_mower.global_transform = Transform3D(start.basis.scaled(mower_scale), start.origin)
	if _mower.get(&"target_body_yaw") != null:
		_mower.set(&"target_body_yaw", _mower.rotation.y)
	for i in 30:
		await get_tree().process_frame

	Input.action_press("move_forward")
	await _measure_window("drive", Callable())
	Input.action_release("move_forward")
	print("[STRESS DRIVE] %s cells cut by the end of the measured window"
		% _thousands(_property.lawn().mowed_item_count()))


## ONE measurement window. `per_frame` (optional) is called with the 0-1
## progress through the window before each frame is awaited, which is how the
## camera route moves without the movement depending on the frame rate.
func _measure_window(label: String, per_frame: Callable) -> void:
	# THE FRAME CAP IS LIFTED FOR THE WINDOW. The project ships `max_fps = 240`,
	# which is a sensible thing for a game to do and useless for a benchmark:
	# every frame cheaper than 4.17 ms comes back as exactly 4.17 ms, so a
	# configuration twice as fast as another measures identically to it.
	var previous_cap := Engine.max_fps
	Engine.max_fps = 0
	for i in SETTLE_FRAMES:
		await get_tree().process_frame

	var times := PackedFloat64Array()
	var draws := 0
	var primitives := 0
	var started := Time.get_ticks_usec()
	var window_us := int(maxf(measure_seconds, 0.1) * 1000000.0)
	var guard := window_us * 4
	var last := Time.get_ticks_usec()
	while true:
		var elapsed := Time.get_ticks_usec() - started
		if elapsed >= window_us:
			break
		if elapsed >= guard:
			break
		if per_frame.is_valid():
			per_frame.call(float(elapsed) / float(window_us))
		await get_tree().process_frame
		# WALL TIME BETWEEN FRAMES, not `Performance.TIME_FPS`. That monitor is
		# a smoothed value the engine refreshes about once a second, so every
		# sample inside a window comes back identical and the p95 and the median
		# are the same number - which is exactly the measurement a percentile
		# exists to avoid. This is the real interval, per frame.
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		last = now
		if frame_ms <= 0.0:
			continue
		times.append(frame_ms)
		draws = maxi(draws, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives = maxi(primitives, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))

	Engine.max_fps = previous_cap
	if times.is_empty():
		print("[STRESS FPS] %-12s no frames measured" % label)
		return
	var sorted_times := times.duplicate()
	sorted_times.sort()
	var window := {
		"name": label,
		"frames": times.size(),
		"avg_fps": 1000.0 / _mean(times),
		"min_fps": 1000.0 / sorted_times[sorted_times.size() - 1],
		"median_ms": _percentile(sorted_times, 0.50),
		"p95_ms": _percentile(sorted_times, 0.95),
		"p99_ms": _percentile(sorted_times, 0.99),
		"draw_calls": draws,
		"primitives": primitives,
	}
	_windows.append(window)
	print("[STRESS FPS] %-12s avg %6.1f fps  med %5.2f  p95 %5.2f  p99 %5.2f ms  draws %s  prims %s"
		% [label, window["avg_fps"], window["median_ms"], window["p95_ms"],
			window["p99_ms"], _thousands(draws), _thousands(primitives)])


## The run's headline numbers. Percentiles are taken from the WORST window
## rather than averaged across the windows, because an average of percentiles is
## not a percentile of anything, and a benchmark exists to find the condition
## that hurts rather than to dilute it.
func _summarise_windows() -> void:
	if _windows.is_empty():
		return
	var total_frames := 0
	var weighted_ms := 0.0
	var worst_fps := INF
	var draws := 0
	var primitives := 0
	var medians := PackedFloat64Array()
	var p95s := PackedFloat64Array()
	var p99s := PackedFloat64Array()
	for w in _windows:
		total_frames += int(w["frames"])
		weighted_ms += (1000.0 / float(w["avg_fps"])) * float(w["frames"])
		worst_fps = minf(worst_fps, float(w["min_fps"]))
		draws = maxi(draws, int(w["draw_calls"]))
		primitives = maxi(primitives, int(w["primitives"]))
		medians.append(float(w["median_ms"]))
		p95s.append(float(w["p95_ms"]))
		p99s.append(float(w["p99_ms"]))
	medians.sort()
	p95s.sort()
	p99s.sort()

	_report["bench_avg_fps"] = "%.1f" % (1000.0 / (weighted_ms / float(maxi(total_frames, 1))))
	_report["bench_min_fps"] = "%.1f" % worst_fps
	_report["bench_median_ms"] = _percentile(medians, 0.50)
	_report["bench_p95_ms"] = p95s[p95s.size() - 1]
	_report["bench_p99_ms"] = p99s[p99s.size() - 1]
	_report["bench_draw_calls"] = draws
	_report["bench_primitives"] = primitives
	_report["bench_frames"] = total_frames
	print("[STRESS FPS] %d x %d %s / %s: avg %s fps, worst %s fps, median %.2f ms, p95 %.2f, p99 %.2f"
		% [_size, _size, profile_name(environment_profile), mode_name(benchmark_mode),
			_report["bench_avg_fps"], _report["bench_min_fps"],
			_report["bench_median_ms"], _report["bench_p95_ms"], _report["bench_p99_ms"]])


static func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


## Nearest-rank on an ALREADY SORTED array.
static func _percentile(sorted_values: PackedFloat64Array, q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := int(ceil(clampf(q, 0.0, 1.0) * float(sorted_values.size()))) - 1
	return sorted_values[clampi(index, 0, sorted_values.size() - 1)]


static func profile_name(value: int) -> String:
	match value:
		EnvironmentProfile.PRODUCTION_CLEAR:
			return "PRODUCTION_CLEAR"
		EnvironmentProfile.PRODUCTION_HEAVY:
			return "PRODUCTION_HEAVY"
		_:
			return "SYSTEM_BASELINE"


static func mode_name(value: int) -> String:
	match value:
		BenchmarkMode.DRIVE:
			return "DRIVE"
		BenchmarkMode.CAMERA:
			return "CAMERA"
		_:
			return "STATIC"


## The results row was written before the benchmark had numbers. Replace it
## rather than appending a second, near-identical row.
func _rewrite_last_results_row() -> void:
	var text := ""
	if FileAccess.file_exists(RESULTS_FILE):
		var reader := FileAccess.open(RESULTS_FILE, FileAccess.READ)
		if reader != null:
			text = reader.get_as_text()
			reader.close()
	var lines := text.split("\n", false)
	if lines.size() > 0:
		lines.remove_at(lines.size() - 1)
	var writer := FileAccess.open(RESULTS_FILE, FileAccess.WRITE)
	if writer == null:
		return
	for line in lines:
		writer.store_line(line)
	writer.close()
	_append_results_row()


# ================================================================== arguments

func _read_arguments() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--stress-size="):
			lawn_size_meters = arg.trim_prefix("--stress-size=").to_int()
			size_preset = SizePreset.INSPECTOR_VALUE
		elif arg.begins_with("--stress-seed="):
			property_seed = arg.trim_prefix("--stress-seed=").to_int()
		elif arg.begins_with("--stress-forestiness="):
			forestiness = arg.trim_prefix("--stress-forestiness=").to_float()
		elif arg == "--stress-no-grass":
			enable_grass = false
		elif arg == "--stress-no-forest":
			enable_forest = false
		elif arg == "--stress-no-rocks":
			enable_rocks = false
		elif arg == "--stress-no-pond":
			enable_pond = false
		elif arg == "--stress-no-mower":
			spawn_mower = false
		elif arg == "--stress-unsafe":
			allow_beyond_safe_limits = true
		elif arg == "--stress-benchmark":
			_benchmark = true
		elif arg == "--stress-drive":
			_drive_test = true
		elif arg.begins_with("--stress-profile="):
			environment_profile = _parse_profile(
				arg.trim_prefix("--stress-profile="))
		elif arg.begins_with("--stress-mode="):
			benchmark_mode = _parse_mode(arg.trim_prefix("--stress-mode="))
		elif arg.begins_with("--stress-weather="):
			benchmark_weather = arg.trim_prefix("--stress-weather=").strip_edges()
		elif arg.begins_with("--stress-hour="):
			benchmark_hour = arg.trim_prefix("--stress-hour=").to_float()
		elif arg.begins_with("--stress-seconds="):
			measure_seconds = maxf(arg.trim_prefix("--stress-seconds=").to_float(), 0.5)
		elif arg.begins_with("--stress-label="):
			build_label = arg.trim_prefix("--stress-label=").strip_edges()


## An unknown name is reported and the default kept, rather than silently
## measuring something other than what was asked for.
func _parse_profile(text: String) -> EnvironmentProfile:
	match text.strip_edges().to_lower():
		"production_clear", "clear", "production":
			return EnvironmentProfile.PRODUCTION_CLEAR
		"production_heavy", "heavy":
			return EnvironmentProfile.PRODUCTION_HEAVY
		"system_baseline", "baseline", "system":
			return EnvironmentProfile.SYSTEM_BASELINE
		_:
			push_warning("[STRESS] unknown profile '%s'; keeping %s"
				% [text, profile_name(environment_profile)])
			return environment_profile


func _parse_mode(text: String) -> BenchmarkMode:
	match text.strip_edges().to_lower():
		"drive":
			return BenchmarkMode.DRIVE
		"camera":
			return BenchmarkMode.CAMERA
		"static":
			return BenchmarkMode.STATIC
		_:
			push_warning("[STRESS] unknown mode '%s'; keeping %s"
				% [text, mode_name(benchmark_mode)])
			return benchmark_mode


# ==================================================================== helpers

func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _count_bodies(node: Node) -> int:
	var total := 1 if node is PhysicsBody3D else 0
	for child in node.get_children():
		total += _count_bodies(child)
	return total


static func _thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	out = text + out
	return ("-" + out) if value < 0 else out


static func _bytes(value: int) -> String:
	var v := float(value)
	if absf(v) < 1024.0:
		return "%d B" % value
	if absf(v) < 1024.0 * 1024.0:
		return "%.1f KB" % (v / 1024.0)
	if absf(v) < 1024.0 * 1024.0 * 1024.0:
		return "%.1f MB" % (v / (1024.0 * 1024.0))
	return "%.2f GB" % (v / (1024.0 * 1024.0 * 1024.0))
