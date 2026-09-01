class_name ACAPortfolio
extends Node
## THE BUSINESS'S RECORD OF ITS OWN WORK. Autoloaded as `Portfolio`.
##
## Every contract the player drives is photographed twice from the same place:
## once when they arrive and once when they finish. The pair is what makes a
## finished lawn something the business KEEPS rather than something that scrolls
## off a results screen.
##
## ---------------------------------------------------------------------------
## IMAGES ARE FILES. METADATA IS SAVE STATE.
## ---------------------------------------------------------------------------
## No image data ever goes into the save JSON. A thumbnail is written to
## `user://portfolio/` as a JPEG and the save carries its FILE NAME, along with
## everything the gallery has to print. That keeps a save a few kilobytes
## whatever the player has photographed, and it means a corrupt or missing
## image degrades to a blank frame rather than to an unreadable save.
##
## ---------------------------------------------------------------------------
## A FAILED CAPTURE IS NEVER A FAILED CONTRACT
## ---------------------------------------------------------------------------
## Every entry point here returns quietly on any problem: no viewport, no
## writable directory, a headless run with nothing rendered. The contract
## settles, the money is paid, the review is written, and the portfolio simply
## has one fewer photograph in it. Nothing in the completion pathway depends on
## this class succeeding.
##
## PUBLIC API
##   capture_before(job, viewport) / capture_after(job, viewport, summary)
##   entries() / entry_count() / entry_for_seed(seed) / featured()
##   latest_pair_for_seed(seed) -> Dictionary
##   load_image(file_name) -> Texture2D          lazily, and cached
##   storage_directory() / used_bytes()
##   reset_to_new_business() / to_save_dict() / from_save_dict(data)
##
## SIGNALS
##   entry_added(entry) / entries_changed()
##
## INVARIANTS
##   * Bounded on disk. `MAX_ENTRIES` pairs, and the oldest unfeatured entry's
##     files are deleted when a new one pushes past it.
##   * Thumbnails are `THUMB_WIDTH` wide at most, and JPEG.
##   * Nothing here ever blocks, awaits or holds a frame open beyond the single
##     frame a capture needs.
##
## PERSISTENCE OWNERSHIP
##   Owns the `portfolio` section of the save file - the metadata only. The
##   image files are its own, under `user://`, and are not part of a save slot.

signal entry_added(entry: Dictionary)
signal entries_changed()

## Where the thumbnails live. Under `user://` so it is writable on every
## platform and is never mistaken for a project asset.
const DIRECTORY := "user://portfolio"

## Bounded thumbnail size. 480 wide is legible in a gallery card at any window
## size the game supports and costs about 25 KB a frame as JPEG.
const THUMB_WIDTH := 480
const THUMB_HEIGHT := 270
const JPEG_QUALITY := 0.82

## How many completed jobs the portfolio remembers. Sixty pairs is about three
## megabytes on disk and rather more history than a player will scroll through;
## past that the oldest ordinary entry is dropped, files and all.
const MAX_ENTRIES := 60

## A job has to be FEATURED-worthy on its own merits. Automatic, and deliberately
## not a judgement of the photograph: the game cannot tell a good screenshot from
## a bad one and should not pretend to.
const FEATURE_STARS := 5
const FEATURE_TRANSFORMATION := true

# --------------------------------------------------------------------- state
## Newest first. Each entry is plain built-in types only, so it round-trips
## through JSON untouched.
var _entries: Array[Dictionary] = []
## `{ file_name: ImageTexture }`, filled on demand by `load_image()`.
var _cache: Dictionary = {}
## The before-shot waiting for its after-shot, keyed by job id.
var _pending: Dictionary = {}
var _next_index: int = 1
## Set once, so a permissions problem is reported once rather than every frame.
var _storage_ready: bool = false
var _storage_warned: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)
	_ensure_directory()


func reset_to_new_business() -> void:
	# THE FILES ARE NOT DELETED. A new business is a new save slot, not a new
	# installation, and wiping the folder would take another slot's photographs
	# with it. Orphans are collected by the cap on the way past.
	_entries.clear()
	_pending.clear()
	_cache.clear()
	_next_index = 1
	entries_changed.emit()


func _ensure_directory() -> bool:
	if _storage_ready:
		return true
	var err := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	_storage_ready = err == OK or DirAccess.dir_exists_absolute(DIRECTORY)
	if not _storage_ready and not _storage_warned:
		_storage_warned = true
		push_warning("Portfolio: could not create %s; photographs are off." % DIRECTORY)
	return _storage_ready


func storage_directory() -> String:
	return DIRECTORY


# ==================================================================== capture

## THE ARRIVAL SHOT. Called by the mowing scene once the property is built and
## the standard camera is in place, before a single cell has been cut.
##
## The image is held in memory rather than written: a contract the player
## abandons never becomes a portfolio entry, and writing the before-shot first
## would leave a file behind for every one of them.
func capture_before(job: ACAJob, viewport: Viewport) -> bool:
	if job == null or viewport == null:
		return false
	var image := _grab(viewport)
	if image == null:
		return false
	_pending[String(job.id)] = image
	return true


## THE FINISHED SHOT, and the entry. `summary` is the completion summary
## `GameSession` publishes, so nothing here recomputes a payout or a rating.
func capture_after(job: ACAJob, viewport: Viewport, summary: Dictionary) -> bool:
	if job == null or viewport == null or not _ensure_directory():
		return false
	var after := _grab(viewport)
	if after == null:
		return false
	var before: Image = _pending.get(String(job.id), null)
	_pending.erase(String(job.id))

	var index := _next_index
	_next_index += 1
	var stem := "job_%d_%d" % [job.seed, index]
	var before_file := ""
	if before != null:
		before_file = _write(before, stem + "_before")
	var after_file := _write(after, stem + "_after")
	if after_file.is_empty():
		return false

	var stage := 0
	var business := get_node_or_null(^"/root/Business")
	if business != null:
		stage = int(business.call(&"condition_stage_for", job))

	var entry := {
		"index": index,
		"job_id": String(job.id),
		"seed": job.seed,
		"site": job.job_site,
		"property_type": int(job.property_type),
		"property_type_name": job.property_type_name(),
		"size_name": job.lawn_size_name(),
		"region": int(ACAServiceTerritory.region_for_job(job)),
		"day": _today() + 1,
		"payout": int(summary.get("total", 0)),
		"stars": int(summary.get("review_stars", 0)),
		"machine": String(summary.get("machine_name", "")),
		"service": String(summary.get("service_name", "")),
		"completion": float(summary.get("completion", 0.0)),
		"before": before_file,
		"after": after_file,
		"stage": stage,
		"featured": false,
	}
	entry["featured"] = _is_featured(entry, summary)
	_entries.push_front(entry)
	_enforce_cap()
	entry_added.emit(entry.duplicate())
	entries_changed.emit()
	return true


## Whether this job goes on the wall. Automatic, and it never looks at the
## picture: an excellent review, a property finished to the last cell, or a
## neglected property brought back into maintenance.
func _is_featured(entry: Dictionary, summary: Dictionary) -> bool:
	if int(entry["stars"]) >= FEATURE_STARS and float(entry["completion"]) >= 0.999:
		return true
	if FEATURE_TRANSFORMATION and int(summary.get("condition_stage_change", 0)) > 0:
		return true
	return false


## One frame of the viewport, scaled into a thumbnail. Null on anything that
## did not produce an image, which includes a headless run.
func _grab(viewport: Viewport) -> Image:
	var texture := viewport.get_texture()
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return null
	# Cover the thumbnail rather than letter-box it: the frames sit side by side
	# in a gallery and two different aspect ratios would read as two different
	# places.
	var source_aspect := float(image.get_width()) / float(image.get_height())
	var target_aspect := float(THUMB_WIDTH) / float(THUMB_HEIGHT)
	if source_aspect > target_aspect:
		var wanted := int(round(float(image.get_height()) * target_aspect))
		var x := int((image.get_width() - wanted) * 0.5)
		image = image.get_region(Rect2i(x, 0, wanted, image.get_height()))
	elif source_aspect < target_aspect:
		var wanted_h := int(round(float(image.get_width()) / target_aspect))
		var y := int((image.get_height() - wanted_h) * 0.5)
		image = image.get_region(Rect2i(0, y, image.get_width(), wanted_h))
	image.resize(THUMB_WIDTH, THUMB_HEIGHT, Image.INTERPOLATE_LANCZOS)
	return image


func _write(image: Image, stem: String) -> String:
	if image == null or not _ensure_directory():
		return ""
	var file_name := stem + ".jpg"
	var err := image.save_jpg("%s/%s" % [DIRECTORY, file_name], JPEG_QUALITY)
	if err != OK:
		push_warning("Portfolio: could not write %s (error %d)" % [file_name, err])
		return ""
	return file_name


func _enforce_cap() -> void:
	while _entries.size() > MAX_ENTRIES:
		# Featured work survives the cull as long as anything ordinary is left
		# to drop instead. Once the whole portfolio is featured, the oldest goes.
		var victim := -1
		for i in range(_entries.size() - 1, -1, -1):
			if not bool(_entries[i]["featured"]):
				victim = i
				break
		if victim < 0:
			victim = _entries.size() - 1
		_delete_files(_entries[victim])
		_entries.remove_at(victim)


func _delete_files(entry: Dictionary) -> void:
	for key in ["before", "after"]:
		var file_name := String(entry.get(key, ""))
		if file_name.is_empty():
			continue
		_cache.erase(file_name)
		var path := "%s/%s" % [DIRECTORY, file_name]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# ==================================================================== reading

## Newest first.
func entries() -> Array:
	var out: Array = []
	for entry in _entries:
		out.append(entry.duplicate())
	return out


func entry_count() -> int:
	return _entries.size()


func featured() -> Array:
	var out: Array = []
	for entry in _entries:
		if bool(entry["featured"]):
			out.append(entry.duplicate())
	return out


func featured_count() -> int:
	return featured().size()


## Every visit to one property, newest first. This is what makes a recurring
## customer's page read as a history rather than as a list of strangers.
func entries_for_seed(property_seed: int) -> Array:
	var out: Array = []
	for entry in _entries:
		if int(entry["seed"]) == property_seed:
			out.append(entry.duplicate())
	return out


## FIRST VISIT -> CURRENT CONDITION for one property, which is the pair worth
## showing for a customer the business has been back to. Empty when the property
## has only been photographed once.
func latest_pair_for_seed(property_seed: int) -> Dictionary:
	var visits := entries_for_seed(property_seed)
	if visits.size() < 2:
		return {}
	return {
		"first": visits[visits.size() - 1],
		"latest": visits[0],
	}


## Lazily loaded and cached. Returns null for a missing or unreadable file, and
## the gallery draws an empty frame - which is the honest thing to show for a
## photograph that is not there.
func load_image(file_name: String) -> Texture2D:
	if file_name.is_empty():
		return null
	if _cache.has(file_name):
		return _cache[file_name]
	var path := "%s/%s" % [DIRECTORY, file_name]
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_cache[file_name] = texture
	return texture


## Roughly what the portfolio is costing on disk, for the office panel.
func used_bytes() -> int:
	var total := 0
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var file := FileAccess.open("%s/%s" % [DIRECTORY, file_name], FileAccess.READ)
			if file != null:
				total += file.get_length()
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()
	return total


func _today() -> int:
	var clock := get_node_or_null(^"/root/WorldClock")
	return int(clock.call(&"day_index")) if clock != null else 0


# =============================================================== persistence

func to_save_dict() -> Dictionary:
	var out: Array = []
	for entry in _entries:
		out.append(entry.duplicate())
	return {"entries": out, "next_index": _next_index}


## A save with no portfolio section was played before there was one, which means
## there are no photographs of it and there is nothing to migrate. Any image
## file it names that has since been deleted degrades to a blank frame.
func from_save_dict(data: Dictionary) -> void:
	_entries.clear()
	_pending.clear()
	_cache.clear()
	for entry: Variant in data.get("entries", []):
		if not (entry is Dictionary):
			continue
		var record: Dictionary = (entry as Dictionary).duplicate()
		for key in ["index", "seed", "property_type", "region", "day", "payout",
				"stars", "stage"]:
			if record.has(key):
				record[key] = int(record[key])
		record["featured"] = bool(record.get("featured", false))
		record["completion"] = float(record.get("completion", 0.0))
		_entries.append(record)
	_next_index = maxi(int(data.get("next_index", 1)), _highest_index() + 1)
	entries_changed.emit()


func _highest_index() -> int:
	var highest := 0
	for entry in _entries:
		highest = maxi(highest, int(entry.get("index", 0)))
	return highest
