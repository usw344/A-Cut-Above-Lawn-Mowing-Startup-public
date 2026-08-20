class_name ACAMowerUpgrades
extends Node
## PER-MOWER UPGRADE STATE. Autoloaded as `MowerUpgrades`.
##
## Owns which upgrades each mower has bought, what they cost, and what they DO.
## It does not own money (`GameSession` does), the market (`Economy` does), or
## any UI.
##
## ---------------------------------------------------------------------------
## MOWER IDS
## ---------------------------------------------------------------------------
##
## `rider`, `powered`, `push` — the keys `MVP.mowers_scene_list` already uses
## and `model.current_mower` already saves. They are NOT scene paths, so moving
## a mower scene cannot invalidate a save.
##
## ---------------------------------------------------------------------------
## NO FAKE UPGRADES
## ---------------------------------------------------------------------------
##
## Every category below changes a number a controller actually reads:
##
##   speed     -> the mower's velocity, through `speed_multiplier()`
##   fuel      -> `MowerFuel.consume()`, through `fuel_multiplier()`
##   handling  -> `mouse_yaw_smoothing`, through `handling_multiplier()`
##
## CUT WIDTH IS DELIBERATELY ABSENT. The mowing grid cuts whatever the mower's
## CharacterBody3D physically touched (`custom_grid_map_collision_handler` reads
## `get_slide_collision()`), so widening the cut means widening the body's
## collision shape — which changes how the machine collides with the world, not
## just how much grass it takes. That is a physics change wearing an upgrade's
## clothes. It is recorded as future work rather than faked.
##
## THE PUSH MOWER HAS TWO CATEGORIES, NOT THREE. It burns no fuel, so it has no
## fuel system to improve. That is the machine being simpler, not the system
## being incomplete.

signal upgrade_purchased(mower_id: StringName, category: StringName, level: int)
signal upgrades_changed()

const MOWER_IDS: PackedStringArray = ["rider", "powered", "push"]

## Display names, so UI never has to hard-code them.
const MOWER_NAMES := {
	"rider": "Riding Mower",
	"powered": "Powered Walk-Behind",
	"push": "Push Mower",
}

## `effect_at_level` is the multiplier AT each level, index 0 being stock.
## Levels are therefore `values.size() - 1` deep.
##
## `base_cost` is what level 1 costs before the market; each further level
## multiplies by `cost_growth`. The market index is applied on top by `Economy`.
const CATEGORIES := {
	"drive": {
		"name": "Engine & Drive",
		"blurb": "More power to the wheels. The machine covers ground faster.",
		"stat": "speed",
		"applies_to": ["rider", "powered"],
		"values": [1.00, 1.09, 1.18, 1.26, 1.33],
		"base_cost": 180,
		"cost_growth": 1.55,
		"unit": "speed",
	},
	"fuel_system": {
		"name": "Fuel System",
		"blurb": "Cleaner burn. The same tank lasts noticeably longer.",
		"stat": "fuel",
		"applies_to": ["rider", "powered"],
		# LOWER is better here: this multiplies the burn rate.
		"values": [1.00, 0.91, 0.83, 0.76, 0.70],
		"base_cost": 150,
		"cost_growth": 1.55,
		"unit": "fuel use",
	},
	"steering": {
		"name": "Steering",
		"blurb": "Tighter response. The mower goes where it is pointed sooner.",
		"stat": "handling",
		"applies_to": ["rider", "powered"],
		"values": [1.00, 1.12, 1.24, 1.36, 1.48],
		"base_cost": 120,
		"cost_growth": 1.45,
		"unit": "response",
	},
	"frame": {
		"name": "Lightweight Frame",
		"blurb": "Less machine to push. Easier to keep moving.",
		"stat": "speed",
		"applies_to": ["push"],
		"values": [1.00, 1.08, 1.16, 1.23, 1.29],
		"base_cost": 90,
		"cost_growth": 1.45,
		"unit": "speed",
	},
	"bearings": {
		"name": "Bearing Kit",
		"blurb": "Smoother wheels and a truer line through a turn.",
		"stat": "handling",
		"applies_to": ["push"],
		"values": [1.00, 1.13, 1.26, 1.38, 1.50],
		"base_cost": 70,
		"cost_growth": 1.40,
		"unit": "response",
	},
}

# --------------------------------------------------------------------- state
## `{ mower_id: { category: level } }`. Absent means level 0.
var _levels: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)


# =================================================================== querying

static func is_valid_mower(mower_id: String) -> bool:
	return MOWER_IDS.has(mower_id)


static func mower_name(mower_id: String) -> String:
	return String(MOWER_NAMES.get(mower_id, mower_id.capitalize()))


## Category ids available for this mower, in display order.
static func categories_for(mower_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in CATEGORIES:
		var applies: Array = CATEGORIES[key]["applies_to"]
		if applies.has(mower_id):
			out.append(key)
	return out


static func max_level(category: String) -> int:
	var spec: Dictionary = CATEGORIES.get(category, {})
	if spec.is_empty():
		return 0
	return (spec["values"] as Array).size() - 1


func level(mower_id: String, category: String) -> int:
	var per_mower: Dictionary = _levels.get(mower_id, {})
	return clampi(int(per_mower.get(category, 0)), 0, max_level(category))


func is_maxed(mower_id: String, category: String) -> bool:
	return level(mower_id, category) >= max_level(category)


## The multiplier this mower currently has for `category`.
func value(mower_id: String, category: String) -> float:
	var spec: Dictionary = CATEGORIES.get(category, {})
	if spec.is_empty():
		return 1.0
	var values: Array = spec["values"]
	return float(values[clampi(level(mower_id, category), 0, values.size() - 1)])


## The multiplier at a hypothetical level, for "next level" UI.
static func value_at(category: String, at_level: int) -> float:
	var spec: Dictionary = CATEGORIES.get(category, {})
	if spec.is_empty():
		return 1.0
	var values: Array = spec["values"]
	return float(values[clampi(at_level, 0, values.size() - 1)])


# ------------------------------------------------------- the gameplay stats
#
# THESE are what the mower controllers call. One question per stat, so a
# controller never has to know which categories exist.

func _stat_multiplier(mower_id: String, stat: String) -> float:
	var total := 1.0
	for key: String in CATEGORIES:
		var spec: Dictionary = CATEGORIES[key]
		if spec["stat"] != stat:
			continue
		if not (spec["applies_to"] as Array).has(mower_id):
			continue
		total *= value(mower_id, key)
	return total


## Scales how fast the mower moves. 1.0 is the authored value.
func speed_multiplier(mower_id: String) -> float:
	return _stat_multiplier(mower_id, "speed")


## Scales `MowerFuel` burn. BELOW 1.0 is an improvement.
func fuel_multiplier(mower_id: String) -> float:
	return _stat_multiplier(mower_id, "fuel")


## Scales steering responsiveness (the exponential approach rate on body yaw).
func handling_multiplier(mower_id: String) -> float:
	return _stat_multiplier(mower_id, "handling")


# ==================================================================== pricing

## What level `target_level` costs BEFORE the market. Deterministic.
static func base_cost(category: String, target_level: int) -> int:
	var spec: Dictionary = CATEGORIES.get(category, {})
	if spec.is_empty() or target_level <= 0:
		return 0
	var cost := float(spec["base_cost"])
	for i in range(target_level - 1):
		cost *= float(spec["cost_growth"])
	return int(round(cost))


## What the NEXT level costs right now, with the market applied. Returns -1 when
## the category is already maxed, so callers cannot show a price for nothing.
func next_cost(mower_id: String, category: String) -> int:
	if is_maxed(mower_id, category):
		return -1
	var raw := base_cost(category, level(mower_id, category) + 1)
	var economy := get_node_or_null(^"/root/Economy")
	if economy == null:
		return raw
	return economy.equipment_price(raw)


# =================================================================== buying

## Attempt to buy the next level. Returns true only if the money was actually
## taken and the level actually went up.
##
## The money lives in `GameSession` — this never keeps a balance of its own, so
## there is no second wallet to drift out of step.
func try_purchase(mower_id: String, category: String) -> bool:
	if not is_valid_mower(mower_id):
		return false
	if not CATEGORIES.has(category):
		return false
	if not (CATEGORIES[category]["applies_to"] as Array).has(mower_id):
		return false
	if is_maxed(mower_id, category):
		return false

	var cost := next_cost(mower_id, category)
	if cost < 0:
		return false
	var session := get_node_or_null(^"/root/GameSession")
	if session == null:
		return false
	if not session.try_spend(cost):
		return false

	var per_mower: Dictionary = _levels.get(mower_id, {})
	per_mower[category] = level(mower_id, category) + 1
	_levels[mower_id] = per_mower

	upgrade_purchased.emit(StringName(mower_id), StringName(category),
		int(per_mower[category]))
	upgrades_changed.emit()
	return true


## Development helper. Sets a level with no payment; never called by gameplay.
func dev_set_level(mower_id: String, category: String, new_level: int) -> void:
	if not CATEGORIES.has(category) or not is_valid_mower(mower_id):
		return
	var per_mower: Dictionary = _levels.get(mower_id, {})
	per_mower[category] = clampi(new_level, 0, max_level(category))
	_levels[mower_id] = per_mower
	upgrades_changed.emit()


func reset_all() -> void:
	_levels = {}
	upgrades_changed.emit()


## Everything a shop panel needs for one mower.
func summary(mower_id: String) -> Array:
	var out: Array = []
	for key: String in categories_for(mower_id):
		var spec: Dictionary = CATEGORIES[key]
		var lvl := level(mower_id, key)
		out.append({
			"category": key,
			"name": String(spec["name"]),
			"blurb": String(spec["blurb"]),
			"stat": String(spec["stat"]),
			"unit": String(spec["unit"]),
			"level": lvl,
			"max_level": max_level(key),
			"value": value(mower_id, key),
			"next_value": value_at(key, lvl + 1),
			"next_cost": next_cost(mower_id, key),
			"maxed": is_maxed(mower_id, key),
		})
	return out


# =============================================================== persistence

func to_save_dict() -> Dictionary:
	# Copied out rather than handed over, so a save cannot alias live state.
	var out := {}
	for mower_id: String in _levels:
		var per_mower: Dictionary = _levels[mower_id]
		var clean := {}
		for category: String in per_mower:
			clean[category] = int(per_mower[category])
		out[mower_id] = clean
	return {"levels": out}


## Unknown mower ids and unknown categories are DROPPED rather than kept: a
## level for something this build no longer has would otherwise sit in the save
## file forever, and could silently reappear if the name were reused.
func from_save_dict(data: Dictionary) -> void:
	_levels = {}
	var raw: Dictionary = data.get("levels", {})
	for mower_id: Variant in raw:
		var id := String(mower_id)
		if not is_valid_mower(id):
			continue
		var per_mower: Dictionary = raw[mower_id]
		var clean := {}
		for category: Variant in per_mower:
			var cat := String(category)
			if not CATEGORIES.has(cat):
				continue
			if not (CATEGORIES[cat]["applies_to"] as Array).has(id):
				continue
			clean[cat] = clampi(int(per_mower[category]), 0, max_level(cat))
		if not clean.is_empty():
			_levels[id] = clean
	upgrades_changed.emit()
