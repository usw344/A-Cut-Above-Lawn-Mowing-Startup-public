class_name ACAAttachments
extends RefCounted
## WHAT BOLTS ON TO A MACHINE. Pure, static, no nodes, no state.
##
## The catalogue, what fits what, and what each one does. `ACAEquipment` owns
## which of them the business has BOUGHT and which are FITTED; this owns the
## table, so there is one description of a bagger in the game.
##
## ---------------------------------------------------------------------------
## AN ATTACHMENT IS NOT AN UPGRADE
## ---------------------------------------------------------------------------
## `ACAMowerUpgrades` improves a machine permanently and invisibly. An
## attachment is a physical thing that is either on the machine for this
## contract or in the shed, it takes room on the trailer, and where it is
## practical it can be SEEN on the machine. That is the difference, and it is
## why they are two systems rather than one with a flag.
##
## ---------------------------------------------------------------------------
## THE BAGGER IS OWNED FROM THE FIRST MORNING
## ---------------------------------------------------------------------------
## Every machine in this game has always had a catcher on it, and the contract
## terms, the clipping prices and all three difficulty profiles were tuned
## against that. So a new business owns the bagger, and a save written before
## attachments existed loads owning it. Nothing about a player who never opens
## the loadout screen changes.
##
## PUBLIC API
##   CATALOG / ORDER / spec(id) / is_valid(id) / display_name(id)
##   static fits(id, mower_id) -> bool
##   static for_mower(mower_id) -> Array[StringName]
##   static grants_mode(id) -> int                    -1 for none
##   static bag_multiplier(fitted) -> float
##   static pattern_bonus(fitted) -> float
##   static slots_used(fitted) -> int
##   static describe(id) -> String / effect_line(id) -> String
##   static base_cost(id) -> int
##
## INVARIANTS
##   * Every entry declares which of the three canonical machines it fits, by
##     id. Nothing infers compatibility from a name or a price.
##   * Nothing here reads a node, a clock or a save. It is a table and the
##     questions that can be answered from it.

## THE STARTING KIT. Owned by a new business and granted to any save written
## before attachments existed - see the note at the top.
const STARTING_ATTACHMENTS: Array[StringName] = [&"bagger"]

## THE FIVE.
##
## A deliberately small first catalogue: each one either changes what the
## machine DOES with the grass, how much of it the machine can carry, or how the
## finish reads. An aerator, a dethatcher and a spreader are all reasonable
## additions and all of them need a second kind of pass over a lawn, which is a
## gameplay verb rather than an item - see the pass notes.
##
##   `fits`        machine ids this bolts on to.
##   `mode`        the mowing mode it makes available, or an empty name.
##   `bag_scale`   multiplier on the machine's catcher capacity.
##   `pattern`     what it adds to a requested finish pattern's score, 0-1.
##   `slots`       room it takes on the trailer.
##   `visual`      which piece of geometry `ACAMowerAttachment` hangs on the
##                 machine for it. Empty means it is not visible.
const CATALOG := {
	&"bagger": {
		"name": "Catcher and Bagger",
		"blurb": "The collection box and the chute that feeds it. Everything the "
			+ "deck cuts ends up in it.",
		"cost": 0,
		"fits": ["rider", "powered", "push"],
		"mode": ACAMowingMode.Mode.BAG,
		"bag_scale": 1.0,
		"pattern": 0.0,
		"slots": 1,
		# NO GEOMETRY, DELIBERATELY. Every canonical machine's model already
		# carries a catcher - the rider has a rear housing and the walk-behind
		# has a bag with AWD printed on it - so the machine ALREADY shows this
		# attachment. Building a second one bolted behind the first is the one
		# thing a visible attachment system must not do.
		"visual": &"",
	},
	&"mulch_kit": {
		"name": "Mulching Kit",
		"blurb": "A closed deck plate and a recirculating blade. Cuts the "
			+ "clippings fine and leaves them down where they fell.",
		"cost": 320,
		"fits": ["rider", "powered", "push"],
		"mode": ACAMowingMode.Mode.MULCH,
		"bag_scale": 0.0,
		"pattern": 0.0,
		"slots": 1,
		"visual": &"",
	},
	&"discharge_chute": {
		"name": "Side Discharge Chute",
		"blurb": "Throws the clippings clear of the deck. Nothing to empty, and "
			+ "the fastest way across open ground.",
		"cost": 180,
		"fits": ["rider", "powered"],
		"mode": ACAMowingMode.Mode.SIDE_DISCHARGE,
		"bag_scale": 0.0,
		"pattern": 0.0,
		"slots": 1,
		"visual": &"chute",
	},
	&"striping_roller": {
		"name": "Striping Roller",
		"blurb": "A weighted roller behind the deck. Lays the grass over "
			+ "properly, so a requested pattern actually shows.",
		"cost": 640,
		"fits": ["rider", "powered", "push"],
		"mode": -1,
		"bag_scale": 1.0,
		"pattern": 0.18,
		"slots": 1,
		"visual": &"roller",
	},
	&"tow_sweeper": {
		"name": "Tow-Behind Sweeper",
		"blurb": "A wide sweeper on a drawbar. Nearly doubles what the machine "
			+ "can carry before it has to go back to the truck.",
		"cost": 1450,
		"fits": ["rider"],
		"mode": -1,
		"bag_scale": 1.9,
		"pattern": 0.0,
		"slots": 2,
		"visual": &"sweeper",
	},
}

## Catalogue order, so the shop never has to sort a Dictionary.
const ORDER: Array[StringName] = [
	&"bagger", &"mulch_kit", &"discharge_chute", &"striping_roller", &"tow_sweeper",
]


static func is_valid(id: StringName) -> bool:
	return CATALOG.has(id)


static func spec(id: StringName) -> Dictionary:
	return CATALOG.get(id, {})


static func display_name(id: StringName) -> String:
	return String(spec(id).get("name", String(id).capitalize()))


static func describe(id: StringName) -> String:
	return String(spec(id).get("blurb", ""))


static func base_cost(id: StringName) -> int:
	return int(spec(id).get("cost", 0))


## Which of the three canonical machines this bolts on to.
static func fits(id: StringName, mower_id: String) -> bool:
	var entry := spec(id)
	if entry.is_empty():
		return false
	return (entry["fits"] as Array).has(mower_id)


## Everything in the catalogue that fits this machine, in catalogue order.
static func for_mower(mower_id: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ORDER:
		if fits(id, mower_id):
			out.append(id)
	return out


## The mowing mode this attachment makes available, or -1 for one that does not
## change the configuration.
static func grants_mode(id: StringName) -> int:
	return int(spec(id).get("mode", -1))


## Which attachment, if any, is what lets a machine work in this mode.
static func for_mode(mode: int) -> StringName:
	return ACAMowingMode.requires_attachment(mode)


# ============================================== what a fitted set adds up to

## What the fitted set does to the machine's catcher capacity.
##
## MULTIPLIED, and the largest carrier wins rather than the sum: a tow-behind
## sweeper and a catcher are the same job done at two sizes, and adding them
## together would let a player stack every carrier in the shed.
static func bag_multiplier(fitted: Array) -> float:
	var best := 0.0
	for id: Variant in fitted:
		var entry := spec(StringName(String(id)))
		if entry.is_empty():
			continue
		best = maxf(best, float(entry["bag_scale"]))
	return best


## What the fitted set adds to a requested pattern's score. Summed, because two
## different things that both help a stripe show really do both help.
static func pattern_bonus(fitted: Array) -> float:
	var total := 0.0
	for id: Variant in fitted:
		total += float(spec(StringName(String(id))).get("pattern", 0.0))
	return clampf(total, 0.0, 0.5)


## Room the fitted set takes on the trailer.
static func slots_used(fitted: Array) -> int:
	var total := 0
	for id: Variant in fitted:
		total += int(spec(StringName(String(id))).get("slots", 1))
	return total


## The modes a fitted set makes available, always including side discharge only
## when something grants it. Every machine can be run with nothing on the deck,
## and that is not one of the three configurations - it is a machine with no
## configuration, which the game does not offer.
static func modes_available(fitted: Array) -> Array[int]:
	var out: Array[int] = []
	for mode in ACAMowingMode.MODE_ORDER:
		var wanted := ACAMowingMode.requires_attachment(mode)
		if String(wanted).is_empty():
			continue
		for id: Variant in fitted:
			if StringName(String(id)) == wanted:
				out.append(mode)
				break
	return out


## One line of plain effect text for the shop, derived from the table rather
## than written twice.
static func effect_line(id: StringName) -> String:
	var entry := spec(id)
	if entry.is_empty():
		return ""
	var parts := PackedStringArray()
	var mode := int(entry.get("mode", -1))
	if mode >= 0:
		parts.append("Allows %s" % ACAMowingMode.mode_name(mode).to_lower())
	var scale := float(entry.get("bag_scale", 0.0))
	if scale > 1.0:
		parts.append("carries %d%% more" % int(round((scale - 1.0) * 100.0)))
	var pattern := float(entry.get("pattern", 0.0))
	if pattern > 0.0:
		parts.append("+%d to a requested pattern" % int(round(pattern * 100.0)))
	var slots := int(entry.get("slots", 1))
	parts.append("%d trailer slot%s" % [slots, "" if slots == 1 else "s"])
	return " · ".join(parts)


## Which piece of geometry hangs on the machine for this, if any.
static func visual_id(id: StringName) -> StringName:
	return StringName(spec(id).get("visual", &""))
