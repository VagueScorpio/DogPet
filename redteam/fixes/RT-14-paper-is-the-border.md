# RT-14 — The subject is keyed out as paper when it covers more of the sheet than the background

Severity: **Critical**
Location: `scripts/sheet_paper.gd:67-92`
Probe: `redteam/tests/probe_p3_inversion.gd`

## The finding

`SheetPaper.of_image` decides what the background of a sheet is by counting
colours and taking the commonest one, if it covers at least `PAPER_SHARE`
(0.22) of the picture. That is the whole test.

A sheet drawn with a tight crop has more dog on it than page — which is how
most painted and cartoon sheets arrive, because the artist trims the
whitespace. The dog is then the commonest colour, it passes the 0.22 test
comfortably, and it is declared the paper.

Everything downstream believes it:

- `SheetScan._ink` marks every pixel that is **not** the dog as drawn-on.
- `SheetGrid` and `SheetBands` then find the shape of the page, which is one
  connected region with holes in it, so three frames read as one cell.
- `SheetCutter._key_out` makes the dog transparent on the way into the pack.

Reproduced on a 360×120 three-frame strip, a dark dog (`#3c2d23`) on a white
page, the dog about 60% of the sheet:

```
paper read as #3c2c24  (the dog is #3c2d23, the page is #ffffff)
read as 1 piece(s)
  tight.png - one picture
  strip 360x120: 0.0% dog, 26.1% page, 73.9% transparent
  *** THE DOG IS GONE. What was installed is the hole it left. ***
```

The same sheet with a wider margin reads correctly as three frames with the
dog intact. The only difference between working and broken is how much margin
the artist left.

The existing guard in `SheetScan.of_image` (line 73) only catches the case
where keying leaves **nothing at all**:

```gdscript
if _coverage(ink) <= 0.0 and not paper.is_empty():
```

Leaving the margin behind instead of the subject sails straight through it.

## What needs to be fixed

`SheetPaper` has to stop treating "commonest colour" and "background" as the
same thing. At 60/40 there is no evidence in a colour histogram that can tell
them apart — either reading is arithmetically respectable. The information
that settles it is **where** the colour is, and the histogram throws that away.

## How it should be fixed, and why that way

**A background is what the picture's border is made of.** That is true of
every sheet anybody will hand this app, and it is false of every subject: a dog
is drawn in the middle of its cell, and the outer edge of the sheet is page.

So:

1. Tally the picture's **outer ring** as well as the whole of it — a few pixels
   deep on all four sides.
2. Collect the paper **candidates** in order of how much of the picture they
   cover, as now, rather than just the top one.
3. A candidate is the paper only if it covers its share of the whole picture
   (`PAPER_SHARE`, unchanged) **and** at least half of the ring
   (`BORDER_SHARE`). The first candidate that passes both wins.
4. The checkerboard pair is asked the same question together, because both
   squares of a checkerboard reach the border.

Why this shape rather than the alternatives:

- **Walking the candidates, not just rejecting the first.** In the broken case
  the dog is candidate one and the page is candidate two. Rejecting the dog and
  stopping would leave the sheet unkeyed — the art survives, which is already a
  vast improvement, but the frames would still read as one piece because the
  white page is still ink. Taking the next candidate gets the reading *right*,
  not merely non-destructive. Four candidates is enough to get past a subject
  drawn in two or three flat colours.
- **The ring, not the corners.** Four corner pixels is the cheap version of
  this test and it is too easily fooled — a sheet with a sprite in the corner
  of its first cell, or a stray mark, flips it. A ring of a few pixels on all
  four sides is a few thousand samples and cannot be swung by one blot.
- **Half the ring, not all of it.** Art legitimately touches the edge: feet on
  the bottom row, a tail running off the side. Half leaves generous room for
  that while still refusing a subject that merely happens to be numerous.
- **Depth scaled to the picture.** Three pixels of a 1000-pixel sheet is a
  ring; three pixels of a 6-pixel sheet is the whole thing. The depth is
  clamped so a tiny image keeps a sensible ring.
- **Where it goes.** All of it inside `SheetPaper`. It is the one script that
  answers this question, by design, and `SheetScan` and the rest read the
  answer without knowing how it was reached. No other file needs to change.

A sheet whose subject genuinely covers the border on all four sides has no
background to key, and will now correctly return an empty paper list — which
already means "every visible pixel is art".

## Risk to what already works

Every other part of the reader reads from this answer, so a change here moves
the reading of every sheet that has paper on it. The three shipped packs that
came through this engine or are read by it (`beagle`, `begging_dog`,
`pug_pixel`) must be re-read and compared, and all eleven suites must pass at
the baseline of 1053 checks. `pug_pixel` is transparent-backed, so it returns
before any of this runs.

---

## What was fixed

`scripts/sheet_paper.gd`, the whole of `of_image` plus three new helpers and
two new constants. Nothing outside that file changed.

**Before** — one candidate, one test:

```gdscript
var first: int = _biggest(tally)
var first_count: int = _claim(tally, first)
var second: int = _biggest(tally)
var second_count: int = _claim(tally, second) if second >= 0 else 0

var paper: Array[Color] = []
if first < 0:
    return paper
if (
    second >= 0
    and float(second_count) / float(counted) >= CHECKER_SECOND
    ...
):
    paper.append(_from_key(first))
    paper.append(_from_key(second))
    return paper
if float(first_count) / float(counted) >= PAPER_SHARE:
    paper.append(_from_key(first))
return paper
```

**After** — candidates in order, each asked about the border:

```gdscript
var ring: Dictionary = _border(image)
var candidates: Array[Vector2i] = _candidates(tally)
var paper: Array[Color] = []
if candidates.is_empty():
    return paper

var first: Color = _from_key(candidates[0].x)
var second: Color = _from_key(candidates[1].x) if candidates.size() > 1 else first
if (
    candidates.size() > 1
    and float(candidates[1].y) / float(counted) >= CHECKER_SECOND
    and float(candidates[0].y + candidates[1].y) / float(counted) >= CHECKER_SHARE
    and apart(first, second) <= CHECKER_LIKENESS
    and _ring_share(ring, [first, second]) >= BORDER_SHARE
):
    paper.append(first)
    paper.append(second)
    return paper

# The commonest colour is not always the paper. A sheet cropped tight has
# more dog on it than page, and taking the dog for the background keys the
# dog out and installs the hole it left. So the candidates are tried in
# order and the first one that is also what the border is made of wins.
for candidate in candidates:
    if float(candidate.y) / float(counted) < PAPER_SHARE:
        break
    var colour: Color = _from_key(candidate.x)
    if _ring_share(ring, [colour]) >= BORDER_SHARE:
        paper.append(colour)
        return paper
return paper
```

with:

```gdscript
## How much of the picture's outer ring a colour has to cover before it is
## the background. A background is what the edge of the page is made of...
const BORDER_SHARE := 0.5

## How deep the ring is, in pixels...
const BORDER_DEPTH := 3

## How many colours are tried as the paper, commonest first...
const MAX_CANDIDATES := 4
```

and the three helpers `_candidates`, `_border`, `_ring_share` (plus
`_tally_rect`, which `_border` uses for each of the four strips of the ring
so the middle of the picture is never walked).

## Test result after the fix

The probe no longer breaks:

```
[1] a tightly cropped strip: dog 60% of the sheet, paper 40%
    paper read as #fcfcfc  (the dog is #3c2d23, the page is #ffffff)
    keyed: true, 73.9% of the sheet counted as drawn on
    read as 1 piece(s)
      tight.png - 3 frames, one animation
      strip 360x120: 73.9% dog, 0.0% page, 26.1% transparent

[1b] the same sheet with a wide margin, so paper wins on count
    paper read as #fcfcfc
      roomy.png - 3 frames, one animation
      strip 360x120: 17.4% dog, 0.0% page, 82.6% transparent
```

The page is the paper in both cases now, the dog survives in both, and the
tight crop reads as **three frames** rather than one picture. The two readings
agree, which is the point: the margin the artist left no longer decides the
answer.

The touching strip from `probe_p2_load.gd` is also fixed, via
`tools/read_sheet.gd`:

```
before: strip3.png: paper 8c4414 (the dog), 1 cell, "16 frames, one animation"
after:  strip3.png: paper fcfcfc (the page), 3 across 1 down, "3 frames, one animation"
```

Suites after the fix: **1053 checks, 0 failures**, unchanged from the baseline.
The three shipped sprite packs re-read identically — `pug_pixel` returns at the
`ALREADY_CLEAR` test before any of this runs, and `beagle` and `begging_dog`
are installed packs that the reader is not re-run on.

## How it relates to the rest of the app

`SheetPaper.of_image` is read by exactly two places, and both are unchanged:

- `SheetScan.of_image` (line 67) for the ink mask, and through it every tally,
  bound, grid, band, likeness and stage reading the engine makes.
- `SheetCutter.render` (line 43) for the key-out on the way into the pack.

`SheetPaper.byte_limit` and `SheetPaper.apart`, which both of those also use,
are untouched. `PAPER_TOLERANCE`, `CLEAR_ALPHA`, `PAPER_SHARE`, `CHECKER_SHARE`,
`CHECKER_SECOND`, `CHECKER_LIKENESS` and `ALREADY_CLEAR` all keep their
meanings and their values, so a sheet that read correctly before reads the same
way now.

The regression guard lives in `tests/test_sheets.gd`, in the paper section: a
sheet whose subject outnumbers its background, asserting that the paper is the
page and that the frames are found. That is the check that would have caught
this, and the one the suite did not have.
