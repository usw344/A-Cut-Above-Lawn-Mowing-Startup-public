class_name ACAGroundWetness
extends RefCounted
## WHAT WET GROUND LOOKS LIKE. Presentation only.
##
## `ACAGroundConditions` already decides whether a property is Dry, Damp or Wet,
## and the mowing already behaves differently on each: the catcher fills faster,
## the dust stops, the grip drops. None of that was VISIBLE. A player mowing in
## the rain saw exactly the same lawn they saw at noon in July, which made a
## real mechanic read as an invisible one.
##
## ---------------------------------------------------------------------------
## THIS IS NOT A SECOND SET OF RULES
## ---------------------------------------------------------------------------
## Nothing here decides anything. It READS `ACAGroundConditions.current()` - the
## one authority, itself a pure function of the one weather authority - and
## turns the answer into two shader numbers. Change what wet ground DOES in
## `ACAGroundConditions`; change what it LOOKS LIKE here.
##
## ---------------------------------------------------------------------------
## TWO UNIFORMS, BOTH ALREADY THERE
## ---------------------------------------------------------------------------
## No shader was edited to build this, and no uniform was added. Both lawn
## shaders already carry:
##
##   `colour_bias`     -1 greener and cooler, +1 warmer and yellower. Wet grass
##                     is greener and cooler. That is the whole of the colour.
##   `roughness_value` how matte the surface is. Water fills the micro-detail
##                     of a leaf, so wet grass catches a sheen off the sky that
##                     dry grass does not.
##
## Both are applied as a DELTA on the property's own authored value, so a lawn
## the generator drew as parched still reads as parched in the rain - just a
## parched lawn that has been rained on.
##
## PUBLIC API
##   static apply(property: ACAProperty, state: int) -> void
##   static apply_current(property: ACAProperty) -> void
##   static values_for(state) -> Dictionary   { bias_delta, roughness_scale }

## What each ground state does to the two uniforms.
##
## DELIBERATELY RESTRAINED, for the same reason the mowing effects are: the
## forecast should change how a day is PLANNED, and mowing in the wet must never
## be unpleasant to look at. A lawn that turned black in drizzle would be a
## worse game than one that ignored the weather.
const STATES := {
	ACAGroundConditions.State.DRY: {
		"bias_delta": 0.10, "roughness_scale": 1.00,
	},
	ACAGroundConditions.State.DAMP: {
		"bias_delta": -0.12, "roughness_scale": 0.90,
	},
	ACAGroundConditions.State.WET: {
		"bias_delta": -0.34, "roughness_scale": 0.70,
	},
}

## Uniform names, in the two shaders that carry them.
const BIAS_PARAM := &"colour_bias"
const ROUGHNESS_PARAM := &"roughness_value"


static func values_for(state: int) -> Dictionary:
	return STATES.get(state, STATES[ACAGroundConditions.State.DAMP])


## Apply the state the world is actually in.
static func apply_current(property: ACAProperty) -> void:
	if property == null or property.params() == null:
		return
	apply(property, ACAGroundConditions.current(property.params().dryness))


## Apply a state. Safe on a half-built property, on one with the grass skipped,
## and on one whose materials have not been made yet: every branch returns
## quietly rather than pushing an error into a mowing session.
static func apply(property: ACAProperty, state: int) -> void:
	if property == null:
		return
	var params := property.params()
	if params == null:
		return
	var values := values_for(state)
	var bias := clampf(params.lawn_colour_bias + float(values["bias_delta"]),
		-1.0, 1.0)
	var roughness := float(values["roughness_scale"])

	var terrain := property.terrain()
	if terrain != null:
		_write(terrain.ground_material(), bias, roughness)
	var grass := property.grass()
	if grass != null:
		_write(grass.material(), bias, roughness)


## The authored roughness, remembered on the material itself the FIRST time it
## is touched.
##
## Reading the live value back and scaling it would compound: a lawn that had
## been rained on twice would be twice as shiny as one rained on once, and the
## sky can change eight times in a working day. The baseline is stored once and
## every later state scales THAT.
const AUTHORED_ROUGHNESS := &"aca_authored_roughness"


static func _write(material: ShaderMaterial, bias: float,
		roughness_scale: float) -> void:
	if material == null:
		return
	material.set_shader_parameter(BIAS_PARAM, bias)
	if not material.has_meta(AUTHORED_ROUGHNESS):
		var authored: Variant = material.get_shader_parameter(ROUGHNESS_PARAM)
		if not (authored is float or authored is int):
			return
		material.set_meta(AUTHORED_ROUGHNESS, float(authored))
	material.set_shader_parameter(ROUGHNESS_PARAM,
		clampf(float(material.get_meta(AUTHORED_ROUGHNESS)) * roughness_scale,
			0.05, 1.0))
