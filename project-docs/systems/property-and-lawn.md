# Property, Terrain and Lawn

Status: **Current playable runtime.** Replaced the `Custom_Gridmap` /
`Multi_Mesh_Chunk` lawn and the authored `Terrain Manager` terrain on
2026-08-20. Reconciled with generation version 6 on 2026-08-30.
Primary path: `Mowing Section/Property/`
Retired predecessors: `Soft Delete/2026-08-20 Legacy Lawn and Terrain/`

## What a property is

One generated mowing job site: the ground, the landscape around it, the mowable
lawn, whatever features sit on it, and everything growing.

```
ACAProperty                  composes, decides the order, owns nothing else
 ├─ ACAFeatureSet            the generic exclusion boundary
 │   ├─ ACAPondFeature       carves the ground, refuses grass, excludes cells,
 │   │                       and stops the machine at its shoreline
 │   └─ ACALawnObstacles     the solid rocks and shrub clumps ON the contract
 ├─ ACATerrain               the height field, the mesh, the collision, the queries
 ├─ ACALawn                  the compact mowing state and the cut mask
 ├─ ACAPropertyBoundary      the playable edge: collision, and the fence on it
 ├─ ACALawnGrass             grass placement and rendering
 └─ ACAForest                trees, shrubs and rocks, all OUTSIDE the boundary
```

The build ORDER is the design:

1. Features are chosen from the parameters, **before** the ground exists, so the
   ground can be dug. The pond goes in first and the obstacles are rolled
   against the set as it already stands, so a lawn rock is never dropped in the
   water.
2. The terrain bakes, with feature offsets applied while the height is generated.
3. The lawn lays its cells out and asks the features which are mowable, using
   the terrain height that now exists.
4. Features add their own nodes - a water surface at a height that was measured
   rather than guessed, the pond's shoreline collision traced from the ground
   that now exists, and the obstacles' bodies and meshes.
5. **The boundary**, before anything is planted, because the foliage placer asks
   it where the property stops.
6. Grass, then foliage, both of which ask the lawn, the features and the
   boundary what is allowed where.

Nothing here is saved. `ACAPropertyParams` is the save.

## ACAPropertyParams - the whole property as data

`Mowing Section/Property/aca_property_params.gd`

One `Resource` holding a seed and about thirty numbers. Two properties built
from equal parameters are identical down to the position of every tree, which
is what makes a property cheap to persist and safe to rebuild.

| Group | Controls |
|---|---|
| identity | `seed`, `generation_version` |
| size | `lawn_size` (96 / 144 / 192), `near_margin` |
| terrain | `terrain_amplitude`, `broad_hill_strength`, `fine_variation`, `micro_relief`, `playable_flatness`, `flatten_falloff` |
| distant landscape | `distant_hill_strength`, `distant_hill_scale`, `distant_hill_start`, `landscape_radius` |
| vegetation | `forestiness`, `tree_cluster_strength`, `lawn_openness`, `shrub_density`, `rock_density`, `meadow_density` |
| features | `feature_probability`, `pond_probability` (both retained; see the pond note below) |
| pond | `pond_enabled`, `pond_offset`, `pond_radius`, `pond_ellipse_ratio`, `pond_irregularity`, `pond_depth`, `pond_bank_fraction`, `pond_water_level`, `pond_seed` |
| appearance | `wind_direction`, `wind_speed`, `lawn_colour_bias`, `dryness` |

**Job integration is one function.** `ACAPropertyParams.for_job(job)` derives
everything from the contract's existing `seed` and `grid_size.x`. No field was
added to `ACAJob`, the Job System does not know properties exist, and accepting
the same contract twice always drives to the same address.

!!! warning "Draw order is part of the format"
    `for_seed()` draws its values in a fixed order. Inserting a draw in the
    middle changes every existing property. Append, or bump
    `GENERATION_VERSION`.

Development presets - `open`, `light_forest`, `wooded`, `pond`, `wooded_pond` -
exist for the visual probes. They are not job categories.

## ACATerrain - the ground

`Mowing Section/Property/aca_terrain.gd`

### The height function

```
height(x, z) =
      broad noise  * broad_hill_strength * 0.62
    + fine noise   * fine_variation                 } x terrain_amplitude
    + micro noise  * micro_relief
    + distant hills, ramped in with radius
```

all multiplied inside the lawn by `1 - playable_flatness`, fading out over
`flatten_falloff` units past the lawn edge. Distance to the LAWN RECTANGLE, not
to the centre, so the flat area is a lawn rather than a circle. Micro relief
survives inside the lawn at about a third weight, so a mown lawn is never a
mathematically perfect plane.

Feature offsets are added on top - see the pond below.

### Two scales

| | Extent | Cell | Purpose |
|---|---|---|---|
| baked lattice | lawn/2 + 44 | 1.0 | queries and collision |
| core mesh | lawn/2 + 22 | 1.0 | the ground the player drives on |
| distant rings | out to `landscape_radius` (3,600 by default) | grows from 1.0, capped at `distant_hill_scale / 5` | the scenery |

The rings are concentric square annuli. The innermost shares its vertex count
per side with the core mesh's outer edge, so the two surfaces meet without a
crack; as the radial step grows the tangential count HALVES and a fan of three
triangles bridges the two resolutions. That is what keeps a landscape four
kilometres across from costing more than the lawn.

### Collision

One `HeightMapShape3D` built from the baked lattice. No conversion, no trimesh,
no per-cell body: the shape IS the data structure the queries read.

### Public API

```gdscript
build(params, features)
height_at(x, z) -> float          # world space; matches the rendered surface
normal_at(x, z) -> Vector3
slope_at(x, z) -> float           # 0 flat, 1 vertical
base_height_at(x, z) -> float     # before feature offsets, terrain-local
base_height_world(x, z) -> float  # before feature offsets, world
bounds() -> AABB                  # the near field
world_bounds() -> AABB            # including the distant rings
near_extent() -> float
contains(x, z) -> bool
collision_body() -> StaticBody3D
ground_material() -> ShaderMaterial
set_lawn_mask(texture, centre, size)
statistics() -> Dictionary
```

`height_at()` reads the baked lattice with the same triangle split the mesh was
built with, so a query and the surface a camera sees are the same number.
`Property Test` asserts that against the committed mesh arrays.

!!! danger "Do not move the terrain after `build()`"
    The lattice and the lawn grid are anchored where they were built. The
    property is generated around its own origin; place the NODE, do not offset
    the generation.

## ACALawn - the mowing state

`Mowing Section/Property/aca_lawn.gd`

One byte per square world unit. A Large lawn is 36,864 cells and 72 KB.

```
_flags[i]   bit 0 MOWABLE     counts towards completion
            bit 1 CUT         has been cut
_dirs[i]    the heading the mower was on when it cut, a byte over a full turn
```

Counters move only when a cell really changes, so progress is O(1) and nothing
ever rescans the lawn.

**There are no physics bodies.** `Property Test` asserts zero.

### The cut mask is the bridge to rendering

The same state is mirrored into one RGBA texture, one texel per cell:
R cut, G heading, A mowable. The grass and ground shaders read it. Cutting
writes bytes into an `Image` and uploads it at most once per frame - never per
cut, never a MultiMesh rebuild, never a node touched. That is the whole reason
the lawn can be dense enough to look like a lawn.

### Mathematical mowing

```gdscript
mow_deck(previous: Transform3D, current: Transform3D, deck: ACAMowerDeck) -> int
```

The deck is an oriented rectangle. Between one update and the next the machine
sweeps a band of ground, and the sweep is stamped as a series of rectangles
along the path rather than as one convex hull, because a rectangle test is exact
and a hull is not: a machine that turned while it moved really did cut a curve.

The step is bounded by the deck's own length, and the sweep INCLUDES the pose it
started from, so:

- however fast the machine moves it cannot leave an uncut strip behind it
  (`Property Test` drives a sixty unit leap in one update and asserts no gap);
- the ground directly under a machine that has just been placed is cut, rather
  than standing until it has driven a deck length.

### Compatibility and persistence

```gdscript
signal mowing_progress_changed(fraction)
total_item_count() / mowed_item_count() / mowed_fraction()
mow_swath(from, to, half_width) / mow_disc(centre, radius)
mowed_item_names() / restore_mowed_items(names)
cut_state() / restore_cut_state(dict)
apply_legacy_mowed_items(names, legacy_grid_size)
is_mowable(world_position) / is_cut(world_position)
lawn_centre() / lawn_half_extent() / lawn_bounds() / cell_count()
cut_mask() -> Texture2D
reset()
```

`mowing_progress_changed`, `total_item_count()`, `mowed_item_count()`,
`mowed_fraction()`, `mowed_item_names()`, `restore_mowed_items()`,
`mow_swath()` and `mow_disc()` are the names the previous lawn exposed and are
kept deliberately: the trailer's lawn adapter, the HUD and the Job System
integration are written against them and did not have to change.

`total_item_count()` counts MOWABLE cells only. **That single decision is what
makes a property with a pond completable without one pond-specific rule anywhere
in the mowing code.**

## ACAMowerDeck and ACAMowerCutter

`aca_mower_deck.gd` resolves a machine's cutting footprint. It is declared in
WORLD units on each mower controller, so re-scaling a mower model to look better
can never quietly change how long a contract takes or whether a tank of fuel is
enough to finish one.

| Machine | `DECK_WIDTH` | `DECK_LENGTH` | `DECK_FORWARD` |
|---|---:|---:|---:|
| rider | 5.6 | 2.4 | 0.4 |
| powered walk-behind | 5.2 | 2.0 | 0.6 |
| push | 4.6 | 1.7 | 0.5 |

A machine that declares nothing falls back to its largest box collision shape
times `CHASSIS_TO_DECK`, then to a documented constant.

`aca_mower_cutter.gd` is the join. It listens to the mower's `collided` signal -
the same signal the old lawn cut from, emitted every physics frame while the
engine runs and stopped when the tank is empty - and turns the transform
difference into `mow_deck()`. **No mower controller had to learn about the new
lawn, and an empty tank still stops the blades for exactly the reason it always
did.** A jump larger than `REPOSITION_DISTANCE` is treated as a placement, so a
save restore or a staged trailer shot cannot mow a stripe across the property.

## ACALawnGrass - what grows

`aca_lawn_grass.gd`, `aca_grass_mesh.gd`, `shaders/aca_grass.gdshader`

The near field is cut into 24 unit tiles. Each tile carries two MultiMeshes:
detailed tufts for the ground near the camera and broader, sparser clumps for
the middle distance. Godot's own visibility ranges fade between them and cull
the rest, so the number of tufts DRAWN depends on where the player is looking
rather than on how big the contract is.

| Band | Mesh | Density | Range |
|---|---|---|---|
| near | 10 blades, 2 segments | one per 0.71 units | 0 - 46, 17 fade |
| mid | 5 blades, 1 segment, 1.62x wider | every third tuft | 29 - 165, 44 fade |
| far | none | - | the ground shader carries the colour |

The mid band used to be the FAR clump - four broad paddles - blown up to 1.9x.
It covered the ground, and it covered it with a visibly different plant, so the
lawn changed material halfway across the property. It is now the same kind of
shape as the near tuft with fewer leaves and one segment fewer, widened only as
far as the tufts it stands in for, and the two bands cross-fade over a much
longer stretch of ground. What gives a distance band away is not the band, it is
how short a run of ground one representation takes to become the other.

The tuft meshes are **generated at runtime**, not imported. The old lawn used a
single imported blade cluster about three world units tall on a two unit
lattice, which read as a crop: identical, upright, taller than the machine
cutting it, and with nothing for wind or a cut to act on. A generated mesh
carries UV.y as the height fraction along each blade (so a tip can move while
its root stays planted) and UV.x as a per-blade id (so blades inside one tuft
move apart from each other), and it is opaque, which is what makes a dense lawn
affordable - no alpha cutout, no depth prepass, no sorting.

Blade normals are nearly VERTICAL rather than perpendicular to the leaf, and the
fragment shader undoes Godot's back-face normal flip. A lawn is read as a
surface catching the sky; blades lit by their own faces turn every gap between
them black.

Grass is never placed where a feature excludes it, nor inside the lawn rectangle
on a cell the lawn says is not mowable. **Grass the mower cannot reach is never
grown in the first place.**

Outside the lawn the same material draws a wild meadow: taller, yellower,
never cuttable. Its height starts barely above the kept lawn and grows into
itself over about seventeen units, with a wandering edge, so the property
boundary reads as a change in upkeep rather than as a fence of grass.

**Its DENSITY makes the same journey.** The meadow is thinned by skipping
candidates off the lawn's own lattice, and dropping straight to the meadow's
spacing the moment a candidate left the rectangle put a hard step in the turf on
the property line: from a mower's seat the ground ahead went abruptly thin and
dark along a dead straight edge. The thinning is now ramped over fifteen units
on the same wandering distance the height uses, so the grass and the ground
shader's own wide, noisy transition agree.

### Cut grass and stripes

A cut blade keeps its root, loses most of its height, lies over along the pass
that cut it, and goes BRIGHTER and slightly warmer. It is never darker: a mown
lawn that goes dark reads as exposed soil.

Three things decide whether that reads as turf or as scribble, and the first two
are geometry:

- **The leaf stands back up.** Every blade in the tuft leans out horizontally
  towards its tip, and that lean is authored in the XZ plane. Scaling only Y
  leaves the full horizontal reach on a blade half its former height, which lays
  it flat: a bright stroke on dark ground. The mesh carries each leaf's own AXIS
  in `COLOR.rg`, so the shader can pull the tip back towards vertical WITHOUT
  also narrowing the leaf - scaling the whole XZ position tapers every mown leaf
  to a needle, and the ground shows between the needles. The root is let out a
  little and the leaf is drawn wider, because height is what a mower takes and
  width is not.
- **The lie points along the pass, in WORLD space.** Applied straight to
  `VERTEX` it is turned by each tuft's own random yaw, which scatters the lay
  directions across the lawn. It is projected through the model axes instead, so
  a pass really does lay its grass one way and its neighbour the other, and
  `cut_lean` reads in world units.
- **The tone closes up.** A short lawn is read as one surface, and every step of
  contrast between the leaves and the thatch they stand in turns that surface
  back into confetti. The cut tone in the grass and the cut tone in the ground
  are close together, the root of a cut leaf is darker than its tip, and a mown
  stub does not glow: the backlight that makes a standing leaf look thin is
  mostly taken away from it.

Stripes work the way real ones do. The mask carries the heading the mower was on
over a FULL turn, so two neighbouring passes lay the grass over in opposite
directions; the shader brightens grass laid away from the viewer and darkens
grass laid towards it. Nothing is painted on, and the pattern changes as the
player turns.

The visual cut boundary is sampled at a position nudged by a per-tuft hash, so
it follows the mower rather than the logical grid, and each tuft also DISAGREES
with its neighbours about where in the mask's filtered ramp "cut" begins. The
last pass therefore ends in a mown margin rather than on a line. Nothing about
the logical cut moves; this is entirely how it reads. The ground shader does the
same with a noise offset.

**Stripes give out with distance.** They are worth the most where the player is,
and one band per pass across a Large lawn seen from the air is a ripple a couple
of pixels wide. The ground shader fades them out between 190 and 460 units, so a
lawn seen from the far side of the property still shows its passes and one seen
from half a kilometre settles into a single mown tone.

## ACAForest - the wood

`aca_forest.gd`, `aca_tree_proxy.gd`

`forestiness` moves three things at once rather than multiplying a tree count:

- the **belt**: how close to the property trees may come and how fast they
  thicken behind that line, with a wandering front edge;
- the **clusters**: a low-frequency field that gathers trees into groves;
- the **openings**: a second field that cuts clearings through the clusters, so
  a dense wood still has depth and broken sightlines rather than a wall.

The mowable rectangle is never a candidate at any setting.

### Distance is a placement decision, not a per-frame switch

The player never leaves the property, so distance from the property centre and
distance from the camera are within a few dozen units of each other. A tree is
authored into the band it belongs to and stays there, which is why nothing pops.

| Band | Radius | Geometry |
|---|---|---|
| near | 0 - 190 | the real imported trees, tiled for frustum culling |
| mid | 190 - 560 | `ACATreeProxy` stand-ins, about 30 triangles |
| far | 560 - 1,500 | coarse stand-ins, about 12 triangles, 1.45x scale, denser |

**Everything past the near field is placed on `surface_height_at()`, not on
`height_at()`.** The far band used the height function, which the coarse ring
mesh under-samples by more than a tree, and the result was a scatter of specks
hanging over the hills. See [Public APIs](../reference/public-apis.md#acaterrain).

The stand-ins are real geometry rather than billboard impostors. An impostor has
to be rendered, stored and re-rendered when the light changes, and it turns as
the camera moves, which is what makes a distant wood shimmer. A dozen triangles
costs about the same, never turns, and casts a real silhouette against the
hills.

### What keeps it from looking generated

Fourteen species rather than nine, including one standing dead tree in about
thirty: a wood with nothing but healthy canopies reads as a texture, and a single
bare crown against the sky makes the same treeline read as a place.

Beyond the species list, four fields do the work:

| | |
|---|---|
| the STAND | a slow noise decides most of a tree's height and the tree itself decides the rest. Scaling every tree by its own random number gives an even canopy made of uneven trees; scaling a whole stand together gives a canopy line that rises and falls, which is what reads as depth from the lawn |
| the TINT | canopies are all one green if nothing varies them, and one green over a hundred trees is the loudest signal that a wood was generated. Each tree draws a tint mostly from a slow field, so a stand agrees with itself, partly from its own position, so a stand is not one flat colour. It is carried as a per-instance MultiMesh colour into a copy of the mesh's own material |
| the UNDERSTORY | young trees along the front of the belt, on the same density field as the wood, so they never appear in a clearing the wood was told to leave open. They are the layer the eye uses to judge how far away the wood is: they overlap the trunks behind them, so the trunks stop reading as a fence |
| the EDGE | the long wander that decides where the wood swings in and out, plus a shorter wave that decides whether that swing arrives as a smooth curve or as a broken margin with spurs and bays in it |

Shrubs gather into thickets at the wood's edge and along the pond bank. Reeds -
tall grass clumps - stand at the water's edge and thinly at the foot of the
wood, which is the cheapest way to stop a hard line between two surfaces. Rocks
go where the ground CHANGES - a break of slope, the bank, the floor of a thicket
- with a small even scatter underneath.

Only the near trees cast shadows. **Saplings do not:** there are hundreds of
them, they are the smallest thing in the wood, and putting them in the shadow map
cost about a third of the frame for contact nobody was going to go looking for.

!!! danger "The pond bank is INSIDE the contract rectangle"
    Every prop pass used to begin by refusing any point within a metre or two of
    the mowable rectangle. That sounds like "stay off the lawn" and is in fact
    "stay away from the pond", because a pond dug into the middle of a lawn is
    surrounded by lawn on every side - which is why the bank had no shrubs, no
    reeds and almost no stones however hard the bank was weighted. The right
    question is not where the rectangle is, it is what the LAWN SAYS: a cell the
    lawn has marked unmowable is ground a feature has already taken, and nothing
    that grows there can cost the player a contract. `ACAForest._plantable()`.

## The generic feature boundary

`aca_property_feature.gd`, `aca_feature_set.gd`

Every feature answers the same three questions, and nothing downstream asks WHY
an area is excluded:

```gdscript
prepare(base_height: Callable)          # resolve reference ground before the bake
bounds() -> AABB                        # broad phase
terrain_offset_at(x, z) -> float        # how the ground moves
exclusion_at(x, z, ground_y) -> float   # 0 clear .. 1 fully taken
blocks_mowing() / blocks_grass() / blocks_foliage()
is_solid() -> bool                      # does the machine physically hit this?
clearance() -> float                    # clear ground it owes the deck
build_nodes(parent, terrain, params)
```

Every method is pure: same arguments, same answer, no node access, no frame
dependence. That is what lets the terrain bake, the collision height map, the
lawn layout, the grass placer and a save-time reconstruction all agree.

`ACAFeatureSet` combines them, maxing exclusions rather than summing them, and
caches XZ rectangles so the common "nothing near here" answer costs four float
comparisons. An empty set answers "clear" at close to no cost.

A rock cluster, a garden bed or a building footprint are new classes
implementing the same methods. The lawn does not change. Three of them now
exist: `ACALawnObstacles`, `ACALawnBeds` and `ACAPropertySurrounds`.

### `is_solid()` and the clearance a feature owes

`is_solid()` is the newest question and the one that fixed a real gameplay
fault. A feature that answers TRUE is something the machine physically collides
with, and a solid feature has to leave more clear ground than its own footprint:
what touches it is the CHASSIS, and on two of the three canonical machines the
chassis is wider than the cutting deck.

`ACAMowerClearance` owns that number, in one place, derived by measurement:

| machine | chassis X/2 | chassis Z/2 | deck W/2 | deck reach | sideways | head-on | min |
|---|---:|---:|---:|---:|---:|---:|---:|
| Push | 3.225 | 1.573 | 2.30 | 1.35 | 0.925 | 0.223 | 0.223 |
| Non-rider | 3.414 | 3.187 | 2.60 | 1.60 | 0.814 | 1.587 | **0.814** |
| Rider | 2.060 | 2.501 | 2.80 | 1.60 | -0.740 | 0.901 | -0.740 |

The player chooses the approach, so what matters per machine is the SMALLEST
shortfall over the directions available; what matters for the game is the worst
of those across the fleet, because a property is generated without knowing which
machine turns up to mow it. That is the non-rider's **0.814**, plus a judged
**0.60** for one-unit cells, uneven ground and imperfect steering:

```gdscript
ACAMowerClearance.REQUIRED == 1.42   # world units
```

`Property Test` re-derives the table from the real mower scenes and fails if the
constant has drifted, so it cannot go stale quietly. A second test walks the
real lawn of ten seeds - about 195,000 mowable cells - and asserts that not one
of them sits within `WORST_SHORTFALL` of any collision surface.

**The property edge needs no clearance band of its own**, and that is asserted
rather than assumed: the lawn stops `boundary_margin()` short of the fence, 15
units at the tightest, so the machine drives past the last row of lawn and back.

## The playable boundary

`aca_property_boundary.gd`

The world around a contract is scenery. It has hills, a treeline and a horizon
three kilometres out, and none of it is anywhere the player is meant to drive.
Before this existed nothing said so: the machine could leave the lawn, cross the
yard, drive **through** the wood (the trees are MultiMeshes and have never had
collision) and eventually run off the edge of the terrain collision forty-four
units past the lawn, where the world simply stops.

### One rectangle, derived, never duplicated

```
boundary half extent = lawn_half_extent() + ACAPropertyParams.boundary_margin()
boundary_margin()    = clamp(lawn_openness, 15.0, 26.0)
```

`lawn_openness` already described how much room a property leaves around its
lawn, so the yard is derived from it rather than from a new draw: the generator's
draw ORDER does not move and every existing seed keeps every value it had.

The floor of 15 units is what the mower needs. `ACAProperty.ARRIVAL_SETBACK`
puts the machine seven units off the lawn edge, and a machine that arrives
already touching the fence behind it is a machine that cannot reverse.

Everything that has to agree about where the property stops asks
`boundary_margin()` — the collision, the fence, the foliage placer, the minimap.
There is no second copy of the number anywhere downstream.

### The collision

**One `StaticBody3D`.** Each side is walked in segments of five world units, and
each segment is a box shape sitting at the middle of the ground beneath it,
tall enough to cover both its ends. A wall following a slope has no gap at the
joins and no lip to climb. A Large property is about 180 shapes on that one body,
which Jolt does not notice.

### The fence

Posts and rails, procedurally instanced as two MultiMeshes — so a whole property
boundary is two draw calls. Three treatments, chosen from a hash of the property
seed rather than from a new generator draw:

| Treatment | |
|---|---|
| `rustic_rail` | posts and two rails the whole way round |
| `low_rail` | posts and one low rail — more open, lets the wood behind read |
| `marker_posts` | posts only, wider spacing, with the wood closing the gaps |

**Every one of them puts posts on the line.** A boundary the player cannot see is
a boundary the player thinks is a bug. A denser wood is more likely to be left to
close its own edge; an open property has nothing else to mark the line with, so
it gets real fence.

### What this bought

The scenery does not need collision. Not one instance `ACAForest` places has a
physics body and none ever did; that was a problem only while the machine could
reach them. `_plantable()` and `_tree_density()` now both measure from the
BOUNDARY rectangle, so every tree, shrub and rock is outside the fence — with one
deliberate exception, the pond bank, which is inside the lawn rectangle on ground
the lawn has already marked unmowable and which the pond's own shoreline
collision keeps the machine away from.

A whole generated property is **four physics bodies**: the ground heightmap, the
boundary, the pond's shoreline ring and the lawn obstacles.

## Lawn obstacles

`aca_lawn_obstacles.gd`

The solid things standing ON the contract: rocks, and the occasional stubborn
shrub clump the owner has clearly mown around for years. Three to four on a
Small property, five to seven on a Medium, eight to twelve on a Large, scaled by
the `rock_density` the seed already drew.

It is **one feature holding a list**, not a feature each: one entry in
`ACAFeatureSet`, one broad-phase rectangle tested per grass tuft, one static body
carrying a sphere per obstacle, and two or three draw calls.

Through the same interface the pond uses, an obstacle:

- takes its ground out of `total_item_count()`, so the contract still finishes at
  exactly 100% with no obstacle-specific rule in the mowing code;
- refuses lawn grass out to `TIDY_MARGIN + ACAMowerClearance.REQUIRED` - half a
  unit so no tuft grows out of the side of a boulder, and 1.42 more because that
  band is ground the machine can see and cannot cut;
- refuses scenery on top of itself;
- and is **solid** — a sphere shape, so the machine slides off rather than
  catching on whichever facet it met.

It does NOT dig the terrain. A rock sits on the ground; it does not deform it.

### Placement is a route-planning problem

Every rule in `_roll()` is there because breaking it produces a property that is
either unfair or dull:

| Rule | Why |
|---|---|
| inset 7 units from the lawn edge | so the last pass round the perimeter is never jammed between a rock and the fence |
| 16 units clear of the arrival, and a 9-unit corridor in front of it | a contract that begins with the machine nose-first into a boulder reads as broken |
| clear of the pond and its bank | the pond is the older, larger claim |
| **11 units between any two rims** | the widest MACHINE in the game is the non-rider's chassis at 6.83 - wider than the widest deck - and the mowable strip left between two rocks is the gap minus two clearance bands. At the old 9.5 that strip was narrower than the machine that has to drive down it. |

Asserted over 90 properties in `Property Test`, and measured over 360 in the
composition audit.

### Deterministic obstacle layouts (generation version 6)

`ACALawnObstacles` selects a layout from a separate seed-derived stream after
the property shape has been decided. It proposes obstacle positions and then
applies the same safety acceptance rules used by the earlier scatter layout;
it does not alter the lawn's exclusion or mowing rules.

| Layout | Shape |
|---|---|
| `SCATTER` | distributed obstacles, the legacy/default pattern |
| `ISLAND` | a compact central grouping |
| `GAUNTLET` | a route-like sequence with controlled gaps |
| `AVENUE` | a spaced linear arrangement |
| `CORNERS` | groups biased toward the lawn corners |
| `PERIMETER` | obstacles following the outer working area |

Properties under 120 units use only `SCATTER` or `CORNERS`; larger properties
use the seeded distribution across all six layouts. Generation versions `<= 5`
continue to use `SCATTER`, preserving the layout of legacy saves. The current
safety constants are an 11-unit minimum rim gap, 7-unit edge inset, 16-unit
arrival clearance and a 9-unit arrival corridor.

The final safety audit covered 180 properties: the tightest obstacle gap was
11.00 units, the boundary approach was 7.00, the arrival clearance was 16.48,
and there were no quota misses. Equal seeds produce equal layouts. `Layout
Probe` reports 15/15.

Final layout measurements from the probe are:

| Layout | reach | excluded share | obstacle count |
|---|---:|---:|---:|
| Scatter | 0.76 | 0.21 | 1.61 |
| Corners | 0.91 | 0.52 | 4.28 |
| Island | 0.53 | 0.29 | 2.14 |
| Gauntlet | 0.70 | 0.22 | 1.45 |
| Perimeter | 0.72 | 0.21 | 1.72 |
| Avenue | 0.64 | 0.23 | 2.80 |

## The pond

`aca_pond_feature.gd`, built on the experimental prototype in
`Mowing Section/Experimental/Pond/`.

**Every generated property has one.** The two draws that used to decide whether a
property got a pond are still taken, in exactly their old positions, because the
draw order IS the save format; they now decide how generous the pond is instead.
A property that would have had one gets precisely the pond it had before, and a
property that would not gets a smaller, more modest one. The current property
generation is **6**; the pond probability draws remain in their historical
positions so the generator's draw order stays compatible.

Size is bounded by the LAWN rather than by a constant:

```
pond_radius = clamp(half * randf(0.19, 0.29) * modest_scale,
                    max(half * 0.15, 6.5),
                    min(half * 0.32, 34.0))
```

Measured over 360 generated properties, a pond takes a median 5% of the lawn and
never more than 10%, at every contract size.

**The shape is not redefined.** Every geometric answer comes from
`ACAPondCarver` - the prototype's `_shore_factor` - so the carved height field,
its collision, the shoreline, the grass exclusion and the mowing exclusion are
all the same curve.

The prototype carved a COPY of an existing mesh. A procedurally generated
terrain has no mesh to copy yet, so the same displacement is applied while the
height is being generated instead. Three small additions were made to
`pond_carver.gd` for that: `depth_offset_at()`, `make_shape_noise()` and
`shore_factor_with()`. `ACAPond` and `Pond Demo.tscn` are untouched and still
work.

| Question | Answer |
|---|---|
| Is the terrain actually carved? | Yes. `terrain_offset_at()` is subtracted while the height field is generated, so the visible mesh, the `HeightMapShape3D` and every query share one surface. |
| Is grass excluded? | Yes, and the band is measured from the COLLISION RING rather than from the water. Grass stops `ACAMowerClearance.REQUIRED` outside the ring and fades out over 1.1 units beyond that. |
| Does mowing progress exclude it? | Yes, and not by a special case: submerged cells are simply not MOWABLE, so they are not in `total_item_count()`. |
| Can the property reach 100%? | Yes. `Property Test` mows a `wooded_pond` property with a real deck and asserts `mowed_item_count() == total_item_count()`, and that nothing under the water was ever cut. |

The water line is measured from the ground BEFORE the pond dug into it, at the
pond centre, so it is stable and level. The water surface is a plane a little
wider than the shoreline; the terrain rises above it outside the pond and hides
the overhang, and the shader fades the last centimetres against the bed.

### Where the grass stops, and why it is measured from the ring

This used to be a HEIGHT test: grass stopped a fixed distance ABOVE the water.
How far out along the ground that landed depended entirely on how steep the bank
happened to be. On a shallow bank it was generous; on the steepest bank the
generator rolls it landed **inside the collision ring**, and the last band of
grass around the water was visible, counted towards completion, and impossible
to cut - because the ring stops the CHASSIS and the deck sits inside it.

The exclusion now measures the horizontal distance from the ring itself:

- inside the ring, fully excluded - the water and the damp bank the ring stands on;
- out to `ACAMowerClearance.REQUIRED` past it, fully excluded;
- fading to nothing over `SHORE_FADE` (1.1 units) beyond that.

Distance to the ring **polygon**, not to the radius on that ray. Where the
shoreline wanders inward the two differ by more than the clearance band is wide,
and it is the polygon the machine meets.

### One trace, three consumers

The ring is resolved once, in `prepare()`, from `base_height + depth_offset_at` -
which is precisely what `ACATerrain` bakes. The collision ring is built on it,
the grass exclusion is measured from it, and the minimap draws it.

The collision used to walk the baked height field a SECOND time, and the second
walk did not quite agree with the first: a lattice with linear interpolation
between its samples is not the continuous function the samples came from, and
the two answers differed by up to about a quarter of a unit on sloping ground.
Small, and enough to leave a couple of mowable cells per property sitting inside
the ring. There is now one curve, so there is nothing for the three to disagree
about.

### The machine does not get in

A pond dug into a heightfield is a hole with water drawn across it. Nothing
about that stops a machine driving down the bank, through the water plane and on
to the bed, where it sits in a bowl it cannot climb out of.

So the pond contributes a **shoreline collision ring**. The outline is TRACED,
not re-derived: forty-eight rays out from the pond centre, each binary-searched
twelve times for the radius at which the carved ground rises to 0.30 units above
the water line. That reads the height field, so it accounts for the bank shape,
the irregularity noise and whatever the surrounding land was doing.

- It is one `StaticBody3D` with a box per shoreline segment.
- It is a **ring, never a lid**. There is no shape over the water, so a machine
  that somehow got in would still be in it rather than standing on an invisible
  floor.
- It sits `ACAMowerClearance.REQUIRED` inside the edge of the ground the pond has
  made unmowable, so it can never stop the player reaching mowable grass.
- The same traced outline is what the minimap draws, so the map and the collision
  cannot disagree about where the water is.

`Containment Test` drives the real machine at the water from eight directions and
asserts it never reaches it — and, separately, that it still gets to the bank.

### What makes it read as a pond rather than as a hole with water in it

Four things, and only one of them is the water.

**The ground knows the water is there.** A shoreline is not a line, it is a band
of damp ground, and what gave the pond away was that mown turf ran straight into
the surface with nothing between them that had been wet recently. The ground
shader draws that band, driven by HEIGHT above the water rather than by distance
from a centre - which is why it follows an irregular outline exactly without the
shader being told anything about the pond's shape. `ACAPondFeature` hands it the
water line and a rectangle that scopes the effect to the feature, so a low corner
elsewhere on the property never turns to mud. A property with no pond passes a
zero extent and the whole term costs one comparison.

**The bank is wide enough to see.** `pond_bank_fraction` and `pond_water_level`
used to put the surface well over a unit below the surrounding ground behind a
narrow, steep rim, so from a mower's seat a pond was a dark depression with a
patch of water at the bottom and the bank - the part worth looking at - hidden
behind its own edge. Both draws are unchanged in position and order; only their
RANGES moved, and every pond field round trips through the save, so a contract
already in progress keeps the pond it was generated with. The current property
generation is **6**; the older version numbers describe historical feature
milestones, not the current pond version.

**It is planted.** Reeds stand at the water's edge and ankle-deep in the
shallows, shrubs are kept SHORT on the bank so they never hide the water or
swallow a player who drives down to it, and stones are half buried and a shade
larger than the ones scattered in a thicket.

**The water is water, not a sheet of sky.** Most of a small pond is seen at a
glancing angle, so the renderer's own sky reflection - `ROUGHNESS` and
`SPECULAR`, nothing the albedo says - washes the whole surface out to a flat pale
blue. Both are pulled well down, the fresnel term with them, and what it reflects
is pulled towards the tone of the trees on the far bank rather than the zenith.
The surface also holds its body across the middle of the pond and gives up its
last centimetres quickly against the bank, instead of thinning evenly towards the
edge and reading as a shallow dish.

There is still no water VOLUME. Nothing floats and nothing gets wet; a machine
that drives in stands on the bed.

## Property archetypes

`aca_property_archetype.gd`

Every generated property used to be the same kind of place. The Job System has
always known what kind of property each contract is - eight `PropertyType`
values, on every job, printed on every card - and `ACAPropertyParams.for_job()`
took the seed and the grid size and threw the rest away.

There are four archetypes, and one generator:

| | |
|---|---|
| `RURAL` | the generator's original character: open country, a real treeline, hills |
| `SUBURBAN` | a garden in a neighbourhood. Graded flat, framed close, houses beyond it |
| `PARK` | a public green. Open, gently rolling, trees in groves, planted beds |
| `LANDSCAPED` | grounds rather than a garden: a building, a car park, clipped edges |

### The mapping

| Property type | Archetype |
|---|---|
| Residential | Suburban |
| Rural | Rural |
| Public | Park |
| Community | Park or Suburban, split on the seed |
| Commercial / Institutional / Industrial | Landscaped |
| Hospitality | Landscaped or Park, split on the seed |

The two split entries are stable for a given contract and varied across a save:
a village hall is as plausible as a green, and a pub garden as plausible as
hotel grounds.

### Reshaping, not redrawing

`apply()` **never draws a random number**. Every value it changes was already
drawn by `for_seed()`, and all it does is move that value from the range it was
drawn in into the range this archetype uses, keeping where in the range the seed
put it. Two consequences, and both are the point:

- the draw ORDER is untouched, so no existing property moves;
- the seed still decides everything WITHIN an archetype, so two Residential
  contracts are two different gardens rather than one garden twice.

`archetype` is saved as an int. A save written before archetypes existed has no
value for it and loads as `RURAL`, which is exactly the property it was played
on - rural was the only kind the generator could make.

The current property generation is **6**. Older generation versions retain
their documented compatibility behavior when loaded.

## Planted beds

`aca_lawn_beds.gd`

The first feature that is not solid. A rock stops the machine; a garden bed does
not - you simply do not drive over it, and nothing in the world prevents you. So
`is_solid()` answers FALSE, the bed owes the deck no clearance band, and its
exclusion is its own outline and nothing more. The mower can put its deck right
up to the mulch, which is what a real operator does.

Rural gets none. Suburban gets one or two small ones against an edge; park gets
three to five large ones out in the open grass, because a park has nothing
beyond its fence to say what it is; landscaped gets three to five smaller,
tidier ones.

There is **no collision body for any of them**, at any size, on any property.

## What stands outside the fence

`aca_property_surrounds.gd`

The house, the neighbours, the street, the driveway and the car park on suburban
and landscaped properties. Everything it builds is on the far side of the
playable boundary, which the machine cannot cross, so:

- **nothing here has a collision body. Not one.**
- nothing here counts towards anything: not the mowing denominator, not the pay,
  not the estimated time.

It is an `ACAPropertyFeature` rather than a plain node, and that is what keeps
the trees out of the houses. The first version was a node that placed some
buildings, and it put a tree through the roof of every one of them, because
`ACAForest` plants the whole band outside the boundary and had no way to know a
house was there. As a feature it answers the interface the forest already asks:

| | |
|---|---|
| `blocks_foliage()` | TRUE - no tree is planted through a wall |
| `blocks_grass()` | TRUE - no lawn tufts under a driveway |
| `blocks_mowing()` | FALSE - and deliberately. A layout bug that put a driveway over the lawn should show up as a driveway drawn on the grass, not as a contract that silently finishes at 94% |
| `is_solid()` | FALSE - no collision, so no clearance owed |

### The runtime asset subset

Eight Quaternius building models, copied out of `asset dump/Models with
Materials/OBJ/` into `res://Assets/Buildings/Low Poly/`. The `_Mat` variants
carry their own colours in an `.mtl` and need no texture, which is what makes
them safe beside a flat-shaded world without importing a palette too.

Their `.mtl` files store **linear** colour, and Godot reads `Kd` straight into
`albedo_color`, which it treats as sRGB - so the first render of a suburban
property was five black houses at the end of a garden. The copied `.mtl` files
were converted once, at import time, rather than corrected at runtime.

Each building is then given a seeded tint, MULTIPLIED over the model's own
per-surface materials rather than replacing them, so a tinted house is still a
house with a darker roof. Batching is by model AND tint, which is six draw calls
for a neighbourhood.

## Boundary treatment by archetype

The playable boundary is the same invisible wall whatever is drawn on it, and
the player should never meet it as a surprise. Each archetype gets the edge its
kind of place would really have:

| | |
|---|---|
| suburban | a real fence, always. A garden has a boundary and the neighbours are right behind it |
| landscaped | posts and one low rail. Managed grounds are edged rather than fenced in, and the building wants to be seen over the top |
| park | marker posts, mostly. A public green is edged with planting, and the shrub belt does the closing |
| rural | whatever the seed says, exactly as before |

## Where the mowing scene meets all this

`Game/M.V.P/Minimum Viable Game.tscn` holds a `Property` node and `MVP.gd`
builds it in `_ready()`. The scene root exposes:

```gdscript
MVP.property() -> ACAProperty
MVP.lawn() -> ACALawn
```

`SaveService`, the trailer director and the validation runners ask for those
rather than reaching for a node by name.

**The property is built at the world ORIGIN.** The old lawn was authored about
five hundred units below it, which is why the weather system had to be told
where the ground was by hand.

RESTART JOB calls `ACALawn.reset()`. The property is not regenerated: the player
asked to start the contract again, not to be sent to a different address.

## How the visual claims were checked

Nothing about the look was decided from code. `Property Probe` renders a
generated property from fixed viewpoints, and every setting below was reached by
rendering, looking at the image, and correcting:

| Judged from | Viewpoints |
|---|---|
| grass scale, density, colour, cut boundary | `close-turf`, `mower-eye` |
| the property as a composition | `overview`, `arrival` |
| forest depth and the treeline | `treeline` |
| distant hills and atmospheric depth | `horizon` |
| the pond and its bank | `pond`, `pond-bank` |
| the treeline's canopy line, tint and understory | `treeline`, `overview` |
| whether the far band sits on the hills | `overview`, `horizon` |
| weather and time of day | the same viewpoints under Clear / Foggy / Rain at four hours, plus `Weather Matrix` in the real scene |

Wind is the one thing a still cannot show, so `--property-wind` compares two
frames about half a second apart from a stationary camera. On a light-forest
property the reading is 2 - 5% of pixels changed with a mean difference of
0.0025 - 0.0056 and localised peaks at blade edges: the grass moves, and it
moves like a breeze rather than a shake.

## Save format

See [Save and Load](save-and-load.md#the-mowing-block). In short: the mowing
block stores the property PARAMETERS and a compressed cut bitset, not geometry
and not a list of blades. A fully mown Large lawn costs under a kilobyte.
