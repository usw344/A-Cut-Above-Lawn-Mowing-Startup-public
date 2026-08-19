class_name ACAGameTime
extends RefCounted
## Formatting helpers for world time expressed in game minutes.
##
## The Job System stores time as a single float: game minutes since the world
## epoch. That keeps it independent of whatever calendar the host game runs.
## The helpers below are used for display only; a host with a different
## calendar can override ACAJobTimeProvider.format_timestamp() and
## ACAJobTimeProvider.calendar_text() instead of changing these.


## "2h 45m", "45m", "3d 4h". Used for offer countdowns.
static func format_duration(minutes: float) -> String:
	var total := int(round(maxf(minutes, 0.0)))
	var days := total / int(ACAJobBalance.MINUTES_PER_DAY)
	var hours := (total % int(ACAJobBalance.MINUTES_PER_DAY)) / int(ACAJobBalance.MINUTES_PER_HOUR)
	var mins := total % int(ACAJobBalance.MINUTES_PER_HOUR)
	if days > 0:
		return "%dd %dh" % [days, hours]
	if hours > 0:
		return "%dh %02dm" % [hours, mins]
	return "%dm" % mins


## "09:15" from an absolute game-minute value.
static func format_clock(game_minutes: float) -> String:
	var into_day := int(floor(game_minutes)) % int(ACAJobBalance.MINUTES_PER_DAY)
	if into_day < 0:
		into_day += int(ACAJobBalance.MINUTES_PER_DAY)
	var hours := into_day / int(ACAJobBalance.MINUTES_PER_HOUR)
	var mins := into_day % int(ACAJobBalance.MINUTES_PER_HOUR)
	return "%02d:%02d" % [hours, mins]


## Whole days elapsed since the epoch.
static func day_index(game_minutes: float) -> int:
	return int(floor(game_minutes / ACAJobBalance.MINUTES_PER_DAY))


## Day number inside the current season, 1-based.
static func day_of_season(game_minutes: float) -> int:
	return day_index(game_minutes) % ACAJobBalance.DAYS_PER_SEASON + 1


## Real minutes of mowing, rendered for the Estimated Time row.
static func format_estimate(real_minutes: float) -> String:
	if real_minutes < 1.0:
		return "< 1 min"
	return "%d min" % int(round(real_minutes))
