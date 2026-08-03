# Performance Architecture

Status: Current workload map and measurement priorities

## Primary performance characteristic

The mowable grass system exchanges node count and physics-body count for direct collision-based identification of every grass position.

At the current MVP call:

```gdscript
test_custom_gridmap(256)
```

and batching size 16:

| Item | Count |
|---|---:|
| Logical grass positions | 65,536 |
| Grass positions per chunk | 16 |
| Chunk data objects | 4,096 |
| Mowed/unmowed MultiMesh nodes per chunk | 2 |
| Grass MultiMesh instance nodes | 8,192 |
| Initial per-grass static collision bodies | 65,536 |

These values follow directly from the grid and chunk loops. Runtime measurements should verify actual node/body totals after initialization.

## Physics configuration

The project currently uses:

- Jolt Physics.
- Separate-threaded 3D physics.
- 576 physics ticks per second.
- Up to 100 physics steps per frame.
- Four solver iterations.
- Two differently named body-limit settings.

The physics rate is four times the 144 FPS cap. Mower physics, fuel counters, collision collection, rain following, and HUD performance updates all run through physics processing.

## Mower collision workload

Every canonical mower physics frame:

1. Calls `move_and_slide()`.
2. Iterates all slide collisions.
3. Creates a new collision array.
4. Emits `collided`, including when the array is empty.
5. Causes the grid handler to inspect each collider name.

Every newly cut grass position removes a collision body and rebuilds both 16-position-or-smaller MultiMeshes for its chunk.

The small chunk size bounds per-cut MultiMesh reconstruction, while the large number of collision bodies and nodes dominates initialization and physics-space scale.

## Grid initialization and reset

Grid creation is synchronous from `MVP._ready()`.

Initialization performs:

- Coordinate-array construction.
- Partitioning.
- Dictionary population.
- 4,096 chunk-object allocations.
- 8,192 MultiMesh node additions.
- 65,536 static-body and collision-shape additions.

Reset repeats the whole process by replacing the Custom Gridmap.

User-visible startup/reset latency and peak allocation should be measured on each target platform.

## MultiMesh strengths

The project correctly uses MultiMesh for:

- Mowable grass rendering.
- Mowed grass rendering.
- Decorative terrain grass.
- Trees.
- Shrubs.

This reduces draw-node and draw-call cost relative to one `MeshInstance3D` per visible plant.

The mowable system still uses one physics body per unmowed grass position, so visual batching does not imply physics batching.

## Canonical terrain workload

The active custom terrain scene serializes:

- One large terrain mesh.
- 216 environmental MultiMesh nodes.
- Decorative grass visibility ranges.
- A far-grass overlay shader.

Its generator does not run at startup under current settings. That avoids runtime mesh extraction, ground triangle generation, random placement, and scene ownership operations during normal play.

If runtime generation is enabled later, measure:

- `TriangleMesh` generation.
- Vertical segment sampling.
- Random placement retries.
- Foliage occupancy checks.
- MultiMesh serialization/addition.

## Weather and Sky3D

Weather cost includes:

- Sky3D atmosphere and cloud shader work.
- Near and far GPU rain particles.
- Per-physics-frame rain-handler repositioning.
- Property tweens during preset transitions.
- Rain and ambient audio.

Rain scenes currently author thousands of particles across the near and far emitters. Performance should be evaluated separately for Clear, Foggy, and Rain.

## UI instrumentation

The MVP HUD currently samples:

- FPS.
- Static memory.
- Process time.
- Physics-process time.

This is useful for coarse observation but does not report:

- Physics body count.
- Draw calls.
- Visible primitives.
- Grid construction time.
- Mowing-handler time.
- Terrain or Sky3D GPU time.

The older mower development HUD and `Dev tools/Performance Monitor.gd` contain additional draw/memory/grid ideas but are not integrated.

`Dev tools/Mesurement.gd` can measure millisecond or microsecond intervals, but it is also unconnected.

## Rendering settings

Current project settings include:

- Occlusion culling enabled.
- 800 occlusion rays per thread.
- ETC2/ASTC texture import support.
- Mobile feature tag.
- VSync disabled.
- 144 FPS cap.

The terrain’s decorative grass uses visibility ranges. Tree and shrub density is reduced by generation ring rather than runtime object pooling.

## No object pool

No reusable object-pool system was found.

Current replacement/allocation behaviors include:

- Fresh mower instantiation on selection.
- Full grid instantiation on startup/reset.
- Job Offer objects generated dynamically in the partial job system.
- Runtime Tween creation for weather/time/audio changes.

## Save-state size

The proposed mowing save stores mowed/unmowed coordinate arrays and lookup dictionaries for every chunk. Before adopting it as a release format, measure:

- Serialized size.
- Save time.
- Load time.
- Compression cost.
- Memory duplication during save.

## Measurement checklist

Measure at minimum:

- Cold startup to first controllable frame.
- Reset duration.
- Node count after grid creation.
- Physics body count before and after mowing.
- Physics-frame time at 576 Hz.
- Collision handler calls per second.
- Memory before and after multiple mower switches/resets.
- Clear/Foggy/Rain GPU and CPU cost.
- Desktop, Web, and Android separately.

Record target hardware and acceptable budgets before using these numbers as pass/fail criteria.
