class_name ACALawn
extends Node3D
## ROLE
## THE mowing state. It owns which parts of the property are mowable, which have
## been cut, and which way the mower was pointing when it cut them. It answers
## progress, it takes cuts, and it persists.
##
## It owns no grass geometry and no physics bodies. The lawn that replaced the
## old one has ZERO collision shapes: a cut is a rectangle test against a byte
## array, not a contact between a machine and forty thousand static bodies.
##
## ---------------------------------------------------------------------------
## THE REPRESENTATION
## ---------------------------------------------------------------------------
## One byte per square world unit, so a Large lawn is 36,864 cells and 72 KB.
##
##     _flags[i]   bit 0 MOWABLE   this cell counts towards completion
##                 bit 1 CUT       it has been cut
##     _dirs[i]    the heading the mower was on when it cut, quantised to a
##                 byte over a full turn. This is what makes stripes possible
##                 without storing anything per blade of grass.
##
## Counters move only when a cell actually changes, so progress is O(1) and
## nothing ever rescans the lawn.
##
## ---------------------------------------------------------------------------
## THE MASK IS THE BRIDGE TO RENDERING
## ---------------------------------------------------------------------------
## The same state is mirrored into one small RGBA texture, one texel per cell.
## The grass and the ground read it in their shaders, which is why cutting
## costs no MultiMesh rebuild, no per-instance write and no node churn: mowing
## writes bytes, and the renderer notices.
##
## PUBLIC API
##   build(params, terrain, features)
##   mow_deck(previous, current, deck) -> int      the mathematical cut
##   mow_swath(from, to, half_width) -> int        media tooling and legacy
##   mow_disc(centre, radius) -> int               media tooling and legacy
##   total_item_count() / mowed_item_count() / mowed_fraction()
##   mowed_item_names() / restore_mowed_items(names)     compatibility
##   cut_state() / restore_cut_state(dict)               the compact save
##   apply_legacy_mowed_items(names, grid_size) -> int    save migration
##   is_mowable(world_position) -> bool
##   lawn_centre() / lawn_half_extent() / lawn_bounds()
##   cut_mask() -> Texture2D
##   reset()
##
## SIGNALS
##   mowing_progress_changed(fraction)   emitted only on a real change
##
## INVARIANTS
##   * A cell that is not MOWABLE can never become CUT, so a pond can never be
##     mowed and can never be needed to reach 100%.
##   * `total_item_count()` counts MOWABLE cells only. That is what makes a
##     pond property completable without a single pond-specific rule anywhere
##     in the mowing code.
##   * Cell size is exactly one world unit, matching the terrain lattice.
##   * The mask texture is uploaded at most once per frame, never per cut.
##
## PERSISTENCE OWNERSHIP
##   Owns the mowing half of the save block: the cut mask and its version.
##   SaveService writes it; the property parameters are owned by ACAProperty.

signal mowing_progress_changed(fraction: float)

## World units per logical cell. One, deliberately: it matches the terrain
## sample lattice and makes a lawn size the cell count.
const CELL := 1.0

const FLAG_MOWABLE := 1
const FLAG_CUT := 2

## Bumped when the meaning of the persisted cut state changes.
const CUT_STATE_VERSION := 2

## How the persisted cut state is packed. Zstandard because the data is long
## runs of identical bytes and the decode has to be quick on a load screen.
const COMPRESSION := FileAccess.COMPRESSION_ZSTD

## Sub-steps of a swept cut are never longer than this fraction of the deck, so
## a fast machine cannot skip a strip between two updates.
const SWEEP_STEP_FRACTION := 0.8

# -------------------------------------------------------------------- state
var _cells: int = 0
var _origin := Vector2.ZERO
var _half_extent: float = 0.0
var _flags := PackedByteArray()
var _dirs := PackedByteArray()
var _mowable_total: int = 0
var _cut_total: int = 0

var _mask_image: Image = null
var _mask_texture: ImageTexture = null
var _mask_dirty: bool = false

var _build_ms: float = 0.0


func _ready() -> void:
	# The mask upload is the only per-frame work this node does, and only when
	# something was actually cut.
	set_process(true)


func _process(_delta: float) -> void:
	_flush_mask()


# ======================================================================= build

## Lay out the lawn over the property and decide which cells are mowable.
## `terrain` supplies the ground height and `features` decides what is taken.
func build(params: ACAPropertyParams, terrain: ACATerrain,
		features: ACAFeatureSet = null) -> void:
	var t0 := Time.get_ticks_usec()
	var set := features if features != null else ACAFeatureSet.new()

	_cells = maxi(params.lawn_size, 4)
	_half_extent = float(_cells) * CELL * 0.5
	var centre: Vector3 = global_position if is_inside_tree() else position
	_origin = Vector2(centre.x, centre.z) - Vector2(_half_extent, _half_extent)

	var count := _cells * _cells
	_flags.resize(count)
	_dirs.resize(count)
	_mowable_total = 0
	_cut_total = 0

	_mask_image = Image.create_empty(_cells, _cells, false, Image.FORMAT_RGBA8)
	_mask_image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var index := 0
	for iz in _cells:
		var z := _origin.y + (float(iz) + 0.5) * CELL
		for ix in _cells:
			var x := _origin.x + (float(ix) + 0.5) * CELL
			var mowable := true
			if not set.is_empty():
				mowable = set.is_mowable(x, z, terrain.height_at(x, z))
			if mowable:
				_flags[index] = FLAG_MOWABLE
				_mowable_total += 1
				_mask_image.set_pixel(ix, iz, Color(0.0, 0.0, 0.0, 1.0))
			else:
				_flags[index] = 0
			_dirs[index] = 0
			index += 1

	_mask_texture = ImageTexture.create_from_image(_mask_image)
	_mask_dirty = false
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	mowing_progress_changed.emit(mowed_fraction())


## Put every cell back to uncut without rebuilding the layout. Used by RESTART
## JOB, which must not change which property the player is standing on.
func reset() -> void:
	for i in _flags.size():
		_flags[i] = _flags[i] & FLAG_MOWABLE
		_dirs[i] = 0
	_cut_total = 0
	_rebuild_mask()
	mowing_progress_changed.emit(0.0)


func build_milliseconds() -> float:
	return _build_ms


# ==================================================================== reading

## Total MOWABLE cells. Excluded ground is not in this number, which is what
## lets a property with a pond reach exactly 100%.
func total_item_count() -> int:
	return _mowable_total


func mowed_item_count() -> int:
	return _cut_total


func mowed_fraction() -> float:
	if _mowable_total <= 0:
		return 0.0
	return clampf(float(_cut_total) / float(_mowable_total), 0.0, 1.0)


func cell_count() -> int:
	return _cells


func lawn_centre() -> Vector3:
	return Vector3(_origin.x + _half_extent, position.y, _origin.y + _half_extent)


func lawn_half_extent() -> float:
	return _half_extent


func lawn_bounds() -> AABB:
	var c := lawn_centre()
	return AABB(
		Vector3(c.x - _half_extent, c.y - 50.0, c.z - _half_extent),
		Vector3(_half_extent * 2.0, 100.0, _half_extent * 2.0))


## Is this world position part of the mowable lawn at all?
func is_mowable(world_position: Vector3) -> bool:
	var i := _index_at(world_position.x, world_position.z)
	if i < 0:
		return false
	return (_flags[i] & FLAG_MOWABLE) != 0


func is_cut(world_position: Vector3) -> bool:
	var i := _index_at(world_position.x, world_position.z)
	if i < 0:
		return false
	return (_flags[i] & FLAG_CUT) != 0


## The texture the grass and ground shaders read. R cut, G heading, A mowable.
func cut_mask() -> Texture2D:
	return _mask_texture


# ==================================================================== mowing

## THE cut. A machine at `previous` that is now at `current` has swept its deck
## across the ground between the two, and everything under that sweep is cut.
##
## The sweep is stamped as a series of oriented rectangles rather than as a
## single hull, because a rectangle test is exact and a hull is not: a mower
## that turned while it moved really did cut a curve, and a hull would claim
## ground beside it. The step is bounded by the deck's own size, so however
## fast the machine is moving it cannot leave an uncut strip behind it.
func mow_deck(previous: Transform3D, current: Transform3D,
		deck: ACAMowerDeck) -> int:
	if deck == null or _cells <= 0:
		return 0
	var from := Vector2(previous.origin.x, previous.origin.z)
	var to := Vector2(current.origin.x, current.origin.z)
	var travelled := from.distance_to(to)
	var step: float = maxf(deck.half_length, 0.25) * 2.0 * SWEEP_STEP_FRACTION
	var steps: int = clampi(int(ceil(travelled / step)), 1, 64)

	var heading := _heading_of(current)
	var cut := 0
	# The sweep INCLUDES the pose it started from. Without that first stamp the
	# ground directly under a machine that has just been placed stays standing
	# until it has driven a full deck length, which shows as an uncut square
	# wherever a contract or a shot begins.
	for s in range(0, steps + 1):
		var t := float(s) / float(steps)
		var machine := previous.interpolate_with(current, t)
		cut += _stamp_deck(machine, deck, heading)
	if cut > 0:
		_after_cut(cut)
	return cut


## Cut everything within `half_width` of the segment from -> to, measured on the
## XZ plane. Kept because the trailer's lawn adapter and the staged-cut tooling
## are written against it, and because it is the honest way to express "this
## strip is finished" without pretending a machine drove it.
func mow_swath(from: Vector3, to: Vector3, half_width: float) -> int:
	if _cells <= 0:
		return 0
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var heading_vector := b - a
	var heading: int = _heading_byte(
		heading_vector.angle() if heading_vector.length_squared() > 0.0001 else 0.0)

	var min_x: float = minf(a.x, b.x) - half_width
	var max_x: float = maxf(a.x, b.x) + half_width
	var min_z: float = minf(a.y, b.y) - half_width
	var max_z: float = maxf(a.y, b.y) + half_width

	var x0 := _cell_index_x(min_x)
	var x1 := _cell_index_x(max_x)
	var z0 := _cell_index_z(min_z)
	var z1 := _cell_index_z(max_z)
	var radius_squared := half_width * half_width
	var cut := 0
	for iz in range(z0, z1 + 1):
		var z := _origin.y + (float(iz) + 0.5) * CELL
		for ix in range(x0, x1 + 1):
			var x := _origin.x + (float(ix) + 0.5) * CELL
			var p := Vector2(x, z)
			if p.distance_squared_to(
					Geometry2D.get_closest_point_to_segment(p, a, b)) > radius_squared:
				continue
			cut += _cut_cell(iz * _cells + ix, heading)
	if cut > 0:
		_after_cut(cut)
	return cut


## A disc. `mow_swath` with a zero-length segment, exactly as before.
func mow_disc(centre: Vector3, radius: float) -> int:
	return mow_swath(centre, centre, radius)


## One oriented rectangle, stamped. Returns how many cells really changed.
func _stamp_deck(machine: Transform3D, deck: ACAMowerDeck, heading: int) -> int:
	var forward3 := machine.basis.z
	var right3 := machine.basis.x
	var f := Vector2(forward3.x, forward3.z)
	var r := Vector2(right3.x, right3.z)
	if f.length_squared() < 0.000001 or r.length_squared() < 0.000001:
		return 0
	f = f.normalized()
	r = r.normalized()
	var centre := Vector2(machine.origin.x, machine.origin.z) + f * deck.forward_offset

	var reach: float = absf(f.x) * deck.half_length + absf(r.x) * deck.half_width
	var reach_z: float = absf(f.y) * deck.half_length + absf(r.y) * deck.half_width
	var x0 := _cell_index_x(centre.x - reach)
	var x1 := _cell_index_x(centre.x + reach)
	var z0 := _cell_index_z(centre.y - reach_z)
	var z1 := _cell_index_z(centre.y + reach_z)

	var cut := 0
	for iz in range(z0, z1 + 1):
		var z := _origin.y + (float(iz) + 0.5) * CELL
		var row := iz * _cells
		for ix in range(x0, x1 + 1):
			var index := row + ix
			if (_flags[index] & FLAG_MOWABLE) == 0 or (_flags[index] & FLAG_CUT) != 0:
				continue
			var d := Vector2(_origin.x + (float(ix) + 0.5) * CELL, z) - centre
			if absf(d.dot(r)) > deck.half_width:
				continue
			if absf(d.dot(f)) > deck.half_length:
				continue
			cut += _cut_cell(index, heading)
	return cut


func _cut_cell(index: int, heading: int) -> int:
	var flags := _flags[index]
	if (flags & FLAG_MOWABLE) == 0 or (flags & FLAG_CUT) != 0:
		return 0
	_flags[index] = flags | FLAG_CUT
	_dirs[index] = heading
	_mask_image.set_pixel(index % _cells, index / _cells,
		Color(1.0, float(heading) / 255.0, 0.0, 1.0))
	return 1


func _after_cut(count: int) -> void:
	_cut_total += count
	_mask_dirty = true
	mowing_progress_changed.emit(mowed_fraction())


## The mask is uploaded once per frame at most. Cutting itself only touches an
## Image in main memory, which is why a fast mower costs the same as a slow one.
func _flush_mask() -> void:
	if not _mask_dirty or _mask_texture == null:
		return
	_mask_dirty = false
	_mask_texture.update(_mask_image)


func _rebuild_mask() -> void:
	if _mask_image == null:
		return
	for iz in _cells:
		for ix in _cells:
			var index := iz * _cells + ix
			var flags := _flags[index]
			if (flags & FLAG_MOWABLE) == 0:
				_mask_image.set_pixel(ix, iz, Color(0.0, 0.0, 0.0, 0.0))
			elif (flags & FLAG_CUT) != 0:
				_mask_image.set_pixel(ix, iz,
					Color(1.0, float(_dirs[index]) / 255.0, 0.0, 1.0))
			else:
				_mask_image.set_pixel(ix, iz, Color(0.0, 0.0, 0.0, 1.0))
	_mask_dirty = true
	_flush_mask()


# =================================================================== indexing

func _cell_index_x(world_x: float) -> int:
	return clampi(int(floor((world_x - _origin.x) / CELL)), 0, _cells - 1)


func _cell_index_z(world_z: float) -> int:
	return clampi(int(floor((world_z - _origin.y) / CELL)), 0, _cells - 1)


## -1 when the position is off the lawn entirely, which is different from being
## on an excluded cell.
func _index_at(world_x: float, world_z: float) -> int:
	var fx := (world_x - _origin.x) / CELL
	var fz := (world_z - _origin.y) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= float(_cells) or fz >= float(_cells):
		return -1
	return int(fz) * _cells + int(fx)


static func _heading_byte(angle: float) -> int:
	# Quantised over a FULL turn, not half of one. Which WAY the mower was
	# pointing is the whole of a mowing stripe: two neighbouring passes lay the
	# grass over in opposite directions, and folding the angle in half would
	# throw away the only thing that makes them look different.
	var wrapped := fposmod(angle, TAU) / TAU
	return clampi(int(wrapped * 255.0), 0, 255)


static func _heading_of(machine: Transform3D) -> int:
	var forward := machine.basis.z
	return _heading_byte(Vector2(forward.x, forward.z).angle())


# ============================================================== compatibility

## Every cut cell as "x,z" strings. The compact save does not use this; it
## exists because media tooling and older tests are written against a list of
## cut items, and because a list of coordinates is easy to reason about in a
## failure report.
func mowed_item_names() -> PackedStringArray:
	var out := PackedStringArray()
	for index in _flags.size():
		if (_flags[index] & FLAG_CUT) != 0:
			out.append("%d,%d" % [index % _cells, index / _cells])
	return out


## Apply a list produced by `mowed_item_names()`. Returns how many applied.
func restore_mowed_items(item_names: PackedStringArray) -> int:
	var applied := 0
	for item_name in item_names:
		var parts := item_name.split(",")
		if parts.size() < 2:
			continue
		var ix := parts[0].to_int()
		var iz := parts[1].to_int()
		if ix < 0 or iz < 0 or ix >= _cells or iz >= _cells:
			continue
		applied += _cut_cell(iz * _cells + ix, 0)
	if applied > 0:
		_cut_total += applied
		_rebuild_mask()
		mowing_progress_changed.emit(mowed_fraction())
	return applied


# ================================================================ persistence

## The compact cut state: a bitset with one bit per cell, and the heading bytes.
##
## Both are COMPRESSED before they are encoded, because both are enormously
## repetitive - a mown lawn is long runs of the same bit and long runs of the
## same heading. A fully mown Large lawn costs a couple of kilobytes of text
## against the thirty-six thousand coordinate strings the old format wrote.
func cut_state() -> Dictionary:
	var bits := PackedByteArray()
	bits.resize((_flags.size() + 7) / 8)
	for i in bits.size():
		bits[i] = 0
	for index in _flags.size():
		if (_flags[index] & FLAG_CUT) != 0:
			bits[index / 8] = bits[index / 8] | (1 << (index % 8))
	return {
		"version": CUT_STATE_VERSION,
		"cells": _cells,
		"cut_count": _cut_total,
		"bits_size": bits.size(),
		"dirs_size": _dirs.size(),
		"cut_bits": Marshalls.raw_to_base64(bits.compress(COMPRESSION)),
		"cut_dirs": Marshalls.raw_to_base64(_dirs.compress(COMPRESSION)),
	}


## Restore state written by `cut_state()`. Returns false and changes nothing if
## the state does not describe this lawn, so a save can never quietly leave the
## player on a property that does not match their progress.
func restore_cut_state(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != CUT_STATE_VERSION:
		push_warning("[LAWN] cut state version %s is not %d; ignoring."
			% [data.get("version", 0), CUT_STATE_VERSION])
		return false
	if int(data.get("cells", 0)) != _cells:
		push_warning("[LAWN] cut state is %s cells wide, this lawn is %d."
			% [data.get("cells", 0), _cells])
		return false

	var bits := _decode(data, "cut_bits", "bits_size")
	if bits.size() < (_flags.size() + 7) / 8:
		push_warning("[LAWN] cut state is truncated; ignoring.")
		return false
	var dirs := _decode(data, "cut_dirs", "dirs_size")

	var restored := 0
	for index in _flags.size():
		var flags := _flags[index] & FLAG_MOWABLE
		if flags != 0 and (bits[index / 8] & (1 << (index % 8))) != 0:
			flags |= FLAG_CUT
			restored += 1
			_dirs[index] = dirs[index] if index < dirs.size() else 0
		else:
			_dirs[index] = 0
		_flags[index] = flags
	_cut_total = restored
	_rebuild_mask()
	mowing_progress_changed.emit(mowed_fraction())
	return true


## Undo `cut_state()`'s encoding. A block written before compression existed has
## no size key, so it is read as plain bytes rather than rejected.
func _decode(data: Dictionary, key: String, size_key: String) -> PackedByteArray:
	var raw := Marshalls.base64_to_raw(String(data.get(key, "")))
	var size := int(data.get(size_key, 0))
	if size <= 0:
		return raw
	var out := raw.decompress(size, COMPRESSION)
	return out if out.size() == size else PackedByteArray()


## MIGRATION from the legacy per-blade save format.
##
## The old lawn stored one string per cut blade, "chunk_id,x,y,z", where x and z
## are the blade's offset inside its chunk and the chunk's own position has to
## be recovered from its id. Those blades sat on a TWO unit lattice, so replaying
## them one cell at a time would restore a quarter of the area actually cut and
## silently rob the player of most of their progress. Each recorded blade is
## therefore replayed as the two-by-two patch of ground it really represented.
##
## Returns how many cells were marked.
func apply_legacy_mowed_items(item_names: PackedStringArray,
		legacy_grid_size: int) -> int:
	if legacy_grid_size <= 0 or _cells <= 0:
		return 0
	var chunks_per_side := legacy_grid_size / 4
	var chunk_count := chunks_per_side * chunks_per_side
	# The old grid spanned this range in its own space; see the note above.
	var legacy_min := -float(legacy_grid_size) * 0.5
	var legacy_span := float(legacy_grid_size) + 2.0

	var applied := 0
	for item_name in item_names:
		var parts := item_name.split(",")
		if parts.size() < 4:
			continue
		var chunk_id := parts[0].to_int()
		var local_x := parts[1].to_int()
		var local_z := parts[3].to_int()
		if chunk_id < 0 or chunk_id >= chunk_count:
			continue
		# Chunk ids were handed out in reverse order of the chunk list.
		var ordinal := chunk_count - 1 - chunk_id
		var chunk_x := ordinal % chunks_per_side
		var chunk_z := ordinal / chunks_per_side
		var legacy_x := float((chunk_x - chunks_per_side / 2) * 4 + local_x)
		var legacy_z := float((chunk_z - chunks_per_side / 2) * 4 + local_z)

		# Normalise into the new lawn, then mark the patch that blade covered.
		var u := (legacy_x - legacy_min) / legacy_span
		var v := (legacy_z - legacy_min) / legacy_span
		var ix := int(u * float(_cells))
		var iz := int(v * float(_cells))
		for dz in 2:
			for dx in 2:
				var cx := ix + dx
				var cz := iz + dz
				if cx < 0 or cz < 0 or cx >= _cells or cz >= _cells:
					continue
				applied += _cut_cell(cz * _cells + cx, 0)

	if applied > 0:
		_cut_total += applied
		_rebuild_mask()
		mowing_progress_changed.emit(mowed_fraction())
	return applied
