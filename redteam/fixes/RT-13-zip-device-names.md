# RT-13: Windows device names pass the zip-entry check

Severity: Info
Location: `scripts/pack_archive.gd:189-201`

## The finding

`is_safe_entry` correctly refuses `..`, absolute paths and drive letters — I
tried `..\escape.txt`, `a./../b` and `C:/absolute.txt` and all three were
rejected, which is better than most zip handling. It does not refuse Windows
device names:

```
is_safe_entry(CON)      = true
is_safe_entry(sub/NUL)  = true
is_safe_entry(COM1.png) = true
```

Win32 resolves these to devices rather than files whatever directory prefix and
extension they carry, so `assets/pets/x/CON` is the console, not a file.

This was reported **Unconfirmed**, and honestly so: `FileAccess.open` on such a
path should simply fail, and `extract` handles a null handle properly — it
records "could not write" and carries on. I could not make it misbehave. The
one case I could not rule out is a machine with a real `COM1`, where opening a
serial port can block.

## What needs to be fixed

Nothing is known to be broken. This is tidying a gap in a check that is
otherwise careful, so that the one unproven case cannot arise at all.

## How it should be fixed, and why that way

A refusal list in `is_safe_entry`, beside the `..` check already there, matched
on the part of the name before the first dot and case-insensitively — because
`COM1.png`, `com1` and `CON.txt` all resolve to the device.

Cheap, local, and it means `extract` never asks Windows to open one. The
alternative — leaving it and relying on `FileAccess.open` failing — is probably
fine, which is exactly the sort of "probably" worth spending five lines to
remove.

Verification plan: extend the existing zip-slip cases in `test_packs.gd`, which
is where every other `is_safe_entry` rule is already checked.

---

## What was fixed

`scripts/pack_archive.gd`, `tests/test_packs.gd`.

### Added — the device names, and the check

```gdscript
## Names Windows resolves to devices rather than to files, whatever folder
## they sit in and whatever extension they carry: assets/pets/x/CON is the
## console. Nothing is known to go wrong - FileAccess.open on one of these
## fails and extract handles that - but a serial port can block when opened,
## and that is a "probably fine" worth five lines to be rid of.
const DEVICE_NAMES: PackedStringArray = [
	"CON", "PRN", "AUX", "NUL",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
]
```

and in `is_safe_entry`, inside the loop that already walks the parts:

```gdscript
	for part in name.split("/"):
		if part == "..":
			return false
		# Matched before the first dot and without case: COM1.png, com1 and
		# CON.txt are all the device.
		if DEVICE_NAMES.has(part.get_slice(".", 0).to_upper()):
			return false
```

Putting it in the existing loop rather than adding a second pass keeps the one
place that decides what a safe entry is.

## Test result after the fix

`tests/test_packs.gd`'s zip-slip section gained 10 checks:

```
  PASS  refuses the device name CON
  PASS  refuses the device name sub/NUL
  PASS  refuses the device name COM1.png
  PASS  refuses the device name lpt3
  PASS  refuses the device name CON.txt
  PASS  refuses the device name pack/aux
  PASS  still allows console.png
  PASS  still allows aux_bits/idle.png
  PASS  still allows nullify.png
  PASS  still allows common/pet.json
```

The last four matter as much as the first six: `console.png`, `aux_bits/`,
`nullify.png` and `common/pet.json` are ordinary names that a careless prefix
match would have refused.

Every existing zip-slip and round-trip check still passes, and the three
shipped packs still export and re-import — none of them contains a file named
anything like a device.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`PackArchive.is_safe_entry`** — the fixed code. Called by both `inspect`
  and `extract`, so one change covers the import path end to end.
- **`PackArchive.extract`** — unchanged; it already refused anything
  `is_safe_entry` rejected and recorded it as a problem.
- **`PackArchive._clean_id`** — the related guard on the *folder* a pack is
  unpacked into, which restricts it to `[a-z0-9_-]` and so already cannot
  produce a device name. Checked.
- **`PackArchive.write_pack`** — exporting reads the owner's own folders, where
  a file named `CON` cannot exist in the first place.
