class_name ACAJobBalance
extends RefCounted
## Central balancing constants for the Job System.
##
## Everything tunable lives here so the numbers can be edited in one place.
## Values marked PLACEHOLDER stand in for systems that do not exist yet
## (mower capability, economy simulation) and are expected to be replaced.

const GENERATOR_VERSION := 1

# ---------------------------------------------------------------- lawn sizes
## Actual grid dimensions. Multiples of 16 on purpose. Stored internally only -
## the player sees "Small Lawn" / "Medium Lawn" / "Large Lawn".
const LAWN_GRID := {
	ACAJobEnums.LawnSize.TINY: Vector2i(64, 64),
	ACAJobEnums.LawnSize.SMALL: Vector2i(96, 96),
	ACAJobEnums.LawnSize.MEDIUM: Vector2i(144, 144),
	ACAJobEnums.LawnSize.LARGE: Vector2i(192, 192),
	ACAJobEnums.LawnSize.HUGE: Vector2i(256, 256),
}

## V1 generation rolls only these three. TINY and HUGE stay reserved.
const GENERATED_LAWN_SIZES: Array[int] = [
	ACAJobEnums.LawnSize.SMALL,
	ACAJobEnums.LawnSize.MEDIUM,
	ACAJobEnums.LawnSize.LARGE,
]

# ----------------------------------------------------------------------- pay
## Prototype contract values before seeded variation.
const BASE_PAY := {
	ACAJobEnums.LawnSize.TINY: 60,
	ACAJobEnums.LawnSize.SMALL: 100,
	ACAJobEnums.LawnSize.MEDIUM: 225,
	ACAJobEnums.LawnSize.LARGE: 400,
	ACAJobEnums.LawnSize.HUGE: 600,
}

const PAY_VARIATION_MIN := 0.85
const PAY_VARIATION_MAX := 1.15
const PAY_ROUNDING := 5

# ------------------------------------------------------------ offer lifetime
## Seeded offer duration, in game minutes. How long the player has to ACCEPT.
## This is not a completion deadline - that is a future system.
const OFFER_DURATION_MIN_MINUTES := 90.0
const OFFER_DURATION_MAX_MINUTES := 360.0

# ------------------------------------------------------------ market arrival
## Game-minute gap between potential job arrivals, indexed by market strength.
## Index 0 never produces an arrival.
const ARRIVAL_INTERVAL_MINUTES := {
	0: Vector2(0.0, 0.0),
	1: Vector2(240.0, 360.0),
	2: Vector2(180.0, 240.0),
	3: Vector2(120.0, 180.0),
	4: Vector2(60.0, 120.0),
	5: Vector2(30.0, 75.0),
}

const MARKET_STRENGTH_MIN := 0
const MARKET_STRENGTH_MAX := 5

## How many seeds the manager will try before giving up on one arrival, when the
## host has set `ACAJobManager.offer_filter_provider`.
##
## Sized against the worst case the host actually has: a business working only
## its starting corner of the market accepts roughly three offers in ten, so
## sixty-four attempts refuse a due arrival about once in every ten million.
## An arrival that IS refused is not an error - it is a quiet market - so this
## only has to be large enough that "quiet" never means "silent".
const OFFER_FILTER_ATTEMPTS := 64

# ------------------------------------------------------------- current jobs
## V1 allows exactly one accepted contract. current_jobs stays a collection so
## raising this number is the only change required later.
## HOW MANY CONTRACTS THE BUSINESS MAY HOLD AT ONCE.
##
## This was 1, and while the player was the only thing that could mow, 1 was the
## right number: a contractor cannot be in two gardens at the same time.
##
## The business now owns machines that work without being driven, and a company
## with a machine on a contract and a driver on another is holding two - so this
## is the business's capacity, not the player's. The PLAYER is still limited to
## one contract they personally drive to, and that limit lives in the host
## (`GameSession.max_player_contracts()`), because it is a fact about the player
## rather than about the job market.
##
## Five is one driven contract plus the four autonomous machines a business may
## own, so a fully equipped company can have every machine out at once and not
## one more.
const MAX_CURRENT_JOBS := 5

# ------------------------------------------------- estimated time PLACEHOLDER
## PLACEHOLDER. Real estimated time will come from lawn size + current mower
## capability. Until the mower system is connected, ACAJobManager derives the
## estimate from this rate. Override it with
## ACAJobManager.estimated_time_provider instead of editing gameplay code.
const PLACEHOLDER_CELLS_PER_REAL_MINUTE := 2000.0
const PLACEHOLDER_ESTIMATE_MIN_MINUTES := 4.0

# --------------------------------------------------------------- manager tick
## Real seconds between market evaluations. The manager owns exactly one timer;
## individual jobs never do. Cheap: expiry and arrival are compared against
## game time, so a coarse poll is enough.
const EVALUATION_INTERVAL_SECONDS := 0.25

# ---------------------------------------------------------- world-time units
## Used only for formatting and for the debug clock. The authoritative game
## clock supplies real values through ACAJobTimeProvider.
const MINUTES_PER_HOUR := 60.0
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := 1440.0
const DAYS_PER_SEASON := 28
