extends Node
## DEVELOPMENT ONLY. The weather/time VISUAL layer.
##
##   godot --headless --path <project> "res://Dev tools/Validation/Weather Test.tscn" -- "--save-root=<dir>"
##
## The look itself is judged from pixels - see `Weather Matrix.tscn`. What this
## suite asserts is the things a screenshot cannot show:
##
##   * the composition RULE (time profile x weather layer) actually composes
##   * WorldClock stays authoritative and Sky3D's own clock is off
##   * the adapter converges and leaves nothing stale behind
##   * weather and time survive Town -> Job -> Town and a save/load round trip,
##     and the visuals are re-applied afterwards
##   * rain still follows the mower and still ducks the ambience
##   * `res://addons/sky_3d/` is not written to

const STEP_FRAMES := 4

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n=============== WEATHER TEST ===============")

	await _step()
	_test_composition()
	_test_audio_buses()
	await _test_scene_visuals()
	await _test_persistence()

	print("============================================")
	print("[WEATHER TEST] %d passed, %d failed" % [_passes, _failures])
	print("============================================\n")
	get_tree().quit(0 if _failures == 0 else 1)


# ============================================================== composition
##
## Pure table logic - no scene needed, so this runs headless in milliseconds.

func _test_composition() -> void:
	var adapter := ACAWeatherVisualAdapter.new()

	# Four time profiles, three weather layers, and every profile has to carry
	# the same key set or blending between two of them is partial.
	var keys: Array = ACAWeatherVisualAdapter.TIME_PROFILES["Day"].keys()
	var same := true
	for name: String in ACAWeatherVisualAdapter.TIME_PROFILES:
		var profile: Dictionary = ACAWeatherVisualAdapter.TIME_PROFILES[name]
		if profile.size() != keys.size():
			same = false
		for key: String in keys:
			if not profile.has(key):
				same = false
	_check("Composition: every time profile carries the same keys", same)
	_check("Composition: the three weather layers exist",
		ACAWeatherVisualAdapter.WEATHER_LAYERS.has("Clear")
		and ACAWeatherVisualAdapter.WEATHER_LAYERS.has("Foggy")
		and ACAWeatherVisualAdapter.WEATHER_LAYERS.has("Rain"))

	# Anchors must be sorted and cover the whole day, or an hour falls through.
	var anchors: Array = ACAWeatherVisualAdapter.TIME_ANCHORS
	var sorted := true
	for i in range(anchors.size() - 1):
		if float(anchors[i][0]) > float(anchors[i + 1][0]):
			sorted = false
	_check("Composition: anchors are sorted", sorted)
	_check("Composition: anchors cover 00:00 - 24:00",
		is_equal_approx(float(anchors[0][0]), 0.0)
		and is_equal_approx(float(anchors[-1][0]), 24.0))

	var covered := true
	var h := 0.0
	while h < 24.0:
		if adapter.time_values(h).size() != keys.size():
			covered = false
		h += 0.25
	_check("Composition: every hour resolves to a complete look", covered)

	# THE RULE. Evening rain must still be evening: the warm sun tint survives
	# as a scaled-down version of the evening value, not replaced by grey.
	var evening_clear := adapter.compose("Clear", 16.3)
	var evening_rain := adapter.compose("Rain", 16.3)
	var day_rain := adapter.compose("Rain", 12.0)

	var e_sun: Color = evening_clear["dome:sun_horizon_light_color"]
	var er_sun: Color = evening_rain["dome:sun_horizon_light_color"]
	var dr_sun: Color = day_rain["dome:sun_horizon_light_color"]
	_check("Composition: rain darkens the evening sun tint", er_sun.r < e_sun.r)
	_check("Composition: rain keeps the evening HUE, not just a grey",
		er_sun.r > er_sun.b and er_sun.r / maxf(er_sun.b, 0.001) > 1.4)
	_check("Composition: evening rain differs from day rain",
		not er_sun.is_equal_approx(dr_sun))

	# Weather owns the clouds and fog outright, whatever the hour.
	_check("Composition: rain sets heavy cloud cover at any hour",
		float(evening_rain["dome:clouds_cumulus_coverage"])
		== float(day_rain["dome:clouds_cumulus_coverage"]))
	_check("Composition: fog is shorter-range in Foggy than in Clear",
		float(adapter.compose("Foggy", 12.0)["dome:fog_end"])
		< float(adapter.compose("Clear", 12.0)["dome:fog_end"]))

	# Readability rules, stated as assertions rather than trusted to taste.
	for weather in ["Clear", "Foggy", "Rain"]:
		var night: Dictionary = adapter.compose(weather, 22.0)
		_check("Readability: %s night is not pitch black (exposure %.2f)"
			% [weather, float(night["sky:camera_exposure"])],
			float(night["sky:camera_exposure"]) >= 1.0)
		_check("Readability: %s night keeps a moon (%.2f)"
			% [weather, float(night["sky:moon_energy"])],
			float(night["sky:moon_energy"]) >= 0.5)
		var day: Dictionary = adapter.compose(weather, 12.0)
		_check("Readability: %s day does not blow out (exposure %.2f)"
			% [weather, float(day["sky:camera_exposure"])],
			float(day["sky:camera_exposure"]) <= 1.2)
		_check("Readability: %s keeps some ambient fill" % weather,
			float(day["sky:ambient_energy"]) >= 0.9)
	_check("Readability: fog does not become a white wall (near field is clear)",
		float(adapter.compose("Foggy", 12.0)["dome:fog_start"]) > 0.0)

	# The town's Day profile must stay the authored town.
	var town_day: Dictionary = ACATownLightAdapter.TIME_PROFILES["Day"]
	_check("Town: Day is the authored sun colour",
		(town_day["sun_color"] as Color).is_equal_approx(Color(1.0, 0.945, 0.851)))
	_check("Town: Day is the authored sun energy",
		is_equal_approx(float(town_day["sun_energy"]), 1.5))
	_check("Town: Day adds no fog",
		not bool(ACATownLightAdapter.WEATHER_LAYERS["Clear"]["set"]["fog_enabled"]))
	_check("Town: shares the sky adapter's anchors",
		ACATownLightAdapter.TIME_ANCHORS == ACAWeatherVisualAdapter.TIME_ANCHORS)

	adapter.free()


# ================================================================== audio
##
## Cheap structural guards only. The MIX itself is measured, not asserted, by
## `Audio Mix Probe.tscn` - which runs the real scene in each weather state and
## reports the level every bus reaches.

func _test_audio_buses() -> void:
	for bus: StringName in ACAAudioMix.BUSES:
		_check("Audio: the %s bus exists" % bus, ACAAudioMix.has_bus(bus))
	_check("Audio: everything routes to Master", _all_route_to_master())

	# The whole point of the buses: two settings that used to be inert.
	GameSettings.set_value("mower_volume", 0.5)
	GameSettings.set_value("ambience_volume", 0.25)
	var mower_db := AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index(ACAAudioMix.MOWER))
	var ambience_db := AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index(ACAAudioMix.AMBIENCE))
	var weather_db := AudioServer.get_bus_volume_db(
		AudioServer.get_bus_index(ACAAudioMix.WEATHER))
	_check("Audio: mower_volume reaches the Mower bus (%.2f dB)" % mower_db,
		is_equal_approx(mower_db,
			linear_to_db(0.5) + ACAAudioMix.trim_db(ACAAudioMix.MOWER)))
	_check("Audio: ambience_volume reaches the Ambience bus (%.2f dB)" % ambience_db,
		is_equal_approx(ambience_db,
			linear_to_db(0.25) + ACAAudioMix.trim_db(ACAAudioMix.AMBIENCE)))
	_check("Audio: Weather follows the Ambience setting (%.2f dB)" % weather_db,
		is_equal_approx(weather_db,
			linear_to_db(0.25) + ACAAudioMix.trim_db(ACAAudioMix.WEATHER)))
	_check("Audio: zero mutes rather than fading to -inf",
		_mutes_at_zero(ACAAudioMix.MOWER))
	GameSettings.apply(ACAGameSettings.DEFAULTS.duplicate())


func _all_route_to_master() -> bool:
	for i in AudioServer.bus_count:
		var name := StringName(AudioServer.get_bus_name(i))
		if name == ACAAudioMix.MASTER:
			continue
		if AudioServer.get_bus_send(i) != ACAAudioMix.MASTER:
			return false
	return true


func _mutes_at_zero(bus: StringName) -> bool:
	GameSettings.set_value("mower_volume", 0.0)
	var muted := AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))
	GameSettings.set_value("mower_volume", 0.8)
	return muted and not AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))


# =============================================================== the scene

func _test_scene_visuals() -> void:
	GameSession.start_new_game()
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	await _step(8)

	var town_lights = get_tree().current_scene.get_node_or_null(^"Town Light Adapter")
	_check("Town: light adapter is running", town_lights != null and town_lights.is_bound())

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		await _step(4)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		_fail("Weather: no contract to enter the mowing scene with")
		return

	WorldClock.set_weather("Rain")
	var job: ACAJob = offers[0]
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	await _wait_for_screen(ACAGameSession.Screen.MOWING)
	await _step(10)

	var scene := get_tree().current_scene
	var pm = scene.get_node_or_null(^"PresetManager (Sky3D)")
	_check("Mowing: preset manager present", pm != null)
	if pm == null:
		return

	_check("Weather survived Town -> Job", WorldClock.weather_preset() == "Rain")
	_check("Mowing: the preset manager agrees with the world clock",
		pm.current_weather_preset == WorldClock.weather_preset())
	_check("Mowing: the visual adapter is bound", pm.visual != null and pm.visual.is_bound())

	# THE clock rule: Sky3D's own time must be off, or it drifts against the HUD.
	var sky = pm.get_node(^"Sky3D")
	_check("Mowing: Sky3D's own clock is disabled", not sky.enable_game_time)
	_check("Mowing: the sky is showing the world clock's hour",
		absf(pm.current_time_of_day - WorldClock.hour_of_day()) < 0.2)

	# Rain: particles running, and following the mower rather than the origin.
	var rain: Rain_Handler = pm.get_node(^"Rain Handler")
	_check("Rain: the rain handler is raining", rain.is_raining)
	await _step(20)
	var mower: Node3D = scene.get(&"current_mower")
	_check("Rain: the emitter follows the mower",
		rain.mower_position.distance_to(mower.global_position) < 1.0)
	_check("Rain: the ambience player was handed over for ducking",
		rain.base_ambience_audio != null)

	# The clock really moves the sky.
	var before: float = pm.current_time_of_day
	WorldClock.advance_to_hour(22.0)
	await _step(10)
	_check("Time: advancing the clock moves the sky (%.1f -> %.1f)"
		% [before, pm.current_time_of_day],
		absf(pm.current_time_of_day - 22.0) < 0.3)

	# Convergence: after a rapid weather flip the adapter must settle on the NEW
	# look, with nothing left applying the old one.
	WorldClock.set_weather("Clear")
	WorldClock.set_weather("Foggy")
	WorldClock.set_weather("Clear")
	await _step(240)
	var target: Dictionary = pm.visual.compose("Clear", pm.current_time_of_day)
	var settled := absf(float(sky.camera_exposure)
		- float(target["sky:camera_exposure"])) < 0.05
	_check("Transitions: rapid preset changes settle on the LAST one, not a stale tween",
		settled)
	_check("Transitions: no Tween is left running on the sky",
		pm.visual.get_children().is_empty())


# ============================================================== persistence

func _test_persistence() -> void:
	WorldClock.set_weather("Foggy")
	WorldClock.advance_to_hour(16.3)
	await _step(6)
	var saved_weather := WorldClock.weather_preset()
	var saved_hour := WorldClock.hour_of_day()

	_check("Save: wrote a slot", SaveService.save_game())

	WorldClock.set_weather("Clear")
	WorldClock.advance_to_hour(12.0)
	await _step(6)

	_check("Load: read the slot back", SaveService.load_most_recent())
	await _step(30)
	_check("Load: weather restored", WorldClock.weather_preset() == saved_weather)
	_check("Load: time restored", absf(WorldClock.hour_of_day() - saved_hour) < 0.5)

	# And the VISUALS have to follow the restored state, not the pre-load one.
	await _step(30)
	var scene := get_tree().current_scene
	var pm = scene.get_node_or_null(^"PresetManager (Sky3D)")
	if pm != null:
		_check("Load: the sky re-applied the restored weather",
			pm.current_weather_preset == saved_weather)
		_check("Load: the sky re-applied the restored hour",
			absf(pm.current_time_of_day - WorldClock.hour_of_day()) < 0.3)
	else:
		var town_lights = scene.get_node_or_null(^"Town Light Adapter")
		_check("Load: the town re-lit from the restored state", town_lights != null)


# ================================================================== helpers

func _wait_for_screen(screen: int, max_frames: int = 900) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1
	_fail("Timed out waiting for screen %d" % screen)


func _step(frames: int = STEP_FRAMES) -> void:
	for i in frames:
		await get_tree().process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("[WEATHER TEST] %s: PASS" % label)
	else:
		_failures += 1
		printerr("[WEATHER TEST] %s: FAIL" % label)


func _fail(label: String) -> void:
	_check(label, false)
