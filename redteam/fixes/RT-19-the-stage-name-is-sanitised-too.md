# RT-19 — An unsanitised stage name writes the strip outside the pack

Severity: **Low**
Location: `scripts/pack_install.gd:214-220`
Probe: `redteam/tests/probe_p5_stages_zip.gd`, case [1]

## The finding

Every name `PackInstall` puts in a pack goes through
`Builder.safe_file_name`, which reduces it to the characters an id may contain
and then checks it with `PackArchive.is_safe_entry`. Every name except one:

```gdscript
var stage: String = str(sheet.get("stage", ""))
sheet["file"] = (
    "%s.png" % state if stage.is_empty()
    else "%s_%s.png" % [state, stage]
)
```

`stage` is pasted straight into a file name, and that name is handed to
`SheetCutter.write`, which calls `save_png` on `target.path_join(name)`.

Reproduced with a pack folder four levels deep in a scratch sandbox and
`stage` set to `../../../../../../escaped`:

```
cut target: ["idle_../../../../../../escaped.png"]
write says: []
inside the pack folder: ["pet.json"]
```

The strip landed at `<user data>/rt_p5/escaped.png`, four folders above where
it belonged. `SheetCutter.write` returned success, so `PackInstall.write`
reported no problem at all, and the manifest named a file that was not there.

## Reachability

Not from the wizard today. `stage` only ever comes from
`SheetStages.names_for` → `LifeStages.names_for`, which returns one of a dozen
fixed words. `PackInstall.plan` is nonetheless a public entry point with its
own test suite, and the next thing that sets a stage from anywhere else
inherits this.

**The asymmetry is the finding**: one name in the installer skips the check
the others all take, and nothing marks it as the exception.

## How it should be fixed, and why that way

Clean the **stage**, then build the name — not the other way round.

Running the composed name through `safe_file_name` is the obvious move and it
is wrong in a small way that matters: `safe_file_name` works on
`path.get_file().get_basename()`, so `"idle_../../../oops.png"` reduces to
`"oops.png"` and the state falls off the front. The file would be safe and
unrecognisable. Cleaning the part keeps `idle_` where it belongs:
`clean_id("../../../oops")` is `"oops"`, and the name comes out
`idle_oops.png`.

The composed name still goes through `safe_file_name` afterwards, as a
belt-and-braces: it is a no-op for any ordinary stage, and it covers `state`
as well, which comes from `PetPack.VALID_STATES` today but need not for ever.

A stage that cleans away to nothing — `"..."` — is treated as no stage at all,
which gives the plain `idle.png`. That is the right answer rather than
`idle_.png`.

---

## What was fixed

This landed with RT-16, which moved the cut naming into `_cut_name` for its
own reasons, so the two changes share one function. `scripts/pack_install.gd`:

```gdscript
static func _cut_name(taken: Dictionary, sheet: Dictionary) -> String:
	var state: String = str(sheet.get("state", ""))
	if state.is_empty() or Dictionary(sheet.get("cut", {})).is_empty():
		return ""
	# The stage is cleaned before the name is built, not after. This was the
	# one name in the installer that skipped the sanitising every other one
	# takes, and a stage of "../../x" wrote the strip outside the pack folder
	# while the manifest still named it inside. Cleaning the part rather than
	# the whole keeps the state on the front, where it belongs.
	var stage: String = Builder.clean_id(str(sheet.get("stage", "")))
	var wanted: String = Builder.safe_file_name(
		"%s.png" % state if stage.is_empty() else "%s_%s.png" % [state, stage]
	)
	return _reserve(taken, wanted, "")
```

## Test result after the fix

The escape no longer escapes:

```
cut target: ["idle_escaped.png"]
write says: []
anything at all in the sandbox root: ["a/"]
inside the pack folder: ["idle_escaped.png", "pet.json"]
```

and nothing leaks anywhere — `find` over the whole user data folder for
`escaped.png` comes back empty.

Every stage name tried, through `PackInstall.plan`:

| stage given | file name before | file name now |
|---|---|---|
| `puppy` | `idle_puppy.png` | `idle_puppy.png` |
| `../../../oops` | `idle_../../../oops.png` | `idle_oops.png` |
| `con` | `idle_con.png` | `idle_con.png` |
| `a b/c` | `idle_a b/c.png` | `idle_a_b_c.png` |

The ordinary case is untouched, which is what the shipped four-stage round
trip confirms: `idle_puppy.png`, `idle_juvenile.png`, `idle_adult.png`,
`idle_senior.png`, installed, exported, extracted and re-read with four stages
intact.

Suites after the fix: **1077 checks, 0 failures**. The two new checks in
`test_builder` ("a stage name cannot climb out of the pack folder", "and the
state is still on the front of it") fail against the old code.

## How it relates to the rest of the app

`_cut_name` is the only place a cut strip's name is decided, and it is now the
only place a stage reaches a file path. `Builder.safe_file_name` and
`Builder.clean_id` are unchanged and still used by `_take` for copied files,
so the installer has one sanitising rule applied in two places rather than one
place and one exception.

`PackBuilder.sprite_pet_manifest` writes the manifest from the same
`sheet["file"]` this produces, so the manifest and the disk agree — which is
the part that was actually broken, more than the escape itself.
