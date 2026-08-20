class_name ACAWorldClock
extends Node
## THE authoritative world clock. Autoloaded as `WorldClock`.
##
## One clock for the whole application. It survives every scene change, so
## Town -> Mowing -> Town never resets time. Scenes ADAPT TO IT; they never own
## a clock of their own and they never write to it except through the API here.
##
##     WorldClock  (absolute game minutes, season, weather preset)
##         |
##         +--> ACAWorldClockTimeProvider --> ACAJobManager   (offers, expiry)
##         |
##         +--> scene adapters ------------> preset_manager --> Sky3D / Rain Handler
##
## Weather lives here rather than in a separate autoload because the only thing
## the application needs to persist is "which preset is current". The Preset
## Manager remains the project-facing sky/weather adapter and is not replaced.

# ------------------------------------------------------------------- signals
## Emitted every process frame the clock advances. Cheap listeners only.
signal time_changed(game_minutes: float)
## Emitted when the whole-day index rolls over.
signal day_changed(day_index: int)
signal season_changed(season: int)
## `preset` is one of WEATHER_PRESETS.
signal weather_changed(preset: String)
signal running_changed(running: bool)

# ------------------------------------------------------------------ constants
## The names the Weather Preset Manager understands. Do not add a preset here
## without adding it to preset_manager.apply_weather_preset().
const WEATHER_PRESETS: PackedStringArray = ["Clear", "Foggy", "Rain"]

## Game minutes at the start of a brand new game: 08:00 on day 0.
const NEW_GAME_START_MINUTES := 8.0 * 60.0

# -------------------------------------------------------------------- tuning
## THE ONE TIME-SCALE VALUE. Game minutes that pass per real second while the
## clock runs. 6.0 => one 24h game day takes four real minutes. Everything
## time-related in the project derives from this; do not hard-code conversions
## anywhere else.
@export var game_minutes_per_real_second: float = 6.0

# --------------------------------------------------------------------- state
var _minutes: float = NEW_GAME_START_MINUTES
var _running: bool = false
var _day_index: int = 0
var _season: ACAJobEnums.Season = ACAJobEnums.Season.SPRING
var _weather: String = "Clear"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_day_index = ACAGameTime.day_index(_minutes)


func _process(delta: float) -> void:
	if not _running:
		return
	_minutes += delta * maxf(game_minutes_per_real_second, 0.0)
	time_changed.emit(_minutes)
	var day := ACAGameTime.day_index(_minutes)
	if day != _day_index:
		_day_index = day
		day_changed.emit(_day_index)


# ============================================================= session control

## Reset to a fresh world and start running. Called by GameSession.start_new_game().
func start_new_world(start_minutes: float = NEW_GAME_START_MINUTES) -> void:
	_minutes = start_minutes
	_day_index = ACAGameTime.day_index(_minutes)
	set_season(ACAJobEnums.Season.SPRING)
	set_weather("Clear")
	_running = true
	running_changed.emit(true)
	time_changed.emit(_minutes)


func set_running(value: bool) -> void:
	if _running == value:
		return
	_running = value
	running_changed.emit(_running)


func is_running() -> bool:
	return _running


# ==================================================================== reading

## Absolute game minutes since the world epoch. Monotonically non-decreasing
## while running; may jump forward on load or dev fast-forward.
func game_minutes() -> float:
	return _minutes


## 0.0 - 23.99, the form Sky3D current_time wants.
func hour_of_day() -> float:
	var into_day := fposmod(_minutes, ACAJobBalance.MINUTES_PER_DAY)
	return clampf(into_day / ACAJobBalance.MINUTES_PER_HOUR, 0.0, 23.99)


## Whole days elapsed since the epoch, 0-based.
func day_index() -> int:
	return _day_index


## Player-facing day number, 1-based.
func day_number() -> int:
	return _day_index + 1


## "09:41"
func clock_text() -> String:
	return ACAGameTime.format_clock(_minutes)


## "Spring Day 12  09:15"
func timestamp_text() -> String:
	return "%s Day %d  %s" % [
		ACAJobEnums.season_name(_season),
		ACAGameTime.day_of_season(_minutes),
		clock_text(),
	]


func season() -> int:
	return _season


func set_season(value: int) -> void:
	if _season == value:
		return
	_season = value
	season_changed.emit(_season)


# ==================================================================== weather

## Current weather preset name. This is the persistent application state that
## scenes read on load; the Preset Manager applies it to Sky3D.
func weather_preset() -> String:
	return _weather


func set_weather(preset: String) -> void:
	if not WEATHER_PRESETS.has(preset):
		push_warning("WorldClock: unknown weather preset %s ignored" % preset)
		return
	if _weather == preset:
		return
	_weather = preset
	weather_changed.emit(_weather)


func cycle_weather() -> String:
	var i := WEATHER_PRESETS.find(_weather)
	set_weather(WEATHER_PRESETS[(i + 1) % WEATHER_PRESETS.size()])
	return _weather


# =============================================================== time control

## Jump the clock forward. Safe: every consumer compares absolute times instead
## of accumulating deltas, so jumps are tolerated by design.
func advance_minutes(minutes: float) -> void:
	if minutes <= 0.0:
		return
	_minutes += minutes
	time_changed.emit(_minutes)
	var day := ACAGameTime.day_index(_minutes)
	if day != _day_index:
		_day_index = day
		day_changed.emit(_day_index)


func advance_hours(hours: float) -> void:
	advance_minutes(hours * ACAJobBalance.MINUTES_PER_HOUR)


## Jump to the next occurrence of `hour` (0.0 - 23.99). Forward only, because
## every consumer relies on the clock never running backwards - if the hour has
## already passed today it lands on tomorrow. Used by the development
## time-of-day controls and by the trailer's deterministic setup.
func advance_to_hour(hour: float) -> void:
	var target := clampf(hour, 0.0, 23.99) * ACAJobBalance.MINUTES_PER_HOUR
	var into_day := fposmod(_minutes, ACAJobBalance.MINUTES_PER_DAY)
	var delta := target - into_day
	if delta <= 0.0:
		delta += ACAJobBalance.MINUTES_PER_DAY
	advance_minutes(delta)


# =================================================================== persistence
## Consumed by the save system. Plain built-in types only.

func to_save_dict() -> Dictionary:
	return {
		"minutes": _minutes,
		"season": int(_season),
		"weather": _weather,
		"running": _running,
		"minutes_per_real_second": game_minutes_per_real_second,
	}


func from_save_dict(data: Dictionary) -> void:
	_minutes = float(data.get("minutes", NEW_GAME_START_MINUTES))
	_day_index = ACAGameTime.day_index(_minutes)
	game_minutes_per_real_second = float(
		data.get("minutes_per_real_second", game_minutes_per_real_second))
	set_season(int(data.get("season", ACAJobEnums.Season.SPRING)))

	# set_weather() early-returns when the value already matches, which would
	# skip the signal listeners need on load. Force the emit.
	var loaded_weather := String(data.get("weather", "Clear"))
	if not WEATHER_PRESETS.has(loaded_weather):
		loaded_weather = "Clear"
	_weather = loaded_weather
	weather_changed.emit(_weather)

	_running = bool(data.get("running", true))
	running_changed.emit(_running)
	time_changed.emit(_minutes)
	day_changed.emit(_day_index)
