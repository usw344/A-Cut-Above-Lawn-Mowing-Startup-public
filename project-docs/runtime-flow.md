# Startup and Runtime Flow

Status: Confirmed current playable flow

## Launch

1. Godot loads `project.godot`.
2. The `model` autoload is created from `Data Structures/Model.gd`.
3. The UID configured as `run/main_scene` resolves to `Game/M.V.P/Minimum Viable Game.tscn`.
4. The MVP scene instantiates its authored children:

   - Rider mower.
   - Custom Gridmap.
   - CanvasLayer and MVP HUD.
   - Ambient AudioStreamPlayer.
   - Mountain-range backdrop.
   - Preset Manager containing Sky3D and Rain Handler.

## Scene initialization

Godot initializes child nodes before the parent root completes `_ready()`.

Important child behavior:

- The rider mower captures the mouse, starts its 3D engine audio, and initializes camera targets.
- The Preset Manager stops rain immediately.
- The Rain Handler configures near/far particles as non-emitting and starts its rain stream silently when available.
- The terrain and its baked environmental MultiMeshes already exist in the custom-grid child scene.

`MVP._ready()` then:

1. Forces the Custom Gridmap to a hard-coded world position.
2. Calls `test_custom_gridmap(256)`.
3. Starts the ambient audio stream.
4. Stores the current mower transform for resets.
5. Moves the start area relative to the mowing surface.
6. Positions the mower at the start area plus a small vertical offset.
7. Applies the Day time preset.
8. Gives the Preset Manager the ambient player for rain ducking.

## Mowing-grid construction

For the current size:

1. `test_custom_gridmap(256)` records a display-area radius derived from `256 × 0.55`.
2. It resizes the mowing surface and collision shape.
3. It configures a 256×256 grid with a batching size of 16.
4. It produces 65,536 logical grass coordinates.
5. It partitions them into 4×4 chunks.
6. It constructs 4,096 `Multi_Mesh_Chunk` objects.
7. Each chunk provides unmowed and mowed MultiMesh instances.
8. Each initially unmowed grass position receives a collision body.

The generated MultiMesh nodes are parented under the `Mowing Area`. The chunk data objects themselves are stored in the Custom Gridmap dictionaries rather than added as scene-tree nodes.

## Active gameplay loop

### Mower

Each mower physics frame:

1. Applies gravity.
2. Reads forward/back input.
3. Uses the global model speed to set horizontal velocity.
4. Updates engine audio.
5. Calls `move_and_slide()`.
6. Updates fuel counters in `model`.
7. Collects current slide collisions.
8. Emits either `collided` or `fuel_empty`.

The MVP currently resets fuel to 100 after an empty-fuel event as testing behavior.

### Grass cutting

The active mower’s `collided` signal is connected to `Custom_Gridmap.custom_grid_map_collision_handler()`.

For each collision:

1. Ground, start-area, and mowing-area collisions are ignored by collider name.
2. A grass collider name is interpreted as:

   ```text
   chunk_id,x,y,z
   ```

3. The grid resolves the owning chunk.
4. The chunk removes the corresponding collision body.
5. The position moves from the unmowed coordinate array to the mowed array.
6. The chunk rebuilds its two small MultiMesh resources.

### Environment

The custom Terrain Manager supplies the surrounding terrain and decorative foliage. Its environmental MultiMeshes are independent of the mowable grass state.

### Weather following

Every MVP physics frame, the current mower’s global position is passed through the Preset Manager to the Rain Handler. The handler positions its near/far rain effect above the mower.

### HUD

The HUD updates FPS, static memory, and process/physics CPU timing each physics frame. It emits requests for:

- Mower selection.
- Grid reset.
- Mower speed.
- Time slider.
- Day, Evening, and Night.
- Clear, Foggy, and Rain.

The MVP root translates those requests into model changes or calls on the Preset Manager.

## Mower switching

When a mower is selected:

1. The current mower transform and mouse mode are saved.
2. The current mower node is detached.
3. A new mower scene is instantiated from the `push`, `powered`, or `rider` lookup.
4. The saved transform is assigned.
5. The new mower is added to the MVP root.
6. Its `collided` signal is connected to the Custom Gridmap.
7. The saved mouse mode is restored.

The global speed and fuel state remain in `model`, so they are shared across mower instances.

## Grid reset

When Reset Map and Location is requested:

1. The Custom Gridmap transform is saved.
2. The existing grid is queued for deletion.
3. A fresh Custom Gridmap scene is instantiated.
4. The 256×256 grid is rebuilt.
5. The saved grid transform is restored.
6. The mower transform is restored.
7. The mower collision signal is connected to the new grid.

## Time and weather

Time presets tween Sky3D time:

- Day: 12.00.
- Evening: 17.5.
- Night: 22.00.

Weather presets:

- Clear: stops rain and restores clear Sky3D properties.
- Foggy: stops rain and applies denser, shorter-range fog with flatter lighting.
- Rain: starts rain, darkens the sky, increases clouds/fog, raises rain audio, and ducks ambience.

## Current stopping boundaries

The current runtime has no implemented application flow for:

- Entering through the main menu.
- Creating or selecting a profile before gameplay.
- Accepting a generated job and configuring the MVP from it.
- Writing a complete save file.
- Loading a complete save file.
- Returning from gameplay to a menu or business area.

No project script currently calls `change_scene` or an equivalent scene-transition API.
