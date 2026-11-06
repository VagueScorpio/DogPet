# RT-17 — A frame count wider than the piece installs a broken pack

Severity: **Medium**
Location: `scripts/sheet_plan.gd:83-108`, `scripts/pack_install.gd:247-281`,
`scripts/import_form.gd:259`
Probe: `redteam/tests/probe_p4_install.gd`, case [1]

## The finding

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
the last takes all thirty. `recount` reports `size` as `(0, 30)` and hands it
on without comment.

`PackInstall.check` does not look at the geometry — for a cut sheet it checks
only that the sources still exist and that the frame count is not absurd — so
it passes. `SheetCutter.render` then hits the first zero-width rect and
returns null, and `PackInstall.write` records the failure **and carries on to
write the manifest anyway**:

```gdscript
for name in cuts:
    var trouble: String = SheetCutter.write(cuts[name], target.path_join(str(name)))
    if not trouble.is_empty():
        problems.append(trouble)
# ... and then, unconditionally:
var manifest: String = Builder.manifest_text(plan_data["manifest"])
```

Reproduced:

```
recounted to 64 frames, cell size (0, 30)
PackInstall.check says: nothing wrong
PackInstall.write says: ["could not read the pictures idle.png was cut from"]
the folder now holds: ["pet.json"]
PetPack reads it back: usable=false problems=[
  "the idle image .../overshoot/idle.png is missing",
  "a sprite pack needs at least an idle animation"]
```

A folder is left in `assets/pets/` holding a `pet.json` and nothing else. The
wizard says "installed with problems", which is honest, but the broken folder
stays and shows in the pet picker as a pack with a problem from then on. The
message blames the source pictures, which were fine.

## What needs to be fixed

Three gaps, each worth closing on its own:

1. The number should not be typeable. The box's ceiling is a flat 64 with no
   reference to how wide the piece actually is.
2. `recount` divides without asking whether the division is possible.
3. `write` treats "the art could not be made" as a note rather than as a
   reason not to write a manifest claiming it exists.

## How it should be fixed, and why that way

**One source of truth for the ceiling.** A new `SheetPlan.most_frames(piece)`
answers how many frames a piece could possibly be cut into: the width of what
it covers, capped at `SheetLikeness.MAX_FRAMES`, and 1 for a numbered run,
which cannot be recounted at all. The form uses it for the box's maximum and
`recount` uses it to refuse. Putting the arithmetic in one place is the point —
a cap in the form alone would leave `recount` wrong for every other caller,
and a check in `recount` alone would leave the owner typing a number that is
silently ignored.

**`write` installs a pack or it does not.** On any problem it empties and
removes the target folder and says that nothing was installed. That is a small
behaviour change, recorded below, and it is the right one: a manifest naming
art that was never written is not a partial success, it is a pack that will be
listed as broken forever by something the owner did not do wrong.

The alternative — writing the manifest but dropping the states whose art
failed — was rejected. It would quietly install a different pack from the one
the owner asked for, and for the commonest case (the idle strip failing) it
produces a sprite pack with no idle, which `PetPack` refuses anyway.

The backup is taken by `import_wizard._write` **before** `PackInstall.write`
runs, so removing the target on failure never loses what was there: it is
already in `assets/_backup/`.

---

## What was fixed

**`scripts/sheet_plan.gd`** — a public ceiling, and `recount` refusing:

```gdscript
## The most frames this piece could be cut into: the width of what it covers,
## since a frame cannot be narrower than a pixel.
##
## Public because the form needs the same number for its frames box. A cap
## there and a check here have to agree, so there is one of them.
static func most_frames(piece: Dictionary) -> int:
	var cut: Dictionary = piece.get("cut", {})
	var paths: PackedStringArray = cut.get("paths", PackedStringArray())
	var rects: Array = cut.get("rects", [])
	# A run of numbered files has as many frames as it has files.
	if rects.is_empty() or paths.size() > 1:
		return maxi(1, int(piece.get("frames", 1)))
	var whole: Rect2i = rects[0]
	for rect in rects:
		whole = whole.merge(rect)
	return clampi(whole.size.x, 1, SheetLikeness.MAX_FRAMES)
```

and in `recount`, after the existing guards:

```gdscript
	# Asking for more frames than the piece is wide gives frames nothing
	# pixels wide, which SheetCutter cannot render and the installer then
	# blamed on the source pictures.
	if frames > most_frames(piece):
		return piece
```

**`scripts/import_form.gd`** — the box cannot be driven past it:

```gdscript
		var most: int = SheetPlan.most_frames(piece)
		var count: SpinBox = _spin(row, frames, 1, maxi(frames, most), 1)
```

**`scripts/pack_install.gd`** — `write` leaves nothing behind on failure:

```gdscript
	file.store_string(manifest)
	file.close()
	return problems
```

became

```gdscript
	file.store_string(manifest)
	file.close()
	return problems

...

# A pack is installed or it is not. A manifest naming art that was never
# written leaves a folder in assets/ that the pet picker lists as broken for
# ever, over something the owner did nothing wrong to cause. Whatever was
# there before this ran is already in assets/_backup, taken by the wizard.
static func _nothing_installed(
	target: String, problems: PackedStringArray
) -> PackedStringArray:
	PackArchive.empty_folder(target)
	DirAccess.remove_absolute(target)
	var said: PackedStringArray = ["nothing was installed"]
	said.append_array(problems)
	return said
```

called from the two places `write` can fail after making the folder — the
copies-and-cuts stage and the manifest write.

## Test result after the fix

```
[1] a 30x30 picture asked for 64 frames
    recounted to 1 frames, cell size (30, 30)
    PackInstall.check says: nothing wrong
    PackInstall.write says: []
    the folder now holds: ["idle.png", "pet.json"]
    PetPack reads it back: usable=true problems=[]
```

`recount` refuses the impossible count and keeps the piece as it was, so the
pack installs correctly as one frame. The form's box now stops at 30 for this
piece, so the number is not typeable in the first place.

And when a cut genuinely cannot be rendered — forced by handing `write` a cut
whose source has been deleted — the folder does not survive it:

```
    write says: ["nothing was installed", "could not read the pictures idle.png was cut from"]
    folder exists afterwards: false
```

Suites after the fix: **1065 checks, 0 failures**. The four new checks in
`test_builder` fail against the old code.

## Behaviour change, recorded

`PackInstall.write` used to leave a half-written pack behind and report the
problems; it now removes the folder and reports that nothing was installed.
`import_wizard._write` already branches on `problems.is_empty()` and shows
`"X was installed with problems: ..."`, which now reads correctly as a failure
rather than describing a folder the owner will go looking for. Nothing else
read the old behaviour.

## How it relates to the rest of the app

`SheetPlan.most_frames` is now the only answer to "how many frames could this
be", used by `recount` and by `import_form`. `SheetGrid.even_parts` is still
reachable with a count of zero from outside — closed separately under RT-21.

`PackInstall.write` is called from `import_wizard._write` and from
`tests/test_builder.gd` and `tests/test_integration.gd`; all of them read the
returned `problems` and none of them inspected the folder after a failure.

The regression guards are in `tests/test_builder.gd`: a recount past the
piece's width leaves it unchanged, `most_frames` answers the width for a cut
piece and the file count for a run, and a `write` whose cut cannot be rendered
leaves no folder.
