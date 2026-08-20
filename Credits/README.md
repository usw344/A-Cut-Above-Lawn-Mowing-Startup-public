# Credits folder

**This folder IS the Credits screen.** Drop a text file in, and it appears in
the game. There is no list in code to update.

## Adding a credit

1. Copy the licence / credit text into a new file here.
2. Name it `<Name_Of_Thing>_licence.txt`.

```
Sky3D_licence.txt            ->  shown as "Sky3D"
Kenney_Assets_licence.txt    ->  shown as "Kenney Assets"
```

Underscores become spaces; the recognised ending is stripped. `_license`,
`_credit` and `_credits` are also accepted, but **`_licence` is the project
convention**. `.txt` and `.md` are read; anything else here (this README
included) is ignored.

## Rules

- **Copy the licence text VERBATIM.** Do not summarise it, reword it, fix its
  wording, or drop the copyright lines. The file body is displayed exactly as
  written.
- One file per credited thing. If a package ships several licences (Sky3D ships
  four), give each its own file so each is readable on its own.
- The original licence files stay where they are — under `addons/` or beside the
  assets they cover. These are player-facing copies, not replacements.

## Who reads this

`res://UI/Credits/credits_loader.gd` (`ACACreditsLoader`) scans this folder; the
path is the single constant `CREDITS_DIRECTORY` at the top of that file.
`res://UI/Credits/credits.gd` (`CreditsScreen`) displays the result, reached from
the Main Menu's CREDITS option.

## Export

`.txt` is not a Godot resource, so `export_presets.cfg` carries
`include_filter="Credits/*.txt"` on the release preset. **A new credit file must
match that filter or it will not ship.**

## Known gap

`Assets/Sounds/rain-sound-188158.wav` has no attribution anywhere in the
repository and its source could not be established from the file alone. It is
deliberately NOT credited here rather than credited to a guessed author. Add a
`_licence.txt` for it once the source is confirmed.
