class_name ACAMowingEffects
extends Node3D
## ROLE
## What the machine throws out while it is cutting: grass clippings, and a
## little dust on a dry property.
##
## ---------------------------------------------------------------------------
## IT ONLY FIRES WHEN GRASS IS ACTUALLY BEING CUT
## ---------------------------------------------------------------------------
## This is driven by `ACAMowerCutter.cut`, which is emitted only when a sweep of
## the deck turned uncut cells into cut ones. Driving back across ground that is
## already mown emits nothing at all, and neither does sitting still with the
## engine running - which is the difference between feedback and confetti.
##
## The emitter is a state machine of exactly two states, and the reason it is
## not simply `emitting = cut_happened` is that the signal arrives in bursts:
## the cutter reports per physics frame at 576 Hz and reports nothing at all
## between passes over cut ground. Toggling a particle system at that rate
## produces a stutter, so a short linger keeps the stream continuous while the
## machine is working and stops it promptly when it is not.
##
## PUBLIC API
##   bind(mower, cutter, params)
##   set_enabled(value)
##   statistics()
##
## SIGNALS: None.
##
## INVARIANTS
##   * Nothing here is gameplay. Removing this node changes no cut, no contract
##     and no number.
##   * Particle counts are small and fixed. See the note on RESTRAINT below.
##
## PERSISTENCE OWNERSHIP: None.

## ---------------------------------------------------------------------------
## RESTRAINT
## ---------------------------------------------------------------------------
## Twenty-eight clippings and twelve motes of dust. That is not a placeholder
## waiting to be turned up: a riding mower on a domestic lawn throws a thin
## spray out of one side, and a cloud of green confetti is what a game does when
## it wants the player to notice the feature rather than the lawn.
const CLIPPING_COUNT := 28
const DUST_COUNT := 12

## Seconds the clipping stream keeps running after the last cut was reported.
const LINGER := 0.18

## Below this `dryness` a property throws no dust at all. A damp lawn does not.
const DUST_DRYNESS := 0.26

var _mower: Node3D = null
var _cutter: ACAMowerCutter = null
var _clippings: GPUParticles3D = null
var _dust: GPUParticles3D = null
var _linger := 0.0
var _enabled := true
## ---------------------------------------------------------------------------
## WHAT THE GROUND AND THE CONFIGURATION DO TO THE SPRAY
## ---------------------------------------------------------------------------
## Two multipliers, both set from outside, both purely cosmetic. Nothing here
## decides how much grass was cut - `ACAClippings` does that from the cell count
## and has never heard of a particle.
##
## `_dust_scale` is the ground condition: dry lawns raise dust and wet ones do
## not. `_mode` is what the machine is configured to do with what it cuts, and
## it changes WHERE the spray leaves from and HOW MUCH of it there is.
var _dust_scale := 1.0
var _mode: int = ACAMowingMode.Mode.BAG


func _ready() -> void:
	set_process(true)


## `params` supplies the property's own dryness and grass colour bias, so the
## clippings are the colour of the lawn they came off rather than a fixed green.
func bind(mower: Node3D, cutter: ACAMowerCutter,
		params: ACAPropertyParams) -> void:
	_mower = mower
	_cutter = cutter
	_clear()
	if mower == null or cutter == null:
		return

	var deck := cutter.deck()
	# BEHIND THE DECK, on the discharge side. Local +Z is forward on every
	# canonical mower, so the spray leaves from behind and to the right, which
	# is the side a real machine discharges from.
	#
	# `forward_offset` IS PART OF WHERE THE DECK IS, and this used to leave it
	# out - the spray was measured from the machine's origin rather than from
	# the deck's own rectangle, so on the rider (offset 0.4) the clippings left
	# from a point over half a unit behind the housing they were supposed to be
	# leaving. Every canonical machine declares a different offset, so the error
	# was a different size on each one.
	var deck_rear: float = deck.forward_offset - deck.half_length
	var behind := Vector3(deck.half_width * 0.55, 0.12, deck_rear - 0.2)

	_clippings = _make_emitter("Clippings", CLIPPING_COUNT, behind,
		_clipping_material(params), _clipping_mesh(params))
	_dust = null
	if params != null and params.dryness >= DUST_DRYNESS and _dust_scale > 0.0:
		# Dust is kicked up UNDER the deck rather than thrown from its edge, so
		# it sits at the deck's own centre line.
		_dust = _make_emitter("Dust", DUST_COUNT,
			Vector3(0.0, 0.06, deck.forward_offset - deck.half_length * 0.6),
			_dust_material(params), _dust_mesh(params))
		_dust.amount_ratio = clampf(_dust_scale, 0.0, 1.0)
	# The spray follows the configuration the machine went out in.
	set_mowing_mode(_mode)


## HOW MUCH DUST THIS PROPERTY IS THROWING TODAY. Zero switches it off, which
## is what a wet lawn does. Set by the mowing runtime from
## `ACAGroundConditions`; this class never asks the weather anything.
func set_dust_scale(value: float) -> void:
	_dust_scale = maxf(value, 0.0)
	if _dust != null:
		_dust.amount_ratio = clampf(_dust_scale, 0.0, 1.0)
		if _dust_scale <= 0.0:
			_dust.emitting = false


## WHICH CONFIGURATION THE MACHINE IS IN, for the look of the discharge.
##
##   BAGGING         the clippings are drawn in behind the deck: a short, thin
##                   spray close to the machine.
##   MULCHING        almost nothing leaves the deck, which is the point of it.
##   SIDE DISCHARGE  a wide throw well clear of the right-hand side.
##
## It only moves and scales the emitter that already existed. There is no second
## particle system and no per-mode effect to maintain.
func set_mowing_mode(mode: int) -> void:
	_mode = mode
	if _clippings == null or _cutter == null:
		return
	var deck := _cutter.deck()
	if deck == null:
		return
	var deck_rear: float = deck.forward_offset - deck.half_length
	match mode:
		ACAMowingMode.Mode.MULCH:
			_clippings.amount_ratio = 0.22
			_clippings.position = Vector3(0.0, 0.08, deck_rear - 0.1)
		ACAMowingMode.Mode.SIDE_DISCHARGE:
			_clippings.amount_ratio = 1.0
			_clippings.position = Vector3(deck.half_width * 1.15, 0.16,
				deck.forward_offset - deck.half_length * 0.35)
		_:
			_clippings.amount_ratio = 0.72
			_clippings.position = Vector3(deck.half_width * 0.55, 0.12,
				deck_rear - 0.2)


func mowing_mode() -> int:
	return _mode


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_stop()


func statistics() -> Dictionary:
	return {
		"clippings": CLIPPING_COUNT if _clippings != null else 0,
		"dust": DUST_COUNT if _dust != null else 0,
	}


func _process(delta: float) -> void:
	if _mower == null or not is_instance_valid(_mower):
		return
	# The emitters ride the machine rather than being parented to it, so a
	# mower swapped out from under this node does not take them with it.
	global_transform = _mower.global_transform

	if _linger > 0.0:
		_linger = maxf(_linger - delta, 0.0)
		if _linger <= 0.0:
			_stop()


## Connected to `ACAMowerCutter.cut`, which fires ONLY on fresh grass.
func on_cut(_cells: int) -> void:
	if not _enabled:
		return
	_linger = LINGER
	if _clippings != null and not _clippings.emitting:
		_clippings.emitting = true
	if _dust != null and not _dust.emitting:
		_dust.emitting = true


func _stop() -> void:
	if _clippings != null:
		_clippings.emitting = false
	if _dust != null:
		_dust.emitting = false


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_clippings = null
	_dust = null


# ==================================================================== emitters

func _make_emitter(node_name: String, amount: int, at: Vector3,
		process_material: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = node_name
	emitter.amount = amount
	emitter.lifetime = 0.62
	emitter.explosiveness = 0.0
	emitter.randomness = 0.5
	emitter.fixed_fps = 30
	emitter.emitting = false
	emitter.local_coords = false
	emitter.process_material = process_material
	emitter.draw_pass_1 = mesh
	emitter.position = at
	# Small, fast, near the ground: a shadow from a clipping is not something
	# anybody will ever see, and it would be in the map for the whole property.
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-3.0, -1.0, -3.0), Vector3(6.0, 3.0, 6.0))
	add_child(emitter)
	return emitter


func _clipping_material(params: ACAPropertyParams) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.35, 0.05, 0.12)
	# Thrown BACK and slightly out, then dropped. Gravity is what makes a
	# clipping land on the lawn instead of drifting like ash.
	m.direction = Vector3(0.45, 0.55, -1.0).normalized()
	m.spread = 26.0
	m.initial_velocity_min = 1.6
	m.initial_velocity_max = 3.4
	m.gravity = Vector3(0.0, -7.0, 0.0)
	m.damping_min = 1.2
	m.damping_max = 2.6
	m.angular_velocity_min = -220.0
	m.angular_velocity_max = 220.0
	m.scale_min = 0.7
	m.scale_max = 1.25
	# Fade out rather than vanish, so the stream has no visible tail.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.72, Color(1, 1, 1, 1))
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	m.color_ramp = texture
	return m


func _clipping_mesh(params: ACAPropertyParams) -> Mesh:
	var quad := QuadMesh.new()
	# A clipping is a few centimetres of leaf. In a world about four times life
	# size that is a very small quad, and the first thing that gives a mowing
	# effect away is clippings the size of playing cards.
	quad.size = Vector2(0.11, 0.05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = _clipping_colour(params)
	quad.material = material
	return quad


## The colour of the lawn it came off. `lawn_colour_bias` and `dryness` are the
## same two fields the grass shader reads, so a dry yellowed property throws dry
## yellowed clippings without either of them being described twice.
static func _clipping_colour(params: ACAPropertyParams) -> Color:
	if params == null:
		return Color(0.353, 0.529, 0.243)
	var green := Color(0.353, 0.529, 0.243)
	var dry := Color(0.541, 0.494, 0.235)
	var colour := green.lerp(dry, clampf(params.dryness * 0.9, 0.0, 0.7))
	var bias := clampf(params.lawn_colour_bias, -1.0, 1.0)
	return Color(colour.r * (1.0 + bias * 0.06), colour.g,
		colour.b * (1.0 - bias * 0.06), 1.0)


func _dust_material(_params: ACAPropertyParams) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.5, 0.02, 0.2)
	# Dust does not get thrown; it gets DISTURBED. Almost no initial speed, no
	# gravity to speak of, and it fades where it was lifted.
	m.direction = Vector3(0.0, 1.0, -0.35).normalized()
	m.spread = 55.0
	m.initial_velocity_min = 0.15
	m.initial_velocity_max = 0.5
	m.gravity = Vector3(0.0, -0.35, 0.0)
	m.damping_min = 0.4
	m.damping_max = 0.9
	m.scale_min = 0.8
	m.scale_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.25, Color(1, 1, 1, 0.30))
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	m.color_ramp = texture
	return m


func _dust_mesh(params: ACAPropertyParams) -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.42)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.686, 0.612, 0.478,
		clampf(params.dryness if params != null else 0.3, 0.0, 0.5))
	quad.material = material
	return quad
