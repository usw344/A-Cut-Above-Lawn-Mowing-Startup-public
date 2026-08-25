shader_type canvas_item;

// THE MINIMAP'S CUT LAYER.
//
// It draws ACALawn's own cut mask - the same texture the grass shader samples -
// so the map can never disagree with the lawn about what has been mown.
//
// The mask is one texel per world unit: R is 1 where a cell is cut, G carries
// the heading the mower was on, and ALPHA is the mowable flag. Drawn as an
// ordinary modulated texture that would paint uncut lawn solid BLACK, because
// an uncut mowable cell is (0, 0, 0, 1). So the red channel becomes the alpha
// of one flat colour instead, and every other channel stays out of the way.
uniform vec4 cut_colour : source_color = vec4(0.404, 0.639, 0.361, 1.0);

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	COLOR = vec4(cut_colour.rgb, cut_colour.a * mask.r * mask.a);
}
