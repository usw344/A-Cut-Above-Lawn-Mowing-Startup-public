# Public API Reference

Status: **Current** — 2026-08-21.

The boundaries other code is allowed to call. Anything not listed here is
internal to its owner, whatever its visibility.

Every significant project-owned script carries the same header block: **ROLE**,
**PUBLIC API**, **SIGNALS**, **INVARIANTS** and, where relevant, **PERSISTENCE
OWNERSHIP**. A script that deliberately exposes nothing says `PUBLIC API: None`.
This page is a map of those headers, not a replacement for them.

## The rule

> Reach for the owner, not for the node.

The mowing scene exposes `property()` and `lawn()`. `SaveService`, the trailer
director and every validation runner ask for those. None of them looks a node up
by name, so renaming or restructuring the scene cannot break them.

---

## Application layer (autoloads)

Owners and boundaries are described in
[Application layer](../application-layer.md) and
[Architecture](../architecture.md). In brief:

| Autoload | Owns | Must never |
|---|---|---|
| `GameSession` | routing, session state, **the one money balance**, the completion pathway | be bypassed for payment or scene changes |
| `JobManager` | job domain state, offers, expiry, history | change scenes |
| `WorldClock` | game time, day, season, weather STATE | be second-guessed by a scene's own clock |
| `SaveService` | file I/O and restoration orchestration | own domain state |
| `AppUI` | transitions, notifications, cursor authority | be bypassed by writing `Input.mouse_mode` |
| `GameSettings` | player settings and their application | |
| `Economy` / `MowerUpgrades` | prices and per-machine upgrade levels | hold a balance |
| `MowerFuel` | fuel RULES; `model` stores the level | |
| `model` | LEGACY shared state | grow |

---

## The mowing scene

`Game/M.V.P/MVP.gd`, the root of `Minimum Viable Game.tscn`.

```gdscript
property() -> ACAProperty          # the generated property
lawn() -> ACALawn                  # the mowing state
mowing_progress() -> float         # 0.0 - 1.0
mower_fuel_fraction() -> float
current_mower_is_powered() -> bool
restart_current_job() -> void
dev_complete_current_job() / dev_refuel_now() / dev_drain_fuel()
dev_toggle_auto_refuel() / dev_toggle_debug_hud() / dev_set_time_of_day(name)
dev_set_reported_progress(fraction)
```

`dev_*` is development tooling and is never on a player path.

**Invariant:** there is ONE completion entry point, `_finish_job()`. Natural
100% and the development helper both reach it, and it calls
`GameSession.complete_current_job()`.

---

## Property generation

`Mowing Section/Property/`. Full description in
[Property, terrain and lawn](../systems/property-and-lawn.md).

### ACAProperty

```gdscript
build(params: ACAPropertyParams) -> void
build_for_job(job: ACAJob) -> void
params() / terrain() / lawn() / features() / grass() / foliage()
is_built() -> bool
ground_height_at(x: float, z: float) -> float
lawn_bounds() -> AABB
property_bounds() -> AABB
mower_start_transform() -> Transform3D
statistics() -> Dictionary
signal built()
```

**Invariants:** `build()` is synchronous and every query is valid the moment it
returns. A property is generated around this node's own origin and must not be
moved afterwards.

### ACAPropertyParams

```gdscript
static for_job(job: ACAJob) -> ACAPropertyParams     # THE Job System integration
static for_seed(seed: int, lawn_size: int) -> ACAPropertyParams
static preset(name: StringName, lawn_size := 144) -> ACAPropertyParams
const PRESET_NAMES                                   # open, light_forest, wooded, pond, wooded_pond, default
to_dictionary() / static from_dictionary(data)
duplicate_params() -> ACAPropertyParams
lawn_half_extent() / near_extent() -> float
```

**Invariant:** `for_seed()` draws its values in a FIXED ORDER. Inserting a draw
in the middle changes every existing property. Append, or bump
`GENERATION_VERSION`.

**Persistence:** this resource IS the property in a save file.

### ACATerrain

```gdscript
build(params, features := null) -> void
height_at(x: float, z: float) -> float       # world space
surface_height_at(x, z) -> float             # the height of the surface DRAWN
normal_at(x: float, z: float) -> Vector3
slope_at(x: float, z: float) -> float        # 0 flat, 1 vertical
base_height_at(x, z) / base_height_world(x, z) -> float
bounds() -> AABB                             # the near field
world_bounds() -> AABB                       # including the distant rings
near_extent() -> float
contains(x: float, z: float) -> bool
collision_body() -> StaticBody3D
ground_material() -> ShaderMaterial
set_lawn_mask(mask: Texture2D, centre: Vector2, size: float) -> void
statistics() -> Dictionary
```

**Invariant:** `height_at()` agrees with the rendered near mesh. Both read the
same baked lattice with the same triangle split, and `Property Test` asserts it
against the committed mesh arrays.

**Past the near field, `height_at()` is not what a camera sees.** The distant
rings are coarse on purpose - their radial step grows past a hundred units - so
the middle of one of their triangles sits well below the height function it was
sampled from. `surface_height_at()` answers with the surface that is actually
drawn: inside the near field it is `height_at()` to the bit, and outside it the
height function is low-passed over the ring's own span. **Anything PLACED beyond
the near field must use it.** The far tree band used `height_at()` and hung over
the hills for exactly this reason.

### ACALawn

```gdscript
signal mowing_progress_changed(fraction: float)

build(params, terrain, features := null) -> void
reset() -> void

mow_deck(previous: Transform3D, current: Transform3D, deck: ACAMowerDeck) -> int
mow_swath(from: Vector3, to: Vector3, half_width: float) -> int
mow_disc(centre: Vector3, radius: float) -> int

total_item_count() / mowed_item_count() -> int
mowed_fraction() -> float
cell_count() -> int
is_mowable(world_position: Vector3) -> bool
is_cut(world_position: Vector3) -> bool
lawn_centre() -> Vector3
lawn_half_extent() -> float
lawn_bounds() -> AABB
cut_mask() -> Texture2D

cut_state() -> Dictionary
restore_cut_state(data: Dictionary) -> bool
apply_legacy_mowed_items(names: PackedStringArray, legacy_grid_size: int) -> int
mowed_item_names() -> PackedStringArray
restore_mowed_items(names: PackedStringArray) -> int
```

`mowing_progress_changed`, `total_item_count()`, `mowed_item_count()`,
`mowed_fraction()`, `mowed_item_names()`, `restore_mowed_items()`,
`mow_swath()` and `mow_disc()` are the names the previous lawn exposed. They are
kept deliberately, because the HUD, the Job System integration and the trailer's
lawn adapter are written against them.

**Invariants:**

- A cell that is not MOWABLE can never become CUT.
- `total_item_count()` counts MOWABLE cells only. **That is what makes a pond
  property completable without a single pond-specific rule in the mowing code.**
- A cell is one world unit, matching the terrain lattice.
- The cut mask uploads at most once per frame, never per cut.

**Persistence:** owns the mowing half of the save block.

### ACAMowerDeck and ACAMowerCutter

```gdscript
# ACAMowerDeck
static for_mower(mower: Node) -> ACAMowerDeck
static make(width: float, length: float, forward := 0.0) -> ACAMowerDeck
half_width / half_length / forward_offset          # WORLD units
corners(machine: Transform3D) -> PackedVector2Array

# ACAMowerCutter
signal cut(cells: int)
bind(mower: Node3D, lawn: ACALawn) / unbind() / is_bound()
deck() -> ACAMowerDeck
on_blades_active(collisions := [])                 # the signal target
resync()                                           # forget the previous pose
cells_cut() -> int
```

**Invariant:** deck sizes are WORLD units declared on each mower controller
(`DECK_WIDTH`, `DECK_LENGTH`, `DECK_FORWARD`), so re-scaling a machine's model
cannot change contract length or fuel balance.

**Invariant:** a jump larger than `REPOSITION_DISTANCE` is a placement, not
driving. A save restore or a staged shot cannot mow a stripe across the
property. Call `resync()` after moving a machine deliberately.

### The feature boundary

```gdscript
# ACAPropertyFeature - implement all of these for a new feature
prepare(base_height: Callable) -> void
bounds() -> AABB
terrain_offset_at(x: float, z: float) -> float
exclusion_at(x: float, z: float, ground_y: float) -> float
blocks_mowing() / blocks_grass() / blocks_foliage() -> bool
is_solid() -> bool         # does the machine physically collide with this?
clearance() -> float       # clear ground it owes the deck, world units
build_nodes(parent: Node3D, terrain: Node3D, params: ACAPropertyParams) -> void
feature_id() -> StringName
const EXCLUDED_THRESHOLD := 0.5

# ACAFeatureSet
add(feature) / features() / is_empty() / count()
prepare(base_height: Callable)
terrain_offset_at(x, z) -> float
mowing_exclusion_at(x, z, ground_y) -> float
grass_exclusion_at(x, z, ground_y) -> float
foliage_exclusion_at(x, z, ground_y) -> float
is_mowable(x, z, ground_y) -> bool
build_nodes(parent, terrain, params)
```

**Invariant:** every feature method is PURE. Same arguments, same answer, no node
access, no frame dependence. That is what lets the terrain bake, the collision
height map, the lawn layout, the grass placer and a save-time reconstruction all
agree.

**Nothing downstream asks WHY an area is excluded.** A rock cluster, a garden
bed or a building footprint is a new class implementing these methods; the lawn
does not change. Three of them exist: `ACALawnObstacles` (solid),
`ACALawnBeds` (not solid) and `ACAPropertySurrounds` (not solid, and outside the
playable boundary entirely).

**A solid feature owes the deck clear ground.** What stops the machine is the
CHASSIS, and on most of the fleet the chassis reaches further than the cutting
deck, so the band between a collision surface and the deck's reach is ground the
player can see and can never cut. Every solid feature answers
`ACAMowerClearance.REQUIRED` unless it has a reason of its own.

### ACAMowerClearance

```gdscript
const REQUIRED           # what a solid feature adds to its own footprint
const WORST_SHORTFALL    # the measured part of it
const SAFETY             # the judged part of it
static measure_scenes() -> Dictionary   # re-derive it, for Property Test
```

**Invariant:** it is a property of the FLEET, not of the machine currently in
play. A property is generated without knowing which machine turns up to mow it,
and a save may have been written while the player owned a different one.

### ACAPropertyArchetype

```gdscript
enum Kind { RURAL, SUBURBAN, PARK, LANDSCAPED }
static for_property_type(property_type: int, property_seed: int) -> Kind
static apply(params: ACAPropertyParams) -> void      # reshape in place
static name_of(kind) -> String
static description_of(kind) -> String                # one player-facing line
static short_description_of(kind) -> String          # three words, for a card
static has_surrounds(kind) -> bool
```

**Invariant:** `apply()` never draws a random number. Every value it changes was
already drawn by `ACAPropertyParams.for_seed()`; it only moves that value into
this archetype's range, keeping where in the range the seed put it. The draw
ORDER is untouched, so no existing property moves.

### ACALawnBeds and ACAPropertySurrounds

```gdscript
static ACALawnBeds.for_params(params, lawn_centre, existing) -> ACALawnBeds
beds() -> Array[Dictionary]     # { position, radius, squash, yaw }
count() -> int

static ACAPropertySurrounds.for_params(params, property_centre) -> ACAPropertySurrounds
plots() -> Array[Dictionary]    # what was laid out, for diagnostics
count() -> int
```

**Invariant:** neither is solid and neither builds a collision body.
`ACAPropertySurrounds` also answers `blocks_mowing()` FALSE, deliberately: every
plot is outside the playable boundary, and a layout bug that put a driveway over
the lawn should show up as a driveway drawn on the grass rather than as a
contract that silently finishes at ninety-four per cent.

### ACAPondFeature

```gdscript
static from_params(property_params, centre_world: Vector2) -> ACAPondFeature
carver_params() -> ACAPondCarver.Params
water_world_height() -> float
centre() -> Vector2
radius() -> float
shore_factor_at(x: float, z: float) -> float   # for composing rocks and shrubs
water_node() -> MeshInstance3D
is_prepared() -> bool
```

**Invariant:** every geometric answer comes from `ACAPondCarver`, so the carved
height field, its collision, the shoreline, the grass exclusion and the mowing
exclusion are all the same curve.

### Rendering

```gdscript
# ACALawnGrass
build(params, terrain, lawn, features) -> void
statistics() / instance_count() / node_count()
set_quality(level: int)          # 0 low, 1 medium, 2 high
material() -> ShaderMaterial

# ACAForest
build(params, terrain, lawn, features) -> void
statistics() / instance_count() / node_count()

# ACAGrassMesh
static near_tuft() / mid_tuft() / far_tuft() -> ArrayMesh
static build_tuft(blades, segments, height, width, spread, seed) -> ArrayMesh

# ACATreeProxy
static conifer(detail: int) / broadleaf(detail: int) -> ArrayMesh
static material() -> StandardMaterial3D
```

**Invariant:** placement is a pure function of the property seed and position.
Two builds of one property put every blade in the same place.

**Invariant:** no grass is placed where a feature excludes it, nor inside the
lawn rectangle on a cell the lawn says is not mowable. Grass the mower cannot
reach is never grown.

---

## The pond prototype

`Mowing Section/Experimental/Pond/`. The demo and its test still stand alone;
gameplay reaches it only through `ACAPondFeature`.

```gdscript
# ACAPondCarver - pure, static, no nodes
static analyse(source_mesh: Mesh, params: Params) -> Dictionary
static carve(source_mesh: Mesh, params: Params) -> Result
static shore_factor_at(v: Vector3, params: Params) -> float
static make_shape_noise(params: Params) -> FastNoiseLite
static shore_factor_with(v: Vector3, params: Params, noise: FastNoiseLite) -> float
static depth_offset_at(v: Vector3, params: Params, noise := null) -> float
```

The last three were added on 2026-08-20 so a procedurally generated height field
could apply the same displacement while generating, instead of carving a mesh
afterwards. `ACAPond` and `Pond Demo.tscn` are untouched.

**Invariant:** the source mesh is never modified. Every carve builds a new
`ArrayMesh` from a copied vertex buffer.

---

## Media tooling

`Game/Demo/Trailer/`. Development only; never on a player path.

```gdscript
# ACATrailerLawnAdapter
bind(lawn: ACALawn) / is_bound() / mowed_fraction()
on_mower_moved(from: Vector3, to: Vector3)
stage_stripes(centre, yaw, count, length, spacing := -1.0, half_width := -1.0) -> int
cut_line(from, to, half_width := -1.0) -> int
clear_around(centre: Vector3, radius: float) -> int

# ACATrailerMowerAdapter
set_ground_provider(provider: Callable)     # (x, z) -> ground height
bind(mower: CharacterBody3D, ground_y: float) / release() / is_bound()
place(where: Vector3, yaw: float)
drive_path(points, speed, start_at := 0.0) / drive_straight(speed, turn_rate := 0.0)
stop() / is_driving() / position_now() / yaw_now() / position_after(seconds)
set_suspension(bob_height, bob_hz, roll_scale) / reset_suspension()
static visual_lift(mower: Node3D) -> float
```

**Invariant:** every adapter puts back what it borrows. `Trailer Test` asserts
that gameplay tuning is untouched after a run.

---

## Weather

`Weather/Preset Manager/preset_manager.gd` remains the project-facing API; the
LOOK lives in `Weather/Visual/weather_visual_adapter.gd` and the reusable
package under `addons/aca_sky3d_environment/`. See
[Weather, time of day, and audio](../systems/weather-time-and-audio.md).

```gdscript
apply_world_state_immediate(weather_preset: String, hour: float)
apply_weather_preset(name: String) / apply_time_of_day_preset(name: String)
set_time_of_day_normalized(hour: float) / smooth_set_time_of_day(target, duration := -1.0)
set_weather_tracking_target(node: Node3D)
set_weather_ground_reference(world_y: float)
set_audio_player(player: AudioStreamPlayer)
get_and_set_mower_global_position(position: Vector3)
```

**Invariant:** `res://addons/sky_3d/` is READ ONLY for this project.
