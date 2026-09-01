class_name ACAServiceTerritory
extends Node
## WHERE THE BUSINESS IS ALLOWED TO WORK. Autoloaded as `Territory`.
##
## The game used to have one market: every kind of property in the entire
## catalogue was on the board from the first morning, and the only thing that
## changed as the business grew was how much it could afford. This is the system
## that makes GEOGRAPHY a progression.
##
##   A REGION is a market. It has its own kinds of property, its own competitive
##   pressure and its own hub to work out of.
##   A SERVICE LOT is a building the business buys, once, out of money it
##   already has. Buying it is what unlocks the region.
##   LOCAL PRESENCE is how established the business is INSIDE a region it has
##   already entered. It never unlocks anything: it is the record of the work.
##
## ---------------------------------------------------------------------------
## A CONTRACT'S REGION IS DERIVED, NEVER STORED
## ---------------------------------------------------------------------------
## Exactly like `ACAContractTerms`, and for exactly the same reasons. A
## contract's region is a pure function of its property type, its size and its
## own seed, so:
##
##   * the same contract is always in the same place, in any build;
##   * a save written before territories existed loads with every one of its
##     contracts already correctly placed, because the placement was always
##     implicit in what the contract was;
##   * the mapping can be retuned without a save migration.
##
## What IS stored is what the business has BOUGHT and what it has DONE, and
## neither of those can be reconstructed from anything.
##
## ---------------------------------------------------------------------------
## NO FINANCING, EVER
## ---------------------------------------------------------------------------
## A service lot is paid for once, in full, out of `GameSession.money()`. There
## is no mortgage, no instalment, no interest and no rent, and there must never
## be. See the project's permanent financial exclusions.
##
## PUBLIC API
##   Region / REGIONS / REGION_ORDER / region_name(region) / region_of(...)
##   static region_for_job(job) -> int          THE derivation
##   static base_region_for_type(property_type) -> int
##   owns(region) / owned_regions() / owned_region_count()
##   is_home(region) / home_region() -> int
##   purchase_cost(region) / requirements(region) / requirement_lines(region)
##   can_purchase(region) -> Dictionary          { allowed, reason }
##   try_purchase_lot(region) -> bool
##   active_region() / set_active_region(region)  where the player is working from
##   presence(region) / presence_band(region) / presence_line(region)
##   note_completed_contract(job, paid) / note_lost_contract(job)
##   accepts_offer(job) -> bool                  the Job System's filter
##   demand_line(region) / competitor_line(region)
##   to_save_dict() / from_save_dict(data)
##
## SIGNALS
##   regions_changed()                a lot was bought, or a save was restored
##   region_purchased(region)         one lot, once, for the presentation
##   active_region_changed(region)    the player moved to another hub
##   presence_changed(region)
##
## INVARIANTS
##   * The home region is owned by every business, always, and can never be
##     bought, sold or lost.
##   * `try_purchase_lot()` takes the money exactly once, through
##     `GameSession.try_spend()`, and changes nothing when it returns false.
##   * `region_for_job()` is pure and static: no nodes, no state, no clock.
##
## PERSISTENCE OWNERSHIP
##   Owns the `territory` section of the save file: which lots are owned, the
##   presence record per region, and which hub the player was last working from.

# ------------------------------------------------------------------- signals
signal regions_changed()
signal region_purchased(region: int)
signal active_region_changed(region: int)
signal presence_changed(region: int)

# =============================================================== the regions

## FIVE, and no more. Each one is a different KIND of market with a hub that
## looks nothing like the others; a sixth would be a sixth place to build and a
## sixth set of numbers to balance, for no decision the player does not already
## have.
enum Region {
	HOME_TOWN,
	RURAL_HIGHWAY,
	COMMERCIAL_DISTRICT,
	CIVIC_PARK,
	HOSPITALITY_STRIP,
}

## Progression order, so nothing has to sort an enum. Also the order the
## expansion screen lists them in.
##
## THE ORDER IS THE GEOGRAPHY, and it reads as a business physically reaching
## further out: the streets it started on, the city next door, the regional
## centre beyond that, the highway out of the county, and finally the public
## green space nobody small is trusted with.
##
##     SMALL TOWN -> MEDIUM CITY -> BIG TOWN -> RURAL HIGHWAY -> COUNTRY PARKS
##
## The ENUM NAMES are the ones the first territory pass shipped and are what a
## save file's region ids are built from, so they are deliberately left alone.
## What a region IS lives in `REGIONS` below, and that is what moved.
const REGION_ORDER: Array[int] = [
	Region.HOME_TOWN,
	Region.COMMERCIAL_DISTRICT,
	Region.HOSPITALITY_STRIP,
	Region.RURAL_HIGHWAY,
	Region.CIVIC_PARK,
]

## THE HOME REGION IS NOT FOR SALE. A business starts here and stays here.
const HOME_REGION := Region.HOME_TOWN

## Everything about a region that is not state.
##
##   `cost`          what the service lot costs, before difficulty and market.
##   `reputation`    the standing the business needs before the seller will deal.
##   `contracts`     completed contracts it needs to have behind it.
##   `hub`           which hub layout the region's screen builds. HOME uses the
##                   authored Business Town; the rest are procedural.
##   `types`         property types whose work is native to this region.
##   `demand`        one line about what the market there is like.
##   `recommends`    the equipment the seller would tell you to bring.
const REGIONS := {
	Region.HOME_TOWN: {
		"id": &"home_town",
		"name": "Small Town",
		"short": "TOWN",
		"blurb": "The streets the business started on. A main street, a few "
			+ "side roads, gardens, verges and the occasional shop front.",
		"cost": 0,
		"reputation": 0.0,
		"contracts": 0,
		"hub": &"town",
		"colour": Color(0.400, 0.612, 0.337),
		"types": [
			ACAJobEnums.PropertyType.RESIDENTIAL,
			ACAJobEnums.PropertyType.COMMUNITY,
		],
		"demand": "Steady, small and close together.",
		"recommends": "A walk-behind machine handles most of it.",
	},
	Region.COMMERCIAL_DISTRICT: {
		"id": &"commercial_district",
		"name": "Medium City",
		"short": "CITY",
		"blurb": "A denser town an hour up the road, with a service yard behind "
			+ "the trade units. Forecourts, landscaped strips and school grounds.",
		"cost": 7500,
		"reputation": 45.0,
		"contracts": 10,
		"hub": &"commercial",
		"colour": Color(0.435, 0.522, 0.612),
		"types": [
			ACAJobEnums.PropertyType.COMMERCIAL,
			ACAJobEnums.PropertyType.INSTITUTIONAL,
		],
		"demand": "Repeat work on a schedule, and it wants collecting.",
		"recommends": "A catcher, and the capacity to empty it.",
	},
	Region.HOSPITALITY_STRIP: {
		"id": &"hospitality_strip",
		"name": "Big Town",
		"short": "BIG TOWN",
		"blurb": "The regional centre. A broad arterial, civic frontage, and "
			+ "the largest developed grounds anywhere on the map.",
		"cost": 16000,
		"reputation": 56.0,
		"contracts": 20,
		"hub": &"hospitality",
		"colour": Color(0.694, 0.478, 0.545),
		"types": [
			ACAJobEnums.PropertyType.HOSPITALITY,
		],
		"demand": "Large, visible, and it pays for the trouble.",
		"recommends": "A striping roller, and a machine that collects.",
	},
	Region.RURAL_HIGHWAY: {
		"id": &"rural_highway",
		"name": "Rural Highway",
		"short": "RURAL",
		"blurb": "A service lot on the highway out of the county, with open "
			+ "country either side of it and acreage to cut.",
		"cost": 26000,
		"reputation": 64.0,
		"contracts": 32,
		"hub": &"rural",
		"colour": Color(0.729, 0.639, 0.361),
		"types": [
			ACAJobEnums.PropertyType.RURAL,
			ACAJobEnums.PropertyType.INDUSTRIAL,
		],
		"demand": "Fewer contracts, and every one of them is bigger.",
		"recommends": "A rider, and something to side-discharge with.",
	},
	Region.CIVIC_PARK: {
		"id": &"civic_park",
		"name": "Country Parks",
		"short": "PARKS",
		"blurb": "A maintenance compound on the edge of the regional parks. "
			+ "Enormous public ground, long contracts, and areas not to be cut.",
		"cost": 40000,
		"reputation": 72.0,
		"contracts": 46,
		"hub": &"civic",
		"colour": Color(0.373, 0.580, 0.451),
		"types": [
			ACAJobEnums.PropertyType.PUBLIC,
		],
		"demand": "Large agreements, awarded on standing rather than price.",
		"recommends": "Wide decks, and the patience for a conservation zone.",
	},
}

## Where a KIND of property is, before the local exception below. Every property
## type in `ACAJobEnums` appears exactly once, so no contract can ever be
## homeless.
const BASE_REGION := {
	ACAJobEnums.PropertyType.RESIDENTIAL: Region.HOME_TOWN,
	ACAJobEnums.PropertyType.COMMUNITY: Region.HOME_TOWN,
	ACAJobEnums.PropertyType.RURAL: Region.RURAL_HIGHWAY,
	ACAJobEnums.PropertyType.INDUSTRIAL: Region.RURAL_HIGHWAY,
	ACAJobEnums.PropertyType.COMMERCIAL: Region.COMMERCIAL_DISTRICT,
	ACAJobEnums.PropertyType.INSTITUTIONAL: Region.COMMERCIAL_DISTRICT,
	ACAJobEnums.PropertyType.PUBLIC: Region.CIVIC_PARK,
	ACAJobEnums.PropertyType.HOSPITALITY: Region.HOSPITALITY_STRIP,
}

## THE LOCAL EXCEPTION, and the reason the starting market is not two property
## types wide.
##
## A small shop, a neighbourhood green and a village school ARE in the town the
## business works in - they are simply not what the trade calls commercial,
## civic or institutional work. So a seeded minority of the SMALLER contracts of
## those three kinds are local, and the player meets them from day one.
##
##   `share`     how many of that type's small work is local.
##   `max_size`  the largest contract this exception applies to. A district
##               shopping centre is never round the corner.
const LOCAL_EXCEPTION := {
	ACAJobEnums.PropertyType.COMMERCIAL: {
		"share": 0.45, "max_size": ACAJobEnums.LawnSize.SMALL,
	},
	ACAJobEnums.PropertyType.PUBLIC: {
		"share": 0.30, "max_size": ACAJobEnums.LawnSize.MEDIUM,
	},
	ACAJobEnums.PropertyType.INSTITUTIONAL: {
		"share": 0.25, "max_size": ACAJobEnums.LawnSize.MEDIUM,
	},
}

## THE SCALE PROMOTION, and the reason Big Town is a bigger market rather than
## a differently-coloured one.
##
## A district shopping centre, a hospital campus and a college green are not the
## same trade as a parade of shops and a village school - they are the work a
## REGIONAL CENTRE has and a market town does not. So the LARGEST contracts of
## those two kinds are promoted out of the Medium City and into Big Town.
##
## This is still a pure function of the property type and its size, so a
## contract's region stays derivable from the contract and no save carries one.
##
##   `at_or_above`  the smallest size that is promoted.
##   `to`           where it goes.
const SCALE_PROMOTION := {
	ACAJobEnums.PropertyType.COMMERCIAL: {
		"at_or_above": ACAJobEnums.LawnSize.LARGE, "to": Region.HOSPITALITY_STRIP,
	},
	ACAJobEnums.PropertyType.INSTITUTIONAL: {
		"at_or_above": ACAJobEnums.LawnSize.LARGE, "to": Region.HOSPITALITY_STRIP,
	},
}

# ============================================================= local presence

## Presence runs 0-100 inside a region the business has entered.
const PRESENCE_MIN := 0.0
const PRESENCE_MAX := 100.0
## What a region starts at the moment its lot is bought: known to nobody.
const PRESENCE_START := 8.0
## The home region begins with the business already established on it.
const HOME_PRESENCE_START := 30.0

## A completed contract moves presence by this, scaled by how big it was.
const PRESENCE_PER_CONTRACT := 3.2
## ...and losing an offer to a rival in that region takes a little back.
const PRESENCE_PER_LOSS := 1.1

const PRESENCE_BANDS := [
	{"at": 0.0, "name": "Unknown", "note": "Nobody here has heard of the business yet."},
	{"at": 22.0, "name": "Noticed", "note": "The name is starting to come up."},
	{"at": 45.0, "name": "Established", "note": "A known operator in this market."},
	{"at": 68.0, "name": "Preferred", "note": "Work here is offered to the business first."},
	{"at": 86.0, "name": "Dominant", "note": "The firm this market measures itself against."},
]

## Presence a region needs before it will put a MAJOR service agreement on the
## board. Read by `ACAServiceAgreements`; kept here because it is a fact about
## the territory rather than about the agreement.
const AGREEMENT_PRESENCE := 40.0

# --------------------------------------------------------------------- state
## `{ region_int: true }`. The home region is always in it.
var _owned: Dictionary = {}
## `{ region_int: float }`, 0-100.
var _presence: Dictionary = {}
## `{ region_int: int }`, contracts completed in that region.
var _completed: Dictionary = {}
## The hub the player is currently operating out of.
var _active: int = HOME_REGION


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	reset_to_new_business()


func reset_to_new_business() -> void:
	_owned = {int(HOME_REGION): true}
	_presence = {int(HOME_REGION): HOME_PRESENCE_START}
	_completed = {}
	_active = HOME_REGION
	regions_changed.emit()
	active_region_changed.emit(_active)


# ================================================================= the table

static func region_spec(region: int) -> Dictionary:
	return REGIONS.get(region, REGIONS[Region.HOME_TOWN])


static func region_name(region: int) -> String:
	return String(region_spec(region)["name"])


## Three-to-ten letters, for a tab or a chip.
static func region_short_name(region: int) -> String:
	return String(region_spec(region)["short"])


static func region_id(region: int) -> StringName:
	return StringName(region_spec(region)["id"])


static func region_colour(region: int) -> Color:
	return region_spec(region)["colour"]


static func region_blurb(region: int) -> String:
	return String(region_spec(region)["blurb"])


static func hub_kind(region: int) -> StringName:
	return StringName(region_spec(region)["hub"])


static func is_valid_region(region: int) -> bool:
	return REGIONS.has(region)


## Turn a stored id back into a region. -1 when it is not one.
static func region_from_id(id: StringName) -> int:
	for region: int in REGIONS:
		if StringName(REGIONS[region]["id"]) == id:
			return region
	return -1


func home_region() -> int:
	return HOME_REGION


func is_home(region: int) -> bool:
	return region == HOME_REGION


# ================================================= THE derivation, pure

## Where a KIND of property is before the local exception. Public because the
## expansion screen lists a region's native work from it.
static func base_region_for_type(property_type: int) -> int:
	return int(BASE_REGION.get(property_type, Region.HOME_TOWN))


## WHICH REGION THIS CONTRACT IS IN. Pure, static, derived from the contract and
## nothing else - see the note at the top of the file.
static func region_for_job(job: ACAJob) -> int:
	if job == null:
		return Region.HOME_TOWN
	return region_for(int(job.property_type), job.seed, int(job.lawn_size))


static func region_for(property_type: int, job_seed: int, lawn_size: int) -> int:
	var base := base_region_for_type(property_type)
	if base == Region.HOME_TOWN:
		return base
	# THE BIGGEST WORK OF ITS KIND IS IN THE REGIONAL CENTRE. Checked before the
	# local exception, which only ever applies to smaller contracts anyway, so
	# the two rules cannot fight over the same one.
	var promotion: Dictionary = SCALE_PROMOTION.get(property_type, {})
	if not promotion.is_empty() and lawn_size >= int(promotion["at_or_above"]):
		return int(promotion["to"])
	var exception: Dictionary = LOCAL_EXCEPTION.get(property_type, {})
	if exception.is_empty() or lawn_size > int(exception["max_size"]):
		return base
	# ITS OWN STREAM, mixed with a constant of its own, so this never consumes,
	# reorders or collides with the draws the job generator, the property
	# generator or the contract terms make from the same seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = (job_seed ^ 0x7E881707) & 0x7FFFFFFF
	return Region.HOME_TOWN if rng.randf() < float(exception["share"]) else base


## The kinds of property whose work is native to a region, as player-facing
## text. Includes anything PROMOTED here by scale, so the expansion screen tells
## a player the regional centre has the big commercial work rather than leaving
## them to find out.
static func native_work_line(region: int) -> String:
	var names := PackedStringArray()
	for property_type: int in region_spec(region)["types"]:
		names.append(ACAJobEnums.property_type_name(property_type))
	for property_type: int in SCALE_PROMOTION:
		var promotion: Dictionary = SCALE_PROMOTION[property_type]
		if int(promotion["to"]) != region:
			continue
		names.append("Large %s" % ACAJobEnums.property_type_name(property_type))
	return ", ".join(names)


# =============================================================== what is owned

func owns(region: int) -> bool:
	return region == HOME_REGION or bool(_owned.get(int(region), false))


## Owned regions in progression order.
func owned_regions() -> Array[int]:
	var out: Array[int] = []
	for region in REGION_ORDER:
		if owns(region):
			out.append(region)
	return out


func owned_region_count() -> int:
	return owned_regions().size()


## Regions that could still be bought, in progression order.
func available_regions() -> Array[int]:
	var out: Array[int] = []
	for region in REGION_ORDER:
		if not owns(region):
			out.append(region)
	return out


func has_expanded() -> bool:
	return owned_region_count() > 1


# ================================================================== buying

## What the lot costs RIGHT NOW. -1 when it is already owned or unknown, so a
## caller cannot show a price for nothing.
##
## The difficulty scales it exactly as it scales a machine, and the market is
## applied on top through `Economy.equipment_price()`. The UI shows what this
## returns and the player is charged what this returns; there is no second
## calculation anywhere.
func purchase_cost(region: int) -> int:
	if not is_valid_region(region) or owns(region):
		return -1
	var raw := int(round(float(REGIONS[region]["cost"])
		* ACADifficulty.value("upgrade_cost_scale", 1.0)))
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return maxi(int(round(float(raw) / 5.0)) * 5, 0)
	return economy.equipment_price(raw)


## What the seller wants beyond the money, as measured values.
## `{ reputation, contracts }`.
func requirements(region: int) -> Dictionary:
	var spec := region_spec(region)
	return {
		"reputation": float(spec["reputation"]),
		"contracts": int(spec["contracts"]),
	}


## Whether the business may buy this lot, and why not. `{ allowed, reason }`.
##
## THE REASON IS ALWAYS GIVEN. A greyed-out button with no explanation is the
## worst possible answer to "why can I not do this".
func can_purchase(region: int) -> Dictionary:
	if not is_valid_region(region):
		return {"allowed": false, "reason": "There is no such service area."}
	if owns(region):
		return {"allowed": false, "reason": "The business already works here."}

	var business := get_node_or_null(^"/root/Business")
	var wanted := requirements(region)
	if business != null:
		var reputation: float = business.call(&"reputation")
		if reputation < float(wanted["reputation"]):
			return {"allowed": false, "reason":
				"The seller wants a business with a standing of %d. Yours is %d."
				% [int(round(float(wanted["reputation"]))), int(round(reputation))]}
		var completed: int = business.call(&"contracts_completed")
		if completed < int(wanted["contracts"]):
			return {"allowed": false, "reason":
				"They want %d completed contracts behind you. You have %d."
				% [int(wanted["contracts"]), completed]}

	var cost := purchase_cost(region)
	var session := get_node_or_null(^"/root/GameSession")
	if session != null and not bool(session.call(&"can_afford", cost)):
		return {"allowed": false, "reason":
			"The lot is %s. There is no credit in this business."
			% UITheme.format_money(cost)}
	return {"allowed": true, "reason": ""}


## Buy the lot outright. True only when the money was actually taken.
func try_purchase_lot(region: int) -> bool:
	if not bool(can_purchase(region).get("allowed", false)):
		return false
	var cost := purchase_cost(region)
	var session := get_node_or_null(^"/root/GameSession")
	if session == null or not bool(session.call(&"try_spend", cost)):
		return false
	_owned[int(region)] = true
	_presence[int(region)] = PRESENCE_START
	regions_changed.emit()
	region_purchased.emit(region)
	presence_changed.emit(region)
	return true


# ========================================================== where we are now

## The hub the player is working out of. Always a region the business owns: a
## restored save whose lot has somehow gone answers HOME rather than stranding
## the player in a market they cannot reach.
func active_region() -> int:
	return _active if owns(_active) else HOME_REGION


func set_active_region(region: int) -> bool:
	if not owns(region) or _active == region:
		return owns(region)
	_active = region
	active_region_changed.emit(_active)
	return true


# ============================================================= local presence

func presence(region: int) -> float:
	if not owns(region):
		return 0.0
	return clampf(float(_presence.get(int(region), PRESENCE_START)),
		PRESENCE_MIN, PRESENCE_MAX)


func presence_band(region: int) -> Dictionary:
	var value := presence(region)
	var band: Dictionary = PRESENCE_BANDS[0]
	for entry: Dictionary in PRESENCE_BANDS:
		if value >= float(entry["at"]):
			band = entry
	return band


func presence_band_name(region: int) -> String:
	return String(presence_band(region)["name"])


func presence_line(region: int) -> String:
	return String(presence_band(region)["note"])


func contracts_completed_in(region: int) -> int:
	return int(_completed.get(int(region), 0))


## A finished contract in a region the business works. Called by `Business` once
## the contract is really settled, so there is one place a completion is
## recorded and one place it is counted.
##
## Bigger work moves presence further, because a market notices the park before
## it notices the verge.
func note_completed_contract(job: ACAJob, stars: int) -> void:
	if job == null:
		return
	var region := region_for_job(job)
	if not owns(region):
		return
	_completed[int(region)] = contracts_completed_in(region) + 1
	var size_weight := 1.0
	match int(job.lawn_size):
		ACAJobEnums.LawnSize.MEDIUM:
			size_weight = 1.35
		ACAJobEnums.LawnSize.LARGE:
			size_weight = 1.8
	# A poor job in a new market still puts the name about, but only just.
	var quality := clampf(float(stars) / 4.0, 0.25, 1.25)
	_move_presence(region, PRESENCE_PER_CONTRACT * size_weight * quality)


## An offer in one of the business's regions went to somebody else.
func note_lost_contract(job: ACAJob) -> void:
	if job == null:
		return
	var region := region_for_job(job)
	if owns(region):
		_move_presence(region, -PRESENCE_PER_LOSS)


## Move presence for something bigger than one contract - a service agreement
## served out, or dropped. Public because `ACABusiness` owns those events and
## this owns the number; a dev helper would have been the wrong door for a
## gameplay outcome.
func award_presence(region: int, delta: float) -> void:
	if owns(region):
		_move_presence(region, delta)


func _move_presence(region: int, delta: float) -> void:
	var before := presence(region)
	var after := clampf(before + delta, PRESENCE_MIN, PRESENCE_MAX)
	if is_equal_approx(before, after):
		return
	_presence[int(region)] = after
	presence_changed.emit(region)


# ====================================================== the Job System filter

## THE FILTER the job market runs every generated offer past.
##
## Set on `ACAJobManager.offer_filter_provider` by the application layer, so the
## Job System never learns what a region is: it rerolls until the host says yes.
## A locked region therefore never puts a contract on the board the player could
## not take.
func accepts_offer(job: ACAJob) -> bool:
	return owns(region_for_job(job))


## Every region a set of offers is spread across, in progression order. The job
## board builds its filter row from this rather than from the region table, so a
## market with nothing in it does not get a tab.
func regions_present_in(jobs: Array) -> Array[int]:
	var seen := {}
	for entry in jobs:
		var job := entry as ACAJob
		if job != null:
			seen[region_for_job(job)] = true
	var out: Array[int] = []
	for region in REGION_ORDER:
		if seen.has(region):
			out.append(region)
	return out


# =============================================================== persistence

## OWNERSHIP AND PRESENCE CANNOT BE RECONSTRUCTED. Both are written. Everything
## else about a region - its name, its price, its property types - comes from
## the constant table, so only the id ever appears in a save.
func to_save_dict() -> Dictionary:
	var owned := PackedStringArray()
	var presence_out := {}
	var completed_out := {}
	for region in REGION_ORDER:
		var id := String(region_id(region))
		if owns(region):
			owned.append(id)
			presence_out[id] = presence(region)
		if contracts_completed_in(region) > 0:
			completed_out[id] = contracts_completed_in(region)
	return {
		"owned": Array(owned),
		"presence": presence_out,
		"completed": completed_out,
		"active": String(region_id(active_region())),
	}


## A SAVE WRITTEN BEFORE TERRITORIES EXISTED was played on a business that could
## take any contract anywhere, and the honest reading of that is a business that
## had never bought a lot - so it loads owning the Home Town and nothing else.
##
## That is not a punishment and it does not lose the player anything they paid
## for: nobody paid for a service lot in a build that had none. What it DOES
## mean is that an old save's board narrows to local work on its next arrival,
## and the expansion screen is waiting for them with the money they already
## have. Its accepted contracts are untouched, wherever they are.
func from_save_dict(data: Dictionary) -> void:
	_owned = {int(HOME_REGION): true}
	_presence = {}
	_completed = {}

	for entry: Variant in data.get("owned", []):
		var region := region_from_id(StringName(String(entry)))
		if region >= 0:
			_owned[int(region)] = true

	var stored_presence: Dictionary = data.get("presence", {})
	for key: Variant in stored_presence:
		var region := region_from_id(StringName(String(key)))
		if region >= 0:
			_presence[int(region)] = clampf(float(stored_presence[key]),
				PRESENCE_MIN, PRESENCE_MAX)

	var stored_completed: Dictionary = data.get("completed", {})
	for key: Variant in stored_completed:
		var region := region_from_id(StringName(String(key)))
		if region >= 0:
			_completed[int(region)] = maxi(int(stored_completed[key]), 0)

	# A business that has always been here starts established, not unknown.
	if not _presence.has(int(HOME_REGION)):
		_presence[int(HOME_REGION)] = HOME_PRESENCE_START

	var active := region_from_id(StringName(String(data.get("active", ""))))
	_active = active if active >= 0 and owns(active) else HOME_REGION

	regions_changed.emit()
	active_region_changed.emit(_active)
	for region in owned_regions():
		presence_changed.emit(region)


# ==================================================================== dev only

func dev_grant_region(region: int) -> void:
	if not is_valid_region(region) or owns(region):
		return
	_owned[int(region)] = true
	_presence[int(region)] = PRESENCE_START
	regions_changed.emit()
	presence_changed.emit(region)


func dev_set_presence(region: int, value: float) -> void:
	if owns(region):
		_presence[int(region)] = clampf(value, PRESENCE_MIN, PRESENCE_MAX)
		presence_changed.emit(region)
