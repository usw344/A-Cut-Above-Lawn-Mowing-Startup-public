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


func bind(mower: Node3D, lawn: ACALawn) -> void:
	_mower = mower
	_lawn = lawn
	_deck = ACAMowerDeck.for_mower(mower)
	_has_previous = false
	_cells_cut = 0


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


## Forget the previous pose. Call after moving the machine deliberately - a save
## restore, a trailer placement, a restart - so the next update measures from
## where it now is.
func resync() -> void:
	_has_previous = false


## THE cut. Connected to the mower's `collided` signal, whose payload is the old
## contact list and is deliberately ignored.
func on_blades_active(_collisions: Array = []) -> void:
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
	_previous = now
	if cells > 0:
		_cells_cut += cells
		cut.emit(cells)
