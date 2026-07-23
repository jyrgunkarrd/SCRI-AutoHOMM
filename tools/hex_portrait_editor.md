# Hex Portrait Editor

The lower-left preview uses the game's 42-pixel hex radius and map color.

Run from the project root:

```bash
love . --portrait-tool
```

Input images go in:

```text
assets/images/process_queue
```

Exports are written to:

```text
assets/images/processed
```

Controls:

- Drag with left mouse: pan image
- Mouse wheel: zoom image
- `E` or `Enter`: export current crop
- `Left` / `Right`: previous / next source image
- `P` / `N`: previous / next source image
- `R`: reset framing and zoom
- `0`: center image without changing zoom
- `O`: rescan the input folder
- `Esc`: quit
