# Public Portfolio Refresh — Incremental Change Packet

Date: 2026-08-30  
Scope: GitHub README, GitHub Pages source, and public screenshots only

## Baseline

- The published site looked polished and active, but its first minute was consumer-focused: Steam led the header, the hero sold the game, and the engineering story appeared after the trailer, gameplay loop, and feature grid.
- The project's ownership and the repository's strongest current work—Lawn 2.0, seeded property composition, MultiMesh rendering, persistence boundaries, weather adapters, and validation tooling—were not obvious above the fold.
- Prominent screenshots predated the current UI/property work and the README/site did not fully reflect the 2026-08-30 repository state.

## Files changed

- `README.md`
- `docs/index.html`
- `docs/assets/site.css`
- `docs/assets/site.js`
- `docs/assets/screenshots/business-town.webp`
- `docs/assets/screenshots/job-board.webp`
- `docs/assets/screenshots/job-complete.webp`
- `docs/assets/screenshots/mower-workshop.webp`
- `docs/assets/screenshots/procedural-property.webp`
- `docs/assets/screenshots/mowing-state.webp`
- `docs/assets/screenshots/pond-feature.webp`
- `docs/assets/screenshots/riding-mower.webp`

## Captures

- Normal application Screenshot Tour: 22 PNGs covering menu, town, services, job board, mowing UI, pause/settings/help, notifications, completion, and job history.
- Property Probe: 8 PNGs covering arrival, mower-eye, turf, overview, treeline, horizon, pond, and pond bank.
- Trailer capture: menu/town/job-board candidates were usable; the mowing phase hit existing capture-script errors and was excluded.
- Site Probe: 5 PNGs reviewed; useful for validation, not selected for the public gallery because composition was weaker.

Selected public images:

- `procedural-property.webp` — strongest combined view of scale, generation, pond, obstacles, foliage, and cut state; used as hero.
- `mowing-state.webp` — clear cut/uncut boundary supporting the Lawn 2.0 story.
- `pond-feature.webp` — connects generation, exclusions, terrain, grass, and foliage.
- `riding-mower.webp` — fresh crop from the live production menu background.
- `business-town.webp` — current street-level town capture.
- `job-board.webp`, `mower-workshop.webp`, `job-complete.webp` — current application/business loop and polished UI.

## Copy and claims

- Reframed the page for hiring managers and engineering leads.
- Made the project status clear while keeping personal attribution off this public-facing surface; credited third-party components remain separated.
- Emphasized generated properties, compact byte-array lawn state, deck-geometry mowing, tiled MultiMesh grass, cut-mask rendering, focused application systems, WorldClock/Sky3D adapter boundaries, additive persistence, and automated/visual validation.
- Follow-up copy pass on 2026-08-31: removed personal-name references and rewrote the public README/site copy in a more direct, less promotional voice. The visual design and media selection were unchanged.
- Removed the stale current-trailer implication; the linked video is identified as the existing v0.3 gameplay showcase.
- No superseded per-grass collision-grid architecture is described as current.

## Links

- Repository, YouTube showcase, itch.io, and Steam links retained and browser-verified.
- Repository is now the primary header and hero action; consumer links remain secondary.

## Browser checks

- Live published baseline reviewed at 1440 × 900.
- Local refreshed site reviewed at 1440 × 900, 900 × 800, and 390 × 844.
- Verified responsive navigation, hero text/buttons, section stacking, gallery cards, image loading, anchor targets, absence of horizontal overflow, and browser console errors/warnings.
- All referenced README and site images exist and load.

## Known remaining presentation weakness

- The available video is still the v0.3 showcase. A current short technical walkthrough would be the highest-value future portfolio addition.

## Safety

- No gameplay code, scenes, resources, project settings, or existing internal documentation page was modified by this portfolio refresh; this packet is the only documentation addition.
- Fresh source captures remain in ignored local capture storage; only optimized WebP selections were added to the public site.
