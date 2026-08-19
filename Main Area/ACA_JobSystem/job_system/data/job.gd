class_name ACAJob
extends Resource
## One contract. Pure data - no timers, no _process, no scene tree, no UI.
##
## ACAJobManager is the single authoritative owner of every ACAJob instance.
## Nothing else may mutate these fields; use the manager's public API.
##
## Exported so a future save system can serialise a job directly. Save/load is
## deliberately not implemented yet - the seed/version pair below is the
## foundation for it: a job's core characteristics can always be rebuilt from
## (seed, generator_version) alone.

## Stable internal id. Never shown to the player.
@export var id: StringName = &""

## Reproduction key. ACAJobGenerator.generate_core(seed, generator_version)
## always rebuilds the same site, property type, lawn size, pay and offer
## duration from these two values.
@export var seed: int = 0
@export var generator_version: int = ACAJobBalance.GENERATOR_VERSION

# ------------------------------------------------------------ generated core
@export var job_site: String = ""
@export var property_type: ACAJobEnums.PropertyType = ACAJobEnums.PropertyType.RESIDENTIAL
@export var lawn_size: ACAJobEnums.LawnSize = ACAJobEnums.LawnSize.SMALL
## Actual mowing grid dimension, e.g. 96x96. Internal - never shown as text.
@export var grid_size: Vector2i = Vector2i.ZERO
## The contract's offered pay in whole dollars: the size base value after
## seeded variation, rounded to the nearest $5. Property type, mower, economy
## and climate deliberately do not affect it in V1.
@export var base_pay: int = 0
## Seeded offer lifetime in game minutes. Absolute expiry depends on when the
## offer entered the market; this value does not.
@export var offer_duration_minutes: float = 0.0

# -------------------------------------------------------------- world timing
## Absolute game minutes, supplied by ACAJobTimeProvider.
@export var created_game_time: float = 0.0
@export var expiry_game_time: float = 0.0
@export var accepted_game_time: float = -1.0
@export var completed_game_time: float = -1.0

# -------------------------------------------------------------------- state
@export var status: ACAJobEnums.Status = ACAJobEnums.Status.GENERATED
## 0.0 - 1.0. Reported from outside via ACAJobManager.update_job_progress().
@export var progress: float = 0.0


## Offer expiry applies to AVAILABLE offers only. Once accepted, a contract
## never expires - a completion deadline is a separate, future system.
func is_offer_expiry_active() -> bool:
	return status == ACAJobEnums.Status.AVAILABLE


func is_expired_at(game_minutes: float) -> bool:
	return is_offer_expiry_active() and game_minutes >= expiry_game_time


## Game minutes left to accept. Zero once the offer has lapsed.
func time_remaining(game_minutes: float) -> float:
	return maxf(expiry_game_time - game_minutes, 0.0)


func is_active() -> bool:
	return status == ACAJobEnums.Status.ACCEPTED or status == ACAJobEnums.Status.IN_PROGRESS


## True once the player has done some work but has not finished. Drives the
## future "RETURN TO JOB" wording in the Current tab.
func is_partially_complete() -> bool:
	return is_active() and progress > 0.0 and progress < 1.0


# ------------------------------------------------------- display convenience
func property_type_name() -> String:
	return ACAJobEnums.property_type_name(property_type)


func lawn_size_name() -> String:
	return ACAJobEnums.lawn_size_name(lawn_size)


func status_name() -> String:
	return ACAJobEnums.status_name(status)


func pay_text() -> String:
	return "$%d" % base_pay


func progress_percent() -> int:
	return int(round(clampf(progress, 0.0, 1.0) * 100.0))


func _to_string() -> String:
	return "<ACAJob %s %s / %s / %s / $%d / %s>" % [
		id, job_site, property_type_name(), lawn_size_name(), base_pay, status_name(),
	]
