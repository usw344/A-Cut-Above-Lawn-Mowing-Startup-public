class_name ACAEquipment
extends Node
## WHAT THE BUSINESS OWNS. Autoloaded as `Equipment`.
##
## Two kinds of machine, one owner:
##
##   MOWERS            the three canonical machines the player drives. This owns
##                     WHICH of them the business has bought and which one is
##                     taken to the next contract. `MowerUpgrades` still owns
##                     what each one has been improved with, and `MowerFuel`
##                     still owns the tank.
##   AUTONOMOUS UNITS  machines that work without being driven. Owned outright,
##                     never hired and never financed.
##
## It owns no money (`GameSession` does), no prices beyond a base cost
## (`Economy` applies the market), no job state (`ACAJobManager` does) and no
## clipping inventory (`Clippings` does).
##
## ---------------------------------------------------------------------------
## WHY OWNERSHIP IS PER TYPE AND NOT PER MACHINE
## ---------------------------------------------------------------------------
## A business that owns "two riders, one of them with a better engine" needs a
## serial number on every machine, an upgrade record per serial, a selection UI
## that distinguishes them, and a save format that survives one being sold.
## None of that buys the player a decision they do not already have. So a mower
## type is owned or it is not, and `MowerUpgrades` improves THE one the business
## owns. Autonomous units ARE individually tracked, because owning three of them
## at once is the whole point of them.
##
## ---------------------------------------------------------------------------
## NO FINANCING, EVER
## ---------------------------------------------------------------------------
## Everything here is bought outright out of `GameSession.money()`. There is no
## credit, no instalment, no interest and no lease, and there must never be:
## the business grows by earning and saving. See the project's permanent
## financial exclusions.

# ------------------------------------------------------------------- signals
signal ownership_changed()
signal selected_mower_changed(mower_id: StringName)
signal autonomous_fleet_changed()
## The loadout for the next contract changed: an attachment was fitted or
## removed, the mowing mode was switched, or a machine was added to the trailer.
signal loadout_changed()

# ================================================================ the mowers

## THE STARTING MACHINE.
##
## The game has always put the player on the Rider from the first contract, and
## the whole economy - fuel share of revenue, contract rates, all three
## difficulty profiles - was tuned against that. Starting anyone on a different
## machine would move every one of those numbers, so the Rider is what a new
## business owns and the other two are things to buy.
const STARTING_MOWER := &"rider"

## What an unowned machine costs before the market and the difficulty.
##
## The Push Mower is CHEAP AND WORTH BUYING, which is the point of it: it burns
## no fuel at all, so on a Small contract it turns the fuel line of the job into
## zero. That is an operating decision rather than a straight upgrade, and it is
## the reason the cheapest machine in the shop is not simply the worst one.
const PURCHASE_COST := {
	"rider": 2400,
	"powered": 850,
	"push": 260,
}

## What each machine can carry when it is collecting, in kilograms.
##
## A Push Mower's box is small enough that a bagged Medium contract on one is a
## genuinely bad idea, which is what makes the recommendation on the work order
## mean something.
const BAG_CAPACITY_KG := {
	"rider": 90.0,
	"powered": 55.0,
	"push": 25.0,
}

## Which machine suits which contract size. Advisory - see `recommended_for()`.
const SIZE_SUITABILITY := {
	# lawn size -> machines, best first
	ACAJobEnums.LawnSize.SMALL: ["push", "powered", "rider"],
	ACAJobEnums.LawnSize.MEDIUM: ["powered", "rider", "push"],
	ACAJobEnums.LawnSize.LARGE: ["rider", "powered", "push"],
}

# =========================================================== autonomous units

## The three tiers, cheapest first. A SMALL progression on purpose: ten tiers
## would be ten prices and one decision.
##
##   `cells_per_minute`  lawn cells covered per GAME minute, off screen.
##   `max_size`          the largest contract this unit may be assigned to.
##   `bag_kg`            0 means it mulches and cannot take a collection contract.
##   `quality`           0-1, how tidy a finish it leaves. Feeds the review.
##   `escort_speed`      world units per REAL second when it is on the lawn
##                       beside the player.
##   `escort_deck`       half the width of its cut, in world units.
##
## THE TWO RATES ARE NOT THE SAME NUMBER, and they must not be derived from each
## other. Off screen a contract is settled by an estimate over game minutes,
## which run at six times real time; on screen the machine is a physical object
## that has to look like it is mowing. Converting one into the other - which the
## first version did, dividing `cells_per_minute` by a constant - gave an escort
## that crawled at three cells a second and would have taken an hour and a half
## to finish its section. They are declared separately, per tier, so each is the
## number it needs to be.
const AUTONOMOUS_TIERS := {
	"auto_compact": {
		"name": "Compact Autonomous Mower",
		"blurb": "Slow, patient, and happiest on a small lawn. Mulches; it has no catcher.",
		"cost": 1900,
		"cells_per_minute": 210.0,
		"max_size": ACAJobEnums.LawnSize.SMALL,
		"bag_kg": 0.0,
		"quality": 0.72,
		"fuel_per_minute": 0.10,
		"escort_speed": 2.6,
		"escort_deck": 0.55,
	},
	"auto_grounds": {
		"name": "Grounds Autonomous Mower",
		"blurb": "Quicker, reads obstacles better, and carries a catcher.",
		"cost": 4600,
		"cells_per_minute": 420.0,
		"max_size": ACAJobEnums.LawnSize.MEDIUM,
		"bag_kg": 40.0,
		"quality": 0.86,
		"fuel_per_minute": 0.16,
		"escort_speed": 3.6,
		"escort_deck": 0.90,
	},
	"auto_commercial": {
		"name": "Commercial Autonomous Unit",
		"blurb": "Wide deck, large catcher, and rated for a full grounds contract.",
		"cost": 9800,
		"cells_per_minute": 760.0,
		"max_size": ACAJobEnums.LawnSize.LARGE,
		"bag_kg": 100.0,
		"quality": 0.94,
		"fuel_per_minute": 0.26,
		"escort_speed": 4.6,
		"escort_deck": 1.35,
	},
}

## Tier ids in progression order, so UI never has to sort a Dictionary.
const AUTONOMOUS_ORDER: PackedStringArray = [
	"auto_compact", "auto_grounds", "auto_commercial",
]

## How many autonomous machines a business may own. A cap so the player cannot
## turn the game into a spreadsheet that mows itself.
const MAX_AUTONOMOUS_UNITS := 4

# --------------------------------------------------------------------- state
## `{ mower_id: true }`. Absent means not owned.
var _owned: Dictionary = {}
## The machine the next contract is started with.
var _selected: StringName = STARTING_MOWER
## Autonomous machines, each `{ uid, tier, job_id, finish_minutes, started_minutes }`.
## `job_id` empty means idle.
var _units: Array[Dictionary] = []
## Monotonic, so a unit's name is stable for the life of the business.
var _next_uid: int = 1
## The unit the player has asked to bring ALONG to the next driven contract.
var _escort_uid: int = 0

# ------------------------------------------------------------- the loadout
## `{ attachment_id: true }` - what the business has BOUGHT.
var _attachments: Dictionary = {}
## What is bolted on for the next contract, in the order it was fitted.
var _fitted: Array[StringName] = []
## Which of the three configurations the machine goes out in.
var _mode: int = ACAMowingMode.Mode.BAG
## The trailer behind the truck.
var _trailer: StringName = ACAHaulage.STARTING_TIER


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)
	reset_to_new_business()


func reset_to_new_business() -> void:
	_owned = {String(STARTING_MOWER): true}
	_selected = STARTING_MOWER
	_units.clear()
	_next_uid = 1
	_escort_uid = 0
	# THE CATCHER THE MACHINES HAVE ALWAYS HAD, and the trailer behind the
	# truck. See `ACAAttachments.STARTING_ATTACHMENTS`: a new business plays
	# exactly the game it played before attachments existed.
	_attachments = {}
	for id in ACAAttachments.STARTING_ATTACHMENTS:
		_attachments[String(id)] = true
	_fitted = [&"bagger"]
	_mode = ACAMowingMode.Mode.BAG
	_trailer = ACAHaulage.STARTING_TIER
	ownership_changed.emit()
	autonomous_fleet_changed.emit()
	loadout_changed.emit()


# =============================================================== mower owning

func owns(mower_id: String) -> bool:
	return bool(_owned.get(mower_id, false))


## Owned machines in the canonical order, so the shop and the pre-job picker
## always list them the same way.
func owned_mowers() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ACAMowerUpgrades.MOWER_IDS:
		if owns(id):
			out.append(id)
	return out


func owned_mower_count() -> int:
	return owned_mowers().size()


## Before the market and the difficulty. -1 for an unknown machine.
static func base_purchase_cost(mower_id: String) -> int:
	return int(PURCHASE_COST.get(mower_id, -1))


## What buying this machine costs RIGHT NOW. -1 when it is already owned or
## unknown, so a caller cannot show a price for nothing.
##
## The difficulty scales it exactly as it scales an upgrade, and the market is
## applied on top through `Economy.equipment_price()`. The UI shows what this
## returns and the player is charged what this returns; there is no second
## calculation anywhere.
func purchase_cost(mower_id: String) -> int:
	if owns(mower_id) or not PURCHASE_COST.has(mower_id):
		return -1
	var raw := int(round(float(PURCHASE_COST[mower_id])
		* ACADifficulty.value("upgrade_cost_scale", 1.0)))
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return maxi(int(round(float(raw) / 5.0)) * 5, 0)
	return economy.equipment_price(raw)


## Buy a machine outright. True only when the money was actually taken.
func try_purchase_mower(mower_id: String) -> bool:
	if not ACAMowerUpgrades.is_valid_mower(mower_id) or owns(mower_id):
		return false
	var cost := purchase_cost(mower_id)
	if cost < 0:
		return false
	var session := get_node_or_null(^"/root/GameSession")
	if session == null or not session.call(&"try_spend", cost):
		return false
	_owned[mower_id] = true
	ownership_changed.emit()
	return true


# ============================================================ mower selection

## The machine the next contract will be started with. Always one the business
## owns: if the selection ever became invalid it falls back to the first owned
## machine rather than sending the player to a contract with nothing to mow it.
func selected_mower() -> StringName:
	if owns(String(_selected)):
		return _selected
	var owned := owned_mowers()
	return StringName(owned[0]) if owned.size() > 0 else STARTING_MOWER


func select_mower(mower_id: String) -> bool:
	if not owns(mower_id):
		return false
	if String(_selected) == mower_id:
		return true
	_selected = StringName(mower_id)
	selected_mower_changed.emit(_selected)
	return true


## What the business would advise for this contract, and why. Advisory ONLY:
## nothing refuses a machine, because a player who wants to push-mow a Large
## rural contract has made a decision rather than a mistake.
##
## Returns `{ mower_id, reason }`. `mower_id` is always a machine the business
## actually owns.
func recommended_for(job: ACAJob) -> Dictionary:
	var owned := owned_mowers()
	if owned.is_empty():
		return {"mower_id": String(STARTING_MOWER), "reason": ""}
	if job == null:
		return {"mower_id": owned[0], "reason": ""}

	var order: Array = SIZE_SUITABILITY.get(job.lawn_size, ["rider"])
	var pick: String = owned[0]
	for candidate: String in order:
		if owned.has(candidate):
			pick = candidate
			break

	var reason := ""
	match job.lawn_size:
		ACAJobEnums.LawnSize.SMALL:
			reason = "A small lawn. The lighter machine finishes it and burns less doing it."
		ACAJobEnums.LawnSize.LARGE:
			reason = "A large contract. Bring the machine that covers ground."
		_:
			reason = "A medium lawn, and a walk-behind handles what is on it."
	if ACAContractTerms.requires_collection(job) and bag_capacity(pick) <= 0.0:
		reason = "This contract collects, and that machine has nowhere to put it."
	return {"mower_id": pick, "reason": reason}


# ================================================== attachments and loadout

## ---------------------------------------------------------------------------
## WHAT IS BOLTED ON, AND WHAT THE TRAILER CAN TAKE
## ---------------------------------------------------------------------------
## Ownership is per attachment, exactly like a mower type: the business either
## has a mulching kit in the shed or it does not, and there is no reason to
## track two of them. What CHANGES between contracts is which of them are
## FITTED, and that is a decision the player makes at the service lot.
##
## The rules are all in `ACAAttachments` and `ACAHaulage`. This owns the state
## and the transactions.

func owns_attachment(id: StringName) -> bool:
	return bool(_attachments.get(String(id), false))


## Everything the business has bought, in catalogue order.
func owned_attachments() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ACAAttachments.ORDER:
		if owns_attachment(id):
			out.append(id)
	return out


## What buying this costs RIGHT NOW. -1 when it is already owned or unknown.
func attachment_cost(id: StringName) -> int:
	if owns_attachment(id) or not ACAAttachments.is_valid(id):
		return -1
	var raw := int(round(float(ACAAttachments.base_cost(id))
		* ACADifficulty.value("upgrade_cost_scale", 1.0)))
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return maxi(int(round(float(raw) / 5.0)) * 5, 0)
	return economy.equipment_price(raw)


func try_purchase_attachment(id: StringName) -> bool:
	var cost := attachment_cost(id)
	if cost < 0:
		return false
	var session := get_node_or_null(^"/root/GameSession")
	if session == null or not bool(session.call(&"try_spend", cost)):
		return false
	_attachments[String(id)] = true
	ownership_changed.emit()
	return true


## What is on the machine for the next contract.
func fitted_attachments() -> Array[StringName]:
	return _fitted.duplicate()


func is_fitted(id: StringName) -> bool:
	return _fitted.has(id)


## Whether this could go on the machine that is going out, and why not.
## `{ allowed, reason }` - the reason is always given.
func can_fit(id: StringName) -> Dictionary:
	if not owns_attachment(id):
		return {"allowed": false, "reason": "The business does not own one."}
	if is_fitted(id):
		return {"allowed": false, "reason": "It is already on the machine."}
	var mower := String(selected_mower())
	if not ACAAttachments.fits(id, mower):
		return {"allowed": false, "reason": "It does not fit a %s."
			% ACAMowerUpgrades.mower_name(mower)}
	if attachment_slots_used() + ACAAttachments.slots_used([id]) \
			> ACAHaulage.attachment_slots(_trailer):
		return {"allowed": false, "reason":
			"No room on the %s. Take something off, or buy a bigger one."
			% ACAHaulage.display_name(_trailer)}
	return {"allowed": true, "reason": ""}


func fit_attachment(id: StringName) -> bool:
	if not bool(can_fit(id).get("allowed", false)):
		return false
	_fitted.append(id)
	_reconcile_mode()
	loadout_changed.emit()
	return true


func remove_attachment(id: StringName) -> bool:
	if not _fitted.has(id):
		return false
	_fitted.erase(id)
	_reconcile_mode()
	loadout_changed.emit()
	return true


func attachment_slots_used() -> int:
	return ACAAttachments.slots_used(_fitted)


func attachment_slot_capacity() -> int:
	return ACAHaulage.attachment_slots(_trailer)


# ------------------------------------------------------------ the mowing mode

## Which configuration the machine goes out in.
func mowing_mode() -> int:
	return _mode


func mowing_mode_name() -> String:
	return ACAMowingMode.mode_name(_mode)


## The configurations the fitted set makes available. Never empty in practice,
## because the bagger is owned and fitted from the first morning - but if a
## player strips the machine bare, bagging is what is offered back, because a
## machine with nothing on its deck is not one of the three configurations.
func available_modes() -> Array[int]:
	var modes := ACAAttachments.modes_available(_fitted)
	if modes.is_empty():
		modes.append(ACAMowingMode.Mode.BAG)
	return modes


func can_use_mode(mode: int) -> bool:
	return available_modes().has(mode)


func set_mowing_mode(mode: int) -> bool:
	if not can_use_mode(mode):
		return false
	if _mode != mode:
		_mode = mode
		loadout_changed.emit()
	return true


## Keep the selected mode honest after the fitted set changes. Taking the
## bagger off a machine set to bag has to leave it set to something it can
## actually do.
func _reconcile_mode() -> void:
	var modes := available_modes()
	if not modes.has(_mode):
		_mode = modes[0]


# ------------------------------------------------------------- the trailer

func trailer_tier() -> StringName:
	return _trailer


func trailer_name() -> String:
	return ACAHaulage.display_name(_trailer)


func trailer_cost(tier: StringName) -> int:
	if not ACAHaulage.is_valid(tier) or tier == _trailer:
		return -1
	if ACAHaulage.base_cost(tier) <= ACAHaulage.base_cost(_trailer):
		return -1
	var raw := int(round(float(ACAHaulage.base_cost(tier))
		* ACADifficulty.value("upgrade_cost_scale", 1.0)))
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return maxi(int(round(float(raw) / 5.0)) * 5, 0)
	return economy.equipment_price(raw)


func try_purchase_trailer(tier: StringName) -> bool:
	var cost := trailer_cost(tier)
	if cost < 0:
		return false
	var session := get_node_or_null(^"/root/GameSession")
	if session == null or not bool(session.call(&"try_spend", cost)):
		return false
	_trailer = tier
	ownership_changed.emit()
	loadout_changed.emit()
	return true


## Machine slots the current loadout uses: the driven machine, plus the escort
## if one is coming.
func machine_slots_used() -> int:
	var used := ACAHaulage.machine_slots_for(String(selected_mower()))
	var uid := escort_unit_uid()
	if uid != 0:
		used += ACAHaulage.autonomous_slots_for(String(unit(uid)["tier"]))
	return used


func machine_slot_capacity() -> int:
	return ACAHaulage.slots(_trailer)


## Whether this unit would physically fit on the trailer beside the machine that
## is going out. `{ allowed, reason }`.
func can_load_unit(uid: int) -> Dictionary:
	var entry := unit(uid)
	if entry.is_empty():
		return {"allowed": false, "reason": "No such machine."}
	if not String(entry["job_id"]).is_empty():
		return {"allowed": false, "reason": "It is out on a contract."}
	var used := ACAHaulage.machine_slots_for(String(selected_mower()))
	var wanted := ACAHaulage.autonomous_slots_for(String(entry["tier"]))
	if used + wanted > machine_slot_capacity():
		return {"allowed": false, "reason":
			"The %s will not take both." % ACAHaulage.display_name(_trailer)}
	return {"allowed": true, "reason": ""}


## Kilograms the trailer holds before it has to be emptied at a service lot.
func trailer_clipping_capacity() -> float:
	return ACAHaulage.clipping_capacity(_trailer)


## Spare fuel on the drawbar, in tank units.
func trailer_fuel_reserve() -> float:
	return ACAHaulage.fuel_reserve(_trailer)


## What is going out, as one dictionary for the depot panel, the work order and
## the mowing scene. Nothing recomputes any of it from the parts.
func loadout_summary() -> Dictionary:
	var names := PackedStringArray()
	for id in _fitted:
		names.append(ACAAttachments.display_name(id))
	var uid := escort_unit_uid()
	return {
		"mower_id": String(selected_mower()),
		"mower_name": ACAMowerUpgrades.mower_name(String(selected_mower())),
		"mode": _mode,
		"mode_name": ACAMowingMode.mode_name(_mode),
		"attachments": Array(names),
		"fitted": _fitted.duplicate(),
		"escort_uid": uid,
		"escort_name": unit_label(uid) if uid != 0 else "",
		"trailer": String(_trailer),
		"trailer_name": ACAHaulage.display_name(_trailer),
		"machine_slots": machine_slots_used(),
		"machine_capacity": machine_slot_capacity(),
		"attachment_slots": attachment_slots_used(),
		"attachment_capacity": attachment_slot_capacity(),
		"bag_capacity": selected_bag_capacity(),
		"pattern_bonus": ACAAttachments.pattern_bonus(_fitted),
	}


# ============================================================ bag capacities

## Kilograms this machine can carry. Zero means it does not collect at all.
##
## THREE THINGS DECIDE IT, and this is the one place they meet:
##
##   the MACHINE      what its own catcher holds. `BAG_CAPACITY_KG`.
##   the CONFIGURATION  a machine set to mulch or to side-discharge carries
##                    nothing, because there is nowhere for it to go. That is
##                    `ACAMowingMode.collects()` and there is no second rule.
##   what is BOLTED ON  a tow-behind sweeper nearly doubles it.
##
## `ACAClippings` is then given this number and never asks why: a capacity of
## zero is a machine that mulches, which is exactly what it already handled.
func bag_capacity(mower_id: String) -> float:
	if not ACAMowingMode.collects(_mode):
		return 0.0
	var base := float(BAG_CAPACITY_KG.get(mower_id, 0.0))
	if base <= 0.0:
		return 0.0
	base *= maxf(ACAAttachments.bag_multiplier(_fitted), 1.0)
	var clippings := get_node_or_null(^"/root/Clippings")
	if clippings == null:
		return base
	return base * float(clippings.call(&"bag_capacity_multiplier"))


## What the machine COULD carry if it were set to collect. What the shop shows
## against a catcher, and what the loadout screen compares two configurations
## with; never what `ACAClippings` is given.
func rated_bag_capacity(mower_id: String) -> float:
	var base := float(BAG_CAPACITY_KG.get(mower_id, 0.0))
	if base <= 0.0:
		return 0.0
	base *= maxf(ACAAttachments.bag_multiplier(_fitted), 1.0)
	var clippings := get_node_or_null(^"/root/Clippings")
	if clippings == null:
		return base
	return base * float(clippings.call(&"bag_capacity_multiplier"))


func selected_bag_capacity() -> float:
	return bag_capacity(String(selected_mower()))


# ========================================================= autonomous owning

static func tier_name(tier: String) -> String:
	var spec: Dictionary = AUTONOMOUS_TIERS.get(tier, {})
	return String(spec.get("name", tier.capitalize()))


static func tier_spec(tier: String) -> Dictionary:
	return AUTONOMOUS_TIERS.get(tier, {})


func autonomous_units() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for unit in _units:
		out.append(unit.duplicate())
	return out


func autonomous_unit_count() -> int:
	return _units.size()


func has_autonomous_units() -> bool:
	return not _units.is_empty()


func unit(uid: int) -> Dictionary:
	for entry in _units:
		if int(entry["uid"]) == uid:
			return entry
	return {}


## The player-facing name of one machine, e.g. "Grounds Autonomous Mower 2".
func unit_label(uid: int) -> String:
	var entry := unit(uid)
	if entry.is_empty():
		return ""
	return "%s %d" % [tier_name(String(entry["tier"])), uid]


func autonomous_cost(tier: String) -> int:
	if not AUTONOMOUS_TIERS.has(tier):
		return -1
	if _units.size() >= MAX_AUTONOMOUS_UNITS:
		return -1
	var raw := int(round(float(AUTONOMOUS_TIERS[tier]["cost"])
		* ACADifficulty.value("upgrade_cost_scale", 1.0)))
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return maxi(int(round(float(raw) / 5.0)) * 5, 0)
	return economy.equipment_price(raw)


## Buy one autonomous machine outright. Returns its uid, or 0 on failure.
func try_purchase_autonomous(tier: String) -> int:
	var cost := autonomous_cost(tier)
	if cost < 0:
		return 0
	var session := get_node_or_null(^"/root/GameSession")
	if session == null or not session.call(&"try_spend", cost):
		return 0
	var uid := _next_uid
	_next_uid += 1
	_units.append({
		"uid": uid,
		"tier": tier,
		"job_id": "",
		"started_minutes": 0.0,
		"finish_minutes": 0.0,
	})
	autonomous_fleet_changed.emit()
	ownership_changed.emit()
	return uid


func idle_units() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _units:
		if String(entry["job_id"]).is_empty():
			out.append(entry.duplicate())
	return out


func is_unit_busy(uid: int) -> bool:
	var entry := unit(uid)
	return not entry.is_empty() and not String(entry["job_id"]).is_empty()


# ====================================================== the escort assignment

## The unit the player has asked to bring to the contract they drive to
## themselves. Zero means none. Cleared when the contract finishes, because an
## escort is a decision about ONE job.
func escort_unit_uid() -> int:
	if _escort_uid == 0:
		return 0
	var entry := unit(_escort_uid)
	if entry.is_empty() or not String(entry["job_id"]).is_empty():
		return 0
	return _escort_uid


func set_escort_unit(uid: int) -> void:
	_escort_uid = uid if not unit(uid).is_empty() else 0
	autonomous_fleet_changed.emit()


func clear_escort_unit() -> void:
	if _escort_uid != 0:
		_escort_uid = 0
		autonomous_fleet_changed.emit()


## Whether an escort makes sense here. A unit whose tier is not rated for the
## contract's size stays in the yard: an off-screen unit on too big a job simply
## works slowly, but one standing on the lawn beside the player has to be able
## to finish the section it is given.
func can_escort(uid: int, job: ACAJob) -> bool:
	var entry := unit(uid)
	if entry.is_empty() or not String(entry["job_id"]).is_empty() or job == null:
		return false
	var spec := tier_spec(String(entry["tier"]))
	if spec.is_empty():
		return false
	return int(job.lawn_size) <= int(spec["max_size"]) + 1


# ================================================== off-screen contract work

## Put an owned unit on an available contract. The contract is ACCEPTED through
## the Job System exactly as the player would accept it, then worked off screen.
##
## Returns the game-minute the work will finish at, or -1.0 on refusal.
func assign_to_contract(uid: int, job_id: StringName) -> float:
	var entry := unit(uid)
	if entry.is_empty() or not String(entry["job_id"]).is_empty():
		return -1.0
	var manager := get_node_or_null(^"/root/JobManager")
	if manager == null:
		return -1.0
	var job: ACAJob = manager.call(&"get_job", job_id)
	if job == null:
		return -1.0
	var spec := tier_spec(String(entry["tier"]))
	if spec.is_empty() or int(job.lawn_size) > int(spec["max_size"]):
		return -1.0
	# A collection contract needs a machine with somewhere to put the clippings.
	if ACAContractTerms.requires_collection(job) and float(spec["bag_kg"]) <= 0.0:
		return -1.0
	# `for_machine`: the business is taking this contract, not the contractor.
	# The player's own one-at-a-time limit must not refuse it.
	if not manager.call(&"accept_job", job_id, true):
		return -1.0

	var clock := get_node_or_null(^"/root/WorldClock")
	var now: float = clock.call(&"game_minutes") if clock != null else 0.0
	var minutes := estimated_minutes_now(String(entry["tier"]), job)
	entry["job_id"] = String(job_id)
	entry["started_minutes"] = now
	entry["finish_minutes"] = now + minutes
	autonomous_fleet_changed.emit()
	return entry["finish_minutes"]


## HOW LONG A MACHINE TAKES, deterministically.
##
## Not a simulation and not a random draw: the mowable area of the property the
## contract would generate, divided by what the tier covers in a minute, with a
## penalty for how cluttered the property is. The same contract given to the
## same tier always takes the same time, which is what lets the player plan.
static func estimated_minutes(tier: String, job: ACAJob) -> float:
	var spec: Dictionary = AUTONOMOUS_TIERS.get(tier, {})
	if spec.is_empty() or job == null:
		return 0.0
	var cells := float(maxi(job.grid_size.x * job.grid_size.y, 1))
	# The generator excludes roughly a tenth of a contract for water, planting
	# and the things a machine has to go round. Taken as a flat share rather
	# than by generating the property, because an estimate must not cost a
	# property build.
	cells *= 0.9
	var rate := maxf(float(spec["cells_per_minute"]), 1.0)
	# A cluttered property is slower for a machine that has to work round things.
	var clutter := 1.0 + (1.0 - float(spec["quality"])) * 0.6
	return maxf(cells / rate * clutter, 4.0)


## THE SAME ESTIMATE, WITH TODAY'S GROUND IN IT.
##
## `estimated_minutes()` is static and stays static: it is what a tier can do on
## an ordinary lawn, it is what the tests pin, and it must not depend on the
## clock. This is the number a machine dispatched RIGHT NOW will actually take,
## and the difference between them is the weather.
##
## An autonomous unit in the wet takes about a fifth longer. It never fails and
## it never refuses: a machine the player bought that stops working because of a
## shower is an asset they cannot plan around, which is the opposite of what
## buying one is for. See `ACAGroundConditions.AUTONOMOUS_TIME_MULTIPLIER`.
func estimated_minutes_now(tier: String, job: ACAJob) -> float:
	var base := estimated_minutes(tier, job)
	# The property's own dryness is what decides how fast it sheds water, and it
	# is drawn from the contract's seed - so this is the ground the unit will
	# actually be standing on rather than an average.
	var dryness := 0.24
	if job != null:
		dryness = ACAPropertyParams.for_seed(job.seed,
			job.grid_size.x if job.grid_size.x > 0 else 96).dryness
	return base * ACAGroundConditions.autonomous_time_multiplier(
		ACAGroundConditions.current(dryness))


## Elapsed fraction of a unit's assignment, 0-1.
func unit_progress(uid: int) -> float:
	var entry := unit(uid)
	if entry.is_empty() or String(entry["job_id"]).is_empty():
		return 0.0
	var span := float(entry["finish_minutes"]) - float(entry["started_minutes"])
	if span <= 0.0:
		return 1.0
	var clock := get_node_or_null(^"/root/WorldClock")
	var now: float = clock.call(&"game_minutes") if clock != null else 0.0
	return clampf((now - float(entry["started_minutes"])) / span, 0.0, 1.0)


## Any unit whose work is finished, resolved through the ordinary completion
## pathway. Called by the application layer as the clock moves; it is never a
## timer of its own, because a system with its own clock and one that reads
## `WorldClock` will always drift apart eventually.
##
## Returns the number of contracts settled.
func resolve_finished_work(now_minutes: float) -> int:
	var settled := 0
	for entry in _units:
		if String(entry["job_id"]).is_empty():
			continue
		if now_minutes < float(entry["finish_minutes"]):
			continue
		if _settle_unit(entry):
			settled += 1
	return settled


func _settle_unit(entry: Dictionary) -> bool:
	var job_id := StringName(String(entry["job_id"]))
	var spec := tier_spec(String(entry["tier"]))
	entry["job_id"] = ""
	var session := get_node_or_null(^"/root/GameSession")
	if session == null:
		autonomous_fleet_changed.emit()
		return false
	var minutes := float(entry["finish_minutes"]) - float(entry["started_minutes"])
	var ok: bool = session.call(&"complete_autonomous_job", job_id,
		float(spec.get("quality", 0.8)), minutes, int(entry["uid"]),
		float(spec.get("bag_kg", 0.0)), float(spec.get("fuel_per_minute", 0.0)))
	autonomous_fleet_changed.emit()
	return ok


## Every unit's state, for the Business Office and the Job Office.
func fleet_summary() -> Array:
	var out: Array = []
	for entry in _units:
		var spec := tier_spec(String(entry["tier"]))
		var busy := not String(entry["job_id"]).is_empty()
		out.append({
			"uid": int(entry["uid"]),
			"tier": String(entry["tier"]),
			"name": unit_label(int(entry["uid"])),
			"busy": busy,
			"job_id": String(entry["job_id"]),
			"progress": unit_progress(int(entry["uid"])) if busy else 0.0,
			"max_size": int(spec.get("max_size", 0)),
			"bag_kg": float(spec.get("bag_kg", 0.0)),
			"quality": float(spec.get("quality", 0.0)),
		})
	return out


# =============================================================== persistence

## OWNERSHIP CANNOT BE RECONSTRUCTED, so all of it is stored. What is NOT stored
## is anything derivable: a unit's speed, capacity and price all come from its
## tier, so only the tier is written.
func to_save_dict() -> Dictionary:
	var owned := PackedStringArray()
	for id in ACAMowerUpgrades.MOWER_IDS:
		if owns(id):
			owned.append(id)
	var units: Array = []
	for entry in _units:
		units.append({
			"uid": int(entry["uid"]),
			"tier": String(entry["tier"]),
			"job_id": String(entry["job_id"]),
			"started_minutes": float(entry["started_minutes"]),
			"finish_minutes": float(entry["finish_minutes"]),
		})
	var attachments := PackedStringArray()
	for id in ACAAttachments.ORDER:
		if owns_attachment(id):
			attachments.append(String(id))
	var fitted := PackedStringArray()
	for id in _fitted:
		fitted.append(String(id))
	return {
		"owned_mowers": Array(owned),
		"selected_mower": String(_selected),
		"units": units,
		"next_uid": _next_uid,
		"escort_uid": _escort_uid,
		# THE LOADOUT. Additive, and every field has a defined meaning when it is
		# absent - see `from_save_dict()`. None of it is derivable: what the
		# business bought and what it bolted on this morning are decisions.
		"attachments": Array(attachments),
		"fitted": Array(fitted),
		"mowing_mode": int(_mode),
		"trailer": String(_trailer),
	}


## A SAVE WRITTEN BEFORE OWNERSHIP EXISTED was played on a business that owned
## whatever it had driven, and the honest reading of that is: the Rider, which
## the game has always started on, PLUS anything the player had spent money
## improving. A save with four levels of Bearing Kit on the Push Mower was
## plainly a save with a push mower in the shed, and taking it away because a
## new field is missing would be a patch stealing equipment.
func from_save_dict(data: Dictionary, upgrades: ACAMowerUpgrades = null) -> void:
	_owned = {}
	var listed: Array = data.get("owned_mowers", [])
	for id: Variant in listed:
		var mower_id := String(id)
		if ACAMowerUpgrades.is_valid_mower(mower_id):
			_owned[mower_id] = true

	if _owned.is_empty():
		_owned[String(STARTING_MOWER)] = true
		var levels := upgrades if upgrades != null else get_node_or_null(^"/root/MowerUpgrades")
		if levels != null:
			for mower_id in ACAMowerUpgrades.MOWER_IDS:
				for category in ACAMowerUpgrades.categories_for(mower_id):
					if int(levels.call(&"level", mower_id, category)) > 0:
						_owned[mower_id] = true
						break

	var wanted := String(data.get("selected_mower", String(STARTING_MOWER)))
	_selected = StringName(wanted) if owns(wanted) else STARTING_MOWER

	_units.clear()
	var raw: Array = data.get("units", [])
	for entry: Variant in raw:
		if not (entry is Dictionary):
			continue
		var record: Dictionary = entry
		var tier := String(record.get("tier", ""))
		if not AUTONOMOUS_TIERS.has(tier):
			continue
		_units.append({
			"uid": int(record.get("uid", 0)),
			"tier": tier,
			"job_id": String(record.get("job_id", "")),
			"started_minutes": float(record.get("started_minutes", 0.0)),
			"finish_minutes": float(record.get("finish_minutes", 0.0)),
		})
	_next_uid = maxi(int(data.get("next_uid", 1)), _highest_uid() + 1)
	_escort_uid = int(data.get("escort_uid", 0))
	_restore_loadout(data)

	ownership_changed.emit()
	autonomous_fleet_changed.emit()
	selected_mower_changed.emit(selected_mower())
	loadout_changed.emit()


## A SAVE WRITTEN BEFORE ATTACHMENTS EXISTED was played on machines that all had
## a catcher on them and a trailer behind the truck, because that is what the
## game was. So it loads owning the bagger, with the bagger fitted, set to bag,
## on the starting trailer - which is not a migration inventing equipment, it is
## writing down what that save already had.
##
## The same reasoning applies field by field rather than as a whole, so a save
## from a build that had attachments but not trailers still loads correctly.
func _restore_loadout(data: Dictionary) -> void:
	_attachments = {}
	var listed: Array = data.get("attachments", [])
	for entry: Variant in listed:
		var id := StringName(String(entry))
		if ACAAttachments.is_valid(id):
			_attachments[String(id)] = true
	if _attachments.is_empty():
		for id in ACAAttachments.STARTING_ATTACHMENTS:
			_attachments[String(id)] = true

	_fitted.clear()
	for entry: Variant in data.get("fitted", []):
		var id := StringName(String(entry))
		# OWNED AND COMPATIBLE, checked rather than trusted. A save that was
		# written while a different machine was selected must not put a
		# tow-behind sweeper on a push mower.
		if not ACAAttachments.is_valid(id) or not owns_attachment(id):
			continue
		if not ACAAttachments.fits(id, String(_selected)) or _fitted.has(id):
			continue
		_fitted.append(id)
	if _fitted.is_empty() and owns_attachment(&"bagger"):
		_fitted.append(&"bagger")

	var tier := StringName(String(data.get("trailer", String(ACAHaulage.STARTING_TIER))))
	_trailer = tier if ACAHaulage.is_valid(tier) else ACAHaulage.STARTING_TIER

	_mode = int(data.get("mowing_mode", ACAMowingMode.Mode.BAG))
	_reconcile_mode()


func _highest_uid() -> int:
	var highest := 0
	for entry in _units:
		highest = maxi(highest, int(entry["uid"]))
	return highest


# ==================================================================== dev only

func dev_grant_mower(mower_id: String) -> void:
	if ACAMowerUpgrades.is_valid_mower(mower_id):
		_owned[mower_id] = true
		ownership_changed.emit()


func dev_grant_attachment(id: StringName) -> void:
	if ACAAttachments.is_valid(id):
		_attachments[String(id)] = true
		ownership_changed.emit()


func dev_grant_trailer(tier: StringName) -> void:
	if ACAHaulage.is_valid(tier):
		_trailer = tier
		ownership_changed.emit()
		loadout_changed.emit()


func dev_grant_autonomous(tier: String) -> int:
	if not AUTONOMOUS_TIERS.has(tier):
		return 0
	var uid := _next_uid
	_next_uid += 1
	_units.append({
		"uid": uid, "tier": tier, "job_id": "",
		"started_minutes": 0.0, "finish_minutes": 0.0,
	})
	autonomous_fleet_changed.emit()
	return uid
