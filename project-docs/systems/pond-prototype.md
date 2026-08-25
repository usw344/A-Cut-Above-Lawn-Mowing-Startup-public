# Pond Prototype

Status: **EXPERIMENTAL — NOT PART OF JOB GENERATION.**
Added 2026-08-20 (session 7, Milestone E).
Canonical owner: none yet — this is a tool, not a system.
Important paths: `Mowing Section/Experimental/Pond/`

## Purpose

A non-destructive pond carver and a procedural water shader, built so that when
the mowing grid is overhauled there is a **working, tested tool to integrate**
rather than a blank page.

!!! danger "Nothing in gameplay builds a pond"
    Superseded on 2026-08-20. The carver IS in gameplay now, through
    `ACAPondFeature`. This page describes the prototype and its demo scene; for
    how a pond is generated on a real contract see
    [Property, terrain and lawn](property-and-lawn.md).

## Files

| Path | |
|---|---|
| `Mowing Section/Experimental/Pond/pond_carver.gd` | `ACAPondCarver` — the deformation. Pure, static, no nodes |
| `Mowing Section/Experimental/Pond/pond.gd` | `ACAPond` — carved terrain, water, exclusion API |
| `Mowing Section/Experimental/Pond/pond_water.gdshader` | procedural water; no textures |
| `Mowing Section/Experimental/Pond/Pond Demo.tscn` | standalone development scene |

## Runtime flow

```
source MeshInstance3D   (READ ONLY — never modified)
        |
  ACAPondCarver.analyse()      is this mesh dense enough?
        |  yes
  ACAPondCarver.carve()        builds a NEW ArrayMesh
        |
   +----+--------+--------------------+
   |             |                    |
carved terrain  water surface   exclusion queries
(new mesh)      (plane + shader) (contains_world_point, ...)
```

`carve()` HIDES the source and shows the copy. `restore_source()` puts
everything back.

## The three guarantees

### 1. The source mesh is never modified

This matters more than it sounds. An imported `.glb` mesh or a `PlaneMesh` is a
**shared resource** — deforming it in place would silently deform every other
instance in the project, including ones in scenes nobody had open. Every carve
builds a new `ArrayMesh` from a copied vertex buffer.

### 2. A mesh too coarse is refused, not mangled

Deformation moves EXISTING vertices; it cannot invent them. A pond carved into
four vertices is a three-triangle pit, which is worse than no pond. `analyse()`
counts vertices inside the footprint and `carve()` returns a failure with an
explanation rather than producing something ugly.

The limit is **relative** — the same coarse mesh accepts a smaller pond.
Subdividing an arbitrary mesh is a remesher, and a remesher is not this
prototype's job.

### 3. The query and the geometry are the same function

`ACAPondCarver.shore_factor_at()` decides both where the ground drops and what
`contains_world_point()` answers, so a future grass or rock placer can never
disagree with what is on screen. `Pond Test` compares the two on every vertex.

## Shape

| Parameter | |
|---|---|
| `radius`, `ellipse_ratio` | size, and how much longer than wide |
| `depth` | maximum drop |
| `bank_fraction` | how much of the radius is sloping bank. 1.0 is a bowl; 0.2 is a bathtub |
| `irregularity`, `pond_seed` | how far the shoreline wanders, sampled by POSITION so neighbouring vertices agree |
| `water_level` | water height relative to the un-carved ground |

## The exclusion API — the point of the prototype

The pond is the easy half. What the grid overhaul will need is a way to ask
"is this where I was about to plant grass?"

| Call | |
|---|---|
| `contains_world_point(p)` | inside the footprint? |
| `shore_factor_world(p)` | 0 outside, rising to 1 at the deepest part — for FADING placement density near the shore rather than cutting it at a line |
| `is_submerged(p)` | inside *and* below the water |
| `get_exclusion_bounds()` | world AABB, for broad-phase rejection before per-blade tests |
| `get_exclusion_polygon(n)` | the shoreline as a world XZ polygon |

## Water

Four crossing sine waves, a value-noise ripple layer, Fresnel, depth-based
colour, and a `DEPTH_TEXTURE` shoreline fade. No FFT, no simulation, no
per-vertex CPU update, no physics — this is a small pond.

**No external assets.** Every wave and normal is arithmetic, so there is nothing
to license and nothing to copy alongside the shader.

Two bugs were found by looking at renders rather than at code:

- the carved copy rendered **white**, because a material can live in three
  places and only `material_override` was being copied. The demo's ground carries
  its material on the mesh resource;
- the water rendered as **plaid**, because the wave directions were near-axis and
  the high-frequency terms carried too much amplitude, which the normal step then
  amplified.

## Collision

`ConcavePolygonShape3D` built from the carved mesh, so a body stands on the BED
rather than on ground that is no longer there.

**Static geometry only.** There is no water volume, nothing floats and nothing
gets wet. Buoyancy belongs to the terrain overhaul; pretending otherwise here
would be worse than saying so.

## Validation

`Dev tools/Validation/pond_test.gd` — 28 assertions, headless, no renderer:
non-destructiveness, the density refusal, geometry, normals (none inverted),
shape controls, the exclusion API, and collision.

The LOOK is judged from `Pond Demo.tscn`'s captures
(`-- "--pond-shots=<dir>"`), not from assertions.

## Future integration boundary

When the grid is overhauled, the integration points are:

1. the grid's ground mesh must be dense enough — `analyse()` says so;
2. grass, rock and prop placement queries `get_exclusion_bounds()` then
   `contains_world_point()`;
3. `mow_item` / progress accounting must exclude submerged cells, or a lawn with
   a pond can never reach 100%;
4. pond parameters would come from the job seed, so a contract's pond is the
   same every time it is loaded.

None of that is built.
