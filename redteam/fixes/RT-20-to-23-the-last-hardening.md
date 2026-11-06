# RT-20 to RT-23 — The last hardening pass

Four small findings, done together because each is a few lines and none of
them is reachable from the wizard as it stands. They are the places where the
engine's public arithmetic answers a bad question badly, and each one is a
trap for the next caller rather than a live fault.

| ID | Severity | What | Where |
|---|---|---|---|
| RT-20 | Low | `of_image` trusts the format; `SheetStages` reads past the buffer | `sheet_scan.gd:51`, `sheet_stages.gd:154` |
| RT-21 | Low | `even_parts` divides by zero; `dips_at_joins` answers a count of 0 | `sheet_grid.gd:185`, `sheet_grid.gd:209` |
| RT-22 | Low | A 20-digit frame number logs an engine error and saturates | `frame_series.gd:92` |
| RT-23 | Info | The frames box shows 64 for a run of 200 files | `import_form.gd:259` |

---

## RT-20 — `SheetScan.of_image` trusts the format

### The finding

`SheetScan.open` converts the picture to RGBA8 before measuring it.
`of_image`, which takes a picture already in hand, converts only its own
downscaled copy — the caller's image is passed through untouched:

```gdscript
var small: Image = image.duplicate()
small.convert(Image.FORMAT_RGBA8)
```

Its doc comment says the wizard uses it ("so does the wizard, which has the
picture open for its preview already"), and `SheetStages._colour_of` reads the
caller's image four bytes to a pixel. An RGB8 image has three:

```
scan of an RGB8 image: coverage 0.0049, problem ''
SCRIPT ERROR: Out of bounds get index '12291' (on base: 'PackedByteArray')
   at: _colour_of (res://scripts/sheet_stages.gd:154)
```

Three errors, then a judgement made from whatever the reads returned. Godot
returns 0 for an out-of-range `PackedByteArray` read rather than falling over,
so it is a wrong answer and a noisy log rather than a crash.

### Reachability

Not reachable, and the doc comment is wrong about why: nothing outside
`tests/test_sheets.gd` calls `of_image`. The wizard reaches the reader through
`SheetPlan.read` → `SheetScan.open`, which converts properly. This is a trap
laid for the next caller, with a comment inviting them in.

### How it was fixed

Both halves, because either alone would leave the other wrong.

`scripts/sheet_scan.gd` converts what it was handed:

```gdscript
	# Converted here as well as in the copy below. SheetStages reads this
	# same image four bytes to a pixel, and an RGB8 one has three - which
	# read off the end of the buffer and judged the sheet on whatever came
	# back. open() already converts; this is the door the tests come in by.
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
```

and `scripts/sheet_stages.gd` checks the buffer is as long as it needs:

```gdscript
	var data: PackedByteArray = image.get_data()
	var width: int = image.get_width()
	# Four bytes a pixel is an assumption, and one that was read off the end
	# of the buffer when it did not hold. Cheaper to ask than to be wrong.
	if data.size() < width * image.get_height() * 4:
		return Vector2.ZERO
```

The comment claiming a caller that does not exist was corrected rather than
left to mislead.

### Test result

```
[6b] SheetScan.of_image handed a non-RGBA8 image
  scan of an RGB8 image: coverage 0.0049, problem ''
  now asking SheetStages about it, which reads 4 bytes a pixel...
  SheetStages survived: is_stages false
```

No errors. The scan's own answer is unchanged, because it always worked off
the converted copy.

---

## RT-21 — `even_parts` divides by zero

### The finding

```gdscript
static func even_parts(rect: Rect2i, count: int) -> Array[Rect2i]:
	var width: int = rect.size.x / count
```

```
SCRIPT ERROR: Division by zero error in operator '/'.
   at: even_parts (res://scripts/sheet_grid.gd:185)
  count 0 -> 0 parts
  count -3 -> 0 parts
```

It recovers — an error in the log and an empty answer — and
`dips_at_joins(tally, 0)` returns `true`, which is a nonsense answer to a
nonsense question. `SheetPlan.recount` indexing an empty `rects` list was the
third of this group and was closed under RT-17, which had to guard the same
list anyway.

### Reachability

None of the three is reachable from the wizard: `split_touching` only ever
passes 2 or more, `recount` guards `frames < 1`, and a piece always carries at
least one rect. Worth closing because these are the engine's public
arithmetic, the suites call them directly, and an engine error in the log is a
thing the owner will one day have to explain.

### How it was fixed

`scripts/sheet_grid.gd`:

```gdscript
static func even_parts(rect: Rect2i, count: int) -> Array[Rect2i]:
	var parts: Array[Rect2i] = []
	# Nothing divides into no parts, and asking cost an engine error in the
	# log before it answered the empty array anyway.
	if count < 1:
		return parts
	var width: int = rect.size.x / count
```

```gdscript
static func dips_at_joins(tally: PackedInt32Array, count: int) -> bool:
	# Fewer than two pieces have no join between them to look at.
	if count < 2 or tally.size() < count * 2:
		return false
```

### Test result

```
[2] SheetGrid.even_parts(rect, 0) and (rect, -3)
  count 0 -> 0 parts
  count -3 -> 0 parts
[2b] SheetGrid.dips_at_joins(tally, 0)
  dips_at_joins(.., 0) -> false
[3b] recount on a piece whose rects list is empty
  survived, frames = 1
```

Same answers for `even_parts`, no engine error, and the two nonsense questions
now get sensible answers.

---

## RT-22 — A 20-digit frame number

### The finding

`split_number` converts whatever digits it found with `int()`, with no limit
on how many there are:

```
ERROR: Cannot represent 99999999999999999999 as a 64-bit signed integer,
       since the value is too large.
   at: _to_int (core/string/ustring.cpp:2281)
  run_99999999999999999999.png -> { "prefix": "run_", "number": 9223372036854775807, ... }
```

An engine error in the log, and the number saturates to `INT64_MAX`. Two such
files both become `INT64_MAX`, so they land in one run in an undefined order,
and `_unbroken`'s `number - previous` overflows, which quietly glues the file
onto whatever run came before.

### How it was fixed

A digit run longer than a counter can sensibly be is not a counter. That is
already the existing answer for a number in brackets — return `{}` and the
file goes in `loose`, where it belongs.

`scripts/frame_series.gd`:

```gdscript
## The most digits a frame counter can have. Past this it is not a counter -
## it is a date, a hash, or a number too big for int() to read without an
## engine error, which then saturates and glues unrelated files into one run.
const MAX_DIGITS := 12
```

```gdscript
	# "sheet (2).png" is Windows saying it already had a sheet.png, not
	# frame two of an animation. A number in brackets is never a counter.
	if first > 0 and base[first - 1] == "(" and base.substr(last + 1).begins_with(")"):
		return {}
	if digits.length() > MAX_DIGITS:
		return {}
```

Twelve digits is a trillion frames, so nothing real is refused.

### Test result

```
run_99999999999999999999.png     -> {  }
run_000000000001.png             -> { "prefix": "run_", "number": 1, "digits": 12, "suffix": "" }
```

No engine error, and the file falls through to `loose` as a single picture.
The 2000-file run still groups in 15 ms as one series.

---

## RT-23 — The frames box shows 64 for a run of 200 files

### The finding

```gdscript
var count: SpinBox = _spin(row, frames, 1, 64, 1)
```

A numbered run of 200 files produces a piece with `frames` 200. The box capped
at 64, so it displayed 64 beside a label reading "200 numbered files, one
animation". The box was correctly read-only for a run and the real count was
what got installed, so nothing downstream was wrong. It just contradicted
itself on screen.

### How it was fixed

RT-17 already replaced the flat 64 with `maxi(frames, SheetPlan.most_frames(piece))`,
and `most_frames` returns the file count for a numbered run, so the box now
shows 200. The remaining change is to stop pretending it is a box at all when
it cannot be edited:

`scripts/import_form.gd`:

```gdscript
		# A run of numbered files has exactly as many frames as it has files,
		# so there is nothing there to correct - and a box that cannot be
		# typed in, showing a number it had to clamp, said 64 beside a label
		# reading "200 numbered files". Shown as words instead.
		var fixed: bool = PackedStringArray(piece["cut"]["paths"]).size() > 1 and frames > 1
		if fixed:
			row.add_child(UiBits.dim("%d frames" % frames, 11, 0.0, false))
		else:
			...the SpinBox, as before...
```

with `_pictures` carrying the count either way, so `_sheets()` reads it the
same.

### Test result

Checked through `ImportForm` in `tests/test_integration.gd`, which drives the
wizard end to end: a 21-frame numbered run shows "21 frames" as text and
installs 21 frames; a single sheet still gets an editable box, now capped at
its own width.

---

## Suites after all four

**1081 checks, 0 failures**, from a baseline of 1053. Every probe that broke
something has been re-run and none of them breaks now.

The regression guards:

- RT-20 — `tests/test_sheets.gd`: a scan of an RGB8 image, asserting the
  coverage is right and that `SheetStages` answers without reading off the
  end.
- RT-21 — `tests/test_sheets.gd`: `even_parts` at 0 and −3, `dips_at_joins` at
  0 and 1.
- RT-22 — `tests/test_sheets.gd`: a 20-digit name is not a counter, a 12-digit
  one is.
- RT-23 — covered by `tests/test_integration.gd`'s existing wizard scenario,
  extended to assert the frame count the form reports for a numbered run.
