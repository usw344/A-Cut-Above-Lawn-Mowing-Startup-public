# Transferable scenery wind package

This folder contains the complete saved wind implementation. It does not alter
the imported GLTF/GLB files and does not depend on unsaved editor material
overrides.

## Use

1. Keep this folder at `res://scenery_wind/` and keep the supplied source assets
   at their current `res://Assets/` paths.
2. Instance `scenes/scenery_wind_controller.tscn` once in the destination scene.
3. Use the wind-ready wrapper scenes in this folder in place of direct GLTF/GLB
   instances.
4. Tune `wind_direction`, `tree_wind_strength`, `tree_wind_speed`, and
   `tree_gust_strength` on the controller. Grass direction and speed remain
   coordinated automatically; its response has separate modest strength knobs.

The shader derives per-instance phase, amplitude, and slight speed differences
from each mesh instance's world position. Neighboring vegetation therefore does
not move in lockstep, including when materials are shared.

## Mesh masking decision

All three supplied trees expose positions, normals, and UV0, but no vertex
colours. Each also combines trunk and foliage in one material, and UV0 is used
for the colour-atlas lookup rather than a reliable structural wind mask. The
tree shader therefore uses saved per-asset height bounds plus radial distance:

- vertices at and below the base threshold remain exactly still;
- upper vertices gain motion gradually;
- vertices near the trunk centre receive only 14–18% of the available bend;
- outer branch/leaf extremities receive the full subtle displacement.

This is the smallest safe approach for these meshes and keeps every supplied
tree variant wind-enabled without changing asset geometry.

`scenes/wind_preview.tscn` is a standalone inspection scene. Validate saved
resource wiring with:

```powershell
Godot.exe --headless --path . --script res://scenery_wind/tests/test_scenery_wind.gd
```
