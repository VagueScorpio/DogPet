# RT-15 — The wizard freezes for 13 seconds on 400 pictures, then offers 24 of them

Severity: **High**
Location: `scripts/import_form.gd:227`, `scripts/sheet_plan.gd:36-71`
Probe: `redteam/tests/probe_p6_freeze.gd`

## The finding

`ImportForm._build_sprite_questions` reads every chosen picture inline, on the
UI thread, while the wizard window is up:

```gdscript
var found: Dictionary = SheetPlan.read(images)
_found = found["pieces"]
```

`SheetPlan.read` decodes each file, scans it, grids it, bands it, and runs the
likeness compare over every row. There is no cap on how many files, no
progress, and no way to cancel. Windows paints the window "Not responding"
for the duration.

Twenty lines later the form caps what it will **show**:

```gdscript
for index in mini(_found.size(), MAX_PIECES):
```

`MAX_PIECES` is 24. The expensive work is done in full and then thrown away.

Measured:

```
400 numbered 256x256 files: 122 ms, 1 pieces
400 unrelated 256x256 files: 12909 ms, 400 pieces
```

Thirteen seconds for four hundred 256×256 pictures — not large files, an
ordinary folder of poses — of which twenty-four are offered. A thousand files
is about half a minute. A Ctrl+A in a frames folder is all it takes.

The numbered run at 122 ms shows the design is already right where it applies:
`read` scans only the first file of a series and header-checks the rest. It is
the loose files that are each read in full.

## What needs to be fixed

The reader should stop once it has more than the form can use. Nothing else
about the timing is wrong — the big single sheets came in at 1.6 s at worst,
including the sixteen divisions `split_touching` tries, and that is a sheet
nobody has.

## How it should be fixed, and why that way

`SheetPlan.read` takes a **ceiling** on how many pieces are worth finding,
defaulting to none. The form passes `MAX_PIECES`. When the ceiling is reached
the reader stops and says in its notes how many files it did not look at, in
the same notes list the form already prints in amber.

Why this shape:

- **A ceiling, not a cap on files.** The cost is per *picture read*, and the
  reason to stop is that the form has run out of rows — those are the same
  quantity. Capping files would be an arbitrary number that is both too small
  for a folder of cheap tiny frames and too large for a folder of sheets.
- **Opt-in, defaulting to no limit.** `tools/read_sheet.gd` exists to report
  everything in a sheet, and a diagnostic that silently stops at 24 is not a
  diagnostic. The default keeps it, and the suites, reading the whole of what
  they are given.
- **Checked between files, never inside one.** A sheet is cut as a whole or
  not at all: stopping halfway through a grid would hand the owner the first
  three rows of a four-row sheet with no sign that the fourth exists. So the
  ceiling is tested before each file is opened, which means a single grid sheet
  can still return 64 pieces — and the form's existing "there are %d more
  pieces in there" note already covers that case. The two messages have
  different jobs and both are kept.
- **It says so.** Stopping quietly would be a worse bug than the freeze: the
  owner would have no way to know that the files at the end of their selection
  were never looked at.

No threading. A background thread would keep the window alive but would need
cancellation, a progress bar, and care about every autoload the reader touches
(it touches none, which helps, but `Image.load_from_file` on a thread is still
a change in kind). The work here is not 13 seconds of necessary work — it is
13 seconds of work to produce 376 pieces nobody will see. Deleting the work is
the right fix; threading it would be hiding it.

---

## What was fixed

**`scripts/sheet_plan.gd`** — `read` takes a ceiling and stops at it.

Before:

```gdscript
static func read(paths: PackedStringArray) -> Dictionary:
	var pieces: Array[Dictionary] = []
	var notes: PackedStringArray = []

	var grouped: Dictionary = FrameSeries.group(paths)
	for entry in grouped["series"]:
		...
	for path in PackedStringArray(grouped["loose"]):
		var opened: Dictionary = SheetScan.open(path)
		...
	return {"pieces": pieces, "notes": notes}
```

After (the new lines only):

```gdscript
static func read(paths: PackedStringArray, ceiling: int = 0) -> Dictionary:
	...
	var skipped: int = 0
	for entry in grouped["series"]:
		if _enough(pieces, ceiling):
			skipped += 1
			continue
		...
	for path in PackedStringArray(grouped["loose"]):
		# Reading every picture to find pieces the form has no room for is
		# where the thirteen-second freeze came from. Checked between files
		# rather than inside one, because a sheet is cut whole or not at all.
		if _enough(pieces, ceiling):
			skipped += 1
			continue
		...
	if skipped > 0:
		notes.append(
			"DogPet stopped after %d thing%s. Install these, then add the other %d file%s."
			% [pieces.size(), ..., skipped, ...]
		)
	return {"pieces": pieces, "notes": notes}
```

plus:

```gdscript
## Has this reading found everything it was asked for? A ceiling of zero or
## less is no ceiling, which is what tools/read_sheet.gd and the tests want.
static func _enough(pieces: Array[Dictionary], ceiling: int) -> bool:
	return ceiling > 0 and pieces.size() >= ceiling
```

**`scripts/import_form.gd:227`** — the form asks for what it can show:

```gdscript
# Only as many as there are rows for, below: reading the rest is work
# nobody sees. SheetPlan says in its notes how many were left.
var found: Dictionary = SheetPlan.read(images, MAX_PIECES)
```

`tools/read_sheet.gd` and all three suites that call `read` were left alone,
and so keep reading everything.

## Test result after the fix

```
400 numbered 256x256 files: 119 ms, 1 pieces, notes []
400 unrelated 256x256 files:  ... with no ceiling: 12.8 s, 400 pieces
                              with the form's ceiling of 24: 793 ms, 24 pieces
```

**12.9 s to 0.79 s**, a factor of sixteen, and the notes say
`DogPet stopped after 24 things. Install these, then add the other 376 files.`

Suites after the fix: **1057 checks, 0 failures** (1053 at the baseline, plus
RT-14's four guards; RT-15 adds its own below).

## How it relates to the rest of the app

`SheetPlan.read` has four callers:

- `ImportForm._build_sprite_questions` — now passes `MAX_PIECES`.
- `tools/read_sheet.gd` — unchanged, still reports everything, which is its job.
- `tests/test_sheets.gd` and `tests/test_integration.gd` — unchanged, so every
  existing assertion about what a sheet contains still sees all of it.

The default argument means nothing else in the app had to change, and anything
added later gets the old behaviour unless it asks for a ceiling.

The regression guard is in `tests/test_sheets.gd`: a set of files that would
produce more pieces than the ceiling, asserting the piece count stops at it,
that the note is there, and that a ceiling of zero still reads everything.
