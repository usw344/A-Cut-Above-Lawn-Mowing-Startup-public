# Shared Theme

## Purpose
The one place the colours, corner radii, type scale and animation timings of
the UI are defined. Every component in `res://UI/` reads from here.

## Files
| File | What it is |
|---|---|
| `ui_theme.gd` | Palette constants + static helpers (`class_name UITheme`) |
| `Game UI.theme.tres` | Generated Godot `Theme`, assigned to every component root |

## Public API
Constants: `INK`, `INK_DIM`, `INK_FAINT`, `INK_ON_ACCENT`, `ACCENT`,
`ACCENT_BRIGHT`, `WARN`, `URGENT`, `MONEY`, `PANEL_BG`, `PANEL_BG2`,
`PANEL_SOLID`, `PANEL_SOLID2`, `CARD_BG`, `CHIP_BG`, `BUTTON_BG`, `TRACK_BG`,
`HAIRLINE`, `SCRIM_LIGHT`, `SCRIM_HEAVY`, `RADIUS_*`, `FONT_*`, `FADE*`,
`SLIDE`.

Helpers:
```gdscript
UITheme.stylebox(bg, radius, border, border_colour, margin_h, margin_v)
UITheme.label(parent, name, text, size, colour, wrap)
UITheme.style_button(button, primary, height, font_size)
UITheme.style_danger_button(button, height, font_size)
UITheme.style_progress(bar, fill_colour)
UITheme.format_money(1234)     # "$1,234"
UITheme.format_clock(522.0)    # "08:42"
UITheme.percent_text(0.723)    # "72%"
```

## Where the palette came from
Matched by eye to the existing screens in this project so the new UI belongs
to the same game:
- `res://ACA_JobSystem/job_system/ui/job_ui_style.gd` (Job Board)
- `res://ACA_BusinessTown/UI/` (Town HUD)

The colour values are intentionally identical to that file.

## Translucent vs opaque surfaces
`PANEL_BG` / `PANEL_BG2` are slightly translucent and are used by panels that
sit over live gameplay (the HUD). `PANEL_SOLID` / `PANEL_SOLID2` are opaque
and are used by menus that can stack on each other - pause under settings
under controls - so the screen below never ghosts through.

## Restyling
Change the constants in `ui_theme.gd`, then re-run
`res://UI/_tools/Build UI.tscn`. That regenerates `Game UI.theme.tres` and
every component scene.

No fonts are imported; everything uses the Godot default font at the sizes
above. To swap in a real font, set `default_font` on `Game UI.theme.tres`.

## Known Limitations
- `HSlider` grabbers and `CheckButton` pills use the engine default textures,
  which keeps the theme asset-free but means those two controls are not fully
  restyled.
- The theme is a hard dependency of every component scene (one `ext_resource`
  per `.tscn`). Copy this folder first. Without it components still lay out
  correctly, they just look generic.
