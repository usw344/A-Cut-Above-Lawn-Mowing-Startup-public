class_name ACAJobTimeProvider
extends RefCounted
## World-time boundary for the Job System. THIS IS AN INTEGRATION POINT.
##
## The Job System never reads a clock directly and never runs its own calendar.
## It asks a provider for the current world time in game minutes, and for the
## current season. To connect the real game clock, subclass this, override the
## three methods below, and hand the instance to
## ACAJobManager.set_time_provider().
##
## Contract:
##  - game_minutes() must be monotonically non-decreasing while the world runs.
##    It is an absolute value, not a delta.
##  - It may jump forward (fast-forward, sleeping, loading a save). The manager
##    tolerates jumps: expiry and arrival are evaluated by comparison, never by
##    accumulating deltas.
##  - Calls must be cheap. The manager polls it a few times per second.
##  - It is called from the main thread only. The Job System does no physics
##    and no threading of its own.
##
## ACAJobDebugTimeProvider (job_system/debug/) is the test implementation the
## standalone demo uses. It is not the game's clock.


## Absolute world time in game minutes since the world epoch.
func game_minutes() -> float:
	return 0.0


## Current season. Feeds market strength.
func season() -> ACAJobEnums.Season:
	return ACAJobEnums.Season.SPRING


## Human-readable stamp for an absolute game-minute value, e.g.
## "Spring Day 12  09:15". Override to match the host game's calendar.
func format_timestamp(absolute_game_minutes: float) -> String:
	return "%s Day %d  %s" % [
		ACAJobEnums.season_name(season()),
		ACAGameTime.day_of_season(absolute_game_minutes),
		ACAGameTime.format_clock(absolute_game_minutes),
	]


## Short label for the current moment, shown in the demo's clock chip.
func calendar_text() -> String:
	return format_timestamp(game_minutes())
