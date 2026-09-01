class_name ACAHaulage
extends RefCounted
## THE WORK TRAILER, as a table. Pure, static, no nodes, no state.
##
## What the business can physically take out for a day's work: how many machines
## fit on the trailer, how many attachments go with them, how much cut grass it
## can bring home before it has to be emptied, and how much spare fuel is on
## board.
##
## `ACAEquipment` owns which trailer the business has bought and what is loaded
## on it. This owns the tiers.
##
## ---------------------------------------------------------------------------
## CAPACITY IS COUNTED IN SLOTS, NOT ARRANGED IN A GRID
## ---------------------------------------------------------------------------
## A machine takes slots, an attachment takes slots, and the trailer has a
## number of them. There is no inventory grid, no packing puzzle and no
## drag-and-drop, because none of those would be a decision - they would be a
## chore standing where a decision should be. What the player actually chooses
## is which machine, which configuration and whether the autonomous unit comes
## too, and slots are exactly enough structure to make those choices exclude
## each other.
##
## PUBLIC API
##   TIERS / ORDER / STARTING_TIER
##   static spec(tier) / is_valid(tier) / display_name(tier)
##   static slots(tier) / attachment_slots(tier)
##   static clipping_capacity(tier) / fuel_reserve(tier)
##   static machine_slots_for(mower_id) / autonomous_slots_for(unit_tier)
##   static base_cost(tier) / summary_lines(tier)
##
## INVARIANTS
##   * The starting trailer carries exactly what the game already allowed: the
##     driven machine and one autonomous escort. Nothing a player could do
##     before this system existed became impossible when it arrived.

## What a new business already has behind the truck.
const STARTING_TIER := &"single"

## THE THREE.
##
##   `slots`        machines. The driven one always takes one.
##   `attachments`  room for what bolts on.
##   `clippings`    kilograms the trailer holds before it has to be emptied at a
##                  service lot. Sized so an ordinary contract never fills it
##                  and a neglected acreage property can.
##   `fuel`         spare fuel carried, in tank units. Poured in at the truck.
const TIERS := {
	&"single": {
		"name": "Single Trailer",
		"blurb": "What the business started with. One machine, one attachment, "
			+ "and room for a day's clippings.",
		"cost": 0,
		"slots": 2,
		"attachments": 1,
		"clippings": 620.0,
		"fuel": 0.0,
	},
	&"twin": {
		"name": "Twin-Axle Trailer",
		"blurb": "A longer bed and a second axle. Takes a machine, a support "
			+ "unit and the kit for both, with a jerry can on the drawbar.",
		"cost": 2100,
		"slots": 3,
		"attachments": 2,
		"clippings": 1150.0,
		"fuel": 35.0,
	},
	&"transporter": {
		"name": "Grounds Transporter",
		"blurb": "A proper plant trailer. Everything the business owns goes out "
			+ "at once, and the tank on it will see the day through.",
		"cost": 7400,
		"slots": 5,
		"attachments": 4,
		"clippings": 2400.0,
		"fuel": 90.0,
	},
}

const ORDER: Array[StringName] = [&"single", &"twin", &"transporter"]

## How much room each canonical machine takes. A rider is a rider; the two
## walk-behinds go on the same deck space as one another.
const MACHINE_SLOTS := {
	"rider": 1,
	"powered": 1,
	"push": 1,
}

## ...and each autonomous tier. The commercial unit is a wide-deck machine and
## takes the room to prove it, which is what makes the bigger trailer worth
## buying rather than merely larger.
const AUTONOMOUS_SLOTS := {
	"auto_compact": 1,
	"auto_grounds": 1,
	"auto_commercial": 2,
}


static func is_valid(tier: StringName) -> bool:
	return TIERS.has(tier)


static func spec(tier: StringName) -> Dictionary:
	return TIERS.get(tier, TIERS[STARTING_TIER])


static func display_name(tier: StringName) -> String:
	return String(spec(tier)["name"])


static func describe(tier: StringName) -> String:
	return String(spec(tier)["blurb"])


static func base_cost(tier: StringName) -> int:
	return int(spec(tier)["cost"])


static func slots(tier: StringName) -> int:
	return int(spec(tier)["slots"])


static func attachment_slots(tier: StringName) -> int:
	return int(spec(tier)["attachments"])


static func clipping_capacity(tier: StringName) -> float:
	return float(spec(tier)["clippings"])


static func fuel_reserve(tier: StringName) -> float:
	return float(spec(tier)["fuel"])


static func machine_slots_for(mower_id: String) -> int:
	return int(MACHINE_SLOTS.get(mower_id, 1))


static func autonomous_slots_for(unit_tier: String) -> int:
	return int(AUTONOMOUS_SLOTS.get(unit_tier, 1))


## The next trailer up, or an empty name at the top of the range.
static func next_tier(tier: StringName) -> StringName:
	var index := ORDER.find(tier)
	if index < 0 or index + 1 >= ORDER.size():
		return &""
	return ORDER[index + 1]


## Rows for the depot panel, derived from the table rather than written twice.
static func summary_lines(tier: StringName) -> Array:
	return [
		{"key": "Machines", "value": "%d slots" % slots(tier)},
		{"key": "Attachments", "value": "%d slots" % attachment_slots(tier)},
		{"key": "Clipping capacity", "value": ACAClippings.format_kg(
			clipping_capacity(tier))},
		{"key": "Spare fuel", "value": "none" if fuel_reserve(tier) <= 0.0
			else "%d units" % int(round(fuel_reserve(tier)))},
	]
