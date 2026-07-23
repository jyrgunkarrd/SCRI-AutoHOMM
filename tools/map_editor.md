# Map Editor

Run from the project root:

```bash
love . --map-editor
```

## Palettes

Place palette images in:

```text
assets/images/map_palettes
```

Each image must contain ten horizontal or vertical color swatches. The editor
samples ten evenly spaced pixels through the center of the image. PNG, JPEG,
BMP, TGA, and WebP files are supported.

If the folder contains no valid palette images, the editor supplies a built-in
ten-color palette.

## Maps

WIP maps are loaded from:

```text
assets/maps/wip_maps
```

Exports are written as named Lua data files to:

```text
assets/maps/saved_maps
```

Press `M` in the editor to name or rename the current map. That name is stored
inside the map and used for its exported filename. Spaces and filesystem-unsafe
characters are converted to underscores in the filename.

Exported maps contain their display name, stable hex coordinates, palette
indices, spawner target strings, and an embedded copy of all ten palette colors.
They can be loaded with
`src.sys.map_data.load` and converted for drawing with
`src.sys.map_data.toColorMap`.

Spawner targets are available to game logic through the exported map's
`spawners` table or `src.sys.map_data.getSpawnerTarget`.

## Controls

- Left-click or drag over hexes: paint with the selected color
- Click a palette swatch or press `1`–`0`: select a color
- `M`: name or rename the current map
- Hover a hex and press `S`: add a spawner or edit its target string
- While editing a target: type text, press `Enter` to save, or `Esc` to cancel
- Hover a spawner and press `Delete`: remove it
- `[` / `]`: previous / next palette
- `,` / `.`: previous / next WIP map
- `L`: load the selected WIP map
- `E`: export the current map
- `R`: reset all hexes to palette color 1
- `O`: rescan palettes and WIP maps
- `Esc`: quit
