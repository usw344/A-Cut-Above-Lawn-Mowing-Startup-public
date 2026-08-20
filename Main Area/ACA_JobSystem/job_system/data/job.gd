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
## What the property was worth BEFORE the market, and what the market did to it.
## Diagnostic only: `base_pay` is the number the player sees and is paid, and it
## is LOCKED once the offer exists. Nothing recomputes it from these.
@export var market_base_pay: int = 0
@export var market_multiplier: float = 1.0
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


# --------------------------------------------------------------- persistence
## Plain built-in types only, so this round-trips through JSON. The seed and
## generator_version are kept even though every generated field is stored too:
## that pair reproduces the whole core contract through
## ACAJobGenerator.generate_core(), which is what a future migration would use.

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"seed": seed,
		"generator_version": generator_version,
		"job_site": job_site,
		"property_type": int(property_type),
		"lawn_size": int(lawn_size),
		"grid_size_x": grid_size.x,
		"grid_size_y": grid_size.y,
		"base_pay": base_pay,
		"market_base_pay": market_base_pay,
		"market_multiplier": market_multiplier,
		"offer_duration_minutes": offer_duration_minutes,
		"created_game_time": created_game_time,
		"expiry_game_time": expiry_game_time,
		"accepted_game_time": accepted_game_time,
		"completed_game_time": completed_game_time,
		"status": int(status),
		"progress": progress,
	}


## Missing fields fall back to defaults, so an older save still loads.
static func from_dict(data: Dictionary) -> ACAJob:
	var job := ACAJob.new()
	job.id = StringName(String(data.get("id", "")))
	job.seed = int(data.get("seed", 0))
	job.generator_version = int(data.get("generator_version", ACAJobBalance.GENERATOR_VERSION))
	job.job_site = String(data.get("job_site", ""))
	job.property_type = int(data.get("property_type", ACAJobEnums.PropertyType.RESIDENTIAL))
	job.lawn_size = int(data.get("lawn_size", ACAJobEnums.LawnSize.SMALL))
	job.grid_size = Vector2i(
		int(data.get("grid_size_x", 96)), int(data.get("grid_size_y", 96)))
	job.base_pay = int(data.get("base_pay", 0))
	# Old saves have neither; fall back so an existing contract still describes
	# itself rather than claiming the market doubled it.
	job.market_base_pay = int(data.get("market_base_pay", job.base_pay))
	job.market_multiplier = float(data.get("market_multiplier", 1.0))
	job.offer_duration_minutes = float(data.get("offer_duration_minutes", 0.0))
	job.created_game_time = float(data.get("created_game_time", 0.0))
	job.expiry_game_time = float(data.get("expiry_game_time", 0.0))
	job.accepted_game_time = float(data.get("accepted_game_time", -1.0))
	job.completed_game_time = float(data.get("completed_game_time", -1.0))
	job.status = int(data.get("status", ACAJobEnums.Status.AVAILABLE))
	job.progress = clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	return job


func _to_string() -> String:
	return "<ACAJob %s %s / %s / %s / $%d / %s>" % [
		id, job_site, property_type_name(), lawn_size_name(), base_pay, status_name(),
	]
