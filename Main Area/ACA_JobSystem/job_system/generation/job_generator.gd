class_name ACAJobGenerator
extends RefCounted
## Deterministic job generation.
##
## The same (seed, generator_version) pair always rebuilds the same core
## contract: property type, job site, lawn size, grid size, pay and offer
## duration. Only the absolute timestamps depend on when the offer entered the
## market:
##
##     expiry_game_time = created_game_time + offer_duration_minutes
##
## That is what makes save/load possible later without storing the whole job:
## a seed and a version reconstruct everything except the timestamps.
##
## Draw order below is part of the contract. Inserting a draw, or reordering
## ACAJobCatalog.GENERATED_PROPERTY_TYPES, changes what existing seeds
## produce - bump GENERATOR_VERSION instead.

const VERSION_1 := 1


## Rebuild the deterministic core of a job. No timestamps, no state.
## Keys: property_type, job_site, lawn_size, grid_size, base_pay,
##       offer_duration_minutes.
static func generate_core(job_seed: int, generator_version: int = ACAJobBalance.GENERATOR_VERSION) -> Dictionary:
	if generator_version != VERSION_1:
		push_warning("ACAJobGenerator: unknown generator_version %d, generating as v1"
			% generator_version)
	var rng := RandomNumberGenerator.new()
	rng.seed = job_seed

	# 1. property type
	var types := ACAJobCatalog.GENERATED_PROPERTY_TYPES
	var property_type: int = types[rng.randi() % types.size()]

	# 2. job site
	var sites := ACAJobCatalog.site_names(property_type)
	var job_site: String = sites[rng.randi() % sites.size()]

	# 3. lawn size, from this property type's pool
	var pool := ACAJobCatalog.size_pool(property_type)
	var lawn_size: int = pool[rng.randi() % pool.size()]
	var grid_size: Vector2i = ACAJobBalance.LAWN_GRID.get(lawn_size, Vector2i(96, 96))

	# 4. pay: size base value with seeded variation, rounded to the nearest $5
	var base: int = int(ACAJobBalance.BASE_PAY.get(lawn_size, 100))
	var factor := rng.randf_range(ACAJobBalance.PAY_VARIATION_MIN, ACAJobBalance.PAY_VARIATION_MAX)
	var pay := _round_to(float(base) * factor, ACAJobBalance.PAY_ROUNDING)

	# 5. seeded offer lifetime, in game minutes
	var duration := rng.randf_range(
		ACAJobBalance.OFFER_DURATION_MIN_MINUTES,
		ACAJobBalance.OFFER_DURATION_MAX_MINUTES)
	duration = round(duration / 5.0) * 5.0

	return {
		"property_type": property_type,
		"job_site": job_site,
		"lawn_size": lawn_size,
		"grid_size": grid_size,
		"base_pay": pay,
		"offer_duration_minutes": duration,
	}


## Build a full job from a seed and the world time it entered the market.
## The returned job is GENERATED; ACAJobManager publishes it as AVAILABLE.
static func generate(job_seed: int, created_game_time: float,
		generator_version: int = ACAJobBalance.GENERATOR_VERSION) -> ACAJob:
	var core := generate_core(job_seed, generator_version)
	var job := ACAJob.new()
	job.id = make_id(job_seed, generator_version, created_game_time)
	job.seed = job_seed
	job.generator_version = generator_version
	job.property_type = core["property_type"]
	job.job_site = core["job_site"]
	job.lawn_size = core["lawn_size"]
	job.grid_size = core["grid_size"]
	job.base_pay = core["base_pay"]
	job.offer_duration_minutes = core["offer_duration_minutes"]
	job.created_game_time = created_game_time
	job.expiry_game_time = created_game_time + core["offer_duration_minutes"]
	job.status = ACAJobEnums.Status.GENERATED
	job.progress = 0.0
	return job


## Stable internal id. Two offers rolled from the same seed at different world
## times are still distinct contracts, so the creation time is part of the id.
static func make_id(job_seed: int, generator_version: int, created_game_time: float) -> StringName:
	return StringName("job_%d_v%d_%d" % [job_seed, generator_version, int(round(created_game_time * 100.0))])


static func _round_to(value: float, step: int) -> int:
	if step <= 1:
		return int(round(value))
	return int(round(value / float(step))) * step
