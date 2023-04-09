shader_type spatial;

uniform vec3 wheel_color : source_color = vec3(4.0, 0.0, 0.0);
uniform vec3 rim_color : source_color = vec3(120.8, 80.8, 0.8);
uniform float rim_thickness : hint_range(0.0, 1.0) = 0.1;
uniform float tread_depth : hint_range(0.0, 1.0) = 0.2;

void fragment() {
   vec3 normal = normalize(NORMAL);
   vec3 view_dir = normalize(CAMERA_POSITION_WORLD - NODE_POSITION_WORLD);
   vec3 light_dir = normalize(vec3(1.0, 1.0, 1.0));
   float ndotl = clamp(dot(normal, light_dir), 0.0, 1.0);
   float ndotv = clamp(dot(normal, view_dir), 0.0, 1.0);
   vec3 color = mix(rim_color, wheel_color, ndotl);
   float tread = 1.0 - (1.0 - ndotv) / tread_depth;
   if (tread > 1.0) {
       tread = 1.0;
   }
   if (tread < 0.0) {
       tread = 0.0;
   }
   if (ndotv < rim_thickness) {
       color = rim_color;
   }
   ALBEDO = vec3(tread) * color;
   METALLIC = 0.0;
   ROUGHNESS = 1.0;
}
