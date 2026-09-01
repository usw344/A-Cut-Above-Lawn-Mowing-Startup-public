class_name ACASaveService
extends Node
## THE save/load system. Autoloaded as `SaveService`.
##
## It is the only thing that touches save files. It owns no game state: it asks
## each owning system for a dictionary and hands one back on load.
##
##     SaveService
##       WorldClock.to_save_dict()   / from_save_dict()
##       JobManager.save_state()     / load_state()
##       GameSession.to_save_dict()  / from_save_dict()
##       GameSettings.to_save_dict() / from_save_dict()   (separate file)
##       model                       (read directly - Model.gd has no save API)
##       ACAProperty.params() + ACALawn.cut_state()   (the mowing block)
##
## See project-docs/systems/save-and-load.md for the full schema.

signal game_saved(slot_name: String)
signal game_loaded(slot_name: String)
signal save_failed(reason: String)
signal load_failed(reason: String)

const SAVE_FORMAT_VERSION := 1

const DEFAULT_ROOT := "user://saves"
const DEFAULT_SLOT := "slot1"
const EXTENSION := ".json"
const BACKUP_SUFFIX := ".bak"
const TEMP_SUFFIX := ".tmp"
const SETTINGS_FILE := "settings.json"

## Development/test override, e.g.
##   godot --headless --path . <scene> -- "--save-root=D:/dir/saves"
## Production leaves it unset and uses DEFAULT_ROOT.
const ROOT_OVERRIDE_ARG := "--save-root="

var _root: String = DEFAULT_ROOT
## One-shot handoff to the mowing scene after a load. Cleared when taken, so a
## later visit to the same job never re-applies a stale grid.
var _pending_mowing: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = _resolve_root()
	DirAccess.make_dir_recursive_absolute(_root)
	load_settings()


func _resolve_root() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with(ROOT_OVERRIDE_ARG):
			var value := arg.substr(ROOT_OVERRIDE_ARG.length()).strip_edges()
			if not value.is_empty():
				return value
	return DEFAULT_ROOT


func storage_root() -> String:
	return _root


# ==================================================================== listing

func _slot_path(slot_name: String) -> String:
	return "%s/%s%s" % [_root, slot_name, EXTENSION]


func has_any_save() -> bool:
	return not list_saves().is_empty()


## Newest first. Each entry: slot, path, saved_at_unix, saved_at_text, day,
## money, valid.
func list_saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(_root)
	if dir == null:
		return out

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() \
				and file_name.ends_with(EXTENSION) \
				and file_name != SETTINGS_FILE:
			out.append(_describe(file_name.trim_suffix(EXTENSION)))
		file_name = dir.get_next()
	dir.list_dir_end()

	out.sort_custom(func(a, b): return a["saved_at_unix"] > b["saved_at_unix"])
	return out


func _describe(slot_name: String) -> Dictionary:
	var info := {
		"slot": slot_name,
		"path": _slot_path(slot_name),
		"saved_at_unix": 0,
		"saved_at_text": "",
		"day": 0,
		"money": 0,
		"valid": false,
	}
	var data := _read_json(_slot_path(slot_name))
	if data.is_empty():
		return info
	info["saved_at_unix"] = int(data.get("saved_at_unix", 0))
	info["saved_at_text"] = String(data.get("saved_at_text", ""))
	info["money"] = int(data.get("profile", {}).get("money", 0))
	var minutes := float(data.get("world", {}).get("minutes", 0.0))
	info["day"] = ACAGameTime.day_index(minutes) + 1
	info["valid"] = int(data.get("save_format_version", 0)) == SAVE_FORMAT_VERSION
	return info


# ====================================================================== saving

## Write the current session. Returns false and emits save_failed on any problem.
func save_game(slot_name: String = "") -> bool:
	if slot_name.is_empty():
		slot_name = DEFAULT_SLOT

	var screen := GameSession.current_screen()
	if screen != ACAGameSession.Screen.TOWN and screen != ACAGameSession.Screen.MOWING:
		return _fail_save("There is nothing to save from this screen.")

	# Mid-transition, current_screen() has already advanced but current_scene is
	# still the old one, so the mowing block would be collected from the wrong
	# scene. Refuse rather than write something subtly wrong.
	if GameSession.is_changing_scene():
		return _fail_save("Cannot save while the game is changing scene.")

	var data := _collect()
	var text := JSON.stringify(data, "\t")

	var final_path := _slot_path(slot_name)
	var temp_path := final_path + TEMP_SUFFIX
	var backup_path := final_path + BACKUP_SUFFIX

	# Temp-then-replace: an interrupted write cannot destroy the previous save.
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail_save("Could not open %s (error %d)"
			% [temp_path, FileAccess.get_open_error()])
	file.store_string(text)
	file.close()

	# Read the temp file back and parse it before it is allowed to replace a
	# good save. A truncated or partially flushed write is caught here, while
	# the previous save is still intact.
	if _read_json(temp_path).is_empty():
		DirAccess.remove_absolute(temp_path)
		return _fail_save("Wrote %s but could not read it back; the previous save was kept."
			% temp_path)

	if FileAccess.file_exists(final_path):
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		DirAccess.copy_absolute(final_path, backup_path)
		DirAccess.remove_absolute(final_path)

	var err := DirAccess.rename_absolute(temp_path, final_path)
	if err != OK:
		return _fail_save("Could not finalise %s (error %d)" % [final_path, err])

	game_saved.emit(slot_name)
	return true


func _collect() -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var data := {
		"save_format_version": SAVE_FORMAT_VERSION,
		"saved_at_unix": int(now),
		"saved_at_text": Time.get_datetime_string_from_unix_time(int(now), true),
		"slot_name": DEFAULT_SLOT,
		"profile": {
			"profile_name": "Player",
			"money": GameSession.money(),
		},
		"world": WorldClock.to_save_dict(),
		"jobs": JobManager.save_state(),
		"session": GameSession.to_save_dict(),
		"mower": _collect_mower(),
		"economy": Economy.to_save_dict(),
		"upgrades": MowerUpgrades.to_save_dict(),
		# THREE MORE ADDITIVE SECTIONS, and no save-format version bump. Each one
		# holds state that genuinely cannot be reconstructed - what the business
		# owns, what is in the yard, and what the town thinks of it - and each
		# one has a defined meaning when it is absent. See `_apply_business()`.
		"equipment": Equipment.to_save_dict(),
		"clippings": Clippings.to_save_dict(),
		"business": Business.to_save_dict(),
		# THREE MORE, on the same terms and again with no version bump: where the
		# business is allowed to work, what long-term agreements it has signed,
		# and the metadata of its portfolio. Every one of them has a defined
		# meaning when it is absent - see `_apply_expansion()`.
		#
		# THE PORTFOLIO'S IMAGES ARE NOT IN HERE and never will be. This section
		# carries file NAMES; the JPEGs live under `user://portfolio/`.
		"territory": Territory.to_save_dict(),
		"agreements": Agreements.to_save_dict(),
		"portfolio": Portfolio.to_save_dict(),
	}

	if GameSession.current_screen() == ACAGameSession.Screen.MOWING:
		var mowing := _collect_mowing()
		if not mowing.is_empty():
			data["mowing"] = mowing
	return data


## Model.gd has no save API of its own, so the durable fields are read directly.
func _collect_mower() -> Dictionary:
	return {
		"current_mower": model.current_mower,
		"speed": model.get_speed(),
		"blade_length": model.get_blade_length(),
		"mower_fuel": model.get_mower_fuel(),
		"mower_fuel_idle_counter": model.get_mower_fuel_idle_counter(),
		"idle_fuel_use": model.get_idle_fuel_use(),
		"stored_cuttings": model.get_stored_cuttings(),
		"cuttings_in_mower": model.get_cuttings_in_mower(),
	}


## The mowing block: which property, and how much of it is cut.
##
## Neither is stored as geometry. The property is its parameters, and the cut is
## a bitset - so a Large lawn mid-contract costs a few kilobytes rather than
## tens of thousands of coordinate strings, and reloading rebuilds the same
## ground rather than restoring a copy of it.
func _collect_mowing() -> Dictionary:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method(&"lawn"):
		return {}
	var lawn: ACALawn = scene.call(&"lawn")
	var property: ACAProperty = scene.call(&"property") \
		if scene.has_method(&"property") else null
	if lawn == null or property == null:
		return {}

	var job := GameSession.current_job()
	var out := {
		"job_id": String(job.id) if job != null else "",
		"lawn_size": lawn.cell_count(),
		"property": property.params().to_dictionary(),
		"cut_state": lawn.cut_state(),
	}

	var mower := scene.get(&"current_mower") as Node3D
	if mower != null:
		var p := mower.global_position
		var r := mower.rotation
		out["mower_position"] = [p.x, p.y, p.z]
		out["mower_rotation"] = [r.x, r.y, r.z]
	return out


# ===================================================================== loading

func load_most_recent() -> bool:
	var saves := list_saves()
	if saves.is_empty():
		return _fail_load("No saved games found.")
	return load_game(String(saves[0]["slot"]))


## Restore a save and route the application to where the player left off.
func load_game(slot_name: String) -> bool:
	var path := _slot_path(slot_name)
	var data := _read_json(path)

	if data.is_empty():
		# Fall back to the previous version before giving up.
		data = _read_json(path + BACKUP_SUFFIX)
		if data.is_empty():
			return _fail_load("Save '%s' could not be read." % slot_name)
		push_warning("SaveService: fell back to the backup for slot '%s'." % slot_name)

	var version := int(data.get("save_format_version", 0))
	if version != SAVE_FORMAT_VERSION:
		return _fail_load("Save '%s' is format version %d; this build reads version %d."
			% [slot_name, version, SAVE_FORMAT_VERSION])

	for section in ["world", "jobs", "session"]:
		if not data.has(section):
			return _fail_load("Save '%s' is missing its '%s' section." % [slot_name, section])

	# Order matters: the clock first, so the job manager re-anchors its arrival
	# time against the restored world time rather than the old one.
	WorldClock.from_save_dict(data["world"])
	JobManager.load_state(data["jobs"])
	GameSession.from_save_dict(data["session"])
	_apply_mower(data.get("mower", {}))
	_apply_economy(data)
	_apply_business(data)

	var screen := int(data.get("session", {}).get("screen", ACAGameSession.Screen.TOWN))
	_pending_mowing = {}

	# Only resume into gameplay if there is still a contract to resume into.
	if screen == ACAGameSession.Screen.MOWING and GameSession.has_active_job():
		var mowing: Variant = data.get("mowing", {})
		if mowing is Dictionary:
			_pending_mowing = (mowing as Dictionary).duplicate(true)
		GameSession.mark_session_active(true)
		GameSession.go_to_mowing()
	else:
		GameSession.mark_session_active(true)
		GameSession.go_to_town()

	game_loaded.emit(slot_name)
	return true


## ECONOMY AND UPGRADES. Both sections are OPTIONAL: a save written before they
## existed loads perfectly, and gets a fresh market anchored to its own day
## rather than a market that has been running since the epoch.
##
## Nothing here rerolls. `Economy.from_save_dict()` restores the exact condition,
## event and drift the player left, and `advance_to_day()` is NOT called — the
## clock's own `day_changed` will do that when the world next moves.
func _apply_economy(data: Dictionary) -> void:
	if data.has("economy"):
		Economy.from_save_dict(data["economy"])
	else:
		Economy.initialise_for_legacy_save(WorldClock.day_index())
	MowerUpgrades.from_save_dict(data.get("upgrades", {}))


## EQUIPMENT, CLIPPINGS AND THE COMPANY. All three sections are OPTIONAL.
##
## A save written before any of them existed is not broken and is not migrated
## with invented history:
##
##   EQUIPMENT  the business owns the Rider it has always driven, plus anything
##              it had plainly bought - see `ACAEquipment.from_save_dict()`.
##              THE UPGRADES MUST BE RESTORED FIRST, because that is the
##              evidence ownership is inferred from.
##   CLIPPINGS  an empty yard and an empty bag. There was nothing to lose,
##              because nothing was collecting anything.
##   BUSINESS   a company with no reviews and no customers on its books. Its
##              completed contracts are deliberately NOT converted into
##              reputation: they were played before there were terms to judge
##              them against, and scoring them now would be inventing a history.
func _apply_business(data: Dictionary) -> void:
	Equipment.from_save_dict(data.get("equipment", {}), MowerUpgrades)
	Clippings.from_save_dict(data.get("clippings", {}))
	Business.from_save_dict(data.get("business", {}))
	_apply_expansion(data)


## TERRITORY, AGREEMENTS AND THE PORTFOLIO. All three sections are OPTIONAL, and
## a save that predates them is not broken and is not migrated with invented
## history:
##
##   TERRITORY   the business owns its Home Town and has bought no service lot,
##               which is exactly true - there were none to buy. Its accepted
##               contracts are untouched wherever they are; what changes is that
##               its NEXT arrivals are local until it expands.
##   AGREEMENTS  none. Nobody offered that business a service agreement.
##   PORTFOLIO   no photographs, because nothing was taking any. An entry whose
##               image file has since been deleted from `user://` degrades to a
##               blank frame rather than to a failed load.
##
## The active REGION is read from the session block rather than from the
## territory block, because which screen the player was on is session state.
func _apply_expansion(data: Dictionary) -> void:
	Territory.from_save_dict(data.get("territory", {}))
	Agreements.from_save_dict(data.get("agreements", {}))
	Portfolio.from_save_dict(data.get("portfolio", {}))
	var region := ACAServiceTerritory.region_from_id(
		StringName(String(data.get("session", {}).get("region", ""))))
	if region >= 0:
		Territory.set_active_region(region)


func _apply_mower(data: Dictionary) -> void:
	if data.is_empty():
		return
	model.current_mower = String(data.get("current_mower", model.current_mower))
	model.set_speed(data.get("speed", model.get_speed()))
	model.set_blade_length(data.get("blade_length", model.get_blade_length()))
	model.set_mower_fuel(data.get("mower_fuel", model.get_mower_fuel()))
	model.set_mower_fuel_idle_counter(
		data.get("mower_fuel_idle_counter", model.get_mower_fuel_idle_counter()))
	model.set_idle_fuel_use(data.get("idle_fuel_use", model.get_idle_fuel_use()))
	model.set_stored_cuttings(int(data.get("stored_cuttings", model.get_stored_cuttings())))
	model.set_cuttings_in_mower(int(data.get("cuttings_in_mower", model.get_cuttings_in_mower())))


## ONE-SHOT. The mowing scene calls this after building its grid. Returns an
## empty dictionary when there is nothing to restore, and clears itself so a
## later visit to the same job cannot re-apply stale state.
func take_pending_mowing_state() -> Dictionary:
	var out := _pending_mowing
	_pending_mowing = {}
	return out


func has_pending_mowing_state() -> bool:
	return not _pending_mowing.is_empty()


# ==================================================================== deleting

func delete_save(slot_name: String) -> bool:
	var path := _slot_path(slot_name)
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + BACKUP_SUFFIX):
		DirAccess.remove_absolute(path + BACKUP_SUFFIX)
	return true


# ==================================================================== settings
## Settings are a property of the installation, not of a save, so they live in
## their own file in the same storage root.

func save_settings() -> bool:
	var path := "%s/%s" % [_root, SETTINGS_FILE]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveService: could not write settings to %s" % path)
		return false
	file.store_string(JSON.stringify(GameSettings.to_save_dict(), "\t"))
	file.close()
	return true


func load_settings() -> bool:
	var data := _read_json("%s/%s" % [_root, SETTINGS_FILE])
	if data.is_empty():
		return false
	GameSettings.from_save_dict(data)
	return true


# ===================================================================== helpers

## Returns an empty dictionary for any failure - missing file, unreadable file,
## invalid JSON, or JSON whose root is not an object. Never throws.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveService: could not open %s (error %d)"
			% [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("SaveService: %s is not valid save JSON." % path)
	return {}


func _fail_save(reason: String) -> bool:
	push_error("SaveService (save): %s" % reason)
	save_failed.emit(reason)
	return false


func _fail_load(reason: String) -> bool:
	push_error("SaveService (load): %s" % reason)
	load_failed.emit(reason)
	return false
