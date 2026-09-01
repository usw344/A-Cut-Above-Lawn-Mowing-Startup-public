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
## ---------------------------------------------------------------------------
## THE EIGHT SKIES, AND WHY THERE ARE EIGHT
## ---------------------------------------------------------------------------
## There used to be three: Clear, Foggy and Rain. Three is enough to have a
## forecast and not enough to have WEATHER - a day was either perfect, in a
## white-out, or being rained on, and there was nothing in between for the
## sky to be on an ordinary afternoon.
##
## These eight are one authority with more states in it, NOT a second weather
## system. They are still chosen by the same hash of the same seed, they still
## come in 240-minute blocks, and `forecast()` is still the same pure function
## evaluated further along the clock.
##
## THE THREE ORIGINAL NAMES ARE UNCHANGED, so every save ever written by this
## project still loads with a sky it recognises.
const WEATHER_PRESETS: PackedStringArray = [
	"Clear", "Partly Cloudy", "Overcast", "Mist", "Foggy",
	"Light Rain", "Rain", "Clearing",
]

## Skies with water coming out of them. `Light Rain` wets the ground exactly as
## `Rain` does - it is lighter to LOOK at, not to stand in.
const RAIN_PRESETS: PackedStringArray = ["Light Rain", "Rain"]
## Skies made of suspended water. They do not wet the ground; they stop it
## drying.
const DAMP_PRESETS: PackedStringArray = ["Mist", "Foggy"]


## Is it raining? THE one place this question is answered, so no caller has to
## know how many presets there are or what they are called.
static func is_rain(preset: String) -> bool:
	return RAIN_PRESETS.has(preset)


## Is the air full of water, without any of it falling?
static func is_damp_air(preset: String) -> bool:
	return DAMP_PRESETS.has(preset)

## Game minutes at the start of a brand new game: 08:00 on day 0.
const NEW_GAME_START_MINUTES := 8.0 * 60.0

# --------------------------------------------------------------- the weather
## ---------------------------------------------------------------------------
## THE WEATHER IS A SCHEDULE, NOT A COIN TOSS
## ---------------------------------------------------------------------------
## Weather used to be a value that only a development key ever changed: the
## preset the player started on was the preset they finished on. A forecast
## needs weather that MOVES, and a forecast the player can plan a working day
## around needs it to move PREDICTABLY.
##
## So the sky is a pure function of `(weather_seed, absolute game minutes)`:
## time is divided into blocks, and a block's weather is a hash of the seed and
## the block index. Nothing accumulates, nothing is rolled per frame, and asking
## what the weather will be at four o'clock costs exactly what asking what it is
## now costs. That is what makes `forecast()` truthful rather than a guess
## dressed as one - it is the same function, evaluated later.
##
## A block is 240 game minutes: six of them in a day, forty real seconds each at
## the shipped time scale. Short enough that a forecast is worth reading during
## one contract; long enough that the sky is not a strobe.
const WEATHER_BLOCK_MINUTES := 240.0

## How likely each preset is in a block, by season. They sum to one per row.
## Spring and autumn are wetter; summer is the dry one. Deliberately modest
## differences: this is a lawn-care game, not a climate.
##
## `Clearing` is NOT in here, because it is not a thing the sky picks - it is
## what a clear block IMMEDIATELY AFTER A WET ONE is called. See
## `_scheduled_preset()`.
##
## QUIET WEATHER IS THE MAJORITY, deliberately. Clear plus Partly Cloudy is
## more than half of every season: variety in a forecast comes from the
## occasional bad afternoon standing out, not from every block being dramatic.
const WEATHER_WEIGHTS := {
	ACAJobEnums.Season.SPRING: {
		"Clear": 0.32, "Partly Cloudy": 0.24, "Overcast": 0.16,
		"Mist": 0.06, "Foggy": 0.04, "Light Rain": 0.12, "Rain": 0.06,
	},
	ACAJobEnums.Season.SUMMER: {
		"Clear": 0.44, "Partly Cloudy": 0.26, "Overcast": 0.10,
		"Mist": 0.04, "Foggy": 0.02, "Light Rain": 0.09, "Rain": 0.05,
	},
	ACAJobEnums.Season.AUTUMN: {
		"Clear": 0.26, "Partly Cloudy": 0.20, "Overcast": 0.20,
		"Mist": 0.10, "Foggy": 0.08, "Light Rain": 0.10, "Rain": 0.06,
	},
	ACAJobEnums.Season.WINTER: {
		"Clear": 0.22, "Partly Cloudy": 0.16, "Overcast": 0.24,
		"Mist": 0.10, "Foggy": 0.08, "Light Rain": 0.12, "Rain": 0.08,
	},
}

## How far ahead anything may ask. Two days is more than a working day and less
## than a promise the game cannot keep.
const FORECAST_LIMIT_MINUTES := 2880.0

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
## The one number the whole sky comes from. Zero randomises on the first world.
var _weather_seed: int = 0
## While this is false the scheduled sky is ignored and whatever was set by hand
## stays put. Set by the development weather keys and by the trailer director,
## so a staged shot is never rained on halfway through.
var _weather_scheduled: bool = true
## The block the applied preset came from, so the schedule is only consulted
## when time has actually crossed into a new one.
var _weather_block: int = -1
## When it last rained, for the cases the schedule cannot answer - a sky set by
## hand, or a world whose schedule was rolled forward past the look-back.
var _last_rain_minutes: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_day_index = ACAGameTime.day_index(_minutes)


func _process(delta: float) -> void:
	if not _running:
		return
	_minutes += delta * maxf(game_minutes_per_real_second, 0.0)
	time_changed.emit(_minutes)
	_apply_scheduled_weather()
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
	# EVERY WORLD GETS ITS OWN SKY. The seed is the whole of the difference
	# between two businesses' weather, and it is stored, so a save always
	# forecasts the same afternoon it forecast before it was closed.
	_weather_seed = randi() & 0x7FFFFFFF
	_weather_scheduled = true
	_weather_block = -1
	# THE FIRST MORNING IS THE ONE THE SCHEDULE SAYS. Forcing it clear would
	# make the forecast lie on day one, which is the one day a new player is
	# most likely to read it.
	_apply_scheduled_weather()
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


## SET THE SKY BY HAND, and stop the schedule until it is handed back.
##
## Every caller of this is a development control, a probe or the trailer
## director - the game itself never sets the weather, it reads the schedule. So
## setting it by hand TAKES the sky: a staged shot cannot be rained on halfway
## through, and a probe measuring rain is measuring rain.
func set_weather(preset: String) -> void:
	if not WEATHER_PRESETS.has(preset):
		push_warning("WorldClock: unknown weather preset %s ignored" % preset)
		return
	_weather_scheduled = false
	if _weather == preset:
		return
	_weather = preset
	if is_rain(_weather):
		_last_rain_minutes = _minutes
	weather_changed.emit(_weather)


## Give the sky back to the schedule. The next block it crosses applies.
func resume_scheduled_weather() -> void:
	_weather_scheduled = true
	_weather_block = -1
	_apply_scheduled_weather()


func weather_is_scheduled() -> bool:
	return _weather_scheduled


# ------------------------------------------------------------- the schedule

## What the schedule says the sky is at an absolute game time. PURE: the same
## arguments always give the same answer, which is the whole reason a forecast
## is possible at all.
func weather_at(game_minutes_value: float) -> String:
	return _scheduled_preset(_block_of(game_minutes_value))


## THE FORECAST. `[{ minutes, preset, hour, is_now }]`, one entry per block from
## the block the player is in to `hours` ahead, clamped to two days.
##
## It is the SAME function the sky is driven from, evaluated further along the
## clock. There is no separate prediction, no probability and nothing that can
## drift out of step with what actually happens.
func forecast(hours: float = 8.0) -> Array:
	var span: float = minf(maxf(hours, 1.0) * ACAJobBalance.MINUTES_PER_HOUR,
		FORECAST_LIMIT_MINUTES)
	var first := _block_of(_minutes)
	var last := _block_of(_minutes + span)
	var out: Array = []
	for block in range(first, last + 1):
		var at: float = float(block) * WEATHER_BLOCK_MINUTES
		out.append({
			"minutes": at,
			"preset": _scheduled_preset(block),
			"hour": fposmod(at, ACAJobBalance.MINUTES_PER_DAY)
				/ ACAJobBalance.MINUTES_PER_HOUR,
			"is_now": block == first,
		})
	return out


## Game minutes until the sky next changes, or INF when nothing in range does.
func minutes_until_weather_change() -> float:
	for entry: Dictionary in forecast(FORECAST_LIMIT_MINUTES
			/ ACAJobBalance.MINUTES_PER_HOUR):
		if bool(entry["is_now"]) or String(entry["preset"]) == _weather:
			continue
		return maxf(float(entry["minutes"]) - _minutes, 0.0)
	return INF


## The next block that rains, in game minutes from now. INF when none does in
## range. What the depot's forecast strip prints its warning from.
func minutes_until_rain() -> float:
	if is_rain(_weather):
		return 0.0
	for entry: Dictionary in forecast(FORECAST_LIMIT_MINUTES
			/ ACAJobBalance.MINUTES_PER_HOUR):
		if is_rain(String(entry["preset"])):
			return maxf(float(entry["minutes"]) - _minutes, 0.0)
	return INF


## HOW LONG SINCE IT LAST RAINED, in game minutes. Read backwards through the
## schedule rather than remembered, so it is right immediately after a load and
## right after the clock has been jumped by a development control.
##
## INF when nothing in range rained, which is what "the ground is dry" means.
func minutes_since_rain() -> float:
	if is_rain(_weather):
		return 0.0
	var block := _block_of(_minutes)
	# A day and a half back is far enough: past that the ground is dry by any
	# reading, and walking further would cost more than the answer is worth.
	for step in range(0, 10):
		var index := block - step
		if index < 0:
			break
		if not is_rain(_scheduled_preset(index)):
			continue
		# It stopped at the END of that block.
		var stopped: float = float(index + 1) * WEATHER_BLOCK_MINUTES
		return maxf(_minutes - stopped, 0.0)
	return maxf(_minutes - _last_rain_minutes, 0.0) if _last_rain_minutes > 0.0 else INF


func _block_of(game_minutes_value: float) -> int:
	return int(floor(maxf(game_minutes_value, 0.0) / WEATHER_BLOCK_MINUTES))


## The hash that IS the weather. Mixed with a constant of its own so it never
## collides with any other stream keyed off a seed in this project.
func _scheduled_preset(block: int) -> String:
	var preset := _rolled_preset(block)
	# CLEARING IS NOT ROLLED, IT IS EARNED. A bright block that follows a wet
	# one is the sky breaking up after rain, and it is the best-looking thing
	# the weather does - low sun on a wet landscape with the cloud pulling
	# apart. Deriving it costs one extra hash and keeps the schedule pure.
	if block > 0 and (preset == "Clear" or preset == "Partly Cloudy"):
		if is_rain(_rolled_preset(block - 1)):
			return "Clearing"
	return preset


## The raw draw for a block, before the clearing rule. Never call this from
## outside `_scheduled_preset()`: it is half of an answer.
func _rolled_preset(block: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(_weather_seed ^ 0x5C1E5, block))
	var weights: Dictionary = WEATHER_WEIGHTS.get(_season,
		WEATHER_WEIGHTS[ACAJobEnums.Season.SPRING])
	var roll := rng.randf()
	var running := 0.0
	for preset in WEATHER_PRESETS:
		running += float(weights.get(preset, 0.0))
		if roll < running:
			return preset
	return "Clear"


## Apply the schedule when the clock has crossed into a new block. Cheap: one
## integer division on the frames that do not cross one, which is almost all
## of them.
func _apply_scheduled_weather() -> void:
	if not _weather_scheduled:
		return
	var block := _block_of(_minutes)
	if block == _weather_block:
		return
	_weather_block = block
	var preset := _scheduled_preset(block)
	if is_rain(preset):
		_last_rain_minutes = _minutes
	if preset == _weather:
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
	_apply_scheduled_weather()
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


## ---------------------------------------------------------------------------
## DEVELOPMENT DAY CONTROL
## ---------------------------------------------------------------------------
## Used by the Super Debugger so a build can be looked at on day 40 without
## being played to day 40. There is NO second day variable here: both of these
## are `advance_minutes()` called a whole number of times, so the day index, the
## season, the weather schedule and every `day_changed` listener move exactly as
## they do when the day is lived through.
##
## A DAY AT A TIME, DELIBERATELY. `ACAEconomy` and `ACAClippings` catch up
## internally when handed a distant day, but `ACABusiness` and
## `ACAServiceAgreements` do ONE day's work per call - repeat customers,
## competition, agreement offers. Emitting `day_changed` once for a seven-day
## jump would skip six days of those, and the resulting world would be one the
## normal game could never produce. Seven emits cost nothing and are correct.

## The most days one call will walk. A guard against a mistyped day number
## locking the application up, not a design limit.
const MAX_DEV_DAY_JUMP := 400


## DEVELOPMENT ONLY. Move the world forward `days` whole days, keeping the time
## of day. Returns the new day index.
func advance_days(days: int) -> int:
	var wanted := clampi(days, 0, MAX_DEV_DAY_JUMP)
	for _i in wanted:
		advance_minutes(ACAJobBalance.MINUTES_PER_DAY)
	return _day_index


## DEVELOPMENT ONLY. Land on an exact absolute day index, keeping the time of
## day. Returns the day index actually reached.
##
## FORWARD ONLY, and that is not a shortcut. Every consumer of this clock
## compares ABSOLUTE times - offer expiry, composting batches, agreement
## windows, the market's `_last_day` - and each of them early-returns on a day
## it has already seen. Running the clock backwards would not undo those; it
## would leave a world whose books are ahead of its calendar. A target already
## past is refused and the current day is returned unchanged.
func set_day_index(target: int) -> int:
	if target <= _day_index:
		return _day_index
	return advance_days(target - _day_index)


# =================================================================== persistence
## Consumed by the save system. Plain built-in types only.

func to_save_dict() -> Dictionary:
	return {
		"minutes": _minutes,
		"season": int(_season),
		"weather": _weather,
		"running": _running,
		"minutes_per_real_second": game_minutes_per_real_second,
		# THE SKY'S SEED, and whether the schedule has the sky. Additive: a save
		# without them is a world whose weather never moved, and it is given a
		# schedule on load - see `from_save_dict()`.
		"weather_seed": _weather_seed,
		"weather_scheduled": _weather_scheduled,
		"last_rain_minutes": _last_rain_minutes,
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

	# A SAVE WRITTEN BEFORE THE SKY MOVED has no seed, and the honest thing to
	# do with it is to give it one: its weather never changed because nothing
	# was changing it, not because that world had eternal sunshine. It is
	# derived from the save's own clock, so reloading the same save twice gives
	# the same forecast, and the sky it was saved under is kept until the first
	# block boundary the clock crosses.
	_weather_seed = int(data.get("weather_seed", 0))
	if _weather_seed == 0:
		_weather_seed = hash(Vector2i(int(_minutes), int(_season))) & 0x7FFFFFFF
	_weather_scheduled = bool(data.get("weather_scheduled", true))
	_last_rain_minutes = float(data.get("last_rain_minutes", 0.0))
	_weather_block = _block_of(_minutes)

	_running = bool(data.get("running", true))
	running_changed.emit(_running)
	time_changed.emit(_minutes)
	day_changed.emit(_day_index)
