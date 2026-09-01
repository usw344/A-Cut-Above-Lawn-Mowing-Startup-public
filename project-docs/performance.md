# Performance Architecture

Status: **Current** — measured/reconciled 2026-08-30, after the property and
game-feel passes.

## Primary performance characteristic

**Changed 2026-08-20.** The mowable lawn used to exchange node count and physics
body count for collision-based identification of every grass position: one
`StaticBody3D` and one `CollisionShape3D` per blade. It no longer does.

Mowing is now a rectangle test against a byte array. The lawn is one byte per
square world unit; the whole property contributes ONE physics body, the terrain's
height field.

### Before and after, measured

Both headless on the development machine. The old numbers come from
`legacy_lawn_baseline.gd` (now in `Soft Delete/`), the new ones from
`Property Test`'s cost tables and `Property Probe`'s node counts.

| Lawn | | logical cells | build ms | nodes | physics bodies | mowing state |
|---|---|---:|---:|---:|---:|---|
| Small 96 | old | 9,216 | 72 | 19,809 | 9,218 | one body + 2 MultiMesh nodes per 16 blades |
| | **new** | 9,216 | **12** | **1** | **0** | 9,216 bytes |
| Medium 144 | old | 20,736 | 156 | 44,289 | 20,738 | |
| | **new** | 20,736 | **26** | **1** | **0** | 20,736 bytes |
| Large 192 | old | 36,864 | 267 | 78,561 | 36,866 | |
| | **new** | 36,864 | **46** | **1** | **0** | 36,864 bytes |

"nodes" and "physics bodies" above are the LAWN's own. The property as a whole
adds the terrain (2 mesh nodes, 1 static body), the grass tiles and the foliage
batches:

| Property (Medium, wooded, with a pond) | |
|---|---:|
| total scene nodes | ~280 |
| total physics bodies | **1** |
| grass instances | ~52,000 in ~200 MultiMesh nodes |
| foliage instances | ~5,000 trees, ~270 shrubs, ~30 rocks in ~95 nodes |
| terrain triangles | 71k core + 22k distant |
| whole property build | ~750 ms |

The old lawn alone was 44,289 nodes and 20,738 bodies for the same contract.

### What cutting costs now

Nothing is rebuilt. A cut writes bytes into an `Image` and marks it dirty; the
mask texture is uploaded at most ONCE PER FRAME regardless of how much was cut.
No MultiMesh is regenerated, no node is created or freed, and no instance
transform is written. The grass and ground shaders read the mask.

`ACAMowerCutter` runs off the mower's `collided` signal at the physics rate. At
a mower speed of 30 units/s that is about 0.05 units of travel per tick, so one
stamp of a roughly 7 x 5 cell footprint - about 35 cell tests, most of which exit
on the first flag check because the cell is already cut.

## Physics configuration

The project currently uses:

- Jolt Physics.
- Separate-threaded 3D physics.
- 576 physics ticks per second.
- Up to 100 physics steps per frame.
- Four solver iterations.
- Two differently named body-limit settings.

The physics rate is higher than the 240 FPS cap. Mower physics, fuel counters,
collision collection, rain following, and HUD performance updates all run
through physics processing.

## Mower collision workload

Every canonical mower physics frame still calls `move_and_slide()`, collects its
slide collisions and emits `collided`. That is unchanged, and deliberately so:
the signal is what stops the blades when the tank runs dry.

What changed is the LISTENER. The collision array is now ignored; the cutter
reads the machine's transform and asks the lawn to mow the swept deck. There is
nothing for a collider name to be parsed out of, because the grass has no
colliders.

## Property construction and reset

Construction is synchronous from `MVP._ready()`, behind the fullscreen transition
and the Job Intro screen, so the cost is masked rather than removed. Roughly, for
a Medium contract:

| Stage | ms |
|---|---:|
| features | <1 |
| terrain: bake, core mesh, rings, collision | ~150 |
| lawn: cell layout and the mask image | ~26 |
| feature nodes (water) | <1 |
| grass placement | ~420 |
| foliage placement | ~130 |

Grass placement dominates and is the obvious target if the budget tightens; the
MultiMesh buffers are already written whole rather than instance by instance,
which was worth about a factor of three.

**RESTART JOB no longer rebuilds anything.** It calls `ACALawn.reset()`, which
clears the cut bits and re-uploads the mask. The property is not regenerated,
because the player asked to start the contract again, not to be sent to a
different address.

## MultiMesh strengths

The project correctly uses MultiMesh for:

- Mowable grass rendering.
- Mowed grass rendering.
- Decorative terrain grass.
- Trees.
- Shrubs.

This reduces draw-node and draw-call cost relative to one `MeshInstance3D` per
visible plant, and since 2026-08-20 visual batching is the ONLY batching the
lawn needs: there is no physics side to batch.

## Terrain workload

Nothing is serialised. The ground is generated from a seed every time the scene
loads, which costs about 150 ms for a Medium property and saves 91 MB of
imported mesh.

| | Small | Medium | Large |
|---|---:|---:|---:|
| baked height samples | 34,225 | 54,289 | 78,961 |
| core mesh triangles | 39,200 | 70,688 | 111,392 |
| distant ring triangles | 16,940 | 22,372 | 27,140 |
| bake ms | 43 | 71 | 99 |
| total terrain ms | 80 | 131 | 183 |

Two optimisations account for most of that. Mesh normals come from the baked
lattice by central difference rather than from re-evaluating the noise, and the
distant rings halve their tangential resolution as their radial step grows, with
a three-triangle fan bridging the two. Before both, Large took 570 ms and the
rings alone were 87k triangles.

## Weather and Sky3D

Weather cost includes:

- Sky3D atmosphere and cloud shader work.
- Near and far GPU rain particles.
- Per-physics-frame rain-handler repositioning.
- Property tweens during preset transitions.
- Rain and ambient audio.

Rain scenes currently author thousands of particles across the near and far emitters. Performance should be evaluated separately for Clear, Foggy, and Rain.

## UI instrumentation

The legacy development MVP HUD samples:

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
- 240 FPS cap.

The terrain’s decorative grass uses visibility ranges. Tree and shrub density is reduced by generation ring rather than runtime object pooling.

## No object pool

No reusable object-pool system was found.

Current replacement/allocation behaviors include:

- Fresh mower instantiation on selection.
- Full property/lawn initialization on startup; reset clears logical state in place.
- Job Offer objects generated dynamically in the partial job system.
- Runtime Tween creation for weather/time/audio changes.

## Game-feel pass measurements — 2026-08-30

The new handling path adds one per-machine speed approach plus clamps; it does
not add a physics body or a per-frame allocation. Body lean reuses two-element
arrays and only changes presentation transforms. Workmanship performs one
distance/index/contact pass over the mower's fresh-sweep measurements, and
obstacle layouts are generated once per property. `Handling Probe` reports
21/21, including the precision view, and `Workmanship Probe` reports 4/4.

The validation harness now measures movement in elapsed physics seconds at the
576 Hz tick rate rather than a fixed render-frame count. This keeps performance
and gameplay assertions independent of render cadence.

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

## Real contract sizes

**Since 2026-08-19** the grid is sized from the accepted contract, so normal
gameplay is well below the 256 fallback:

| Lawn size | Grid | Instances | Chunks |
|---|---|---:|---:|
| Small | 96 | 9,216 | 576 |
| Medium | 144 | 20,736 | 1,296 |
| Large | 192 | 36,864 | 2,304 |
| *(standalone fallback)* | 256 | 65,536 | 4,096 |

Since 2026-08-20 a cell is a BYTE, not a node. The "Chunks" column no longer
applies; the lawn is one flat array and one small texture.

## Progress accounting is O(1)

Mowing progress is tracked with incremental counters on `ACALawn`, moved only
when a cell really changes state. Nothing walks the lawn per frame. The only
full passes are the initial layout, `reset()`, and a save restore.

`MVP._tick_job_runtime()` pushes progress into `ACAJobManager` at 2 Hz, not per
frame. The town refreshes its clock label at 2 Hz for the same reason.

## Session 8 measurements — the property rewrite

### Frame cost, by property

`Property Probe --property-fps`, ninety frames held per viewpoint after a
warm-up pass that visits every viewpoint once. The warm-up matters: the first
frame from a new angle compiles shader variants, and a measurement taken across
that reports the compiler rather than the scene. `arrival` is the first shot and
still carries some of that.

Development machine, Intel Arc B580, 1920 x 1080, Clear at noon, lawn half mown.

| Property | mower-eye | close-turf | overview | treeline | horizon | pond |
|---|---:|---:|---:|---:|---:|---:|
| Open, 96 | 233 | 148 | 138 | 151 | 184 | — |
| Light forest, 144 | 166 | 171 | 167 | 116 | 152 | — |
| Wooded, 192 | 190 | 121 | 150 | 151 | 140 | — |
| Wooded pond, 192 | 226 | 116 | 150 | 156 | 152 | 154 |

Draw calls stay between 90 and 171. Triangles per frame run 0.6M (Open, 96) to
2.1M (Wooded pond, 192, from the overview).

### Weather and time of day

`Weather Matrix`, twelve time/weather combinations in the real mowing scene on a
generated Medium contract:

| | old environment | new property |
|---|---|---|
| fps range across 12 shots | 114 – 146 | 100 – 172 |

The new scene shows a far larger world — a full landscape out to 3.6 km, a
wooded perimeter, distant hills — and is no slower.

### Two changes that paid for most of that

| Change | Effect |
|---|---|
| The ground mesh stopped CASTING shadows (it still receives them) | about 450k fewer triangles per frame on a Large property; a gentle lawn shadows almost nothing of itself |
| Trees past `TREE_SHADOW_RADIUS` (115 units) stopped casting | draw calls 185 → 133 and triangles 3.4M → 1.9M on the Wooded 192 overview |

Neither is visible in a capture. Both were found by measuring, not by guessing.

### Graphics quality is wired to the grass

`ACALawnGrass.bind_to_settings()` follows `GameSettings.graphics_quality()` and
keeps following it if the player changes it mid-contract. Quality trims the
DISTANCE BANDS rather than the density, because a thinner lawn looks broken
while a shorter draw distance looks like weather.

| Setting | near band | mid band |
|---|---:|---:|
| low | 29 units | 83 |
| medium | 38 | 124 |
| high / ultra | 46 | 165 |

## Large-lawn scalability sweep — 2026-08-23

`Large Lawn Stress Test`, one real property per run, Intel Arc B580, 1920x1080,
Godot 4.6.1, seed 20260823, bare sun (the weather stack is deliberately out of
this measurement). Frame rates are the average and the worst of three held
viewpoints — inside the machine at the lawn edge, mid-lawn looking down the
property, and an overview above the corner — after a warm-up pass over all
three. **This is a laboratory, not a contract.** Real contracts are 96 - 192.

| Lawn | logical cells | grass tufts | MultiMesh nodes | property nodes | physics bodies | build | memory | fps avg | fps worst |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 256 | 65,536 | 166,972 | 450 | 553 | **1** | 2.0 s | 114 MB | 177 | 101 |
| 512 | 262,144 | 593,119 | 1,250 | 1,291 | **1** | 6.0 s | 224 MB | 192 | 110 |
| 1000 | 1,000,000 | 2,134,211 | 4,232 | 4,269 | **1** | 19.7 s | 631 MB | 188 | 164 |
| 1500 | 2,250,000 | 4,704,387 | 8,978 | 9,003 | **1** | 42.2 s | 1.27 GB | 156 | 149 |
| 2000 | 4,000,000 | 8,278,952 | 15,138 | 15,163 | **1** | 74.5 s | 2.19 GB | 118 | 103 |
| 2048 | 4,194,304 | 8,674,670 | 15,842 | 15,867 | **1** | 80.3 s | — | — | — |

Draw calls per frame stayed between 126 and 178 at **every** size, because what
is drawn is bounded by the grass draw distance rather than by the property.

### Where the time goes

Each stage is **linear in area**, and the constants are stable across a
sixty-fold range of cell counts:

| Stage | cost per unit | 256 | 2000 |
|---|---|---:|---:|
| Lawn layout | ~195 ms per million cells | 12.7 ms | 775 ms |
| Terrain bake + mesh + collision | ~2.5 us per height sample | 329 ms | 10.7 s |
| Grass placement | ~7.6 us per tuft | 1.38 s | 62.7 s |
| Foliage | **does not scale** | 295 ms | 308 ms |

**The grass placer is the whole story: 82 - 85% of the build time and 85% of the
memory at every size past 512.** Building 1000 m with `enable_grass` off takes
3.4 s instead of 19.7 and costs 82 MB instead of 631; at 2000 m it is 11.7 s and
333 MB instead of 74.5 s and 2.19 GB.

The foliage row is not a rounding error, it is the design: `ACAForest` plants a
BELT around the property and a scatter on the hills, both sized from fixed
radii. A larger lawn pushes the belt outward, it does not fill the middle. Tree
counts actually FALL slightly with size (4,815 at 256 down to 1,688 at 2000)
because more of the fixed-radius scatter area is now lawn.

### Where it starts to hurt, and what actually hurts

Nothing collapses, and nothing behaves worse than linearly. What degrades is
absolute cost:

- **Up to 512** everything is comfortable: six seconds and a quarter of a
  gigabyte.
- **At 1000** the architecture still runs well — 164 fps at worst, one physics
  body, a megabyte-scale lawn state — but the **build takes twenty seconds**,
  which is a loading screen, not a pause.
- **At 1500 - 2000** the build is 42 - 75 seconds and 1.3 - 2.2 GB. Frame rate
  is still over a hundred; it is the *build* that has become impractical.

Frame rate declining from 188 at 1000 m to 118 at 2000 m is **not** more grass
being drawn — the draw calls and the near-field density are unchanged. It is the
fixed per-frame cost of culling fifteen thousand MultiMesh instances plus one
8.4-million-triangle ground mesh that cannot be culled in pieces because it is a
single `ArrayMesh`.

**No optimisation has been done in response to any of this**, deliberately. The
bottleneck is named and measured; whether it is worth anything is a separate
decision, and the sizes that expose it are sizes the game does not ask for.

### Against the old system, at 256

The pre-redesign lawn ran a 256 property at roughly 140 fps with per-instance
physics. The comparison worth making is not the frame rate:

| At 256 x 256 | old | new |
|---|---:|---:|
| logical cells | 65,536 | 65,536 |
| lawn nodes | ~78,000+ | **1** |
| physics bodies | ~65,000 | **1** |
| mowing state | one body + shape per blade | 65,536 bytes + a 256x256 texture |
| frame rate | ~140 | **177 avg, 101 worst** |
| largest lawn that works at all | 256 was the ceiling | **2048**, 64x the cells |

The old architecture could not have been asked this question. Sixty-five
thousand bodies at 256 would have been four million at 2000, which is past the
configured Jolt body limit and far past anything the physics step could carry.

### Mowing still works at every size

`--stress-drive` holds the real `move_forward` action down through the real
controller for five seconds and reports what happened. At 1000 m: the machine
travelled 51.1 units, stayed within **0.12 units** of the terrain surface, cut
**276 cells** (51.1 x 5.6 deck = 286 expected), and the lawn emitted 23 real
progress changes. Whole-scene physics bodies: **2** — the ground and the
machine.

## Session 7 measurements — the environment rewrite

Measured with `Weather Matrix` in the real mowing scene, twelve combinations per
run, on the development machine. `--matrix-quality=` forces a level.

| | fps range across 12 shots | mean |
|---|---|---|
| Baseline (before session 7) | 86 – 121 | ~101 |
| **High** (volumetric + aerial + 3 rain layers) | 84 – 115 | ~97 |
| **Medium** (no volumetric, 2 rain layers) | 78 – 108 | ~95 |
| **Low** (no volumetric, no aerial quad, 1 rain layer) | 77 – 113 | ~92 |

### The honest reading of that table

The environment rewrite costs roughly **4–6% of mean frame rate at High**, which
is comfortably inside the "no unexplained >20% loss" budget, and there is no
weather-specific collapse: the worst single combination is 77 fps and the best
is 115.

**The three quality levels do not separate in this scene, and the table should
not be read as though they do.** Run-to-run variance on these short samples is
larger than the difference between levels — Foggy Day measured 96.7 at High and
78.0 at Medium on consecutive runs, which is obviously not a real ordering.

The reason is that the mowing scene is dominated by the **grass MultiMesh**, not
by the sky. Turning off a froxel volume and a screen-space quad removes real GPU
work, but not work that was the bottleneck here.

So the quality levels are verified **structurally** rather than by frame rate:
`Environment Test` asserts that each level switches different mechanisms off and
that they are ordered by cost. That is a claim about what the code does, which
is checkable; "Low is faster" is a claim about a particular machine and a
particular scene, and in this scene it is not currently true.

They will matter on hardware where the sky IS the bottleneck, and they cost
nothing to keep.

### What the rewrite added, and what it removed

| Added | Removed |
|---|---|
| Godot Environment depth + height fog (all levels) | 6,700 authored rain particles across two emitters |
| Volumetric fog (High only) | the 24x-scaled far-rain emitter |
| Three code-built rain layers (~2,160 particles at High) | — |
| A grade pass (saturation/contrast) when a weather asks for one | — |

The old rain was **more** particles than the new rain, and each one was a
`RibbonTrailMesh` with trails enabled.

### Things deliberately kept off the per-frame path

- `Economy` has no `_process` at all. The market moves on
  `WorldClock.day_changed`.
- The environment recomposes at 10–20 Hz depending on quality, not per frame.
- Sky3D's tween-spawning setters (`ambient_energy`, `sky_contribution`,
  `night_ambient_min`) are written only when the value has really moved past a
  deadband — driving them per tick would spawn tweens per tick.
- The Town sun's basis is written only when the yaw has moved a quarter of a
  degree. See [decisions](decisions-and-open-questions.md), R-022.

---

# Profiler 2.0 and the presentation pass (2026-08-24)

## The instrument

`Dev tools/Validation/Large Lawn Stress Test.tscn` was extended rather than
replaced, so every measurement in this document taken before this date is still
directly comparable with every measurement taken after it. The original CSV
(`user://large_lawn_stress_results.csv`) is still written in its original schema;
a second, wider one (`user://profiler2_results.csv`) carries everything below.

### Three environment profiles, and they are not interchangeable

| Profile | What it measures |
|---|---|
| `SYSTEM_BASELINE` | a bare sun and a procedural sky. The property architecture on its own: terrain, lawn, grass, foliage, with none of the production presentation on top. **Every historical number in this document was taken with this.** |
| `PRODUCTION_CLEAR` | the REAL `Weather/Preset Manager` scene — the project's own Sky3D integration, its lighting, its atmosphere — held at a clear day. What a player sees on a fine morning. |
| `PRODUCTION_HEAVY` | the same production stack under rain: its precipitation rig, its heavier atmosphere, its darker sky. A condition the game ships and a player meets on an ordinary contract, NOT an everything-maximised torture test. |

The production profiles instantiate the real preset manager rather than
approximating it, with `follow_world_clock` off and the state applied
immediately, so two runs of one profile light the property identically.

### Three benchmark modes

`STATIC` (parked machine, fixed camera), `CAMERA` (a repeatable path through the
same viewpoints), `DRIVE` (the real mower on the real controller, throttle held,
cutting real grass — the only mode whose frames include the cost of cutting).

### Methodology

```
warm-up (every viewpoint, nothing recorded)  ->  settle  ->  fixed window  ->  summary
```

Two things about this are load-bearing:

- **The window is a DURATION, not a frame count**, so a heavy configuration and
  a light one are given the same wall clock and their percentiles mean the same
  thing.
- **Frame times are measured as wall time between frames, and the frame cap is
  lifted for the window.** `Performance.TIME_FPS` is a smoothed value the engine
  refreshes about once a second, so every sample inside a window comes back
  identical — which is exactly the measurement a percentile exists to avoid. And
  the project ships `max_fps = 240`, which is sensible for a game and useless
  for a benchmark: every frame cheaper than 4.17 ms comes back as 4.17 ms.

Recorded per run: average fps, worst fps, median / p95 / p99 frame time, draw
calls, primitives, static memory, video memory, every build stage's cost, tuft
and instance counts, node and body counts, plus the things that decide whether
two rows may be compared at all — seed, size, profile, mode, weather, hour,
resolution, graphics level and window length.

## Before and after the presentation pass

Same machine, same seed (20260824), same viewpoints, four-second windows.
"Before" is backup 24, "after" is the finished pass.

### The production Large contract, 192 x 192

| Profile | Mode | before | after | change |
|---|---|---:|---:|---:|
| SYSTEM_BASELINE | STATIC | 447.8 | 431.8 | -3.6% |
| SYSTEM_BASELINE | CAMERA | 435.2 | 418.2 | -3.9% |
| SYSTEM_BASELINE | DRIVE | 393.6 | 347.2 | **-11.8%** |
| PRODUCTION_CLEAR | STATIC | 291.8 | 281.5 | -3.5% |
| PRODUCTION_CLEAR | CAMERA | 286.0 | 275.3 | -3.7% |
| PRODUCTION_CLEAR | DRIVE | 270.1 | 240.2 | **-11.1%** |
| PRODUCTION_HEAVY | STATIC | 219.1 | 214.3 | -2.2% |
| PRODUCTION_HEAVY | CAMERA | 219.1 | 211.5 | -3.5% |
| PRODUCTION_HEAVY | DRIVE | 202.5 | 181.8 | **-10.2%** |

### The stress sizes, STATIC

| Size | Profile | before | after | change |
|---|---|---:|---:|---:|
| 256 | SYSTEM_BASELINE | 522.7 | 474.7 | -9.2% |
| 256 | PRODUCTION_CLEAR | 322.5 | 299.0 | -7.3% |
| 256 | PRODUCTION_HEAVY | 251.8 | 229.7 | -8.8% |
| 512 | SYSTEM_BASELINE | 550.1 | 448.3 | **-18.5%** |
| 512 | PRODUCTION_CLEAR | 328.4 | 282.4 | -14.0% |
| 512 | PRODUCTION_HEAVY | 277.8 | 238.3 | -14.2% |
| 1000 | SYSTEM_BASELINE | 447.8 | 379.9 | **-15.2%** |
| 1000 | PRODUCTION_CLEAR | 286.9 | 252.1 | -12.1% |

## What the regression is, measured rather than guessed

The DRIVE regression crossed the 15% threshold in the first measurement, so it
was isolated rather than accepted. Current build, 192, `SYSTEM_BASELINE`:

| | grass on | grass off |
|---|---:|---:|
| STATIC | 415.4 | 659.3 |
| DRIVE | 329.9 | 631.8 |

**With the grass off, DRIVE and STATIC are within 4% of each other.** The
boundary's collision, the pond's shoreline ring and the obstacle bodies — the
three physics bodies this pass added — cost about 0.06 ms between them at
576 Hz. The whole regression is the taller lawn being rendered, and it is
concentrated in DRIVE because that mode looks along the ground from the seat,
where a lawn that is now most of twice as tall fills far more of the frame.

A second A/B checked whether the extra blade segment was worth its cost:

| Near tuft | 192 DRIVE, SYSTEM_BASELINE |
|---|---:|
| 2 segments | 352.4 fps |
| 3 segments | 343.7 fps |

2.5%, for an arc rather than a hinge on a blade that is now much longer. Kept.
The MID tuft's second segment was reverted in the same experiment — a hinge
forty-six units away is smaller than a pixel — and that recovered about 4%.

**Nothing was reverted for the rest.** The taller lawn is the point of the pass:
it is what makes the before-and-after of mowing worth doing. It is understood,
attributed, measured, and it leaves the heaviest player-facing configuration
(`PRODUCTION_HEAVY` / `DRIVE` on a Large contract) at **182 fps average and a
p99 of 8.3 ms**.

## The collision model after the pass

| | before | after |
|---|---:|---:|
| physics bodies on a generated property | 1 | **4** |
| ...the ground heightmap | 1 | 1 |
| ...the playable boundary | – | 1 |
| ...the pond's shoreline ring | – | 1 |
| ...the lawn obstacles | – | 1 |
| physics bodies on the wood | 0 | **0** |

The boundary and the obstacles are ONE body each carrying many shapes, not a
body each. A Large property's boundary is about 180 box shapes on a single
static body; the pond ring is 48; the obstacles are eight to twelve spheres.

Scene nodes grew with them — 430 to 553 on a Large — almost entirely
`CollisionShape3D` children of those two bodies. The wall is segmented every five
world units so it follows the ground, so that count is linear in the property's
perimeter: about 180 shapes at 192, and about 840 at the 512 stress size. At the
sizes the game actually asks for it is not a cost worth optimising; at stress
sizes it is worth knowing about.

Memory moved by under 1% at every size.

## The three profiles as a picture of where the frame goes

At 192, STATIC, on this machine:

| | ms/frame | attributable to |
|---|---:|---|
| `SYSTEM_BASELINE` | 2.30 | terrain, lawn, grass, foliage |
| `PRODUCTION_CLEAR` | 3.25 | + Sky3D, production lighting and atmosphere (+0.95) |
| `PRODUCTION_HEAVY` | 4.56 | + rain and its heavier sky (+1.31) |

The production presentation costs about as much as the whole property does. That
is the single most useful thing Profiler 2.0 reports, and it was invisible before
it existed, because every previous measurement was taken under a bare sun.
