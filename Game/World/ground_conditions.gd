class_name ACAGroundConditions
extends RefCounted
## HOW WET THE GRASS IS, AND WHAT THAT DOES. Pure, static, no nodes, no state.
##
## The game has had weather since long before it had consequences: the sky
## changed, the rain fell, and the mowing was identical. This is the small,
## honest bridge between the two.
##
##     DRY    light clippings, more dust, easy mulching
##     DAMP   the ordinary morning. A little heavier, a little slower.
##     WET    heavy clippings, the catcher fills faster, and the machine is
##            happiest taken steadily
##
## THREE STATES, and no fourth decimal place. The player has to be able to read
## the condition off one word and know what it means for the next ten minutes;
## a percentage would be a number they could not act on.
##
## ---------------------------------------------------------------------------
## IT IS DERIVED FROM THE CLOCK, NOT SIMULATED
## ---------------------------------------------------------------------------
## Nothing here accumulates, ticks or stores. The state is a pure function of
## what `ACAWorldClock` already knows - what the sky is doing, how long since it
## last did it, and what time of morning it is - plus the property's own
## `dryness`, which the generator already drew. There is no second weather
## system and there is no moisture value being integrated behind the player's
## back.
##
## ---------------------------------------------------------------------------
## WET GRASS IS NOT A PUNISHMENT
## ---------------------------------------------------------------------------
## Every multiplier below is deliberately gentle. Mowing in the wet should
## change how the player plans the day - bag on the dry job, mulch on the damp
## one, get the park done before the rain - and it must never make the mowing
## itself unpleasant. The largest single effect in the file is a quarter more
## clippings.
##
## PUBLIC API
##   enum State { DRY, DAMP, WET }
##   static current(property_dryness := 0.24) -> int      reads WorldClock
##   static state_for(weather, minutes_since_rain, hour, dryness) -> int
##   static state_name(state) / blurb(state) / short_name(state) -> String
##   static clipping_multiplier(state) -> float
##   static speed_advice(state) -> float                  0-1, a HINT, not a cap
##   static traction_multiplier(state) -> float
##   static dust_multiplier(state) -> float
##   static mulch_penalty(state) -> float
##   static autonomous_time_multiplier(state) -> float
##   static summary_line(state) -> String
##
## INVARIANTS
##   * Pure and static. It reads `WorldClock` in `current()` and nowhere else,
##     and even that only asks questions.
##   * Nothing here is stored in a save. The state is the clock plus the seed.

enum State { DRY, DAMP, WET }

const STATE_NAMES := {
	State.DRY: "Dry",
	State.DAMP: "Damp",
	State.WET: "Wet",
}

const STATE_BLURBS := {
	State.DRY: "Light, dusty and quick. The clippings are barely worth carrying.",
	State.DAMP: "Ordinary working ground. A little heavier than dry.",
	State.WET: "Heavy going. The catcher will fill well before you expect it to.",
}

## HOW LONG THE GROUND STAYS WET after the rain stops, in game minutes. Six
## hours, which at the shipped time scale is about a real minute and a half -
## long enough that finishing a contract in the wet is a thing that happens, and
## short enough that a player who waits is rewarded rather than parked.
const WET_MINUTES := 360.0
## ...and how long it stays DAMP after that.
const DAMP_MINUTES := 900.0

## Before this hour the dew has not lifted, whatever the sky has been doing.
const DEW_UNTIL_HOUR := 8.5

## A property whose own `dryness` is above this shrugs the damp off faster: a
## late-summer lawn on free-draining ground is not wet three hours after a
## shower, and `dryness` is the number the generator already drew for exactly
## that character.
const DRYNESS_PIVOT := 0.30

# ------------------------------------------------------------- what it does

## WET GRASS PRODUCES MORE. The one large effect in the file, and the one the
## player feels: a bagged contract in the wet is more trips back to the truck.
const CLIPPING_MULTIPLIER := {
	State.DRY: 0.82,
	State.DAMP: 1.0,
	State.WET: 1.26,
}

## An ADVISORY ideal speed, 0-1 of the machine's own. Nothing enforces it and
## nothing slows the mower down: the HUD says the ground is heavy, and a player
## who charges across a wet park gets a rougher finish for it through the review
## rather than through a hand on the throttle.
const SPEED_ADVICE := {
	State.DRY: 1.0,
	State.DAMP: 0.95,
	State.WET: 0.86,
}

## Grip, applied to the mower's own acceleration and steering response on slope.
## SMALL. This is a lawn-care game and a machine the player cannot steer is a
## bug however it is justified.
const TRACTION_MULTIPLIER := {
	State.DRY: 1.0,
	State.DAMP: 0.97,
	State.WET: 0.90,
}

## The dust the deck throws. Zero in the wet, which is the cheapest and most
## legible signal in the whole system.
const DUST_MULTIPLIER := {
	State.DRY: 1.35,
	State.DAMP: 0.7,
	State.WET: 0.0,
}

## What mulching gives up in the wet: wet clippings clump rather than break
## down, so the customer gets less of the benefit. Subtracted from
## `ACAMowingMode.MULCH_LOYALTY_BONUS`.
const MULCH_PENALTY := {
	State.DRY: 0.0,
	State.DAMP: 0.5,
	State.WET: 1.5,
}

## An autonomous unit takes longer in the wet, because it is a machine on the
## same grass. It never FAILS: a unit that stopped working because of weather
## would be an owned asset the player cannot rely on, which is the opposite of
## what buying one is for.
const AUTONOMOUS_TIME_MULTIPLIER := {
	State.DRY: 0.96,
	State.DAMP: 1.0,
	State.WET: 1.22,
}


static func state_name(state: int) -> String:
	return String(STATE_NAMES.get(state, "Damp"))


static func short_name(state: int) -> String:
	return state_name(state).to_upper()


static func blurb(state: int) -> String:
	return String(STATE_BLURBS.get(state, ""))


static func is_wet(state: int) -> bool:
	return state == State.WET


# ==================================================================== reading

## THE state, right now, on a property of this dryness. The only function here
## that touches the tree, and it only asks questions.
static func current(property_dryness: float = 0.24) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return State.DAMP
	var clock := tree.root.get_node_or_null(^"/root/WorldClock")
	if clock == null:
		return State.DAMP
	return state_for(String(clock.call(&"weather_preset")),
		float(clock.call(&"minutes_since_rain")),
		float(clock.call(&"hour_of_day")), property_dryness)


## THE derivation. Four inputs, three outcomes, and no state anywhere.
static func state_for(weather: String, minutes_since_rain: float,
		hour: float, dryness: float) -> int:
	# IT IS RAINING. Nothing else matters, and light rain counts: a lawn under
	# drizzle is a wet lawn, whatever it looks like from the seat.
	if ACAWorldClock.is_rain(weather):
		return State.WET

	# How much faster this ground sheds water than the average property.
	var shed: float = clampf(1.0 + (dryness - DRYNESS_PIVOT) * 1.4, 0.55, 1.6)
	var wet_for := WET_MINUTES / shed
	var damp_for := DAMP_MINUTES / shed

	if minutes_since_rain < wet_for:
		return State.WET
	if minutes_since_rain < damp_for:
		return State.DAMP

	# EARLY MORNING DEW, and fog that has been sitting on it. Neither makes the
	# ground wet; both stop it being dry.
	if hour < DEW_UNTIL_HOUR or ACAWorldClock.is_damp_air(weather):
		return State.DAMP

	# A properly dry lawn wants a properly dry property. Ground the generator
	# drew as lush stays merely ordinary however long the sun has been on it.
	return State.DRY if dryness >= 0.18 else State.DAMP


# ================================================================ what it does

static func clipping_multiplier(state: int) -> float:
	return float(CLIPPING_MULTIPLIER.get(state, 1.0))


static func speed_advice(state: int) -> float:
	return float(SPEED_ADVICE.get(state, 1.0))


static func traction_multiplier(state: int) -> float:
	return float(TRACTION_MULTIPLIER.get(state, 1.0))


static func dust_multiplier(state: int) -> float:
	return float(DUST_MULTIPLIER.get(state, 1.0))


static func mulch_penalty(state: int) -> float:
	return float(MULCH_PENALTY.get(state, 0.0))


static func autonomous_time_multiplier(state: int) -> float:
	return float(AUTONOMOUS_TIME_MULTIPLIER.get(state, 1.0))


# ==================================================================== display

## One line for the HUD chip and the work order. It says what the state means
## for THIS contract rather than restating the state's own name.
static func summary_line(state: int) -> String:
	match state:
		State.WET:
			return "Wet grass - the catcher fills about a quarter faster."
		State.DRY:
			return "Dry - light clippings, and the deck will raise dust."
		_:
			return "Damp - ordinary going."


## What the forecast means for a day's planning, in one sentence. Used by the
## depot's forecast strip; `minutes` is what `WorldClock.minutes_until_rain()`
## returned.
static func forecast_advice(minutes_until_rain: float) -> String:
	if is_inf(minutes_until_rain):
		return "No rain in the next two days."
	if minutes_until_rain <= 0.0:
		return "Raining now. Everything out there is heavy going."
	var hours := minutes_until_rain / ACAJobBalance.MINUTES_PER_HOUR
	if hours < 2.0:
		return "Rain within the hour or two. Get the big ground done first."
	if hours < 6.0:
		return "Rain later today. There is time for one large contract before it."
	return "Dry for the rest of the working day."
