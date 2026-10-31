# RT-03: Import pack — unbounded decompression (zip bomb)

Severity: High
Location: `scripts/pack_archive.gd:68` (`inspect`) and `:144` (`extract`)

## The finding

`inspect` reads the manifest with no size check at all:

```gdscript
var text: String = reader.read_file(manifest).get_string_from_utf8()
```

`extract:144` does the same, per entry, for every file in the pack. Nothing
checks the declared uncompressed size, the total, or the entry count.

Proven with `redteam/tests/probe_g_zipbomb.gd`: a **597 KB** zip holding a
`pet.json` of 600 MB of spaces followed by a valid manifest took peak memory to
**3,024 MB** and froze for 4.4 seconds — and `inspect` accepted the pack, since
the JSON parser skips the padding. 1029× amplification. Scale the padding to
4 GB (the zip stays about 4 MB) and it is an out-of-memory crash, triggered the
moment the file is chosen in the dialog, before the "Replace?" confirmation.

## What needs to be fixed

An entry's size has to be known *before* it is read, and an implausible one
refused. After the read the allocation has already happened, so a check there
is worth nothing.

## How it should be fixed, and why that way

### First, what the engine actually gives us

`CLAUDE.md`'s note that "Godot 4.4+ exposes `ZIPReader.get_file_info()`" is
wrong for this build. Enumerated with `ClassDB` on 4.7.2
(`redteam/tests/probe_l_zipapi.gd`), `ZIPReader` offers only:

```
open(path)   close()   get_files()
read_file(path, case_sensitive)   file_exists(path, case_sensitive)
get_compression_level(path, case_sensitive)
```

No size, anywhere. So there is nothing to ask, and the size has to come out of
the zip file itself.

### Why reading the declared size is a real fix and not a guess

This looked at first like it could only ever be best-effort — a zip's declared
sizes are its own claims, and a lying zip could say 1 KB and hold a gigabyte.
It turns out not to matter here, because of how Godot reads an entry:
`ZIPReader::read_file` asks minizip for the entry's `uncompressed_size`,
`resize()`s the buffer to exactly that, and reads at most that many bytes.

So **the declared size is the allocation.** A zip that under-declares cannot
make Godot allocate more than it declared; it just gets truncated. Checking the
declaration therefore bounds the memory completely, which is what makes this
worth doing properly rather than approximately. The 600 MB declaration in the
probe is exactly where the 600 MB allocation came from.

### The change

1. **New `scripts/zip_sizes.gd`** (`class_name ZipSizes`): reads a zip's central
   directory with `FileAccess` and returns each entry's declared uncompressed
   size, without decompressing anything. Pure — no nodes, no autoloads — so it
   can be tested headlessly, following `ImageLimits`, `PackLinks` and the rest.

   It locates the End of Central Directory record by scanning back from the end
   of the file, then walks the central directory's fixed-layout records. Where
   it cannot be confident of a size it **refuses** rather than guessing:
   - no EOCD found, or a truncated or malformed record;
   - Zip64 in use, either in the EOCD or in a per-entry size of `0xFFFFFFFF`.

   Refusing Zip64 outright is deliberate. Zip64 exists for archives over 4 GB or
   with more than 65,535 entries, and a pet or a room is neither; implementing
   it would be a pile of parsing whose only purpose would be to let bigger
   things through the size check.

2. **Limits in `PackArchive`**, checked in `inspect` before the first
   `read_file`, and again per entry in `extract`:
   - `MAX_MANIFEST_BYTES` 256 KB — the shipped pug's `pet.json` is about 500
     bytes. This one also bounds the `get_string_from_utf8` that follows, since
     a String costs up to four bytes per byte of input.
   - `MAX_FILE_BYTES` 64 MB for any single file.
   - `MAX_TOTAL_BYTES` 256 MB for the pack as a whole.
   - `MAX_ENTRIES` 512.

   Hard-coded constants, not `settings.json`. Every other tuning number in this
   app lives in that file on purpose, and these deliberately do not: a limit the
   owner can edit is a limit an unpacked pack could edit, and it would stop
   being a limit.

Refusals go into `inspect`'s existing `problems` array with a plain reason, so
`PackTransfer` shows them to the owner with no change at all. `extract` skips an
oversized entry and records it, which is the shape it already uses for a file it
cannot write.

Verification plan: re-run `probe_g_zipbomb.gd` and confirm the bomb is refused
with memory flat; then export and re-import a real pack to confirm ordinary
packs are unaffected, which is the owner's own phase 5 test.

---

## What was fixed

`scripts/zip_sizes.gd` (new), `scripts/pack_archive.gd`, `tests/test_packs.gd`.

### Added — `scripts/zip_sizes.gd`

The central directory walk, with every field read at an explicit offset from
the record's start rather than by sequential reads, so a mistake in one field's
width cannot silently shift every field after it.

```gdscript
## Each entry's declared uncompressed size, read out of the zip's central
## directory without decompressing anything.
##
## Returns {"sizes": {name: bytes}, "total": int, "problem": String}. A
## non-empty "problem" means the zip could not be measured and should be
## refused rather than read: a size that cannot be trusted is the whole
## reason this exists.
static func read(zip_path: String) -> Dictionary
```

### Changed — `PackArchive.inspect`

The size check sits with the path check, before anything is read:

```gdscript
	# Every entry has to be safe before anything is unpacked anywhere.
	for entry in entries:
		if not is_safe_entry(entry):
			result["problems"].append("the zip contains an unsafe path: %s" % entry)
	# ... and small enough to read. A pack zip of a few hundred KB can declare
	# gigabytes, and ZIPReader.read_file allocates whatever it declares.
	_check_sizes(zip_path, entries, result["problems"])
	if not result["problems"].is_empty():
		reader.close()
		return result
```

and the manifest gets its own, tighter ceiling just before it is read.

### Changed — `PackArchive.extract`

Takes the measured sizes once, up front, and skips any entry that is over its
ceiling or that would push the pack over the total.

A manifest keeps its tighter 256 KB ceiling here too, which was not in the plan.
The tests caught it: a `pet.json` of 263 KB is well under the 64 MB per-file
limit, so `extract` wrote it to disk happily. That write is harmless in itself —
but `PetPack.load_from_dir` and `ScenePack.load_from_dir` then read that file
with `get_file_as_string` and parse it on **every** `AssetLibrary.reload()`, with
no limit of their own. So the ceiling belongs on the way in, where it can still
be refused:

```gdscript
		var ceiling: int = MAX_FILE_BYTES
		var file_name: String = entry.get_file()
		if file_name == PET_JSON or file_name == SCENE_JSON:
			ceiling = MAX_MANIFEST_BYTES
```

Worth noting what this does *not* cover: a file the owner drops into `assets/`
by hand is still read with no size limit. That is a different thing — `assets/`
is the owner's own folder and `CLAUDE.md` invites them to put what they like in
it — and it is the import path that takes files from strangers.

## Test result after the fix

`redteam/tests/probe_g_zipbomb.gd`, same 600 MB bomb:

```
zip on disk: 611682 bytes (597.3 KB)
index readable: true
declared size of pet.json: 629145673 bytes (600.0 MB)
inspect took ms: 1
memory held before inspect: 24 MB
memory held after inspect:  24 MB
inspect itself allocated:   1 KB
inspect accepted the pack: false
why: the pack unpacks to 600.0 MB, more than the 256.0 MB this app will read
amplification refused at: 1029x
extract problems: ["skipped pet.json: it is 600.0 MB, more than the 64.0 MB
                    this app will read"]
```

**1 KB allocated instead of roughly 3 GB, in 1 ms instead of 4,374 ms.** The
bomb is refused with a reason the owner can read, and `extract` refuses it
independently, in case anything ever reaches it without inspecting first.

The probe had to be corrected mid-verification. It first reported "peak: 624 MB"
and I nearly wrote that down as the fix's cost — but
`OS.get_static_memory_peak_usage()` is a high-water mark for the whole process,
and the probe itself had just built a 600 MB buffer in order to *write* the
bomb. It now reports the change in held memory across the `inspect` call, which
is the only figure that says anything about `inspect`.

It is the total that refuses this particular bomb rather than the manifest
ceiling, because 600 MB in one entry trips the 256 MB pack total first. Both
checks work; the total is simply the one that gets there first.

`tests/test_packs.gd` gained `_test_zip_sizes()` — **16 checks** covering a real
zip's declared sizes and total, an entry the index does not mention, an
over-large manifest refused by both `inspect` and `extract` with nothing
written, too many entries, a file that is not a zip, a zip cut in half, a
missing file, and the plain-English size wording. All pass.

Ordinary packs are unaffected. `redteam/tests/probe_m_real_pack.gd` exports and
re-imports all three shipped packs with the app's own writer and reader — the
owner's phase 5 test, headlessly:

```
pug_pixel   zip 5.2 KB    unpacks to 5.1 KB in 4 entries    accepted, reloads as sprite2d
pug_3d      zip 1.6 MB    unpacks to 1.6 MB in 3 entries    accepted, reloads as model3d
pawsome_3d  zip 38.4 KB   unpacks to 181.1 KB in 3 entries  accepted, reloads as model3d
```

The largest real pack is 1.6 MB against a 64 MB per-file ceiling, so the limits
sit a long way above anything genuine. `_test_round_trip` and `_test_inspect`
also still pass untouched.

Whole suite at the time: **686 checks, 0 failures** (test_packs 73 → 89). After
all nine remaining findings were fixed it stands at 760.

## How it relates to the rest of the app

- **`PackArchive.inspect` / `extract`** — the fixed code, and the only two
  callers of `ZIPReader.read_file` in the app.
- **`PackTransfer._on_import_chosen`** — already shows `problems[0]` to the
  owner, so it reports the refusal with no change.
- **`PackTransfer._do_import`** — unchanged. A refused zip never reaches it.
- **`ZipSizes`** (new) — pure and testable, in the same shape as `ImageLimits`,
  `PackLinks`, `NotificationRules` and `CareSettings`.
- **`ImageLimits`** — guards the same class of problem one step later, when a
  pack's PNG is decoded. The two are complementary: `ZipSizes` stops a huge file
  being read out of the zip at all, `ImageLimits` stops a file already on disk
  being decoded into too many pixels. RT-10 (the 32-bit truncation in
  `ImageLimits`) is still open and unrelated.
- **`PackArchive.write_pack`** — exporting is unaffected; it reads the owner's
  own folders.
