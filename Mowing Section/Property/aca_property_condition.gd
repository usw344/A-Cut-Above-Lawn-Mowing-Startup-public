class_name ACAPropertyCondition
extends RefCounted
## WHAT CONDITION A PROPERTY IS IN, and what the business's work has done to it.
## Pure, static, no nodes, no state.
##
## Most contracts are a lawn that needs cutting. A minority are a PROJECT: a
## property that has been left, where the first visit is a rescue and the value
## of it is what the place looks like on the third.
##
##     STAGE 0  NEGLECTED    tall, untidy, cluttered. The rescue job.
##     STAGE 1  RECOVERY     back within normal service height, edges cleaner.
##     STAGE 2  MAINTAINED   a cared-for property. Ordinary recurring work.
##
## ---------------------------------------------------------------------------
## MAINTAINED IS THE NEUTRAL DEFAULT
## ---------------------------------------------------------------------------
## Every property that is not a project is MAINTAINED, and `apply()` changes
## NOTHING at that stage. That is what guarantees this system cannot move a
## single existing property: the overwhelming majority of contracts take the
## default branch and are generated exactly as they always were.
##
## ---------------------------------------------------------------------------
## THE IDENTITY NEVER CHANGES
## ---------------------------------------------------------------------------
## A project property is the same customer, the same seed, the same archetype,
## the same house, the same pond and the same layout at every stage. The seed
## still decides everything; the stage only moves values the seed already drew,
## exactly as `ACAPropertyArchetype` does. What the player's work changes is the
## CONDITION, never the address.
##
## PUBLIC API
##   enum Stage { NEGLECTED, RECOVERY, MAINTAINED }
##   static is_project_site(property_seed, property_type) -> bool
##   static stage_for(property_seed, property_type, services_completed) -> int
##   static apply(params) -> void            reshape in place, after the archetype
##   static stage_name(stage) / stage_note(stage) -> String
##   static contract_label(stage) -> String  what the work order calls it
##   static pay_multiplier(stage) -> float   what a rescue is worth
##
## INVARIANTS
##   * `apply()` NEVER draws a random number, exactly like the archetype. It only
##     moves values `ACAPropertyParams.for_seed()` already drew.
##   * `apply()` at MAINTAINED is a no-op.
##   * `is_project_site()` is a pure function of the seed and the property type.

enum Stage { NEGLECTED, RECOVERY, MAINTAINED }

const STAGE_NAMES := {
	Stage.NEGLECTED: "Neglected",
	Stage.RECOVERY: "Recovering",
	Stage.MAINTAINED: "Maintained",
}

const STAGE_NOTES := {
	Stage.NEGLECTED: "Badly overdue. Heavy growth and a lot of clutter in it.",
	Stage.RECOVERY: "Coming back. Growth is under control and the edges are tidier.",
	Stage.MAINTAINED: "Kept properly. Ordinary recurring service.",
}

## What the job board calls the contract at each stage.
const CONTRACT_LABELS := {
	Stage.NEGLECTED: "Property Recovery",
	Stage.RECOVERY: "Follow-Up Service",
	Stage.MAINTAINED: "",
}

## HOW OFTEN A PROPERTY IS A PROJECT, by the kind of place it is.
##
## Nobody lets a hotel forecourt go, so hospitality and commercial work almost
## never is one. A rural property or an empty house very much can be.
const PROJECT_CHANCE := {
	ACAJobEnums.PropertyType.RESIDENTIAL: 0.20,
	ACAJobEnums.PropertyType.COMMUNITY: 0.22,
	ACAJobEnums.PropertyType.RURAL: 0.28,
	ACAJobEnums.PropertyType.INDUSTRIAL: 0.24,
	ACAJobEnums.PropertyType.PUBLIC: 0.14,
	ACAJobEnums.PropertyType.INSTITUTIONAL: 0.10,
	ACAJobEnums.PropertyType.COMMERCIAL: 0.06,
	ACAJobEnums.PropertyType.HOSPITALITY: 0.04,
}

## WHAT A RESCUE IS WORTH. A neglected property is harder work, produces far more
## to carry away, and the customer knows it - so the contract pays for that, once,
## on the visit that does the work.
const PAY_MULTIPLIER := {
	Stage.NEGLECTED: 1.45,
	Stage.RECOVERY: 1.12,
	Stage.MAINTAINED: 1.0,
}


## Is this property one of the projects? Pure, and its own random stream.
static func is_project_site(property_seed: int, property_type: int) -> bool:
	var chance := float(PROJECT_CHANCE.get(property_type, 0.12))
	var rng := RandomNumberGenerator.new()
	# Mixed with a constant of its own so this can never consume, reorder or
	# collide with the draws made from the same seed by the job generator, the
	# property generator, the contract terms or the territory.
	rng.seed = (property_seed ^ 0x0C0FFEE1) & 0x7FFFFFFF
	return rng.randf() < chance


## The condition this property is in, given how many times the business has
## finished a contract on it. An ordinary property is always MAINTAINED.
static func stage_for(property_seed: int, property_type: int,
		services_completed: int) -> int:
	if not is_project_site(property_seed, property_type):
		return Stage.MAINTAINED
	return clampi(services_completed, Stage.NEGLECTED, Stage.MAINTAINED)


static func stage_name(stage: int) -> String:
	return String(STAGE_NAMES.get(stage, "Maintained"))


static func stage_note(stage: int) -> String:
	return String(STAGE_NOTES.get(stage, STAGE_NOTES[Stage.MAINTAINED]))


## What the work order calls a contract at this stage. Empty for ordinary work,
## which is what stops every card in the game growing a label.
static func contract_label(stage: int) -> String:
	return String(CONTRACT_LABELS.get(stage, ""))


static func pay_multiplier(stage: int) -> float:
	return float(PAY_MULTIPLIER.get(stage, 1.0))


static func is_project_stage(stage: int) -> bool:
	return stage == Stage.NEGLECTED or stage == Stage.RECOVERY


# =================================================================== reshaping

## RESHAPE A PROPERTY FOR ITS CONDITION. Called last in
## `ACAPropertyParams.for_seed()`, after the archetype, and it never draws.
##
## What a stage changes, and why each one is a value the seed already holds:
##
##   `grass_height_scale`  how far over the standard the uncut grass stands. This
##                         is the whole of the visible difference from the seat.
##   `clutter`             how many rocks and shrub clumps are on the lawn. A
##                         neglected property has things in the grass; a
##                         maintained one has the handful the seed drew.
##   `bed_overgrowth`      how far the planted beds have spread past their edge.
##   `dryness` / `lawn_colour_bias`  a neglected lawn is patchier and yellower.
##   `boundary_condition`  which fence treatment the boundary builds.
static func apply(params: ACAPropertyParams) -> void:
	if params == null or params.condition_stage == Stage.MAINTAINED:
		return

	match params.condition_stage:
		Stage.NEGLECTED:
			# HEAVY GROWTH. Well over an ordinary overdue lawn, and the reason a
			# rescue contract feels like one from the first metre.
			params.grass_height_scale = 1.85
			params.clutter = clampf(params.clutter + 0.55, 0.0, 1.0)
			params.bed_overgrowth = 1.0
			params.boundary_condition = 0.0
			# Patchy and going over. The seed's own dryness is pushed up rather
			# than replaced, so two neglected properties are still different.
			params.dryness = clampf(params.dryness * 1.5 + 0.16, 0.0, 1.0)
			params.lawn_colour_bias = clampf(params.lawn_colour_bias - 0.35, -1.0, 1.0)
			params.shrub_density = clampf(params.shrub_density * 1.3, 0.0, 2.0)
		Stage.RECOVERY:
			# BACK UNDER CONTROL. Still a bit rough, plainly being looked after.
			params.grass_height_scale = 1.22
			params.clutter = clampf(params.clutter + 0.18, 0.0, 1.0)
			params.bed_overgrowth = 0.45
			params.boundary_condition = 0.5
			params.dryness = clampf(params.dryness * 1.15 + 0.04, 0.0, 1.0)
			params.lawn_colour_bias = clampf(params.lawn_colour_bias - 0.12, -1.0, 1.0)
