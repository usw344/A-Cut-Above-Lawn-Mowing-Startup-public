# Terrain and Foliage

Status: Current playable runtime  
Canonical implementation: Custom Terrain Manager  
Deprecated implementation: Terrain3D

## Canonical scene

`Mowing Section/Mowing Area/Mowing Ground/Custom Gridmap solution/Terrain Manager.tscn` is instantiated by `custom_gridmap.tscn`, which is instantiated by the MVP.

Its root is:

```text
Ground : MeshInstance3D
```

The root:

- Uses `Terrain/Meshes/1x1 Ground Main Mesh.mesh`.
- Uses `Terrain/Meshes/Gound 1x1 ColourMap.png`.
- Attaches `Terrain Manager.gd`.
- Has `low_poly = true`.
- Uses an embedded far-grass overlay shader material.

## Authored scene content

The scene has 218 nodes:

- 1 root ground `MeshInstance3D`.
- 1 hidden `Central Mesh` helper.
- 216 `MultiMeshInstance3D` foliage/grass nodes.

The baked MultiMesh breakdown is:

| Prefix | Count | Role |
|---|---:|---|
| `grass_lod1` | 8 | Nearest decorative grass ring |
| `grass_lod2` | 16 | Second decorative grass ring |
| `tree` | 48 | Tree variant 1 |
| `tree2` | 48 | Tree variant 2 |
| `tree3` | 48 | Tree variant 3 |
| `shrub` | 48 | Shrubs |

These are environmental decorations. They are not the mowable grass instances managed by `Custom_Gridmap`.

## Runtime behavior

`Terrain Manager.gd` currently has an empty `_ready()`. The active runtime therefore uses the MultiMeshes already serialized into the scene.

The script’s `_process()` watches three exported development controls:

- `toogle_run`
- `toggle_clear`
- `low_poly`

Generation only starts when `toogle_run` is manually set. The `@tool` annotation is commented out, indicating that generation is currently an editor/development workflow rather than normal startup behavior.

## Foliage database

The script defines high and low variants for:

- `tree`
- `tree2`
- `tree3`
- `shrub`
- `grass_lod1`
- `grass_lod2`
- Placeholder `stone`
- Placeholder `stone2`

Each entry can specify:

- Mesh.
- Density or instance count.
- Instance scale.
- Random scale range.
- Y offset.
- Placement collision radius.
- Grass grid spacing and jitter.
- Fill chance.
- Visibility begin/end distance.

`low_poly = true` selects low variants when a valid value is present and falls back to the other variant if necessary.

## Generation area

The generator:

1. Creates coordinates around the center while excluding `(0, 0)`.
2. Splits coordinates into Chebyshev-distance rings.
3. Generates three outer rings.
4. Selects grass LOD by ring.
5. Places trees and shrubs for each cell.
6. Applies a far-grass material overlay to the ground.

The configured cell size is 350.

## Ground sampling

Before generation, the script:

1. Treats the root as the ground `MeshInstance3D`.
2. Generates a `TriangleMesh` from the visual mesh.
3. Intersects a vertical segment at candidate X/Z positions.
4. Converts the hit position back into the generator’s local space.
5. Places foliage so the source mesh’s bottom rests on the terrain.

This uses visual-mesh triangle sampling and does not require a physics collision for placement.

## Placement collision avoidance

`foliage_occupancy` stores accepted positions by grid cell. New tree and shrub candidates use circle-distance checks against previously accepted candidates in the same cell.

This is generation-time overlap avoidance. It does not create runtime physics bodies for all decorative foliage.

## Grass LOD

Decorative grass uses:

- One `grass_lod1` ring.
- One `grass_lod2` ring.
- No grass MultiMesh beyond those rings.
- A shader overlay to tint farther ground with patchy grass colour.

Visibility ranges are assigned to grass MultiMesh nodes. Trees and shrubs use ring-density adjustments rather than the same two grass visibility ranges.

## Asset collections

Canonical foliage inputs are under the repository’s intentionally retained `Assets/Foilage/` spelling:

- `Assets/Foilage/trees/`
- `Assets/Foilage/Shurbs/`
- `Assets/Foilage/Low Poly/Grass/`
- `Assets/Foilage/Low Poly/Trees/`

The terrain mesh inputs are under:

- `Terrain/Meshes/`

Large mesh, image, and model contents are not enumerated in this documentation.

## Relationship to mowing

The Terrain Manager is a child of the Custom Gridmap scene, but it does not own mowable grass state.

The mowing collision handler explicitly ignores a collider named `Ground`. The current terrain root is a visual `MeshInstance3D`; the `Mowing Area` static body supplies the primary mowing surface collision.

## Terrain3D deprecation

Terrain3D is no longer planned for the final game. It was judged unnecessary and overly complex for project needs.

Remaining Terrain3D content includes:

- `addons/terrain_3d/`
- Terrain3D resources in `Terrain/Footage-Demo Data/`
- Terrain3D nodes in the three footage scenes.
- Export and credit references.

This content is deprecated cleanup debt. It must not be presented as a second planned terrain architecture.

Removal should occur only in a separate cleanup task after checking:

- Footage/demo preservation requirements.
- Export configuration.
- Third-party credits.
- Serialized Terrain3D resource references.

## Future direction

Future work should refine the custom Terrain Manager rather than restore Terrain3D. Likely documentation updates will be needed when:

- Generation is formalized as an editor tool or runtime pipeline.
- Foliage collision requirements are decided.
- Deterministic seeds are added.
- Generated scene ownership and baking are standardized.
- LOD and density targets are performance-tested.
