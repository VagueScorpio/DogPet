# RT-08: Replacing a pack merges into it instead of replacing it

Severity: Low
Location: `scripts/pack_transfer.gd:75-87`; `scripts/pack_archive.gd:105-148`

## The finding

`_do_import` backs the old folder up and then calls `extract` straight into the
same path. `extract` writes the zip's files over whatever is there and removes
nothing, so every file in the old pack that the new one does not happen to
overwrite survives. The dialog says "then replaced"; the behaviour is a merge.

Reproduced by exporting `pug_pixel`, deleting `walk.png` from the zip,
re-importing over the existing folder, and finding `walk.png` still there.

## What needs to be fixed

"Replace" should replace. The backup in `assets/_backup/` already works and is
what makes this safe to do.

## How it should be fixed, and why that way

In `_do_import`, once `_back_up` has **confirmed** success, empty the target
folder before extracting into it. The ordering is the whole point: the delete
only happens after a verified copy exists, which is the same reasoning as RT-06
— nothing good is destroyed before its replacement is safe.

The recursive delete mirrors `_copy_tree`, which is already there and already
walks a tree correctly, so the two can be read side by side.

Where there is no existing folder, nothing changes.

Verification plan: import a pack over an existing one that has a file the new
one lacks, and confirm the stale file is gone and the backup holds it.

---

## What was fixed

`scripts/pack_archive.gd`, `scripts/pack_transfer.gd`, `tests/test_packs.gd`.

### Where the delete ended up, and why it moved

The plan put `_empty_folder` on `PackTransfer`. That makes it untestable, for
the third time in this engagement: `PackTransfer` is a `Node` that names `Log`,
`Paths` and `AssetLibrary`, so it cannot be loaded in a `--script` run at all.

Emptying a folder is pure filesystem work with no autoloads in it, so it went
to `PackArchive` as `empty_folder()` — beside `extract`, `is_safe_entry` and the
rest of the file-level pack operations, where it can be driven directly by the
tests. `PackTransfer` keeps the part that is genuinely its own: deciding *when*
it is safe to call.

### Added — `PackArchive.empty_folder`, and the call that uses it

```gdscript
func _do_import(zip_path: String, found: Dictionary, target: String, id: String) -> void:
	if DirAccess.dir_exists_absolute(target):
		if not _back_up(target, id):
			finished.emit("Could not back up the existing \"%s\", so nothing was changed." % id)
			return
		# Replace means replace. Writing the new pack over the old one left
		# behind every file the new one did not happen to overwrite - a pet.json
		# that no longer lists a walk strip, with the old walk.png still beside
		# it. Only ever after _back_up has said yes: the copy in
		# assets/_backup is what makes emptying this safe.
		PackArchive.empty_folder(target)
```

## Test result after the fix

`tests/test_packs.gd` gained 8 checks:

```
  PASS  the stale files are there to begin with
  PASS  the folder itself survives
  PASS  the stale file is gone
  PASS  so is the stale manifest
  PASS  and a nested stale folder with it
  PASS  the replacing pack landed
  PASS  and it loads
  PASS  emptying a folder that is not there is harmless
```

The last one matters because `_do_import` reaches it on paths that may not
exist yet.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`PackArchive.empty_folder`** (new) — the delete, pure and testable.
- **`PackTransfer._do_import`** — decides when it is safe to call it.
- **`PackTransfer._back_up` / `_copy_tree`** — unchanged, and now load-bearing:
  the delete depends on the backup having worked.
- **`PackTransfer._confirm`** — the dialog already said "copied into
  assets/_backup first, then replaced", which is now true.
- **`PackArchive.extract`** — unchanged. It writes files; deciding what should
  already be in the folder is the caller's business.
- **`AssetLibrary.reload`** — called after an import, so the rescan sees the
  replaced folder rather than a mixture.
