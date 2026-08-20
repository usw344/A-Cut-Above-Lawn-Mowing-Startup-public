class_name ACATrailerLawnAdapter
extends Node
## DEVELOPMENT / MEDIA TOOLING. Owns what the lawn LOOKS like in a trailer shot.
##
## ---------------------------------------------------------------------------
## WHY
## ---------------------------------------------------------------------------
## Two problems, one answer.
##
## 1. `ACATrailerMowerAdapter` owns the mower's transform during a shot, so the
##    mower produces no slide collisions and the grid is never told anything was
##    cut. Without this the trailer mower would drive over tall grass and leave
##    it standing.
##
## 2. A Large Lawn is 36,864 blades. Forty seconds of footage cannot cut a
##    meaningful fraction of it by driving, so every shot in Trailer V2 was
##    filmed on an almost untouched lawn and the mowing never read as progress.
##
## Both are solved by cutting through the grid's OWN api, selected by geometry:
## `Custom_Gridmap.mow_swath()` runs exactly the bookkeeping a collision would --
## the same `mow_item_silent`, the same MultiMesh rebuild, the same progress
## counter and the same `mowing_progress_changed` signal. The grass that
## disappears is really gone, the HUD percentage is really that percentage, and
## a save taken mid-trailer would round-trip.
##
## What is STAGED is only WHICH blades get cut and WHEN -- which is exactly the
## thing a trailer is allowed to stage.

## Half-width of the cut the mower leaves behind it, in world units. The rider's
## deck is about 8 units wide at this world scale; a little wider makes the
## stripe read on video without looking like a bulldozer.
const CUT_HALF_WIDTH := 5.2

var _grid: Custom_Gridmap = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(grid: Custom_Gridmap) -> void:
	_grid = grid


func is_bound() -> bool:
	return _grid != null and is_instance_valid(_grid)


func mowed_fraction() -> float:
	return _grid.mowed_fraction() if is_bound() else 0.0


## Follow the mower. Connected to `ACATrailerMowerAdapter.moved`, so the swath
## is cut along the segment actually travelled rather than sampled per frame --
## at trailer speed a per-frame disc would leave gaps between the discs.
func on_mower_moved(from: Vector3, to: Vector3) -> void:
	if is_bound():
		_grid.mow_swath(from, to, CUT_HALF_WIDTH)


## Lay `count` finished stripes across the lawn, centred on `centre` and running
## along `yaw`. Used behind a covered screen to give a shot a lawn that is
## visibly PART DONE, which is what makes the mowing read.
##
## Returns how many blades were cut.
func stage_stripes(centre: Vector3, yaw: float, count: int, length: float,
		spacing: float = -1.0, half_width: float = -1.0) -> int:
	if not is_bound() or count <= 0:
		return 0
	var width: float = half_width if half_width > 0.0 else CUT_HALF_WIDTH
	var pitch: float = spacing if spacing > 0.0 else width * 2.0
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var sideways := Vector3(cos(yaw), 0.0, -sin(yaw))
	var cut := 0
	for i in count:
		# Grown from one edge rather than around the centre, so a staged lawn
		# reads as work that started somewhere and stopped, not as a stripe
		# pattern airbrushed over the middle.
		var lane: Vector3 = centre + sideways * (float(i) - float(count - 1) * 0.5) * pitch
		cut += _grid.mow_swath(lane - forward * length * 0.5,
			lane + forward * length * 0.5, width)
	return cut


## One finished pass between two points. Used to put a cut trail BEHIND the
## mower before a shot starts -- a mower that has only just been placed has
## nothing behind it, and "cut stripe streaming away" is the whole point of the
## tracking shots.
func cut_line(from: Vector3, to: Vector3, half_width: float = -1.0) -> int:
	if not is_bound():
		return 0
	return _grid.mow_swath(from, to,
		half_width if half_width > 0.0 else CUT_HALF_WIDTH)


## Cut everything within `radius` of a point. For clearing the ground a hero
## close-up is standing on, where tall grass in the extreme foreground would
## otherwise fill the lens.
func clear_around(centre: Vector3, radius: float) -> int:
	return _grid.mow_disc(centre, radius) if is_bound() else 0
