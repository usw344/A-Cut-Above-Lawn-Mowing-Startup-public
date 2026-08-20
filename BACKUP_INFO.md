# Backup 13 — Trailer Mowing Shots

Taken: 2026-08-19 (America/Regina)
Source: `Working Repository/`
Files: 887 (`.godot/` omitted — regenerable import cache)

## State at this point

Everything in Backup 12, plus Milestone 13 — the trailer's **mowing section**
reworked, and nothing else touched.

The brief was narrow and was kept to. The review said the trailer was close, the
intro and main menu were good and the town pan was good; the mower **bounced,
flew above the grass and looked comical**, and the mowing shots were not
attractive enough to put on YouTube.

`diff -rq` against Backup 12 lists **exactly three changed files**:
`trailer_director.gd`, `trailer_mower_adapter.gd`, `trailer_test.gd` (plus two
markdown docs). The main menu beat, the town dolly, the Job Board and the accept
beat are unchanged to the line, and the town review frame is pixel-identical.

### The mower was never on the ground

V3 planted it at the height its own physics settled at. That is wrong twice
over, and the V3 review frames show it as a band of daylight under every wheel:

1. **Every blade of grass is a real `StaticBody3D` about three units tall**
   (`MultiMesh Chunk.gd` scales each collider by 3). A mower dropped on an uncut
   lawn lands on the GRASS.
2. **The ground you can see is not the ground physics uses.** `Mowing Area` is a
   `PlaneMesh` at its StaticBody's origin inside a 50 x 1 x 50 `BoxShape3D`
   centred on the same origin, so the collision surface stands **half a unit
   proud of the visible dirt** — everywhere, cut or not.

A downward raycast answers neither: grass and ground are both on layer 1.

`_measure_ground_y()` measures both parts instead — the visible plane from the
grid's own node, plus the new `ACATrailerMowerAdapter.visual_lift()`, which
walks the mower's `MeshInstance3D` children for how far its origin sits above
its lowest visible point:

```
[TRAILER]   ground: plane -508.58 + mower lift 0.02 = -508.56  (settled -508.15, -0.41)
```

0.41 units, on a machine three units tall, filmed from five metres: the whole
difference between a lawn tractor and a hovercraft.

### The speed was forcing the distance

V3 ran the mowing beats at 38-55 u/s — faster than gameplay's 30 — so that a
distant camera would have something crossing its frame. That is circular. The
speed is what made a close lens impossible and the distance is what made the
mower a speck. The shots now run **13-24 u/s** and every lens is close.
`Trailer Test` asserts the ceiling so it cannot drift back.

### Five mower angles became three shots

| | |
|---|---|
| **`mower over the top`** (0:14, 5.0s) | the hero. The lens in the DRIVING SEAT, steering wheel in frame, looking forward over the bonnet. Nearly rigid, so it reads as MOUNTED rather than as a chase |
| **`mower low pass`** (0:19, 4.0s) | low on the finished lawn, ahead and to the cut side, the machine coming on towards the lens |
| **`mower close`** (0:23, 3.6s) | the composition V3 got right, at half the speed and finally on the ground |

All three frame **the boundary between cut and uncut lawn**, which is the rule
V3 was missing: a mower in the middle of an untouched field is a mower standing
in a field, whatever the lens is doing. The staged lanes are laid immediately
beside the mower's own and on the side the lens is on — `MOWING_YAW` and
`CUT_SIDE` name the sign once — and they overlap, because uncut ridges between
lanes put a line of grass across the mower's wheels from a low camera.

### Also in this milestone

- `ACATrailerMowerAdapter.set_suspension()`, and gentler defaults
  (`BOB_HEIGHT` 0.09 → 0.045, `MAX_ROLL` 0.10 → 0.05). A lens bolted to the
  machine turns every millimetre of bob into camera shake; the over-the-mower
  shot damps it to almost nothing.
- Storyboard 43.8s → 41.8s, twelve beats.
- The storm's teardown moved into the gameplay-proof beat, which is the beat
  that now follows it.

## Validation at this point

| Suite | Result |
|---|---|
| `validate_all` | 114 scripts ok / 0 fail, 84 of 85 scenes ok |
| **Trailer Test** | **101 / 101** (was 98) |
| Flow Test | 54 / 54 |
| UI Smoke Test | 60 / 60 |
| Save Test | 59 / 59 |
| Pause Test | 49 / 49 headless |
| Credits Test | 40 / 40 |
| Weather Test | 56 / 56 |
| Fuel Test | 56 / 56 |
| Trailer graphical run | ~42 s, 12 beats, 37 review frames, reviewed |
| Sky3D addon files changed | **0** (`diff -rq` against Backup 04 is silent) |

The single scene failure is the pre-existing third-party
`addons/sky_3d/assets/resources/MoonRender.tscn`. Nothing loads it.

## Do not modify

This is an immutable recovery point.
