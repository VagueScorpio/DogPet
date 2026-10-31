# RT-06: The last good save is deleted before the new one lands

Severity: Medium
Location: `scripts/save_file.gd:36-44`

## The finding

```gdscript
if FileAccess.file_exists(path):
	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(bak_path)
	if DirAccess.rename_absolute(path, bak_path) != OK:
		# No backup this time, but a good save still beats a stale one.
		DirAccess.remove_absolute(path)
```

Three problems in five lines:

1. The old backup is removed **before** anyone knows a new one can be made.
2. When the rename fails, the only remaining good save is deleted — and the
   return value of that deletion is ignored.
3. The function still returns `true` if the final rename works, so the app
   never learns it is now running without a fallback.

On Windows a rename fails routinely when something holds a handle: antivirus
mid-scan, OneDrive or Dropbox syncing the folder, a backup agent, Explorer's
preview pane — or when the `.bak` has picked up a read-only flag.

Proven with `redteam/tests/probe_f_save.gd`:

```
with pet.json.bak unusable:
  third save reports: true
  pet.json now holds: Pickle
  a usable backup exists: false
  after pet.json is corrupted, recovery source: none
  recovered dog: <THE DOG IS GONE>
```

The save reports success, the backup is gone, and from then on *every* save
deletes the previous good file — so the fallback never comes back and the first
interrupted write loses the dog. `Needs._ready` has correct recovery code that
now has nothing to recover from.

## What needs to be fixed

The order. Nothing good may be destroyed before its replacement is in place,
and a save that could not keep a backup has to say so.

## How it should be fixed, and why that way

Reorder to copy-then-replace, and report honestly:

1. Write `pet.json.tmp` (unchanged).
2. **Copy** the current `pet.json` to the backup, rather than moving it. A copy
   leaves the original in place while it happens, so a failure costs nothing; a
   move is a destructive act performed on the only good copy. Write the copy to
   `pet.json.bak.tmp` and rename that over `pet.json.bak`, so an interrupted
   copy cannot leave a half-written backup either.
3. If the backup cannot be made, keep the **existing** `.bak` and carry on. A
   slightly stale backup is worth enormously more than none.
4. Rename `tmp` over `path`. If that fails, leave `path` alone and return
   `false`. Never delete it.
5. Return `false` when no backup could be maintained, so `Needs.save_now` can
   log that the save folder has quietly stopped working properly.

The one behaviour change worth stating: step 5 means `write_atomic` can now
return `false` in a case where it used to return `true` — the save itself
succeeded but the backup could not be refreshed. `Needs.save_now` logs an error
on `false`, which would be slightly misleading, so it is given a separate,
accurate message for that case rather than "could not save the dog".

`PetHistory.save_records` writes `history.json` in place with no temp file and
no backup at all, so a crash mid-write loses every remembered dog. Same defect
class, two lines to fix by routing it through `SaveFile.write_atomic`, and the
scoreboard is the one file in the app that is meant to outlive everything else.
Done here rather than left as a note.

Verification plan: re-run `probe_f_save.gd` and confirm a usable backup survives
an unusable `.bak`, and that a corrupted `pet.json` still recovers.

---

## What was fixed

`scripts/save_file.gd`, `scripts/needs.gd`, `scripts/pet_history.gd`,
`tests/test_needs.gd`, `tests/test_history.gd`.

### Changed — `SaveFile.write_atomic`

Now returns a `bool` for "the save landed" and sets `last_write_kept_backup` for
"and a backup exists". The copy-then-rename shape replaces move-then-hope.

### Changed — `Needs.save_now`

```gdscript
	if not SaveFile.write_atomic(Paths.pet_save_path(), payload):
		Log.error("Could not save the dog to " + Paths.pet_save_path())
	elif not SaveFile.last_write_kept_backup:
		# Worth saying once it starts happening: the save went in, but the
		# safety net under it did not, so the next corrupt write has nothing
		# to fall back on. Usually something else holding the file open.
		Log.warn("Saved, but could not refresh the backup at "
			+ Paths.pet_save_path() + ".bak")
```

### Changed — `PetHistory.save_records`

Routed through `SaveFile.write_atomic`, so the scoreboard gets the same
temp-file-and-backup treatment as the dog.

## Test result after the fix

`redteam/tests/probe_f_save.gd`, same unusable `.bak`:

```
with pet.json.bak unusable:
  third save reports: true
  it reports the backup was kept: false
  pet.json now holds: Pickle
  a usable backup exists: true      <- the older one, left in place
  after pet.json is corrupted, recovery source: backup
  recovered dog: Rex
```

The dog survives. The backup is now one generation older than it would ideally
be, which is the correct trade and is reported rather than hidden.

Also checked: with a healthy folder the backup still rolls forward normally,
`pet.json.tmp` and `pet.json.bak.tmp` are both cleaned up, and a corrupt
`pet.json` with no backup at all still means a fresh dog rather than a crash.

The existing save tests in `tests/test_needs.gd` and `tests/test_history.gd` all still pass unchanged, which is the point: the reordering is invisible to a healthy save folder. The unusable-backup case is covered by the probe above rather than by a suite check, because making a `.bak` unrenameable needs a directory in its place and that is awkward to set up and tear down inside a shared scratch folder.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`SaveFile.write_atomic`** — the fixed code. Used by `Needs.save_now` and now
  by `PetHistory.save_records`.
- **`SaveFile.read_with_fallback` / `read_one`** — unchanged; they were already
  correct and are what this protects.
- **`Needs.save_now`** — now distinguishes "could not save" from "saved without
  a net".
- **`PetHistory.remember` / `load_records`** — `remember` reads, appends, sorts
  and writes; the write is now atomic, so an interrupted one keeps the previous
  record file.
- **`Settings._save`** — writes `settings.json` straight with no temp file
  either. Left alone deliberately: `Settings._ready` rewrites the whole file
  from the defaults merged with whatever parsed, so a mangled settings file
  self-heals on the next launch and costs the owner their preferences at worst,
  not their dog. Worth noting rather than fixing.
- **`Paths._prepare_saves_dir`** — the write probe that decides the folder is
  usable at all. Unrelated but adjacent; checked and correct.
