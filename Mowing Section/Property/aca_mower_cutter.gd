class_name ACAMowerCutter
extends Node
## ROLE
## The join between a machine and the lawn. It watches where the mower's deck
## has been and tells the lawn what that swept it over.
##
## ---------------------------------------------------------------------------
## WHY THIS EXISTS AS ITS OWN THING
## ---------------------------------------------------------------------------
## The old lawn was cut by CONTACT: every blade of grass was a static body, the
## mower reported its slide collisions, and the grid looked each collider up by
## name. That is what forced tens of thousands of physics bodies into the scene,
## and with them the body limits and the physics rate.
##
## Cutting is now geometry. The machine's deck is a rectangle in world space;
## between one update and the next it sweeps a band of ground; everything under
## that band is cut. No contact, no bodies, no names.
##
## ONE THING IS DELIBERATELY UNCHANGED. The mowers still emit `collided` every
## physics frame while their engine is running, and `fuel_empty` when it is not.
## This listens to `collided`, so an empty tank stops the blades for exactly the
## reason it always did, and no mower controller had to learn about the new
## lawn.
##
## PUBLIC API
##   bind(mower, lawn) / unbind() / is_bound()
##   deck() -> ACAMowerDeck
##   on_blades_active(collisions := [])   the signal target
##   resync()                             forget where the machine was
##   cells_cut() -> int
##   coverage() / contacts() / reset_counters()
##
## SIGNALS
##   cut(cells: int)   emitted when a call actually cut something
##
## INVARIANTS
##   * A jump larger than REPOSITION_DISTANCE is treated as a placement, not as
##     driving, so restoring a save or staging a shot cannot mow a stripe
##     across the property.
##   * The deck is resolved once per bind, from the machine itself.
##
## PERSISTENCE OWNERSHIP: None.

signal cut(cells: int)

## Further than a machine can travel in one update at any sane speed. Beyond
## this the transform changed because something MOVED the mower.
const REPOSITION_DISTANCE := 12.0

var _mower: Node3D = null
var _lawn: ACALawn = null
var _deck: ACAMowerDeck = null
var _previous := Transform3D.IDENTITY
var _has_previous := false
var _cells_cut := 0

# ------------------------------------------------------------- WORKMANSHIP
#
# Two readings taken while the cutting happens, because this is the one place
# that already knows how far the machine moved, how wide its deck is, and how
# much of what it passed over was really standing grass.
#
# Neither is tracked anywhere else and neither costs anything worth measuring:
# the distance is already computed for the reposition test, `is_mowable()` is an
# index lookup, and the contacts are on a list the mower already hands over.
# There is no second sweep of the lawn and no spatial analysis.

## Square units of lawn the deck has passed over WHILE OVER THE LAWN. Driving to
## the truck to unload, or round the far side of a pond, is not counted against
## the player: the machine had to do it.
var _swept_area: float = 0.0
## Separate times the machine has touched something solid, counted on the RISING
## EDGE - the mowers report their slide collisions every physics frame, so a
## single scrape along a fence would otherwise count as several hundred.
var _contacts: int = 0
var _in_contact: bool = false
## Seconds since the last counted contact. A machine sliding along a fence
## flickers in and out of contact from one physics frame to the next, and
## without this a single scrape counts as dozens.
var _since_contact: float = 0.0

## How long after a contact before another can be counted as separate.
const CONTACT_DEBOUNCE := 0.4


func bind(mower: Node3D, lawn: ACALawn) -> void:
	_mower = mower
	_lawn = lawn
	_deck = ACAMowerDeck.for_mower(mower)
	_has_previous = false
	_cells_cut = 0
	reset_counters()


func unbind() -> void:
	_mower = null
	_lawn = null
	_has_previous = false


func is_bound() -> bool:
	return _mower != null and is_instance_valid(_mower) \
		and _lawn != null and is_instance_valid(_lawn)


func deck() -> ACAMowerDeck:
	return _deck


func cells_cut() -> int:
	return _cells_cut


## HOW MUCH OF THE GROUND THE DECK PASSED OVER WAS STANDING GRASS, 0-1.
##
## A mowing cell is exactly one world unit, so cells cut and square units swept
## are directly comparable and a single pass over uncut grass reads as 1.0.
## Everything below that is ground covered twice: overlapping passes, turns
## taken on cut grass, and hunting for a missed patch at the end.
##
## It is a measure of ROUTE, not of speed, and it is only ever used to say
## something encouraging.
func coverage() -> float:
	if _swept_area <= 0.0:
		return 0.0
	return clampf(float(_cells_cut) / _swept_area, 0.0, 1.0)


## How many separate times the machine touched something that was not the ground.
func contacts() -> int:
	return _contacts


## Put the workmanship readings back to nothing. Called on bind, and by the
## mowing scene when the player restarts a contract - the lawn goes back to how
## it was found, so the record of how it was cut has to as well.
func reset_counters() -> void:
	_swept_area = 0.0
	_contacts = 0
	_in_contact = false
	_since_contact = CONTACT_DEBOUNCE


## Forget the previous pose. Call after moving the machine deliberately - a save
## restore, a trailer placement, a restart - so the next update measures from
## where it now is.
func resync() -> void:
	_has_previous = false


## THE cut. Connected to the mower's `collided` signal. The payload is the slide
## contact list, which the cutting itself still ignores - cutting has been
## geometry since the lawn stopped being physics bodies - but which the
## workmanship reading below does use, because it is already there.
func on_blades_active(collisions: Array = []) -> void:
	if not is_bound():
		return
	var now := _mower.global_transform
	if not _has_previous:
		_previous = now
		_has_previous = true
		return
	if _previous.origin.distance_to(now.origin) > REPOSITION_DISTANCE:
		# Something placed the machine rather than drove it.
		_previous = now
		return

	var cells := _lawn.mow_deck(_previous, now, _deck)
	_measure_workmanship(_previous, now, collisions)
	_previous = now
	if cells > 0:
		_cells_cut += cells
		cut.emit(cells)


func _measure_workmanship(previous: Transform3D, now: Transform3D,
		collisions: Array) -> void:
	if _deck != null and _lawn.is_mowable(now.origin):
		_swept_area += previous.origin.distance_to(now.origin) \
			* _deck.half_width * 2.0

	# A near-vertical normal is the ground, which the machine is always touching.
	var touching := false
	for c in collisions:
		var hit := c as KinematicCollision3D
		if hit != null and absf(hit.get_normal().y) < 0.5:
			touching = true
			break
	_since_contact += 1.0 / float(Engine.physics_ticks_per_second)
	if touching and not _in_contact and _since_contact >= CONTACT_DEBOUNCE:
		_contacts += 1
		_since_contact = 0.0
	_in_contact = touching
