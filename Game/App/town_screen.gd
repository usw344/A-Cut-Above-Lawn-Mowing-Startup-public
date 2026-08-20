extends Node3D
## Host for the Business Town.
##
## The town package stays self-contained: it reports what the player asked for
## and this host supplies real game state to its readouts. Job routing itself
## already happens inside the town (Job Office -> its embedded Job Board, which
## is bound to the JobManager autoload), so this host only feeds the HUD and
## handles the destinations the town cannot serve yet.

const CLOCK_REFRESH_INTERVAL := 0.5

@onready var _town: ACABusinessTown = $BusinessTown
## The shared pause stack. Same component set the mowing screen uses; it sits
## FIRST in the tree so the town gets Escape before it does - closing a building
## panel or clearing a selection takes priority over opening the pause menu.
@onready var _pause_layer: ACAPauseLayer = $"Pause Layer"

## Set false to put the town back to its authored lighting with no other
## change. See Weather/Visual/town_light_adapter.gd.
@export var light_from_world_clock: bool = true

var _hud: ACABusinessHUD
var _clock_refresh_accumulator: float = 0.0
var _lights: ACATownLightAdapter = null
var _services: ACABusinessServices = null


func _ready() -> void:
	# The town is played with a free cursor: buildings are hovered and clicked.
	# Resuming from pause has to come back to THIS, not to a captured cursor.
	AppUI.set_mouse_context(Input.MOUSE_MODE_VISIBLE)
	_hud = _town.hud

	_town.business_action_requested.connect(_on_business_action)

	GameSession.money_changed.connect(_on_money_changed)

	_setup_pause()
	_setup_lighting()
	_refresh_readouts()


## R-013. The town keeps its own authored WorldEnvironment, SSAO and grading;
## only light colour/energy, the procedural sky gradient, ambient, exposure and
## fog are driven from the world clock. Day is the authored look unchanged.
## The services panel is built on first use. It is a whole UI that most visits
## to the town never open, and creating it up front would cost every player the
## work whether or not they ever walk into a shop.
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


func _setup_lighting() -> void:
	if not light_from_world_clock:
		return
	var environment := _town.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	var sun := _town.get_node_or_null(^"Sun") as DirectionalLight3D
	var fill := _town.get_node_or_null(^"FillLight") as DirectionalLight3D
	if environment == null or sun == null:
		push_warning("Town Screen: expected WorldEnvironment + Sun in BusinessTown.")
		return
	_lights = ACATownLightAdapter.new()
	_lights.name = "Town Light Adapter"
	add_child(_lights)
	_lights.bind(environment, sun, fill)
	_lights.apply_immediate(WorldClock.weather_preset(), WorldClock.hour_of_day())
	WorldClock.weather_changed.connect(_on_weather_changed)


## RESTART is a mowing action - there is no lawn on this screen, so it is never
## available here. ABANDON is available only when a contract is actually open.
## Neither is left enabled emitting intent nothing can service.
func _setup_pause() -> void:
	var job := GameSession.current_job()
	if job != null:
		_pause_layer.set_pause_context("Contract open: %s" % job.job_site)
	else:
		_pause_layer.set_pause_context("Business Town")
	_pause_layer.set_pause_option_enabled(&"restart", false)
	_pause_layer.set_pause_option_enabled(&"abandon", job != null)


## The clock ticks every frame; refreshing the label at 2 Hz is plenty and keeps
## the town off the per-frame path.
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
	# job_office is handled by the town itself (it opens the Job Board).
	# supply_store / business_hq / mower_dealer open the real services panel.
	# future_lot is still a placeholder, because there really is nothing there.
	if ACABusinessServices.handles(action):
		_ensure_services().open_service(action)
		return
	if action != &"job_office":
		return
