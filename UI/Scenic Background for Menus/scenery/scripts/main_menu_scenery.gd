@tool
class_name MainMenuScenery
extends Node3D

## Camera framing and terrain grounding are kept deterministic so this scene can
## be transferred without relying on editor-only transforms.

@export var camera_position := Vector3(0.0, 2.75, 14.2):
	set(value):
		camera_position = value
		_queue_refresh()

@export var camera_target := Vector3(1.15, 2.25, -2.0):
	set(value):
		camera_target = value
		_queue_refresh()

@export var ground_vegetation := true:
	set(value):
		ground_vegetation = value
		_queue_refresh()

@export_group("Ambient Camera Motion")
@export var camera_drift_enabled := true:
	set(value):
		camera_drift_enabled = value
		_update_processing()

@export_range(0.0, 0.25, 0.005) var camera_drift_speed := 0.035
@export var camera_position_drift := Vector3(0.055, 0.015, 0.035)
@export var camera_target_drift := Vector3(0.075, 0.025, 0.045)

@export_group("Crepuscular Rays")
@export_range(0.0001, 0.003, 0.0001) var crepuscular_ray_density := 0.0005:
	set(value):
		crepuscular_ray_density = value
		_queue_environment_refresh()

@export_range(0.0, 1.0, 0.01) var crepuscular_ray_anisotropy := 0.72:
	set(value):
		crepuscular_ray_anisotropy = value
		_queue_environment_refresh()

@export_range(16.0, 96.0, 1.0) var crepuscular_ray_length := 58.0:
	set(value):
		crepuscular_ray_length = value
		_queue_environment_refresh()

@export_range(0.0, 500.0, 5.0) var crepuscular_ray_sun_energy := 125.0:
	set(value):
		crepuscular_ray_sun_energy = value
		_queue_environment_refresh()

var _camera_drift_time := 0.0


func _ready() -> void:
	_refresh_layout()
	_configure_environment()
	_update_processing()



func _process(delta: float) -> void:
	if not camera_drift_enabled:
		return
	_camera_drift_time = fmod(_camera_drift_time + delta, 10000.0)
	var phase := _camera_drift_time * TAU * camera_drift_speed
	var position_offset := Vector3(
		sin(phase) * camera_position_drift.x,
		sin(phase * 0.73 + 1.1) * camera_position_drift.y,
		cos(phase * 0.61 + 0.4) * camera_position_drift.z
	)
	var target_offset := Vector3(
		cos(phase * 0.79 + 0.7) * camera_target_drift.x,
		sin(phase * 0.53 + 2.0) * camera_target_drift.y,
		sin(phase * 0.67 + 0.2) * camera_target_drift.z
	)
	_apply_camera_frame(camera_position + position_offset, camera_target + target_offset)


func _queue_refresh() -> void:
	if is_inside_tree():
		_refresh_layout.call_deferred()


func _queue_environment_refresh() -> void:
	if is_inside_tree():
		_configure_environment.call_deferred()


func _refresh_layout() -> void:
	_apply_camera_frame(camera_position, camera_target)

	if not ground_vegetation:
		return
	_ground_descendants(self)


func _apply_camera_frame(position: Vector3, target: Vector3) -> void:
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.look_at_from_position(position, target)


func _configure_environment() -> void:
	var world_environment := get_node_or_null("Sky3D") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	var environment := world_environment.environment
	# Screen-space contact depth helps the simple supplied meshes sit together
	# without changing or restructuring any imported asset.
	environment.ssao_enabled = true
	environment.ssao_radius = 1.35
	environment.ssao_intensity = 1.25
	environment.ssao_power = 1.15
	environment.ssao_detail = 0.62
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color(0.55, 0.60, 0.61, 1.0)
	environment.fog_light_energy = 0.72
	environment.fog_density = 0.42
	environment.fog_depth_begin = 24.0
	environment.fog_depth_end = 145.0
	environment.fog_depth_curve = 1.25
	environment.fog_aerial_perspective = 0.46
	environment.fog_sky_affect = 0.18
	environment.fog_sun_scatter = 0.07
	# A very light participating medium lets the directional sun and the saved
	# canopy shadow maps form restrained crepuscular rays. Keeping ambient
	# injection low preserves their definition without washing out the menu.
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = crepuscular_ray_density
	environment.volumetric_fog_albedo = Color(0.93, 0.86, 0.72, 1.0)
	environment.volumetric_fog_emission = Color(0.0, 0.0, 0.0, 1.0)
	environment.volumetric_fog_emission_energy = 0.0
	environment.volumetric_fog_ambient_inject = 0.02
	environment.volumetric_fog_gi_inject = 0.0
	environment.volumetric_fog_anisotropy = crepuscular_ray_anisotropy
	environment.volumetric_fog_length = crepuscular_ray_length
	environment.volumetric_fog_detail_spread = 2.0
	environment.volumetric_fog_sky_affect = 0.08
	environment.volumetric_fog_temporal_reprojection_enabled = true
	environment.volumetric_fog_temporal_reprojection_amount = 0.80
	environment.glow_enabled = true
	environment.glow_intensity = 0.14
	environment.glow_bloom = 0.06
	environment.glow_hdr_threshold = 1.15
	environment.glow_hdr_scale = 1.3
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.0
	environment.adjustment_saturation = 0.89

	var sun := get_node_or_null("Sky3D/SunLight") as DirectionalLight3D
	if sun != null:
		sun.light_volumetric_fog_energy = crepuscular_ray_sun_energy
	var moon := get_node_or_null("Sky3D/MoonLight") as DirectionalLight3D
	if moon != null:
		moon.light_volumetric_fog_energy = 0.0
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null:
		fill.light_volumetric_fog_energy = 0.0


func _update_processing() -> void:
	set_process(camera_drift_enabled and not Engine.is_editor_hint())


func reset_camera_drift() -> void:
	_camera_drift_time = 0.0
	_apply_camera_frame(camera_position, camera_target)


func _ground_descendants(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and child.is_in_group("scenery_grounded"):
			var anchor := child as Node3D
			var offset := float(anchor.get_meta("ground_offset", 0.0))
			anchor.position.y = terrain_height(Vector2(anchor.position.x, anchor.position.z)) + offset
		_ground_descendants(child)


static func terrain_height(point: Vector2) -> float:
	var local_roll := sin(point.x * 0.105 + 0.65) * 0.24
	local_roll += cos(point.y * 0.085 - 0.55) * 0.22
	var crossing_roll := sin((point.x + point.y) * 0.045) * 0.38
	crossing_roll += cos((point.x - point.y) * 0.061) * 0.19
	var distant_rise := smoothstep(3.0, 32.0, -point.y) * 1.4
	var surface_relief := (_soil_noise(point * 0.45) - 0.5) * 0.12
	surface_relief += (_value_noise(point * 1.2 + Vector2(19.7, 19.7)) - 0.5) * 0.035
	return local_roll + crossing_roll + distant_rise + surface_relief


static func _soil_noise(point: Vector2) -> float:
	return (
		_value_noise(point) * 0.58
		+ _value_noise(point * 2.07 + Vector2(13.4, 13.4)) * 0.29
		+ _value_noise(point * 4.13 - Vector2(7.1, 7.1)) * 0.13
	)


static func _value_noise(point: Vector2) -> float:
	var cell := Vector2(floor(point.x), floor(point.y))
	var fraction := point - cell
	fraction = fraction * fraction * (Vector2(3.0, 3.0) - fraction * 2.0)
	var a := _hash21(cell)
	var b := _hash21(cell + Vector2(1.0, 0.0))
	var c := _hash21(cell + Vector2(0.0, 1.0))
	var d := _hash21(cell + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, fraction.x), lerpf(c, d, fraction.x), fraction.y)


static func _hash21(point: Vector2) -> float:
	var warped := Vector2(
		_fract(point.x * 123.34),
		_fract(point.y * 456.21)
	)
	var offset := warped.dot(warped + Vector2(45.32, 45.32))
	warped += Vector2(offset, offset)
	return _fract(warped.x * warped.y)


static func _fract(value: float) -> float:
	return value - floor(value)
