class_name ACABusiness
extends Node
## THE COMPANY. Autoloaded as `Business`.
##
## Everything about the business that is not money, not equipment and not a
## contract: how well it is thought of, who keeps calling it back, who else is
## bidding for the same work, and how much of the local market it holds.
##
##   REPUTATION      one number, 0-100, moved only by finished work.
##   REVIEWS         a 1-5 rating and a line of text per completed contract,
##                   both derived from what the game measured.
##   CUSTOMERS       a record per property serviced, with a loyalty and a day it
##                   is next due.
##   COMPETITORS     four firms that take offers off the board.
##   MARKET SHARE    the player's share of recently contracted work.
##   SCHEDULE        the day's work, in the order it is meant to happen.
##   THE YARD        which of four states the business premises are in.
##
## It owns no money, no equipment, no clipping inventory and no job state. It
## reads `JobManager` and asks it to do things through its public API; it never
## reaches into a job list.
##
## ---------------------------------------------------------------------------
## NO PEOPLE
## ---------------------------------------------------------------------------
## There are no customer names, no owners, no staff and no portraits anywhere in
## this class, and there must not be. A CUSTOMER IS A PROPERTY - a site name and
## a seed - and a competitor is a FIRM. That is the project's standing art
## direction, and it is also what keeps this from needing a name generator:
## a returning customer is recognised by the lawn, which is the thing the player
## actually spent twenty minutes looking at.
##
## ---------------------------------------------------------------------------
## NO WAGES, NO TAX, NO INSURANCE, NO INTEREST
## ---------------------------------------------------------------------------
## The business has no payroll, because it has no staff: capacity beyond what
## the player personally drives comes from OWNED autonomous machines. None of
## the excluded financial systems appear here and none may be added.

# ------------------------------------------------------------------- signals
signal reputation_changed(value: float)
signal review_posted(review: Dictionary)
signal customers_changed()
signal competitors_changed()
## A competitor took an offer the player could have had.
signal offer_lost(job_site: String, competitor_name: String)
signal schedule_changed()
signal yard_tier_changed(tier: int)

# ================================================================ reputation

## Where a new business starts. Not zero: a firm with no history is unproven
## rather than disgraced, and starting at the bottom would make the first ten
## contracts feel like a punishment for having played them.
const STARTING_REPUTATION := 45.0
const MIN_REPUTATION := 0.0
const MAX_REPUTATION := 100.0

## How far one contract can move the number. Small, because reputation is the
## SLOW measure and the review is the fast one.
const REPUTATION_PER_STAR := {
	1: -6.0,
	2: -2.5,
	3: 0.4,
	4: 2.2,
	5: 3.6,
}
## Walking away from accepted work costs more than doing it badly.
const REPUTATION_ABANDON_PENALTY := 7.5

## What serving out a whole service agreement is worth, and what dropping one
## costs. Both larger than a single contract, because both are a term rather
## than a morning.
const AGREEMENT_HONOURED_REPUTATION := 6.0
const AGREEMENT_DROPPED_REPUTATION := 9.0
const AGREEMENT_PRESENCE_GAIN := 10.0

## Reputation bands, low to high. `at` is the floor.
const BANDS := [
	{"at": 0.0, "name": "Unknown",
		"blurb": "Nobody has heard of the business yet."},
	{"at": 25.0, "name": "Local",
		"blurb": "A few properties know the machine when it arrives."},
	{"at": 45.0, "name": "Established",
		"blurb": "Steady work and steady customers."},
	{"at": 65.0, "name": "Well Regarded",
		"blurb": "The better contracts come to the business first."},
	{"at": 82.0, "name": "Leading",
		"blurb": "The firm the town calls first."},
]

## Reputation at which an offer starts being held back for the player instead of
## being taken by the competition.
##
## THIS IS WHAT REPUTATION BUYS, and it is deliberately not a payout multiplier:
## a flat percentage on every contract is a number going up, whereas first
## refusal on the good work is a decision the player gets to make.
const RESERVED_ACCESS_AT := 62.0

# =============================================================== competitors

## Four firms - inside the three-to-five the design calls for, and enough that
## each archetype appears exactly once rather than twice with different colours.
##
## NAMED AS FIRMS, NEVER AFTER A PERSON.
##   `appetite`  roughly the share of suitable offers this firm will take.
##   `prefers`   the property types it goes for. Others are taken far less often.
##   `sizes`     the contract sizes it is equipped for.
const COMPETITORS := [
	{
		"id": &"verge",
		"name": "Verge & Kerb Lawncare",
		"archetype": "Budget operator",
		"colour": Color(0.851, 0.639, 0.267),
		"appetite": 0.34,
		"prefers": [ACAJobEnums.PropertyType.RESIDENTIAL,
			ACAJobEnums.PropertyType.COMMUNITY],
		"sizes": [ACAJobEnums.LawnSize.SMALL, ACAJobEnums.LawnSize.MEDIUM],
		"strong_in": [ACAServiceTerritory.Region.HOME_TOWN],
		"weak_in": [ACAServiceTerritory.Region.CIVIC_PARK,
			ACAServiceTerritory.Region.HOSPITALITY_STRIP],
		"capacity": 3,
		"blurb": "Cheap, quick and everywhere. Takes the small residential work.",
	},
	{
		"id": &"stonewell",
		"name": "Stonewell Grounds Care",
		"archetype": "Premium service",
		"colour": Color(0.400, 0.612, 0.337),
		"appetite": 0.28,
		"prefers": [ACAJobEnums.PropertyType.HOSPITALITY,
			ACAJobEnums.PropertyType.COMMERCIAL],
		"sizes": [ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE],
		"strong_in": [ACAServiceTerritory.Region.HOSPITALITY_STRIP,
			ACAServiceTerritory.Region.COMMERCIAL_DISTRICT],
		"weak_in": [ACAServiceTerritory.Region.RURAL_HIGHWAY],
		"capacity": 2,
		"blurb": "Immaculate finishes at immaculate prices. Wants the forecourts.",
	},
	{
		"id": &"broadacre",
		"name": "Broadacre Contracting",
		"archetype": "Large contractor",
		"colour": Color(0.353, 0.396, 0.337),
		"appetite": 0.30,
		"prefers": [ACAJobEnums.PropertyType.PUBLIC,
			ACAJobEnums.PropertyType.INDUSTRIAL,
			ACAJobEnums.PropertyType.INSTITUTIONAL],
		"sizes": [ACAJobEnums.LawnSize.LARGE],
		"strong_in": [ACAServiceTerritory.Region.RURAL_HIGHWAY,
			ACAServiceTerritory.Region.CIVIC_PARK],
		"weak_in": [ACAServiceTerritory.Region.HOME_TOWN],
		"capacity": 4,
		"blurb": "Fleet machinery and civic contracts. Only interested in acreage.",
	},
	{
		"id": &"meadowline",
		"name": "Meadowline Lawn Services",
		"archetype": "Generalist",
		"colour": Color(0.545, 0.780, 0.478),
		"appetite": 0.22,
		"prefers": [],
		"sizes": [ACAJobEnums.LawnSize.SMALL, ACAJobEnums.LawnSize.MEDIUM,
			ACAJobEnums.LawnSize.LARGE],
		"strong_in": [],
		"weak_in": [],
		"capacity": 3,
		"blurb": "Takes whatever is going. The firm the business measures itself against.",
	},
]

## Game minutes between competitor decisions. Long enough that an offer is on
## the board for a while before anyone else looks at it - a board that emptied
## the moment it filled would be a board the player never got to use.
const COMPETITOR_INTERVAL_MINUTES := 55.0

## ---------------------------------------------------------------------------
## A COMPETITOR HAS A FLEET TOO
## ---------------------------------------------------------------------------
## The board used to behave as though every rival could absorb every offer on
## it. They cannot: a firm with three machines can hold three contracts, and
## while it is holding them it is not bidding for a fourth. `capacity` on each
## firm is how many contracts it can have in hand, and a firm at capacity is
## simply skipped when its turn comes round.
##
## The commitments are ABSTRACT - a count and a release day, not a simulated
## contract - because nothing in the game will ever look at a rival's work. What
## the player sees is a market where the pressure moves about instead of being
## constant, which is the whole of what this is for.
const COMPETITOR_CONTRACT_DAYS := 2

## What a firm's appetite is multiplied by in a region it is strong in, and in
## one it is weak in. The strong end is what makes expanding into somebody
## else's market a decision.
const REGION_STRONG_APPETITE := 1.7
const REGION_WEAK_APPETITE := 0.35
## An offer is safe for this long after it appears, so the player always gets a
## look at everything.
const OFFER_GRACE_MINUTES := 90.0

# ============================================================== market share

## How many recent contracts the share is measured over. A window, not a
## lifetime total, so a share can be LOST as well as won.
const MARKET_WINDOW := 24

# =============================================================== the schedule

## How many stops the day's work list holds.
##
## A QUEUE, NOT A CALENDAR. The player says what they mean to do next and the
## Job Office shows it back to them in that order; there is no date picker, no
## time slot and no week view, because the game has one working day at a time
## and a calendar application would be a bigger interface than the thing it
## organises. Five is the Job System's own current-contract capacity plus room
## to think.
const SCHEDULE_CAPACITY := 5

# =============================================================== the customers

## Days between services, by property type. Seeded within these bounds per
## customer, so two suburban gardens are not on the same rota.
const SERVICE_INTERVAL_DAYS := {
	ACAJobEnums.PropertyType.RESIDENTIAL: [6, 10],
	ACAJobEnums.PropertyType.COMMERCIAL: [5, 9],
	ACAJobEnums.PropertyType.PUBLIC: [8, 14],
	ACAJobEnums.PropertyType.COMMUNITY: [8, 13],
	ACAJobEnums.PropertyType.RURAL: [10, 18],
	ACAJobEnums.PropertyType.INSTITUTIONAL: [7, 12],
	ACAJobEnums.PropertyType.INDUSTRIAL: [9, 15],
	ACAJobEnums.PropertyType.HOSPITALITY: [5, 8],
}

## Loyalty runs 0-100. A finished contract moves it by the review; an ignored
## return offer takes it down.
const LOYALTY_START := 50.0
const LOYALTY_PER_STAR := {1: -18.0, 2: -8.0, 3: 2.0, 4: 8.0, 5: 13.0}
## What ignoring a returning customer's offer costs them in loyalty.
const LOYALTY_IGNORED_PENALTY := 14.0
## Below this a customer stops coming back on their own.
const LOYALTY_LAPSED := 18.0
## A lapsed customer can come back, with their loyalty reset to this. A lost
## client is not lost forever - they simply do not trust the business as much.
const LOYALTY_RETURNED := 30.0
## Chance per day that a lapsed customer gives the business another try.
const LAPSED_RETURN_CHANCE := 0.06

# =================================================================== the yard

enum Yard { STARTER, ESTABLISHED, GROWING, LEADING }

const YARD_NAMES := {
	Yard.STARTER: "Starter Operation",
	Yard.ESTABLISHED: "Established Business",
	Yard.GROWING: "Growing Operation",
	Yard.LEADING: "Leading Operation",
}

const YARD_BLURBS := {
	Yard.STARTER: "A shed, one machine and the work truck.",
	Yard.ESTABLISHED: "A proper garage, a trailer, and somewhere to put the clippings.",
	Yard.GROWING: "A yard with machines parked in it and a compost bay out the back.",
	Yard.LEADING: "The largest operation in the district, and it looks it.",
}

## THE YARD IS EARNED, NOT LEVELLED. Each state has a gate on things the
## business already tracks - money taken over its lifetime, how it is regarded,
## and how much machinery it owns. There is no separate experience number,
## because there is nothing an experience number would measure that these do not.
const YARD_GATES := {
	Yard.ESTABLISHED: {"revenue": 3000, "reputation": 40.0, "machines": 2},
	Yard.GROWING: {"revenue": 14000, "reputation": 58.0, "machines": 4},
	Yard.LEADING: {"revenue": 45000, "reputation": 74.0, "machines": 6},
}

# ==================================================================== reviews

## THE REVIEW TEXT IS AUTHORED, NOT GENERATED.
##
## Five bands of a few lines each, chosen by the rating and the seed of the
## contract being reviewed. No runtime language model, no template filling, no
## personal names, and nothing that claims something the game did not measure.
const REVIEW_LINES := {
	5: [
		"Quick work and a clean finish.",
		"Everything asked for, done properly.",
		"Exactly what was agreed, and no fuss about it.",
		"The lawn has not looked this tidy in months.",
	],
	4: [
		"Good service. No complaints worth making.",
		"Tidy job. Happy to have them back.",
		"Well done, and finished when they said.",
	],
	3: [
		"The lawn was cut. That was the job.",
		"Fine, though nothing special about it.",
		"Acceptable work.",
	],
	2: [
		"Good service, though the job took longer than expected.",
		"It was done, eventually.",
		"Not what was agreed, but the grass is shorter.",
	],
	1: [
		"Not what was asked for.",
		"The job was left unfinished.",
		"Would not book this again.",
	],
}

## Extra lines used when a specific term was missed, so a review says WHY.
const REVIEW_NOTE := {
	ACAContractTerms.Flag.COLLECT: "The clippings were left behind.",
	ACAContractTerms.Flag.ON_TIME: "It ran well past the time booked.",
	ACAContractTerms.Flag.NO_DRY_TANK: "The machine ran out of fuel on site.",
	ACAContractTerms.Flag.PATTERN: "The finish was not what we asked for.",
	ACAContractTerms.Flag.CONSERVE: "They cut through the wildflower planting.",
}

# --------------------------------------------------------------------- state
var _reputation: float = STARTING_REPUTATION
## Newest first. Capped, because a review list is a feed rather than an archive.
var _reviews: Array[Dictionary] = []
const REVIEW_HISTORY := 20

## `{ customer_id: record }`, where a record is
## `{ id, seed, site, property_type, lawn_size, services, loyalty, last_day,
##    next_day, lapsed, offered_job_id }`.
var _customers: Dictionary = {}

## Rolling window of who won recent contracts: `{ who, value }`, `who` being
## `player` or a competitor id.
var _market_window: Array[Dictionary] = []
## Lifetime money taken from contracts. Drives the yard, and is not the same as
## the current balance - a business that has earned and spent forty thousand
## has still earned forty thousand.
var _lifetime_revenue: int = 0
var _contracts_completed: int = 0
var _contracts_abandoned: int = 0

## Job ids, in the order the player means to do them.
var _schedule: Array[String] = []

var _yard: int = Yard.STARTER
var _last_competitor_minutes: float = 0.0
## `{ competitor_id: [release_day, ...] }`. One entry per contract that firm is
## currently holding; the day it frees up is the whole of the record.
var _competitor_work: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_rng.randomize()


func reset_to_new_business() -> void:
	_reputation = STARTING_REPUTATION
	_reviews.clear()
	_customers.clear()
	_market_window.clear()
	_lifetime_revenue = 0
	_contracts_completed = 0
	_contracts_abandoned = 0
	_schedule.clear()
	_yard = Yard.STARTER
	_last_competitor_minutes = 0.0
	_competitor_work.clear()
	reputation_changed.emit(_reputation)
	customers_changed.emit()
	competitors_changed.emit()
	schedule_changed.emit()
	yard_tier_changed.emit(_yard)


# ================================================================ reputation

func reputation() -> float:
	return _reputation


func reputation_band() -> Dictionary:
	var band: Dictionary = BANDS[0]
	for entry: Dictionary in BANDS:
		if _reputation >= float(entry["at"]):
			band = entry
	return band


func reputation_band_name() -> String:
	return String(reputation_band()["name"])


func has_reserved_access() -> bool:
	return _reputation >= RESERVED_ACCESS_AT


func _move_reputation(delta: float) -> void:
	var was := _reputation
	_reputation = clampf(_reputation + delta, MIN_REPUTATION, MAX_REPUTATION)
	if not is_equal_approx(was, _reputation):
		reputation_changed.emit(_reputation)
		_reconsider_yard()


# =================================================================== reviews

## THE RATING IS MEASURED, NOT INVENTED.
##
## It starts from how much of the lawn was actually cut, and is then moved by
## the contract's own terms - each of which the game already has a number for.
## Nothing here scores tidiness, stripe quality or customer mood, because the
## game does not measure any of those and a rating built on them would be a
## rating built on nothing.
##
## `outcome` keys: completion, collected_kg, elapsed_minutes, ran_dry,
##                 autonomous (bool), autonomous_quality (float).
static func rate(job: ACAJob, outcome: Dictionary) -> int:
	var completion := clampf(float(outcome.get("completion", 0.0)), 0.0, 1.0)
	# A contract left half cut is a one-star job whatever else went right.
	if completion < 0.5:
		return 1
	if completion < 0.9:
		return 2

	var stars := 4.0 if completion >= 0.999 else 3.0
	var scored := ACAContractTerms.score(job, outcome)
	var terms := ACAContractTerms.terms_for(job)
	var flags := int(terms["flags"])

	# Every term met is worth a little; each missed one costs more than it paid,
	# because a customer notices the thing they asked for far more than the
	# things they did not.
	for flag in [int(ACAContractTerms.Flag.COLLECT),
			int(ACAContractTerms.Flag.ON_TIME),
			int(ACAContractTerms.Flag.NO_DRY_TANK),
			int(ACAContractTerms.Flag.PATTERN),
			int(ACAContractTerms.Flag.CONSERVE)]:
		if not (flags & flag):
			continue
		if int(scored["met"]) & flag:
			stars += 0.34
		else:
			stars -= 0.9

	# HOW THE MACHINE WAS CONFIGURED. Small, and only where it matters: a clean
	# bagged finish on a job that did not ask for one is a nice surprise, and a
	# discharge finish on one that did is the customer noticing.
	stars += ACAMowingMode.finish_quality(
		int(outcome.get("mowing_mode", ACAMowingMode.Mode.BAG)), job)

	# A machine that worked alone is judged on what it is rated to do.
	if bool(outcome.get("autonomous", false)):
		stars += (float(outcome.get("autonomous_quality", 0.8)) - 0.85) * 3.0

	return clampi(int(round(stars)), 1, 5)


## The line the customer wrote. Deterministic for a given contract and rating,
## so re-reading the results sheet never changes what it says.
static func review_text(job: ACAJob, stars: int, missed_flags: int) -> String:
	var lines: Array = REVIEW_LINES.get(clampi(stars, 1, 5), REVIEW_LINES[3])
	var pick_seed := (job.seed if job != null else 0) ^ (stars * 7919)
	var text := String(lines[abs(pick_seed) % lines.size()])
	# One note, and only the most important one. Two complaints in a two-line
	# review reads as a list rather than as a person being annoyed.
	for flag: int in [int(ACAContractTerms.Flag.COLLECT),
			int(ACAContractTerms.Flag.CONSERVE),
			int(ACAContractTerms.Flag.ON_TIME),
			int(ACAContractTerms.Flag.PATTERN),
			int(ACAContractTerms.Flag.NO_DRY_TANK)]:
		if missed_flags & flag:
			return "%s %s" % [text, String(REVIEW_NOTE[flag])]
	return text


func recent_reviews(count: int = 5) -> Array:
	var out: Array = []
	for i in mini(count, _reviews.size()):
		out.append(_reviews[i].duplicate())
	return out


func average_rating() -> float:
	if _reviews.is_empty():
		return 0.0
	var total := 0.0
	for review in _reviews:
		total += float(review["stars"])
	return total / float(_reviews.size())


# =========================================================== settling a job

## THE ONE PLACE a finished contract becomes company history.
##
## Called by `GameSession` after the job has really been completed and paid, for
## contracts the player drove AND for contracts an autonomous unit finished off
## screen. Returns the review it posted, which the results sheet displays.
func settle_completed_job(job: ACAJob, outcome: Dictionary, paid: int) -> Dictionary:
	var stars := rate(job, outcome)
	var scored := ACAContractTerms.score(job, outcome)
	var text := review_text(job, stars, int(scored["missed"]))

	var review := {
		"job_id": String(job.id) if job != null else "",
		"site": job.job_site if job != null else "",
		"stars": stars,
		"text": text,
		"day": _today(),
		"autonomous": bool(outcome.get("autonomous", false)),
	}
	_reviews.push_front(review)
	while _reviews.size() > REVIEW_HISTORY:
		_reviews.pop_back()

	var before := _reputation
	_move_reputation(float(REPUTATION_PER_STAR.get(stars, 0.0)))
	review["reputation_change"] = _reputation - before

	_contracts_completed += 1
	_lifetime_revenue += maxi(paid, 0)
	_record_market_result(&"player", maxi(paid, 0))

	# THE CONDITION THE PROPERTY WAS IN when the work started, captured BEFORE
	# the visit is counted. That is what makes a results sheet able to say the
	# place has moved on: the stage after is derived from a service count this
	# call is about to increase.
	var stage_before := condition_stage_for(job)
	_remember_customer(job, stars, outcome)
	review["condition_stage_before"] = stage_before
	review["condition_stage_after"] = condition_stage_for(job)

	remove_from_schedule(String(job.id) if job != null else "")
	_reconsider_yard()

	# THE OTHER TWO BOOKS THIS CONTRACT BELONGS IN. Both are told once, here,
	# after the contract has really been settled - so neither can ever record a
	# job the company did not finish, and neither needs a clock of its own.
	var territory := get_node_or_null(^"/root/Territory")
	if territory != null:
		territory.call(&"note_completed_contract", job, stars)
	var agreements := get_node_or_null(^"/root/Agreements")
	if agreements != null:
		agreements.call(&"note_completed_contract", job, stars)

	review_posted.emit(review)
	return review


# ======================================================== property condition

## WHAT CONDITION A PROPERTY IS IN, given what this business has done to it.
##
## The derivation is `ACAPropertyCondition`'s and the service count is this
## class's, which is exactly the split: the property generator owns what a
## neglected lawn LOOKS like, and the company owns how many times it has been
## back. Nothing about the stage is stored - it is the seed and the count.
func condition_stage_for(job: ACAJob) -> int:
	if job == null:
		return ACAPropertyCondition.Stage.MAINTAINED
	return ACAPropertyCondition.stage_for(job.seed, int(job.property_type),
		services_for(job))


## Whether this contract is a rescue rather than a cut. What the work order asks
## to print a label from.
func is_recovery_contract(job: ACAJob) -> bool:
	return ACAPropertyCondition.is_project_stage(condition_stage_for(job))


# ======================================================== service agreements

## An agreement was served out. Called by `ACAServiceAgreements` when the term
## closes; the standing it earns is this class's to award, because reputation
## has exactly one owner.
func note_agreement_honoured(region: int) -> void:
	_move_reputation(AGREEMENT_HONOURED_REPUTATION)
	var territory := get_node_or_null(^"/root/Territory")
	if territory != null:
		territory.call(&"award_presence", region, AGREEMENT_PRESENCE_GAIN)


## ...and one that was not. A dropped agreement costs more than a missed
## contract, because the customer was promised a term rather than a morning.
func note_agreement_dropped(region: int) -> void:
	_move_reputation(-AGREEMENT_DROPPED_REPUTATION)
	var territory := get_node_or_null(^"/root/Territory")
	if territory != null:
		territory.call(&"award_presence", region, -AGREEMENT_PRESENCE_GAIN)


## Accepted work the player walked away from.
func record_abandoned_job(job: ACAJob) -> void:
	_contracts_abandoned += 1
	_move_reputation(-REPUTATION_ABANDON_PENALTY)
	if job != null:
		var record := _customers.get(_customer_id(job), {}) as Dictionary
		if not record.is_empty():
			_adjust_loyalty(record, -LOYALTY_IGNORED_PENALTY)
		remove_from_schedule(String(job.id))
	customers_changed.emit()


# ================================================================= customers

## A customer IS a property. The id is the contract seed, because that is what
## rebuilds the same ground - so a returning customer is literally the same
## lawn, not a name attached to a fresh one.
static func _customer_id(job: ACAJob) -> String:
	return "site_%d" % (job.seed if job != null else 0)


func _remember_customer(job: ACAJob, stars: int, outcome: Dictionary = {}) -> void:
	if job == null:
		return
	var id := _customer_id(job)
	var record: Dictionary = _customers.get(id, {})
	if record.is_empty():
		record = {
			"id": id,
			"seed": job.seed,
			"site": job.job_site,
			"property_type": int(job.property_type),
			"lawn_size": int(job.lawn_size),
			"services": 0,
			"loyalty": LOYALTY_START,
			"last_day": -1,
			"next_day": 0,
			"lapsed": false,
			"offered_job_id": "",
		}
	record["services"] = int(record["services"]) + 1
	record["last_day"] = _today()
	record["offered_job_id"] = ""
	record["lapsed"] = false
	_adjust_loyalty(record, float(LOYALTY_PER_STAR.get(stars, 0.0)))
	# WHAT MULCHING IS WORTH, and it is worth exactly two points of loyalty on a
	# dry lawn and less on a wet one. Not a fertiliser multiplier and not a
	# reason to mulch everything - a reason to mulch the garden the business
	# keeps coming back to. See `ACAMowingMode.MULCH_LOYALTY_BONUS`.
	var mulch := ACAMowingMode.lawn_health_bonus(
		int(outcome.get("mowing_mode", ACAMowingMode.Mode.BAG)))
	if mulch > 0.0:
		mulch -= ACAGroundConditions.mulch_penalty(
			int(outcome.get("ground_state", ACAGroundConditions.State.DAMP)))
		if mulch > 0.0:
			_adjust_loyalty(record, mulch)
	record["next_day"] = _today() + _service_interval(job)
	_customers[id] = record
	customers_changed.emit()


func _adjust_loyalty(record: Dictionary, delta: float) -> void:
	record["loyalty"] = clampf(float(record["loyalty"]) + delta, 0.0, 100.0)
	if float(record["loyalty"]) < LOYALTY_LAPSED:
		record["lapsed"] = true


## SEEDED PER CUSTOMER, so two suburban gardens are not on the same rota and the
## same garden is always on the same one.
static func _service_interval(job: ACAJob) -> int:
	var bounds: Array = SERVICE_INTERVAL_DAYS.get(job.property_type, [7, 12])
	var rng := RandomNumberGenerator.new()
	rng.seed = (job.seed ^ 0x1EC0D) & 0x7FFFFFFF
	return rng.randi_range(int(bounds[0]), int(bounds[1]))


func customer_count() -> int:
	return _customers.size()


## Customers who are still on the books, best first.
func active_customers() -> Array:
	var out: Array = []
	for id: String in _customers:
		var record: Dictionary = _customers[id]
		if bool(record["lapsed"]):
			continue
		out.append(record.duplicate())
	out.sort_custom(func(a, b): return float(a["loyalty"]) > float(b["loyalty"]))
	return out


func lapsed_customers() -> Array:
	var out: Array = []
	for id: String in _customers:
		var record: Dictionary = _customers[id]
		if bool(record["lapsed"]):
			out.append(record.duplicate())
	return out


## Whether this contract is a property the business has cut before.
func is_returning_customer(job: ACAJob) -> bool:
	if job == null:
		return false
	var record: Dictionary = _customers.get(_customer_id(job), {})
	return not record.is_empty() and int(record["services"]) > 0


func services_for(job: ACAJob) -> int:
	if job == null:
		return 0
	var record: Dictionary = _customers.get(_customer_id(job), {})
	return int(record.get("services", 0))


func loyalty_for(job: ACAJob) -> float:
	if job == null:
		return 0.0
	var record: Dictionary = _customers.get(_customer_id(job), {})
	return float(record.get("loyalty", 0.0))


# ======================================================== the daily rollover

## Everything that happens because a day passed. Driven by the application layer
## off `WorldClock.day_changed`; this class never runs a clock of its own.
##
## Returns how many returning contracts were put on the board.
func advance_to_day(today: int) -> int:
	var manager := get_node_or_null(^"/root/JobManager")
	if manager == null:
		return 0

	var returned := 0
	for id: String in _customers.keys():
		var record: Dictionary = _customers[id]

		# A customer whose offer is still standing and has gone stale has been
		# ignored, and notices.
		var pending := String(record["offered_job_id"])
		if not pending.is_empty():
			if manager.call(&"get_job", StringName(pending)) == null:
				# Taken, expired or done. Either way the offer is no longer out.
				record["offered_job_id"] = ""
			continue

		if bool(record["lapsed"]):
			# NOT GONE FOREVER. A lapsed customer may give the business another
			# go, with their trust starting lower than it did the first time.
			if _rng.randf() < LAPSED_RETURN_CHANCE:
				record["lapsed"] = false
				record["loyalty"] = LOYALTY_RETURNED
				record["next_day"] = today + 1
			continue

		if today < int(record["next_day"]):
			continue

		var job: ACAJob = manager.call(&"commission_offer", int(record["seed"]), 0.0)
		if job == null:
			continue
		record["offered_job_id"] = String(job.id)
		returned += 1

	# A day of composting, and any autonomous work that finished overnight, are
	# not this class's business - the application layer drives those.
	if returned > 0:
		customers_changed.emit()
	return returned


## The player did not take a returning customer's offer and it lapsed. Called
## from the offer-expiry and competitor paths.
func note_offer_lapsed(job: ACAJob) -> void:
	if job == null:
		return
	var record: Dictionary = _customers.get(_customer_id(job), {})
	if record.is_empty():
		return
	record["offered_job_id"] = ""
	_adjust_loyalty(record, -LOYALTY_IGNORED_PENALTY)
	# Next time they are due, not tomorrow: a customer who was let down does not
	# ring again the following morning.
	record["next_day"] = _today() + maxi(int(_service_interval_for_record(record)), 3)
	customers_changed.emit()


static func _service_interval_for_record(record: Dictionary) -> int:
	var bounds: Array = SERVICE_INTERVAL_DAYS.get(int(record["property_type"]), [7, 12])
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(record["seed"]) ^ 0x1EC0D) & 0x7FFFFFFF
	return rng.randi_range(int(bounds[0]), int(bounds[1]))


# =============================================================== competitors

static func competitor_by_id(id: StringName) -> Dictionary:
	for firm: Dictionary in COMPETITORS:
		if StringName(firm["id"]) == id:
			return firm
	return {}


static func competitor_name(id: StringName) -> String:
	var firm := competitor_by_id(id)
	return String(firm.get("name", "A competitor"))


## THE COMPETITION LOOKS AT THE BOARD.
##
## Called by the application layer as game time passes. Every
## `COMPETITOR_INTERVAL_MINUTES` one firm may take ONE offer - never more, so
## the player can never open the Job Office to find it emptied.
##
## Returns the number of offers taken.
func consider_competition(now_minutes: float) -> int:
	if now_minutes - _last_competitor_minutes < COMPETITOR_INTERVAL_MINUTES:
		return 0
	_last_competitor_minutes = now_minutes

	var manager := get_node_or_null(^"/root/JobManager")
	if manager == null:
		return 0
	var offers: Array = manager.call(&"available_jobs")
	if offers.size() <= 1:
		# NEVER THE LAST OFFER. A board a competitor can empty is a board the
		# player cannot use, and a game where the work can simply stop is not a
		# game about choosing between contracts.
		return 0

	# A FIRM WITH ITS HANDS FULL DOES NOT BID. Picked from the firms that have
	# room rather than from all four, so a busy market really does ease off.
	var free: Array = []
	for entry: Dictionary in COMPETITORS:
		if _committed_count(StringName(entry["id"])) < int(entry["capacity"]):
			free.append(entry)
	if free.is_empty():
		return 0
	var firm: Dictionary = free[_rng.randi_range(0, free.size() - 1)]
	var candidates: Array = []
	for entry in offers:
		var job := entry as ACAJob
		if job == null or not _competitor_wants(firm, job, now_minutes):
			continue
		candidates.append(job)
	if candidates.is_empty():
		return 0

	var target := candidates[_rng.randi_range(0, candidates.size() - 1)] as ACAJob
	if not manager.call(&"competitor_take_offer", target.id):
		return 0

	_record_market_result(StringName(firm["id"]), target.base_pay)
	_commit_competitor(StringName(firm["id"]))
	note_offer_lapsed(target)
	# The market notices when work in the business's own area goes elsewhere.
	var territory := get_node_or_null(^"/root/Territory")
	if territory != null:
		territory.call(&"note_lost_contract", target)
	offer_lost.emit(target.job_site, String(firm["name"]))
	competitors_changed.emit()
	return 1


## How many contracts a firm is holding right now. Commitments that have run
## their course are dropped as they are counted, so nothing has to sweep them.
func _committed_count(id: StringName) -> int:
	var held: Array = _competitor_work.get(String(id), [])
	if held.is_empty():
		return 0
	var today := _today()
	var still: Array = []
	for value: Variant in held:
		if int(value) > today:
			still.append(int(value))
	_competitor_work[String(id)] = still
	return still.size()


func _commit_competitor(id: StringName) -> void:
	var held: Array = _competitor_work.get(String(id), [])
	held.append(_today() + COMPETITOR_CONTRACT_DAYS)
	_competitor_work[String(id)] = held


## Every firm's fleet position, for the office's operations page.
func competitor_capacity_table() -> Array:
	var out: Array = []
	for firm: Dictionary in COMPETITORS:
		var id := StringName(firm["id"])
		out.append({
			"id": String(id),
			"name": String(firm["name"]),
			"colour": firm["colour"],
			"held": _committed_count(id),
			"capacity": int(firm["capacity"]),
			"archetype": String(firm["archetype"]),
			"strong_in": (firm["strong_in"] as Array).duplicate(),
		})
	return out


func _competitor_wants(firm: Dictionary, job: ACAJob, now_minutes: float) -> bool:
	# EVERY OFFER GETS A GRACE PERIOD. The player must always have had a chance
	# to take a contract before anyone else could.
	if now_minutes - job.created_game_time < OFFER_GRACE_MINUTES:
		return false
	# WHAT REPUTATION BUYS: at a high enough standing the good work is held for
	# the player rather than being fair game.
	if has_reserved_access() and job.lawn_size == ACAJobEnums.LawnSize.LARGE:
		return false
	if not (firm["sizes"] as Array).has(int(job.lawn_size)):
		return false

	# WORK THE BUSINESS HAS ALREADY BEEN AWARDED IS NOT ON THE MARKET. A visit
	# scheduled under a signed service agreement is a commitment, not an offer,
	# and a rival taking one would be a rival taking work that was never theirs
	# to bid for.
	var agreements := get_node_or_null(^"/root/Agreements")
	if agreements != null and bool(agreements.call(&"is_agreement_job", job)):
		return false

	var appetite := float(firm["appetite"])
	var prefers: Array = firm["prefers"]
	if not prefers.is_empty() and not prefers.has(int(job.property_type)):
		# Outside its usual work. It will still take it, far less often.
		appetite *= 0.25
	# A well-regarded business simply gets asked first, so less is taken from
	# under it. Never to zero - a firm with no competition has no market.
	appetite *= clampf(1.0 - (_reputation - 40.0) / 160.0, 0.45, 1.15)
	# WHOSE PATCH IT IS. Each firm has areas it dominates and areas it barely
	# works, so moving into a new territory means meeting different pressure
	# rather than the same four firms with the same appetite everywhere.
	var region := ACAServiceTerritory.region_for_job(job)
	if (firm["strong_in"] as Array).has(region):
		appetite *= REGION_STRONG_APPETITE
	elif (firm["weak_in"] as Array).has(region):
		appetite *= REGION_WEAK_APPETITE
	# ...and a firm is hungrier where the business has not established itself.
	var territory := get_node_or_null(^"/root/Territory")
	if territory != null and bool(territory.call(&"owns", region)):
		var presence: float = territory.call(&"presence", region)
		appetite *= clampf(1.25 - presence / 140.0, 0.5, 1.25)

	# A returning customer would rather wait for the business they know.
	if is_returning_customer(job):
		appetite *= 0.45
	return _rng.randf() < appetite


# ============================================================== market share

func _record_market_result(who: StringName, value: int) -> void:
	_market_window.push_front({"who": String(who), "value": maxi(value, 0)})
	while _market_window.size() > MARKET_WINDOW:
		_market_window.pop_back()


## The player's share of recent contracted work, 0-1.
##
## MEASURED BY VALUE, not by count: winning four small gardens while the
## competition takes the town park is not leading the market, and a share that
## said otherwise would be a share worth ignoring.
func market_share() -> float:
	var total := 0.0
	var mine := 0.0
	for entry in _market_window:
		var value := float(entry["value"])
		total += value
		if String(entry["who"]) == "player":
			mine += value
	if total <= 0.0:
		return 0.0
	return clampf(mine / total, 0.0, 1.0)


## Every firm's share of the same window, the player included. Sorted, biggest
## first, so the Business Office can print a league table.
func market_table() -> Array:
	# NO HISTORY IS AN EMPTY TABLE, not a table with the player on nought per
	# cent. The first version seeded the player in unconditionally, so a brand
	# new business showed itself holding 0% of a market in which nothing had
	# happened - and the Business Office's "nobody has taken anything yet" line,
	# which tests for an empty table, could never appear. Found by
	# `Business Test`.
	if _market_window.is_empty():
		return []
	var totals := {"player": 0.0}
	var overall := 0.0
	for entry in _market_window:
		var who := String(entry["who"])
		totals[who] = float(totals.get(who, 0.0)) + float(entry["value"])
		overall += float(entry["value"])
	var out: Array = []
	for who: String in totals:
		var is_player := who == "player"
		out.append({
			"id": who,
			"name": "Your business" if is_player else competitor_name(StringName(who)),
			"is_player": is_player,
			"share": (float(totals[who]) / overall) if overall > 0.0 else 0.0,
			"value": int(totals[who]),
			"colour": Color(0.243, 0.435, 0.278) if is_player
				else Color(competitor_by_id(StringName(who)).get("colour",
					Color(0.502, 0.537, 0.478))),
		})
	out.sort_custom(func(a, b): return float(a["share"]) > float(b["share"]))
	return out


## Whether the player currently holds the largest share. The long-term objective,
## in one question.
func is_market_leader() -> bool:
	var table := market_table()
	return not table.is_empty() and bool(table[0]["is_player"])


# ================================================================= the schedule

## The day's work, in order. A queue of accepted contracts, not a calendar: the
## player says what they mean to do next and the Job Office shows it back.
func schedule() -> Array:
	var manager := get_node_or_null(^"/root/JobManager")
	var out: Array = []
	if manager == null:
		return out
	for job_id in _schedule:
		var job: ACAJob = manager.call(&"get_job", StringName(job_id))
		if job != null:
			out.append(job)
	return out


func schedule_ids() -> Array[String]:
	return _schedule.duplicate()


func is_scheduled(job_id: String) -> bool:
	return _schedule.has(job_id)


func add_to_schedule(job_id: String) -> bool:
	if job_id.is_empty() or _schedule.has(job_id):
		return false
	if _schedule.size() >= SCHEDULE_CAPACITY:
		return false
	_schedule.append(job_id)
	schedule_changed.emit()
	return true


func remove_from_schedule(job_id: String) -> bool:
	if job_id.is_empty() or not _schedule.has(job_id):
		return false
	_schedule.erase(job_id)
	schedule_changed.emit()
	return true


## Move a stop one place earlier or later. `direction` is -1 or +1.
func reorder_schedule(job_id: String, direction: int) -> bool:
	var at := _schedule.find(job_id)
	if at < 0:
		return false
	var to := clampi(at + signi(direction), 0, _schedule.size() - 1)
	if to == at:
		return false
	_schedule.remove_at(at)
	_schedule.insert(to, job_id)
	schedule_changed.emit()
	return true


## Drop anything the Job System no longer knows about - completed, expired or
## taken. Called on the daily rollover so the list cannot rot.
func prune_schedule() -> void:
	var manager := get_node_or_null(^"/root/JobManager")
	if manager == null:
		return
	var kept: Array[String] = []
	for job_id in _schedule:
		var job: ACAJob = manager.call(&"get_job", StringName(job_id))
		if job != null and job.is_active():
			kept.append(job_id)
	if kept.size() != _schedule.size():
		_schedule = kept
		schedule_changed.emit()


# ==================================================================== the yard

func yard_tier() -> int:
	return _yard


func yard_name() -> String:
	return String(YARD_NAMES.get(_yard, "Operation"))


func yard_blurb() -> String:
	return String(YARD_BLURBS.get(_yard, ""))


func lifetime_revenue() -> int:
	return _lifetime_revenue


func contracts_completed() -> int:
	return _contracts_completed


func contracts_abandoned() -> int:
	return _contracts_abandoned


## How many machines the business owns, of any kind. The yard's third gate.
func machine_count() -> int:
	var equipment := get_node_or_null(^"/root/Equipment")
	if equipment == null:
		return 1
	return int(equipment.call(&"owned_mower_count")) \
		+ int(equipment.call(&"autonomous_unit_count"))


## THE YARD ONLY EVER GOES UP. A quiet month should not demolish the garage: the
## premises are what the business HAS BUILT, and reputation is what measures how
## it is doing right now.
func _reconsider_yard() -> void:
	var machines := machine_count()
	var wanted := _yard
	for tier: int in [Yard.ESTABLISHED, Yard.GROWING, Yard.LEADING]:
		var gate: Dictionary = YARD_GATES[tier]
		if _lifetime_revenue >= int(gate["revenue"]) \
				and _reputation >= float(gate["reputation"]) \
				and machines >= int(gate["machines"]):
			wanted = maxi(wanted, tier)
	if wanted == _yard:
		return
	_yard = wanted
	yard_tier_changed.emit(_yard)


## What the business still needs for the next state of its yard, as one line.
## Empty when it is already at the top.
func next_yard_requirement() -> String:
	if _yard >= Yard.LEADING:
		return ""
	var tier: int = _yard + 1
	var gate: Dictionary = YARD_GATES[tier]
	var wants := PackedStringArray()
	if _lifetime_revenue < int(gate["revenue"]):
		wants.append("%s earned" % UITheme.format_money(int(gate["revenue"])))
	if _reputation < float(gate["reputation"]):
		wants.append("%d reputation" % int(gate["reputation"]))
	if machine_count() < int(gate["machines"]):
		wants.append("%d machines" % int(gate["machines"]))
	if wants.is_empty():
		return ""
	return "%s needs %s" % [String(YARD_NAMES[tier]), ", ".join(wants)]


# ===================================================================== helpers

func _today() -> int:
	var clock := get_node_or_null(^"/root/WorldClock")
	return int(clock.call(&"day_index")) if clock != null else 0


# ================================================================ persistence

## NONE OF THIS CAN BE RECONSTRUCTED. Reputation is the sum of a hundred
## contracts, a customer's loyalty is the sum of every visit, and the market
## window is a history. All of it is written.
##
## What is NOT written is anything derivable: a competitor's name, colour and
## appetite come from the constant table, so only the id ever appears in a save.
func to_save_dict() -> Dictionary:
	var customers: Array = []
	for id: String in _customers:
		customers.append((_customers[id] as Dictionary).duplicate())
	var reviews: Array = []
	for review in _reviews:
		reviews.append(review.duplicate())
	var window: Array = []
	for entry in _market_window:
		window.append(entry.duplicate())
	return {
		"reputation": _reputation,
		"reviews": reviews,
		"customers": customers,
		"market_window": window,
		"lifetime_revenue": _lifetime_revenue,
		"contracts_completed": _contracts_completed,
		"contracts_abandoned": _contracts_abandoned,
		"schedule": _schedule.duplicate(),
		"yard": _yard,
		"last_competitor_minutes": _last_competitor_minutes,
		"competitor_work": _competitor_work.duplicate(true),
	}


## A save written before the business layer existed loads as a NEW business that
## happens to have money and contracts. That is the honest reading: it has no
## reviews because nobody was writing any, and no customers because nothing was
## keeping a book. Nothing is invented to fill the gap - in particular, its
## completed contracts are NOT retro-fitted into reputation, because the terms
## those contracts would have been judged against did not exist when they were
## played.
func from_save_dict(data: Dictionary) -> void:
	_reputation = clampf(float(data.get("reputation", STARTING_REPUTATION)),
		MIN_REPUTATION, MAX_REPUTATION)
	_lifetime_revenue = maxi(int(data.get("lifetime_revenue", 0)), 0)
	_contracts_completed = maxi(int(data.get("contracts_completed", 0)), 0)
	_contracts_abandoned = maxi(int(data.get("contracts_abandoned", 0)), 0)
	_yard = clampi(int(data.get("yard", Yard.STARTER)), Yard.STARTER, Yard.LEADING)
	_last_competitor_minutes = float(data.get("last_competitor_minutes", 0.0))

	# A save with no competitor commitments in it was written when rivals had no
	# fleet limit, and the honest reading of that is four firms with nothing in
	# hand. They fill up again within a day or two of play.
	_competitor_work = {}
	var held: Dictionary = data.get("competitor_work", {})
	for key: Variant in held:
		var days: Array = []
		for value: Variant in held[key]:
			days.append(int(value))
		_competitor_work[String(key)] = days

	_reviews.clear()
	for entry: Variant in data.get("reviews", []):
		if entry is Dictionary:
			_reviews.append((entry as Dictionary).duplicate())
	while _reviews.size() > REVIEW_HISTORY:
		_reviews.pop_back()

	_customers.clear()
	for entry: Variant in data.get("customers", []):
		if not (entry is Dictionary):
			continue
		var record: Dictionary = (entry as Dictionary).duplicate()
		if not record.has("id"):
			continue
		record["loyalty"] = clampf(float(record.get("loyalty", LOYALTY_START)), 0.0, 100.0)
		record["lapsed"] = bool(record.get("lapsed", false))
		record["offered_job_id"] = String(record.get("offered_job_id", ""))
		_customers[String(record["id"])] = record

	_market_window.clear()
	for entry: Variant in data.get("market_window", []):
		if entry is Dictionary:
			_market_window.append((entry as Dictionary).duplicate())

	_schedule.clear()
	for entry: Variant in data.get("schedule", []):
		_schedule.append(String(entry))

	reputation_changed.emit(_reputation)
	customers_changed.emit()
	competitors_changed.emit()
	schedule_changed.emit()
	yard_tier_changed.emit(_yard)


# ==================================================================== dev only

func dev_set_reputation(value: float) -> void:
	_reputation = clampf(value, MIN_REPUTATION, MAX_REPUTATION)
	reputation_changed.emit(_reputation)
	_reconsider_yard()


func dev_add_revenue(amount: int) -> void:
	_lifetime_revenue += maxi(amount, 0)
	_reconsider_yard()
