extends Node
## DEVELOPMENT ONLY. Renders everything the gameplay expansion ADDED that has a
## picture, so it can be judged from pixels rather than from source.
##
##   godot --path . "res://Dev tools/Validation/Expansion Probe.tscn" \
##       -- "--expansion-output=<dir>"
##
## Needs a REAL renderer; it captures the viewport. Nothing here asserts - it
## produces images and a printed index of what each one is, and the judgement is
## made by looking at them.
##
## Four groups:
##
##   HUBS         each regional service lot, from the player's own camera and
##                from a low angle, at two levels of company growth.
##   PROPERTIES   a neglected property and the same property maintained, from
##                the SAME viewpoint; a conservation property with its planting;
##                and the minimap drawing the protected ground.
##   MACHINES     each attachment on the machine that carries it, and the three
##                mowing configurations mid-cut.
##   SCREENS      the service lot, the territory page, the operations board, the
##                agreements page and the portfolio.

const DEFAULT_OUTPUT_DIR := "user://expansion_probe"
const SETTLE := 26

var _dir: String = DEFAULT_OUTPUT_DIR
var _shots: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = _output_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	print("[EXPANSION PROBE] writing to %s" % _dir)
	_run.call_deferred()


func _output_dir() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--expansion-output="):
			return arg.trim_prefix("--expansion-output=")
	return DEFAULT_OUTPUT_DIR


func _run() -> void:
	GameSession.start_new_game()
	while GameSession.current_screen() != ACAGameSession.Screen.TOWN:
		await get_tree().process_frame
	# THE SKY MOVES ON ITS OWN NOW. A probe that runs for several game hours
	# photographs half its subjects through fog and the other half in rain,
	# which is a comparison of the weather rather than of the thing under
	# review. `set_weather()` takes the schedule until it is handed back - see
	# `ACAWorldClock.resume_scheduled_weather()`.
	WorldClock.set_weather("Clear")
	await _settle(40)

	await _shoot_hubs()
	await _shoot_properties()
	await _shoot_machines()
	await _shoot_screens()

	print("[EXPANSION PROBE] done, %d shots" % _shots)
	get_tree().quit(0)


# ======================================================================== hubs

## EVERY REGIONAL LOT, at two levels of company growth. The second is the whole
## point of the growth system: the plot the player has worked for a month has to
## look different from the one they just bought.
func _shoot_hubs() -> void:
	for region in ACAServiceTerritory.REGION_ORDER:
		if region == ACAServiceTerritory.HOME_REGION:
			continue
		Territory.dev_grant_region(region)
	for region in ACAServiceTerritory.REGION_ORDER:
		if region == ACAServiceTerritory.HOME_REGION:
			continue
		for presence in [ACAServiceTerritory.PRESENCE_START, 92.0]:
			Territory.dev_set_presence(region, presence)
			Territory.set_active_region(region)
			GameSession.go_to_town()
			await _wait_for_screen(ACAGameSession.Screen.TOWN)
			await _settle(46)
			var label := "%s-%s" % [
				String(ACAServiceTerritory.region_id(region)),
				"new" if presence < 40.0 else "established"]
			await _shot("hub-%s" % label)
			await _low_angle_shot("hub-%s-graze" % label)

	Territory.set_active_region(ACAServiceTerritory.HOME_REGION)
	GameSession.go_to_town()
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	await _settle(40)
	await _shot("hub-home_town")


## The hub from a low, close angle, which is where a procedural layout gives
## itself away: floating props, a road that does not meet its apron, a building
## standing off its own slab.
func _low_angle_shot(name: String) -> void:
	var scene := get_tree().current_scene
	var hub: Node3D = scene.call(&"hub") if scene.has_method(&"hub") else null
	if hub == null:
		return
	var camera := Camera3D.new()
	camera.near = 0.08
	camera.fov = 42.0
	hub.add_child(camera)
	camera.global_position = Vector3(-13.5, 1.4, 9.0)
	camera.look_at(Vector3(1.0, 0.6, -1.0), Vector3.UP)
	camera.make_current()
	await _settle(SETTLE)
	await _shot(name)
	camera.queue_free()
	await _settle(4)


# ================================================================== properties

## A NEGLECTED PROPERTY AND THE SAME PROPERTY MAINTAINED, from the same place.
## The pair is the whole payoff of the condition system and it is the one thing
## in this expansion that cannot be judged from a single image.
func _shoot_properties() -> void:
	var seed := _find_project_seed()
	for stage in [ACAPropertyCondition.Stage.NEGLECTED,
			ACAPropertyCondition.Stage.RECOVERY,
			ACAPropertyCondition.Stage.MAINTAINED]:
		var params := ACAPropertyParams.for_seed(seed, 144,
			ACAPropertyArchetype.Kind.SUBURBAN, stage)
		await _shoot_property(params, "property-condition-%d-%s"
			% [stage, ACAPropertyCondition.stage_name(stage).to_lower()])

	# ...and a property with protected planting on it.
	var conservation_seed := _find_conservation_seed()
	if conservation_seed > 0:
		var params := ACAPropertyParams.for_seed(conservation_seed, 144,
			ACAPropertyArchetype.Kind.PARK)
		await _shoot_property(params, "property-conservation")


## Build one property in an empty scene and photograph it from a fixed place, so
## two properties built from the same seed are two images of the same view.
func _shoot_property(params: ACAPropertyParams, name: String) -> void:
	# THE LIVE SCREEN IS STILL IN THE TREE. A property built at the origin shares
	# a world with whichever hub the probe was last standing in, and the first
	# renders showed exactly that: a small rectangle of roads and rooftops lying
	# in the middle of every lawn, which was the Business Town seen from above
	# through the property's own camera. It is hidden for the duration.
	var host := get_tree().current_scene as Node3D
	if host != null:
		host.visible = false
	# ...AND ITS WORLDENVIRONMENT WITH IT. Hiding a node does not switch its
	# environment off, and two of them in one tree is a fight nobody wins: the
	# first render taken this way came back as a white wash, because the hub's
	# own fog was still being applied to a scene that had its own sky.
	var host_env := _borrow_environment(host)
	var root := Node3D.new()
	get_tree().root.add_child(root)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(38.0), 0.0)
	light.light_energy = 1.25
	light.shadow_enabled = true
	root.add_child(light)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.29, 0.478, 0.729)
	sky_material.sky_horizon_color = Color(0.796, 0.851, 0.878)
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment = env
	root.add_child(environment)

	var property := ACAProperty.new()
	root.add_child(property)
	property.build(params)

	var lawn := property.lawn()
	var half := lawn.lawn_half_extent()
	var centre := lawn.lawn_centre()

	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.5
	camera.far = 4000.0
	root.add_child(camera)
	# FROM THE SEAT, at the arrival corner: the view the player actually gets,
	# and the one the difference between two conditions has to read from.
	var eye := Vector3(centre.x - half - 5.0, 0.0, centre.z - half * 0.35)
	eye.y = property.ground_height_at(eye.x, eye.z) + 3.2
	camera.global_position = eye
	camera.look_at(Vector3(centre.x + half * 0.2, centre.y, centre.z), Vector3.UP)
	camera.make_current()
	await _settle(52)
	await _shot(name)

	# ...and from above, where a conservation zone's shape reads.
	camera.global_position = Vector3(centre.x, centre.y + half * 1.5, centre.z + half * 0.9)
	camera.look_at(centre, Vector3.UP)
	await _settle(SETTLE)
	await _shot("%s-above" % name)

	print("[EXPANSION PROBE] %s: %d mowable, %d protected"
		% [name, lawn.total_item_count(), lawn.protected_cell_count()])
	root.queue_free()
	if host != null:
		host.visible = true
	_return_environment(host_env)
	await _settle(6)


# ==================================================================== machines

## EVERY ATTACHMENT ON THE MACHINE IT FITS, and the three configurations. Shot
## against a plain property so the geometry is the subject.
func _shoot_machines() -> void:
	var host := get_tree().current_scene as Node3D
	if host != null:
		host.visible = false
	# ...AND ITS WORLDENVIRONMENT WITH IT. Hiding a node does not switch its
	# environment off, and two of them in one tree is a fight nobody wins: the
	# first render taken this way came back as a white wash, because the hub's
	# own fog was still being applied to a scene that had its own sky.
	var host_env := _borrow_environment(host)
	var root := Node3D.new()
	get_tree().root.add_child(root)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(52.0), 0.0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	root.add_child(light)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.52, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.72)
	env.ambient_light_energy = 0.8
	environment.environment = env
	root.add_child(environment)

	var camera := Camera3D.new()
	camera.fov = 40.0
	root.add_child(camera)
	camera.make_current()

	# THE BAGGER IS NOT IN THIS LIST because it has no geometry of its own: every
	# canonical machine's model already carries a catcher. See
	# `ACAAttachments.CATALOG`.
	for pair in [["rider", &"chute_only"], ["rider", &"striping_roller"],
			["rider", &"tow_sweeper"], ["powered", &"striping_roller"],
			["powered", &"chute_only"], ["push", &"striping_roller"]]:
		var mower_id := String(pair[0])
		var attachment := StringName(pair[1])
		var fitted: Array = []
		if attachment == &"chute_only":
			fitted = [&"discharge_chute"]
			attachment = &"discharge_chute"
		else:
			fitted = [attachment]
		var machine := _spawn_mower(root, mower_id)
		if machine == null:
			continue
		ACAMowerAttachment.fit_to(machine, fitted)
		camera.make_current()
		# BEHIND AND TO ONE SIDE, far enough back to hold the whole machine. The
		# canonical rider is about six units long and the first framing put the
		# lens two units off its seat, which photographed a steering wheel.
		# Local +Z is forward on every machine, so an attachment hangs at -Z.
		camera.global_position = machine.global_position \
			+ Vector3(11.0, 6.0, -13.0)
		camera.look_at(machine.global_position + Vector3(0.0, 0.8, -2.0), Vector3.UP)
		await _settle(SETTLE)
		await _shot("machine-%s-%s" % [mower_id, String(attachment)])
		machine.queue_free()
		await _settle(4)

	root.queue_free()
	if host != null:
		host.visible = true
	_return_environment(host_env)
	await _settle(6)


## Take the live screen's environment away for the duration of a shot, and give
## it back afterwards. Returns the node it was taken from, or null.
func _borrow_environment(host: Node) -> WorldEnvironment:
	var found := _find_environment(host)
	if found == null:
		return null
	_host_env_backup = found.environment
	found.environment = null
	return found


func _return_environment(holder: WorldEnvironment) -> void:
	if holder != null and is_instance_valid(holder):
		holder.environment = _host_env_backup
	_host_env_backup = null


var _host_env_backup: Environment = null


func _find_environment(host: Node) -> WorldEnvironment:
	if host == null:
		return null
	for node in host.find_children("*", "WorldEnvironment", true, false):
		return node as WorldEnvironment
	return null


func _spawn_mower(parent: Node3D, mower_id: String) -> Node3D:
	const SCENES := {
		"rider": "res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn",
		"powered": "res://Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn",
		"push": "res://Assets/Vehicles and Mowers/Mowers/Push Mower.tscn",
	}
	var packed := load(String(SCENES.get(mower_id, ""))) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	parent.add_child(node)
	node.global_position = Vector3.ZERO
	# The machines are physics bodies; they must not fall out of the shot.
	if node is CharacterBody3D:
		(node as CharacterBody3D).set_physics_process(false)
	# EVERY CANONICAL MOWER CARRIES ITS OWN CAMERA, and it takes the viewport
	# the moment the machine enters the tree - which is why the first framing
	# here had no effect at all: the shots were being taken through the driver's
	# eyes rather than through the probe's lens.
	for camera in node.find_children("*", "Camera3D", true, false):
		(camera as Camera3D).current = false
	return node


# ===================================================================== screens

## THE FIVE PAGES the expansion added to the town's counters. Rendered by
## opening the real panel on the real screen, not by building a mock.
func _shoot_screens() -> void:
	Territory.set_active_region(ACAServiceTerritory.HOME_REGION)
	Business.dev_set_reputation(78.0)
	Equipment.dev_grant_attachment(&"mulch_kit")
	Equipment.dev_grant_attachment(&"discharge_chute")
	Equipment.dev_grant_attachment(&"striping_roller")
	Equipment.dev_grant_trailer(&"transporter")
	Equipment.dev_grant_autonomous("auto_grounds")
	Territory.dev_set_presence(ACAServiceTerritory.Region.HOME_TOWN, 74.0)
	Agreements.dev_force_offer(ACAServiceTerritory.Region.HOME_TOWN)

	GameSession.go_to_town()
	await _wait_for_screen(ACAGameSession.Screen.TOWN)
	await _settle(40)

	var scene := get_tree().current_scene
	var services := _open_services(scene)
	if services == null:
		print("[EXPANSION PROBE] could not reach the services panel")
		return

	services.open_service(&"service_lot")
	await _settle(20)
	await _shot("screen-service-lot")

	services.open_service(&"business_hq")
	for page in [&"territories", &"operations", &"agreements", &"portfolio"]:
		services.set(&"_office_tab", page)
		services.call(&"_refresh")
		await _settle(20)
		await _shot("screen-office-%s" % String(page))

	services.open_service(&"mower_dealer")
	services.set(&"_workshop_tab", &"attachments")
	services.call(&"_refresh")
	await _settle(20)
	await _shot("screen-attachment-shop")
	services.close()


## The town builds its services panel on first use; this is the same door the
## player's click goes through.
func _open_services(scene: Node) -> ACABusinessServices:
	if scene == null or not scene.has_method(&"_ensure_services"):
		return null
	return scene.call(&"_ensure_services") as ACABusinessServices


# ===================================================================== helpers

func _find_project_seed() -> int:
	for seed in range(1, 900):
		if ACAPropertyCondition.is_project_site(seed,
				ACAJobEnums.PropertyType.RESIDENTIAL):
			return seed
	return 1


func _find_conservation_seed() -> int:
	for seed in range(1, 400):
		var params := ACAPropertyParams.for_seed(seed, 144,
			ACAPropertyArchetype.Kind.PARK)
		if ACAConservationZone.for_params(params, Vector2.ZERO, null).count() > 0:
			return seed
	return 0


func _wait_for_screen(screen: int) -> void:
	var guard := 0
	while GameSession.current_screen() != screen or GameSession.is_changing_scene():
		await get_tree().process_frame
		guard += 1
		if guard > 900:
			return


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	image.save_png("%s/%s.png" % [_dir, name])
	_shots += 1
	print("[EXPANSION PROBE] %s" % name)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
