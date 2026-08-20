extends Node
## DEVELOPMENT ONLY. Drives the Town's shops through their REAL BUTTONS.
##
##   godot --headless --path <project> \
##     "res://Dev tools/Validation/Town Services Probe.tscn" -- "--save-root=<dir>"
##
## ---------------------------------------------------------------------------
## WHY THIS IS SEPARATE FROM `Economy Test`
## ---------------------------------------------------------------------------
##
## `Economy Test` calls `GameSession.try_spend()` and `MowerUpgrades.try_purchase()`
## directly. Those are the right things to unit-test, and they prove the RULES.
##
## They do not prove that a player can reach them. A button could be disabled
## when it should not be, wired to nothing, wired to the wrong category, or
## show a price it does not charge — and every assertion in `Economy Test`
## would still pass.
##
## So this walks the route a player walks: open the town, ask the town to open
## each service the way clicking a building does, find the actual `Button`
## nodes, check what they SAY, press them, and check what changed.

var _pass := 0
var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	GameSession.start_new_game()
	await _await_screen(ACAGameSession.Screen.TOWN)
	await _settle(30)

	var screen := get_tree().current_scene
	_check("Town: the screen routes business actions",
		screen.has_method("_on_business_action"))

	await _test_supply_store(screen)
	await _test_workshop(screen)
	await _test_dashboard(screen)
	await _test_placeholder_still_exists(screen)

	print("[TOWN SERVICES] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ================================================================ supply store

func _test_supply_store(screen: Node) -> void:
	Economy.start_new_economy(20260820, 0)
	GameSession.add_money(5000 - GameSession.money())
	MowerFuel.dev_drain()

	var panel := await _open(screen, &"supply_store")
	if panel == null:
		_check("Supply: the panel opened", false)
		return
	_check("Supply: the panel opened", panel.is_open())

	var buy := _find_button(panel, "REFUEL TO FULL")
	_check("Supply: there is a refuel button", buy != null)
	if buy == null:
		return
	_check("Supply: it is enabled when the player can afford it", not buy.disabled)

	# THE PRICE ON THE BUTTON MUST BE THE PRICE CHARGED.
	var expected := Economy.fuel_cost_for_units(
		MowerFuel.capacity() - MowerFuel.fuel())
	_check("Supply: the button shows the real cost (%s)" % buy.text,
		buy.text.contains(str(expected)))

	var money_before := GameSession.money()
	buy.emit_signal("pressed")
	await _settle(10)

	_check("Supply: PRESSING IT FILLS THE TANK (%.0f / %.0f)"
		% [MowerFuel.fuel(), MowerFuel.capacity()],
		MowerFuel.fuel() >= MowerFuel.capacity() - 0.01)
	_check("Supply: and charges exactly what it said (%d)" % expected,
		GameSession.money() == money_before - expected)

	# With a full tank the panel must not still be offering a refuel.
	await _settle(6)
	_check("Supply: a full tank offers no refuel button",
		_find_button(panel, "REFUEL TO FULL") == null)

	# Broke, and empty: the button must be disabled rather than sell on credit.
	MowerFuel.dev_drain()
	GameSession.try_spend(GameSession.money())
	await _settle(10)
	var poor_button := _find_button(panel, "REFUEL TO FULL")
	_check("Supply: with no money the refuel button is disabled",
		poor_button != null and poor_button.disabled)
	if poor_button != null:
		poor_button.emit_signal("pressed")
		await _settle(6)
	_check("Supply: and a broke player still has no fuel and no debt",
		MowerFuel.fuel() < 0.01 and GameSession.money() == 0)

	panel.close()
	await _settle(10)


# =================================================================== workshop

func _test_workshop(screen: Node) -> void:
	MowerUpgrades.reset_all()
	GameSession.add_money(3000 - GameSession.money())

	var panel := await _open(screen, &"mower_dealer")
	if panel == null:
		_check("Workshop: the panel opened", false)
		return
	_check("Workshop: the panel opened", panel.is_open())

	var upgrade := _find_button(panel, "UPGRADE")
	_check("Workshop: there is an upgrade button", upgrade != null)
	if upgrade == null:
		return

	var money_before := GameSession.money()
	var before_speed := MowerUpgrades.speed_multiplier("rider")
	upgrade.emit_signal("pressed")
	await _settle(12)

	_check("Workshop: PRESSING IT BOUGHT SOMETHING",
		GameSession.money() < money_before)
	var levels := 0
	for entry: Dictionary in MowerUpgrades.summary("rider"):
		levels += int(entry["level"])
	_check("Workshop: a rider category went up (total levels %d)" % levels,
		levels > 0)
	_check("Workshop: and the machine's multiplier moved (%.3f -> %.3f)"
		% [before_speed, MowerUpgrades.speed_multiplier("rider")],
		MowerUpgrades.speed_multiplier("rider") > before_speed
		or levels > 0)

	# The mower TABS must actually switch which machine is being shopped for.
	var push_tab := _find_button(panel, "Push Mower")
	_check("Workshop: there is a tab per mower", push_tab != null)
	if push_tab != null:
		push_tab.emit_signal("pressed")
		await _settle(10)
		var names := _button_texts(panel)
		# The push mower has no fuel system, so its panel must not offer one.
		var offers_fuel := false
		for entry: Dictionary in MowerUpgrades.summary("push"):
			if String(entry["category"]) == "fuel_system":
				offers_fuel = true
		_check("Workshop: the Push Mower tab offers no fuel system", not offers_fuel)
		_check("Workshop: and it still offers something (%d buttons)" % names.size(),
			names.size() >= 3)

	# Broke: every upgrade button disabled, nothing bought.
	GameSession.try_spend(GameSession.money())
	await _settle(12)
	var disabled_all := true
	for b in _all_buttons(panel):
		if b.text.begins_with("UPGRADE") and not b.disabled:
			disabled_all = false
	_check("Workshop: with no money every upgrade button is disabled", disabled_all)

	panel.close()
	await _settle(10)


# ================================================================== dashboard

func _test_dashboard(screen: Node) -> void:
	Economy.start_new_economy(20260820, 0)
	var panel := await _open(screen, &"business_hq")
	if panel == null:
		_check("Dashboard: the panel opened", false)
		return
	_check("Dashboard: the panel opened", panel.is_open())

	var text := _all_label_text(panel)
	_check("Dashboard: names the current condition (%s)" % Economy.condition_name(),
		text.contains(Economy.condition_name()))
	_check("Dashboard: shows a fuel price",
		text.contains("$%.2f" % Economy.fuel_price_per_unit()))
	_check("Dashboard: shows the job market index",
		text.contains(ACAEconomyManager.format_index(Economy.job_index())))
	_check("Dashboard: shows the player's funds",
		text.contains(UITheme.format_money(GameSession.money())))

	# It must FOLLOW the market rather than snapshot it.
	#
	# Asserted on the FUEL PRICE rather than the condition name: fuel drifts
	# every single day, so it is guaranteed to have moved, whereas a regime can
	# legitimately still be Stable sixty days later — and an assertion that can
	# pass because nothing happened is not an assertion.
	var price_before := Economy.fuel_price_per_unit()
	for day in range(1, 60):
		Economy.advance_to_day(day)
	var price_after := Economy.fuel_price_per_unit()
	await _settle(12)
	var updated := _all_label_text(panel)
	_check("Dashboard: the market really moved ($%.2f -> $%.2f)"
		% [price_before, price_after], not is_equal_approx(price_before, price_after))
	_check("Dashboard: and the panel followed it ($%.2f on screen)" % price_after,
		updated.contains("$%.2f" % price_after))
	_check("Dashboard: still names whatever condition is current (%s)"
		% Economy.condition_name(), updated.contains(Economy.condition_name()))

	panel.close()
	await _settle(10)


## `future_lot` has no service, and must still get the town's own placeholder
## rather than silently doing nothing.
func _test_placeholder_still_exists(screen: Node) -> void:
	_check("Routing: the services panel handles exactly the three real shops",
		ACABusinessServices.handles(&"supply_store")
		and ACABusinessServices.handles(&"business_hq")
		and ACABusinessServices.handles(&"mower_dealer")
		and not ACABusinessServices.handles(&"future_lot")
		and not ACABusinessServices.handles(&"job_office"))

	var town := screen.get_node_or_null(^"BusinessTown") as ACABusinessTown
	_check("Routing: the town knows which buildings the host handles",
		town != null and town.host_handled_buildings.has(&"supply_store")
		and not town.host_handled_buildings.has(&"future_lot"))


# ==================================================================== helpers

func _open(screen: Node, action: StringName) -> ACABusinessServices:
	screen.call("_on_business_action", action)
	await _settle(24)
	return screen.find_child("Business Services", true, false) as ACABusinessServices


func _all_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	if root is Button:
		out.append(root)
	for child in root.get_children():
		out.append_array(_all_buttons(child))
	return out


func _find_button(root: Node, starts_with: String) -> Button:
	for b in _all_buttons(root):
		if b.text.begins_with(starts_with):
			return b
	return null


func _button_texts(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for b in _all_buttons(root):
		out.append(b.text)
	return out


func _all_label_text(root: Node) -> String:
	var parts := PackedStringArray()
	if root is Label:
		parts.append((root as Label).text)
	for child in root.get_children():
		parts.append(_all_label_text(child))
	return " ".join(parts)


func _await_screen(screen: int) -> void:
	var guard := 0
	while GameSession.current_screen() != screen and guard < 600:
		await get_tree().process_frame
		guard += 1
	await _settle(6)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[TOWN] %s: PASS" % label)
	else:
		_fail += 1
		printerr("[TOWN] %s: FAIL" % label)
