# Mowing Grid and Grass Removal

Status: Current playable runtime  
Primary scene: `Mowing Section/Mowing Area/Mowing Ground/Custom Gridmap solution/custom_gridmap.tscn`

## Purpose

The custom grid is the core mowing system. It creates a dense mowable grass field, maps every grass collision to a chunk-local instance, and changes cut grass from an unmowed mesh to a mowed mesh.

The system has two layers:

- `Custom_Gridmap` — whole-area layout, chunk indexes, collision routing, reset position, and aggregate save data.
- `Multi_Mesh_Chunk` — per-chunk mowed/unmowed instance state and collision bodies.

## Scene structure

`custom_gridmap.tscn` contains:

- `Custom Gridmap` (`Node3D`) with `custom_gridmap.gd`.
- `Mowing Area` (`StaticBody3D`).
  - Plane mesh.
  - Box collision shape.
- `Start Area` (`StaticBody3D`), hidden at runtime.
  - Plane mesh.
  - Box collision shape.
- Canonical `Terrain Manager` instance.

The mowing surface and the surrounding terrain are related spatially but have distinct responsibilities.

## Current initialization

The MVP calls:

```gdscript
custom_gridmap_object.test_custom_gridmap(256)
```

This method:

1. Sets a display-area radius to `grid_size * 0.55`.
2. Resizes the mowing plane and its collision.
3. Repositions the mowing and start areas.
4. Sets width and length to 256.
5. Sets batching size to 16.
6. Calls `make_grid()`.

## Coordinate and chunk data

`Custom_Gridmap` maintains:

| Field | Mapping |
|---|---|
| `chunk_to_coordinates_dictionary` | Chunk ID → global logical grass coordinates |
| `coordinates_to_chunk_dictionary` | Global logical coordinate → chunk ID |
| `chunk_id_to_chunk_dictionary` | Chunk ID → `Multi_Mesh_Chunk` object |
| `global_array_of_coordinates` | Complete ordered grid |

A batching size of 16 is interpreted as a square 4×4 chunk.

For a 256×256 grid:

- 65,536 logical grass positions.
- 4,096 chunks.
- 16 initial grass positions per chunk.

## Runtime scene-tree representation

`Multi_Mesh_Chunk` is created as a data object with `Multi_Mesh_Chunk.new()`. It is not itself added to the scene tree.

Each chunk creates two scene-tree nodes:

- `multimesh_instance_unmowed`
- `multimesh_instance_mowed`

Both are parented under `Mowing Area`, positioned at the chunk origin, and retained by the chunk object.

No object pool is used.

## Grass resources

The active chunk script loads:

- Collision shape: `Assets/Grass/Unmowed Grass Collision Shape polygon.tres`
- Mowed mesh: `Assets/Grass/Mowed_Grass_With_LOD_attempt1.res`
- Unmowed mesh: `Assets/Grass/Unmowed_Grass_OBJ.obj`

The similarly named mowed-grass resource at the `Assets/` root is not the active load path.

## Collision bodies

Each initially unmowed grass coordinate receives:

- A `StaticBody3D`.
- A child `CollisionShape3D`.
- A name encoding its owning chunk and local coordinate.

Format:

```text
chunk_id,x,y,z,
```

The trailing comma is tolerated by the current string split and integer conversion.

Collision bodies are children of the chunk’s unmowed `MultiMeshInstance3D`.

## Mowing flow

The mower emits an array of slide collisions. `custom_grid_map_collision_handler()`:

1. Reads each collider’s name.
2. Ignores `Mowing Area`, `Start Area`, and `Ground`.
3. Passes any other name to `mow_item()`.
4. Parses it into `Vector4i(chunk_id, x, y, z)`.
5. Resolves the chunk object.
6. Calls `mow_item_by_name()`.

The chunk then:

1. Confirms that the collision name still exists.
2. Removes its `StaticBody3D`.
3. Removes the coordinate from the unmowed array.
4. Adds it to the mowed array.
5. Rebuilds the mowed MultiMesh.
6. Rebuilds the unmowed MultiMesh.

The name lookup prevents the same grass position from being mowed repeatedly.

## Start area

The start area is positioned to one side of the mowing surface. The MVP calls `reset_start_area_global_position()` after placing the overall grid, then places the current mower at `get_mower_inital_position()` plus a vertical margin.

## Reset behavior

The system is reset by replacing the entire Custom Gridmap scene and rebuilding all chunks. It does not restore cut-state data during the MVP reset operation.

## Save representation

`Custom_Gridmap.save_object()` returns:

```text
{
  "chunk_save_objects": {
    chunk_id: <Multi_Mesh_Chunk save dictionary>
  },
  "grid_params": {
    "grid_width": ...,
    "grid_length": ...,
    "batching_size": ...
  },
  "chunk_to_coordinates_dictionary": ...,
  "coordinates_to_chunk_dictionary": ...
}
```

Each chunk saves:

```text
{
  "chunk_params": {
    "chunk_coord": ...,
    "chunk_grid_coord": ...,
    "chunk_id": ...,
    "chunk_size": ...
  },
  "mowed_coordinates": ...,
  "unmowed_coordinates": ...,
  "global_to_instance_reference": ...
}
```

Corresponding `load_object()` methods rebuild MultiMeshes and collision bodies. These methods are implemented but are not connected to the current application save flow.

## Development-only paths

The custom grid contains:

- A CSV writer with a hard-coded developer-machine path.
- A save/load test using `res://Saves/testing/load_save_testing.txt`.
- An input action named `Save`.

The test call is disabled in normal processing, and `res://` is not the intended location for release save data.

## Performance sensitivity

The active 256×256 setup creates:

- 65,536 grass collision bodies.
- 8,192 grass MultiMesh instance nodes.
- 4,096 chunk data objects.

Mower collisions are collected and emitted at the project’s 576 physics ticks per second. These characteristics explain the high body-limit and physics settings and should be measured whenever grid size, batch size, or collision strategy changes.

See [Performance architecture](../performance.md).
