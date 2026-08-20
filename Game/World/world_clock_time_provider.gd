class_name ACAWorldClockTimeProvider
extends ACAJobTimeProvider
## Bridges the authoritative WorldClock into the Job System time boundary.
##
## This is the ONLY provider that should ever be handed to
## ACAJobManager.set_time_provider() in a real game session. The debug provider
## in job_system/debug/ stays for the standalone Job System demo and tests.

var _clock: ACAWorldClock


func _init(clock: ACAWorldClock) -> void:
	_clock = clock


func game_minutes() -> float:
	return _clock.game_minutes() if _clock != null else 0.0


func season() -> ACAJobEnums.Season:
	return _clock.season() if _clock != null else ACAJobEnums.Season.SPRING


func format_timestamp(absolute_game_minutes: float) -> String:
	return "%s Day %d  %s" % [
		ACAJobEnums.season_name(season()),
		ACAGameTime.day_of_season(absolute_game_minutes),
		ACAGameTime.format_clock(absolute_game_minutes),
	]


func calendar_text() -> String:
	return _clock.timestamp_text() if _clock != null else format_timestamp(0.0)
