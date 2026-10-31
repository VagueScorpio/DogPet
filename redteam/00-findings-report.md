# Red Team Findings Report

Project: DogPet v1.21 (Godot 4.7.2, GDScript, Windows)
Date: 2026-10-31
Tester: Jack Sparrow, red team consultant (external)

Scope: every file under `scripts/` (43 scripts, ~3,900 lines) read line by line,
plus `project.godot`, `export_presets.cfg`, `tools/build.ps1`, the `tests/`
suites, and the JSON files under `assets/`. All testing was local, against the
owner's own code. Harnesses used are in `redteam/tests/`.

Baseline before I started: all eight existing suites pass — 637 checks, 0
failures (`test_needs` 157, `test_pets` 105, `test_scenes` 88, `test_life` 85,
`test_notify` 62, `test_packs` 56, `test_integration` 47, `test_history` 37).
None of them fail now; nothing below was found by breaking an existing test.

## Summary

Thirteen findings: **2 Critical, 2 High, 3 Medium, 5 Low, 1 Info.** Eleven are
confirmed with a working reproduction; one is reasoned from code with the
mechanism proven in a probe; one is unconfirmed.

> **Status, 2026-10-31. All thirteen findings are fixed**, in three passes at
> the owner's instruction: the Criticals, then the Highs, then the remaining
> nine. Every one has a fix document in `fixes/` written before its code was
> touched and updated after, and every probe that broke something has been
> re-run and no longer does.
>
> The suite stands at **760 checks / 0 failures**, up from 637, and the project
> opens with no script errors. 123 of the new checks are permanent regression
> guards across all eight suites.
>
> **RT-07's behaviour change was put to the owner and kept** (2026-10-31): after
> an absence longer than thirty days the dog survives to be looked at instead of
> being found dead. It is now written into `CLAUDE.md` §6.3 beside the original
> offline-starvation rule it qualifies, so the spec and the code agree.
> Nothing in this engagement is left open.
>
> See `99-master-report.md` for the whole engagement.

The arithmetic is in good shape. `NeedsModel`, `LifeModel`, `NeedsText` and
`PetHistory` are properly pure, properly tested, and I could not make them lie.
Zip-slip is correctly refused — I tried `..\`, `a./../b` and `C:/absolute.txt`
and all three were rejected. The atomic-save design is sound in intent. The
`--script` guards keep the tests off the real save folder. That is better
hygiene than most code I am handed.

The holes are all on the **trust boundaries**, and they share one root cause:
data read from disk — `pet.json`, `settings.json`, `ui.json`, and above all an
imported pack `.zip` — is treated as if the owner had typed it, when in fact a
pack is a file people are invited to download and share. Two of those paths
reach arbitrary code execution. `assets/` being loose and importable is the
app's best feature and its whole attack surface.

The two Criticals both need one thing from the owner — typing a name, or
clicking a licence link — and neither looks like a dangerous act.

## Findings

| ID | Severity | Title | File:Line | Status |
|---|---|---|---|---|
| RT-01 | Critical | PowerShell code execution via the pet name | scripts/notifier.gd:237 | **Fixed** |
| RT-02 | Critical | Arbitrary program launch from a pack's licence link | scripts/credits_list.gd:133 | **Fixed** |
| RT-03 | High | Import pack: unbounded decompression (zip bomb) | scripts/pack_archive.gd:68 | **Fixed** |
| RT-04 | High | `starve_grace_intervals` ≤ 0 kills the dog instantly, forever | scripts/life_model.gd:144 | **Fixed** |
| RT-05 | Medium | A room with tiny tiles freezes the window | scripts/scene_view.gd:155 | **Fixed** |
| RT-06 | Medium | The last good save is deleted before the new one lands | scripts/save_file.gd:41 | **Fixed** |
| RT-07 | Medium | No cap on catch-up: a clock jump kills the pet | scripts/needs.gd:90 | **Fixed** |
| RT-08 | Low | Replacing a pack merges into it instead of replacing it | scripts/pack_transfer.gd:80 | **Fixed** |
| RT-09 | Low | Infinities from a save file reach the screen | scripts/life_model.gd:240 | **Fixed** |
| RT-10 | Low | PNG size guard truncated to 32 bits, so it skips the worst files | scripts/image_limits.gd:63 | **Fixed** |
| RT-11 | Low | The log rotates only at startup | scripts/log.gd:37 | **Fixed** |
| RT-12 | Low | `saves/notify.vbs` is written then executed | scripts/notifier.gd:207 | **Fixed** |
| RT-13 | Info | Windows device names pass the zip-entry check | scripts/pack_archive.gd:189 | **Fixed** (was Unconfirmed) |

---

### RT-01: PowerShell code execution via the pet name

- Severity: **Critical**
- Location: `scripts/notifier.gd:237` (the here-string in `_toast_script`), with
  `_xml_escape` at `scripts/notifier.gd:249` and `_file_uri` at `:260`
- Category: injection (command / code execution)

**What's wrong**

`_toast_script` builds the PowerShell script as text and substitutes the title
into it with GDScript's `String.replace`:

```gdscript
return """...
$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml(@"
<toast>...<text>{TITLE}</text>...</toast>
"@)
...""".replace("{TITLE}", _xml_escape(title))
```

`@"` … `"@` is PowerShell's **expandable** here-string. Because the substitution
happens in GDScript, the pet's name is physically present in the script source
before PowerShell parses it — so `$(...)` inside the name is a subexpression
PowerShell evaluates and runs.

`_xml_escape` escapes `&`, `<`, `>`, `"` and `'`. It does not touch `$`. The
comment above it says "a dog could be called anything", which is exactly right;
the escaping just guards the wrong language. The base64 `-EncodedCommand` is
genuinely good protection for the *shell argument*, and it does nothing here,
because the injection is inside the script it carries.

The same line of reasoning applies to the icon: `_file_uri` only converts `\` to
`/` and spaces to `%20`, then drops the path into `src="file:///%s"`. A tray
icon filename from `assets/ui/ui.json` containing `$(...)` or a double quote
reaches PowerShell the same way.

**How to reproduce**

`redteam/tests/probe_d_injection.gd` builds the script exactly as `_toast_script`
does and runs it through `powershell.exe -EncodedCommand`, with a pet name of:

```
$(Set-Content -Path <user data folder>/rt_marker.txt -Value pwned-via-pet-name; Rex)
```

(No quotes in the payload, so `_xml_escape` has nothing to catch.)

```
godot --headless --path . --script res://redteam/tests/probe_d_injection.gd
```

**What happens**

The generated script contains the live subexpression:

```
<text>$(Set-Content -Path <user data folder>/rt_marker.txt -Value pwned-via-pet-name; Rex) is starving!</text>
```

PowerShell runs it. The probe reports:

```
--- marker exists: true ---
marker contents: pwned-via-pet-name
```

Arbitrary code ran, in a hidden window, with the owner's privileges, the next
time the dog got hungry while the window was minimised.

**Why it happens**

Two string worlds got crossed. The author correctly identified that the pet name
is untrusted and correctly escaped it for **XML**, then placed the result in a
position that is parsed by **PowerShell** first. Escaping is only ever safe
against the parser that actually sees the text, and here two parsers see it in
sequence: PowerShell's here-string expander, then `XmlDocument.LoadXml`.

**Who can set the name**

- The owner types it (Pet → Change Name, or Settings → Pet). Self-inflicted, but
  a name copied off a web page is a real way in.
- `pet_name` in `saves/pet.json` — `Needs._ready:87` reads it with `str()` and no
  filtering. A save file passed between people carries it.
- The icon path variant comes from an **imported pack's** `ui.json`, which is
  squarely untrusted.

**Recommended fix**

Stop interpolating into the script at all. Pass the title, body and icon path to
PowerShell as **data**, not as source:

1. Keep a single-quoted (literal) here-string `@'` … `'@`, which PowerShell does
   not expand, and build the XML inside PowerShell from `$env:` variables set by
   `OS.create_process`'s environment; or
2. simpler and belt-and-braces: base64 the three values separately in GDScript
   and have the script `[Convert]::FromBase64String(...)` them, so no attacker
   byte is ever part of the script text.

Either way, also add `$` to `_xml_escape`'s refusal list as defence in depth, and
reject a pet name containing `$`, backtick or a newline at the point it is set
(`Needs.set_pet_name`), so a hostile name cannot be stored in the first place.

**Related code affected**

`Notifier.send_toast`, `_launch_via_powershell`, `_launch_via_wscript` (same
script text), `Needs.set_pet_name`, `Needs.start_new_pet`, `UiPack.tray_icon_path`.
`Tray.hide_to_tray:107` also sends the pet name through `send_toast`.

---

### RT-02: Arbitrary program launch from a pack's licence link

- Severity: **Critical**
- Location: `scripts/credits_list.gd:133`
- Category: injection / unvalidated URI handling

**What's wrong**

```gdscript
static func _link(text: String, url: String) -> LinkButton:
	...
	button.pressed.connect(func() -> void: OS.shell_open(url))
```

`url` is `license_url` or `source_url` straight out of a pack's `pet.json` or
`scene.json`. Nothing between the file and `ShellExecuteW` checks the scheme —
`PetPack.from_dictionary:86-87` and `ScenePack.from_dictionary:89-90` just
`str().strip_edges()` them. `OS.shell_open` on Windows is `ShellExecuteW`, which
will open a document, launch an executable, resolve a bare command name off the
`PATH`, or hand the string to any registered protocol handler.

The button's visible text is the **licence name** ("CC-BY 3.0"), so a malicious
pack shows a perfectly ordinary-looking licence link. The real target appears
only in the tooltip, on hover.

**How to reproduce**

`redteam/tests/probe_e_shell_open.gd` builds a `PetPack` from a dictionary whose
`license_url` is a path to a `.cmd` file, confirms the value survives parsing
untouched, and then calls `OS.shell_open` on it exactly as `_link` does:

```
godot --headless --path . --script res://redteam/tests/probe_e_shell_open.gd
```

**What happens**

```
license_url kept verbatim: .../rt_shell_probe/rt_payload.cmd
any scheme check in the pack? true
calling OS.shell_open on it, exactly as the link does...
=== MARKER ===
launched-by-shell_open-from-pack-json
```

The payload ran. In the real app the sequence is: import a pack someone sent you
→ open Settings → About → click the licence link beside its credit.

Worse variants need no file on disk: `calc.exe` (resolved off the `PATH`),
`\\attacker\share\payload.exe` (an executable fetched from a remote SMB share),
or any `ms-*:` protocol handler.

**Why it happens**

`license_url` and `source_url` are described in `CLAUDE.md` §5.1 as URLs, and the
code trusts that description. There is no validation layer between a pack's JSON
and the OS — and the credits block is, by design, the one place that *must* show
whatever an untrusted pack says, because showing it is a licence obligation.

**Recommended fix**

In `CreditsList`, make a link only for a value that starts with `http://` or
`https://` after trimming; show anything else as plain, unclickable text. Best
done as a single `static func safe_url(raw: String) -> String` in `CreditsList`
(returning `""` when it is not an http(s) URL), used by both `license_url` and
`source_url`, so the rule lives in one place. Validating in `PetPack` /
`ScenePack` as well would let the pack loader log the refusal, which is worth
having — but the guard belongs at the `shell_open` call whatever else is done.

**Related code affected**

`CreditsList._entry_block` (both link branches), `SettingsPanel._build_about`,
`PetPack.license_url` / `source_url`, `ScenePack.license_url` / `source_url`.
`Paths.open_in_file_manager:104` also calls `shell_open`, but only ever on
`Paths.assets_dir` or `Paths.saves_dir`, which the app controls — that one is fine.

---

### RT-03: Import pack — unbounded decompression (zip bomb)

- Severity: **High**
- Location: `scripts/pack_archive.gd:68` (`inspect`) and `:144` (`extract`)
- Category: resource exhaustion

**What's wrong**

`inspect` reads the manifest with no size check at all:

```gdscript
var text: String = reader.read_file(manifest).get_string_from_utf8()
```

`ZIPReader.read_file` decompresses the whole entry into a `PackedByteArray`, and
`get_string_from_utf8` then builds a `String` from it. `extract:144` has the same
shape, per entry, for every file in the pack. Nothing checks the declared
uncompressed size, the total, or the entry count.

This is the one place `ImageLimits` was written to defend — its own doc comment
says "a 200-megapixel sprite sheet can zip down to a couple of megabytes" — but
`ImageLimits` guards `PetLoader.load_texture`, which runs *after* `extract` has
already written the file out, and never guards the manifest at all.

**How to reproduce**

`redteam/tests/probe_g_zipbomb.gd` packs a `pet.json` consisting of 600 MB of
spaces followed by a valid manifest (the JSON parser skips the padding, so the
pack is accepted), then calls `PackArchive.inspect` on it:

```
godot --headless --path . --script res://redteam/tests/probe_g_zipbomb.gd
```

**What happens**

```
zip on disk: 611682 bytes (597.3 KB)
inspect took ms: 4374
memory before: 24 MB   peak: 3024 MB
inspect accepted the pack: true  id: bomb
amplification: 1029x
```

A **597 KB** file took peak memory to **3,024 MB** and froze the app for 4.4
seconds — and `inspect` happily accepted the pack. Scale the padding to 4 GB (the
zip stays about 4 MB) and it is an out-of-memory crash on any normal machine,
before the owner has agreed to anything: `inspect` runs the moment the file is
chosen in the dialog, before the "Replace?" confirmation.

**Why it happens**

The zip-slip defence was thought through carefully — entry *names* are checked
before anything is unpacked. Entry *sizes* were not, and a zip's danger is
equally in how much it claims to contain. `ZIPReader` offers no streaming read,
so "read the whole entry" is the only shape the API suggests.

**Recommended fix**

Add two constants and one check to `PackArchive`:

- `MAX_ENTRY_BYTES` (1 MB is generous for a `pet.json`; 64 MB for art), and
- `MAX_TOTAL_BYTES` / `MAX_ENTRIES` for the pack as a whole.

Check them in `inspect` **before the first `read_file`**, from
`ZIPReader.get_files()` plus the per-entry size (Godot 4.4+ exposes
`ZIPReader.get_file_info()`; if that is unavailable, read in bounded chunks and
abort past the limit). Add each refusal to `problems` with a plain reason, which
is the shape `inspect` already uses, so `PackTransfer` will show it without
changes. `extract` needs the same ceiling per entry.

**Related code affected**

`PackArchive.inspect`, `PackArchive.extract`, `PackTransfer._on_import_chosen`,
`PackTransfer._do_import`. `tests/test_packs.gd` is the right place for the new
cases.

---

### RT-04: `starve_grace_intervals` ≤ 0 kills the dog instantly, forever

- Severity: **High**
- Location: `scripts/life_model.gd:143-148`; missing floor in
  `scripts/care_settings.gd:82-93`
- Category: logic / unvalidated configuration

**What's wrong**

```gdscript
var grace: float = hunger_interval * _number(config, "starve_grace_intervals", 1.0)
if starving_seconds >= grace:
	_die(Cause.STARVATION, now_unix)
```

When `grace` is `0.0`, `starving_seconds` is also `0.0` — because the line above
resets it to zero for a dog that is *not* hungry — and `0.0 >= 0.0` is true. A
perfectly fed dog dies of starvation on the first processed frame.

`settings.json` is explicitly designed to be hand-edited: `CLAUDE.md` §6.2 says
the numbers live there "so they can be tuned without code changes", and
`CareSettings` already floors the two tunables where a zero would misbehave
(`MIN_REMINDER_SECONDS`, `MIN_ACTION_SECONDS`, with a good comment explaining
why). The `real_play` block has no floors, and `Settings.real_play():92` hands
the dictionary to `LifeModel` verbatim. `CareSettings.merge_into` accepts `0.0`
without comment, because the type matches.

**How to reproduce**

`redteam/tests/probe_c_numbers.gd`, section "a zero starve grace":

```
godot --headless --path . --script res://redteam/tests/probe_c_numbers.gd
```

Or by hand: set `"starve_grace_intervals": 0` in `saves/settings.json`, switch
to Real Pet play, and feed the dog.

**What happens**

```
not hungry at all, grace 0 -> died: true alive: false
negative grace -> died: true
```

And it does not stop. Start a new dog from the death card and `life.reset()`
zeroes `starving_seconds` again, so the next frame kills that one too — a fresh
record appended to `history.json` each time. Real play becomes unplayable with
no indication why, and the scoreboard fills with one-frame dogs.

**Why it happens**

The guard clause at `:124` rejects `seconds <= 0.0` and `hunger_interval <= 0.0`
but not a nonsensical grace. The comparison is also `>=` where the quantities can
both legitimately be zero, which is the classic boundary slip.

**Recommended fix**

Floor the `real_play` numbers the way the other tunables are floored. Add to
`CareSettings`:

```gdscript
## A grace of zero means the dog dies with a full bowl, on the first frame.
const MIN_STARVE_GRACE_INTERVALS := 0.1
const MIN_SICKNESS_RISE_INTERVALS := 0.1
```

and a `static func real_play_from(data: Dictionary) -> Dictionary` that clamps
them, called by `Settings.real_play()` so every reader gets the clamped version.
Separately, in `LifeModel.advance`, return early when `grace <= 0.0` rather than
treating it as "die now" — a model that cannot be told to kill the dog by
accident is worth having regardless of what the settings layer does.

**Related code affected**

`LifeModel.advance`, `LifeModel.seconds_to_fatal` (already guards `to_fatal <= 0.0`
correctly — copy that shape), `Settings.real_play`, `Settings.starve_grace_seconds`,
`LifeModel.starving_fraction` (guards `grace_seconds <= 0.0` correctly too).
`tests/test_life.gd` should gain the zero and negative cases.

---

### RT-05: A room with tiny tiles freezes the window

- Severity: **Medium**
- Location: `scripts/scene_view.gd:146-177`; `scripts/scene_pack.gd:198`
- Category: resource exhaustion / unvalidated configuration

**What's wrong**

`_draw_tiled_background` steps by the tile's own drawn size:

```gdscript
var tile: Vector2 = wall.get_size() * tile_scale
...
while x < size.x:
	draw_texture_rect(wall, Rect2(Vector2(x, y), tile), false)
	x += tile.x
```

`tile_scale` is floored at 1 (`scene_pack.gd:198`, `maxi(1, ...)`) but nothing
relates it to how big the tile actually is. A 1×1-pixel `wall.png` means one
`draw_texture_rect` per screen pixel, recomputed every frame.

**How to reproduce**

`redteam/tests/probe_h_tiles.gd` reproduces the two loops exactly and counts the
calls:

```
godot --headless --path . --script res://redteam/tests/probe_h_tiles.gd
```

Or by hand: a room folder with a 1×1 PNG and
`"background": {"type":"tiled","wall":"1px.png","floor":"1px.png","tile_scale":1}`.

**What happens**

```
default 540x760 window, 32x32 tile at scale 1: 425 draw calls per frame
default 540x760 window, 4x4 tile at scale 1: 25785 draw calls per frame
default 540x760 window, 1x1 tile at scale 1: 410940 draw calls per frame
maximised 2560x1440 window, 1x1 tile at scale 1: 3688960 draw calls per frame
```

3.7 million draw calls a frame is a hard freeze. The owner cannot reach Settings
to pick a different room, because the window has stopped responding. The room is
also *remembered* in `settings.json` under `rooms`, so restarting lands straight
back in it.

**Why it happens**

`ImageLimits` guards the top of the size range and nothing guards the bottom.
A pixel-art app reasonably expects small tiles, and "small" has no floor.

**Recommended fix**

In `ScenePack._read_tiled_background`, compute the effective tile size from the
image header (`ImageLimits.png_size_from_header`, already available and already
used nearby) and raise `tile_scale` until the drawn tile is at least, say, 8
pixels on both axes — or add the tile to `problems` and fall back to a generated
background, which is the behaviour the loader already uses for a missing tile.
A hard ceiling on iterations in `_draw_tiled_background` is worth adding too, as
the backstop for an image format whose header is not read.

**Related code affected**

`SceneView._draw_tiled_background`, `ScenePack._read_tiled_background`,
`ScenePack._fall_back_background`. The `scenes/home` and `scenes/eat` packs that
ship use 32×32 tiles and are unaffected.

---

### RT-06: The last good save is deleted before the new one lands

- Severity: **Medium**
- Location: `scripts/save_file.gd:36-44`
- Category: error handling / data loss

**What's wrong**

```gdscript
if FileAccess.file_exists(path):
	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(bak_path)
	if DirAccess.rename_absolute(path, bak_path) != OK:
		# No backup this time, but a good save still beats a stale one.
		DirAccess.remove_absolute(path)
```

Three problems in five lines:

1. The old backup is removed **before** anyone knows the new one can be made.
2. When the rename fails, the only remaining good save is deleted, and the
   return value of that deletion is ignored.
3. The function still returns `true` if the final rename works, so the app never
   learns it is now running with no fallback.

On Windows a rename fails routinely when something holds a handle — antivirus
mid-scan, OneDrive or Dropbox syncing the folder, a backup agent, Explorer's
preview pane — or when the `.bak` has picked up a read-only flag.

**How to reproduce**

`redteam/tests/probe_f_save.gd` makes `pet.json.bak` unrenameable-over (a
non-empty directory, which stands in for a locked or read-only file), saves
again, then corrupts `pet.json`:

```
godot --headless --path . --script res://redteam/tests/probe_f_save.gd
```

**What happens**

```
with pet.json.bak unusable:
  third save reports: true
  pet.json now holds: Pickle
  a usable backup exists: false
  after pet.json is corrupted, recovery source: none
  recovered dog: <THE DOG IS GONE>
```

The save reports success. The backup is gone. From then on *every* save deletes
the previous good file, so the fallback never comes back — and the first
interrupted write or corrupted sector loses the dog, which is precisely the case
`SaveFile` exists to survive. `Needs._ready:76-85` has correct recovery code that
now has nothing to recover from.

**Why it happens**

The order is ordered for the happy path. The safe order is "write the new file,
then move the old one aside, then put the new one in place" — never "destroy
what you have, then hope". The comment on the failure branch ("a good save still
beats a stale one") is reasoning about freshness when the question is survival.

**Recommended fix**

Reorder and report:

1. Write `pet.json.tmp` (unchanged).
2. Copy — do not move — the current `pet.json` to `pet.json.bak2`, then rename
   `bak2` over `bak` only once the copy succeeded. If the copy fails, keep the
   existing `.bak` and carry on; a slightly stale backup is worth far more than
   none.
3. Rename `tmp` over `path`. If `path` cannot be replaced, leave it alone and
   return `false` — do not delete it.
4. Return `false` whenever no backup could be maintained, and have `Needs.save_now`
   log it, so a save folder that has quietly stopped working says so.

**Related code affected**

`SaveFile.write_atomic`, `SaveFile.read_with_fallback`, `Needs.save_now:367`,
`PetHistory.save_records:54` (which has no atomic write or backup at all — the
history file is rewritten in place on every death, so a crash mid-write loses
every remembered dog; worth the same treatment). `tests/test_needs.gd` covers
the corrupt-save fallback and should gain the unusable-backup case.

---

### RT-07: No cap on catch-up, so a clock jump kills the pet

- Severity: **Medium**
- Location: `scripts/needs.gd:90-104`; `scripts/needs_model.gd:160-170`
- Category: logic / input validation

**What's wrong**

`elapsed_between` guards one direction only:

```gdscript
static func elapsed_between(then_unix: float, now_unix: float) -> float:
	return maxf(now_unix - then_unix, 0.0)
```

The comment names the right hazards — daylight saving, a corrected system time,
a dead CMOS battery — and then handles only the backwards case. A clock that
jumps **forward** produces an arbitrarily large `elapsed`, which flows into
`model.catch_up` and `_catch_up_life` with no ceiling. In Real play the starving
clock then runs for that whole stretch and the dog dies before the window opens.

A dead CMOS battery usually reads 2099 or similar, not 1970 — so the forward jump
is the *more* likely of the two faults, and it is the one that is not handled.

**How to reproduce**

The mechanism is in `redteam/tests/probe_c_numbers.gd` ("NeedsModel with an
infinite elapsed" and the grace sections). By hand: set the Windows clock a year
forward, open DogPet in Real play with a save from today.

**What happens**

Every bar maxes out, and in Real play `_catch_up_life:200-209` credits the dog
with a year of starvation — far past any grace period — so it dies during the
catch-up, before any scene exists. `Main._ready:69` then shows the death card, as
designed. Casual play merely maxes the bars, which the owner can fix; Real play
is irreversible, and the dog died because of a clock, not neglect.

The same path also produces `NaN` internally: with an infinite `elapsed`,
`_catch_up_life` computes `well_fed_for = elapsed - starving_for` = `inf - inf` =
`NaN`, and `NaN > 0.0` is false, so the well-fed leg of the absence is silently
skipped. Confirmed in the probe (`is_nan: true`). It does not change the outcome
today, but it is a wrong number flowing through the most consequential code in
the app.

**Why it happens**

`last_saved_unix` is the only record of when the app was last open, so a clock
jump and a real absence are indistinguishable from inside. That is unavoidable —
but an absence of 400 days is overwhelmingly more likely to be a broken clock
than a real one, and the app need not treat the two the same.

**Recommended fix**

Cap the catch-up in `Needs._ready`:

```gdscript
## Longer than this and a broken clock is likelier than a real absence.
const MAX_CATCH_UP_SECONDS := 60.0 * 60.0 * 24.0 * 30.0
```

Clamp `elapsed` to it, and when the clamp bites, log it and say so on the "While
you were away" card — the card already exists and is exactly the right place to
tell the owner the time away looked wrong. Thirty days still maxes every bar and
still starves a dog in Real play, so nothing about the intended design changes;
it only stops a clock fault from being unbounded. Separately, make
`_catch_up_life` reject a non-finite `elapsed` outright (`is_finite`), so the
`NaN` cannot arise.

**Related code affected**

`Needs._ready`, `Needs._catch_up_life`, `NeedsModel.catch_up`,
`NeedsModel.elapsed_between`, `NeedsModel.seconds_at_critical`,
`AwayCard.show_summary`. `tests/test_needs.gd` covers 0 s, 1 h, 3 days and a
negative elapsed — the cap wants a case of its own.

---

### RT-08: Replacing a pack merges into it instead of replacing it

- Severity: **Low**
- Location: `scripts/pack_transfer.gd:75-87`; `scripts/pack_archive.gd:105-148`
- Category: logic

**What's wrong**

`_do_import` backs the old folder up and then calls `extract` straight into the
same path. `extract` writes the zip's files over whatever is there and removes
nothing, so every file in the old pack that the new one does not happen to
overwrite survives. The dialog says "then replaced"; the behaviour is a merge.

**How to reproduce**

Export `pug_pixel`, delete `walk.png` from the zip, re-import over the existing
folder, and look in `assets/pets/pug_pixel/`: `walk.png` is still there.

**What happens**

The new pack inherits stray art from the old one. Harmless most of the time, and
confusing exactly when it matters: a `pet.json` that no longer lists `walk` leaves
an orphan file; two packs sharing an id leave a folder that is neither. The
backup in `assets/_backup/` is correct and does its job, so nothing is lost.

**Why it happens**

"Replace" was implemented as "write over", which is the same thing only when the
new file list is a superset of the old.

**Recommended fix**

After a successful `_back_up`, delete the target folder's contents before calling
`extract` — a small recursive remove alongside the existing `_copy_tree`, which
already walks a tree correctly and can be mirrored. Do it only once the backup
has been confirmed, which `_do_import:76` already checks.

**Related code affected**

`PackTransfer._do_import`, `PackTransfer._back_up`, `PackArchive.extract`.

---

### RT-09: Infinities from a save file reach the screen

- Severity: **Low**
- Location: `scripts/life_model.gd:239-248`, `:67-74`;
  `scripts/needs_text.gd:59-71`; `scripts/pet_history.gd:82-94`
- Category: input validation

**What's wrong**

`LifeModel.from_dictionary` floors and clamps some fields and not others:
`age_days` gets `maxf(0.0, ...)`, `sickness` gets a proper `clampf`, but
`born_unix` and `died_unix` are taken as-is, and no field is checked for being
finite. JSON can express an infinity in practice — Godot's parser turns `1e999`
into `inf` (with a warning) and `JSON.stringify` writes `inf` back out as
`1e99999`, so once an infinity is in the save it round-trips and stays.

`Settings` has the same gap: a hand-edited interval of `1e999` passes
`merge_into`'s type check, and `seconds_to_critical` then divides by zero.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_i_misc.gd
godot --headless --path . --script res://redteam/tests/probe_c_numbers.gd
```

**What happens**

```
format_age(INF)              = -9223372036854775808 days old
format_countdown(INF)        = ~-9223372036854775808m
format_date(1e999)           = 27 Jan -292277022657, 08:29
describe(hostile record)     = A, -9223372036854775808 days old, died of unknown
```

`int(floor(inf))` is undefined and lands on `INT64_MIN`. Nothing crashes and no
state is harmed, but the scoreboard — the memorial feature — prints nonsense, and
it is the kind of nonsense that makes an owner think the app has lost their dog.

**Why it happens**

Partial validation. The author clearly thought about bad input (`_number` checks
the type, `age_days` is floored, `sickness` is clamped) and the one property that
was not considered is finiteness, which is the one JSON can smuggle through.

**Recommended fix**

Add a finite check to the single funnel that already exists:

```gdscript
static func _number(source: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = source.get(key, fallback)
	if (raw is float or raw is int) and is_finite(float(raw)):
		return float(raw)
	return fallback
```

Do the same in `NeedsModel.from_dictionary:244-251` (where `clampf` happens to
absorb an infinity, but only by luck) and in `CareSettings.merge_into:177` for
the float branch. Then make `format_age`, `format_countdown`, `format_duration`
and `format_date` defend their own output with `is_finite` and a plain "unknown",
since they are the last stop before the screen.

**Related code affected**

`LifeModel.from_dictionary`, `NeedsModel.from_dictionary`,
`CareSettings.merge_into`, `NeedsText.format_countdown` / `format_duration`,
`LifeModel.format_age` / `stage_for`, `PetHistory.format_date` /
`format_lifespan` / `describe`, `Scoreboard._past_entry`, `DeathCard.show_death`.

---

### RT-10: PNG size guard truncated to 32 bits, so it skips the worst files

- Severity: **Low**
- Location: `scripts/image_limits.gd:50-63` and `:37-40`
- Category: logic / integer truncation

**What's wrong**

`png_size_from_header` reads the two big-endian 32-bit header fields correctly as
64-bit GDScript integers, then packs them into a `Vector2i` — whose components
are **32-bit**. A declared width of `4294967295` becomes `-1`. `is_too_large`
then takes `size.x <= 0` to mean "not known", which it documents as never too
large, and the file is handed to the decoder — the exact outcome the guard was
written to prevent.

**How to reproduce**

```
godot --headless --path . --script res://redteam/tests/probe_c_numbers.gd
```

**What happens**

```
4294967295 x 4294967295 product = 1
is_too_large says: false
```

In practice Godot's PNG decoder refuses such dimensions, so the file fails to
load and the app carries on — which is why this is Low rather than High. But the
cheap pre-decode guard is silently inoperative for the extreme case, leaving only
the post-decode check at `PetLoader.load_texture:161`, and that one has already
paid the allocation. `PetPack._png_size:289-298` has the same truncation, plus it
checks neither the PNG signature nor `ImageLimits`.

**Why it happens**

`Vector2i` looks like a 64-bit pair in GDScript, where every `int` is 64-bit, and
is not. The "unknown means not too large" rule is a reasonable choice that
becomes a hole once a real size can masquerade as unknown.

**Recommended fix**

Return the two dimensions as plain 64-bit integers — a small `Dictionary` or a
`Vector2i` only after refusing anything above `Image.MAX_WIDTH` / `MAX_HEIGHT`:

```gdscript
var w: int = _big_endian_u32(header, 16)
var h: int = _big_endian_u32(header, 20)
if w <= 0 or h <= 0 or w > MAX_SIDE or h > MAX_SIDE:
	return Vector2i(-1, -1)   # refuse, not "unknown"
```

and give `is_too_large` a third answer for "refused" rather than folding it into
"unknown". While there: delete `PetPack._png_size` and have `_read_one_sprite_animation`
call `ImageLimits.png_size_from_header`, so there is one header reader with one
set of checks.

**Related code affected**

`ImageLimits.png_size_from_header`, `ImageLimits.is_too_large`,
`PetLoader.load_texture`, `PetPack._png_size`, `PetPack._read_one_sprite_animation`,
`SceneView._load`.

---

### RT-11: The log rotates only at startup

- Severity: **Low**
- Location: `scripts/log.gd:36-38` and `:94-107`
- Category: resource growth

**What's wrong**

`_rotate_if_large` is called once, from `_ready`. `_write` never checks the size
again. The whole point of DogPet is that it is left running in the tray for days,
and `MAX_BYTES` is 1 MB — a ceiling that is only ever enforced at launch.

**What happens**

With Demo Speed on and a critical need, the reminder path logs steadily; at a
nag a minute plus the autosave traffic the file passes 1 MB in a few hours and
then grows without limit until the app is restarted. Nothing breaks — every write
is an open, append, close — but a tray app left for a fortnight can leave a
log of hundreds of megabytes in the owner's `saves/` folder.

**Recommended fix**

Keep a running byte count in `_write` (add the line's length as it goes, which
costs nothing) and call `_rotate_if_large` when it passes `MAX_BYTES`, resetting
the count on rotation. Keeping one `.old` generation, as it does now, is right.

**Related code affected**

`Log._write`, `Log._rotate_if_large`, `Log._open_for_append`.

---

### RT-12: `saves/notify.vbs` is written then executed

- Severity: **Low** (the route is off by default)
- Location: `scripts/notifier.gd:206-221`
- Category: platform / local code execution

**What's wrong**

When `notification_launcher` is `"wscript"`, every notification writes
`saves/notify.vbs` and then runs it with `wscript.exe`. The base64 payload itself
is safe — base64's alphabet cannot break out of the VBScript string literal, and
I checked that — but the *file* is a script in a predictable path inside a folder
whose permissions depend on where the owner unzipped the app.

**What happens**

Anyone who can write to `saves/` can replace `notify.vbs` between the `close()`
at `:219` and the `create_process` at `:220`, or simply leave a hostile copy in
place for the next notification, and have it run as the owner. On a single-user
machine that is nothing — they could run anything anyway. It matters where DogPet
is unzipped somewhere several accounts can reach: a shared folder, a
`C:\Tools\DogPet` created by an admin and left writable by `Users`, a USB stick.

`CLAUDE.md` §7.3 asks for this route as the fallback if a console window ever
flashes, so it is meant to be reachable. It is off by default
(`notification_launcher` is `"powershell"`), which is why this is Low.

**Recommended fix**

Write the helper to a per-user private location — `OS.get_user_data_dir()`, which
is under the owner's `AppData` and not shared — rather than next to the app. Give
it a unique name per launch, and delete it after the process has been started.
Fixing RT-01 first matters more: with RT-01 open, the `.vbs` route carries the
same injected script the PowerShell route does.

**Related code affected**

`Notifier._launch_via_wscript`, `Notifier.send_toast`, `Paths.saves_dir`,
`CareSettings.DEFAULTS["notification_launcher"]`.

---

### RT-13: Windows device names pass the zip-entry check

- Severity: **Info**
- Location: `scripts/pack_archive.gd:189-201`
- Category: platform
- Status: **Unconfirmed**

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
extension they carry. `FileAccess.open(.../CON, WRITE)` should simply fail and
`extract` handles a null handle gracefully — it records "could not write" and
carries on, which is the right shape. I did not confirm what happens on a machine
that genuinely has a `COM1`, where opening a serial port can block. I could not
make it misbehave here, so it is listed for completeness rather than as a defect.

If it is tidied up, the cheapest fix is a refusal list in `is_safe_entry`
(`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`, compared on the part
before the first dot, case-insensitively), alongside the `..` check that is
already there.

---

## What I tested and could not break

Worth saying, since a report of only failures reads as if nothing was sound:

- **Zip-slip.** `..`, `..\`, mixed separators, drive letters, nested `a./../b`,
  leading `/`. All refused before anything is unpacked, and `extract` re-checks
  every entry rather than trusting `inspect`. Correct, and correctly ordered.
- **Dictionary mutation.** `PackArchive.inspect` appends to a `PackedStringArray`
  held in a `Dictionary` and relies on the append landing. I checked that it
  does in Godot 4.7 (`probe_a_dict_append.gd`) — had it not, every safety
  refusal in `inspect` would have been silently discarded.
- **Out-of-range timestamps.** Godot 4.7's `Time.get_datetime_dict_from_unix_time`
  handles `9e18` and `-9e18` arithmetically in 16 ms. An older per-year loop
  would have hung; this one does not (`probe_b2_time.gd`). Only the printed text
  is wrong, which is RT-09.
- **`NaN` in a save file.** `JSON.stringify` replaces `NaN` with `null` and warns,
  so a `NaN` cannot corrupt `pet.json` into an unparseable file and take the
  `.bak` down with it. I went looking for that chain specifically and it is not
  there.
- **Corrupt and truncated saves.** Empty file, truncated JSON, a JSON array
  instead of an object, missing required keys, wrong types per field. All fall
  back cleanly through `read_with_fallback` to `.bak` and then to a fresh dog.
- **Broken packs.** Missing `pet.json`, invalid JSON, unknown `kind`, missing
  model, missing sprite sheet, a sheet whose width does not divide by its frame
  count, no `idle`, unknown state names, zero and negative `target_height` and
  `display_height_px`, unknown background type, unknown role, missing props. Every
  one is described in `problems` and either skipped or fallen back; nothing
  crashes, which is what §4 and §5.4 ask for.
- **Division by zero.** `seconds_to_critical`, `starving_fraction`,
  `seconds_to_fatal`, `integer_scale` and `ScenePainter._layer_range` all guard
  their divisors, and `_layer_range`'s returned count is bounded by the view
  width over the spacing, so a large `scroll_speed_px` does not blow it up.
- **Overlapping transitions.** `SceneStage`'s generation counter and its
  timer-rather-than-tween wait handle a room change arriving mid-action. The
  existing `overlapping_room_changes` scenario covers it and it holds.
- **Actions on a dead dog.** Guarded at `ActionRunner.run`, `Needs.apply_action`
  and `Needs.take_to_vet` — three doors, all locked, as the comments say.
- **The `--script` sandbox.** The `tool_script_mode` guard genuinely keeps the
  test suites off the real `saves/` folder; I ran every suite repeatedly and the
  owner's own `pet.json` was never touched.

## Phase 5: your call

> **Answered.** The owner chose the two Criticals, then the two Highs, then all
> nine remaining findings. Everything in this report is fixed. The one open
> question is the RT-07 behaviour change noted at the top.

1. **Do you want me to fix everything found?** All of it, only certain
   severities (the two Criticals alone, say, or Critical + High), or picked by ID.
2. **Prompt or auto?** Should I stop and show you each fix before moving to the
   next, or work through the list and report at the end?

My recommendation: RT-01 and RT-02 first and on their own — both are code
execution, both are small, contained fixes, and neither changes how the app
behaves for an honest pack. Then RT-03 and RT-04. The rest can go in one pass
afterwards.

## Files changed

Three new scripts, eleven changed, all eight suites extended. The full list,
with what changed and why, is in `99-master-report.md`.

Everything under `redteam/` is still uncommitted: it holds working proofs of
concept, and its transcripts quote the owner's own absolute paths, which
`CLAUDE.md` §11.2 says never to commit.
