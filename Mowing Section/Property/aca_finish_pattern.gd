class_name ACAFinishPattern
extends RefCounted
## THE FINISH A CUSTOMER ASKED FOR. Pure, static, no nodes, no state.
##
## The lawn has always remembered which way the machine was pointing when it cut
## each cell - that is what draws the stripes. This reads the same record back
## and asks whether it makes a PATTERN.
##
##     PARALLEL     every pass on one axis. The ordinary striped lawn.
##     DIAGONAL     the same, at forty-five degrees to the property.
##     CROSS        two axes, roughly half the lawn on each.
##
## ---------------------------------------------------------------------------
## ONLY WHAT CAN BE MEASURED RELIABLY
## ---------------------------------------------------------------------------
## Three patterns, and each of them is a statement about the DISTRIBUTION of
## headings over the lawn - which is a histogram, and a histogram is something a
## byte array can answer honestly. A checkerboard needs to know where each pass
## was as well as which way it went, and scoring one fairly against a player who
## mowed a good checkerboard slightly off the grid is a harder problem than it
## is worth; a perimeter finish needs the same. Both are noted as later work
## rather than shipped badly.
##
## ---------------------------------------------------------------------------
## IT SCORES CONSISTENCY, NOT PRECISION
## ---------------------------------------------------------------------------
## A player steering a real machine corrects constantly, and a score that
## punished that would be a score nobody could get. What is measured is how much
## of the lawn agrees on an axis, with a tolerance of twenty degrees either
## side, and the pass does not have to be at any particular compass bearing -
## only consistent with itself. Turning at the end of a pass is not counted
## against anyone: a headland is a few per cent of the lawn and the threshold
## for a good score is well under a hundred.
##
## PUBLIC API
##   enum Pattern { NONE, PARALLEL, DIAGONAL, CROSS }
##   static pattern_for(job) -> int          DERIVED from the contract's seed
##   static requests_pattern(job) -> bool
##   static pattern_name(pattern) / description(pattern) -> String
##   static score(lawn, pattern, attachment_bonus) -> Dictionary
##   static bonus_share(pattern) -> float
##   static diagram_axes(pattern) -> Array   for the work order's little sketch
##
## INVARIANTS
##   * Nothing is stored. Which pattern a contract wants is a pure function of
##     its seed, exactly like `ACAContractTerms`, so a save written before
##     patterns existed loads with them already correct.
##   * `score()` reads only `ACALawn.heading_histogram()`. It never touches a
##     node, a machine or the clock.

enum Pattern { NONE, PARALLEL, DIAGONAL, CROSS }

const NAMES := {
	Pattern.NONE: "Any finish",
	Pattern.PARALLEL: "Straight stripes",
	Pattern.DIAGONAL: "Diagonal stripes",
	Pattern.CROSS: "Cross pattern",
}

const DESCRIPTIONS := {
	Pattern.NONE: "Mow it however suits you.",
	Pattern.PARALLEL: "Straight passes, all on the same line.",
	Pattern.DIAGONAL: "Straight passes at an angle across the property.",
	Pattern.CROSS: "Two sets of passes at right angles, about half the lawn each.",
}

## How many contracts ask for a finish at all. Below a fifth: a pattern is
## something a premium customer asks for, and a request on every job would be
## the rules rather than a request.
const REQUEST_CHANCE := 0.18

## Which kinds of place ask. A hotel forecourt and a civic green care what the
## lawn looks like from the road; a paddock does not.
const REQUEST_BIAS := {
	ACAJobEnums.PropertyType.HOSPITALITY: 1.9,
	ACAJobEnums.PropertyType.COMMERCIAL: 1.5,
	ACAJobEnums.PropertyType.PUBLIC: 1.3,
	ACAJobEnums.PropertyType.INSTITUTIONAL: 1.2,
	ACAJobEnums.PropertyType.RESIDENTIAL: 1.0,
	ACAJobEnums.PropertyType.COMMUNITY: 0.8,
	ACAJobEnums.PropertyType.INDUSTRIAL: 0.3,
	ACAJobEnums.PropertyType.RURAL: 0.15,
}

## What meeting the request pays, as a share of the contract.
const BONUS_SHARE := 0.14

## How many buckets the half turn is divided into when scoring. Thirty-six is
## five degrees a bucket, which is finer than any tolerance below and coarse
## enough that a lawn's worth of headings lands in a readable shape.
const BUCKETS := 36

## How far either side of an axis still counts as being on it, in buckets.
## Four buckets is twenty degrees, which is a generous but not silly amount of
## steering correction.
const TOLERANCE_BUCKETS := 4

## What share of the lawn has to agree before a single-axis pattern is met.
const PASS_THRESHOLD := 0.72
## ...and what share earns full marks.
const EXCELLENT_THRESHOLD := 0.90

## For CROSS: how even the two axes have to be. 0.5 is a perfect half; this is
## how far from it is still acceptable.
const CROSS_BALANCE_TOLERANCE := 0.22


static func pattern_name(pattern: int) -> String:
	return String(NAMES.get(pattern, "Any finish"))


static func description(pattern: int) -> String:
	return String(DESCRIPTIONS.get(pattern, ""))


static func bonus_share(_pattern: int) -> float:
	return BONUS_SHARE


# ============================================================= the derivation

## WHICH FINISH THIS CONTRACT ASKS FOR. Pure, derived from the contract's own
## seed, never stored - see the note at the top.
static func pattern_for(job: ACAJob) -> int:
	if job == null:
		return Pattern.NONE
	# ITS OWN STREAM, mixed with a constant of its own so it never consumes,
	# reorders or collides with the draws the job generator, the property
	# generator, the contract terms, the territory or the condition make from
	# the same seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = (job.seed ^ 0x571B3517) & 0x7FFFFFFF
	var chance := REQUEST_CHANCE * float(REQUEST_BIAS.get(int(job.property_type), 1.0))
	if rng.randf() >= chance:
		return Pattern.NONE
	# A CROSS IS THE RARE ONE. It is two patterns' worth of work and it is what a
	# customer asks for when they want the lawn to be the point.
	var roll := rng.randf()
	if roll < 0.44:
		return Pattern.PARALLEL
	if roll < 0.80:
		return Pattern.DIAGONAL
	return Pattern.CROSS


static func requests_pattern(job: ACAJob) -> bool:
	return pattern_for(job) != Pattern.NONE


# ================================================================== scoring

## HOW WELL THE FINISHED LAWN MATCHES THE REQUEST.
##
## `attachment_bonus` is what a striping roller adds - see
## `ACAAttachments.pattern_bonus()`. It moves the SCORE rather than the
## tolerance, because a roller lays the grass over properly and does not steer
## the machine for you.
##
## Returns `{ pattern, met, score, share, axis_degrees, note }` where `score` is
## 0-1 and `share` is the raw fraction of the lawn on the dominant axis, before
## the attachment.
static func score(lawn: ACALawn, pattern: int,
		attachment_bonus: float = 0.0) -> Dictionary:
	var empty := {
		"pattern": pattern, "met": true, "score": 1.0, "share": 1.0,
		"axis_degrees": 0.0, "note": "",
	}
	if pattern == Pattern.NONE or lawn == null:
		return empty

	var histogram := lawn.heading_histogram(BUCKETS)
	var total := 0
	for count in histogram:
		total += count
	if total <= 0:
		return {
			"pattern": pattern, "met": false, "score": 0.0, "share": 0.0,
			"axis_degrees": 0.0, "note": "Nothing was cut.",
		}

	if pattern == Pattern.CROSS:
		return _score_cross(histogram, total, attachment_bonus)
	return _score_single(histogram, total, pattern, attachment_bonus)


## ONE AXIS. Find the best band of buckets and see how much of the lawn is in it.
##
## DIAGONAL AND PARALLEL SCORE THE SAME WAY, and that is deliberate: the game
## does not know which way round the customer's house is, so "diagonal" means
## "consistently at an angle to the passes you would fall into", and the axis
## test below is what measures that. What separates them is the CHECK on the
## dominant axis afterwards.
static func _score_single(histogram: PackedInt32Array, total: int,
		pattern: int, attachment_bonus: float) -> Dictionary:
	var best := _dominant_axis(histogram)
	var share := float(best["count"]) / float(total)
	var degrees := float(best["bucket"]) / float(histogram.size()) * 180.0

	var note := ""
	var met := share >= PASS_THRESHOLD
	if pattern == Pattern.DIAGONAL and met:
		# A DIAGONAL HAS TO BE ONE. The property's own axes are 0 and 90 degrees,
		# so a "diagonal" finish driven straight up and down the lawn is a
		# straight finish with a different name on the work order.
		var off_axis: float = minf(
			minf(absf(degrees - 45.0), absf(degrees - 135.0)), 90.0)
		if off_axis > 22.0:
			met = false
			note = "The passes are square to the property rather than across it."
	elif pattern == Pattern.PARALLEL and met:
		var off_square: float = minf(minf(degrees, absf(degrees - 90.0)),
			absf(degrees - 180.0))
		if off_square > 24.0:
			met = false
			note = "The passes are at an angle rather than square to the property."

	var raw: float = clampf(
		(share - PASS_THRESHOLD) / maxf(EXCELLENT_THRESHOLD - PASS_THRESHOLD, 0.01),
		0.0, 1.0)
	var final_score: float = clampf(raw + attachment_bonus, 0.0, 1.0) if met else raw * 0.4
	if note.is_empty() and not met:
		note = "The passes wandered across too many directions."
	return {
		"pattern": pattern, "met": met, "score": final_score, "share": share,
		"axis_degrees": degrees, "note": note,
	}


## TWO AXES AT RIGHT ANGLES, and roughly half the lawn on each. Scored from the
## same histogram: the dominant axis, and then the band ninety degrees from it.
static func _score_cross(histogram: PackedInt32Array, total: int,
		attachment_bonus: float) -> Dictionary:
	var best := _dominant_axis(histogram)
	var buckets := histogram.size()
	var opposite: int = (int(best["bucket"]) + buckets / 2) % buckets
	var second := _band_count(histogram, opposite)

	var first_share := float(best["count"]) / float(total)
	var second_share := float(second) / float(total)
	var covered := first_share + second_share
	# How evenly the two axes split what they cover. 0.5 is perfect.
	var balance: float = first_share / maxf(covered, 0.001)
	var off_balance: float = absf(balance - 0.5)

	var met := covered >= PASS_THRESHOLD and off_balance <= CROSS_BALANCE_TOLERANCE
	var note := ""
	if not met:
		note = "Only one direction was used." if off_balance > CROSS_BALANCE_TOLERANCE \
			else "The passes wandered across too many directions."

	var raw: float = clampf(
		(covered - PASS_THRESHOLD) / maxf(EXCELLENT_THRESHOLD - PASS_THRESHOLD, 0.01),
		0.0, 1.0)
	raw *= clampf(1.0 - off_balance / maxf(CROSS_BALANCE_TOLERANCE, 0.01) * 0.5, 0.4, 1.0)
	var final_score: float = clampf(raw + attachment_bonus, 0.0, 1.0) if met else raw * 0.4
	return {
		"pattern": Pattern.CROSS, "met": met, "score": final_score,
		"share": covered,
		"axis_degrees": float(best["bucket"]) / float(buckets) * 180.0,
		"note": note,
	}


## The band of buckets, `TOLERANCE_BUCKETS` either side, holding the most cells.
## Wrapped, because a half turn is a circle: a pass at 178 degrees and one at 2
## are the same line.
static func _dominant_axis(histogram: PackedInt32Array) -> Dictionary:
	var best_bucket := 0
	var best_count := -1
	for bucket in histogram.size():
		var count := _band_count(histogram, bucket)
		if count > best_count:
			best_count = count
			best_bucket = bucket
	return {"bucket": best_bucket, "count": maxi(best_count, 0)}


static func _band_count(histogram: PackedInt32Array, centre: int) -> int:
	var buckets := histogram.size()
	var total := 0
	for offset in range(-TOLERANCE_BUCKETS, TOLERANCE_BUCKETS + 1):
		total += histogram[posmod(centre + offset, buckets)]
	return total


# ================================================================== display

## The axes a work-order sketch should draw, in degrees. One line for a single
## axis, two for a cross, none when no finish was asked for.
static func diagram_axes(pattern: int) -> Array:
	match pattern:
		Pattern.PARALLEL:
			return [0.0]
		Pattern.DIAGONAL:
			return [45.0]
		Pattern.CROSS:
			return [0.0, 90.0]
	return []


## What the work order says about the request.
static func request_line(job: ACAJob) -> String:
	var pattern := pattern_for(job)
	if pattern == Pattern.NONE:
		return ""
	return "Finish requested: %s" % pattern_name(pattern).to_lower()


## What the results sheet says about how it went.
static func result_line(result: Dictionary) -> String:
	if int(result.get("pattern", Pattern.NONE)) == Pattern.NONE:
		return ""
	if bool(result.get("met", false)):
		return "%s - %d%% of the lawn on line." % [
			pattern_name(int(result["pattern"])),
			int(round(float(result.get("share", 0.0)) * 100.0))]
	var note := String(result.get("note", ""))
	return note if not note.is_empty() else "The requested finish was not achieved."
