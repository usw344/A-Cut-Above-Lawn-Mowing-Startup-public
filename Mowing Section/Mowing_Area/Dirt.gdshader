shader_type spatial;
uniform sampler2D noise; 

void fragment() {
    // Set the color of the fragment to a dark brown color.
    // You can adjust the RGB values to get different shades of soil.
    ALBEDO = vec3(0.122,0.090, 0.067);

    // Add a small amount of noise to the fragment color
    // to create a more natural-looking texture.
    ALBEDO += texture(noise, vec2(UV)).rgb *0.05;
        
    // Apply a slight ambient occlusion effect to create depth.
    ALBEDO *= 1.0 - (AO * 0.5);
}
