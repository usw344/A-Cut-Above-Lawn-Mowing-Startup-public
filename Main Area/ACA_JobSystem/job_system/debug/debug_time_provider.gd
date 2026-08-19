class_name ACAJobDebugTimeProvider
extends ACAJobTimeProvider
## TEST CLOCK - development only. NOT the game's world clock.
##
## Exists so the portable Job System can be exercised without the host game.
## It implements exactly the same boundary the real clock will implement, so
## swapping it out later is a one-line change:
##
##     manager.set_time_provider(MyRealGameClockProvider.new(world_clock))
##
## It deliberately does not simulate seasons, weather or the economy - the
## season is set directly by the demo's debug buttons.
##
## Time is computed from the real clock on demand rather than ticked, so there
## is no _process anywhere in the Job System.

## Game minutes that pass per real second while running.
var minutes_per_real_second: float = 1.0

var paused: bool = false

var _season: ACAJobEnums.Season = ACAJobEnums.Season.SPRING
var _base_minutes: float = 8.0 * 60.0  # start the world at 08:00 on day 1
var _anchor_msec: int = 0


func _init(start_minutes: float = 8.0 * 60.0) -> void:
	_base_minutes = start_minutes
	_anchor_msec = Time.get_ticks_msec()


# ------------------------------------------------------ ACAJobTimeProvider API

func game_minutes() -> float:
	if paused:
		return _base_minutes
	var elapsed_seconds := float(Time.get_ticks_msec() - _anchor_msec) / 1000.0
	return _base_minutes + elapsed_seconds * minutes_per_real_second


func season() -> ACAJobEnums.Season:
	return _season


# ------------------------------------------------------------ debug controls

func set_season(value: ACAJobEnums.Season) -> void:
	_season = value


## Jump the world clock forward. The manager tolerates jumps because it
## compares absolute times instead of accumulating deltas.
func advance_minutes(minutes: float) -> void:
	_rebase()
	_base_minutes += minutes


func advance_hours(hours: float) -> void:
	advance_minutes(hours * ACAJobBalance.MINUTES_PER_HOUR)


func advance_days(days: float) -> void:
	advance_minutes(days * ACAJobBalance.MINUTES_PER_DAY)


func set_speed(minutes_per_second: float) -> void:
	_rebase()
	minutes_per_real_second = maxf(minutes_per_second, 0.0)


func set_paused(value: bool) -> void:
	_rebase()
	paused = value


func speed_text() -> String:
	if paused:
		return "PAUSED"
	return "%s min/sec" % String.num(minutes_per_real_second, 1)


## Collapse elapsed real time into the base value so speed/pause changes never
## retroactively rewrite history.
func _rebase() -> void:
	_base_minutes = game_minutes()
	_anchor_msec = Time.get_ticks_msec()
