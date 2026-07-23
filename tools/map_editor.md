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

Exports are written as timestamped Lua data files to:

```text
assets/maps/saved_maps
```

Exported maps contain stable hex coordinates, palette indices, and an embedded
copy of all ten palette colors. They can be loaded with
`src.sys.map_data.load` and converted for drawing with
`src.sys.map_data.toColorMap`.

## Controls

- Left-click or drag over hexes: paint with the selected color
- Click a palette swatch or press `1`–`0`: select a color
- `[` / `]`: previous / next palette
- `,` / `.`: previous / next WIP map
- `L`: load the selected WIP map
- `E`: export the current map
- `R`: reset all hexes to palette color 1
- `O`: rescan palettes and WIP maps
- `Esc`: quit
