extends Node
## DEVELOPMENT ONLY. Measures the audio mix instead of guessing at it.
##
##   godot --headless --path <project> "res://Dev tools/Validation/Audio Mix Probe.tscn" -- "--save-root=<dir>"
##
## The addendum to Milestone 9 asks for a balance that holds across weather.
## "Perceived balance" cannot be asserted, but the level each family of sounds
## actually reaches CAN be: this runs the real mowing scene, puts the real rider
## through Clear / Foggy / Rain at idle and while mowing, and reports the peak
## level the **Mower**, **Ambience** and **Weather** buses hit in each state.
##
## Those numbers are what `ACAAudioMix.TRIM_DB` was set from. Re-run it after
## changing a source level or a trim.
##
## It also proves the thing the old mix got wrong: a Clear -> Rain -> Clear
## round trip must leave the ambience player at exactly its authored level. The
## Rain Handler used to write ABSOLUTE decibels on to it, so the first return to
## Clear raised the ambience by nearly 17 dB and left it there.

## Peak windows the mix has to land in, in dBFS on each bus. Wide on purpose -
## this is a guard against a source level or a trim being changed by an order of
## magnitude, not a claim that one particular number sounds right.
const TARGETS := {
	# state                       bus            min      max
	"clear/idle": {"Mower": [-26.0, -14.0]},
	"clear/mowing": {"Mower": [-18.0, -5.0], "Ambience": [-27.0, -12.0]},
	"rain/mowing": {"Mower": [-18.0, -5.0], "Weather": [-23.0, -8.0]},
}

## Rain must be present but must not bury the engine. Measured as the difference
## between the two buses' peaks while mowing in the rain.
const RAIN_UNDER_MOWER_MIN_DB := 0.5
const RAIN_UNDER_MOWER_MAX_DB := 18.0

## How much the mower peak is allowed to move between Clear and Rain. The mower
## source level must not be touched by weather at all, so this is only sampling
## noise.
const MOWER_WEATHER_DRIFT_MAX_DB := 4.0

## Waits are in SECONDS, not frames. The mowing scene runs physics at 576 Hz
## over tens of thousands of grass bodies, so a headless frame is not cheap and
## a frame count is not a duration. The rain fade alone is 2.0 s.
const SETTLE_SECONDS := 2.6
const SAMPLE_SECONDS := 1.2

var _passes: int = 0
var _failures: int = 0
var _readings: Dictionary = {}
var _rain: Rain_Handler = null
var _ambience: AudioStreamPlayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	print("\n============== AUDIO MIX PROBE ==============")
	print("[AUDIO] driver: %s" % AudioServer.get_driver_name())
	_report_buses()

	await _enter_mowing()
	if _rain == null:
		print("[AUDIO] could not reach the mowing scene; nothing measured")
		get_tree().quit(1)
		return

	var authored_ambience_db: float = _ambience.volume_db
	print("[AUDIO] ambience authored at %.2f dB" % authored_ambience_db)

	await _measure("clear/idle", "Clear", false)
	await _measure("clear/mowing", "Clear", true)
	await _measure("foggy/mowing", "Foggy", true)
	await _measure("rain/idle", "Rain", false)
	await _measure("rain/mowing", "Rain", true)
	await _measure("clear again/mowing", "Clear", true)

	_print_table()
	_assert_mix(authored_ambience_db)
	await _assert_environment_beds()
	await _assert_ui_sound()

	print("=============================================")
	print("[AUDIO MIX PROBE] %d passed, %d failed" % [_passes, _failures])
	print("=============================================\n")
	get_tree().quit(0 if _failures == 0 else 1)


# ==================================================================== setup

func _report_buses() -> void:
	var names: PackedStringArray = []
	for i in AudioServer.bus_count:
		names.append("%s -> %s" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i)])
	print("[AUDIO] buses: %s" % ", ".join(names))
	_check("Buses: every expected bus exists", ACAAudioMix.all_buses_present())


func _enter_mowing() -> void:
	GameSession.start_new_game()
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	await _step(8)

	var offers := JobManager.available_jobs()
	if offers.is_empty():
		JobManager.seed_initial_offers(1)
		await _step(4)
		offers = JobManager.available_jobs()
	if offers.is_empty():
		return

	var job: ACAJob = offers[0]
	JobManager.accept_job(job.id)
	JobManager.begin_new_job(job.id)
	await _wait_for_screen(ACAGameSession.Screen.MOWING)
	await _step(20)

	var scene := get_tree().current_scene
	var pm = scene.get_node_or_null(^"PresetManager (Sky3D)")
	if pm == null:
		return
	_rain = pm.get_node_or_null(^"Rain Handler") as Rain_Handler
	_ambience = scene.get_node_or_null(^"AudioStreamPlayer") as AudioStreamPlayer

	# A full tank, so a long probe is not measuring a dead engine.
	MowerFuel.refuel_full()


# ================================================================ measuring

func _measure(label: String, weather: String, mowing: bool) -> void:
	WorldClock.set_weather(weather)
	if mowing:
		Input.action_press(&"move_forward")
	else:
		Input.action_release(&"move_forward")

	var t0 := Time.get_ticks_msec()
	await _wait_seconds(SETTLE_SECONDS)

	var peaks := {ACAAudioMix.MOWER: -200.0, ACAAudioMix.AMBIENCE: -200.0,
		ACAAudioMix.WEATHER: -200.0, ACAAudioMix.MASTER: -200.0}
	var frames := 0
	var until := Time.get_ticks_msec() + int(SAMPLE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < until:
		for bus: StringName in peaks:
			peaks[bus] = maxf(peaks[bus], _peak_db(bus))
		frames += 1
		await get_tree().process_frame
	print("[AUDIO] %-20s sampled %d frames over %.1f s" % [
		label, frames, float(Time.get_ticks_msec() - t0) / 1000.0])

	peaks["ambience_player_db"] = _ambience.volume_db
	peaks["fuel"] = MowerFuel.fraction()
	_readings[label] = peaks
	Input.action_release(&"move_forward")
	# Keep the tank full so later states are measured with the engine running.
	MowerFuel.refuel_full()


func _peak_db(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return -200.0
	return maxf(
		AudioServer.get_bus_peak_volume_left_db(index, 0),
		AudioServer.get_bus_peak_volume_right_db(index, 0))


## ---------------------------------------------------------------------------
## THE AIR RESPONDS TO THE SKY
## ---------------------------------------------------------------------------
## `ACAEnvironmentAudio` adds wind, wildlife and far rain and mixes them from
## the weather. Bus peaks cannot show that - all three share a bus with things
## that were already there - so this reads the three players directly and checks
## the CLAIM: birds in the clear, wind and rain instead of them in the wet.
func _assert_environment_beds() -> void:
	var scene := get_tree().current_scene
	var env = scene.get("environment_audio") if scene != null else null
	if env == null:
		_check("Environment audio is mounted in the mowing scene", false)
		return
	_check("Environment audio is mounted in the mowing scene", true)

	print("")
	print("  sky            wind   wildlife   far rain")
	print("  ------------ ------ ---------- ----------")
	var readings := {}
	for preset: String in ["Clear", "Overcast", "Light Rain", "Rain"]:
		WorldClock.set_weather(preset)
		# The beds walk at a fixed decibels per second, deliberately, so they
		# need real time to arrive rather than a frame.
		await _wait_seconds(7.0)
		var row := {
			"wind": _bed_db(env, "Wind"),
			"wildlife": _bed_db(env, "Wildlife"),
			"far_rain": _bed_db(env, "Far Rain"),
		}
		readings[preset] = row
		print("  %-12s %6.1f %10.1f %10.1f" % [preset, row["wind"],
			row["wildlife"], row["far_rain"]])

	var clear: Dictionary = readings["Clear"]
	var rain: Dictionary = readings["Rain"]
	_check("Wildlife is loud in the clear (%.1f dB)" % clear["wildlife"],
		clear["wildlife"] > -30.0)
	_check("Wildlife goes quiet in heavy rain (%.1f -> %.1f dB)"
		% [clear["wildlife"], rain["wildlife"]],
		rain["wildlife"] < clear["wildlife"] - 6.0)
	_check("Wind rises with the weather (%.1f -> %.1f dB)"
		% [clear["wind"], rain["wind"]], rain["wind"] > clear["wind"] + 3.0)
	_check("Far rain is silent when it is dry (%.1f dB)" % clear["far_rain"],
		clear["far_rain"] < -50.0)
	_check("Far rain is present in rain (%.1f dB)" % rain["far_rain"],
		rain["far_rain"] > -30.0)
	_check("Light rain is quieter than heavy rain (%.1f vs %.1f dB)"
		% [readings["Light Rain"]["far_rain"], rain["far_rain"]],
		readings["Light Rain"]["far_rain"] < rain["far_rain"] - 0.5)
	WorldClock.set_weather("Clear")


## ---------------------------------------------------------------------------
## THE UI BUS IS NO LONGER RESERVED
## ---------------------------------------------------------------------------
## It carried no signal at all until this pass. Every cue is checked to actually
## reach the bus, because a UI sound set that is wired to nothing looks exactly
## like one that works.
func _assert_ui_sound() -> void:
	print("")
	print("  cue          peak on UI bus")
	print("  ------------ --------------")
	var quiet := 0
	for cue: StringName in ACAUISound.CUES:
		# SEVERAL TIMES, AND THE PEAK OF ALL OF THEM. Two of these clips are TEN
		# MILLISECONDS long, and a single one can fall entirely between two
		# mixer callbacks - which reads as silence and is not.
		var peak := -200.0
		for _shot in 5:
			AppUI.play_sound(cue)
			var t := 0.0
			while t < 0.45:
				await get_tree().process_frame
				t += get_process_delta_time()
				peak = maxf(peak, _peak_db(ACAAudioMix.UI))
		print("  %-12s %10.2f dBFS" % [String(cue), peak])
		if peak <= -60.0:
			quiet += 1
		await _wait_seconds(0.6)
	_check("every UI cue reaches the UI bus", quiet == 0)


func _bed_db(env: Node, bed_name: String) -> float:
	var player := env.get_node_or_null(NodePath(bed_name)) as AudioStreamPlayer
	return player.volume_db if player != null else -200.0


func _print_table() -> void:
	print("")
	print("  state                 Mower   Ambience  Weather   Master   ambience src")
	print("  ------------------- -------- --------- -------- -------- --------------")
	for label: String in _readings:
		var r: Dictionary = _readings[label]
		print("  %-19s %7.2f  %8.2f %8.2f %8.2f  %8.2f dB" % [
			label,
			r[ACAAudioMix.MOWER], r[ACAAudioMix.AMBIENCE],
			r[ACAAudioMix.WEATHER], r[ACAAudioMix.MASTER],
			r["ambience_player_db"]])
	print("")


# =============================================================== assertions

func _assert_mix(authored_ambience_db: float) -> void:
	# The one thing the old mix got permanently wrong.
	var after: float = _readings["clear again/mowing"]["ambience_player_db"]
	_check("Clear -> Rain -> Clear leaves the ambience at its authored level"
		+ " (%.2f -> %.2f dB)" % [authored_ambience_db, after],
		absf(after - authored_ambience_db) < 0.5)

	var ducked: float = _readings["rain/mowing"]["ambience_player_db"]
	_check("Rain ducks the ambience bed (%.2f dB)" % ducked,
		ducked < authored_ambience_db - 1.0)

	# Nothing may change a mower's source level because of the weather.
	var clear_mower: float = _readings["clear/mowing"][ACAAudioMix.MOWER]
	var rain_mower: float = _readings["rain/mowing"][ACAAudioMix.MOWER]
	_check("The mower's own level does not change with weather (%.2f vs %.2f dB)"
		% [clear_mower, rain_mower],
		absf(clear_mower - rain_mower) <= MOWER_WEATHER_DRIFT_MAX_DB)

	# Rain audible, engine still on top of it.
	var rain_bus: float = _readings["rain/mowing"][ACAAudioMix.WEATHER]
	var under := rain_mower - rain_bus
	_check("Rain sits under the engine by %.2f dB (want %.1f - %.1f)"
		% [under, RAIN_UNDER_MOWER_MIN_DB, RAIN_UNDER_MOWER_MAX_DB],
		under >= RAIN_UNDER_MOWER_MIN_DB and under <= RAIN_UNDER_MOWER_MAX_DB)

	_check("Rain is actually audible in the rain (%.2f dBFS)" % rain_bus,
		rain_bus > -40.0)
	_check("Rain is silent when it is not raining (%.2f dBFS)"
		% _readings["clear/mowing"][ACAAudioMix.WEATHER],
		_readings["clear/mowing"][ACAAudioMix.WEATHER] < -30.0)

	# The mower is the loudest thing while mowing, in every weather.
	for label: String in ["clear/mowing", "foggy/mowing", "rain/mowing"]:
		var r: Dictionary = _readings[label]
		_check("%s: the engine is the loudest element" % label,
			r[ACAAudioMix.MOWER] > r[ACAAudioMix.AMBIENCE]
			and r[ACAAudioMix.MOWER] > r[ACAAudioMix.WEATHER])

	for label: String in TARGETS:
		var wanted: Dictionary = TARGETS[label]
		for bus: String in wanted:
			var window: Array = wanted[bus]
			var value: float = _readings[label][StringName(bus)]
			_check("%s: %s peak %.2f dBFS inside [%.1f, %.1f]"
				% [label, bus, value, window[0], window[1]],
				value >= float(window[0]) and value <= float(window[1]))


# ================================================================== helpers

func _wait_for_screen(screen: int, max_frames: int = 900) -> void:
	var frames := 0
	while frames < max_frames:
		if GameSession.current_screen() == screen and not GameSession.is_changing_scene():
			return
		await get_tree().process_frame
		frames += 1


func _step(frames: int = 1) -> void:
	for _i in frames:
		await get_tree().process_frame


func _wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _check(what: String, ok: bool) -> void:
	if ok:
		_passes += 1
		print("[AUDIO] %s: PASS" % what)
	else:
		_failures += 1
		printerr("[AUDIO] %s: FAIL" % what)
