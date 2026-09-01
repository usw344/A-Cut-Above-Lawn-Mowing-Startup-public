class_name ACAMowingMode
extends RefCounted
## HOW THE MACHINE DEALS WITH WHAT IT CUTS. Pure, static, no nodes, no state.
##
## The game has had one answer since clippings arrived: everything with a
## catcher collects, everything without mulches, and the player never chose. A
## grounds machine has three configurations and they are a genuine operating
## decision:
##
##   BAGGING          the clippings are collected and become stock. Clean
##                    finish, and trips back to the truck.
##   MULCHING         the clippings are cut fine and left down. No stock, no
##                    trips, and the lawn is a little better for it.
##   SIDE DISCHARGE   the clippings are thrown out of the side. Nothing to
##                    empty, nothing collected, and a finish some customers
##                    will not accept.
##
## ---------------------------------------------------------------------------
## THE MODE IS AN EQUIPMENT DECISION, NOT A BUTTON ON THE LAWN
## ---------------------------------------------------------------------------
## Which modes a machine can work in is decided by what is BOLTED TO IT, and a
## deck plate is not something a contractor swaps in the middle of a customer's
## garden. So the mode is chosen at the service lot with the rest of the
## loadout, it travels to the contract, and the HUD reports it.
##
## ---------------------------------------------------------------------------
## BAGGING IS THE DEFAULT, AND THAT IS DELIBERATE
## ---------------------------------------------------------------------------
## Every machine in the game has always had a catcher on it and the whole
## economy - contract terms, clipping prices, the difficulty study - was tuned
## against that. A business starts with the bagger it has always had, a save
## written before attachments existed loads with one, and a player who never
## opens the loadout screen plays exactly the game they were playing before.
##
## PUBLIC API
##   enum Mode { BAG, MULCH, SIDE_DISCHARGE }
##   static mode_name(mode) / blurb(mode) / short_name(mode) -> String
##   static collects(mode) -> bool
##   static yield_multiplier(mode) -> float       clippings produced
##   static finish_quality(mode, job) -> float    -1..+1, feeds the review
##   static satisfies_terms(mode, job) -> bool
##   static lawn_health_bonus(mode) -> float      what mulching is worth
##   static requires_attachment(mode) -> StringName
##
## INVARIANTS
##   * `collects()` is the ONE place that decides whether a mode produces
##     clippings. `ACAClippings` is given a bag capacity of zero for the two
##     modes that do not, so there is no second rule anywhere.
##   * Nothing here is stored. `ACAEquipment` owns which mode is selected.

enum Mode { BAG, MULCH, SIDE_DISCHARGE }

const MODE_ORDER: Array[int] = [Mode.BAG, Mode.MULCH, Mode.SIDE_DISCHARGE]

const NAMES := {
	Mode.BAG: "Bagging",
	Mode.MULCH: "Mulching",
	Mode.SIDE_DISCHARGE: "Side Discharge",
}

const SHORT_NAMES := {
	Mode.BAG: "BAG",
	Mode.MULCH: "MULCH",
	Mode.SIDE_DISCHARGE: "DISCHARGE",
}

const BLURBS := {
	Mode.BAG: "Collects everything it cuts. Cleanest finish, and a trip back to "
		+ "the truck whenever the catcher fills.",
	Mode.MULCH: "Cuts the clippings fine and leaves them down. Nothing to empty, "
		+ "and the lawn is the better for it.",
	Mode.SIDE_DISCHARGE: "Throws the clippings out of the side. Quick and simple "
		+ "on open ground; not what a forecourt wants.",
}

## THE ATTACHMENT EACH MODE NEEDS BOLTED ON.
##
## All three of them need one, including side discharge - a deck without a
## shroud on it throws clippings at the operator, and a machine with nothing on
## its deck is not one of the three configurations, it is a machine that has
## been stripped. `ACAEquipment.available_modes()` falls back to bagging in that
## case rather than offering a fourth, unnamed way of working.
const REQUIRED_ATTACHMENT := {
	Mode.BAG: &"bagger",
	Mode.MULCH: &"mulch_kit",
	Mode.SIDE_DISCHARGE: &"discharge_chute",
}

## HOW MUCH GRASS EACH MODE PRODUCES, as a multiplier on what the deck cut.
##
## Only bagging produces any at all, so the other two are zero and are here to
## say so rather than to be multiplied by. Bagging is 1.0 because that is the
## rate the whole clipping economy was tuned at.
const YIELD_MULTIPLIER := {
	Mode.BAG: 1.0,
	Mode.MULCH: 0.0,
	Mode.SIDE_DISCHARGE: 0.0,
}

## WHAT MULCHING IS WORTH TO A RECURRING CUSTOMER, in loyalty.
##
## MODEST, on purpose. Mulching a lawn is good practice and it is not fertiliser
## with a multiplier on it; two points of loyalty a visit is a reason to choose
## it on a garden the business keeps coming back to and is never a reason to
## choose it on everything.
const MULCH_LOYALTY_BONUS := 2.0

## What side discharge costs on a contract that PERMITS it: nothing. The penalty
## below applies only where the customer asked for collection.
const DISCHARGE_FINISH_PENALTY := 0.35
## ...and what a clean bagged finish is worth where they did not ask.
const BAG_FINISH_BONUS := 0.12


static func mode_name(mode: int) -> String:
	return String(NAMES.get(mode, "Bagging"))


static func short_name(mode: int) -> String:
	return String(SHORT_NAMES.get(mode, "BAG"))


static func blurb(mode: int) -> String:
	return String(BLURBS.get(mode, ""))


static func is_valid(mode: int) -> bool:
	return NAMES.has(mode)


## THE ONE RULE about whether a mode produces clippings.
static func collects(mode: int) -> bool:
	return mode == Mode.BAG


static func yield_multiplier(mode: int) -> float:
	return float(YIELD_MULTIPLIER.get(mode, 0.0))


static func requires_attachment(mode: int) -> StringName:
	return StringName(REQUIRED_ATTACHMENT.get(mode, &""))


## Does this configuration satisfy what the contract asked for?
##
## Only COLLECTION can be failed by a mode, and only because collection is the
## only clipping term the game measures. A mulching contract is a PREFERENCE and
## is never refused; a discharge finish on a job that wanted collecting is
## refused by the collection term itself, which already exists.
static func satisfies_terms(mode: int, job: ACAJob) -> bool:
	if not ACAContractTerms.requires_collection(job):
		return true
	return collects(mode)


## -1 to +1, folded into the review by `ACABusiness`. Small numbers: the mode is
## an operating decision, not a score.
static func finish_quality(mode: int, job: ACAJob) -> float:
	if job == null:
		return 0.0
	if mode == Mode.SIDE_DISCHARGE:
		# ONLY WHERE IT WAS NOT WANTED. A rural paddock has nowhere for the
		# clippings to go anyway, and penalising a perfectly ordinary choice on
		# a contract that permits it would make the mode a trap.
		if ACAContractTerms.requires_collection(job):
			return -DISCHARGE_FINISH_PENALTY
		return 0.0
	if mode == Mode.MULCH:
		return 0.0 if not ACAContractTerms.requires_collection(job) else -DISCHARGE_FINISH_PENALTY
	if mode == Mode.BAG and not ACAContractTerms.requires_collection(job):
		return BAG_FINISH_BONUS
	return 0.0


## What mulching does for a property the business keeps coming back to.
static func lawn_health_bonus(mode: int) -> float:
	return MULCH_LOYALTY_BONUS if mode == Mode.MULCH else 0.0


## One line for the work order, saying what this configuration will do here.
static func advice_for(mode: int, job: ACAJob) -> String:
	if job == null:
		return ""
	if ACAContractTerms.requires_collection(job) and not collects(mode):
		return "This contract wants the clippings taken away, and the machine is set to %s." % mode_name(mode).to_lower()
	if ACAContractTerms.prefers_mulching(job) and mode == Mode.MULCH:
		return "They are happy for the clippings to be left down."
	if mode == Mode.SIDE_DISCHARGE:
		return "Open ground, and nothing to empty."
	return ""
