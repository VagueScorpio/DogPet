# Red Team Findings Report — The Import Engine

Project: DogPet v1.42 (Godot 4.7.2, GDScript, Windows 11)
Date: 2026-11-05
Tester: Jack Sparrow, red team consultant (external)

Second engagement. The first one (`00-findings-report.md`, 2026-10-31, DogPet
v1.21) swept the whole of `scripts/` and is closed — all thirteen of its
findings are fixed. This one was asked to go at the **import engine** only,
which did not exist then: it arrived in v1.38 and was still being built as
recently as v1.42, the commit before I started. Finding IDs continue from
RT-13 so nothing in `fixes/` collides.

## Scope

Read line by line, start to finish:

| File | Lines | What it does |
|---|---|---|
| `scripts/sheet_paper.gd` | 141 | what colour the page is |
| `scripts/sheet_scan.gd` | 246 | which pixels are drawn on it |
| `scripts/sheet_grid.gd` | 258 | the grid, from the two tallies |
| `scripts/sheet_bands.gd` | 162 | rows and cells, and splitting a touching strip |
| `scripts/sheet_likeness.gd` | 110 | one animal moving, or several things |
| `scripts/sheet_stages.gd` | 221 | one animal growing up |
| `scripts/frame_series.gd` | 131 | numbered runs of files |
| `scripts/sheet_plan.gd` | 311 | the front door |
| `scripts/sheet_cutter.gd` | 218 | the pixels, into one strip |
| `scripts/life_stages.gd` | 132 | naming and choosing stages |
| `scripts/image_limits.gd` | 119 | how big is too big |
| `scripts/pack_builder.gd` | 311 | the manifest |
| `scripts/pack_install.gd` | 309 | what lands on disk |
| `scripts/pet_sprite_art.gd` | 152 | reading the animations block back |
| `scripts/import_form.gd` | 514 | the questions |
| `scripts/import_wizard.gd` | 321 | the clicking |
| `scripts/pack_archive.gd` | 430 | the zip path (re-checked, not re-audited) |

Baseline before I started: **eleven suites, 1053 checks, 0 failures**
(`test_needs` 170, `test_pets` 137, `test_life` 108, `test_packs` 107,
`test_sheets` 105, `test_scenes` 96, `test_integration` 91, `test_notify` 68,
`test_stages` 65, `test_builder` 61, `test_history` 45). None of them fails
now; nothing below was found by breaking an existing test, and nothing below
is caught by one.

All testing was local, against the owner's own code. Harnesses are in
`redteam/tests/probe_p1` through `probe_p6`. They write only into Godot's own
user data folder (`OS.get_user_data_dir()`); `assets/` and `saves/` were never
touched, and `git status` on `assets/` is clean.

## Summary

**Ten findings: 1 Critical, 1 High, 3 Medium, 4 Low, 1 Info.** Nine are
confirmed with a working reproduction. One is cosmetic.

The engine is better built than most of what I am handed. Eight of the nine
sheet-reader scripts are genuinely pure, the decisions are documented with the
reasoning rather than the result, and `PetSpriteArt` refused every malformed
`stages` list I could invent — empty, nine long, a string in it, a null in it,
negative frames, not a list at all — with a plain-English complaint each time
and no crash. A four-stage pack survived install, export to zip, inspect,
extract and re-read with its stage count and its age mapping intact. The zip
boundary that the last engagement hardened is still hard.

The hole is somewhere else, and it is one idea rather than ten:
**the engine decides what it is looking at by counting, and never checks the
answer against anything.**

RT-14 is the whole engagement in one line. `SheetPaper` takes the commonest
colour as the background. Hand it a tightly cropped sheet — a dark dog filling
60% of each cell, a white margin filling 40% — and it concludes that the dog is
the paper, keys the dog out, keeps the page, and reads three frames as one
picture. Nothing anywhere notices. The owner installs it, the dog appears in
the app as a white blob, and the only difference between that sheet and one
that works is how much margin the artist happened to leave. For an engine whose
entire job is "give it whatever you have and it will cut it up", silently
inverting the art is as bad as it gets.

The rest fall out of the same habit. A frame count larger than the piece is
wide is accepted and produces sixty-three zero-width frames (RT-17). A cut
strip and a copied file both claim `idle.png` and the second quietly wins
(RT-16). Four hundred chosen pictures are all read on the UI thread, taking
thirteen seconds with the window dead, after which twenty-four of them are
shown (RT-15). `pet.json` may name a file outside its own folder and does
(RT-18). A stage name goes into a file path without the sanitising every other
name in the installer gets, and the strip lands four folders above the pack
(RT-19).

None of this is a security hole. There is no code execution here and no
privilege to take — `assets/` is the owner's own folder and the one genuinely
dangerous thing a pack could do (the PowerShell and shell-open paths) was
closed in the first engagement. RT-18 is the only finding with an attacker in
it, and the worst it buys is reading a PNG off the machine. These are
correctness failures, which in an import engine is the thing that matters:
every one of them ends with art on disk that is wrong, and the owner finding
out later.

## Findings

| ID | Severity | Title | File:Line | Status |
|---|---|---|---|---|
| RT-14 | **Critical** | The subject is keyed out as paper when it covers more of the sheet than the background | `sheet_paper.gd:67` | **Fixed** |
| RT-15 | **High** | The wizard freezes for 13 s on 400 pictures, then offers 24 of them | `import_form.gd:227` | **Fixed** |
| RT-16 | Medium | A cut strip and a copied file can claim one name, and one animation gets the other's art | `pack_install.gd:207` | **Fixed** |
| RT-17 | Medium | A frame count wider than the piece installs a broken pack | `sheet_plan.gd:96` | **Fixed** |
| RT-18 | Medium | `pet.json` may name art outside its own pack folder | `pet_sprite_art.gd:74` | **Fixed** |
| RT-19 | Low | An unsanitised stage name writes the strip outside the pack | `pack_install.gd:215` | **Fixed** |
| RT-20 | Low | `SheetScan.of_image` trusts the format; `SheetStages` then reads past the buffer | `sheet_scan.gd:51` | **Fixed** |
| RT-21 | Low | `even_parts` divides by zero; `recount` indexes an empty list | `sheet_grid.gd:185` | **Fixed** |
| RT-22 | Low | A 20-digit frame number logs an engine error and saturates | `frame_series.gd:92` | **Fixed** |
| RT-23 | Info | The frames box shows 64 for a run of 200 files | `import_form.gd:259` | **Fixed** |

---

### RT-14: The subject is keyed out as paper when it covers more of the sheet than the background

- **Severity:** Critical
- **Location:** `scripts/sheet_paper.gd:67-92`, with the consequence visible in `scripts/sheet_scan.gd:73`
- **Category:** Logic — unchecked assumption about input
- **Harness:** `redteam/tests/probe_p3_inversion.gd`

**What's wrong**

`SheetPaper.of_image` finds the paper by counting colours and taking the
biggest neighbourhood:

```gdscript
var first: int = _biggest(tally)
var first_count: int = _claim(tally, first)
...
if float(first_count) / float(counted) >= PAPER_SHARE:
    paper.append(_from_key(first))
```

`PAPER_SHARE` is 0.22. The test is "does one colour cover a fifth of the
picture", and nothing else. A sheet drawn with a tight crop — which is how
most cartoon and painted sheets arrive, because the artist trims the
whitespace — has more dog on it than page. The dog is then the commonest
colour, it passes the 0.22 test comfortably, and it is declared the paper.

Everything downstream believes it. `SheetScan._ink` marks every pixel that is
*not* the dog as drawn-on. `SheetGrid` and `SheetBands` then find the shape of
the **page**, which is one connected region with holes in it, so the three
frames read as one cell. And `SheetCutter._key_out` makes the dog transparent
on the way into the pack.

`SheetScan` has a guard for the related case, at line 73:

```gdscript
if _coverage(ink) <= 0.0 and not paper.is_empty():
```

but that only fires when keying leaves *nothing at all* — a single flat tile.
Leaving behind the margin instead of the subject sails straight through it.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_p3_inversion.gd
```

The probe builds two 360×120 three-frame strips of the same dark dog
(`#3c2d23`) on the same white page. They differ only in margin: the first is
cropped tight (dog ≈ 60% of the sheet), the second has a wide margin (dog
≈ 17%).

**What happens**

```
[1] a tightly cropped strip: dog 60% of the sheet, paper 40%
    paper read as #3c2c24  (the dog is #3c2d23, the page is #ffffff)
    keyed: true, 26.1% of the sheet counted as drawn on
    read as 1 piece(s)
      tight.png - one picture
      strip 360x120: 0.0% dog, 26.1% page, 73.9% transparent
      *** THE DOG IS GONE. What was installed is the hole it left. ***

[1b] the same sheet with a wide margin, so paper wins on count
    paper read as #fcfcfc  (the dog is #3c2d23, the page is #ffffff)
    read as 1 piece(s)
      roomy.png - 3 frames, one animation
      strip 360x120: 17.4% dog, 0.0% page, 82.6% transparent
```

Two failures from the one cause: the strip that goes into the pack contains
**no dog at all**, and the frame count is wrong as well — one picture instead
of three, because the remaining ink is one blob.

It also fires on a sheet built the other way round. `probe_p2_load.gd` draws
three touching brown frames on white and `tools/read_sheet.gd` reports it
plainly:

```
strip3.png: 960 x 320, measured at 1/1, paper 8c4414, 37.1% drawn on
  grid: 1 across, 1 down, cell 960 x 320, regular, 1 cells used
strip3.png - 16 frames, one animation
```

`8c4414` is the dog. One cell, so `split_touching` ran, and it cut the page
into **sixteen** frames.

**Why it happens**

The commonest colour and the background are different things, and the code
treats them as the same thing. There is no evidence in a colour histogram
alone that can tell them apart: at 60/40 either reading is arithmetically
respectable. The information that settles it is *where* the colour is, and the
histogram throws that away.

**Recommended fix**

A background is what the picture's border is made of. Tally the outer ring —
a few pixels deep on all four sides — and require a paper candidate to
dominate it as well as to cover its share of the whole. The ring costs a
fraction of what the full tally already costs, the existing share and
checkerboard tests stay exactly as they are (a checkerboard dominates the
border too), and the one case it changes is this one: the dog is in the middle
of its cell and is not what the edge is made of.

A subject that genuinely touches all four edges of every cell has no
background to key and should be left alone, which is what an empty paper list
already means.

**Related code affected**

`SheetScan.of_image` (ink, coverage, bounds, both tallies), `SheetGrid.of_scan`,
`SheetBands`, `SheetLikeness`, `SheetStages`, `SheetPlan.read` and
`SheetCutter._key_out` all read from this one answer. Fixing it moves every
reading for an affected sheet, so the whole of `test_sheets`, `test_stages` and
`test_builder` has to be re-run, and the two packs this engine installed
(`assets/pets/beagle`, `assets/pets/begging_dog`) re-read to confirm they are
unchanged.

---

### RT-15: The wizard freezes for 13 seconds on 400 pictures, then offers 24 of them

- **Severity:** High
- **Location:** `scripts/import_form.gd:227`, `scripts/sheet_plan.gd:36-71`
- **Category:** Resources — unbounded work on the UI thread
- **Harness:** `redteam/tests/probe_p6_freeze.gd`

**What's wrong**

`ImportForm._build_sprite_questions` reads every chosen picture inline:

```gdscript
var found: Dictionary = SheetPlan.read(images)
_found = found["pieces"]
```

`SheetPlan.read` decodes each file, scans it, grids it, bands it and runs the
likeness compare over every row. There is no cap on the number of files, no
progress, and no way to cancel. The window is up and unresponsive throughout —
Windows paints it "Not responding".

Twenty lines later the form caps what it will *show*:

```gdscript
for index in mini(_found.size(), MAX_PIECES):
```

`MAX_PIECES` is 24. So the expensive work is done in full and then thrown
away.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_p6_freeze.gd
```

**What happens**

```
2048x1024 strip:   1568 ms, 1 pieces
4096x1024 strip:    846 ms, 1 pieces
8192x1024 strip:   1613 ms, 1 pieces
400 numbered 256x256 files: 122 ms, 1 pieces
400 unrelated 256x256 files: 12909 ms, 400 pieces
```

Thirteen seconds for four hundred 256×256 pictures — not large files, an
ordinary folder of poses — of which the form will offer twenty-four. A
thousand files comes to about half a minute. A Ctrl+A in a frames folder is
all it takes.

The numbered run at 122 ms shows the design is right when it applies:
`SheetPlan.read` scans only the first file of a series and header-checks the
rest. It is the loose files that are each read in full.

The big single sheets are fine — 1.6 s at worst, including the sixteen
divisions `split_touching` tries. No finding there.

**Why it happens**

Every loose path gets `SheetScan.open`, which decodes the PNG, converts it to
RGBA8, duplicates it, resizes it, histograms it and walks every pixel twice.
At 256×256 that is a few dozen milliseconds, and nothing multiplies it by the
number of files before deciding to do it four hundred times.

**Recommended fix**

Stop reading once there are more pieces than the form will show. `SheetPlan.read`
should take a ceiling, default it to no limit for `tools/read_sheet.gd`, and
have the form pass `MAX_PIECES`; when it stops early it says so in the notes,
which the form already prints in amber. That turns the 400-file case into
roughly the cost of the first 24 files and changes nothing about what the owner
sees.

Worth adding a hard ceiling on chosen files as well, so the honest answer to
two thousand files is a sentence rather than a minute.

**Related code affected**

`tools/read_sheet.gd` calls `SheetPlan.read` and must keep reading everything,
so the ceiling has to be opt-in rather than baked in.

---

### RT-16: A cut strip and a copied file can claim one name, and one animation gets the other's art

- **Severity:** Medium
- **Location:** `scripts/pack_install.gd:205-223`, with `_take` at 287
- **Category:** Logic — two namespaces, one folder
- **Harness:** `redteam/tests/probe_p4_install.gd`, case [2]

**What's wrong**

`PackInstall.plan` names files inside the pack two different ways. A file
copied in keeps a sanitised version of its own name, de-duplicated against the
other copies by `_take`. A strip the sheet reader cut is named after its job:

```gdscript
sheet["file"] = (
    "%s.png" % state if stage.is_empty()
    else "%s_%s.png" % [state, stage]
)
cuts[sheet["file"]] = cut
```

`copies` and `cuts` are separate dictionaries and neither looks at the other.
A chosen file called `idle.png` therefore lands in the pack as `idle.png`, and
a cut strip given the idle job is *also* written as `idle.png`. In
`PackInstall.write` the copies go first and the cuts go second, so the cut
overwrites the copy — and the manifest, built before any of it, names
`idle.png` for both states with different frame counts.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_p4_install.gd
```

Case [2] gives the wizard a 3-frame strip (job: idle) and a plain file that
happens to be called `idle.png` (job: walk).

**What happens**

```
check says: nothing wrong
copies: { "idle.png": ".../rt_p4/idle.png" }
cuts:   ["idle.png"]
manifest animations: { "idle": { "file": "idle.png", "frames": 3, "fps": 6.0 },
                       "walk": { "file": "idle.png", "frames": 1, "fps": 1.0 } }
write says: []
folder holds: ["idle.png", "pet.json"]
read back: usable=true problems=[]
  idle -> file idle.png, 3 frames, 32x32
  walk -> file idle.png, 1 frames, 96x32
```

No complaint from `check`, none from `write`, and `PetPack` calls the pack
usable with no problems. But the walk animation is now the idle strip shown as
one 96×32 frame — three dogs side by side, standing still. The file the owner
chose for the walk was copied in and then overwritten before anything read it.

`idle.png` and `walk.png` are the two most likely names in a folder of dog
art, so this is not an exotic input.

**Why it happens**

Two naming schemes sharing one folder, with the de-duplication living inside
only one of them.

**Recommended fix**

One namespace. Have the cut branch reserve its name through the same
dictionary the copies use — register `cuts` names in `copies`' keyspace (or
keep a single `taken` set that `_take` consults), so the second claimant gets
`idle_2.png` exactly as a second copied `idle.png` already does.

**Related code affected**

`PackInstall.write` loops `copies` then `cuts`; both must agree on the final
names. `test_builder` covers `_take`'s de-duplication among copies and should
gain the cross-case.

---

### RT-17: A frame count wider than the piece installs a broken pack

- **Severity:** Medium
- **Location:** `scripts/sheet_plan.gd:83-108`, `scripts/pack_install.gd:247-281`
- **Category:** Input handling / partial failure
- **Harness:** `redteam/tests/probe_p4_install.gd`, case [1]

**What's wrong**

The frames box in the form is a `SpinBox` with the range 1 to 64, editable for
any piece that came out of a single file:

```gdscript
var count: SpinBox = _spin(row, frames, 1, 64, 1)
count.editable = PackedStringArray(piece["cut"]["paths"]).size() <= 1 or frames == 1
```

Typing 64 against a 30-pixel picture sends `SheetPlan.recount(piece, 64)`,
which divides it with `SheetGrid.even_parts`:

```gdscript
var width: int = rect.size.x / count
```

30 / 64 is 0, so sixty-three of the sixty-four rects are zero pixels wide and
the last one takes all thirty. `recount` reports `size` as `(0, 30)` and hands
it on without comment.

`PackInstall.check` does not look at the geometry — for a cut sheet it checks
only that the sources still exist and that the frame count is not absurd —
so it passes. `SheetCutter.render` then hits the first zero-width rect and
returns null, and `PackInstall.write` records the failure **and carries on to
write the manifest anyway**.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_p4_install.gd
```

**What happens**

```
recounted to 64 frames, cell size (0, 30)
PackInstall.check says: nothing wrong
PackInstall.write says: ["could not read the pictures idle.png was cut from"]
the folder now holds: ["pet.json"]
PetPack reads it back: usable=false problems=[
  "the idle image .../overshoot/idle.png is missing",
  "a sprite pack needs at least an idle animation"]
```

A pack folder is left in `assets/pets/` holding a `pet.json` and nothing else.
The wizard says "installed with problems", which is at least honest, but the
broken folder stays and shows up in the pet picker as a pack with a problem
from then on. The message blames the source pictures, which were fine.

**Why it happens**

Two gaps. `recount` divides without asking whether the division is possible,
and `write` treats "the art could not be made" as a note rather than as a
reason not to write a manifest claiming it exists.

**Recommended fix**

Two small changes, each worth having on its own:

1. `recount` refuses a count that would make a frame narrower than one pixel
   and returns the piece unchanged, the same answer it already gives for a
   numbered run. Better still, the form should cap the box at the piece's own
   width so the number is never typeable.
2. `PackInstall.write` writes the manifest only when the art it names was
   written. When a cut fails, remove what landed and report the folder as not
   installed, rather than leaving a manifest pointing at nothing.

**Related code affected**

`import_wizard._write` reads `problems` and already distinguishes the two
outcomes, so it needs no change beyond not having a half-pack to describe.
`SheetGrid.even_parts` is also reachable with `count` 0 — see RT-21.

---

### RT-18: `pet.json` may name art outside its own pack folder

- **Severity:** Medium
- **Location:** `scripts/pet_sprite_art.gd:61-76`
- **Category:** Path handling / trust boundary
- **Harness:** `redteam/tests/probe_p4_install.gd`, case [3]

**What's wrong**

```gdscript
var file: String = str(spec.get("file", "")).strip_edges()
...
var path: String = folder.path_join(file)
if not FileAccess.file_exists(path):
```

`file` comes out of a `pet.json` that may have arrived in a pack somebody
downloaded. It is joined to the pack folder with no check that it stays there.

The last engagement closed zip-slip properly — `PackArchive.is_safe_entry`
refuses `..`, drive letters, leading slashes and Windows device names, and I
could not get past it. But that guards the *entries* of the zip. A zip whose
every entry is impeccable can still carry a manifest that points outwards, and
nothing reads the manifest with the same suspicion.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_p4_install.gd
```

**What happens**

```
[3] a hand-written pet.json whose file field climbs out of the pack
    PetPack: usable=true problems=[]
    *** idle resolved to a file outside the pack: ../../secret.png ***
```

Accepted, called usable, no problems. The pack then draws a PNG from two
folders above itself. A drive-absolute path (`C:/...`) fails harmlessly,
because `path_join` glues it onto the folder and the result does not exist.

**What it is worth**

Little, and I want to be straight about that. The app reads the file as a
picture and draws it; there is no execution and no exfiltration — DogPet talks
to nothing. The realistic harms are that a shared pack can display a PNG from
the machine it is installed on, and that such a pack silently stops working
when it is passed on, because the file it depends on was never in the zip.

**Why it happens**

The pack folder is treated as a base for joining rather than as a boundary to
stay inside.

**Recommended fix**

Refuse a `file` that is not a plain name inside the pack. `PackArchive.is_safe_entry`
already encodes exactly that judgement and is already used by the installer for
the names it writes — call it here too, and complain in the same plain English
as the other problems ("the idle animation names a file outside the pack").
The same applies to `scene.json`'s `background` and `props` file names, which
`ScenePack` reads the same way.

**Related code affected**

`PetSpriteArt.one` is the single place sprite art resolves a path, so one check
covers every state and every life stage. `ScenePack` needs the matching change,
and `PetPack`'s `model` field deserves a look for the same reason.

---

### RT-19: An unsanitised stage name writes the strip outside the pack

- **Severity:** Low
- **Location:** `scripts/pack_install.gd:214-220`
- **Category:** Path handling
- **Harness:** `redteam/tests/probe_p5_stages_zip.gd`, case [1]

**What's wrong**

Every name `PackInstall` puts in a pack goes through `Builder.safe_file_name`,
which reduces it to the characters an id may contain and then checks it with
`PackArchive.is_safe_entry`. Every name except this one:

```gdscript
var stage: String = str(sheet.get("stage", ""))
sheet["file"] = (
    "%s.png" % state if stage.is_empty()
    else "%s_%s.png" % [state, stage]
)
```

`stage` is pasted straight into a file name, and that name is handed to
`SheetCutter.write`, which calls `save_png` on `target.path_join(name)`.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_p5_stages_zip.gd
```

Case [1] installs into a pack folder four levels deep inside a scratch
sandbox, with `stage` set to `../../../../../../escaped`.

**What happens**

```
cut target: ["idle_../../../../../../escaped.png"]
write says: []
anything at all in the sandbox root: ["a/"]
inside the pack folder: ["pet.json"]
```

Nothing in the sandbox, nothing in the pack — the strip landed at
`<user data>/rt_p5/escaped.png`, four folders above where it belonged.
`SheetCutter.write` returned success, so `PackInstall.write` reported no
problem at all, and the manifest names a file that is not there.

**Reachability**

Not from the wizard today. `stage` only ever comes from
`SheetStages.names_for` → `LifeStages.names_for`, which returns one of a dozen
fixed words. `PackInstall.plan` is nonetheless a public entry point with its
own test suite, and the next thing that sets a stage from anywhere else inherits
this. The asymmetry is the finding: one name in the installer skips the check
the others all take.

**Recommended fix**

Run the composed name through `Builder.safe_file_name`, the same as the copied
files. One line, and it also tidies the manifest for any stage name with a
space or a capital in it.

**Related code affected**

`PackInstall.plan` for `PET_SPRITE`; `test_builder` should gain the case.

---

### RT-20: `SheetScan.of_image` trusts the format; `SheetStages` then reads past the buffer

- **Severity:** Low
- **Location:** `scripts/sheet_scan.gd:51-91`, `scripts/sheet_stages.gd:132-168`
- **Category:** Memory / out-of-bounds read
- **Harness:** `redteam/tests/probe_p1_pure_edges.gd`, case [6b]

**What's wrong**

`SheetScan.open` converts the picture to RGBA8 before measuring it.
`SheetScan.of_image`, which takes a picture already in hand, converts only its
own downscaled copy — the caller's image is passed through untouched. Its
doc comment says the wizard uses it ("so does the wizard, which has the picture
open for its preview already"), and `SheetStages._colour_of` reads the image's
bytes four to a pixel:

```gdscript
var at: int = (line + x) * 4
...
if data[at + 3] < 128:
```

An RGB8 image has three.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_p1_pure_edges.gd
```

**What happens**

```
scan of an RGB8 image: coverage 0.0049, problem ''
now asking SheetStages about it, which reads 4 bytes a pixel...
SCRIPT ERROR: Out of bounds get index '12291' (on base: 'PackedByteArray')
   at: _colour_of (res://scripts/sheet_stages.gd:154)
```

Three errors, then a judgement made from whatever the reads returned. Godot
returns 0 for an out-of-range `PackedByteArray` read rather than falling over,
so this is a wrong answer and a noisy log rather than a crash.

**Reachability**

Not reachable today, and the doc comment is wrong about why: nothing outside
`tests/test_sheets.gd` calls `of_image`. The wizard reaches the reader through
`SheetPlan.read` → `SheetScan.open`, which converts properly. This is a trap
laid for the next caller, with a comment inviting them in.

**Recommended fix**

`of_image` converts the image it was given, exactly as `open` does, and
`_colour_of` checks the buffer is as long as it expects before walking it.
Then correct the comment, which claims a caller that does not exist.

**Related code affected**

`SheetStages.of_cells` and `SheetPaper.of_image` make the same four-bytes
assumption; `SheetCutter._key_out` makes it too but always after an explicit
convert.

---

### RT-21: `even_parts` divides by zero; `recount` indexes an empty list

- **Severity:** Low
- **Location:** `scripts/sheet_grid.gd:183-190`, `scripts/sheet_plan.gd:93`
- **Category:** Input handling
- **Harness:** `redteam/tests/probe_p1_pure_edges.gd`, cases [2] and [3b]

**What's wrong**

```gdscript
static func even_parts(rect: Rect2i, count: int) -> Array[Rect2i]:
    var width: int = rect.size.x / count
```

and

```gdscript
var whole: Rect2i = rects[0]
```

Neither checks its argument.

**What happens**

```
[2] SheetGrid.even_parts(rect, 0) and (rect, -3)
SCRIPT ERROR: Division by zero error in operator '/'.
   at: even_parts (res://scripts/sheet_grid.gd:185)
  count 0 -> 0 parts
  count -3 -> 0 parts

[3b] recount on a piece whose rects list is empty
SCRIPT ERROR: Out of bounds get index '0' (on base: 'Array[Rect2i]')
   at: recount (res://scripts/sheet_plan.gd:93)
```

Both recover — an error in the log and an empty or unchanged answer.
`dips_at_joins(tally, 0)` returns `true`, which is a nonsense answer to a
nonsense question.

**Reachability**

Neither is reachable from the wizard. `split_touching` only ever passes 2 or
more, `recount` guards `frames < 1`, and a piece always carries at least one
rect. Worth closing anyway: these are the public arithmetic of the engine, the
suites call them directly, and an engine error in the log is a thing the owner
will one day have to explain.

**Recommended fix**

`even_parts` returns an empty array for a count below 1. `recount` returns the
piece unchanged when there is nothing to merge. `dips_at_joins` answers `false`
below 2.

---

### RT-22: A 20-digit frame number logs an engine error and saturates

- **Severity:** Low
- **Location:** `scripts/frame_series.gd:92`
- **Category:** Integer handling
- **Harness:** `redteam/tests/probe_p1_pure_edges.gd`, case [5]

**What's wrong**

`split_number` converts whatever digits it found with `int()`, with no limit on
how many there are.

**What happens**

```
ERROR: Cannot represent 99999999999999999999 as a 64-bit signed integer,
       since the value is too large.
   at: _to_int (core/string/ustring.cpp:2281)
   GDScript backtrace:
       [0] split_number (res://scripts/frame_series.gd:92)
  run_99999999999999999999.png -> { "prefix": "run_", "number": 9223372036854775807, ... }
```

An engine error in the log, and the number saturates to `INT64_MAX`. Two such
files both become `INT64_MAX`, so they land in one run in an undefined order,
and `_unbroken`'s `number - previous` overflows, which quietly glues the file
onto whatever run came before.

Everything else I threw at `split_number` was handled correctly, including the
cases the comments claim: `sheet (2).png` is rejected as a Windows duplicate,
`.png` and `....png` give nothing, `a1b2c3.png` buckets on `a1b2c`, and
`walk_-5.png` keeps the minus in the prefix rather than reading a negative
frame. 2000 numbered files group in 15 ms.

**Recommended fix**

Treat a digit run longer than a counter can sensibly be — say past 12 digits —
as not a counter at all, which is the existing answer for a number in brackets.
Returning `{}` puts the file in `loose` where it belongs.

---

### RT-23: The frames box shows 64 for a run of 200 files

- **Severity:** Info
- **Location:** `scripts/import_form.gd:259`
- **Category:** UI / display

```gdscript
var count: SpinBox = _spin(row, frames, 1, 64, 1)
```

A numbered run of 200 files produces a piece with `frames` 200. The box caps
at 64, so it displays 64 beside a label that says "200 numbered files, one
animation". The box is correctly made read-only for a run, and the real count
is what gets installed — `recount` refuses a multi-file piece and `_sheets`
reads `piece["frames"]` — so nothing downstream is wrong. It just contradicts
itself on screen.

Fix: show the count as text rather than as a capped box when the piece cannot
be recounted.

---

## What I could not break

Worth recording, since it is most of what I tried.

- **`PetSpriteArt` on malformed `stages`.** Empty list, nine entries, a bare
  string, a `null`, negative frames, `stages` that is not a list at all — each
  refused with its own plain-English complaint and no crash
  (`probe_p5_stages_zip.gd` case [3]).
- **The life-stage round trip.** A four-stage pack installed, exported with
  `write_pack`, re-inspected, extracted and re-read keeps its four stages, its
  `CREDITS.txt` and its age mapping. `sprite_for` answers correctly at 0, 1, 5,
  20, 100 and 10⁹ days and at a negative age.
- **`LifeStages`.** Counts of −3, 0, 1, 2, 7, 8, 9 and 64 all give sensible
  names, clamped at `MAX_STAGES`. `index_for` stays in range for `NAN`, `INF`
  and −10³⁰.
- **`ImageLimits`.** The saturating `MAX_SIDE` fix from the last engagement
  holds: `0x7FFFFFFF²` does not overflow int64, and an 8192×4096 sheet — exactly
  `MAX_PIXELS` — is read without complaint.
- **Degenerate pictures.** 1×1, 4096×1, 1×4096, wholly transparent, a single
  flat colour: all scanned and reported without an error.
- **Line art at a reduced scan scale.** A 3000×2400 sheet of 1-pixel outlines
  measured at 1/2 still read as 4 rows of 3, which is what it was. The nearest
  sampling does not sample a hairline away.
- **Big single sheets.** 64×64 cells (4096 of them) in 1.25 s; an 8192×1024
  lane-less strip, which makes `split_touching` try every division, in 1.6 s.
- **`state_for`.** `creatures.png` does not ask to be fed, `UNSTEADY.png` is
  not a walk, and a folder name is used when the file name says nothing.
- **The zip boundary.** Re-checked rather than re-audited: `is_safe_entry` still
  refuses `..`, drive letters, leading slashes and the Windows device names, and
  the byte ceilings from the last engagement are still in place and still not
  settable from a pack.
- **A dictionary-held `PackedStringArray`.** `SheetPlan.read`'s
  `grouped["loose"].append_array(files)` does mutate the stored value, so the
  different-sized files it rejects really do fall through to the loose branch.
  I expected that to be a silent drop and it is not.

## What to do about it

My recommendation, in order:

1. **RT-14 first and on its own.** It is the only Critical, it silently
   destroys imported art, and the fix touches the one function every other
   part of the reader reads from. It wants its own commit and a full re-run of
   all eleven suites, plus a re-read of the two packs this engine installed.
2. **RT-15**, because a thirteen-second dead window is what the owner will hit
   first and it reads as a crash.
3. **RT-16 and RT-17 together.** Both end with a pack on disk that is wrong,
   and both are a few lines in `PackInstall`.
4. **RT-18 to RT-22** as one hardening pass. None is urgent; all are small.
5. **RT-23** whenever the form is next touched.

Each fix gets a document in `fixes/` written before the code is touched and
updated after, and a permanent regression check in whichever suite owns it —
`test_sheets` for the reader, `test_builder` for the installer, `test_pets` for
`PetSpriteArt`.

---

## Status, 2026-11-05 — all ten fixed

All ten findings are closed, at the owner's instruction to fix everything and
work through automatically. Every one has a fix document in `fixes/` written
before its code was touched and updated after, and every probe that broke
something has been re-run and no longer breaks:

```
probe_p1_pure_edges   no errors
probe_p2_load         no errors
probe_p3_inversion    no errors
probe_p4_install      no errors
probe_p5_stages_zip   no errors
probe_p6_freeze       no errors
```

The suite stands at **1104 checks / 0 failures**, up from 1053. Fifty-one of
the new checks are permanent regression guards, spread across `test_sheets`
(+22), `test_pets` (+6), `test_builder` (+13), `test_scenes` (+5) and
`test_integration` (+5). Fourteen of them were confirmed to fail against the
code as it was before the fix. The project opens with no script errors.

**One behaviour change was made and is recorded in RT-17's fix document:**
`PackInstall.write` used to leave a half-written pack in `assets/` when a
strip could not be made, and report the problems; it now removes the folder
and says that nothing was installed. The backup the wizard takes beforehand is
untouched, so nothing can be lost by it.

See `99-master-report-import-engine.md` for the whole engagement.
