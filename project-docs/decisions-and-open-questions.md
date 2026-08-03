# Architecture Decisions and Open Questions

Status: Confirmed decisions plus review queue  
Decision date recorded: 2026-08-02

## Confirmed decisions

### D-001 — Authoritative runtime

Decision:

`Game/M.V.P/Minimum Viable Game.tscn` is the authoritative current playable architecture.

Consequences:

- Runtime documentation starts from this scene.
- `Main.tscn` is not described as the application root.
- Systems outside the main graph require an explicit partial, tooling, legacy, or deprecated label.

### D-002 — Partially integrated application systems

Decision:

Menus, jobs, saving/loading, economy, upgrades, and the full HUD are existing but partially integrated systems.

Consequences:

- They are not documented as purely hypothetical.
- Their implemented components and missing integration boundaries are both recorded.
- Future work focuses on completion, integration, balancing, polish, and release preparation.

### D-003 — Canonical terrain

Decision:

The custom `Terrain Manager.tscn` and `Terrain Manager.gd` are canonical.

Terrain3D is a deprecated experiment that is no longer planned for the final game.

Consequences:

- New terrain documentation and development use the custom system.
- Terrain3D content is cleanup debt.
- Cleanup must still check footage scenes, resources, exports, and licenses.

### D-004 — Canonical mower architecture

Decision:

The three mower scenes under `Assets/Vehicles and Mowers/Mowers/` are canonical.

The older `Mower_Normal` and `Model.mower_scene_references` approach is legacy.

Consequences:

- Future mower selection, upgrades, and persistence build on the canonical scenes.
- The model should eventually store the selected mower and durable mower data using stable canonical identifiers.

### D-005 — Canonical weather and sky

Decision:

The custom Preset Manager and Rain Handler form the canonical weather direction. Sky3D is the canonical sky system.

GodotWeatherSystem is removed and not expected to return. GodotSky is historical and replaced.

Consequences:

- Old precipitation resources are cleanup debt.
- Current weather should be formalized and refactored without changing its overall direction.
- Stale GodotSky public text should be updated separately.

### D-006 — Obsolete ODT

Decision:

`Documentation.odt` is obsolete Godot 4 migration-era planning material.

Consequences:

- It is not a source for internal documentation.
- Repository code, the MVP graph, confirmed decisions, and these pages are authoritative.
- The ODT may be removed in later cleanup.

### D-007 — Public website boundary

Decision:

`docs/index.html` is a public portfolio/landing page, not the implementation roadmap.

Consequences:

- Its roadmap does not determine architecture or development order.
- It may lag current development.
- It remains manually maintained for public presentation.

## Review flags

These items are documented but still need future technical or design decisions.

### R-001 — Model schema for canonical mowers

Decide:

- Stable mower IDs.
- Selected mower field.
- Owned equipment representation.
- Base data versus upgrades.
- Per-mower fuel/storage state.
- Save compatibility rules.

### R-002 — First authoritative save schema

Decide:

- Profile file format and version.
- Atomic writes/backups.
- Default and optional fields.
- Job/grid serialization scope.
- Migration policy.
- Whether transient job offers persist.

### R-003 — Job acceptance and gameplay bridge

Decide:

- How offer data becomes an accepted Job.
- How a Job configures the custom grid and terrain.
- Where completion state lives.
- How pay is settled.
- Scene transition/overlay ownership.

### R-004 — Economy and upgrades

Decide:

- Player balance ownership.
- Store/equipment data.
- Upgrade definitions and application.
- Relationship between model speed/blade fields and specific mower data.
- Reward/balance rules.

### R-005 — Production HUD composition

Decide which parts of:

- MVP HUD.
- Mowing Information UI.
- Information Bar.
- Job Offer Display.
- Menu prototypes.

become the production interface and which remain development-only.

### R-006 — Terrain generation workflow

The canonical Terrain Manager scene currently contains baked MultiMeshes while its script contains toggled generation tools.

Decide:

- Editor plugin/tool versus runtime generation.
- Deterministic seeds.
- Generated-scene ownership.
- Bake and rebuild procedure.
- Collision requirements for decorative foliage.

### R-007 — Weather formalization

Decide:

- Hard-coded presets versus custom resources.
- Weather/time state ownership.
- Save/load representation.
- Quality levels.
- Snow’s future.
- Audio bus structure.

### R-008 — Physics limit key

Confirm which Jolt maximum-body setting Godot 4.6 uses before removing or reconciling the duplicate key.

### R-009 — Grass artifact review

Review:

- The two similarly named mowed-grass resources.
- The duplicate embedded/external Grass Grid Item scripts.
- Whether either Grass Grid Item representation belongs in the canonical grid.

### R-010 — Rider-parts Timer

Confirm whether the Timer and stale `straighten_wheel` connection can be removed now that steering return occurs continuously in `_update_steering()`.

### R-011 — Snow

The removed addon resources are deprecated, but the local `snow_particles.tscn` remains technically independent. Decide whether snow remains in scope.

### R-012 — Main Area attachment

`Main Area.tscn` does not attach `Main Area.gd`. Decide whether this is intentional scaffolding or an incomplete scene setup when business-area integration begins.

## Documentation update rule

When a review flag is resolved:

1. Record the decision and date here.
2. Update the affected system page.
3. Update scene/script status tables.
4. Do not silently reclassify a second implementation as active.
