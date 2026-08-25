class_name ACAAmbientLife
extends Node3D
## ROLE
## The two small things that make an outdoor scene feel occupied rather than
## rendered: pollen drifting in the light, and a few insects near the ground.
##
## ---------------------------------------------------------------------------
## IT IS SUPPOSED TO BE ALMOST INVISIBLE
## ---------------------------------------------------------------------------
## A player who notices these has been shown too many of them. What they are for
## is the moment a still frame stops looking still: sixty motes in a box a few
## metres across, moving slowly enough that nothing crosses the frame, and a
## dozen specks flicking about at knee height.
##
## They FOLLOW the camera rather than being scattered over the property. Filling
## a hundred and eighty metres of lawn with pollen would cost thousands of
## particles to achieve the same look, and every one of them out of frame.
##
## ---------------------------------------------------------------------------
## NOT A WEATHER SYSTEM
## ---------------------------------------------------------------------------
## This does not read the weather, the time of day or the season, and it should
## not learn to. `Weather/` owns all of that, and a second thing with an opinion
## about what the sky is doing is how two systems start disagreeing. The one
## concession is that a host can switch it off, which is what the rain does.
##
## PUBLIC API
##   follow(target: Node3D)
##   set_enabled(value)
##   set_density(scale)        0 - 1, from the graphics setting
##
## SIGNALS: None.
##
## INVARIANTS
##   * No gameplay. No collision. No save state.
##
## PERSISTENCE OWNERSHIP: None.

## Deliberately small. See the note above.
const POLLEN_COUNT := 60
const INSECT_COUNT := 14

## How far around the camera each is scattered, in world units.
const POLLEN_EXTENT := 9.0
const INSECT_EXTENT := 5.0

## How quickly the emitters catch up to the camera. Slower than the machine, so
## motes drift PAST the player as they drive rather than being carried along
## with them - which is the difference between air and a swarm.
const FOLLOW_SMOOTHING := 1.6

var _target: Node3D = null
var _pollen: GPUParticles3D = null
var _insects: GPUParticles3D = null
var _density := 1.0
var _enabled := true


func _ready() -> void:
	_build()
	set_process(true)


func follow(target: Node3D) -> void:
	_target = target
	if target != null:
		global_position = target.global_position


func set_enabled(value: bool) -> void:
	_enabled = value
	_apply()


## From the player's graphics setting. Below about a third the effect stops
## being subtle and starts being sparse, so low turns it off outright rather
## than showing four motes.
func set_density(scale: float) -> void:
	_density = clampf(scale, 0.0, 1.0)
	_apply()


func _apply() -> void:
	var on := _enabled and _density > 0.34
	if _pollen != null:
		_pollen.emitting = on
		_pollen.amount = maxi(int(round(POLLEN_COUNT * _density)), 1)
	if _insects != null:
		_insects.emitting = on
		_insects.amount = maxi(int(round(INSECT_COUNT * _density)), 1)


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var blend: float = 1.0 - exp(-FOLLOW_SMOOTHING * delta)
	global_position = global_position.lerp(_target.global_position, blend)


func _build() -> void:
	_pollen = GPUParticles3D.new()
	_pollen.name = "Pollen"
	_pollen.amount = POLLEN_COUNT
	_pollen.lifetime = 11.0
	_pollen.preprocess = 11.0
	_pollen.randomness = 1.0
	_pollen.fixed_fps = 20
	_pollen.local_coords = false
	_pollen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pollen.visibility_aabb = AABB(
		Vector3(-POLLEN_EXTENT, -3.0, -POLLEN_EXTENT),
		Vector3(POLLEN_EXTENT * 2.0, 12.0, POLLEN_EXTENT * 2.0))
	_pollen.process_material = _pollen_material()
	# SMALLER AND FAINTER than the first attempt. At 0.035 units and 42% alpha
	# they read as white specks on the screen rather than as anything in the
	# air, which the first menu render showed clearly against the sky.
	_pollen.draw_pass_1 = _mote_mesh(0.020, Color(1.0, 0.969, 0.827, 0.26))
	add_child(_pollen)

	_insects = GPUParticles3D.new()
	_insects.name = "Insects"
	_insects.amount = INSECT_COUNT
	_insects.lifetime = 6.5
	_insects.preprocess = 6.5
	_insects.randomness = 1.0
	_insects.fixed_fps = 24
	_insects.local_coords = false
	_insects.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_insects.visibility_aabb = AABB(
		Vector3(-INSECT_EXTENT, -2.0, -INSECT_EXTENT),
		Vector3(INSECT_EXTENT * 2.0, 6.0, INSECT_EXTENT * 2.0))
	_insects.process_material = _insect_material()
	_insects.draw_pass_1 = _mote_mesh(0.019, Color(0.106, 0.114, 0.086, 0.72))
	add_child(_insects)
	_apply()


func _pollen_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(POLLEN_EXTENT, 3.4, POLLEN_EXTENT)
	# A DRIFT, not a fall. Barely any gravity, barely any speed, and a slow
	# turbulence so no two motes take the same line.
	m.direction = Vector3(0.4, 0.15, 0.2).normalized()
	m.spread = 60.0
	m.initial_velocity_min = 0.06
	m.initial_velocity_max = 0.22
	m.gravity = Vector3(0.0, -0.035, 0.0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.14
	m.turbulence_noise_scale = 1.6
	m.turbulence_noise_speed = Vector3(0.06, 0.03, 0.05)
	m.scale_min = 0.6
	m.scale_max = 1.5
	# In and out at both ends: a mote that appears is a mote that gets noticed.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.18, Color(1, 1, 1, 1))
	ramp.add_point(0.80, Color(1, 1, 1, 1))
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	m.color_ramp = texture
	return m


func _insect_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(INSECT_EXTENT, 0.9, INSECT_EXTENT)
	m.direction = Vector3(0.0, 1.0, 0.0)
	m.spread = 180.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.4
	m.gravity = Vector3.ZERO
	# ERRATIC is the whole point. Strong, fast turbulence on a short lifetime
	# reads as something alive; a smooth path reads as another mote.
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.6
	m.turbulence_noise_scale = 5.0
	m.turbulence_noise_speed = Vector3(1.4, 0.9, 1.2)
	m.damping_min = 0.6
	m.damping_max = 1.4
	m.scale_min = 0.7
	m.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.15, Color(1, 1, 1, 1))
	ramp.add_point(0.85, Color(1, 1, 1, 1))
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	m.color_ramp = texture
	return m


static func _mote_mesh(size: float, colour: Color) -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = colour
	material.disable_receive_shadows = true
	quad.material = material
	return quad
