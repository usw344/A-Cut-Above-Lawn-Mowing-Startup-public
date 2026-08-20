@tool
class_name ACAPrecipitationRig
extends Node3D
## LAYERED RAIN, built entirely in code.
##
## Nothing is loaded from disk: the meshes, materials and process materials are
## constructed in `_ready()`. That is what makes this package portable — there
## is no particle scene to copy, no texture to license, and no path into a host
## project's asset tree.
##
## ---------------------------------------------------------------------------
## WHY A STREAK IS NOT A SCALED-UP DROP
## ---------------------------------------------------------------------------
##
## The obvious way to build distant rain is to take the near emitter and scale
## it. It is also the reason so much game rain looks like scratches on the film
## print: scaling a 0.2-unit ribbon by 24 gives a FIVE-METRE-WIDE white bar,
## and a screen full of them is a curtain, not weather.
##
## Distance is expressed here by ALPHA AND COUNT, never by size alone. The far
## layer is longer than the near layer, because perspective would otherwise
## shrink it to nothing — but it is also six times more transparent, so it
## reads as a veil of depth rather than as bars in front of the camera.
##
## ---------------------------------------------------------------------------
## ORIENTATION
## ---------------------------------------------------------------------------
##
## Every layer uses `TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY`, which points
## each particle's Y down its own velocity vector and turns its Z to face the
## camera. A streak is therefore always along the direction it is actually
## travelling, and wind tilts the rain for free: change the velocity and the
## visual follows, with no billboard fighting it.
##
## ---------------------------------------------------------------------------
## TRACKING
## ---------------------------------------------------------------------------
##
## `local_coords` is false on every layer, so moving this node moves the SPAWN
## VOLUME and leaves airborne drops where they are. Without that, rain visibly
## drags sideways whenever the player turns.
##
## The volume is also pushed AHEAD of the target by `lead_seconds` worth of its
## own measured velocity, because a target moving at 30 u/s outruns rain spawned
## directly overhead before it lands.
##
## ---------------------------------------------------------------------------
## AUDIO IS NOT INCLUDED
## ---------------------------------------------------------------------------
##
## This package deliberately bundles no sound. Hand it a player you own with
## `set_audio_player()` and it will fade it with the intensity; give it nothing
## and it stays silent.

## Emitted when the rig finishes fading to fully dry, so a host can release
## anything it was holding open for the weather.
signal became_dry()

@export_group("Intensity")
## 0 dry, 1 full. Eased towards, never snapped, unless `apply_immediate` is used.
@export_range(0.0, 1.0, 0.005) var intensity: float = 0.0: set = set_intensity
## Exponential approach per second. ~1.1 crosses in about two seconds.
@export var fade_speed: float = 1.1

@export_group("Tracking")
## Rain follows this. A camera reads better than a vehicle: the drops the
## player sees are the ones near the lens, not the ones near the machine.
@export var tracking_target: NodePath
## Seconds of the target's own velocity to lead the spawn volume by.
@export var lead_seconds: float = 0.45
## How far above the target the volume sits.
@export var height_offset: float = 7.0
## How far BELOW the tracking target the ground is. Splashes are placed here.
##
## Without it the splash emitter sits at the target's own origin, which for a
## camera is head height — and a 0.16-unit quad spawning a metre from the lens
## fills a quarter of the frame. A host that knows its terrain should set this;
## the default assumes a target at roughly eye level.
@export var ground_offset: float = -2.0

@export_group("Wind")
## World units per second of horizontal drift. Small: this tilts the streaks,
## and past about six the rain stops looking like it is falling.
@export var wind: Vector2 = Vector2(1.6, 0.8)
@export var fall_speed_min: float = 24.0
@export var fall_speed_max: float = 31.0

@export_group("Look")
@export var rain_color: Color = Color(0.80, 0.86, 0.95)

# ---------------------------------------------------------------- layer specs
#
# `[name, half_extent, height, amount, width, length, alpha, speed_scale]`
# Alpha falls with distance and length rises; see the header.
const LAYERS := [
	["Near", 9.0, 7.0, 420, 0.014, 0.36, 0.46, 1.00],
	["Mid", 26.0, 10.0, 860, 0.012, 0.30, 0.26, 0.94],
	["Far", 70.0, 15.0, 880, 0.026, 0.95, 0.10, 0.88],
]

var _layers: Array[GPUParticles3D] = []
var _splash: GPUParticles3D = null
var _target: Node3D = null
var _last_target_pos: Vector3 = Vector3.ZERO
var _target_velocity: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _current: float = 0.0
var _quality: ACAEnvQualityProfile = null
var _audio: AudioStreamPlayer = null
var _audio_base_db: float = 0.0
var _was_dry: bool = true

## Decibels the supplied player drops to when fully dry.
@export var audio_silent_db: float = -40.0


func _ready() -> void:
	_build()
	_apply_visibility()
	set_process(true)


# ======================================================================= build

func _build() -> void:
	for spec: Array in LAYERS:
		var p := _make_layer(spec)
		add_child(p)
		_layers.append(p)
	_splash = _make_splash()
	add_child(_splash)


func _make_layer(spec: Array) -> GPUParticles3D:
	var half: float = float(spec[1])
	var height: float = float(spec[2])
	var width: float = float(spec[4])
	var length: float = float(spec[5])
	var alpha: float = float(spec[6])
	var speed_scale: float = float(spec[7])

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(half, 0.6, half)
	# Gravity is zero on purpose. A constant velocity keeps every streak
	# perfectly straight and its Y-to-velocity alignment stable; acceleration
	# would curve the drop and make the streak fight its own orientation.
	proc.gravity = Vector3.ZERO
	proc.direction = Vector3(0, -1, 0)
	proc.spread = 3.0
	proc.initial_velocity_min = fall_speed_min * speed_scale
	proc.initial_velocity_max = fall_speed_max * speed_scale
	# Length and speed both vary a little, so the fall reads as many drops
	# rather than as one repeating pattern.
	proc.scale_min = 0.75
	proc.scale_max = 1.35

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(rain_color.r, rain_color.g, rain_color.b, alpha)
	mat.vertex_color_use_as_albedo = false
	mat.disable_receive_shadows = true
	mat.disable_ambient_light = true

	var quad := QuadMesh.new()
	quad.size = Vector2(width, length)
	quad.material = mat

	var p := GPUParticles3D.new()
	p.name = String(spec[0]) + " Rain"
	p.amount = int(spec[3])
	p.draw_pass_1 = quad
	p.process_material = proc
	# The whole point: Y down the velocity, Z to the camera.
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	# World space, so the emitter can be teleported without dragging drops.
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0, height, 0)
	# Long enough to carry the drop well below ground level, where the terrain
	# occludes it. Rain that stops at a horizontal line is worse than none.
	var travel := height + 8.0
	p.lifetime = travel / maxf(fall_speed_min * speed_scale, 1.0)
	p.explosiveness = 0.0
	p.randomness = 0.35
	p.amount_ratio = 0.0
	p.emitting = false
	p.visibility_aabb = AABB(
		Vector3(-half - 4.0, -travel - 4.0, -half - 4.0),
		Vector3(half * 2.0 + 8.0, travel + 8.0, half * 2.0 + 8.0))
	return p


## Short-lived ground impacts. A fourth emitter, and therefore a quality
## decision rather than part of the rain.
func _make_splash() -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(9.0, 0.05, 9.0)
	proc.gravity = Vector3.ZERO
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 8.0
	proc.initial_velocity_min = 0.4
	proc.initial_velocity_max = 1.1
	proc.scale_min = 0.5
	proc.scale_max = 1.0
	# A splash grows and fades. `scale_curve` wants a CurveTexture, not a Curve.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	proc.scale_curve = curve_tex

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(rain_color.r, rain_color.g, rain_color.b, 0.14)
	mat.disable_receive_shadows = true
	mat.disable_ambient_light = true

	var quad := QuadMesh.new()
	quad.size = Vector2(0.10, 0.10)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = mat

	var p := GPUParticles3D.new()
	p.name = "Splash"
	p.amount = 260
	p.lifetime = 0.42
	p.draw_pass_1 = quad
	p.process_material = proc
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.randomness = 0.6
	p.amount_ratio = 0.0
	p.emitting = false
	p.position = Vector3(0, ground_offset, 0)
	p.visibility_aabb = AABB(Vector3(-13, -2, -13), Vector3(26, 6, 26))
	return p


# ====================================================================== public

func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)


## Snap rather than fade. For scene load and save restore, where easing in from
## the previous scene's weather would be a visible glitch.
func apply_immediate(value: float) -> void:
	set_intensity(value)
	_current = intensity
	_push()


func current_intensity() -> float:
	return _current


func is_raining() -> bool:
	return _current > 0.002


func set_wind(value: Vector2) -> void:
	if wind.is_equal_approx(value):
		return
	wind = value
	_push_wind()


func set_tracking_target(node: Node3D) -> void:
	_target = node
	_has_last = false


func set_quality(profile: ACAEnvQualityProfile) -> void:
	_quality = profile
	_apply_visibility()


## OPTIONAL, and owned by the caller. This package ships no audio; see the
## header. The player's authored level is captured once and every fade is
## relative to it, so dry always returns to exactly the level it was given at.
func set_audio_player(player: AudioStreamPlayer) -> void:
	_audio = player
	if _audio != null:
		_audio_base_db = _audio.volume_db


func layer_count() -> int:
	return _layers.size()


## The emitters, for a host that needs to inspect or measure them.
func layers() -> Array[GPUParticles3D]:
	return _layers


# ===================================================================== running

func _process(delta: float) -> void:
	_track(delta)
	if not is_equal_approx(_current, intensity):
		_current = lerpf(_current, intensity, 1.0 - exp(-fade_speed * delta))
		if absf(_current - intensity) < 0.002:
			_current = intensity
		_push()
	var dry := _current <= 0.002
	if dry and not _was_dry:
		became_dry.emit()
	_was_dry = dry


func _track(delta: float) -> void:
	if _target == null and not tracking_target.is_empty():
		_target = get_node_or_null(tracking_target) as Node3D
	if _target == null or not is_instance_valid(_target):
		return
	var pos := _target.global_position
	if _has_last and delta > 0.0:
		# Measured, not read off a controller: this package has no idea what
		# kind of node it is following.
		var v := (pos - _last_target_pos) / delta
		_target_velocity = _target_velocity.lerp(v, 1.0 - exp(-6.0 * delta))
	_last_target_pos = pos
	_has_last = true

	var lead := _target_velocity * lead_seconds
	lead.y = 0.0
	global_position = pos + lead


func _push() -> void:
	var q_scale := 1.0 if _quality == null else _quality.rain_amount_scale
	for i in range(_layers.size()):
		var p := _layers[i]
		if not p.visible:
			continue
		p.amount_ratio = clampf(_current * q_scale, 0.0, 1.0)
		p.emitting = _current > 0.002
	if _splash != null and _splash.visible:
		_splash.amount_ratio = clampf(_current * q_scale, 0.0, 1.0)
		_splash.emitting = _current > 0.002
	if _audio != null:
		_audio.volume_db = lerpf(audio_silent_db, _audio_base_db, _current)


func _push_wind() -> void:
	for i in range(_layers.size()):
		var proc := _layers[i].process_material as ParticleProcessMaterial
		if proc == null:
			continue
		var speed_scale: float = float(LAYERS[i][7])
		var fall := -0.5 * (fall_speed_min + fall_speed_max) * speed_scale
		proc.direction = Vector3(wind.x, fall, wind.y).normalized()


## Quality decides how many WHOLE EMITTERS exist, not how full they are.
func _apply_visibility() -> void:
	var wanted := 3 if _quality == null else _quality.rain_layers
	for i in range(_layers.size()):
		var on := i < wanted
		_layers[i].visible = on
		if not on:
			_layers[i].emitting = false
			_layers[i].amount_ratio = 0.0
	if _splash != null:
		var splash_on := _quality != null and _quality.rain_splash
		_splash.visible = splash_on
		if not splash_on:
			_splash.emitting = false
	_push_wind()
	_push()
