class_name ACAClippings
extends Node
## CUT GRASS AS A RESOURCE. Autoloaded as `Clippings`.
##
## Owns three things:
##
##   THE BAG        how much cut grass is in the machine right now.
##   THE STORE      how much the business has back at the yard, and how much of
##                  it is composting.
##   THE PRICE      what a kilogram is worth, fresh or composted.
##
## It owns no money (`GameSession` does) and no particles. The clippings thrown
## by the deck are `ACAMowingEffects` and are cosmetic; this is the ledger, and
## the two never speak.
##
## ---------------------------------------------------------------------------
## THE UNIT IS THE KILOGRAM
## ---------------------------------------------------------------------------
## One unit, everywhere, chosen because it is the one a player already has an
## intuition for. A machine carries kilograms, the yard stores kilograms, and
## the shop pays per kilogram. Nothing anywhere converts between two units.
##
## ---------------------------------------------------------------------------
## ONLY FRESH GRASS FILLS THE BAG
## ---------------------------------------------------------------------------
## `ACALawn.mow_deck()` returns the number of cells that went from UNCUT to CUT,
## and that return value - not the deck's area, not the time spent, not the
## particle count - is what this converts into weight. Driving over ground that
## is already mown produces exactly nothing, which is the behaviour a player
## expects and the only one that cannot be farmed.
##
## ---------------------------------------------------------------------------
## A FULL BAG STOPS COLLECTING. IT DOES NOT STOP MOWING.
## ---------------------------------------------------------------------------
## One rule, chosen and applied consistently: when the catcher is full the
## machine keeps cutting and the grass it cuts is left on the lawn. The contract
## still progresses, the lawn is still finished, and what the player loses is
## the COLLECTION - which is exactly what a full catcher costs in reality, and
## which is what a collection contract is scored on.
##
## The alternative - refusing to cut - was rejected: a machine that will not mow
## because a box is full turns a logistics decision into a wall, and it makes a
## contract failable in a way the player cannot undo without restarting.

signal bag_changed(kilograms: float, capacity: float)
signal bag_filled()
signal inventory_changed()
## Clippings moved from the machine into the truck. `kilograms` is what actually
## transferred, which is zero when the bag was already empty.
signal unloaded(kilograms: float)

## ---------------------------------------------------------------------------
## HOW MUCH GRASS A SQUARE METRE OF OVERDUE LAWN IS
## ---------------------------------------------------------------------------
## One lawn cell is one square world unit. At this rate a Medium contract
## (144 x 144, about 19,000 mowable cells) yields roughly 285 kg, which is a
## little over three Rider catchers - so a bagged Medium contract is three trips
## back to the truck. That is the number this was tuned to: enough that the truck
## matters, few enough that the contract is still mowing rather than errands.
const KG_PER_CELL := 0.015

## What a kilogram fetches before the market, fresh off the machine.
const FRESH_PRICE_PER_KG := 0.42
## ...and after it has been composted. Worth the wait, and not worth gaming:
## the whole store is only ever a supplement to contract income.
const COMPOST_PRICE_PER_KG := 1.05
## Composting loses mass as it breaks down. A real heap loses more than this;
## a third is enough to make the choice a choice.
const COMPOST_YIELD := 0.68
## World days a batch takes to become compost.
const COMPOST_DAYS := 4

## How much the yard can hold before the machine has nowhere to unload to.
## Raised by the storage upgrade.
const BASE_STORE_CAPACITY_KG := 400.0

## ------------------------------------------------------------- the upgrades
## Both change a number this class actually reads. There is no third upgrade,
## because there is no third number worth changing.
const UPGRADES := {
	"catcher": {
		"name": "Catcher Extension",
		"blurb": "A deeper box on every machine. Fewer trips back to the truck.",
		"values": [1.00, 1.25, 1.50, 1.80],
		"base_cost": 240,
		"cost_growth": 1.6,
		"unit": "bag capacity",
	},
	"yard_store": {
		"name": "Yard Storage",
		"blurb": "More room at the yard, so a full day's collection has somewhere to go.",
		"values": [1.00, 1.60, 2.30, 3.20],
		"base_cost": 300,
		"cost_growth": 1.6,
		"unit": "yard capacity",
	},
}

# --------------------------------------------------------------------- state
## Kilograms in the machine right now. Session state, saved with the contract.
var _bag_kg: float = 0.0
## Capacity of the machine currently in the scene. Set when a contract starts.
var _bag_capacity_kg: float = 0.0
## Kilograms of fresh clippings at the yard.
var _fresh_kg: float = 0.0
## Composting batches, `{ kilograms, ready_day }`. Kept as batches rather than a
## single pool so a heap started today does not become sellable because an older
## one did.
var _composting: Array[Dictionary] = []
## Finished compost, ready to sell.
var _compost_kg: float = 0.0
## `{ upgrade_id: level }`.
var _upgrade_levels: Dictionary = {}
## How much this contract has delivered to the truck, for scoring its terms.
var _delivered_this_job: float = 0.0
## Kilograms on the TRAILER: unloaded from the machine, not yet back at the
## yard. See `unload_to_truck()`.
var _trailer_kg: float = 0.0
## WHAT THE GROUND IS DOING TO THE YIELD. 1.0 is ordinary going; wet grass is
## heavier and dry grass is lighter. Set once when a contract starts, by the
## mowing runtime, from `ACAGroundConditions` - this class never asks the
## weather anything.
var _yield_multiplier: float = 1.0
## Kilograms the machine cut and could not carry, this contract. Not a penalty
## on its own - it is what the results sheet reports so a player can see why a
## collection term was missed.
var _spilled_this_job: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)


func reset_to_new_business() -> void:
	_bag_kg = 0.0
	_bag_capacity_kg = 0.0
	_fresh_kg = 0.0
	_compost_kg = 0.0
	_composting.clear()
	_upgrade_levels = {}
	_delivered_this_job = 0.0
	_spilled_this_job = 0.0
	_trailer_kg = 0.0
	_yield_multiplier = 1.0
	inventory_changed.emit()
	bag_changed.emit(_bag_kg, _bag_capacity_kg)


# ======================================================================= bag

## Called by the mowing runtime when a contract starts, and again if the player
## changes machines mid-contract. Setting a capacity never spills what is
## already in the bag: the load is carried over and clamped.
func begin_contract(capacity_kg: float) -> void:
	_bag_capacity_kg = maxf(capacity_kg, 0.0)
	_bag_kg = minf(_bag_kg, _bag_capacity_kg)
	bag_changed.emit(_bag_kg, _bag_capacity_kg)


## A fresh contract: nothing in the bag, nothing delivered yet.
func start_new_job(capacity_kg: float) -> void:
	_bag_kg = 0.0
	_delivered_this_job = 0.0
	_spilled_this_job = 0.0
	begin_contract(capacity_kg)


func bag_kilograms() -> float:
	return _bag_kg


func bag_capacity() -> float:
	return _bag_capacity_kg


func bag_fraction() -> float:
	if _bag_capacity_kg <= 0.0:
		return 0.0
	return clampf(_bag_kg / _bag_capacity_kg, 0.0, 1.0)


func bag_is_full() -> bool:
	return _bag_capacity_kg > 0.0 and _bag_kg >= _bag_capacity_kg - 0.001


func machine_collects() -> bool:
	return _bag_capacity_kg > 0.0


## THE ONE ENTRY POINT for grass entering the machine.
##
## `cells` is what `ACALawn` reported as newly cut - never an area, never a
## duration. Returns the kilograms that actually went in; anything over capacity
## is dropped on the lawn and counted as spilled.
## HOW HEAVY THE GRASS IS TODAY. Set by the mowing runtime when a contract
## starts, and again if the ground changes under the player. Clamped, because
## this is a condition and not a lever.
func set_yield_multiplier(value: float) -> void:
	_yield_multiplier = clampf(value, 0.5, 2.0)


func yield_multiplier() -> float:
	return _yield_multiplier


func collect_from_cells(cells: int) -> float:
	if cells <= 0:
		return 0.0
	var produced := float(cells) * KG_PER_CELL * _yield_multiplier
	if _bag_capacity_kg <= 0.0:
		# A mulching machine. The grass goes back down where it was cut, which
		# is what the customer asked for on a mulching contract.
		return 0.0
	var was_full := bag_is_full()
	var room := maxf(_bag_capacity_kg - _bag_kg, 0.0)
	var taken := minf(produced, room)
	_bag_kg += taken
	_spilled_this_job += produced - taken
	if taken > 0.0:
		bag_changed.emit(_bag_kg, _bag_capacity_kg)
	if not was_full and bag_is_full():
		bag_filled.emit()
	return taken


## ---------------------------------------------------------------------------
## THE MACHINE EMPTIES INTO THE TRAILER, AND THE TRAILER EMPTIES AT THE YARD
## ---------------------------------------------------------------------------
## This used to move clippings from the catcher straight into the yard's store,
## which was the right shape while a working day was exactly one contract long.
## A day can now be a ROUTE - several stops between one visit to a service lot
## and the next - so there has to be somewhere on the truck for the grass to be
## in the meantime, and how much that somewhere holds is what a bigger trailer
## buys.
##
## `ACAEquipment` owns the trailer's capacity. This owns the load on it.
##
## Returns what actually transferred, which is less than the bag held when the
## trailer is nearly full.
func unload_to_truck() -> float:
	if _bag_kg <= 0.0:
		unloaded.emit(0.0)
		return 0.0
	var room := maxf(trailer_capacity() - _trailer_kg, 0.0)
	var moved := minf(_bag_kg, room)
	_bag_kg -= moved
	_trailer_kg += moved
	_delivered_this_job += moved
	bag_changed.emit(_bag_kg, _bag_capacity_kg)
	inventory_changed.emit()
	unloaded.emit(moved)
	return moved


## Kilograms on the trailer right now.
func trailer_kilograms() -> float:
	return _trailer_kg


## What the trailer holds. Asked of `ACAEquipment`, which owns which trailer the
## business bought; a fallback keeps this class usable on its own in a test.
func trailer_capacity() -> float:
	var equipment := get_node_or_null(^"/root/Equipment")
	if equipment == null:
		return ACAHaulage.clipping_capacity(ACAHaulage.STARTING_TIER)
	return float(equipment.call(&"trailer_clipping_capacity"))


func trailer_fraction() -> float:
	var capacity := trailer_capacity()
	if capacity <= 0.0:
		return 0.0
	return clampf(_trailer_kg / capacity, 0.0, 1.0)


func trailer_is_full() -> bool:
	return _trailer_kg >= trailer_capacity() - 0.001


## BACK AT A SERVICE LOT. Everything on the trailer goes into the yard, up to
## what the yard will take. Called by the application layer when the player
## arrives at a hub, so a route ends where a route should end.
##
## Returns what was deposited.
func deposit_trailer_at_yard() -> float:
	if _trailer_kg <= 0.0:
		return 0.0
	var room := maxf(store_capacity() - stored_total(), 0.0)
	var moved := minf(_trailer_kg, room)
	if moved <= 0.0:
		return 0.0
	_trailer_kg -= moved
	_fresh_kg += moved
	inventory_changed.emit()
	return moved


## Clippings the machine can still take on before something has to be emptied:
## the room in the bag, plus the room on the trailer behind it. What the HUD
## warns against, and the number a route is actually planned around.
func remaining_capacity() -> float:
	return maxf(_bag_capacity_kg - _bag_kg, 0.0) \
		+ maxf(trailer_capacity() - _trailer_kg, 0.0)


## Kilograms this contract has delivered to the truck. What a collection term is
## scored against - the bag's current contents do not count, because clippings
## still on the machine have not been taken away.
func delivered_this_job() -> float:
	return _delivered_this_job


func spilled_this_job() -> float:
	return _spilled_this_job


## Used when a contract is settled off screen by an autonomous unit: there is no
## bag and no truck, only a delivery.
func deliver_direct(kilograms: float) -> float:
	if kilograms <= 0.0:
		return 0.0
	var room := maxf(store_capacity() - stored_total(), 0.0)
	var moved := minf(kilograms, room)
	_fresh_kg += moved
	inventory_changed.emit()
	return moved


# ================================================================= the store

func fresh_kilograms() -> float:
	return _fresh_kg


func compost_kilograms() -> float:
	return _compost_kg


func composting_kilograms() -> float:
	var total := 0.0
	for batch in _composting:
		total += float(batch["kilograms"])
	return total


## Everything at the yard, whatever state it is in. This is what the store
## capacity is measured against, so a player cannot dodge a full yard by
## composting everything.
func stored_total() -> float:
	return _fresh_kg + _compost_kg + composting_kilograms()


func store_capacity() -> float:
	return BASE_STORE_CAPACITY_KG * upgrade_value("yard_store")


func store_fraction() -> float:
	var capacity := store_capacity()
	return clampf(stored_total() / capacity, 0.0, 1.0) if capacity > 0.0 else 0.0


func store_is_full() -> bool:
	return stored_total() >= store_capacity() - 0.001


# ================================================================== the price

## What a kilogram of fresh clippings fetches right now. The market moves it the
## same way it moves fuel, so a resource has a price rather than a constant.
func fresh_price_per_kg() -> float:
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return FRESH_PRICE_PER_KG
	return FRESH_PRICE_PER_KG * float(economy.call(&"resource_index"))


func compost_price_per_kg() -> float:
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return COMPOST_PRICE_PER_KG
	return COMPOST_PRICE_PER_KG * float(economy.call(&"resource_index"))


func fresh_sale_value() -> int:
	return int(floor(_fresh_kg * fresh_price_per_kg()))


func compost_sale_value() -> int:
	return int(floor(_compost_kg * compost_price_per_kg()))


## Sell everything fresh at the yard. Returns what was paid; zero changes
## nothing, so a double click cannot pay twice for the same grass.
func sell_fresh() -> int:
	var paid := fresh_sale_value()
	if paid <= 0 or _fresh_kg <= 0.0:
		return 0
	_fresh_kg = 0.0
	var session := get_node_or_null(^"/root/GameSession")
	if session != null:
		session.call(&"add_money", paid)
	inventory_changed.emit()
	return paid


func sell_compost() -> int:
	var paid := compost_sale_value()
	if paid <= 0 or _compost_kg <= 0.0:
		return 0
	_compost_kg = 0.0
	var session := get_node_or_null(^"/root/GameSession")
	if session != null:
		session.call(&"add_money", paid)
	inventory_changed.emit()
	return paid


# ================================================================ composting

## Put the fresh pile on the heap. It comes back as compost in `COMPOST_DAYS`,
## lighter and worth more per kilogram.
##
## Batched, and each batch carries its own ready day, so starting a second heap
## does not make the first one finish early or late.
func start_composting(today: int) -> float:
	if _fresh_kg <= 0.0:
		return 0.0
	var amount := _fresh_kg
	_fresh_kg = 0.0
	_composting.append({
		"kilograms": amount,
		"ready_day": today + COMPOST_DAYS,
	})
	inventory_changed.emit()
	return amount


## Move every batch whose day has come into finished compost. Called as the
## world clock rolls a day; it is never a timer of its own.
func advance_to_day(today: int) -> float:
	var finished := 0.0
	var still_going: Array[Dictionary] = []
	for batch in _composting:
		if today >= int(batch["ready_day"]):
			finished += float(batch["kilograms"]) * COMPOST_YIELD
		else:
			still_going.append(batch)
	if finished <= 0.0:
		return 0.0
	_composting = still_going
	_compost_kg += finished
	inventory_changed.emit()
	return finished


## Days until the next batch is ready, or -1 when nothing is composting.
func days_until_compost(today: int) -> int:
	var soonest := -1
	for batch in _composting:
		var days: int = maxi(int(batch["ready_day"]) - today, 0)
		if soonest < 0 or days < soonest:
			soonest = days
	return soonest


# ================================================================= upgrades

func upgrade_level(upgrade_id: String) -> int:
	return clampi(int(_upgrade_levels.get(upgrade_id, 0)), 0, max_upgrade_level(upgrade_id))


static func max_upgrade_level(upgrade_id: String) -> int:
	var spec: Dictionary = UPGRADES.get(upgrade_id, {})
	if spec.is_empty():
		return 0
	return (spec["values"] as Array).size() - 1


func upgrade_value(upgrade_id: String) -> float:
	var spec: Dictionary = UPGRADES.get(upgrade_id, {})
	if spec.is_empty():
		return 1.0
	var values: Array = spec["values"]
	return float(values[clampi(upgrade_level(upgrade_id), 0, values.size() - 1)])


static func upgrade_value_at(upgrade_id: String, at_level: int) -> float:
	var spec: Dictionary = UPGRADES.get(upgrade_id, {})
	if spec.is_empty():
		return 1.0
	var values: Array = spec["values"]
	return float(values[clampi(at_level, 0, values.size() - 1)])


## Multiplier applied to every machine's catcher. `Equipment` reads this rather
## than owning a second copy of the number.
func bag_capacity_multiplier() -> float:
	return upgrade_value("catcher")


func upgrade_cost(upgrade_id: String) -> int:
	var spec: Dictionary = UPGRADES.get(upgrade_id, {})
	if spec.is_empty() or upgrade_level(upgrade_id) >= max_upgrade_level(upgrade_id):
		return -1
	var cost := float(spec["base_cost"])
	for _i in range(upgrade_level(upgrade_id)):
		cost *= float(spec["cost_growth"])
	var raw := int(round(cost * ACADifficulty.value("upgrade_cost_scale", 1.0)))
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return maxi(int(round(float(raw) / 5.0)) * 5, 0)
	return int(economy.call(&"equipment_price", raw))


func try_purchase_upgrade(upgrade_id: String) -> bool:
	var cost := upgrade_cost(upgrade_id)
	if cost < 0:
		return false
	var session := get_node_or_null(^"/root/GameSession")
	if session == null or not session.call(&"try_spend", cost):
		return false
	_upgrade_levels[upgrade_id] = upgrade_level(upgrade_id) + 1
	inventory_changed.emit()
	bag_changed.emit(_bag_kg, _bag_capacity_kg)
	return true


## Everything a shop panel needs.
func upgrade_summary() -> Array:
	var out: Array = []
	for key: String in UPGRADES:
		var spec: Dictionary = UPGRADES[key]
		var lvl := upgrade_level(key)
		out.append({
			"id": key,
			"name": String(spec["name"]),
			"blurb": String(spec["blurb"]),
			"unit": String(spec["unit"]),
			"level": lvl,
			"max_level": max_upgrade_level(key),
			"value": upgrade_value(key),
			"next_value": upgrade_value_at(key, lvl + 1),
			"cost": upgrade_cost(key),
			"maxed": lvl >= max_upgrade_level(key),
		})
	return out


# ================================================================== display

## Kilograms, written the way a person would say them.
static func format_kg(kilograms: float) -> String:
	if kilograms >= 100.0:
		return "%d kg" % int(round(kilograms))
	if kilograms >= 10.0:
		return "%.0f kg" % kilograms
	return "%.1f kg" % kilograms


# =============================================================== persistence

## THE STORE CANNOT BE RECONSTRUCTED and neither can a part-composted heap, so
## both are written. The PRICE is not: it comes from the market, which has its
## own save block.
func to_save_dict() -> Dictionary:
	var batches: Array = []
	for batch in _composting:
		batches.append({
			"kilograms": float(batch["kilograms"]),
			"ready_day": int(batch["ready_day"]),
		})
	var levels := {}
	for key: String in _upgrade_levels:
		levels[key] = int(_upgrade_levels[key])
	return {
		"bag_kg": _bag_kg,
		"bag_capacity_kg": _bag_capacity_kg,
		"delivered_this_job": _delivered_this_job,
		"spilled_this_job": _spilled_this_job,
		"fresh_kg": _fresh_kg,
		"compost_kg": _compost_kg,
		"composting": batches,
		"upgrades": levels,
		# WHAT IS ON THE TRAILER, additive. A save without it was written when
		# the machine emptied straight into the yard, which is a trailer with
		# nothing on it - so its default is exactly true.
		"trailer_kg": _trailer_kg,
	}


## A save with no clipping block was played before clippings existed, and the
## honest reading of that is an empty yard and an empty bag. There is nothing to
## migrate, because there was nothing to lose.
func from_save_dict(data: Dictionary) -> void:
	_bag_kg = maxf(float(data.get("bag_kg", 0.0)), 0.0)
	_bag_capacity_kg = maxf(float(data.get("bag_capacity_kg", 0.0)), 0.0)
	_delivered_this_job = maxf(float(data.get("delivered_this_job", 0.0)), 0.0)
	_spilled_this_job = maxf(float(data.get("spilled_this_job", 0.0)), 0.0)
	_trailer_kg = maxf(float(data.get("trailer_kg", 0.0)), 0.0)
	_yield_multiplier = 1.0
	_fresh_kg = maxf(float(data.get("fresh_kg", 0.0)), 0.0)
	_compost_kg = maxf(float(data.get("compost_kg", 0.0)), 0.0)
	_composting.clear()
	var raw: Array = data.get("composting", [])
	for entry: Variant in raw:
		if entry is Dictionary:
			_composting.append({
				"kilograms": maxf(float((entry as Dictionary).get("kilograms", 0.0)), 0.0),
				"ready_day": int((entry as Dictionary).get("ready_day", 0)),
			})
	_upgrade_levels = {}
	var levels: Dictionary = data.get("upgrades", {})
	for key: Variant in levels:
		var id := String(key)
		if UPGRADES.has(id):
			_upgrade_levels[id] = clampi(int(levels[key]), 0, max_upgrade_level(id))
	inventory_changed.emit()
	bag_changed.emit(_bag_kg, _bag_capacity_kg)


# ==================================================================== dev only

func dev_fill_bag() -> void:
	_bag_kg = _bag_capacity_kg
	bag_changed.emit(_bag_kg, _bag_capacity_kg)
	bag_filled.emit()


func dev_add_fresh(kilograms: float) -> void:
	_fresh_kg = minf(_fresh_kg + kilograms, store_capacity())
	inventory_changed.emit()
