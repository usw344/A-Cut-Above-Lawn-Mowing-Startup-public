class_name ACAServiceAgreements
extends Node
## MAJOR SERVICE CONTRACTS. Autoloaded as `Agreements`.
##
## A contract in this game has always been one lawn, once. An AGREEMENT is the
## other kind of work a grounds business does: several related properties,
## serviced repeatedly, for a fixed term, won on standing rather than on price.
##
## ---------------------------------------------------------------------------
## IT IS BUILT OUT OF ORDINARY CONTRACTS
## ---------------------------------------------------------------------------
## An agreement owns no mowing, no property, no payment and no completion. Every
## visit it schedules is a REAL `ACAJob`, published on the real job board,
## accepted the normal way, driven to the normal way, and settled through
## `GameSession`'s one completion pathway. The agreement notices afterwards.
##
## That is deliberate and it is the whole design:
##
##   * nothing about mowing has to know agreements exist;
##   * an agreement visit pays exactly what that property is worth, once,
##     through the one balance in the game;
##   * a save can store an agreement in a few hundred bytes, because a visit is
##     a seed and a due day rather than a property.
##
## The agreement's own money is a COMPLETION BONUS paid when the term is served
## out. There is no second payment path and no per-visit retainer.
##
## ---------------------------------------------------------------------------
## THE SITES ARE FOUND, NOT INVENTED
## ---------------------------------------------------------------------------
## An agreement holds a handful of contract SEEDS. They are chosen by rolling
## seeds through `ACAJobGenerator.generate_core()` - the same pure function the
## market uses - until enough of them describe the kind of property the
## agreement is for. So an agreement's sites are properties the game would have
## generated anyway, they are the same ground every visit, and a returning
## customer record forms on them exactly as it does for ordinary work.
##
## PUBLIC API
##   offers() / active() / completed() / has_capacity_for(offer)
##   offer_for_region(region) -> Dictionary
##   can_accept(offer_id) -> Dictionary        { allowed, reason }
##   accept(offer_id) -> bool / decline(offer_id) -> bool
##   agreement_for_job(job) -> Dictionary      which agreement a contract serves
##   is_agreement_job(job) -> bool
##   note_completed_contract(job, stars) -> void
##   advance_to_day(today) -> void             THE heartbeat
##   summary_lines(agreement) -> Array
##   reset_to_new_business() / to_save_dict() / from_save_dict(data)
##
## SIGNALS
##   offers_changed()
##   agreement_started(agreement) / agreement_finished(agreement, honoured)
##   visit_due(agreement, job)
##   agreement_lost(agreement, competitor_name)
##
## INVARIANTS
##   * An agreement NEVER completes a contract, pays for one, or moves
##     reputation directly. It reads outcomes and awards its own bonus through
##     `GameSession`.
##   * A visit is published as an ordinary offer. If the player ignores it, it
##     expires like any other offer and the agreement counts a missed visit.
##   * Missing one visit never ends an agreement. See `MISSES_ALLOWED`.
##
## PERSISTENCE OWNERSHIP
##   Owns the `agreements` section of the save file.

# ------------------------------------------------------------------- signals
signal offers_changed()
signal agreement_started(agreement: Dictionary)
signal agreement_finished(agreement: Dictionary, honoured: bool)
signal visit_due(agreement: Dictionary, job: ACAJob)
signal agreement_lost(agreement: Dictionary, competitor_name: String)

# ============================================================== the templates

## The kinds of agreement the market offers, keyed by the region that offers
## them. Each region has exactly one, because an agreement is what that market
## does at scale rather than an item in a catalogue.
##
##   `sites`       how many related properties are on the agreement.
##   `rounds`      how many times each site is serviced over the term.
##   `interval`    world days between rounds.
##   `bonus_share` the completion bonus, as a share of the term's contract value.
##   `types`       property types the sites are chosen from.
##   `sizes`       contract sizes the sites are chosen from.
const TEMPLATES := {
	ACAServiceTerritory.Region.HOME_TOWN: {
		"id": &"residential_maintenance",
		"name": "Residential Maintenance Agreement",
		"blurb": "Three gardens on the same round, cut on a fortnightly rota "
			+ "for six weeks.",
		"sites": 3,
		"rounds": 3,
		"interval": 5,
		"bonus_share": 0.18,
		"types": [ACAJobEnums.PropertyType.RESIDENTIAL],
		"sizes": [ACAJobEnums.LawnSize.SMALL, ACAJobEnums.LawnSize.MEDIUM],
	},
	ACAServiceTerritory.Region.RURAL_HIGHWAY: {
		"id": &"rural_grounds",
		"name": "Rural Grounds Package",
		"blurb": "Two acreage properties on the highway, cut through the "
			+ "growing season.",
		"sites": 2,
		"rounds": 3,
		"interval": 7,
		"bonus_share": 0.20,
		"types": [ACAJobEnums.PropertyType.RURAL],
		"sizes": [ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE],
	},
	ACAServiceTerritory.Region.COMMERCIAL_DISTRICT: {
		"id": &"commercial_grounds",
		"name": "Commercial Grounds Package",
		"blurb": "Three trade forecourts under one contract, serviced weekly.",
		"sites": 3,
		"rounds": 3,
		"interval": 5,
		"bonus_share": 0.22,
		"types": [ACAJobEnums.PropertyType.COMMERCIAL],
		"sizes": [ACAJobEnums.LawnSize.SMALL, ACAJobEnums.LawnSize.MEDIUM],
	},
	ACAServiceTerritory.Region.CIVIC_PARK: {
		"id": &"municipal_park",
		"name": "Municipal Park Agreement",
		"blurb": "Two public greens maintained across a full month, "
			+ "conservation areas included.",
		"sites": 2,
		"rounds": 4,
		"interval": 7,
		"bonus_share": 0.24,
		"types": [ACAJobEnums.PropertyType.PUBLIC],
		"sizes": [ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE],
	},
	ACAServiceTerritory.Region.HOSPITALITY_STRIP: {
		"id": &"hospitality_grounds",
		"name": "Hospitality Grounds Agreement",
		"blurb": "Motel and venue grounds kept to a standard, every five days.",
		"sites": 3,
		"rounds": 3,
		"interval": 5,
		"bonus_share": 0.26,
		"types": [ACAJobEnums.PropertyType.HOSPITALITY],
		"sizes": [ACAJobEnums.LawnSize.MEDIUM, ACAJobEnums.LawnSize.LARGE],
	},
}

# ================================================================== balance

## How many missed visits an agreement tolerates before the customer takes it
## elsewhere. Two, so one bad day is a bad day and a pattern is a pattern.
const MISSES_ALLOWED := 2

## Days an OFFER of an agreement stands before somebody else takes it.
const OFFER_DAYS := 4

## Chance per day that a market with the presence for it puts an agreement up,
## once the business has none outstanding there.
const OFFER_CHANCE := 0.22

## How many agreements the business may hold at once, before its fleet is even
## considered. Two, because a third is a spreadsheet.
const MAX_ACTIVE := 2

## Machines an agreement needs the business to own, per site on it. A company
## with one mower cannot keep three forecourts on a weekly rota, and the
## qualification is the game saying so rather than the player finding out.
const MACHINES_PER_SITE := 0.5

## Seeds tried when choosing an agreement's sites. Generation is pure and cheap;
## this only has to be large enough that a template can always be filled.
const SITE_SEARCH_ATTEMPTS := 900

## How long an agreement's visit offer stands on the board, in game minutes.
## Longer than an ordinary offer: a scheduled visit is work the business already
## agreed to, so it should not lapse while the player finishes another contract.
const VISIT_OFFER_MINUTES := 900.0

# --------------------------------------------------------------------- state
## Agreements on the table. `{ id, region, template, sites, value, bonus,
## offered_day, expires_day }`
var _offers: Array[Dictionary] = []
## Agreements being served. Adds `{ round, visits_done, visits_missed,
## next_day, outstanding }`
var _active: Array[Dictionary] = []
## Finished agreements, newest first. Trimmed.
var _history: Array[Dictionary] = []
const HISTORY_LIMIT := 12

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()
var _last_day: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_rng.seed = 0x51C0DE ^ int(Time.get_unix_time_from_system())
	reset_to_new_business()


func reset_to_new_business() -> void:
	_offers.clear()
	_active.clear()
	_history.clear()
	_next_id = 1
	_last_day = -1
	offers_changed.emit()


# ==================================================================== reading

func offers() -> Array:
	var out: Array = []
	for entry in _offers:
		out.append(entry.duplicate(true))
	return out


func active() -> Array:
	var out: Array = []
	for entry in _active:
		out.append(entry.duplicate(true))
	return out


func completed() -> Array:
	var out: Array = []
	for entry in _history:
		out.append(entry.duplicate(true))
	return out


func active_count() -> int:
	return _active.size()


func has_offers() -> bool:
	return not _offers.is_empty()


static func template_for_region(region: int) -> Dictionary:
	return TEMPLATES.get(region, {})


func offer_for_region(region: int) -> Dictionary:
	for entry in _offers:
		if int(entry["region"]) == region:
			return entry.duplicate(true)
	return {}


func _find(list: Array[Dictionary], id: String) -> Dictionary:
	for entry in list:
		if String(entry["id"]) == id:
			return entry
	return {}


# ================================================================ qualifying

## Whether the business may take this agreement, and why not.
func can_accept(offer_id: String) -> Dictionary:
	var offer := _find(_offers, offer_id)
	if offer.is_empty():
		return {"allowed": false, "reason": "That agreement is no longer on the table."}
	if _active.size() >= MAX_ACTIVE:
		return {"allowed": false, "reason":
			"The business is already committed to %d agreements." % _active.size()}

	var region := int(offer["region"])
	var territory := get_node_or_null(^"/root/Territory")
	if territory != null and not bool(territory.call(&"owns", region)):
		return {"allowed": false, "reason": "The business does not work that area."}
	if territory != null:
		var presence: float = territory.call(&"presence", region)
		if presence < ACAServiceTerritory.AGREEMENT_PRESENCE:
			return {"allowed": false, "reason":
				"They award these to established operators. Do more work in this area first."}

	# FLEET CAPACITY, not cash. An agreement is a promise to be in several
	# places repeatedly, and the thing that makes that possible is machines.
	var needed := _machines_needed(offer)
	var owned := _machines_owned()
	if owned < needed:
		return {"allowed": false, "reason":
			"An agreement this size wants %d machines behind it. The business has %d."
			% [needed, owned]}
	return {"allowed": true, "reason": ""}


static func _machines_needed(offer: Dictionary) -> int:
	var sites := (offer.get("sites", []) as Array).size()
	return maxi(int(ceil(float(sites) * MACHINES_PER_SITE)), 1)


func _machines_owned() -> int:
	var equipment := get_node_or_null(^"/root/Equipment")
	if equipment == null:
		return 1
	return int(equipment.call(&"owned_mower_count")) \
		+ int(equipment.call(&"autonomous_unit_count"))


func has_capacity_for(offer: Dictionary) -> bool:
	return _machines_owned() >= _machines_needed(offer)


# ================================================================= accepting

func accept(offer_id: String) -> bool:
	if not bool(can_accept(offer_id).get("allowed", false)):
		return false
	var offer := _find(_offers, offer_id)
	if offer.is_empty():
		return false
	_offers.erase(offer)

	var today := _today()
	offer["round"] = 0
	offer["visits_done"] = 0
	offer["visits_missed"] = 0
	offer["started_day"] = today
	# The first round is scheduled for TOMORROW rather than for now: an
	# agreement signed this afternoon does not put three contracts on the board
	# beside the one the player is standing on.
	offer["next_day"] = today + 1
	offer["outstanding"] = []
	_active.append(offer)
	offers_changed.emit()
	agreement_started.emit(offer.duplicate(true))
	return true


func decline(offer_id: String) -> bool:
	var offer := _find(_offers, offer_id)
	if offer.is_empty():
		return false
	_offers.erase(offer)
	offers_changed.emit()
	return true


# =================================================================== the term

## THE HEARTBEAT. Driven by `GameSession` from `WorldClock.day_changed`, exactly
## as `Business` and `Clippings` are. Nothing here runs a clock of its own.
func advance_to_day(today: int) -> void:
	if today == _last_day:
		return
	_last_day = today
	_expire_offers(today)
	_advance_active(today)
	_maybe_offer(today)


func _expire_offers(today: int) -> void:
	var lapsed: Array[Dictionary] = []
	for entry in _offers:
		if today >= int(entry["expires_day"]):
			lapsed.append(entry)
	if lapsed.is_empty():
		return
	for entry in lapsed:
		_offers.erase(entry)
		# SOMEBODY ELSE TOOK IT. An agreement the player did not answer does not
		# evaporate; it goes to the firm that did answer, which is what makes
		# leaving one on the table cost something.
		var firm := _competitor_for(int(entry["region"]))
		agreement_lost.emit(entry.duplicate(true), firm)
	offers_changed.emit()


## The rival most likely to be awarded work in this region. Chosen from
## `ACABusiness`'s own table, so there is one list of firms in the game.
func _competitor_for(region: int) -> String:
	var best := "A competitor"
	var types: Array = ACAServiceTerritory.region_spec(region)["types"]
	for firm: Dictionary in ACABusiness.COMPETITORS:
		var prefers: Array = firm["prefers"]
		for property_type: int in types:
			if prefers.has(property_type):
				return String(firm["name"])
		if prefers.is_empty():
			best = String(firm["name"])
	return best


func _advance_active(today: int) -> void:
	var finished: Array[Dictionary] = []
	for entry in _active:
		_score_outstanding(entry, today)
		if today >= int(entry["next_day"]) and int(entry["round"]) < int(entry["rounds"]):
			_publish_round(entry, today)
		if _is_finished(entry):
			finished.append(entry)
	for entry in finished:
		_close(entry)


## Visits whose offer has passed its due day and was never completed.
func _score_outstanding(entry: Dictionary, today: int) -> void:
	var still: Array = []
	for record: Variant in entry["outstanding"]:
		var visit: Dictionary = record
		if today <= int(visit["due_day"]):
			still.append(visit)
			continue
		entry["visits_missed"] = int(entry["visits_missed"]) + 1
	entry["outstanding"] = still


## Put this round's contracts on the real job board.
func _publish_round(entry: Dictionary, today: int) -> void:
	var manager := get_node_or_null(^"/root/JobManager")
	if manager == null:
		return
	entry["round"] = int(entry["round"]) + 1
	entry["next_day"] = today + int(entry["interval"])
	var due := today + maxi(int(entry["interval"]) - 1, 1)
	var published := 0
	for site: Variant in entry["sites"]:
		var job: ACAJob = manager.call(&"commission_offer", int(site),
			VISIT_OFFER_MINUTES)
		if job == null:
			continue
		published += 1
		(entry["outstanding"] as Array).append({
			"seed": int(site), "job_id": String(job.id), "due_day": due,
		})
		visit_due.emit(entry.duplicate(true), job)
	if published > 0:
		offers_changed.emit()


func _is_finished(entry: Dictionary) -> bool:
	if int(entry["visits_missed"]) > MISSES_ALLOWED:
		return true
	var total := (entry["sites"] as Array).size() * int(entry["rounds"])
	var settled := int(entry["visits_done"]) + int(entry["visits_missed"])
	return int(entry["round"]) >= int(entry["rounds"]) \
		and (entry["outstanding"] as Array).is_empty() and settled >= total


func _close(entry: Dictionary) -> void:
	_active.erase(entry)
	var honoured := int(entry["visits_missed"]) <= MISSES_ALLOWED \
		and int(entry["visits_done"]) > 0
	entry["honoured"] = honoured
	entry["closed_day"] = _today()

	if honoured:
		# THE COMPLETION BONUS, and the agreement's only payment. Every visit
		# was already paid for as the contract it was.
		var session := get_node_or_null(^"/root/GameSession")
		if session != null:
			session.call(&"add_money", int(entry["bonus"]))
		var business := get_node_or_null(^"/root/Business")
		if business != null:
			business.call(&"note_agreement_honoured", int(entry["region"]))
	else:
		var business := get_node_or_null(^"/root/Business")
		if business != null:
			business.call(&"note_agreement_dropped", int(entry["region"]))

	_history.push_front(entry.duplicate(true))
	while _history.size() > HISTORY_LIMIT:
		_history.pop_back()
	offers_changed.emit()
	agreement_finished.emit(entry.duplicate(true), honoured)


# ============================================================ contract linkage

## Which agreement, if any, this contract is a visit for. Empty when it is
## ordinary work.
func agreement_for_job(job: ACAJob) -> Dictionary:
	if job == null:
		return {}
	for entry in _active:
		for record: Variant in entry["outstanding"]:
			if int((record as Dictionary)["seed"]) == job.seed:
				return entry.duplicate(true)
	return {}


func is_agreement_job(job: ACAJob) -> bool:
	return not agreement_for_job(job).is_empty()


## A contract was completed. Called by `Business` after the books are settled,
## so this can never run for work that did not really finish.
func note_completed_contract(job: ACAJob, _stars: int) -> void:
	if job == null:
		return
	for entry in _active:
		var outstanding: Array = entry["outstanding"]
		for record: Variant in outstanding:
			var visit: Dictionary = record
			if int(visit["seed"]) != job.seed:
				continue
			outstanding.erase(visit)
			entry["visits_done"] = int(entry["visits_done"]) + 1
			if _is_finished(entry):
				_close(entry)
			else:
				offers_changed.emit()
			return


# ================================================================== offering

## The market puts an agreement up, at most one per region at a time, and only
## where the business is established enough to be asked.
func _maybe_offer(today: int) -> void:
	var territory := get_node_or_null(^"/root/Territory")
	if territory == null or _active.size() >= MAX_ACTIVE:
		return
	for region: int in territory.call(&"owned_regions"):
		if not TEMPLATES.has(region):
			continue
		if float(territory.call(&"presence", region)) < ACAServiceTerritory.AGREEMENT_PRESENCE:
			continue
		if not offer_for_region(region).is_empty() or _has_active_in(region):
			continue
		if _rng.randf() >= OFFER_CHANCE:
			continue
		var offer := _compose_offer(region, today)
		if offer.is_empty():
			continue
		_offers.append(offer)
		offers_changed.emit()
		return


func _has_active_in(region: int) -> bool:
	for entry in _active:
		if int(entry["region"]) == region:
			return true
	return false


## Build one agreement: find its sites, price its term, and set its clock.
func _compose_offer(region: int, today: int) -> Dictionary:
	var template: Dictionary = TEMPLATES.get(region, {})
	if template.is_empty():
		return {}
	var sites := _find_sites(template)
	if sites.size() < int(template["sites"]):
		return {}

	# THE TERM'S VALUE is the sum of what its contracts are worth, taken from the
	# same generator the board prices offers with. Nothing here invents a number.
	var value := 0
	for site: int in sites:
		var core := ACAJobGenerator.generate_core(site)
		value += int(core["base_pay"])
	value *= int(template["rounds"])

	var id := "agreement_%d" % _next_id
	_next_id += 1
	return {
		"id": id,
		"region": region,
		"template": String(template["id"]),
		"name": String(template["name"]),
		"blurb": String(template["blurb"]),
		"sites": sites,
		"rounds": int(template["rounds"]),
		"interval": int(template["interval"]),
		"value": value,
		"bonus": int(round(float(value) * float(template["bonus_share"]))),
		"offered_day": today,
		"expires_day": today + OFFER_DAYS,
	}


## Roll seeds through the market's own pure generator until enough of them
## describe the kind of property this agreement is for.
func _find_sites(template: Dictionary) -> Array[int]:
	var wanted := int(template["sites"])
	var types: Array = template["types"]
	var sizes: Array = template["sizes"]
	var out: Array[int] = []
	for _attempt in SITE_SEARCH_ATTEMPTS:
		if out.size() >= wanted:
			break
		var candidate := _rng.randi() & 0x7FFFFFFF
		if out.has(candidate):
			continue
		var core := ACAJobGenerator.generate_core(candidate)
		if not types.has(int(core["property_type"])):
			continue
		if not sizes.has(int(core["lawn_size"])):
			continue
		out.append(candidate)
	return out


# =================================================================== display

## What an agreement says about itself, as rows for the office panel.
static func summary_lines(agreement: Dictionary) -> Array:
	if agreement.is_empty():
		return []
	var sites := (agreement.get("sites", []) as Array).size()
	var rounds := int(agreement.get("rounds", 0))
	var out: Array = [
		{"key": "Area", "value": ACAServiceTerritory.region_name(
			int(agreement.get("region", 0)))},
		{"key": "Properties", "value": "%d on the round" % sites},
		{"key": "Visits", "value": "%d over %d days" % [
			sites * rounds, rounds * int(agreement.get("interval", 0))]},
		{"key": "Contract value", "value": UITheme.format_money(
			int(agreement.get("value", 0)))},
		{"key": "Completion bonus", "value": UITheme.format_money(
			int(agreement.get("bonus", 0)))},
	]
	if agreement.has("visits_done"):
		var total := sites * rounds
		out.append({"key": "Progress", "value": "%d of %d visits" % [
			int(agreement["visits_done"]), total]})
		if int(agreement.get("visits_missed", 0)) > 0:
			out.append({"key": "Missed", "value": "%d of %d allowed" % [
				int(agreement["visits_missed"]), MISSES_ALLOWED]})
	return out


## A one-line status for an agreement being served.
static func status_line(agreement: Dictionary) -> String:
	var outstanding := (agreement.get("outstanding", []) as Array).size()
	if outstanding > 0:
		return "%d visit%s on the board now." % [
			outstanding, "" if outstanding == 1 else "s"]
	var next_day := int(agreement.get("next_day", 0))
	return "Next round on day %d." % (next_day + 1)


func _today() -> int:
	var clock := get_node_or_null(^"/root/WorldClock")
	return int(clock.call(&"day_index")) if clock != null else 0


# =============================================================== persistence

func to_save_dict() -> Dictionary:
	return {
		"offers": _offers.duplicate(true),
		"active": _active.duplicate(true),
		"history": _history.duplicate(true),
		"next_id": _next_id,
		"last_day": _last_day,
	}


## A save written before agreements existed loads with none, which is exactly
## true: nobody offered that business one. Nothing is invented to fill the gap.
func from_save_dict(data: Dictionary) -> void:
	_offers.clear()
	_active.clear()
	_history.clear()
	for entry: Variant in data.get("offers", []):
		if entry is Dictionary:
			_offers.append(_restore(entry as Dictionary))
	for entry: Variant in data.get("active", []):
		if entry is Dictionary:
			_active.append(_restore(entry as Dictionary))
	for entry: Variant in data.get("history", []):
		if entry is Dictionary:
			_history.append((entry as Dictionary).duplicate(true))
	_next_id = maxi(int(data.get("next_id", 1)), 1)
	_last_day = int(data.get("last_day", -1))
	offers_changed.emit()


## JSON turns every number into a float and every typed array into a plain one.
## Restoring the shapes here means nothing downstream has to guess.
static func _restore(raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	var sites: Array[int] = []
	for value: Variant in out.get("sites", []):
		sites.append(int(value))
	out["sites"] = sites
	var outstanding: Array = []
	for value: Variant in out.get("outstanding", []):
		if value is Dictionary:
			var visit: Dictionary = value
			outstanding.append({
				"seed": int(visit.get("seed", 0)),
				"job_id": String(visit.get("job_id", "")),
				"due_day": int(visit.get("due_day", 0)),
			})
	out["outstanding"] = outstanding
	for key in ["region", "rounds", "interval", "value", "bonus", "offered_day",
			"expires_day", "round", "visits_done", "visits_missed",
			"started_day", "next_day"]:
		if out.has(key):
			out[key] = int(out[key])
	return out


# ==================================================================== dev only

func dev_force_offer(region: int) -> Dictionary:
	var offer := _compose_offer(region, _today())
	if offer.is_empty():
		return {}
	_offers.append(offer)
	offers_changed.emit()
	return offer.duplicate(true)
