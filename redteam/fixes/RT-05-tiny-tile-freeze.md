# RT-05: A room with tiny tiles freezes the window

Severity: Medium
Location: `scripts/scene_view.gd:146-177`; `scripts/scene_pack.gd:198`

## The finding

`_draw_tiled_background` steps by the tile's own drawn size:

```gdscript
var tile: Vector2 = wall.get_size() * tile_scale
...
while x < size.x:
	draw_texture_rect(wall, Rect2(Vector2(x, y), tile), false)
	x += tile.x
```

`tile_scale` is floored at 1 but nothing relates it to how big the tile actually
is. Measured with `redteam/tests/probe_h_tiles.gd`:

```
540x760 window,  32x32 tile at scale 1:     425 draw calls per frame
540x760 window,  4x4 tile at scale 1:    25,785 draw calls per frame
540x760 window,  1x1 tile at scale 1:   410,940 draw calls per frame
2560x1440 window, 1x1 tile at scale 1: 3,688,960 draw calls per frame
```

3.7 million draw calls a frame is a hard freeze, and the owner cannot reach
Settings to pick another room because the window has stopped responding. The
choice is remembered in `settings.json` under `rooms`, so restarting lands
straight back in it.

## What needs to be fixed

A tile has to be big enough that covering the window with it is cheap. There
also needs to be a backstop in the drawing itself, for a tile whose size could
not be read before it was drawn.

## How it should be fixed, and why that way

Two layers, because the information arrives at two different times.

1. **At load, in `ScenePack._read_tiled_background`:** read each tile's real
   pixel size from its PNG header — `ImageLimits.png_size_from_header`, which is
   already used a few lines away for exactly this kind of thing — and raise
   `tile_scale` until the drawn tile is at least `MIN_TILE_PIXELS` on both axes.
   Raising the scale rather than refusing the room keeps a well-meant pack with
   small tiles working, just drawn chunkier; pixel art is scaled by whole
   numbers everywhere in this app, so a larger integer scale is a normal thing
   for it to be.

2. **At draw, in `SceneView._draw_tiled_background`:** a hard ceiling on how
   many tiles either loop will place. This covers the case the first layer
   cannot: an image whose header is not readable (not a PNG), where the size is
   only known once it has been decoded into a texture. Past the ceiling it
   stretches one tile over the whole area instead, which looks wrong but keeps
   the window alive — and `ScenePack` will have logged the problem.

Not done: refusing the room outright. A room that merely draws oddly should
still appear, which is the rule `ScenePack` already follows for a missing prop
or an unreadable background.

Verification plan: re-run `probe_h_tiles.gd` against the fixed loop and confirm
the call count collapses; check the shipped 32×32 rooms are untouched.

---

## What was fixed

`scripts/scene_pack.gd`, `scripts/scene_view.gd`, `tests/test_scenes.gd`.

### Added — `ScenePack.MIN_TILE_PIXELS` and the scale it forces

```gdscript
## How small a drawn tile is allowed to get.
##
## _draw_tiled_background places one tile per step across and down the window,
## so the cost of a room is the window's area divided by the tile's. A 1x1
## pixel tile at scale 1 asks for 3.7 million draw calls a frame on a
## maximised window, which is a frozen app rather than a slow one. tile_scale
## is floored at 1, but 1 is only meaningful next to how big the tile is.
const MIN_TILE_PIXELS := 8
```

`_read_tiled_background` now measures both images and raises the scale:

```gdscript
	# Raise the scale rather than refuse the room: a pack with small tiles is
	# more likely well-meant than hostile, and pixel art is scaled by whole
	# numbers everywhere here anyway.
	var scale: int = maxi(1, int(data.get("tile_scale", 1)))
	scale = _scale_for_tiles(scale, [wall, floor_file])
```

### Added — the drawing backstop

`SceneView` grew `MAX_TILES_PER_AXIS` and a guard that falls back to one
stretched tile when a step would exceed it.

## Test result after the fix

`redteam/tests/probe_h_tiles.gd`, now driving the real `ScenePack` loader and
the real drawing loop:

```
--- what the pack author writes, and what the loader does with it ---
   1x1  tile, tile_scale 1 -> loader uses 8   (raised)
   1x1  tile, tile_scale 4 -> loader uses 8   (raised)
   4x4  tile, tile_scale 1 -> loader uses 2   (raised)
   4x4  tile, tile_scale 4 -> loader uses 4
  32x32 tile, tile_scale 1 -> loader uses 1
  32x32 tile, tile_scale 4 -> loader uses 4

--- draw calls per frame, after the loader has had its say ---
  540x760 window,    1x1 tile:  6,528  (was   410,940)
  540x760 window,   32x32 tile:   425  (unchanged)
  2560x1440 window,  1x1 tile: 14,560  (was 3,688,960)
  2560x1440 window, 32x32 tile: 3,680  (unchanged)

--- and the shipped rooms are untouched ---
  home: tile_scale 4, problems none
  eat:  tile_scale 4, problems none
```

**253× fewer draw calls on a maximised window.** Not down to the 32×32 figure —
an 8-pixel tile is still four times smaller than a 32-pixel one, so it costs
about four times as many — and 14,560 a frame is an ordinary number that
renders without trouble. I had guessed "425" when writing the plan; the probe
says 6,528 and 14,560, and those are the real figures.

Note that a `tile_scale` of 4 on a 1×1 tile is also raised to 8: the check is
on the drawn result, not on what was asked for, so a small tile cannot slip
through by naming a scale that is larger but still not large enough.

The shipped rooms are genuinely untouched — `scenes/home` and `scenes/eat` use
32×32 tiles, come through with `tile_scale` 4 exactly as written, and report no
problems.

`tests/test_scenes.gd` gained 8 checks (88 -> 96). All pass.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`ScenePack._read_tiled_background`** — the load-time fix.
- **`SceneView._draw_tiled_background`** — the draw-time backstop.
- **`ImageLimits.png_size_from_header`** — reused to measure the tiles; its own
  32-bit truncation is RT-10, fixed in the same pass.
- **`ScenePack._read_image_background` / `_read_props`** — a full-window picture
  is drawn once and a prop once each, so neither has this shape of problem.
- **`ScenePainter`** — the drawn backgrounds compute their spacing from the
  view's height, so their layer counts are bounded already. Checked.
