class_name ACAJobMarket
extends RefCounted
## Market demand model: season + economy + climate -> market strength (0-5).
##
## Market strength is a capacity, not a spawn instruction. It caps how many
## offers may exist at once; ACAJobManager still makes them arrive one at a
## time at the interval for the current strength.
##
## Season/economy/climate are inputs supplied from outside. The Job System does
## not simulate seasons, weather or the economy - those are future systems.

const SEASON_BASE := {
	ACAJobEnums.Season.SPRING: 4,
	ACAJobEnums.Season.SUMMER: 3,
	ACAJobEnums.Season.AUTUMN: 2,
	ACAJobEnums.Season.WINTER: 0,
}

const ECONOMY_MODIFIER := {
	ACAJobEnums.Economy.RECESSION: -2,
	ACAJobEnums.Economy.SLOW: -1,
	ACAJobEnums.Economy.NORMAL: 0,
	ACAJobEnums.Economy.BOOMING: 1,
}

const CLIMATE_MODIFIER := {
	ACAJobEnums.Climate.WET: 1,
	ACAJobEnums.Climate.NORMAL: 0,
	ACAJobEnums.Climate.DRY: -1,
	ACAJobEnums.Climate.DROUGHT: 0,
}


## Drought is a hard zero: it overrides every other modifier.
static func market_strength(season: int, economy: int, climate: int) -> int:
	if climate == ACAJobEnums.Climate.DROUGHT:
		return 0
	var raw: int = int(SEASON_BASE.get(season, 0)) \
		+ int(ECONOMY_MODIFIER.get(economy, 0)) \
		+ int(CLIMATE_MODIFIER.get(climate, 0))
	return clampi(raw, ACAJobBalance.MARKET_STRENGTH_MIN, ACAJobBalance.MARKET_STRENGTH_MAX)


## maximum_available_jobs == market_strength, by design.
static func capacity_for(strength: int) -> int:
	return clampi(strength, ACAJobBalance.MARKET_STRENGTH_MIN, ACAJobBalance.MARKET_STRENGTH_MAX)


## Game minutes until the next potential arrival, randomised inside the band
## for this market strength. Strength 0 never produces an arrival.
static func next_arrival_gap(strength: int, rng: RandomNumberGenerator) -> float:
	var band: Vector2 = ACAJobBalance.ARRIVAL_INTERVAL_MINUTES.get(strength, Vector2.ZERO)
	if band.y <= 0.0:
		return INF
	return rng.randf_range(band.x, band.y)


## Plain-language summary for the demo readout.
static func describe(season: int, economy: int, climate: int) -> String:
	var strength := market_strength(season, economy, climate)
	if climate == ACAJobEnums.Climate.DROUGHT:
		return "Drought - market closed (strength 0)"
	return "%s / %s / %s - strength %d" % [
		ACAJobEnums.season_name(season),
		ACAJobEnums.economy_name(economy),
		ACAJobEnums.climate_name(climate),
		strength,
	]
