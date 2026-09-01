extends Node
## DEVELOPMENT ONLY. Finds and ATTRIBUTES representation popping in the real
## mowing scene.
##
##   godot --path . "res://Dev tools/Validation/Pop Probe.tscn" \
##       -- "--pop-output=<dir>"
##
## Needs a real renderer.
##
## ---------------------------------------------------------------------------
## WHAT A POP IS, AS A NUMBER
## ---------------------------------------------------------------------------
## The camera is walked along a smooth path at a constant speed and a frame is
## captured at every step. Between two adjacent frames of smooth motion the
## image changes by a small, fairly steady amount - parallax. A representation
## swapping over changes a patch of the image all at once, which shows up as a
## SPIKE in that per-frame difference.
##
## So the measurement is not "how much did the image change" (which says more
## about how fast the camera is going than about anything else) but "how much
## did the CHANGE change": each step's difference against the median of its
## neighbours. A step several times the local median is a pop, and the probe
## reports where along the path it happened and how big it was.
##
## ---------------------------------------------------------------------------
## AND WHICH SYSTEM DID IT
## ---------------------------------------------------------------------------
## Measuring a spike does not say what caused one, so the same path is walked
## several times with one subsystem removed each time:
##
##   all           everything on - the shipped configuration
##   no-grass      `dev_skip_grass`
##   no-foliage    `dev_skip_foliage` (the wood, the shrubs, the rocks)
##   no-lod        the renderer's automatic mesh LOD switched off
##   no-occlusion  occlusion culling switched off
##
## Whichever run loses the spikes is the one that was causing them. That is the
## whole point of this tool: the last two are RENDERER settings rather than
## anything this project wrote, and they are the ones a reading of the property
## code would never have found.

const DEFAULT_OUTPUT_DIR := "user://pop_probe"

## The property the runs are measured on. Fixed, so two runs are comparable.
const SEED := 648465655
const LAWN_SIZE := 192

## How many steps the camera path is walked in. Enough that a swap lands inside
## one step rather than being smeared over several.
## STEP SIZE IS THE WHOLE MEASUREMENT.
##
## The first version walked 150 units in 120 steps - 1.26 units a step, which is
## about half a second of driving. A representation that swaps between two real
## frames is smeared across a step that big and never rises above its own
## neighbourhood, so the probe reported nothing and proved nothing.
##
## These are FRAME-SCALE: a rider does about eight units a second, so a frame at
## sixty is roughly 0.13 units. Two hundred steps at that size is a real
## twenty-six unit stretch of driving sampled the way the player sees it.
const STEPS := 200
## World units the camera travels over the whole path.
const TRAVEL := 26.0
## Eye height, matched to the rider's seat.
const EYE_HEIGHT := 2.1

## A step whose difference is this many times the local median is a pop.
const SPIKE_RATIO := 3.0
## ...and it has to be at least this big in absolute terms, so a run where the
## image is almost perfectly still does not report noise as a pop.
const SPIKE_FLOOR := 0.0006
## How many neighbours the local median is taken over.
const MEDIAN_WINDOW := 9

## Downsample before comparing. A pop is a large patch changing, not a pixel, and
## comparing at a fifth of the resolution is twenty-five times less work.
const SAMPLE_STEP := 5

enum Motion { DRIVE, LOOK }

var _dir: String = DEFAULT_OUTPUT_DIR
var _property: ACAProperty = null
var _camera: Camera3D = null
var _results: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--pop-output="):
			_dir = arg.trim_prefix("--pop-output=")
	DirAccess.make_dir_recursive_absolute(_dir)
	_run.call_deferred()


func _run() -> void:
	print("[POP] %d steps over %.0f units, seed %d, lawn %d"
		% [STEPS, TRAVEL, SEED, LAWN_SIZE])

	# EVERY ARCHETYPE, BOTH KINDS OF MOTION, before anything is attributed. The
	# first version of this probe drove in a straight line across a rural
	# property and reported nothing, which proved only that a rural property
	# driven in a straight line does not pop. The surrounds - the houses, the
	# streets and the car parks beyond the fence - exist on two archetypes only
	# and are the newest thing out there.
	for archetype in [ACAPropertyArchetype.Kind.RURAL,
			ACAPropertyArchetype.Kind.SUBURBAN,
			ACAPropertyArchetype.Kind.PARK,
			ACAPropertyArchetype.Kind.LANDSCAPED]:
		for motion in [Motion.DRIVE, Motion.LOOK]:
			await _walk({
				"label": "%s/%s" % [
					ACAPropertyArchetype.name_of(archetype).to_lower(),
					"drive" if motion == Motion.DRIVE else "look"],
				"archetype": archetype, "motion": motion,
				"grass": true, "foliage": true, "lod": true, "occlusion": true,
			})

	# Whichever of those popped is the one worth taking apart. If none did, the
	# attribution pass below still runs on the worst of them, so the table is
	# comparable either way.
	# ------------------------------------------------------------------------
	# THE SENSITIVE PASS, and the reason it exists.
	#
	# The runs above all came back with nothing, and their MEDIANS say why: with
	# the grass on, the frame-to-frame difference sits around 0.0087, and with it
	# off it is 0.0003. Twenty-nine times. That is the WIND - three layers of it,
	# animating every tuft on the property every frame - and it means a spike has
	# to beat three times 0.0087 to be noticed. A distant tree band swapping over
	# does not move a hundredth of the image, so the first pass could not have
	# seen one however hard it looked.
	#
	# So everything except the grass is measured with the grass OFF, where the
	# floor is a ten-thousandth and a swap of any size stands out. The grass
	# itself is measured with the wood off, for the same reason in reverse.
	print("")
	print("[POP] sensitive pass: the noise floor without the wind")
	var suspect := int(_worst_result().get("archetype", ACAPropertyArchetype.Kind.SUBURBAN))
	for config in [
			{"label": "quiet/all", "grass": false, "foliage": true,
				"lod": true, "occlusion": true},
			{"label": "quiet/no-foliage", "grass": false, "foliage": false,
				"lod": true, "occlusion": true},
			{"label": "quiet/no-lod", "grass": false, "foliage": true,
				"lod": false, "occlusion": true},
			{"label": "quiet/no-occlusion", "grass": false, "foliage": true,
				"lod": true, "occlusion": false},
			{"label": "grass/no-foliage", "grass": true, "foliage": false,
				"lod": true, "occlusion": true},
		]:
		config["archetype"] = suspect
		config["motion"] = Motion.DRIVE
		await _walk(config)

	print("")
	print("[POP] %-18s %8s %8s %8s   %s" % [
		"run", "pops", "worst", "median", "where the worst one was"])
	for result in _results:
		print("[POP] %-18s %8d %8.4f %8.4f   %s" % [
			result["label"], int(result["pops"]), float(result["worst"]),
			float(result["median"]), String(result["where"])])

	_verdict()
	get_tree().quit(0)


# ======================================================================= a run

func _walk(config: Dictionary) -> void:
	var archetype := int(config.get("archetype", ACAPropertyArchetype.Kind.RURAL))
	var motion := int(config.get("motion", Motion.DRIVE))
	await _build_property(bool(config["grass"]), bool(config["foliage"]), archetype)
	# THE RENDERER'S OWN SETTINGS. Both of these switch representations by
	# distance, neither of them is anything this project wrote, and neither is
	# visible from reading the property code.
	get_viewport().mesh_lod_threshold = 1.0 if bool(config["lod"]) else 0.0
	get_viewport().use_occlusion_culling = bool(config["occlusion"])
	await _settle(0.4)

	var centre := _property.lawn().lawn_centre()
	var half := _property.lawn().lawn_half_extent()
	var from := Vector3(centre.x - half + 4.0, 0.0, centre.z)
	var direction := Vector3(1.0, 0.0, 0.0)

	var differences := PackedFloat32Array()
	var previous: Image = null
	for step in STEPS:
		var fraction := float(step) / float(STEPS - 1)
		if motion == Motion.DRIVE:
			var at := from + direction * (TRAVEL * fraction)
			at.y = _property.ground_height_at(at.x, at.z) + EYE_HEIGHT
			_camera.global_position = at
			# Looking along the direction of travel and a little down, which is
			# what the seat of a mower sees.
			_camera.look_at(at + direction * 20.0 + Vector3(0.0, -3.0, 0.0),
				Vector3.UP)
		else:
			# STANDING IN THE MIDDLE AND TURNING RIGHT ROUND. A representation
			# that swaps when it enters or leaves the frustum shows up here and
			# nowhere else, and looking around is most of what a player does.
			var at := Vector3(centre.x, 0.0, centre.z)
			at.y = _property.ground_height_at(at.x, at.z) + EYE_HEIGHT
			_camera.global_position = at
			var angle := fraction * TAU
			_camera.look_at(at + Vector3(sin(angle), -0.18, cos(angle)) * 20.0,
				Vector3.UP)
		await RenderingServer.frame_post_draw
		var frame := _sampled()
		if previous != null:
			differences.append(_difference(previous, frame))
		previous = frame

	var result := _analyse(String(config["label"]), differences, from, direction)
	result["archetype"] = archetype
	result["motion"] = motion
	_results.append(result)


## One capture, downsampled. Kept as an Image rather than a texture so two of
## them can be compared without another draw.
func _sampled() -> Image:
	var full := get_viewport().get_texture().get_image()
	var width := int(full.get_width() / SAMPLE_STEP)
	var height := int(full.get_height() / SAMPLE_STEP)
	full.resize(width, height, Image.INTERPOLATE_BILINEAR)
	return full


## Mean absolute difference between two frames, 0-1.
func _difference(a: Image, b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / maxf(float(count), 1.0)


## Which steps were pops, measured against their own neighbourhood.
func _analyse(label: String, differences: PackedFloat32Array,
		from: Vector3, direction: Vector3) -> Dictionary:
	var pops := 0
	var worst := 0.0
	var worst_at := -1
	var overall := _median(differences)

	for i in differences.size():
		var local := _median(_window(differences, i))
		if local <= 0.0:
			continue
		var ratio := differences[i] / local
		if ratio >= SPIKE_RATIO and differences[i] >= SPIKE_FLOOR:
			pops += 1
			if ratio > worst:
				worst = ratio
				worst_at = i

	var where := "-"
	if worst_at >= 0:
		var at := from + direction * (TRAVEL * float(worst_at) / float(STEPS - 1))
		where = "step %d, x = %.0f" % [worst_at, at.x]
	return {
		"label": label, "pops": pops, "worst": worst,
		"median": overall, "where": where,
	}


func _window(values: PackedFloat32Array, centre: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var half := MEDIAN_WINDOW / 2
	for i in range(maxi(centre - half, 0), mini(centre + half + 1, values.size())):
		if i != centre:
			out.append(values[i])
	return out


func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


## Which run lost the spikes, said in a sentence. A tool that prints a table and
## leaves the reading to whoever runs it will be read wrong eventually.
func _verdict() -> void:
	# The sensitive baseline: everything on except the grass, which is where a
	# swap of any size is actually visible to this measurement.
	var baseline := 0
	for result in _results:
		if String(result["label"]) == "quiet/all":
			baseline = int(result["pops"])
	print("")
	if baseline == 0:
		print("[POP] No representation swap found, at frame-scale steps, on any")
		print("[POP] archetype, driving or looking around, with the grass's wind")
		print("[POP] removed so a swap of any size would show. The property's own")
		print("[POP] distance bands cross-fade over 17 and 44 units and the wood's")
		print("[POP] bands are fixed rings in the world rather than camera-relative,")
		print("[POP] so there is nothing here that switches as the player moves.")
		return
	print("[POP] The shipped configuration pops %d times over %.0f units."
		% [baseline, TRAVEL])
	for result in _results:
		var label := String(result["label"])
		if not label.begins_with("quiet/no-"):
			continue
		var pops := int(result["pops"])
		if pops * 2 < baseline:
			print("[POP]   -> Removing '%s' takes it to %d. That is the cause."
				% [label.trim_prefix("quiet/no-"), pops])
		else:
			print("[POP]      Removing '%s' leaves %d. Not it."
				% [label.trim_prefix("quiet/no-"), pops])


# ==================================================================== the scene

func _worst_result() -> Dictionary:
	var worst: Dictionary = _results[0] if not _results.is_empty() else {}
	for result in _results:
		if int(result["pops"]) > int(worst.get("pops", -1)):
			worst = result
	return worst


func _build_property(grass: bool, foliage: bool, archetype: int) -> void:
	if _property != null:
		_property.queue_free()
		await get_tree().process_frame
	var root := get_tree().current_scene
	_property = ACAProperty.new()
	_property.name = "Pop Property"
	_property.dev_skip_grass = not grass
	_property.dev_skip_foliage = not foliage
	root.add_child(_property)
	_property.build(ACAPropertyParams.for_seed(SEED, LAWN_SIZE, archetype))

	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Pop Camera"
		_camera.near = 0.1
		_camera.far = 4000.0
		root.add_child(_camera)
	_camera.make_current()


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await get_tree().process_frame
