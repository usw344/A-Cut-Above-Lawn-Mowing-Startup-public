extends Node3D
## ROLE
## Host for a REGIONAL SERVICE LOT - the Business Town's counterpart in every
## territory the business has expanded into.
##
## It is the same screen as the Town in every way that matters to the rest of
## the application: `GameSession` still calls it `Screen.TOWN`, the job board is
## the same board, the services panel is the same panel, saving works from here,
## and a finished contract returns here. What changes is the ground under it.
##
## ---------------------------------------------------------------------------
## IT REUSES THE TOWN'S OWN MACHINERY
## ---------------------------------------------------------------------------
## `ACABusinessTown` is the controller: picking, hover, selection, the camera
## focus and the HUD binding all live there and are entirely generic - it takes
## a camera rig, a HUD and a root of `ACAInteractiveBuilding`s and does not care
## where they came from. So this screen builds those three things around an
## `ACARegionalHub` and hands them over.
##
## That is the whole reason there is no second interaction system, no second
## job-board binding and no second building panel in the project.
##
## PUBLIC API
##   hub() -> ACARegionalHub
##
## SIGNALS: None of its own.
##
## PERSISTENCE OWNERSHIP
##   None. `ACAServiceTerritory` owns which region the player is in.

const CLOCK_REFRESH_INTERVAL := 0.5
const HUD_SCENE := "res://Main Area/ACA_BusinessTown/UI/BusinessHUD.tscn"

@onready var _pause_layer: ACAPauseLayer = $"Pause Layer"

var _hub: ACARegionalHub = null
var _controller: ACABusinessTown = null
var _hud: ACABusinessHUD = null
var _camera: ACABusinessCamera = null
var _services: ACABusinessServices = null
var _lights: ACATownLightAdapter = null
var _clock_refresh_accumulator: float = 0.0


func _ready() -> void:
	# Free cursor, like the Town: buildings are hovered and clicked.
	AppUI.set_mouse_context(Input.MOUSE_MODE_VISIBLE)

	_build_environment()
	_build_hub()
	_build_camera()
	_build_hud()
	_build_controller()
	_setup_pause()
	_setup_lighting()
	_refresh_readouts()

	GameSession.money_changed.connect(_on_money_changed)


func hub() -> ACARegionalHub:
	return _hub


# ======================================================================= build

## THE TOWN'S OWN LIGHTING, VALUES AND ALL. Copied rather than shared because
## `BusinessTown.tscn` owns its environment as a sub-resource; what matters is
## that a hub is lit like the town, so `ACATownLightAdapter` can drive both from
## the same world clock and the two never look like different games.
func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.29, 0.478, 0.729)
	sky_material.sky_horizon_color = Color(0.796, 0.851, 0.878)
	sky_material.sky_curve = 0.14
	sky_material.ground_bottom_color = Color(0.451, 0.478, 0.451)
	sky_material.ground_horizon_color = Color(0.769, 0.808, 0.82)
	sky_material.sun_angle_max = 24.0
	sky_material.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 5.0
	environment.ssao_enabled = true
	environment.ssao_radius = 0.65
	environment.ssao_intensity = 1.5
	environment.ssao_power = 1.7
	environment.ssao_light_affect = 0.25
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.01
	environment.adjustment_contrast = 1.03
	environment.adjustment_saturation = 1.06

	var holder := WorldEnvironment.new()
	holder.name = "WorldEnvironment"
	holder.environment = environment
	add_child(holder)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1, 0.945, 0.851)
	sun.light_energy = 1.5
	sun.shadow_enabled = false
	sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color(0.706, 0.788, 0.902)
	fill.light_energy = 0.3
	fill.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-150.0), 0.0)
	add_child(fill)


func _build_hub() -> void:
	_hub = ACARegionalHub.new()
	_hub.name = "Regional Hub"
	add_child(_hub)
	_hub.build(Territory.active_region())


func _build_camera() -> void:
	_camera = ACABusinessCamera.new()
	_camera.name = "CameraRig"
	_camera.boom_length = 80.0
	_camera.overview_pivot = _hub.camera_pivot()
	_camera.overview_size = _hub.camera_size()
	_camera.overview_min_width = _hub.camera_min_width()
	var lens := Camera3D.new()
	lens.name = "Camera3D"
	lens.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.add_child(lens)
	_camera.camera = lens
	_camera.position = _hub.camera_pivot()
	add_child(_camera)


func _build_hud() -> void:
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		push_error("Regional Hub: could not load %s" % HUD_SCENE)
		return
	_hud = packed.instantiate() as ACABusinessHUD
	if _hud == null:
		return
	add_child(_hud)


## `ACABusinessTown` as a plain controller: no town in the scene, the same
## picking and selection over this hub's buildings.
func _build_controller() -> void:
	_controller = ACABusinessTown.new()
	_controller.name = "Hub Controller"
	_controller.camera_rig = _camera
	_controller.hud = _hud
	_controller.buildings_root = _hub.destinations_root()
	# The host opens all four of these with a real screen; nothing here should
	# ever get the town's "coming soon" placeholder.
	_controller.host_handled_buildings = [
		&"supply_store", &"business_hq", &"mower_dealer", &"service_lot",
	]
	add_child(_controller)
	_controller.business_action_requested.connect(_on_business_action)


func _ensure_services() -> ACABusinessServices:
	if _services != null and is_instance_valid(_services):
		return _services
	_services = ACABusinessServices.new()
	_services.name = "Business Services"
	var layer := CanvasLayer.new()
	layer.name = "Business Services Layer"
	layer.layer = 6
	layer.add_child(_services)
	add_child(layer)
	return _services


func _setup_pause() -> void:
	var job := GameSession.current_job()
	if job != null:
		_pause_layer.set_pause_context("Contract open: %s" % job.job_site)
	else:
		_pause_layer.set_pause_context(
			ACAServiceTerritory.region_name(Territory.active_region()))
	_pause_layer.set_pause_option_enabled(&"restart", false)
	_pause_layer.set_pause_option_enabled(&"abandon", job != null)


func _setup_lighting() -> void:
	var environment := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	var sun := get_node_or_null(^"Sun") as DirectionalLight3D
	var fill := get_node_or_null(^"FillLight") as DirectionalLight3D
	if environment == null or sun == null:
		return
	_lights = ACATownLightAdapter.new()
	_lights.name = "Hub Light Adapter"
	add_child(_lights)
	_lights.bind(environment, sun, fill)
	# THE REGION'S OWN AIR, before the first frame is composed. It is a standing
	# difference between places - haze over a trade park, clear air over open
	# country - and NOT a second weather system: the sky the clock scheduled is
	# still the sky, in every region, at the same moment.
	if _hub != null:
		var air: Dictionary = _hub.region_air()
		_lights.set_region_air(air["tint"], float(air["haze"]))
	_lights.apply_immediate(WorldClock.weather_preset(), WorldClock.hour_of_day())
	WorldClock.weather_changed.connect(_on_weather_changed)


# ==================================================================== readouts

func _process(delta: float) -> void:
	_clock_refresh_accumulator += delta
	if _clock_refresh_accumulator < CLOCK_REFRESH_INTERVAL:
		return
	_clock_refresh_accumulator = 0.0
	_refresh_calendar()
	if _lights != null:
		_lights.set_state(WorldClock.weather_preset(), WorldClock.hour_of_day())


func _on_weather_changed(preset: String) -> void:
	if _lights != null:
		_lights.set_state(preset, WorldClock.hour_of_day())


func _refresh_readouts() -> void:
	if _hud == null:
		return
	_hud.set_funds(GameSession.money())
	_hud.set_hint("%s - click a location to visit it"
		% ACAServiceTerritory.region_name(Territory.active_region()))
	_refresh_calendar()


func _refresh_calendar() -> void:
	if _hud == null:
		return
	_hud.set_calendar(
		WorldClock.day_number(), WorldClock.clock_text(), WorldClock.weather_preset())


func _on_money_changed(amount: int) -> void:
	if _hud != null:
		_hud.set_funds(amount)


func _on_business_action(action: StringName) -> void:
	if ACABusinessServices.handles(action):
		_ensure_services().open_service(action)
		return
	# `job_office` is handled by the controller, which opens the job board.
