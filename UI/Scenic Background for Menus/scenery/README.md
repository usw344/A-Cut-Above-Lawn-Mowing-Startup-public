# Main menu scenery package

`scenes/main_menu_scenery.tscn` is the production composition. It depends on
the existing `res://Assets/`, `res://addons/sky_3d/`, and
`res://scenery_wind/` folders, all of which are saved project resources.

The scene keeps the left portion calm enough for title/menu content while using
edge foliage and a middle-distance tree line to maintain a sheltered woodland
feeling. The focal trees, foreground framing, and strongest contrast occupy the
right side. `MenuSafeOverlay/Gradient` adds a restrained readability treatment
without containing or intercepting UI.

`MainMenuScenery` keeps camera framing and all vegetation/rock grounding
deterministic. Its terrain-height function mirrors the vertex displacement in
`rolling_ground.gdshader`, so the scene survives transfer without baked editor
positions.

`DenseGrassField` creates the mowing-focused meadow as two efficient MultiMeshes.
Its saved defaults generate 895 varied clumps and a narrow low-cut lane from a
fixed seed. The 24 manually composed grass nodes remain as larger foreground
accents. Density, spacing, scale range, seed, lane width, and cut-height ratio
are exposed on `dense_grass_field.tscn`.

Ambient presentation is also saved and optional. `MainMenuScenery` exposes a
very slow camera drift and an exact reset method, the Sky3D node owns restrained
near/far depth of field, and `ambient_pollen.tscn` supplies soft warm motes that
move in the breeze direction.

The exposed ground uses a procedural loam shader rather than a flat green
surface. Layered value noise supplies broad compacted-soil variation and small
mineral flecks without requiring an external texture. The production camera is
saved at a lower, near-eye-level angle, while restrained grading, softer shadows,
MSAA, and screen-space contact depth give the supplied low-poly assets a more
contemporary presentation.

The previous `res://scenery_wind/scenes/wind_preview.tscn` remains available as
an isolated diagnostic scene.

Validate the production scene with:

```powershell
Godot.exe --headless --path . --script res://scenery/tests/test_main_menu_scenery.gd
Godot.exe --headless --path . --script res://scenery/tests/test_dense_grass_field.gd
```
