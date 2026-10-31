# RT-10: PNG size guard truncated to 32 bits, so it skips the worst files

Severity: Low
Location: `scripts/image_limits.gd:50-63`, `:37-40`; duplicate in
`scripts/pet_pack.gd:289-298`

## The finding

`png_size_from_header` reads the two big-endian 32-bit header fields correctly
as 64-bit GDScript integers, then packs them into a `Vector2i` — whose
components are **32-bit**. A declared width of `4294967295` becomes `-1`.
`is_too_large` then takes `size.x <= 0` to mean "not known", which it documents
as never too large, and the file goes to the decoder — the exact outcome the
guard exists to prevent.

```
4294967295 x 4294967295 product = 1
is_too_large says: false
```

In practice Godot's PNG decoder refuses such dimensions, so the file fails to
load and the app carries on — which is why this is Low. But the cheap
pre-decode guard is silently inoperative for the extreme case, leaving only the
post-decode check, which has already paid the allocation.

`PetPack._png_size` is a second, worse copy of the same reader: same truncation,
and it checks neither the PNG signature nor `ImageLimits`.

## What needs to be fixed

A declared size that cannot be represented must be refused rather than
mistaken for "unknown", and there should be one header reader, not two.

## How it should be fixed, and why that way

`is_too_large` has to distinguish three things, where it currently has two:

- a size it knows and accepts,
- a size it knows and refuses,
- a size it could not read — which must stay "not refused", because refusing
  every format whose header this does not parse would refuse every non-PNG.

The neat way to keep all of that inside a `Vector2i` is to **saturate instead
of truncate**: when a declared side does not fit, report `MAX_SIDE`
(`0x7FFFFFFF`) rather than letting it wrap negative. That is honest — the file
really is at least that big — it stays positive, so it reads as "known", and
`is_too_large` refuses it on the spot. `Vector2i.ZERO` keeps its existing
meaning of "unknown", and the existing test that a negative size is "nonsense
and never too large" keeps working unchanged.

Then delete `PetPack._png_size` and have `_read_one_sprite_animation` call
`ImageLimits.png_size_from_header`, so there is one reader with one set of
checks.

**One behaviour change worth flagging:** the shared reader verifies the PNG
signature, which `PetPack._png_size` did not. A sprite sheet that is not
actually a PNG — a WebP or JPEG named `.png` — will now be refused with "could
not read the size of X" instead of getting garbage dimensions from whatever
bytes sat at offset 16. `CLAUDE.md` §5.1 specifies PNG strips, and such a pack
was already broken in practice (its garbage width would almost never divide by
its frame count), so this turns a confusing failure into a clear one rather than
taking away something that worked.

Verification plan: re-run `probe_c_numbers.gd`'s overflow section; confirm the
real `pug_pixel` sheets still measure correctly through the shared reader.

---

## What was fixed

`scripts/image_limits.gd`, `scripts/pet_pack.gd`, `tests/test_pets.gd`.

### Added — `MAX_SIDE`, and saturation instead of truncation

```gdscript
## The largest side this can report. Vector2i holds 32-bit components, so a
## PNG declaring 4294967295 wide used to wrap round to -1 and be mistaken for
## "size unknown", which is_too_large treats as never too large - so the one
## file the guard existed to refuse went straight to the decoder.
##
## Saturating is honest rather than clever: the file really is at least this
## big, the figure stays positive so it still reads as known, and is_too_large
## refuses it immediately.
const MAX_SIDE := 0x7FFFFFFF

static func png_size_from_header(path: String) -> Vector2i:
	...
	return Vector2i(
		mini(_big_endian_u32(header, 16), MAX_SIDE),
		mini(_big_endian_u32(header, 20), MAX_SIDE)
	)
```

### Removed — `PetPack._png_size`

`_read_one_sprite_animation` now calls `ImageLimits.png_size_from_header`, and
refuses a sheet that is too large as well as one it cannot measure — which the
duplicate never did, so an enormous sprite sheet used to be caught only later,
by `PetLoader.load_texture`, after the pack had already been listed as usable.

## Test result after the fix

```
4294967295 x 4294967295 -> reported as 2147483647 x 2147483647
is_too_large says: true          (was false)
a real sprite sheet still measures right: true
a file that is not a PNG still reads as unknown: true
an unknown size is still never too large: true
```

`tests/test_pets.gd` gained 6 checks (105 -> 111), including a crafted header
declaring `0xFFFFFFFF` on both axes. The existing image-limit checks — the real PNG, the
`.glb`, the missing file, the 8192×4096 boundary, the 20000×20000 fixture, and
the two negative/zero cases — all still pass unchanged, which is what says the
three-way distinction survived.

The real `pug_pixel` pack still loads: its `idle.png` measures 45×43 and
`walk.png` 172×32 through the shared reader, and `test_pets` and
`test_integration` both still pass.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`ImageLimits.png_size_from_header` / `is_too_large`** — the fixed code.
- **`PetPack._read_one_sprite_animation`** — now uses the shared reader, and
  gained the size refusal it never had.
- **`PetLoader.load_texture`** — the post-decode check behind it. Unchanged, and
  now less often the only line of defence.
- **`SceneView._load`** — loads room pictures through `PetLoader.load_texture`,
  so it benefits from the same guard.
- **`ScenePack._read_tiled_background`** — RT-05 added a *minimum* tile size
  using this same reader, so the two findings meet here.
- **`PetPack.tallest_frame_height` / `integer_scale`** — read the measured
  figures; unchanged.
