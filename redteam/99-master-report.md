# Red Team Master Report

Project: DogPet — portable Windows virtual pet, Godot 4.7.2, GDScript
Engagement: 2026-10-31, external red team
Versions: audited at v1.21, shipped fixes as v1.22, v1.23, v1.24

---

## 1. What this was

One job: break DogPet before anyone else did, then fix what broke. Thirteen
findings, all thirteen fixed, every one with its own document written before the
code was touched and updated after it was proven.

| | Found | Fixed |
|---|---|---|
| Critical | 2 | 2 |
| High | 2 | 2 |
| Medium | 3 | 3 |
| Low | 5 | 5 |
| Info | 1 | 1 |

Tests: **637 → 760 checks, 0 failures.** 123 new checks, all permanent
regression guards in the project's own suites rather than in `redteam/`.

## 2. The app, as mapped in recon

A single-window Godot app, 43 scripts, about 3,900 lines. Seven autoloads
(`Paths`, `Log`, `Settings`, `Needs`, `AssetLibrary`, `Notifier`, `Tray`) over a
set of deliberately pure, node-free classes (`NeedsModel`, `LifeModel`,
`CareSettings`, `NeedsText`, `NotificationRules`, `ActionPlan`, `ImageLimits`,
`PetPack`, `ScenePack`, `PackArchive`, `SaveFile`, `PetHistory`).

That split is the best thing about the codebase and it is why the arithmetic
held up under attack. It is also, as it turned out, the thing the defects had in
common: **everything I found was on a trust boundary, and the pure layer was
clean.**

### Trust boundaries

| Boundary | What arrives | Findings |
|---|---|---|
| `assets/pets/*/pet.json` | pack metadata, from a downloaded zip | RT-01, RT-02, RT-10 |
| `assets/scenes/*/scene.json` | room metadata | RT-02, RT-05 |
| `assets/ui/ui.json` | icon file names | RT-01 |
| Imported `.zip` | arbitrary archive | RT-03, RT-08, RT-13 |
| `saves/pet.json` | a save that can be shared or corrupt | RT-01, RT-06, RT-07, RT-09 |
| `saves/settings.json` | hand-edited by design | RT-04, RT-09 |
| `saves/history.json` | the scoreboard | RT-06, RT-09 |
| PowerShell / `wscript` | the notification subprocess | RT-01, RT-12 |
| `OS.shell_open` | whatever a pack names | RT-02 |
| The system clock | `last_saved_unix` | RT-07 |

The root cause behind the two Criticals and most of the rest: **`assets/` being
loose and shareable is the app's best feature and its entire attack surface**,
and pack data was being trusted the way typed-in text is trusted.

## 3. Scope

Read line by line: all 43 files in `scripts/`, plus `project.godot`,
`export_presets.cfg`, `tools/build.ps1`, all eight suites in `tests/`, and the
JSON under `assets/`. All testing was local, against the owner's own code.

Attack surfaces exercised: hand-crafted `pet.json` / `scene.json` /
`settings.json` / `history.json` / `pet.json.bak`; crafted PNG headers; crafted
and bombed zips; pet names; pack URLs; the PowerShell and wscript notification
paths; the offline catch-up; the save/backup cycle; and a 600 MB zip bomb.

## 4. Findings and fixes

Every row links to its own document; each holds the defect, the reproduction,
the root cause, the fix, the test result, and what else in the app it touches.

| ID | Sev | Finding | Fix doc |
|---|---|---|---|
| RT-01 | Critical | Pet name ran as PowerShell: the name was substituted into an expandable `@"…"@` here-string in the script's own source | [RT-01](fixes/RT-01-pet-name-powershell-injection.md) |
| RT-02 | Critical | A pack's licence link went straight to `OS.shell_open`, which launches programs | [RT-02](fixes/RT-02-pack-link-shell-open.md) |
| RT-03 | High | Import read any declared size: a 597 KB zip took 3 GB | [RT-03](fixes/RT-03-zip-bomb-import.md) |
| RT-04 | High | `starve_grace_intervals: 0` killed a fed dog on the first frame, repeatedly | [RT-04](fixes/RT-04-starve-grace-floor.md) |
| RT-05 | Medium | A 1×1 tile asked for 3.7 M draw calls a frame and froze the window | [RT-05](fixes/RT-05-tiny-tile-freeze.md) |
| RT-06 | Medium | The last good save was deleted before its replacement landed, and success was reported anyway | [RT-06](fixes/RT-06-save-backup-order.md) |
| RT-07 | Medium | A forward clock jump was acted on in full and killed the pet | [RT-07](fixes/RT-07-catch-up-cap.md) |
| RT-08 | Low | "Replace this pack" merged into it instead | [RT-08](fixes/RT-08-import-replaces-not-merges.md) |
| RT-09 | Low | `1e999` in a save round-tripped and printed as "-9223372036854775808 days old" | [RT-09](fixes/RT-09-non-finite-numbers.md) |
| RT-10 | Low | PNG sizes truncated to 32 bits, so the guard skipped the files it existed for | [RT-10](fixes/RT-10-png-size-truncation.md) |
| RT-11 | Low | The log rotated only at startup, so a tray session grew it without limit | [RT-11](fixes/RT-11-log-rotation.md) |
| RT-12 | Low | `saves/notify.vbs` was written to a possibly-shared folder, then executed | [RT-12](fixes/RT-12-notify-vbs-location.md) |
| RT-13 | Info | Windows device names passed the zip-entry check | [RT-13](fixes/RT-13-zip-device-names.md) |

## 5. How the fixes connect

Four patterns run through the thirteen, and each was fixed the same way in every
place it appeared.

**Escaping for the wrong parser (RT-01).** The pet name was correctly escaped
for XML and then placed where PowerShell read it first. The fix was to stop
interpolating at all — base64 in, DOM out — rather than to escape harder. Any
future "escape it properly" instinct in this codebase should be checked against
*which* parser sees the text, and in what order.

**Trusting a declaration instead of checking it (RT-02, RT-03, RT-04, RT-05,
RT-09, RT-10).** `license_url` claimed to be a URL; a zip entry claimed a size;
`settings.json` claimed a grace period; a tile claimed to be a tile; a save
claimed a number. In each case the claim was acted on. All six are now checked
at the boundary, with an allow-list where the valid set is small (RT-02's two
schemes) and a clamp where it is a range (RT-03, RT-04, RT-05, RT-09, RT-10).

**Destroying before replacing (RT-06, RT-08).** `write_atomic` moved the only
good save aside to make room; the importer wrote over a pack without clearing
it. Both now do the safe half first — copy, verify, then replace — and both
turned out to rest on the same discovery: Godot's `rename_absolute` *does*
overwrite an existing file on Windows, contrary to the comment in `SaveFile`
that justified the destructive order.

**Doing a job once that needs doing continuously (RT-11, RT-12).** The log
rotated at startup only; the vbs helper was written and left. Both are now
maintained as the app runs — a running byte count, and a sweep per
notification.

### A fifth pattern, in my own work

Three fixes had to move because the code they belonged in could not be tested:
`CreditsList` (RT-02), `PackTransfer` (RT-08) and, for the probes, `SceneView`
and `Log`. All four name autoloads, and **a script that names an autoload cannot
be compiled by a `--script` run at all** — which `ImageLimits` and
`CareSettings` say in their own comments. The rule the project already follows
is the right one and worth stating plainly for future work: *if a rule is worth
testing, it goes in a pure class.* Two new ones came out of this engagement
(`PackLinks`, `ZipSizes`) and one existing one gained a method
(`PackArchive.empty_folder`).

## 6. New and changed files

**New**

| File | For | Why it is its own file |
|---|---|---|
| `scripts/pack_links.gd` | RT-02 | Pure URL rule; `CreditsList` cannot be tested |
| `scripts/zip_sizes.gd` | RT-03 | Reads a zip's central directory; `ZIPReader` has no size API |

**Changed**

| File | Findings |
|---|---|
| `scripts/notifier.gd` | RT-01, RT-12 |
| `scripts/credits_list.gd` | RT-02 |
| `scripts/pack_archive.gd` | RT-03, RT-08, RT-13 |
| `scripts/care_settings.gd` | RT-04, RT-09 |
| `scripts/settings.gd` | RT-04 |
| `scripts/life_model.gd` | RT-04, RT-09 |
| `scripts/scene_pack.gd` | RT-05 |
| `scripts/scene_view.gd` | RT-05 |
| `scripts/save_file.gd` | RT-06 |
| `scripts/pet_history.gd` | RT-06, RT-09 |
| `scripts/needs.gd` | RT-06, RT-07 |
| `scripts/needs_model.gd` | RT-07, RT-09 |
| `scripts/away_card.gd` | RT-07 |
| `scripts/pack_transfer.gd` | RT-08 |
| `scripts/needs_text.gd` | RT-09 |
| `scripts/image_limits.gd` | RT-10 |
| `scripts/pet_pack.gd` | RT-10 |
| `scripts/log.gd` | RT-11 |

**One deletion:** `PetPack._png_size`, a second PNG header reader that checked
neither the signature nor the size. There is one reader now.

## 7. Tests

| Suite | Before | After | Covering |
|---|---|---|---|
| `test_needs` | 157 | 170 | RT-07 |
| `test_life` | 85 | 108 | RT-04, RT-09 |
| `test_history` | 37 | 45 | RT-09 |
| `test_packs` | 56 | 107 | RT-02, RT-03, RT-08, RT-13 |
| `test_pets` | 105 | 111 | RT-10 |
| `test_scenes` | 88 | 96 | RT-05 |
| `test_notify` | 62 | 68 | RT-11 |
| `test_integration` | 47 | 55 | RT-07 |
| **Total** | **637** | **760** | 0 failures |

`godot --headless --path . --quit` reports no script errors.

Red team harnesses live in `redteam/tests/` — fifteen probes. They are the
reproductions, not the regression suite; the regression guards are in `tests/`
where the owner's own `build.ps1` and habits will keep running them.

### What testing caught that reasoning did not

Worth recording, because in each case the plan was wrong and the probe was right:

1. **RT-07's whole approach.** The cap I designed did not fix the finding, and
   the integration scenario proved it in one run. The fix had to be rethought
   around what is reversible rather than how long the absence was.
2. **An engine claim in `CLAUDE.md`.** `ZIPReader.get_file_info()` does not
   exist in 4.7.2, so RT-03's planned approach was impossible as written.
3. **A comment that justified a bug.** `SaveFile` said Windows cannot rename
   onto an existing file. It can, in this build — and that comment was the
   stated reason for the destructive ordering in RT-06.
4. **Two defects I introduced.** `raw_to_base64("")` pushes an engine error
   (RT-01), and `get_tree()` is null in an autoload before it enters the tree
   (RT-12). Both were caught by running the probe rather than by reading the
   diff.
5. **A gap in RT-03's limits.** A 263 KB manifest passed the per-file ceiling
   onto disk, where it is re-parsed on every asset reload. Found by a test
   expectation I had written for the wrong reason.
6. **A misleading measurement.** The zip bomb probe's "peak 624 MB" after the
   fix was the probe's own 600 MB buffer, not `inspect`'s. Isolated properly it
   is 1 KB.

## 8. Still open

**Nothing.** All thirteen findings are fixed and the one decision has been made.

RT-07's behaviour change — after an absence longer than thirty days the dog
survives to be looked at rather than being found dead — was put to the owner
and **kept**. It is now recorded in `CLAUDE.md` §6.3 beside the original
offline-starvation rule it qualifies, so the spec and the code cannot drift
apart on the most consequential rule in the app.

**Deliberately not changed**, with reasons in the fix docs:

- `Settings._save` writes `settings.json` with no temp file. A mangled settings
  file self-heals on the next launch from the merged defaults, so it costs
  preferences at worst, never the dog.
- A file the owner drops into `assets/` by hand is still read with no size
  limit. That is their own folder, and `CLAUDE.md` invites them to fill it; the
  import path is the one that takes files from strangers.
- `sickness_rise_intervals` and `illness_mean_intervals` have no floors. Zero
  already means "never happens" there, and a floor would introduce a death.
- Pet names may still contain `$`, backticks and anything else. After RT-01 they
  are safe, and "Mr. $parkles" should keep working.
- `PetPack` / `ScenePack` still store pack URLs verbatim. Nothing acts on them
  unchecked now, and parsing is their job.

**Not re-tested after the fixes:** the real tray icon, close-to-tray, and the
packaged build from `tools/build.ps1`. Everything here was verified headlessly
plus live PowerShell toasts; a run of the shipped zip on a clean folder is the
owner's phase 6 test and has not been redone since v1.21.

## 9. Keeping it hardened

1. **Treat `assets/` as hostile input, always.** Every finding of substance came
   from there. A new field in `pet.json` or `scene.json` needs a decision about
   what happens when it is a lie, before it is read.
2. **Never interpolate into another language.** Pass values as data — base64,
   DOM nodes, process arguments. `_xml_escape` was removed rather than extended
   for exactly this reason.
3. **Allow-list where the valid set is small.** `PackLinks` allows two schemes
   because nothing can know which of the owner's protocol handlers are
   dangerous.
4. **Check the size before the allocation.** `ZipSizes` and `ImageLimits` both
   exist to answer "how big is this?" without decoding it. Anything new that
   reads a file from `assets/` should ask one of them first.
5. **Keep security limits out of `settings.json`.** Every tuning number lives
   there on purpose; the four import ceilings deliberately do not, because a
   limit a pack could edit is not a limit.
6. **Do the safe half first.** Copy before replace, back up before delete,
   write the new file before touching the old one.
7. **If a rule is worth testing, put it in a pure class.** An autoload reference
   makes a script untestable headlessly. This moved three fixes during this
   engagement.
8. **Run the suites before committing.** `CLAUDE.md` §11.2 already says so. 760
   checks take under three minutes and caught six things reasoning missed.
