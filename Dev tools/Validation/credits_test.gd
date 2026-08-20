extends Node
## DEVELOPMENT ONLY. The data-driven Credits system.
##
##   godot --headless --path <project> "res://Dev tools/Validation/Credits Test.tscn"
##
## Two halves:
##
##   1. The LOADER, tested against a throwaway folder this test writes and
##      deletes under `user://`. It never edits a real licence file - a test
##      must not be a reason to touch attribution text.
##   2. The REAL folder and the REAL screen: `res://Credits` scans, the Main
##      Menu opens the Credits screen, long text is present and scrollable, and
##      BACK returns.

const TEST_DIR := "user://credits_test_fixture"
const LONG_MARKER := "END OF A DELIBERATELY LONG FIXTURE"

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n=============== CREDITS TEST ===============")

	await _step()
	_test_loader_against_fixture()
	_test_real_folder()
	await _test_screen_from_main_menu()

	print("============================================")
	print("[CREDITS TEST] %d passed, %d failed" % [_passes, _failures])
	print("============================================\n")
	_remove_fixture()
	get_tree().quit(0 if _failures == 0 else 1)


# ============================================================ 1. the loader

func _test_loader_against_fixture() -> void:
	_build_fixture()

	var entries := ACACreditsLoader.list_entries(TEST_DIR)
	var titles := PackedStringArray()
	for entry in entries:
		titles.append(String(entry["title"]))

	_check("Loader: scans the configured folder", not entries.is_empty())

	# 1. the project convention
	_check("Loader: finds <Name>_licence.txt", titles.has("Sky3D"))
	# 2. underscores become spaces
	_check("Loader: derives a multi-word title", titles.has("Kenney Assets"))
	# 3. the tolerated spellings
	_check("Loader: accepts _license.txt", titles.has("American Spelling"))
	_check("Loader: accepts _credits.txt", titles.has("Audio Contributor"))
	# 4. unrelated files are ignored
	_check("Loader: ignores a README", not titles.has("README"))
	_check("Loader: ignores an unrelated .txt",
		not _titles_contain(titles, "notes"))
	_check("Loader: ignores a bare licence.txt with no name",
		not _titles_contain(titles, ""))
	_check("Loader: exactly the four valid files were picked up",
		entries.size() == 4)

	# 5. deterministic ordering, twice
	var again := ACACreditsLoader.list_entries(TEST_DIR)
	var titles_again := PackedStringArray()
	for entry in again:
		titles_again.append(String(entry["title"]))
	_check("Loader: ordering is deterministic", titles == titles_again)
	_check("Loader: ordering is alphabetical by title",
		titles == PackedStringArray(
			["American Spelling", "Audio Contributor", "Kenney Assets", "Sky3D"]))

	# 6. the text comes back verbatim
	var text := ACACreditsLoader.load_text(TEST_DIR.path_join("Sky3D_licence.txt"))
	_check("Loader: loads the file text", text.contains("FIXTURE SKY3D BODY"))
	_check("Loader: preserves line breaks", text.contains("\n"))
	_check("Loader: preserves non-ASCII characters", text.contains("J. Cuéllar"))
	_check("Loader: missing file returns empty, not a crash",
		ACACreditsLoader.load_text(TEST_DIR.path_join("nope.txt")).is_empty())

	# 7. title derivation in isolation
	_check("Loader: title_from_filename strips the suffix",
		ACACreditsLoader.title_from_filename("Nature_Pack_licence.txt") == "Nature Pack")
	_check("Loader: title_from_filename is case-insensitive about the suffix",
		ACACreditsLoader.title_from_filename("Thing_LICENCE.txt") == "Thing")
	_check("Loader: is_credit_file rejects an unrelated name",
		not ACACreditsLoader.is_credit_file("notes.txt"))
	_check("Loader: is_credit_file rejects a non-text extension",
		not ACACreditsLoader.is_credit_file("Sky3D_licence.png"))


func _build_fixture() -> void:
	_remove_fixture()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_write("Sky3D_licence.txt",
		"FIXTURE SKY3D BODY\nCopyright (c) 2021 J. Cuéllar\nline three\n")
	_write("Kenney_Assets_licence.txt", "FIXTURE KENNEY BODY\n")
	_write("American_Spelling_license.txt", "FIXTURE US SPELLING\n")
	_write("Audio_Contributor_credits.txt", "FIXTURE AUDIO\n")
	# Must all be ignored.
	_write("README.md", "not a credit\n")
	_write("notes.txt", "not a credit\n")
	_write("licence.txt", "no name in front of the suffix\n")


func _write(file_name: String, text: String) -> void:
	var f := FileAccess.open(TEST_DIR.path_join(file_name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _remove_fixture() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(TEST_DIR)


func _titles_contain(titles: PackedStringArray, needle: String) -> bool:
	for title in titles:
		if title.to_lower() == needle.to_lower():
			return true
	return false


# ======================================================= 2. the real folder

func _test_real_folder() -> void:
	var entries := ACACreditsLoader.list_entries()
	_check("Real folder: %s has credits in it (%d)"
		% [ACACreditsLoader.CREDITS_DIRECTORY, entries.size()], entries.size() >= 5)

	var titles := PackedStringArray()
	for entry in entries:
		titles.append(String(entry["title"]))

	# The attribution that used to be embedded in the MVP HUD must still exist
	# somewhere player-facing, or retiring that UI lost it.
	_check("Real folder: Sky3D is credited", titles.has("Sky3D"))
	_check("Real folder: Terrain3D attribution survived the HUD removal",
		titles.has("Terrain3D"))
	_check("Real folder: the engine is credited", titles.has("Godot Engine"))

	var sky := ""
	for entry in entries:
		if String(entry["title"]) == "Sky3D":
			sky = ACACreditsLoader.load_text(String(entry["path"]))
	_check("Real folder: the Sky3D licence text is the real one",
		sky.contains("MIT License") and sky.contains("Cory Petkovsek"))

	# The old player-facing credits UI is gone from the development HUD.
	var hud_scene: PackedScene = load("res://Game/M.V.P/MVP_HUD.tscn")
	_check("Old UI: MVP HUD still loads", hud_scene != null)
	if hud_scene != null:
		var hud: Node = hud_scene.instantiate()
		_check("Old UI: the HUD credits button is gone",
			hud.get_node_or_null(^"Credit Button") == null)
		_check("Old UI: the HUD credits panels are gone",
			hud.get_node_or_null(^"ColorRect") == null
			and hud.get_node_or_null(^"ColorRect2") == null)
		hud.free()


# ======================================================= 3. the real screen

func _test_screen_from_main_menu() -> void:
	GameSession.go_to_main_menu()
	await _wait_for_screen(ACAGameSession.Screen.MAIN_MENU)
	await _step(6)

	var scene := get_tree().current_scene
	var credits: CreditsScreen = scene.get_node_or_null(^"Menu UI/Credits") if scene != null else null
	_check("Screen: Credits is part of the Main Menu", credits != null)
	if credits == null:
		return

	_check("Screen: starts closed", not credits.is_open())

	# The real route the player takes.
	var menu: MainMenuScreen = null
	for node in scene.find_children("*", "MainMenuScreen", true, false):
		menu = node as MainMenuScreen
		break
	_check("Screen: the main menu component is present", menu != null)
	if menu != null:
		menu.menu_option_selected.emit(&"credits")
		await _step(4)
	_check("Screen: CREDITS from the main menu opens it", credits.is_open())

	_check("Screen: shows every entry in the folder",
		credits.entry_count() == ACACreditsLoader.list_entries().size())
	_check("Screen: an entry is selected by default",
		not credits.selected_title().is_empty())
	_check("Screen: the detail pane has the selected text",
		credits.detail_text().length() > 40)

	# Long text has to be reachable, not clipped away.
	var titles := credits.entry_titles()
	var long_index := titles.find("Sky3D Milky Way Texture")
	if long_index < 0:
		long_index = titles.find("Sky3D")
	credits.select_index(long_index)
	await _step(4)
	_check("Screen: selecting an entry swaps the detail text",
		credits.selected_title() == titles[long_index])
	var scroll: ScrollContainer = credits.find_child("DetailScroll", true, false)
	var body: Label = credits.find_child("DetailBody", true, false)
	_check("Screen: the detail pane is inside a ScrollContainer", scroll != null)
	if scroll != null and body != null:
		_check("Screen: long text is taller than the pane, so it scrolls",
			body.size.y > scroll.size.y or scroll.get_v_scroll_bar().max_value > scroll.size.y)
		_check("Screen: the text is wrapped, not clipped",
			body.autowrap_mode != TextServer.AUTOWRAP_OFF)

	credits.back_requested.emit()
	await _step(4)
	_check("Screen: BACK closes it", not credits.is_open())
	_check("Screen: the main menu is still the current screen",
		GameSession.current_screen() == ACAGameSession.Screen.MAIN_MENU)


# ===================================================================== helpers

func _wait_for_screen(screen: int, max_frames: int = 600) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1
	_fail("Timed out waiting for screen %d" % screen)


func _step(frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[CREDITS TEST] %s: PASS" % label)
	else:
		_failures += 1
		printerr("[CREDITS TEST] %s: FAIL" % label)


func _fail(label: String) -> void:
	_check(label, false)
