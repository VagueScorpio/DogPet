# RT-16 — A cut strip and a copied file can claim one name, and one animation gets the other's art

Severity: **Medium**
Location: `scripts/pack_install.gd:205-223`, with `_take` at 287
Probe: `redteam/tests/probe_p4_install.gd`, case [2]

## The finding

`PackInstall.plan` names files inside the pack two different ways.

A file **copied** in keeps a sanitised version of its own name, de-duplicated
against the other copies by `_take`:

```gdscript
while copies.has(name) and str(copies[name]) != source:
    name = "%s_%d.%s" % [wanted.get_basename(), attempt, wanted.get_extension()]
```

A strip the sheet reader **cut** is named after its job:

```gdscript
sheet["file"] = (
    "%s.png" % state if stage.is_empty()
    else "%s_%s.png" % [state, stage]
)
cuts[sheet["file"]] = cut
```

`copies` and `cuts` are separate dictionaries and neither looks at the other.
A chosen file called `idle.png` lands in the pack as `idle.png`; a cut strip
given the idle job is **also** written as `idle.png`. In `PackInstall.write`
the copies go first and the cuts second, so the cut overwrites the copy — and
the manifest, built before any of it happens, names `idle.png` for both states
with different frame counts.

Reproduced with a 3-frame strip (job: idle) and a plain file that happens to
be called `idle.png` (job: walk):

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
usable with no problems. The walk animation is now the idle strip shown as one
96×32 frame — three dogs side by side, standing still. The file the owner
chose for the walk was copied in and then overwritten before anything read it.

`idle.png` and `walk.png` are the two likeliest names in a folder of dog art,
so this is not an exotic input.

## What needs to be fixed

Two naming schemes share one folder, and the de-duplication lives inside only
one of them. There has to be one list of names already taken, and both schemes
have to consult it.

## How it should be fixed, and why that way

Pull the de-duplication out of `_take` into a `_reserve` that works on a
single `taken` dictionary, and have both the copy branch and the cut branch go
through it.

**The cut names get first refusal.** `idle.png` for the idle animation is a
chosen, meaningful name — the comment in the code says so: "a pack whose files
are idle.png and walk.png can be opened afterwards and understood without the
manifest". A copied file's name is incidental, so when the two collide the
copy is the one that should move and become `idle_2.png`. That means reserving
every cut name before any copy name, which is one extra pass over the sheets.

The pass has to leave the **order** of the sheets alone, because
`PackBuilder.sprite_pet_manifest` gathers a state's life stages into a
`stages` list in the order it meets them, youngest first. So the first pass
only works out the names, into a list indexed the same way, and the second
pass builds the manifest's sheets in their original order.

A cut reserves its name against a source of `""`, which never equals a real
path, so a cut never aliases a copy the way two copies of the same file
legitimately do.

---

## What was fixed

`scripts/pack_install.gd`. `plan` gained a shared `taken` dictionary and a
first pass; `_take` delegates to a new `_reserve`.

**Before** — the cut branch named itself:

```gdscript
Builder.Kind.PET_SPRITE:
    var sheets: Array = []
    for entry in answers.get("sheets", []):
        var sheet: Dictionary = (entry as Dictionary).duplicate()
        var state: String = str(sheet.get("state", ""))
        if state.is_empty():
            continue
        var cut: Dictionary = sheet.get("cut", {})
        if cut.is_empty():
            sheet["file"] = _take(copies, str(sheet.get("path", "")), false)
        else:
            var stage: String = str(sheet.get("stage", ""))
            sheet["file"] = (
                "%s.png" % state if stage.is_empty()
                else "%s_%s.png" % [state, stage]
            )
            ...
```

**After** — cut names are reserved first, in their own pass, and copies yield:

```gdscript
Builder.Kind.PET_SPRITE:
    var entries: Array = answers.get("sheets", [])
    # The cut strips claim their names first, because those names mean
    # something - idle.png is the idle animation - while a copied file's
    # name is incidental. Without this, a chosen file already called
    # idle.png took the name and the cut strip overwrote it afterwards,
    # leaving two states pointing at one picture.
    var cut_names: Array[String] = []
    for entry in entries:
        cut_names.append(_cut_name(taken, entry as Dictionary))
    var sheets: Array = []
    for index in entries.size():
        var sheet: Dictionary = (entries[index] as Dictionary).duplicate()
        var state: String = str(sheet.get("state", ""))
        if state.is_empty():
            continue
        var cut: Dictionary = sheet.get("cut", {})
        if cut.is_empty():
            sheet["file"] = _take(copies, taken, str(sheet.get("path", "")), false)
        else:
            sheet["file"] = cut_names[index]
            sheet["frames"] = SheetCutter.frames_in(cut)
            cuts[sheet["file"]] = cut
            sheet.erase("cut")
        sheet.erase("path")
        sheets.append(sheet)
    local["sheets"] = sheets
```

with the de-duplication now in one place:

```gdscript
# The name a file will have inside the pack, kept unique across everything
# that lands there - copied files and cut strips both. A source of "" is a
# cut, which never aliases a copy the way two copies of one file do.
static func _reserve(taken: Dictionary, wanted: String, source: String) -> String:
	var name: String = wanted
	var attempt: int = 2
	while taken.has(name) and str(taken[name]) != source:
		name = "%s_%d.%s" % [wanted.get_basename(), attempt, wanted.get_extension()]
		attempt += 1
	taken[name] = source
	return name
```

and `_cut_name`, which composes `idle.png` / `idle_puppy.png` and reserves it
(and which is also where RT-19's sanitising went).

## Test result after the fix

```
copies: { "idle_2.png": ".../rt_p4/idle.png" }
cuts:   ["idle.png"]
manifest animations: { "idle": { "file": "idle.png", "frames": 3, "fps": 6.0 },
                       "walk": { "file": "idle_2.png", "frames": 1, "fps": 1.0 } }
write says: []
folder holds: ["idle.png", "idle_2.png", "pet.json"]
read back: usable=true problems=[]
  idle -> file idle.png, 3 frames, 32x32
  walk -> file idle_2.png, 1 frames, 32x32
```

The cut strip kept the meaningful name, the copied file moved to `idle_2.png`,
both files are in the pack, and the walk is 32×32 — the picture the owner
chose — rather than the idle strip.

Suites after the fix: **1065 checks, 0 failures**. The three new checks in
`test_builder` fail against the old code.

## How it relates to the rest of the app

`_take` is called from all three kinds in `plan` — the model's `model` and
`extras`, the room's `image`/`wall`/`floor` and props — and all of them now
share the one `taken` dictionary, so a room whose backdrop and prop reduce to
the same safe name is covered by the same change. The model branch keeps
`keep_name: true`, which is still honoured: a `.gltf` and its `.bin` must keep
their own names or the model breaks.

`PackInstall.write` loops `copies` then `cuts` as before; it no longer matters
which order, because the names cannot collide.

The regression guard is in `tests/test_builder.gd`: a cut strip and a chosen
file both wanting `idle.png`, asserting the two states end up on two different
files and that the cut keeps the plain name.
