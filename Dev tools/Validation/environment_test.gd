extends SceneTree
## DEVELOPMENT ONLY. Guards the REUSABLE environment package.
##
##   godot --headless --path <project> \
##     --script "res://Dev tools/Validation/environment_test.gd"
##
## `Weather Test` already covers how the game LOOKS and how the integration is
## wired. This suite covers the thing that suite structurally cannot: whether
## `res://addons/aca_sky3d_environment/` is still a package someone could copy
## into another project.
##
## It runs headless in milliseconds because none of it needs a renderer.

const ADDON := "res://addons/aca_sky3d_environment"
const SKY3D := "res://addons/sky_3d"

## Anything here appearing inside the package means the boundary has been
## broken. These are A Cut Above's own directories and autoloads: the package
## must not know that any of them exist.
const FORBIDDEN_PATHS: PackedStringArray = [
	"res://Game/", "res://Mowing Section/", "res://Main Area/",
	"res://Data Structures/", "res://Assets/", "res://UI/", "res://Weather/",
	"res://Dev tools/", "res://Credits/", "res://Shaders/", "res://Terrain/",
	"res://Mower Scenes/",
]
const FORBIDDEN_IDENTIFIERS: PackedStringArray = [
	"WorldClock", "JobManager", "GameSession", "SaveService", "AppUI",
	"MowerFuel", "ACALawn", "ACAProperty", "ACATerrain", "BusinessTown",
	"ACAWeatherVisualAdapter",
	"ACATrailer", "Rain_Handler", "ACAJob", "ACATownLightAdapter",
]
## Extensions that are code or data. Anything else under the package is an
## ASSET, and this package deliberately ships none - see the licensing note in
## its README.
const SOURCE_EXTENSIONS: PackedStringArray = ["gd", "tres", "tscn", "cfg", "md", "uid"]

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_test_portability()
	_test_no_bundled_assets()
	_test_sky3d_untouched_by_us()
	_test_profiles_load()
	_test_composition_is_standalone()
	_test_ground_reference()
	_test_transitions()
	_test_quality_removes_work()
	_test_demo_exists()

	print("[ENVIRONMENT TEST] %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ================================================================ portability

## THE ASSERTION THAT MATTERS MOST.
##
## A reusable package stops being reusable the moment one file reaches back
## into the game, and that happens by accident far more often than by decision.
## Doing this by eye once proves nothing about next month.
func _test_portability() -> void:
	var offenders: Array[String] = []
	for path in _files_under(ADDON):
		if not SOURCE_EXTENSIONS.has(path.get_extension()):
			continue
		var text := _read(path)
		if text.is_empty():
			continue
		for needle: String in FORBIDDEN_PATHS:
			if text.contains(needle):
				offenders.append("%s -> %s" % [path.get_file(), needle])
		for ident: String in FORBIDDEN_IDENTIFIERS:
			# Word-ish match: `ACAJob` must not fire on `ACAJobless` either, but
			# a substring hit here is worth looking at regardless.
			if text.contains(ident):
				offenders.append("%s -> %s" % [path.get_file(), ident])
	_check("Portability: no A Cut Above paths or classes inside the package%s"
		% ("" if offenders.is_empty() else " (" + ", ".join(offenders) + ")"),
		offenders.is_empty())

	# The one dependency it IS allowed, and must actually declare.
	var uses_sky3d := false
	for path in _files_under(ADDON):
		if path.get_extension() == "gd" and _read(path).contains(SKY3D):
			uses_sky3d = true
	_check("Portability: the package references vanilla Sky3D (its one dependency)",
		uses_sky3d)


## No audio, no textures, no meshes. Everything is built in code, which is what
## keeps the package free of someone else's licence - including this project's
## own sound files, whose attribution is unresolved (R-016).
func _test_no_bundled_assets() -> void:
	var assets: Array[String] = []
	for path in _files_under(ADDON):
		if not SOURCE_EXTENSIONS.has(path.get_extension()):
			assets.append(path.get_file())
	_check("Portability: the package bundles no binary assets%s"
		% ("" if assets.is_empty() else " (" + ", ".join(assets) + ")"),
		assets.is_empty())


## The package must never write into the third-party addon. A grep is not proof
## of runtime behaviour, but it catches the obvious mistake, and the file-level
## proof is the `diff -rq` in the session close-out.
func _test_sky3d_untouched_by_us() -> void:
	var writes := false
	for path in _files_under(ADDON):
		if path.get_extension() != "gd":
			continue
		var text := _read(path)
		if text.contains("ResourceSaver.save") and text.contains(SKY3D):
			writes = true
	_check("Sky3D: the package never writes into res://addons/sky_3d", not writes)


# =================================================================== profiles

func _test_profiles_load() -> void:
	var env := ACASky3DEnvironment.new()
	env.load_profiles()
	var times := env.time_profile_ids()
	var weathers := env.weather_ids()
	var qualities := env.quality_ids()
	_check("Profiles: time profiles loaded from disk (%s)" % str(times), times.size() >= 4)
	_check("Profiles: weather profiles loaded from disk (%s)" % str(weathers),
		weathers.size() >= 3)
	_check("Profiles: quality profiles loaded from disk (%s)" % str(qualities),
		qualities.size() >= 3)

	# Every profile is a real resource on disk, not a fallback built in code.
	var on_disk := 0
	for path in _files_under(ADDON + "/profiles"):
		if path.get_extension() == "tres":
			on_disk += 1
	_check("Profiles: %d .tres files on disk" % on_disk,
		on_disk == times.size() + weathers.size() + qualities.size())
	env.free()


## Composition must not need a scene, a renderer or a bound Sky3D. That is what
## lets tooling and tests inspect a look without standing one up.
func _test_composition_is_standalone() -> void:
	var env := ACASky3DEnvironment.new()
	env.load_profiles()
	_check("Composition: works with nothing bound", not env.is_bound())
	var values := env.compose("Rain", 16.3)
	_check("Composition: an unbound adapter still composes a full look (%d keys)"
		% values.size(), values.size() > 40)
	_check("Composition: the key space covers sky, dome, env and fx",
		values.has("sky:camera_exposure") and values.has("dome:atm_day_tint")
		and values.has("env:fog_enabled") and values.has("fx:rain_intensity"))
	env.free()


# =========================================================== ground reference

## Regression guard for the flat-white-screen bug.
##
## `Environment.fog_height` is an ABSOLUTE world Y. A Cut Above's lawn is
## authored at about y = -508, so a fog layer placed at "3.0" put every surface
## in the scene five hundred units under it, saturating the height term and
## rendering the whole frame white. The composed value must move with the
## declared ground.
func _test_ground_reference() -> void:
	var env := ACASky3DEnvironment.new()
	env.load_profiles()
	var authored := float(env.compose("Foggy", 12.0)["env:fog_height"])
	_check("Ground: profiles author fog height RELATIVE to ground (%.1f)" % authored,
		absf(authored) < 50.0)
	env.set_ground_reference(-508.0)
	_check("Ground: setting a reference does not change the COMPOSED value",
		is_equal_approx(float(env.compose("Foggy", 12.0)["env:fog_height"]), authored))
	_check("Ground: the reference is stored for the write step",
		is_equal_approx(env.ground_reference, -508.0))
	env.free()


# ================================================================ transitions

## Interruption safety. The whole reason there is no Tween in the package is
## that overlapping weather changes must not be able to strand one.
func _test_transitions() -> void:
	var env := ACASky3DEnvironment.new()
	env.load_profiles()
	env.set_weather(&"Rain")
	env.set_weather(&"Foggy")
	env.set_weather(&"Clear")
	_check("Transitions: rapid changes settle on the LAST one",
		env.current_weather() == "Clear")

	env.set_weather(&"NotAWeather")
	_check("Transitions: an unknown weather does not strand the adapter",
		env.weather_ids().has(env.current_weather()))

	env.set_time_of_day(999.0)
	_check("Transitions: an out-of-range hour is clamped, not wrapped into nonsense",
		env.current_hour() >= 0.0 and env.current_hour() <= 23.99)

	# The override must leave nothing behind.
	var before := env.compose("Rain", 15.4)
	env.set_presentation_override({"set": {"dome:atm_day_tint": Color(0, 1, 0)}})
	_check("Transitions: an override changes the composed look",
		not (env.compose("Rain", 15.4)["dome:atm_day_tint"] as Color)
			.is_equal_approx(before["dome:atm_day_tint"]))
	env.clear_presentation_override()
	_check("Transitions: clearing the override restores it exactly",
		(env.compose("Rain", 15.4)["dome:atm_day_tint"] as Color)
			.is_equal_approx(before["dome:atm_day_tint"]))
	_check("Transitions: no override is left installed", not env.has_presentation_override())
	env.free()


# ==================================================================== quality

## A quality level must REMOVE WORK. Two levels that do the same thing are one
## level and a lie.
func _test_quality_removes_work() -> void:
	var env := ACASky3DEnvironment.new()
	env.load_profiles()
	var high := env.quality_profile("High")
	var medium := env.quality_profile("Medium")
	var low := env.quality_profile("Low")
	if high == null or medium == null or low == null:
		_check("Quality: the three shipped levels exist", false)
		env.free()
		return
	_check("Quality: the three shipped levels exist", true)

	# Each pair must differ in at least one MECHANISM, not only in a number.
	var mechanisms := func(q: ACAEnvQualityProfile) -> Array:
		return [q.use_depth_fog, q.use_aerial, q.use_volumetric_fog,
			q.rain_layers, q.rain_splash]
	_check("Quality: High and Medium are genuinely different work",
		mechanisms.call(high) != mechanisms.call(medium))
	_check("Quality: Medium and Low are genuinely different work",
		mechanisms.call(medium) != mechanisms.call(low))
	_check("Quality: cost is ordered High > Medium > Low",
		high.rain_layers > medium.rain_layers and medium.rain_layers > low.rain_layers)
	_check("Quality: the cheapest level still updates least often (%.3f s)"
		% low.update_interval, low.update_interval >= high.update_interval)
	env.free()


# ======================================================================= demo

## The demo is the package's own proof it does not need a game. If it stops
## loading, the claim in the README stops being true.
func _test_demo_exists() -> void:
	var scene_path := ADDON + "/demo/Environment Demo.tscn"
	_check("Demo: the standalone scene exists", FileAccess.file_exists(scene_path))
	_check("Demo: the standalone scene loads",
		ResourceLoader.load(scene_path, "PackedScene") != null)
	_check("Demo: the package documents its install order",
		_read(ADDON + "/README.md").contains("vanilla Sky3D"))


# ==================================================================== helpers

func _files_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_files_under(full))
		else:
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[ENV] %s: PASS" % label)
	else:
		_fail += 1
		printerr("[ENV] %s: FAIL" % label)
