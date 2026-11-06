# Red Team Master Report — The Import Engine

Project: DogPet, v1.42 at the start, v1.43 at the end
Engine: Godot 4.7.2 stable, GDScript only, Windows 11 Home
Date: 2026-11-05
Tester: Jack Sparrow, red team consultant (external)

Second engagement. The first (`00-findings-report.md`, `99-master-report.md`,
2026-10-31, v1.21) swept the whole of `scripts/` and is closed. This one was
asked to go at the **import engine** only, which did not exist then: it
arrived in v1.38 and was still being built at v1.42, the commit before I
started. Finding IDs continue from RT-13.

**Outcome: ten findings — 1 Critical, 1 High, 3 Medium, 4 Low, 1 Info — all
ten fixed.** Suite from 1053 checks to 1104, zero failures throughout. One
behaviour change, recorded and justified. Nothing left open.

---

## 1. What the import engine is

The owner points the wizard at whatever art they have — a `.glb`, a sprite
sheet, a folder of numbered PNGs, a ready-made `.zip` — and it works out what
it has been handed, asks only what cannot be measured, writes the manifest
itself and copies the files into `assets/`. The design goal, in the spec's
words: *"No owner should ever have to write a `pet.json` by hand."*

It is seventeen scripts in three layers.

**The sheet reader** turns art of any shape into the one shape DogPet draws —
a horizontal row of equal cells. Nine scripts, none of which touches a node:

```
  SheetPaper     what colour the page is, under the art
  SheetScan      which pixels are drawn on it, and how much down each column
  SheetGrid      the grid, as arithmetic over those two tallies
  SheetBands     rows and cells; and splitting a strip whose frames touch
  SheetLikeness  one animal moving, or several different things
  SheetStages    one animal growing up (v1.41)
  FrameSeries    which file names are a numbered run
  SheetPlan      the front door: puts the rest together into "pieces"
  SheetCutter    the pixels, keyed and baselined, into one strip
```

The flow is strictly one way: `SheetPaper` → `SheetScan` → `SheetGrid` →
`SheetBands` → (`SheetStages`, `SheetLikeness`) → `SheetPlan` → `SheetCutter`.
Everything after `SheetScan` reads a plain `Dictionary` rather than an object,
which is why the suites can hand `SheetGrid` a hand-written array of numbers
and check the answer exactly.

**The installer** decides what lands on disk: `PackBuilder` (the manifest),
`PackInstall` (the checking and the copying), `LifeStages` (naming the ages),
`ImageLimits` (how big is too big), `PackArchive` (the zip).

**The wizard** is the part that gets clicked: `ImportWizard` (three steps),
`ImportForm` (the questions), `ImportPreview`. And `PetSpriteArt` reads back
what was written, which closes the loop.

## 2. Scope, and what was tested

Read line by line, start to finish: all seventeen scripts above, 3,966 lines.
`PackArchive` was re-checked rather than re-audited, since the previous
engagement had been through it.

Tested by running it, with six harnesses in `redteam/tests/`:

| Probe | What it feeds the engine |
|---|---|
| `probe_p1_pure_edges` | every pure function, given rubbish: zero and negative counts, empty lists, `NAN`, `INF`, −10³⁰, 1×1 and 4096×1 pictures, wholly transparent ones, a 20-digit frame number, nine pathological file names, a non-RGBA8 image |
| `probe_p2_load` | 16×16, 32×32 and 64×64 grid sheets, a 4096×2048 backdrop, an 8192×4096 sheet at exactly `MAX_PIXELS`, a touching strip |
| `probe_p3_inversion` | the same three-frame strip cropped tight and cropped loose; a filled gradient; 3000×2400 line art measured at a reduced scale |
| `probe_p4_install` | the installer end to end: an impossible frame count, a file-name collision, a `pet.json` that climbs out of its folder, four hostile stage names |
| `probe_p5_stages_zip` | a four-stage pack through install → export → inspect → extract → re-read; six malformed `stages` lists |
| `probe_p6_freeze` | 2048, 4096 and 8192-wide lane-less strips; 400 numbered files; 400 unrelated files |

All testing was local, against the owner's own code. Every harness writes
only into Godot's own user data folder (`OS.get_user_data_dir()`). `assets/`
and `saves/` were never touched, and `git status` on `assets/` stayed clean
throughout. One stray file written by a probe that was *proving* an escape was
found and removed by hand.

## 3. The one root cause

Nine of the ten findings are the same mistake wearing different clothes:

> **The engine decides what it is looking at by counting, and then never
> checks the answer against anything else.**

It is an easy mistake to make here, because counting is genuinely most of what
this engine can do — a sheet arrives as pixels and nothing else, and the
tallies really are the evidence. The failure is in treating one reading as
settled when a second, cheap, independent reading was available and would have
contradicted it.

- **RT-14** took the commonest colour for the background. The second reading
  it never asked for: *where* that colour is. A background touches the border;
  a dog does not.
- **RT-17** accepted 64 frames for a 30-pixel picture. The second reading: how
  wide the piece actually is.
- **RT-16** de-duplicated cut names and copied names in two separate
  dictionaries, each correct on its own and neither aware of the other.
- **RT-15** counted pieces found without counting rows available to show them.
- **RT-18** joined a manifest's file name to the pack folder without checking
  it stays there, when `is_safe_entry` — the very same judgement — was already
  being applied to the zip's own entries three files away.
- **RT-19** sanitised every name but one.
- **RT-20**, **RT-21**, **RT-22** each take an argument on trust that one
  comparison would have settled.

So the fixes share a shape: **add the cheap second reading, in the one place
that owns the question.** No new layers, no new scripts, one new dependency
(`SheetPaper` now looks at the border it was already iterating past). The
engine's pure-logic discipline from §9 of the spec is what made this possible
— every fix went into a function with no nodes in it and got a headless test
the same hour.

## 4. The findings and what was done

Most severe first. Each links to its fix document.

### RT-14 — Critical — [the subject keyed out as paper](fixes/RT-14-paper-is-the-border.md)

`scripts/sheet_paper.gd`. A sheet cropped tight has more dog on it than page,
so the dog was the commonest colour and was declared the background: keyed out
on the way into the pack, with the page kept in its place. Three frames also
read as one picture, because the remaining ink was one blob with holes in it.

```
paper read as #3c2c24  (the dog is #3c2d23, the page is #ffffff)
  tight.png - one picture
  strip 360x120: 0.0% dog, 26.1% page, 73.9% transparent
  *** THE DOG IS GONE. What was installed is the hole it left. ***
```

The only difference between that sheet and one that worked was how much margin
the artist left.

**Fixed** by asking where the colour is, not just how much of it there is. The
picture's outer ring is tallied as well as the whole, the paper candidates are
walked in order of frequency, and a candidate is the paper only if it covers
`PAPER_SHARE` of the picture **and** `BORDER_SHARE` (half) of the ring. Both
sheets now read identically: page as paper, dog intact, three frames.

### RT-15 — High — [the frozen wizard](fixes/RT-15-stop-reading-at-the-ceiling.md)

`scripts/sheet_plan.gd`, `scripts/import_form.gd`. Every chosen picture was
read in full on the UI thread, with no progress and no cancel, and the form
then showed the first 24. Four hundred 256×256 files took **12.9 seconds** with
the window painted "Not responding".

**Fixed** by giving `read` a ceiling, defaulting to none, which the form sets
to the number of rows it has. **12.9 s → 0.82 s.** It says in its notes how
many files it left: *"DogPet stopped after 24 things. Install these, then add
the other 376 files."* `tools/read_sheet.gd` passes no ceiling and still
reports everything, which is its whole job.

### RT-16 — Medium — [two names, one folder](fixes/RT-16-one-namespace-in-the-pack.md)

`scripts/pack_install.gd`. A cut strip is named for its job (`idle.png`) and a
copied file keeps its own name, de-duplicated in two separate dictionaries. A
chosen file called `idle.png` and a cut strip given the idle job both got
`idle.png`; the copy was written first and the cut overwrote it. `PetPack` read
the result as usable with no problems, and the walk animation was the idle
strip shown as one 96×32 frame.

**Fixed** with one `taken` set that both schemes consult, through a shared
`_reserve`. The cut names are reserved in a first pass so they get first
refusal — their names mean something, a copied file's does not — and the copy
moves to `idle_2.png`. The sheets keep their original order, because a state's
life stages are gathered in it, youngest first.

### RT-17 — Medium — [no half-installed pack](fixes/RT-17-no-half-installed-pack.md)

`scripts/sheet_plan.gd`, `scripts/pack_install.gd`, `scripts/import_form.gd`.
The frames box ran 1 to 64 whatever the piece was. Sixty-four frames of a
30-pixel picture gave sixty-three rects zero pixels wide; `check` passed,
`SheetCutter` failed, and `write` wrote the manifest anyway — leaving a folder
in `assets/pets/` holding a `pet.json` and nothing else, listed in the picker
as broken from then on, with a message that blamed the source pictures.

**Fixed** three ways: `SheetPlan.most_frames` is now the one answer to "how
many frames could this be" and both the box's ceiling and `recount`'s refusal
read it; and `write` installs a pack or removes the folder and says nothing
was installed.

### RT-18 — Medium — [art stays in its pack](fixes/RT-18-art-stays-in-its-pack.md)

`scripts/pet_sprite_art.gd` and four others. Zip-slip was closed properly last
time — I could not get past `is_safe_entry` — but that guards the zip's
*entries*. A zip whose every entry is impeccable could still carry a
`pet.json` naming `../../secret.png`, and nothing read the manifest with the
same suspicion. Accepted, called usable, no problems.

Worth little on its own: no execution, and DogPet talks to nothing, so nothing
leaves the machine. The realistic harms are a shared pack displaying a PNG off
the machine it is installed on, and — more likely — such a pack silently
breaking when it is passed on.

**Fixed** with `PackArchive.inside(folder, file)`, beside `is_safe_entry` so
the import and the read share one rule: a pack cannot be read in a way it
could not have been installed. Five callers — the sprite states and their life
stages, the model, the scene background and props, the UI icons. Subfolders
inside a pack are still allowed, because that is organising, not leaving.

### RT-19 — Low — [the stage name is sanitised too](fixes/RT-19-the-stage-name-is-sanitised-too.md)

`scripts/pack_install.gd`. The one name in the installer that skipped
`safe_file_name`. A stage of `../../../../../../escaped` wrote the strip four
folders above the pack, `SheetCutter.write` reported success, and the manifest
still named it inside. Not reachable from the wizard — stages only ever come
from `LifeStages` — but it is the asymmetry that was the finding.

**Fixed** by cleaning the stage before the name is built rather than after, so
`idle_` stays on the front: `../../../oops` becomes `idle_oops.png`, not
`oops.png`.

### RT-20 to RT-23 — Low and Info — [the last hardening](fixes/RT-20-to-23-the-last-hardening.md)

- **RT-20** — `SheetScan.of_image` converted only its own copy, and
  `SheetStages._colour_of` then read the caller's image four bytes to a pixel.
  An RGB8 one has three: three out-of-bounds reads and a judgement made from
  whatever came back. The doc comment claimed the wizard used this path; it
  does not. Both halves fixed, and the comment corrected rather than left to
  mislead.
- **RT-21** — `even_parts(rect, 0)` printed "Division by zero";
  `dips_at_joins(tally, 0)` answered `true`. Both now answer sensibly.
- **RT-22** — a 20-digit frame number printed an engine error, saturated to
  `INT64_MAX`, and overflowed the gap arithmetic that groups runs. Past twelve
  digits it is not a counter.
- **RT-23** — the frames box showed 64 beside a label reading "200 numbered
  files". A run that cannot be recounted now says its count in words.

## 5. What I could not break

Recorded because it is most of what I tried, and because it says where the
engine is already sound.

- **`PetSpriteArt` on malformed `stages`.** Empty list, nine entries, a bare
  string, a `null`, negative frames, `stages` that is not a list at all — each
  refused with its own plain-English complaint and no crash. This is the
  newest code in the engine and it is the best-behaved.
- **The life-stage round trip.** Install → export → inspect → extract →
  re-read keeps four stages, the `CREDITS.txt`, and the age mapping.
  `sprite_for` answers correctly at 0, 1, 5, 20, 100 and 10⁹ days, and at a
  negative age.
- **`LifeStages`.** Counts of −3, 0, 1, 2, 7, 8, 9, 64 all sensible and
  clamped at `MAX_STAGES`. `index_for` stays in range for `NAN`, `INF`, −10³⁰.
- **`ImageLimits`.** The saturating `MAX_SIDE` fix from the last engagement
  holds — `0x7FFFFFFF²` does not overflow int64 — and an 8192×4096 sheet at
  exactly `MAX_PIXELS` is read without complaint.
- **Degenerate pictures.** 1×1, 4096×1, 1×4096, wholly transparent, a single
  flat colour: all scanned and reported without an error.
- **Line art at a reduced scan scale.** A 3000×2400 sheet of 1-pixel outlines,
  measured at 1/2 with nearest sampling, still read as 4 rows of 3. The
  hairlines survive.
- **Big single sheets.** 4096 cells in 1.25 s; an 8192×1024 lane-less strip,
  which makes `split_touching` try every division, in 1.6 s. No finding.
- **`state_for`.** `creatures.png` does not ask to be fed, `UNSTEADY.png` is
  not a walk, and the folder name is used when the file name says nothing.
- **A dictionary-held `PackedStringArray`.** `SheetPlan.read`'s
  `grouped["loose"].append_array(files)` does mutate the stored value. I
  expected a silent drop there and was wrong.
- **The zip boundary.** `is_safe_entry` still refuses `..`, drive letters,
  leading slashes and the Windows device names, and the byte ceilings from the
  last engagement are still in place and still not settable from a pack.

## 6. Tests added

Fifty-one permanent regression guards, all passing, bringing the suite from
1053 to **1104 checks, 0 failures**.

| Suite | Before | After | Guards for |
|---|---|---|---|
| `test_sheets` | 105 | 127 | RT-14, RT-15, RT-20, RT-21, RT-22 |
| `test_pets` | 137 | 143 | RT-18 (states, life stages, models, subfolders) |
| `test_builder` | 61 | 74 | RT-16, RT-17, RT-19 |
| `test_scenes` | 96 | 101 | RT-18 (backgrounds, tiles, props) |
| `test_integration` | 91 | 96 | RT-17, RT-23, through the real wizard |
| `test_stages` | 65 | 65 | — |
| `test_packs` | 107 | 107 | — |
| `test_needs` | 170 | 170 | — |
| `test_life` | 108 | 108 | — |
| `test_notify` | 68 | 68 | — |
| `test_history` | 45 | 45 | — |

Fourteen of the new checks were run against the code as it was before the fix
and confirmed to fail:

```
with sheet_paper.gd reverted:    3 FAIL  (RT-14)
with pack_install.gd reverted:   5 FAIL  (RT-16, RT-17, RT-19)
with sheet_plan.gd reverted:     5 FAIL  (RT-15)
with the RT-18 fixes reverted:   1 FAIL  (and 5 more by inspection)
```

A guard that cannot fail is not a guard, which is why this was worth the time.

## 7. Remaining risks

Nothing from this engagement is left open. Three things are worth the owner
knowing, none of them a finding.

**The engine still guesses, and it always will.** `split_touching` decides how
many frames are in a strip with no lanes in it by trying every even division
and keeping the one whose pieces look most alike. It is a reading, and a
reading can be wrong. The design already answers this properly — every piece
is shown with its frame count and `recount` re-cuts it on demand — and RT-17
made that box honest. But a sheet whose frames genuinely cannot be told apart
by shape will be read wrong, and the owner is the backstop. That is the right
design; it is not a weakness to be fixed.

**`BORDER_SHARE` is a threshold, and thresholds have a far side.** A sheet
whose subject genuinely covers the border on all four sides of every cell will
now return no paper at all, so nothing is keyed and the whole sheet counts as
ink. That is the safe failure — the art survives and the frames may read as
one piece — but it is a failure, and it is the honest cost of the fix. There is
no reading that gets both cases right, because at that point there is no
background in the picture to find.

**`split_touching` is the engine's slowest path**: 1.6 s for an 8192-wide
strip, fifteen divisions each needing a full likeness compare, on the UI
thread. Under the 13-second freeze it was invisible; now it is the worst case
left. It is not worth fixing at 1.6 s, but it is the thing to look at first if
the wizard ever feels slow again.

Out of scope this time, and untouched since the first engagement: the
notification path, the needs and life models, the tray, the save files, and
`tools/build.ps1`. The first engagement's report covers all of them.

## 8. Keeping it hardened

1. **A new reading needs a second opinion.** This engagement's root cause, in
   one line. When the engine concludes something from one tally, ask what else
   is cheaply knowable that would contradict it. The border test is the model:
   a few thousand extra reads bought the single worst bug in the engine.
2. **A guard that cannot fail is not a guard.** Revert the fix, watch the new
   check go red, put the fix back. It took a few minutes per finding here and
   it is the difference between a test and a comment.
3. **One rule, one place.** `PackArchive.is_safe_entry` and now
   `PackArchive.inside` are the same judgement applied at both ends of the
   trust boundary. RT-16, RT-18 and RT-19 were all "the rule exists but not
   here". When a check is worth making twice, make it callable instead.
4. **Keep the pure-logic rule.** §9 of the spec is not negotiable and it
   earned its keep: every fix here landed in a function with no nodes in it
   and had a headless test the same hour. The one script that needed node
   surgery (`import_form.gd`) was the one that took longest to verify.
5. **Say what you skipped.** RT-15's fix only works because it tells the owner
   it stopped. Quiet optimisations become quiet bugs.
6. **Watch `SheetPaper` specifically.** Everything downstream reads its one
   answer, so a change there moves the reading of every sheet. It now has the
   regression guards it was missing; keep them, and re-run `test_sheets`,
   `test_stages` and `test_builder` together after any change to it.
