class_name ACAContractTerms
extends RefCounted
## WHAT A CONTRACT ASKS FOR BEYOND "MOW IT". Pure, static, no nodes, no state.
##
## ---------------------------------------------------------------------------
## DERIVED, NOT STORED
## ---------------------------------------------------------------------------
## Every term below is a pure function of a contract's OWN seed, property type
## and size. Nothing here is written to a save file, nothing is added to
## `ACAJob`, and the Job System does not know this class exists.
##
## That is not a shortcut, it is the point:
##
##   * the same contract always asks for the same things, on any machine, in any
##     build, before and after a reload;
##   * a save written before contract terms existed loads with terms already on
##     its contracts, correctly, because they were always implicit in the seed;
##   * a term can be added or retuned without a save migration.
##
## The one thing that IS stored is whether the player met the terms, and that
## lives with the completed job in `Business`, not here.
##
## ---------------------------------------------------------------------------
## ONLY THINGS THE GAME CAN MEASURE
## ---------------------------------------------------------------------------
## Every term maps to a number the mowing runtime already produces: the cut
## fraction, the elapsed stopwatch, the clipping ledger and the fuel authority.
## There is deliberately no "quality" or "neatness" requirement, because nothing
## in the game measures either and a requirement the game cannot judge is a
## requirement it would have to fake.

## The bits of `terms_for()`'s `flags`.
enum Flag {
	NONE = 0,
	## The customer wants the clippings taken away. Mulching does not satisfy it.
	COLLECT = 1 << 0,
	## The customer would rather the clippings were left on the lawn. Bagging is
	## allowed, it just earns nothing extra.
	MULCH = 1 << 1,
	## Finish inside the service window.
	ON_TIME = 1 << 2,
	## Do not run the tank dry on their property.
	NO_DRY_TANK = 1 << 3,
	## The customer asked for a particular finish. See `ACAFinishPattern`.
	PATTERN = 1 << 4,
	## There is ground on this property that is not to be cut at all. See
	## `ACAConservationZone`.
	CONSERVE = 1 << 5,
}

## Roughly how often a generated contract carries any optional term at all.
## Below half on purpose: a requirement on every job is not a requirement, it is
## the rules.
const OPTIONAL_CHANCE := 0.55

## How generous the service window is, as a multiple of the contract's own
## estimated duration. 1.35 is comfortable for a player who knows the machine
## and tight for one who wanders.
const WINDOW_SLACK := 1.35

## Bonus paid for meeting an optional term, as a share of the contract's pay.
const BONUS_SHARE := {
	Flag.COLLECT: 0.16,
	Flag.ON_TIME: 0.10,
	Flag.NO_DRY_TANK: 0.06,
	Flag.PATTERN: ACAFinishPattern.BONUS_SHARE,
	Flag.CONSERVE: 0.12,
}

## A MANDATORY collection contract pays more for the trouble, and is refused
## rather than merely unrewarded if the clippings are left behind. Only
## collection is ever mandatory: a deadline the player misses by ten seconds
## should cost them a bonus, not a day's work.
const MANDATORY_COLLECT_UPLIFT := 0.22

## HOW MUCH OF A PROTECTED AREA MAY BE CUT before the objective is failed. Eight
## per cent: a clipped corner and a pass that strayed are forgiven, and mowing a
## strip through the middle of a meadow is not.
const CONSERVATION_TOLERANCE := 0.08


## Everything one contract asks for. Keys:
##   flags              int, a mask of `Flag`
##   mandatory          int, the subset of `flags` that must be met to complete
##   window_minutes     float, game minutes allowed. 0 when there is no window.
##   collect_target_kg  float, 0 unless COLLECT is set
static func terms_for(job: ACAJob) -> Dictionary:
	var empty := {
		"flags": int(Flag.NONE), "mandatory": int(Flag.NONE),
		"window_minutes": 0.0, "collect_target_kg": 0.0,
	}
	if job == null:
		return empty

	# ITS OWN STREAM. Mixed with a constant so this never consumes, reorders or
	# collides with the draws the job generator or the property generator make
	# from the same seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = (job.seed ^ 0x5EA51DE5) & 0x7FFFFFFF

	if rng.randf() > OPTIONAL_CHANCE:
		# NO CUSTOMER TERMS, which is not the same as no terms: the property may
		# still have protected ground on it and the customer may still have
		# asked for a finish. Both are the ground and the seed rather than a
		# preference, so they are added whatever this roll said.
		empty["flags"] = _property_flags(job)
		return empty

	var flags := int(Flag.NONE)
	var mandatory := int(Flag.NONE)

	# WHAT THE CUSTOMER WANTS DONE WITH THE CLIPPINGS is decided by the KIND of
	# place it is, not by a free roll. A hotel forecourt does not want cuttings
	# left across it; a rural paddock has nowhere for them to go anyway.
	var collect_bias := _collection_bias(job.property_type)
	var roll := rng.randf()
	if roll < collect_bias:
		flags |= int(Flag.COLLECT)
		# About a third of collection contracts insist. The rest pay a bonus.
		if rng.randf() < 0.34:
			mandatory |= int(Flag.COLLECT)
	elif roll < collect_bias + 0.30:
		flags |= int(Flag.MULCH)

	if rng.randf() < 0.45:
		flags |= int(Flag.ON_TIME)
	if rng.randf() < 0.30:
		flags |= int(Flag.NO_DRY_TANK)

	var window := 0.0
	if flags & int(Flag.ON_TIME):
		window = _estimated_minutes(job) * WINDOW_SLACK

	var target := 0.0
	if flags & int(Flag.COLLECT):
		target = expected_yield_kg(job)

	return {
		"flags": flags | _property_flags(job), "mandatory": mandatory,
		"window_minutes": window, "collect_target_kg": target,
	}


## ---------------------------------------------------------------------------
## THE TWO TERMS THAT COME FROM THE PROPERTY RATHER THAN FROM THE CUSTOMER
## ---------------------------------------------------------------------------
## A requested finish and a conservation zone are not rolled by this class and
## are not gated on `OPTIONAL_CHANCE`: one is `ACAFinishPattern`'s own draw and
## the other is a fact about the ground `ACAConservationZone` will generate. Both
## are still pure functions of the contract's seed, which is why they can be
## folded in here as ordinary flags and scored, described and paid for through
## exactly the machinery the other four already use.
##
## Both are read OUTSIDE the early return above, so a contract with no customer
## terms at all can still be a park with two wildflower meadows on it.
static func _property_flags(job: ACAJob) -> int:
	var flags := int(Flag.NONE)
	if ACAFinishPattern.requests_pattern(job):
		flags |= int(Flag.PATTERN)
	if ACAConservationZone.likely_for_job(job):
		flags |= int(Flag.CONSERVE)
	return flags


## How likely this kind of place is to want its clippings taken away.
static func _collection_bias(property_type: int) -> float:
	match property_type:
		ACAJobEnums.PropertyType.HOSPITALITY, ACAJobEnums.PropertyType.COMMERCIAL:
			return 0.62
		ACAJobEnums.PropertyType.INSTITUTIONAL, ACAJobEnums.PropertyType.RESIDENTIAL:
			return 0.48
		ACAJobEnums.PropertyType.PUBLIC, ACAJobEnums.PropertyType.COMMUNITY:
			return 0.34
		ACAJobEnums.PropertyType.RURAL, ACAJobEnums.PropertyType.INDUSTRIAL:
			return 0.14
	return 0.35


# ================================================================== questions

static func flags_of(job: ACAJob) -> int:
	return int(terms_for(job)["flags"])


static func requires_collection(job: ACAJob) -> bool:
	return (flags_of(job) & int(Flag.COLLECT)) != 0


static func collection_is_mandatory(job: ACAJob) -> bool:
	return (int(terms_for(job)["mandatory"]) & int(Flag.COLLECT)) != 0


static func prefers_mulching(job: ACAJob) -> bool:
	return (flags_of(job) & int(Flag.MULCH)) != 0


static func has_any_terms(job: ACAJob) -> bool:
	return flags_of(job) != int(Flag.NONE)


static func requests_pattern(job: ACAJob) -> bool:
	return (flags_of(job) & int(Flag.PATTERN)) != 0


static func has_protected_ground(job: ACAJob) -> bool:
	return (flags_of(job) & int(Flag.CONSERVE)) != 0


## The service window in game minutes, or 0 when there is none.
static func window_minutes(job: ACAJob) -> float:
	return float(terms_for(job)["window_minutes"])


## How much cut grass this contract is expected to produce, in kilograms.
## Derived from the contract's own grid, so it agrees with what the mowing scene
## will actually generate from the property built for that grid.
static func expected_yield_kg(job: ACAJob) -> float:
	if job == null:
		return 0.0
	var cells := float(maxi(job.grid_size.x * job.grid_size.y, 1))
	# The generator excludes roughly a tenth for water, planting and obstacles.
	return cells * 0.9 * ACAClippings.KG_PER_CELL


## The contract's own estimated duration, in game minutes. Asks the Job System
## when it is available so the number on the work order and the number the
## window is measured against are the same one.
static func _estimated_minutes(job: ACAJob) -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var manager := tree.root.get_node_or_null(^"/root/JobManager")
		if manager != null:
			return float(manager.call(&"estimated_time_minutes", job))
	return maxf(float(job.grid_size.x * job.grid_size.y) / 1800.0, 4.0)


# ================================================================== scoring

## Did the finished contract meet each of its terms?
##
## `outcome` is what the mowing runtime measured:
##   collected_kg     float, clippings actually delivered to the truck
##   elapsed_minutes  float, GAME minutes the contract took
##   ran_dry          bool, whether the tank reached empty on this property
##
## Returns `{ met: int, missed: int, mandatory_missed: int, bonus: int }`, where
## the three masks are subsets of the contract's own flags and `bonus` is the
## money earned, already rounded.
static func score(job: ACAJob, outcome: Dictionary) -> Dictionary:
	var terms := terms_for(job)
	var flags := int(terms["flags"])
	var met := int(Flag.NONE)
	var missed := int(Flag.NONE)

	if flags & int(Flag.COLLECT):
		# Within a tenth of the expected yield counts: a player is not going to
		# recover the last blade, and asking them to would make a term into a
		# chore.
		var wanted := float(terms["collect_target_kg"]) * 0.9
		if float(outcome.get("collected_kg", 0.0)) >= wanted:
			met |= int(Flag.COLLECT)
		else:
			missed |= int(Flag.COLLECT)

	if flags & int(Flag.ON_TIME):
		if float(outcome.get("elapsed_minutes", 0.0)) <= float(terms["window_minutes"]):
			met |= int(Flag.ON_TIME)
		else:
			missed |= int(Flag.ON_TIME)

	if flags & int(Flag.NO_DRY_TANK):
		if bool(outcome.get("ran_dry", false)):
			missed |= int(Flag.NO_DRY_TANK)
		else:
			met |= int(Flag.NO_DRY_TANK)

	# THE REQUESTED FINISH. `ACAFinishPattern` did the measuring on the real
	# lawn; this only reads the verdict, exactly as it reads the clipping ledger
	# and the fuel authority for the terms above.
	if flags & int(Flag.PATTERN):
		if bool(outcome.get("pattern_met", false)):
			met |= int(Flag.PATTERN)
		else:
			missed |= int(Flag.PATTERN)

	# CONSERVATION COMPLIANCE. A tolerance rather than a line: driving over the
	# corner of a meadow is not the same as mowing it, and a term that failed on
	# one flower would be a term nobody attempted.
	if flags & int(Flag.CONSERVE):
		if float(outcome.get("protected_damage", 0.0)) <= CONSERVATION_TOLERANCE:
			met |= int(Flag.CONSERVE)
		else:
			missed |= int(Flag.CONSERVE)

	var bonus := 0.0
	for flag: int in BONUS_SHARE:
		if not (met & flag):
			continue
		var share := float(BONUS_SHARE[flag])
		# THE FINISH BONUS SCALES WITH HOW GOOD IT WAS. Every other term is met
		# or it is not; a pattern has a quality, and paying a scruffy pass the
		# same as an immaculate one would waste the only term the game measures
		# on a curve. Half for meeting it, half for how well.
		if flag == int(Flag.PATTERN):
			share *= 0.5 + 0.5 * clampf(float(outcome.get("pattern_score", 0.0)), 0.0, 1.0)
		bonus += float(job.base_pay) * share

	return {
		"met": met,
		"missed": missed,
		"mandatory_missed": missed & int(terms["mandatory"]),
		"bonus": int(round(bonus)),
	}


# ================================================================== display

## One line per term, for the work order and the job card. Each entry:
##   `{ flag, text, mandatory }`
static func describe(job: ACAJob) -> Array:
	var terms := terms_for(job)
	var flags := int(terms["flags"])
	var mandatory := int(terms["mandatory"])
	var out: Array = []
	if flags & int(Flag.COLLECT):
		out.append({
			"flag": int(Flag.COLLECT),
			"text": "Collect the clippings (about %s)" % ACAClippings.format_kg(
				float(terms["collect_target_kg"])),
			"mandatory": (mandatory & int(Flag.COLLECT)) != 0,
		})
	if flags & int(Flag.MULCH):
		out.append({
			"flag": int(Flag.MULCH),
			"text": "Mulching is fine; leave the clippings down",
			"mandatory": false,
		})
	if flags & int(Flag.ON_TIME):
		out.append({
			"flag": int(Flag.ON_TIME),
			"text": "Finish within %d minutes on site" % int(round(
				float(terms["window_minutes"]))),
			"mandatory": false,
		})
	if flags & int(Flag.NO_DRY_TANK):
		out.append({
			"flag": int(Flag.NO_DRY_TANK),
			"text": "Do not run the tank dry on site",
			"mandatory": false,
		})
	if flags & int(Flag.PATTERN):
		out.append({
			"flag": int(Flag.PATTERN),
			"text": "Finish it in %s" % ACAFinishPattern.pattern_name(
				ACAFinishPattern.pattern_for(job)).to_lower(),
			"mandatory": false,
		})
	if flags & int(Flag.CONSERVE):
		out.append({
			"flag": int(Flag.CONSERVE),
			"text": "Leave the protected planting uncut",
			"mandatory": false,
		})
	return out


## The same thing as one sentence, for a job card that has room for a line.
static func summary_line(job: ACAJob) -> String:
	var parts := PackedStringArray()
	for term: Dictionary in describe(job):
		var text := String(term["text"])
		parts.append(("%s (required)" % text) if bool(term["mandatory"]) else text)
	return " · ".join(parts)


## The SHORT name of a term, for a results sheet that has already printed the
## measurements above it. "Clippings collected" was the wrong name here: the
## sheet lists what was collected two lines earlier, and the same words for a
## reading and for a verdict read as the card contradicting itself.
static func flag_name(flag: int) -> String:
	match flag:
		int(Flag.COLLECT):
			return "Take the clippings away"
		int(Flag.MULCH):
			return "Mulching permitted"
		int(Flag.ON_TIME):
			return "Finish inside the window"
		int(Flag.NO_DRY_TANK):
			return "Keep fuel in the tank"
		int(Flag.PATTERN):
			return "The requested finish"
		int(Flag.CONSERVE):
			return "Protected planting left alone"
	return ""
