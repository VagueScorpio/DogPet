# DogPet — Complete Blueprint, Design and Architecture

**Version of this document:** 1.0, covering DogPet **v1.26** (2026-10-31)
**Engine:** Godot 4.7.2 stable, standard (non-.NET) build — GDScript only
**Platform:** Windows 10/11, x86_64
**Repository:** https://github.com/VagueScorpio/DogPet (MIT for the code; art under its own licences)

---

## 0. How to use this document

This is the complete specification of a working application. It is written so
that a competent developer — or an AI agent — can rebuild DogPet from nothing
and arrive at substantially the same program, including the parts that are
non-obvious and the parts that were got wrong the first time.

It contains:

| Section | What it gives you |
|---|---|
| 1–4 | What the app is, its hard constraints, and its file layout |
| 5 | Architecture: the one organising idea, and every script's job |
| 6–11 | Full functional specification, with every tuning number |
| 12–13 | Testing strategy and the build pipeline |
| 14 | **Every bug and hole found, how it was fixed, and why** |
| 15 | The complete roadmap, as built, plus what remains |
| 16 | A recommended build order for recreating it |
| 17 | Appendices: JSON schemas, every constant, engine gotchas |

If you are rebuilding the app, read §5 before writing any code — the layering
rule there is what everything else depends on — then follow §16.

**Section 17.3 is the highest-value page in this document.** It lists engine
behaviours that are counter-intuitive, cost real time to discover, and two of
which were documented *wrongly* in the project's own spec. Read it before
trusting any assumption about Godot.

---

## 1. What the app is

A virtual pet dog that lives in its own small desktop window.

The dog has three needs — **Hunger**, **Happiness** and **Energy** — which
change continuously, **including while the app is closed**. On launch the app
works out how long it was shut and catches the needs up, then shows a "While you
were away" summary. The owner cares for the dog with three actions — **Feed**,
**Play** and **Walk** — each of which switches to its own room, plays an
animation, and then applies its effect.

The window minimises to a **system tray icon**. While it is out of the way the
app raises **Windows toast notifications** when a need gets low, and drops to a
very low frame rate so leaving it running is nearly free.

All art lives in a **loose `assets/` folder beside the .exe**. Pets and rooms are
plain folders holding a JSON manifest and ordinary PNG or GLB files, loaded at
runtime. They can be added, swapped, imported and exported as `.zip` packs
without rebuilding anything. This is the app's defining feature — and, as §14
shows, its entire attack surface.

There are two ways to play:

- **Casual** (default): the dog can never die. It gets sad until cared for.
- **Real Pet**: the dog ages, can fall ill, needs taking to the vet, and can be
  lost to starvation or to an untreated illness. A scoreboard remembers every
  dog that has lived.

The product is a zip containing `DogPet.exe`, a loose `assets/` folder and a
`README.txt`. Nothing is installed; `saves/` is created beside the exe on first
run.

### 1.1 Scale

| | |
|---|---|
| GDScript files in `scripts/` | 43 (~7,970 lines) |
| Scenes in `scenes/` | 9 |
| Autoloads | 7 |
| Test suites | 8 (760 checks) |
| Shipped pet packs | 3 (two 3D, one 2D pixel) |
| Shipped rooms | 5 (home, eat, play, walk, vet) |

---

## 2. Hard constraints

These are non-negotiable. Several design decisions elsewhere only make sense in
their light.

1. **Godot 4.4+, standard build. GDScript only.** No C#, no GDExtensions, no
   third-party addons. (Developed against 4.7.2.)
2. **Compatibility renderer** (`gl_compatibility`).
3. **Static typing everywhere** — `var x: float`, typed function signatures,
   typed returns.
4. **Nothing is installed on the user's machine.** The exported app must run
   from an unzipped folder. Anything that calls out to Windows may use only
   tools built into Windows 10/11 — in practice PowerShell 5.1 and `wscript`.
5. **No hard-coded art paths in game logic.** All art arrives through the asset
   loader. The only art packed into the exe is the fallback set and the exe
   icon.
6. **The app must never crash on bad or missing assets.** Every loader degrades:
   a broken pack is described and skipped, a missing picture costs one prop, a
   missing `assets/` falls back to the built-in copy.
7. **One version number**, in `project.godot` under `application/config/version`,
   shown in Settings → About. It increments with every change.
8. **A rolling `CHANGELOG.txt`** with what / why / how per version, and a
   table of contents kept current.
9. **Scripts stay focused and under about 300 lines**, commented in plain
   English — the owner is learning Godot from this code.

### 2.1 Project settings

```ini
[application]
config/name="DogPet"
config/version="1.26"
run/main_scene="res://scenes/Main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
config/icon="res://icons/app_icon.png"

[display]
window/size/viewport_width=540
window/size/viewport_height=760
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
textures/canvas_textures/default_texture_filter=0   # nearest — pixel art
renderer/rendering_method="gl_compatibility"

[autoload]
Paths="*res://scripts/paths.gd"
Log="*res://scripts/log.gd"
Settings="*res://scripts/settings.gd"
Needs="*res://scripts/needs.gd"
AssetLibrary="*res://scripts/asset_library.gd"
Notifier="*res://scripts/notifier.gd"
Tray="*res://scripts/tray.gd"
```

Window minimum size `420×600` is set in code (`Main.MIN_WINDOW_SIZE`).
**Autoload order matters** — see §5.6.

---

## 3. Repository layout

```
DogPet/
├── project.godot
├── CLAUDE.md                  the original build blueprint / spec
├── BLUEPRINT.md               this document
├── CHANGELOG.txt              rolling, what/why/how per version
├── README.md                  repo front page, with screenshots
├── LICENSE                    MIT, for the code only
├── .gitignore  .gitattributes
├── icons/app_icon.ico         exe icon
├── icons/app_icon.png         project icon
├── scripts/                   all 43 .gd files, flat
├── scenes/                    all 9 .tscn files
├── builtin/                   fallback art packed INTO the exe
│   ├── pets/pug_3d/
│   ├── scenes/{home,eat,play,walk}/
│   └── ui/
├── tests/                     8 headless suites
├── tools/build.ps1            export + package
├── docs/                      screenshots (+ .gdignore)
├── redteam/                   the security audit (see §14.2)
├── assets/                    LOOSE art, + .gdignore
└── saves/                     dev saves, + .gdignore
```

### 3.1 The `.gdignore` files — important

`assets/`, `saves/`, `docs/` and `build/` each contain an empty `.gdignore`.
**These must be kept.** They stop the Godot editor importing those folders,
which means:

- art in `assets/` is **never** baked into the `.pck`, and is always loaded at
  runtime from disk — exactly as it will be in the shipped app;
- development behaves identically to the shipped build;
- `build/` is not re-imported into the *next* build (see bug **D-2** in §14.1 —
  omitting this made the exe grow by megabytes every build).

### 3.2 Shipped zip layout

```
DogPet-v<ver>.zip
└── DogPet-v<ver>/
    ├── DogPet.exe        single file, PCK embedded
    ├── assets/           copied from the project, .gdignore and _backup stripped
    └── README.txt        generated by build.ps1
                          (saves/ is created by the app on first run)
```

---

## 4. Paths and portability

`Paths` is the first autoload and establishes where everything lives.

- **Base folder:** in an exported build, `OS.get_executable_path().get_base_dir()`;
  in the editor (`OS.has_feature("editor")`),
  `ProjectSettings.globalize_path("res://")`. So the app is portable: unzip it
  anywhere and `assets/` and `saves/` sit beside it.
- `assets_dir = base/assets`, `saves_dir = base/saves`
- `saves/pet.json` — the dog
- `saves/settings.json` — preferences and tuning
- `saves/history.json` — the scoreboard. **Deliberately separate from
  `pet.json`**, because it outlives every pet in it: starting a new dog wipes the
  save and must not wipe the record of the one before.
- `saves/dogpet.log`

**Write-probe fallback.** On startup `Paths` creates `saves/` if missing, then
*writes a probe file into it*. Creating a directory can succeed on Windows where
writing a file still fails, so the probe is the part that matters. If it fails —
the app was unzipped into `C:\Program Files`, say — saves fall back to
`OS.get_user_data_dir() + "/saves"`, `saves_moved_to_user_dir` is set, and Main
shows a one-time notice saying where the saves went.

**Bootstrap ordering problem.** `Paths` runs before `Log` exists, so it cannot
log. Anything worth saying goes into `Paths.startup_notes: PackedStringArray`,
which `Log` drains in its own `_ready` and `Main` shows on screen.

**`tool_script_mode`.** `Paths._ready` sets this from
`OS.get_cmdline_args().has("--script")`. Every autoload checks it and skips its
startup work, so the headless test suites never touch the owner's real save
files. This flag is load-bearing for the whole test strategy (§12).

---

## 5. Architecture

### 5.1 The one organising idea

**Every piece of logic worth testing lives in a pure class with no nodes, no
autoloads and no clock of its own. Time, randomness and configuration arrive as
arguments.** The autoloads are thin wrappers that own a clock, a file and some
signals.

This is not stylistic. It is forced by a hard engine constraint:

> **A script that names an autoload cannot be compiled by a `--script` run at
> all.** A `--script` invocation is compiled *before* the autoload singletons
> are registered as names, so referring to `Needs` or `Log` in such a script
> fails with "Identifier not found".

Consequently a rule with an autoload reference anywhere in its file is
**permanently untestable headlessly**. During the security audit this forced
three fixes to move house after they were written (§14.2, RT-02/RT-08). The rule
to follow is blunt:

> **If a rule is worth testing, it goes in a pure class.**

Pure classes are also reached by `preload()` rather than by their `class_name`
where they are used by other pure classes, because a newly added script is not
in the editor-generated class cache until the editor rescans, and neither a
headless build nor the tests should have to wait for that.

### 5.2 Autoloads (7)

| Autoload | File | Owns |
|---|---|---|
| `Paths` | `paths.gd` | Folder resolution, write probe, `tool_script_mode`, `startup_notes` |
| `Log` | `log.gd` | Timestamped append-only log with size rotation |
| `Settings` | `settings.gd` | `settings.json`, the `changed(key)` signal, tuning lookups |
| `Needs` | `needs.gd` | The live needs, the clock, autosave, offline catch-up, the dog's name and pack |
| `AssetLibrary` | `asset_library.gd` | Scanning `assets/`, the active pet and rooms, the UI pack |
| `Notifier` | `notifier.gd` | When to speak, and raising toasts or banners |
| `Tray` | `tray.gd` | The tray icon and menu, close-button behaviour, low-power mode |

### 5.3 Pure classes (no nodes, no autoloads — all testable)

| Class | File | Job |
|---|---|---|
| `NeedsModel` | `needs_model.gd` | The needs arithmetic: drain, clamp, thresholds, catch-up, actions, mood |
| `NeedsText` | `needs_text.gd` | The words: names, labels, countdowns, durations, reactions |
| `CareSettings` | `care_settings.gd` | The shipped defaults and the pure lookups/floors over them |
| `LifeModel` | `life_model.gd` | Ageing, illness, starvation, death |
| `PetHistory` | `pet_history.gd` | `history.json`: the record of past dogs |
| `SaveFile` | `save_file.gd` | Atomic save write, read-with-fallback |
| `PetPack` | `pet_pack.gd` | Parsing and validating `pet.json`; fit/scale geometry |
| `ScenePack` | `scene_pack.gd` | Parsing and validating `scene.json` |
| `UiPack` | `ui_pack.gd` | Parsing `ui.json` |
| `PetMotion` | `pet_motion.gd` | Procedural poses: state + time → pose |
| `PetPose` | `pet_pose.gd` | The pose value object |
| `PetAnimator` | `pet_animator.gd` | State machine, blending, idle fidgets |
| `PetLoader` | `pet_loader.gd` | Turning a pack into nodes/textures (touches resources, not autoload state) |
| `ActionPlan` | `action_plan.gd` | What each care action involves, as lookups |
| `NotificationRules` | `notification_rules.gd` | Whether to speak, and what to say |
| `ImageLimits` | `image_limits.gd` | How big an image may be; PNG header reading |
| `PackArchive` | `pack_archive.gd` | Reading/writing pack zips; entry safety; size limits |
| `PackLinks` | `pack_links.gd` | Which of a pack's links are safe to follow |
| `ZipSizes` | `zip_sizes.gd` | A zip's declared sizes, read from its central directory |
| `ScenePainter` | `scene_painter.gd` | Drawing the generated backgrounds |
| `UiBits` | `ui_bits.gd` | The headings, rows and buttons panels are built from |

### 5.4 Nodes and scenes (9)

| Scene | Script | Role |
|---|---|---|
| `Main.tscn` | `main.gd` | The window: menu, bars, pet area, buttons, overlays |
| `PetView.tscn` | `pet_view.gd` | The dog — 3D in a SubViewport or a 2D AnimatedSprite2D |
| `NeedsBar.tscn` | `needs_bar.gd` | One need (or the sickness meter) |
| `SettingsPanel.tscn` | `settings_panel.gd` | The seven-section settings screen |
| `AwayCard.tscn` | `away_card.gd` | "While you were away" |
| `Banner.tscn` | `banner.gd` | In-app message strip |
| `DeathCard.tscn` | `death_card.gd` | Real play: the dog has died |
| `Scoreboard.tscn` | `scoreboard.gd` | Every dog that has lived |
| `HelpPanel.tscn` | `help_panel.gd` | How to change the art |

Built in code rather than as scenes: `AppMenu` (`app_menu.gd`, a `MenuBar`),
`SceneStage` (`scene_stage.gd`), `SceneView` (`scene_view.gd`), `ActionRunner`
(`action_runner.gd`), `PackTransfer` (`pack_transfer.gd`), `CreditsList`
(`credits_list.gd`).

Panels are built in code because almost everything they show is a list of
whatever happens to be installed — the pets found, the rooms offering themselves
for each slot, each pack's credit line — none of which can be known in advance.

#### Main.tscn tree

```
Main (Control)
├── Background (ColorRect)
└── Shell (VBoxContainer)
    ├── %MenuHost (PanelContainer)        ← AppMenu added here in code
    └── Layout (MarginContainer)
        └── Column (VBoxContainer)
            ├── HeaderRow (HBoxContainer)
            │   ├── %TitleLabel  ├── HeaderSpacer  └── %DemoBadge
            ├── %NoticePanel (PanelContainer)
            │   └── NoticePad → NoticeRow → %NoticeLabel, %NoticeDismiss
            ├── %Bars (VBoxContainer)     ← one NeedsBar per need, in code
            ├── %PetArea (PanelContainer)
            │   └── %PetView             ← SceneStage inserted at index 0
            ├── %ReactionLabel (Label)
            └── ActionRow (HBoxContainer)
                └── %FeedButton %PlayButton %WalkButton %VetButton %SettingsButton
```

The overlays (`%AwayCard`, `%Banner`, `%SettingsPanel`, `%HelpPanel`,
`%DeathCard`, `%Scoreboard`) are instanced in `Main.tscn` as siblings drawn over
the shell.

#### PetView.tscn tree

```
PetView (Control)
├── %Shadow (TextureRect)                 ← generated blob texture
├── %Viewport3D (SubViewportContainer)
│   └── %SubViewport (transparent_bg = true)
│       ├── WorldEnvironment
│       ├── %Camera3D
│       ├── %KeyLight (DirectionalLight3D)
│       ├── %FillLight (DirectionalLight3D)
│       └── %PetPivot (Node3D)
│           └── %PetFacing (Node3D)       ← the loaded model goes here
├── %Sprite (AnimatedSprite2D)            ← for 2D packs
└── %Zzz (Control)                        ← floating sleep "z"s
```

The other scenes follow the same shape: a `ColorRect` dim, a `PanelContainer`
frame, a `MarginContainer` pad, a `VBoxContainer` column, with `%`-unique names
on anything the script touches.

### 5.5 Signals

Components communicate by signal. Long `get_node` paths across the tree are
avoided.

```
Needs.need_changed(key: StringName, value: float)       → NeedsBar
Needs.threshold_crossed(key: StringName, level: int)    → NeedsBar, Notifier
Needs.pet_name_changed(new_name: String)                → Main
Needs.pet_died(cause: int, name: String, age: float)    → Main → DeathCard
Needs.fell_ill()                                        → Main
Needs.healed()                                          → Main
Needs.pet_started()                                     → Main, Notifier

Settings.changed(key: String)                           → Main, panels

AssetLibrary.pet_changed(pack: PetPack)                 → PetView
AssetLibrary.scene_changed(role: String, pack)          → SceneStage
AssetLibrary.library_reloaded()                         → SettingsPanel

Notifier.banner_requested(title: String, body: String)  → Banner

SceneStage.transition_finished(role: String)
ActionRunner.started(action) / finished(action)         → Main
PackTransfer.finished(message: String)                  → SettingsPanel
DeathCard.new_pet_requested(name: String)               → Needs.start_new_pet
AppMenu.rename_requested / instructions_requested /
        settings_requested / scoreboard_requested       → Main
```

`need_changed` fires only when the **rounded** percentage changes, and
`threshold_crossed` only on an actual level change, so connecting to them is
cheap. `Needs` keeps `_shown` and `_levels` dictionaries to do that debouncing.

### 5.6 Startup sequence

Autoload order is significant and must be preserved:

1. **`Paths`** — resolves folders, probes for writability, sets
   `tool_script_mode`, collects `startup_notes`.
2. **`Log`** — opens the log, rotates it if oversized, replays
   `Paths.startup_notes`, prints version and folders.
3. **`Settings`** — loads defaults, merges `settings.json` over them, always
   rewrites the file (so a missing or half-filled one is repaired).
4. **`Needs`** — reads `pet.json` (falling back to `.bak`), applies the offline
   catch-up, builds the away-card summary, saves.
5. **`AssetLibrary`** — scans `assets/pets` and `assets/scenes`, loads the UI
   pack, falls back to `res://builtin/` where needed, activates the saved pet
   and rooms.
6. **`Notifier`** — connects to `Needs`, sweeps stale helper files, adopts the
   current levels (see below).
7. **`Tray`** — builds the indicator and menu if supported, optionally hides to
   tray.

Then `Main.tscn` is instanced.

**Two consequences that caused real bugs (§14.1):**

- The autoloads all finish *before any scene exists*, so nothing is listening to
  signals during startup. `Needs` therefore **stores** the catch-up summary in
  `_away_summary` and `Main` collects it with `take_away_summary()` in its own
  `_ready`. Likewise a dog that died during the catch-up emits `pet_died` into
  an empty room, so `Main._ready` separately checks `Needs.life.alive`.
- A need can be sitting at Critical at launch with no *crossing* to hear about,
  ever. `Notifier._adopt_current_levels()` therefore takes the current levels as
  read and schedules reminders for anything already critical.

---

## 6. The needs system

### 6.1 Meanings

All values are floats 0–100.

| Need | Over time | Bad end | Fixed by |
|---|---|---|---|
| **Hunger** | rises | 100 = starving | Feed |
| **Happiness** | falls | 0 = miserable | Play |
| **Energy** | rises (pent-up) | 100 = bouncing off the walls | Walk |

"**Badness**" is the unifying abstraction: how far a need has travelled towards
its own bad end, always 0 (just cared for) to 100 (critical), whichever
direction the need runs. `badness = 100 - value` for Happiness, `value`
otherwise. One piece of code then handles all three with no special cases.

Each bar shows an icon, the value, a word label (**Fine** / **Getting low** /
**Needs care now**), a countdown ("needs care in ~1h 20m") and a hint spelling
out what a full bar means — because a full Hunger bar is bad news while a full
Happiness bar is the opposite. **Colour is never the only signal.**

### 6.2 Care intervals

The interval is the time from fully cared for to critical. Each need drains
linearly at `100 / interval` per second.

| Setting | Hunger | Happiness | Energy |
|---|---|---|---|
| Frequent | 40 min (2400 s) | 45 min (2700 s) | 50 min (3000 s) |
| Moderate | 3 h (10800 s) | 3.5 h (12600 s) | 4 h (14400 s) |
| Long | 10 h (36000 s) | 11 h (39600 s) | 12 h (43200 s) |
| ⚡ Demo | 45 s | 50 s | 55 s |

The three are **staggered on purpose** so they do not all hit critical at once.

**Demo Speed is a toggle, not a fourth setting.** When on, the live drain uses
the Demo row; a ⚡ badge shows in the header. **The offline catch-up always uses
the selected real setting, never Demo** — otherwise a 45-second demo row applied
to hours of real absence would max every bar the moment the app reopened. This
is enforced by two separate functions, `CareSettings.live_interval_name()` and
`catch_up_interval_name()`, and is explicitly tested.

### 6.3 Thresholds

- **Warning** at 70% of the way to critical (`WARNING_BADNESS = 70.0`).
- **Critical** at the bad end.
- Values clamp at the bad end.
- `EPSILON = 0.001`. Draining for exactly 70% of an interval lands on 69.99999,
  and a full interval on 99.99999. Without this slack a need could sit one
  ten-millionth below a threshold, display as "70", and never fire its warning.

### 6.4 Actions

Each action: locks the buttons → transitions to its room → plays its animation
for its duration → applies its effects → transitions home → unlocks.

Effects land **after** the animation, so the bars move when the dog has actually
been fed rather than when the button was pressed.

| Action | Room | Animation | Duration | Main effect | Side effects |
|---|---|---|---|---|---|
| Feed | eat | `eat` | 5 s | Hunger → 0 | Happiness +5 |
| Play | play | `play` | 8 s | Happiness → 100 | Energy −15, Hunger +5 |
| Walk | walk | `walk` | 10 s | Energy → 0 | Happiness +10, Hunger +10 |
| Vet | vet | `sad` | 7 s | (sickness −60) | Happiness −8 |

Durations are the same in Demo mode. In `apply_action`, **every `_set` happens
before every `_delta`**, so the result does not depend on the order the JSON
file happened to list them in.

### 6.5 Offline catch-up

- `pet.json` stores the three values, the pet name, the pack id, the life block
  and `last_saved_unix`.
- Autosave every 30 s, on minimise to tray, and on quit.
- On launch: `elapsed = now − last_saved_unix`, floored at 0 by
  `NeedsModel.elapsed_between()` so a clock that moved backwards cannot heal the
  dog for free.
- **Capped at 30 days** by `NeedsModel.capped_elapsed()` — see RT-07 in §14.2
  for why, and for the important subtlety about what the cap does and does not
  do.
- If `elapsed > 60 s`, a "While you were away (3h 12m)…" card lists each need's
  before → after and the dog's reaction.

### 6.6 Mood state

When no action is running, read worst-first:

```
energy ≥ 85            → restless      (too wound up to settle)
happiness ≤ 25
  or hunger ≥ 85       → sad
within 4 s of an action → happy
otherwise              → idle
```

An ill or dead dog is always `sad`, whatever its needs say.

---

## 7. Real Pet play

Added at the owner's explicit request. **None of this happens in Casual play**,
and anything left over from a spell of Real play is cleared rather than lying in
wait.

All numbers live in `settings.json` under `real_play` and are **counted in
hunger intervals**, so everything scales with the care setting: on Demo an
illness runs its course in a minute, on Long it takes most of a day.

### 7.1 Starvation

Hunger reaching 100 starts a countdown of one further care interval
(`starve_grace_intervals = 1.0`). On Moderate that is 3 h to reach starving,
then 3 h more. **The countdown resets the moment the dog is fed.**

This can happen during the offline catch-up — the owner's explicit choice — but
the absence is split in two: the stretch before hunger reached the bad end, and
the stretch after it. **Only the second feeds the starving clock.** Done in one
piece instead, a dog fed right before the app closed and away for three hours
and one minute on Moderate would be credited with three hours and a minute of
starvation and die on the spot, when in truth it had been starving for a minute.
`NeedsModel.seconds_at_critical()` does this arithmetic.

### 7.2 Illness

At random — on average every 8 hunger intervals — the dog falls ill. A fourth
**Sickness** bar climbs 0 → 100 over 1.5 hunger intervals; at 100 the dog dies.
A newly ill dog starts at 4 rather than 0 so the bar is visible the moment it
appears. **Take To Vet** takes 60 off the bar, so a badly ill dog needs more
than one visit.

The chance is expressed as an **average wait** rather than a per-tick
probability — `roll < 1 - exp(-seconds / mean)` — so one long catch-up is as
likely to produce an illness as the same time spent watching, and no more
likely. The `roll` is supplied by the caller, which keeps `LifeModel` pure and
lets the tests decide what happens.

### 7.3 Ageing

Two hunger intervals to the dog-day, through **Puppy** (<3 days), **Young**
(<10), **Adult** (<40), **Senior**. Ageing happens in **both** modes.
**Old age is never fatal** — the owner chose that too.

### 7.4 Scoreboard

Every dog that dies is written to `saves/history.json` **the moment it dies**,
with name, birth date, death date, age and cause. Written there and nowhere else
so that reloading an already-dead save cannot record the same dog twice —
`LifeModel.advance()` returns early once `alive` is false. Capped at 200
records, newest first, oldest trimmed.

Reached from **Mode → Scoreboard…**, which also lists the dog you have now,
marked as still living.

---

## 8. The asset system

### 8.1 Pet packs — `assets/pets/<folder>/pet.json`

Every folder under `assets/pets/` with a readable `pet.json` is a selectable
pet. Two kinds.

**3D model pet** (`"kind": "model3d"`), `.glb` or `.gltf`:

```json
{
  "format_version": 1,
  "id": "pug_3d",
  "name": "Pug",
  "kind": "model3d",
  "model": "model.glb",
  "target_height": 1.0,
  "rotation_y_degrees": -29,
  "animations": {},
  "credit": "Pug by Smirnoff Alexander [CC-BY] (…) via Poly Pizza (…)",
  "license": "CC-BY 3.0",
  "license_url": "https://creativecommons.org/licenses/by/3.0/",
  "source_url": "https://poly.pizza/m/3nFZQW8yojl"
}
```

- Loaded at runtime with `GLTFDocument.append_from_file()` + `GLTFState` →
  `generate_scene()`. **Not** `load()` — these are not imported resources.
- **Auto-normalising is essential.** Compute the combined `AABB` of every
  `MeshInstance3D` child, scale uniformly so the height equals `target_height`,
  and shift so the feet sit at y = 0 and the model is centred on x/z. Models from
  different sources arrive at wildly different scales — the two shipped models
  differ by about 3×.
- `rotation_y_degrees` turns the dog to face the camera. The shipped pug is
  modelled 29° off, hence `-29`.
- `animations` optionally maps app states to clip names inside the `.glb`. If a
  state has a mapped clip and the file brought an `AnimationPlayer`, play it.
  **Otherwise use the procedural animation.** Both shipped models are static
  meshes with no rig and no clips, so **procedural animation is the main path,
  not an edge case.**

**2D sprite pet** (`"kind": "sprite2d"`):

```json
{
  "format_version": 1,
  "id": "pug_pixel",
  "name": "Pixel Pug",
  "kind": "sprite2d",
  "pixel_art": true,
  "display_height_px": 160,
  "faces": "right",
  "animations": {
    "idle": { "file": "idle.png", "frames": 1, "fps": 1 },
    "walk": { "file": "walk.png", "frames": 4, "fps": 6 }
  },
  "credit": "Nasha's Cozy Pets Pack"
}
```

- Each animation is a horizontal strip of `frames` equal-width cells. Load PNGs
  with `Image.load_from_file()` → `ImageTexture.create_from_image()` and build
  `SpriteFrames` at runtime from `AtlasTexture` regions — the cells are *not*
  copied, so a four-frame walk costs one texture.
- `pixel_art: true` → nearest filtering and **whole-number scaling only**. Pick
  the largest integer scale not exceeding `display_height_px`.
- **One scale for the whole pack**, chosen from its tallest frame. The pixel
  pug's idle frames are 43 px and its walk frames 32 px; scaling each to fit on
  its own would make the dog visibly change size the moment it started walking.
- `faces` says which way the art faces; flip horizontally for the other.
- Any state without its own animation falls back to `idle` plus the procedural
  layer.

**Valid state names** (both kinds): `idle`, `happy`, `sad`, `eat`, `play`,
`walk`, `restless`, `sleep`.

**`credit` is required.** It is a licence obligation, not decoration — the
default pug is CC-BY 3.0, so its credit line must be visible in the app. A pack
with no credit is still *usable* (the complaint is non-fatal) but it is reported.

### 8.2 Scene packs — `assets/scenes/<folder>/scene.json`

Five fixed **roles**: `home` (the default view), `eat`, `play`, `walk`, `vet`.

A room declares which role it fills with its own `"role"` field, so **the folder
may be named anything and several rooms can offer themselves for the same
role**, for the owner to choose between in Settings. A folder with no `"role"`
falls back to its folder name. The chosen room per role is saved in
`settings.json` under `rooms`.

```json
{
  "format_version": 1,
  "role": "eat",
  "name": "Kitchen",
  "background": { "type": "tiled", "wall": "wall.png", "floor": "floor.png",
                  "floor_ratio": 0.38, "tile_scale": 4 },
  "props": [
    { "file": "feeding_station.png", "x": 0.78, "y": 0.78,
      "scale": 3, "role": "food_bowl" }
  ],
  "pet_spot": { "x": 0.5, "y": 0.82 },
  "transition": "fade"
}
```

**`background.type`:**

| Type | Fields | Behaviour |
|---|---|---|
| `image` | `file` | One picture scaled to **cover** the window — cropped, never stretched |
| `tiled` | `wall`, `floor`, `floor_ratio`, `tile_scale` | Repeating tiles, nearest filter, with a thin darker line where wall meets floor |
| `generated` | `style` + colours | Drawn in code, no pictures at all |

**Generated styles:** `yard` and `park` (gradient sky in 48 bands, ground, a few
clouds; trees and bushes for park; a dirt path when `path` is given) and `room`
(a plain indoor wall, skirting band and floor, taking `wall_color`,
`wainscot_color`, `floor_color`, `floor_ratio` — this is how the vet clinic is
drawn, with no wall or floor pictures at all).

With `"scroll": true` the scene scrolls horizontally at `scroll_speed_px`, with
**parallax**: clouds slow (0.25), trees medium (0.6), path stones and bushes at
full speed. This is how the walk scene moves. All scenery is sized as a
**fraction of the view height**, not in fixed pixels, so it keeps its
proportions at any window size (with fixed sizes the dog ended up towering over
the trees — bug **D-1**, §14.1).

**Props:**

- `x`/`y` are fractions of the window, 0–1. `x` is the prop's middle; **`y` is
  its bottom edge**, so things sit on the floor rather than floating.
- `scale` is an integer (pixel art).
- Drawn in order of `y`, lowest first, so nearer things overlap farther ones.
- `role` is optional and gives a prop a job: `food_bowl` is where the dog walks
  to eat, `toy` is what gets thrown during play, `vet_table` is where the dog
  stands at the vet. The first prop with the role wins; a `<role>_alt` prop is a
  backup used only when the main one is missing.
- Optional `pet_spot` sets where the dog stands; default is centre, 82% down.

**Transitions:** `fade` cross-dissolves over 0.5 s; `slide` pushes the old scene
out sideways (used when starting a walk, so it reads as going somewhere). Each
action switches from `home` to its role's room, plays, then transitions back —
**both legs use the same transition**, so coming back matches going out.

A missing file costs that one prop, or falls the background back to `generated`.
A warning goes in the log. **Never crash.**

### 8.3 UI pack — `assets/ui/ui.json`

The tray icon, the tray alert icon, the four need icons and the three action
button icons.

```json
{
  "format_version": 1,
  "tray_icon": "tray_icon.png",
  "tray_icon_alert": "tray_icon_alert.png",
  "icons":   { "hunger": "…", "happiness": "…", "energy": "…", "sickness": "…" },
  "buttons": { "feed": "…", "play": "…", "walk": "…" },
  "icon_scale": 3
}
```

No icon is load-bearing: a missing one simply is not drawn. The pack is "usable"
if it has at least a tray icon.

### 8.4 Built-in fallback set — `res://builtin/`

Copied into the exe: the default pet (`pets/pug_3d/`), four rooms
(`scenes/{home,eat,play,walk}/`) and `ui/`. **This is the only place art is
packed into the exe.**

If `assets/` is missing, damaged, or every pack in it fails, the app falls back
to these and logs a notice. The app must never come up with no dog at all.

**A `res://` pack loads differently.** Because `builtin/` is inside `res://`,
the editor *has* imported it — so a `.glb` there is a `PackedScene` and must be
loaded with `load()`, not `GLTFDocument`. The loader therefore branches on
`PetPack.is_builtin()` (`dir.begins_with("res://")`). Note the vet room has no
built-in fallback.

### 8.5 Size limits

`assets/` is a folder the owner is invited to drop art into, and an imported
pack may come from anyone. Two independent guards:

**`ImageLimits`** — `MAX_PIXELS = 33,554,432` (8192 × 4096, about 128 MB as
RGBA8). A PNG's dimensions are read out of its 24-byte header *before* anything
is decoded, because pixel count has little to do with file size: a
200-megapixel sheet can zip to a couple of megabytes and then ask for most of a
gigabyte the moment it is decoded. A size that cannot be read is "unknown" and
is never refused — refusing every format whose header this does not parse would
refuse every non-PNG — so there is also a post-decode check behind it.

**`ZipSizes` + `PackArchive`** — per-entry and total ceilings on import, checked
against the zip's own central directory before anything is read. See RT-03 in
§14.2, which explains why the declared size is the right thing to check.

### 8.6 Import and export

**Export.** Pick a pet pack or a room, choose a destination in a save dialog,
and `ZIPPacker` writes the folder out with a `CREDITS.txt` alongside, so the
credit travels with the art instead of being left behind. The built-in packs
cannot be exported.

**Import.** A native file dialog (`DisplayServer.file_dialog_show`, with Godot's
own `FileDialog` as the fallback), then `ZIPReader`. The zip must contain a
`pet.json` or `scene.json` at its root or inside one top-level folder; the
manifest **nearest the top wins**, so a stray nested manifest cannot hijack the
import. The JSON is validated, then the pack is extracted to
`assets/pets/<id>/` or `assets/scenes/<id>/`, where a room's `<id>` is its
*folder name* rather than its role — so importing a second kitchen adds one
rather than replacing the first.

Replacing an existing folder **asks first**, copies the old one to
`assets/_backup/<id>-<timestamp>/`, and only then empties and replaces it.

**Entry safety.** Every entry is checked before anything is unpacked:

- rejected: empty names, leading `/`, any `:` (drive letters and schemes), any
  path component equal to `..`, and Windows device names (`CON`, `NUL`,
  `COM1`–`COM9`, `LPT1`–`LPT9`, matched before the first dot, case-insensitively);
- the check runs in `inspect` *and* again per entry in `extract`, rather than
  `extract` trusting `inspect`.

---

## 9. Rendering and animation

### 9.1 Both kinds of pet in one layout

The main view is 2D. The stack is **background → props → pet → UI**.

For a `model3d` pet the pet layer is a `SubViewportContainer` whose
`SubViewport` has `transparent_bg = true`, holding the model, a `Camera3D` at a
slight three-quarter overhead angle (position `(0, 0.85, 2.2)`, pitch −10°,
FOV 40), a `DirectionalLight3D` key light and a fill light. This lets a 3D dog
stand in front of any 2D background.

A soft dark ellipse **blob shadow** is drawn under the pet for both kinds — it is
what sells the dog as standing on a floor rather than floating in front of one.
The texture is generated once in code (128 × 56, alpha falling off as
`(1 − distance)²`).

The 3D dog always stands at the world origin. Rather than moving it about the
world, **the whole viewport is nudged** until the point where its feet land falls
on the wanted spot: `_viewport_box.position = ground_point - camera.unproject_position(Vector3.ZERO)`.
One body height in pixels is measured off the camera the same way, so the shadow
and the sleep "z"s can be sized identically for both kinds of pet.

### 9.2 Procedural animation

This exists because **neither shipped 3D pet has a rig or a single animation
clip** — they are static meshes. The life has to come from moving the whole dog
about, and that turns out to work just as well on a 2D sprite.

`PetMotion` is entirely static functions of `(state, time, variation)`, so the
same state at the same time always gives the same pose. That makes it testable
and means a state can be scrubbed to any point rather than only played forwards.
Anything genuinely random — which fidget, whether this particular happy spins —
is decided by `PetAnimator` and passed in.

| State | Motion |
|---|---|
| `idle` | Slow breathing (scale Y ±2%, 3 s cycle). Every 4–9 s a fidget: head-tilt (roll ±8°), a small turn toward the camera, or a little hop |
| `happy` | 2–3 quick hops with squash-and-stretch on landing; a 360° spin 30% of the time |
| `sad` | Sinks ~8% lower, nose down (pitch 14°), breathing halved, slow 7 s sway, desaturated tint |
| `eat` | Nods (pitch down 20°) about 2.5×/second |
| `play` | A 1.6 s cycle: fast run bob, then a pounce (jump + squash). Turns back and forth after the toy |
| `walk` | Steady trot bob (~4 Hz), side-on to the camera (yaw 70°), while the background scrolls |
| `restless` | Pacing left and right over a 1.6 s cycle, faster bobs, a zoomie spin every ~5 s |
| `sleep` | Lies low (scale Y 0.85, roll 6°), very slow breathing, floating "z"s |

**Blending.** The blueprint called for short tweens between states; it is done
as a *blend* instead — the pose the dog was holding is mixed into the new state's
pose over `BLEND_SECONDS = 0.3`. Same result, and it survives a state changing
again halfway through, which a tween would not.

**Sprite adaptations.** A sprite cannot turn, so a yaw is shown as a horizontal
squeeze (`lerp(1, |cos(yaw)|, 0.6)`), which reads as the same thing at this
size — **but only when the pack has no art of its own for the state**, because a
walk strip is already drawn side-on and squeezing it as well just makes the dog
look thin. `pose.facing` is a sprite instruction (mirror yourself); a 3D model
cannot mirror, only turn, so it uses yaw.

---

## 10. Window, tray and notifications

### 10.1 Window

540 × 760 default, resizable, 420 × 600 minimum. Title `DogPet — <pet name>`.
Top: the need bars. Bottom: Feed, Play, Walk (+ Vet in Real play) and ⚙
Settings. A `MenuBar` runs across the top with Pet / Mode / Care / Assets /
Window menus, refreshed each time one is opened rather than kept in step by
hand — which is a great deal harder to get wrong.

### 10.2 Tray

A `StatusIndicator` node with a `PopupMenu`: **Open DogPet**, **Pause
notifications for 1 hour** (checkable), **Quit**. Tooltip shows
`Hunger 62% · Happiness 40% · Energy 75%`, refreshed every 10 s. The alert icon
shows while anything is at Warning or worse. Left-click restores the window.

**Close-button behaviour** is a setting, default *minimise to tray*:
`get_tree().auto_accept_quit = false`, then on
`NOTIFICATION_WM_CLOSE_REQUEST` either hide to tray or save and quit. Quit from
the tray menu always saves first. The first time the window hides, a one-time
notification says "DogPet is still running in the tray."

**Two Windows quirks that must be respected** (see §17.3):

- `Window.hide()` does **nothing** to the root window on Windows. Minimise with
  `DisplayServer.window_set_mode(WINDOW_MODE_MINIMIZED)` and restore with
  `window_set_mode(WINDOW_MODE_WINDOWED)` **plus**
  `DisplayServer.window_move_to_foreground()` — the mode change alone leaves it
  minimised.
- The root `Window`'s own `visible`, `mode` and `has_focus()` all report
  **wrongly** while it is minimised. Ask `DisplayServer` instead when deciding
  whether the owner can see the window.

The tray does not work when the game is embedded in the editor. Check
`DisplayServer.has_feature(FEATURE_STATUS_INDICATOR) and not Engine.is_embedded_in_editor()`;
when unsupported, the close button quits normally.

While hidden or minimised, `Engine.max_fps = 5` and
`OS.low_processor_usage_mode = true`; both restored on show. The needs keep
ticking throughout.

### 10.3 Windows notifications

Godot cannot raise a Windows toast, so one is raised through **PowerShell 5.1**,
which ships with every Windows 10 and 11.

The script uses `Windows.UI.Notifications.ToastNotificationManager` with a
`ToastGeneric` payload. To avoid needing an app registration it uses
PowerShell's own AppUserModelID:
`{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe`.
Notifications therefore appear to come from "Windows PowerShell" — expected and
acceptable, because a portable app that installs nothing has no registered name
of its own.

It is launched with `OS.create_process` (not `execute`, so the game never
stutters) and the script is passed base64-encoded via `-EncodedCommand`, which
sidesteps every quoting problem between Godot and the shell.

**Critically, the title, body and icon path are *not* interpolated into the
script.** They travel as separate base64 blobs decoded inside PowerShell, and
the XML is built through the DOM with `CreateTextNode` and `SetAttribute`. See
RT-01 in §14.2 — doing this by string substitution was a remote-code-execution
hole.

An alternative `wscript` launcher exists for if a console window ever flashes.
It writes a tiny `.vbs` to the user's own data folder under an unpredictable
name and runs it with `wscript.exe` (window style 0), sweeping the previous one
away first.

**When to notify** — only while the window is hidden, minimised or unfocused:

- on crossing **Warning**: "Biscuit is getting hungry."
- on reaching **Critical**: "Biscuit is starving! Time to feed."
- at most once per crossing; the flag resets when the need is cared for, and
  clears when things get *better* so the next slide down is announced again;
- while Critical, a reminder every 30 min (Frequent) / 60 (Moderate) /
  120 (Long) / 60 s (Demo), floored at 10 s;
- never during "Pause notifications".

While the window is visible and focused the same messages appear as an **in-app
banner** instead, which slides in, sits for 7 s and leaves by itself.

---

## 11. Settings and persistence

### 11.1 The settings screen

Seven sections, rebuilt from scratch each time it opens (cheap, and nothing can
drift out of step with what is actually installed):

1. **Care** — Frequent / Moderate / Long radios, the full interval table so the
   choice is not a guess, and the ⚡ Demo Speed toggle.
2. **Pet** — name field, and a pack picker listing every valid pack with its
   name, kind and credit. *Switching pets keeps the needs — it is the same dog
   in a new body.*
3. **Rooms** — one picker per role, listing every room offering itself for it.
4. **Assets** — Open folder, Reload, Import pack…, Export pet…, Export room.
5. **Window** — close-button behaviour, Start minimised.
6. **Notifications** — on/off, Test notification, Resume if paused.
7. **About** — version, Godot version, the save and asset folder paths (click to
   open), and the credits.

**The credits block is a licence obligation.** Every installed pack's credit
line is shown exactly as its author wrote it, the active pet's first, with
`license_url` and `source_url` as clickable links **only when they are plain
`http(s)` addresses** — anything else is shown as unclickable text, because the
URI still has to be readable but a clicked link reaches `OS.shell_open` (RT-02).
The whole of `assets/CREDITS.txt` is shown underneath.

Every change saves immediately.

### 11.2 `saves/pet.json`

```json
{
  "format_version": 1,
  "pet_name": "Biscuit",
  "pet_pack_id": "pug_3d",
  "last_saved_unix": 1762000000.0,
  "hunger": 42.0, "happiness": 61.0, "energy": 18.0,
  "life": {
    "born_unix": 1761000000.0, "age_days": 5.8,
    "sickness": 0.0, "ill": false, "starving_seconds": 0.0,
    "alive": true, "died_unix": 0.0, "cause": 0
  }
}
```

Required keys for a save to be trusted: `hunger`, `happiness`, `energy`,
`last_saved_unix`.

**Write protocol** (`SaveFile.write_atomic`) — the ordering is the whole point:

1. write `pet.json.tmp`;
2. **copy** (never move) `pet.json` → `pet.json.bak.tmp`, then rename that over
   `pet.json.bak`;
3. if that fails, keep the **existing** `.bak` and record
   `last_write_kept_backup = false`;
4. rename `tmp` over `pet.json` — which Godot's rename *does* do on Windows;
5. if that fails, leave `pet.json` alone and return `false`. **Never delete it.**

**Read protocol** (`read_with_fallback`): try `pet.json`; if it is missing,
empty, unparseable or incomplete, try `pet.json.bak`; otherwise return empty,
meaning "start a fresh dog". `last_read_source` records which was used.

`history.json` goes through the same function, so the scoreboard gets the same
protection.

### 11.3 `saves/settings.json`

Written with the shipped defaults when missing, and any key an older file lacks
is filled in. Loaded values are merged over the defaults **only where the key is
known and the type matches**, so a typo cannot put a String where a number
belongs, and floats must additionally be finite.

```json
{
  "format_version": 1,
  "care_interval": "moderate",
  "play_mode": "casual",
  "demo_speed": false,
  "intervals_seconds": {
    "frequent": { "hunger": 2400.0, "happiness": 2700.0, "energy": 3000.0 },
    "moderate": { "hunger": 10800.0, "happiness": 12600.0, "energy": 14400.0 },
    "long":     { "hunger": 36000.0, "happiness": 39600.0, "energy": 43200.0 },
    "demo":     { "hunger": 45.0, "happiness": 50.0, "energy": 55.0 }
  },
  "action_effects": {
    "feed": { "hunger_set": 0.0, "happiness_delta": 5.0 },
    "play": { "happiness_set": 100.0, "energy_delta": -15.0, "hunger_delta": 5.0 },
    "walk": { "energy_set": 0.0, "happiness_delta": 10.0, "hunger_delta": 10.0 },
    "vet":  { "happiness_delta": -8.0 }
  },
  "action_seconds": { "feed": 5.0, "play": 8.0, "walk": 10.0, "vet": 7.0 },
  "real_play": {
    "age_day_intervals": 2.0,
    "starve_grace_intervals": 1.0,
    "sickness_rise_intervals": 1.5,
    "illness_mean_intervals": 8.0,
    "vet_visit_heals": 60.0
  },
  "critical_reminder_minutes": { "frequent": 30.0, "moderate": 60.0, "long": 120.0, "demo": 1.0 },
  "rooms": { "home": "", "eat": "", "play": "", "walk": "", "vet": "" },
  "close_button": "tray",
  "tray_notice_shown": false,
  "notification_launcher": "powershell",
  "start_minimized": false,
  "notifications_enabled": true
}
```

**This file is meant to be hand-edited**, which is why several values have
floors enforced in code (§17.2). The import size limits deliberately are **not**
in here: a limit the owner can edit is a limit an unpacked pack could edit, and
then it is not a limit.

### 11.4 `saves/history.json`

```json
{ "format_version": 1,
  "pets": [ { "name": "Biscuit", "born_unix": 0.0, "died_unix": 0.0,
              "age_days": 7.4, "cause": 1 } ] }
```

`cause`: 0 none, 1 starvation, 2 sickness. Entries without a `name` are
discarded on load; the list is sorted newest death first and trimmed to 200.

---

## 12. Testing strategy

Eight headless suites, **760 checks**, run as:

```
godot --headless --path . --script res://tests/test_needs.gd
```

Each is an `extends SceneTree` script printing `PASS`/`FAIL` per check and
exiting 0 or 1.

| Suite | Checks | Covers |
|---|---|---|
| `test_needs` | 170 | Drain rates, clamping, thresholds, catch-up (0 s / 1 h / 3 days / negative / capped), Demo exclusion, actions, corrupt-save fallback |
| `test_pets` | 111 | `PetPack` parsing, fit/scale geometry, integer scaling, `PetMotion` poses, image limits |
| `test_life` | 108 | Casual never kills, ageing, starvation, offline starvation split, illness, vet, broken tuning, saving |
| `test_packs` | 107 | Zip-slip and device names, zip sizes, pack links, inspect, round-trip, replace, broken zips |
| `test_scenes` | 96 | Real rooms, roles, backgrounds, props, tile sizes, action plan |
| `test_notify` | 68 | When to speak, what to say, tray display, icon pack, log rotation |
| `test_integration` | 55 | **Cold launches of the real app** |
| `test_history` | 45 | Empty, remembering, order and trimming, broken file, formatting |

### 12.1 Why `test_integration` exists

Every other suite tests a pure class on its own, and that is exactly why a v1.16
audit found **all eight** of its defects in the *wiring* between them: a death
announced to an empty room, actions that still worked on a dead dog, reminders
never scheduled. None of it was arithmetic, so none of it was visible to a pure
test.

It runs the **real autoloads and the real `Main` scene**. Each scenario is a
cold launch in its own Godot process, because a cold launch is the thing being
tested and the autoloads are singletons that load a save once — "what happens
when the app starts" cannot be tested twice in one start. The parent process
spawns one child per scenario (`--script … -- --scenario <name>`) and tallies
what it prints; a scenario that printed nothing is itself a failure.

Scenarios: `dead_save_shows_death_card`, `actions_refused_when_dead`,
`critical_at_launch_schedules_reminders`, `new_pet_clears_notifier_memory`,
`reminder_gap_is_clamped`, `overlapping_room_changes`, `panels_build`,
`clock_jumped_forward`.

Each child points `Paths` at a sandbox under the user data folder, and **every
scenario ends with the same check** — `saves never left the sandbox`. Getting
that wrong does not fail a test, it quietly eats the owner's dog; it has
happened once already, when the boot waited one frame for the engine instead of
waiting for `Paths` to have actually run.

### 12.2 The constraint that shapes everything

As §5.1 says: a script naming an autoload cannot compile under `--script`.
`test_integration` works around it by fetching the autoloads out of the tree
(`root.get_node("Needs")`) rather than naming them, and by waiting for
`Paths.base_dir` to be non-empty before touching anything — a `--script` run
reaches `_initialize` *before* the autoloads have had their `_ready`.

---

## 13. Build and packaging

`tools/build.ps1` (PowerShell 5.1), with `-GodotPath` and `-SkipTests`:

1. Check Godot is findable and **that export templates are installed** — their
   absence is the usual reason a first build fails, so it is reported plainly
   rather than letting Godot's error through.
2. Read the version from `project.godot`.
3. `godot --headless --path … --import` to prepare the caches. **Before the
   tests, not just before the export** — a fresh clone has no `.godot` folder,
   and without it Godot cannot resolve the class names the scripts use, and the
   tests are scripts too.
4. Run **every** `tests/test_*.gd`, found by globbing rather than from a list —
   a hand-written list silently stopped covering two suites when they were
   added, so a failure in either would not have stopped a release.
5. Write a `.gdignore` at the top of `build/` (see §3.1 / bug **D-2**).
6. `--export-release "Windows Desktop"` to `build/DogPet-v<ver>/DogPet.exe`.
7. Copy `assets/` in beside the exe, stripping `.gdignore` and `_backup/`.
8. Generate `README.txt` for the player, with the credits copied from
   `assets/CREDITS.txt`, written **without a BOM** and with CRLF line endings.
9. `Compress-Archive` **the staging folder itself**, not its contents, so the
   zip holds one `DogPet-v<ver>` folder (bug **D-5**).
10. Print the zip path and size.

**Export preset:** Windows Desktop, x86_64, `embed_pck=true` (single-file exe),
icon `res://icons/app_icon.ico`, product name DogPet,
`exclude_filter="tests/*"`.

One PowerShell subtlety worth keeping: capturing a native program's stderr in
Windows PowerShell wraps every line as an error, and with
`$ErrorActionPreference = "Stop"` that aborts the build. The tests deliberately
provoke engine errors — `test_needs` feeds a corrupt file to the JSON parser on
purpose — so the preference is relaxed around the test loop and **the exit code
is what decides**.

---

## 14. Bugs, holes and how they were fixed

This section is the hard-won part. §14.1 covers defects found during
development; §14.2 covers a full external security audit. For each: what was
wrong, how it was fixed, and **why that fix rather than another**.

### 14.1 Defects found during development

#### D-1 — Scenery towered over the dog (v1.10)

Drawn scenery (trees, bushes, clouds, path stones) was sized in **fixed
pixels**, so at a larger window the dog shrank relative to it and the
proportions fell apart.

**Fix:** size everything as a fraction of the view's height.
**Why:** the dog's own on-screen size is derived from the view, so deriving the
scenery from the same quantity is the only way the two stay in agreement at any
window size.

#### D-2 — Every build swallowed the previous one (v1.11)

`build/` lives inside the project, and the assets staged into it have had their
`.gdignore` stripped on purpose — the player has no use for it. That left Godot
free to import every staged copy and pack it into the **next** build, so the exe
grew by several megabytes every time.

**Fix:** write one `.gdignore` at the top of `build/`.
**Why:** one marker keeps the whole folder out of Godot's sight, where stripping
per-file markers cannot.

#### D-3 — Real play was unplayable: the death nobody was told about (v1.17)

Seven related defects, all in the **wiring** rather than the arithmetic:

1. A dog that died while the app was closed emitted `pet_died` during the
   catch-up, **before any scene existed**, so the signal was lost. The window
   came up frozen, with no card and no way to start another dog. *The save was
   unplayable for good.*
   **Fix:** `Main._ready` checks `Needs.life.alive` directly, as well as
   connecting to the signal. **Why:** a signal cannot be the only channel for
   something that happens before there are listeners; the state has to be
   readable too.
2. The catch-up credited the dog with starving for the **whole** absence.
   **Fix:** `NeedsModel.seconds_at_critical()` splits the absence and only the
   part after hunger reached the bad end counts (§7.1).
3. Actions still worked on a dead dog.
   **Fix:** guards in `ActionRunner.run`, `Needs.apply_action` and
   `Needs.take_to_vet` — three doors, all locked. **Why:** the buttons being
   disabled is a UI fact, not an invariant; a keyboard shortcut or a press in
   the same frame as the death got through.
4. A new dog's bars opened reading "Needs care now" in red, inherited from the
   dog before.
   **Fix:** `start_new_pet` *announces* the reset rather than quietly writing
   over the levels, because the bars and the notifier both learn what a need is
   doing from `threshold_crossed`.
5. A need already Critical at launch was never mentioned again.
   **Fix:** `Notifier._adopt_current_levels()` (§5.6).
6. The bars promised care in two hours for a dog that had died.
   **Fix:** "no longer counting".
7. The "While you were away" card reported a dead dog as merely starving.
   **Fix:** a death-aware reaction line.

#### D-4 — Three settings values that could wreck the app (v1.18)

`settings.json` is designed to be hand-edited, and three values had no floor:

- A **zero reminder gap** meant a reminder every frame — and every reminder
  raised while the window is hidden starts a PowerShell process, so roughly
  **sixty new processes a second**. → floored at 10 s.
- A **negative action length** made Godot's timer fire on the very next frame,
  so the animation never played and the dog was home before it had left. →
  floored at 0.5 s.
- The notifier kept its memory of the previous dog, so a new dog's first warning
  read as an improvement on the dead one's Critical and was swallowed silently.
  → cleared on `pet_started`.

**Why the floors live in `CareSettings`:** they were moved out of `Settings`
(a node) into the pure class precisely so the tests could reach them.

#### D-5 — The zip scattered itself into Downloads (v1.21)

`Compress-Archive` was given the staging folder's *contents*, so the zip held
the exe, `assets/` and `README.txt` loose at the top. Unzipping into Downloads
scattered a 113 MB exe and an assets folder in among everything else.

**Fix:** pass the staging folder itself. One word.
**Why it matters:** "unzip it anywhere and run it" is the whole shape of this
app.

#### D-6 — Overlapping room transitions (v1.20)

Two transitions at once trod on each other: the older one freed the room the
newer one was showing, cleared the busy flag early, and announced a room that
had already been left. Picking a room in Settings during an action was silently
dropped.

**Fix:** a generation counter — each call takes a ticket, and a call that finds
itself overtaken steps aside quietly. The wait is on a **timer rather than on
the tween**, because a second call frees the room the first was animating, which
kills its tween without ever emitting `finished` — and the first call would then
wait for it forever, holding `_busy` true behind it.

### 14.2 The security audit (13 findings)

An external red-team audit at v1.21 read all 43 scripts line by line and found
**13 defects: 2 Critical, 2 High, 3 Medium, 5 Low, 1 Info.** All are fixed
(v1.22–v1.25). Tests went 637 → 760.

The audit's own conclusion is the single most useful sentence in it:

> **Every finding of substance was on a trust boundary, and the pure arithmetic
> layer was clean.** `assets/` being loose and shareable is the app's best
> feature and its entire attack surface, and pack data was being trusted the way
> typed-in text is trusted.

Full write-up in `redteam/`: `00-findings-report.md`, `99-master-report.md`, a
document per finding in `fixes/`, and 16 reproduction probes in `tests/`.

---

#### RT-01 — Critical — The pet's name ran as PowerShell

`_toast_script` built the notification script as text and substituted the title
into it:

```gdscript
$doc.LoadXml(@"
<toast>…<text>{TITLE}</text>…</toast>
"@)
""".replace("{TITLE}", _xml_escape(title))
```

`@"` … `"@` is PowerShell's **expandable** here-string, and because the
substitution happened in GDScript the name was physically in the script's source
*before PowerShell parsed it*. So `$(...)` in a pet name was a subexpression
PowerShell evaluated and ran. `_xml_escape` covered `& < > " '` but not `$`.

**Proven** with a name of `$(Set-Content -Path … -Value pwned; Rex)`, which
wrote the file.

The name arrives from the rename dialog, from `pet_name` in a **shared
`pet.json`**, and — for the icon variant, via `_file_uri` — from an **imported
pack's `ui.json`**.

**Fix:** stop interpolating entirely. The title, body and icon path travel as
base64 in single-quoted PowerShell strings and are decoded inside the script;
the XML is built through the DOM with `CreateTextNode` and `SetAttribute`.
`_xml_escape` was **deleted**.

**Why that fix:** escaping harder was the wrong instinct. The escaping was
correct *for XML* and the text was placed where PowerShell read it first — two
parsers saw it in sequence and it only ever satisfied the second. Base64 cannot
terminate a single-quoted string, and a single-quoted string does not expand
`$`; the DOM escapes at the layer that actually knows what needs escaping.
Deliberately **not** done: filtering `$` out of pet names, because after this
fix "Mr. $parkles" is both reasonable and safe.

#### RT-02 — Critical — A pack's licence link launched programs

`CreditsList._link` handed `license_url` straight to `OS.shell_open`, which is
`ShellExecuteW`: it opens documents, launches executables, resolves bare command
names off the `PATH`, and hands strings to any registered protocol handler.
Nothing checked the scheme. The button's visible text is the *licence name*
("CC-BY 3.0"), so a hostile pack showed an ordinary-looking licence link.

**Proven** by pointing it at a `.cmd` file, which ran. Variants needing no file:
`calc.exe`, `\\attacker\share\payload.exe`.

**Fix:** new pure class `PackLinks.web_url()` allows only `http://` and
`https://` (case-insensitive, trimmed, no whitespace or control characters, and
not a bare scheme). Anything else is rendered as **plain unclickable text**.

**Why that fix:** an allow-list of the two schemes that belong in a credit, not
a deny-list — which schemes are dangerous depends on what is installed on the
owner's machine, which the app cannot know. And the refused URL is still
*shown*, because displaying the licence URI is part of the attribution;
dropping it would trade a security hole for a licensing one.

**Where it lives, and why that matters:** the plan put the validator in
`CreditsList`. That proved untestable — `CreditsList` names the `AssetLibrary`
autoload, so it cannot compile under `--script` (§5.1). A security rule that can
never be tested is not much of a rule, so it moved to its own pure class.

#### RT-03 — High — Import pack: unbounded decompression (zip bomb)

`inspect` read the manifest with no size check: `reader.read_file(manifest).get_string_from_utf8()`.
`extract` did the same per entry.

**Proven:** a **597 KB** zip holding a `pet.json` of 600 MB of spaces followed by
a valid manifest drove peak memory to **3,024 MB** and froze for 4.4 s — and
`inspect` **accepted** the pack, because the JSON parser skips the padding. At
4 GB of padding (zip still ~4 MB) it is an out-of-memory crash, triggered the
moment the file is chosen, *before* the "Replace?" confirmation.

**The engine detail that makes the fix sound:** `ZIPReader` in 4.7.2 offers no
size API at all. But `read_file` asks minizip for the entry's
`uncompressed_size`, resizes its buffer to exactly that, and reads at most that
many bytes — so **the declared size *is* the allocation**. A zip that
under-declares cannot make Godot allocate more; it just gets truncated.
Checking the declaration therefore bounds memory completely.

**Fix:** new pure class `ZipSizes` reads each entry's declared uncompressed size
from the zip's **central directory** with `FileAccess`, refusing outright
anything it cannot be confident of — no EOCD, a truncated index, or Zip64 in use
(Zip64 is for archives over 4 GB or 65,535 entries; a pet pack is neither).
`PackArchive` then enforces `MAX_MANIFEST_BYTES` 256 KB, `MAX_FILE_BYTES` 64 MB,
`MAX_TOTAL_BYTES` 256 MB and `MAX_ENTRIES` 512, before the first read.

**Result:** `inspect` allocates **1 KB in 1 ms** instead of ~3 GB in 4.4 s.

**Why hard-coded limits:** a limit the owner can edit is a limit an unpacked
pack could edit.

**A gap the tests caught:** a 263 KB manifest passes the 64 MB per-file ceiling
onto disk — harmless to copy, but `PetPack.load_from_dir` re-reads and re-parses
it on *every* `AssetLibrary.reload()`. The manifest ceiling now applies in
`extract` too.

#### RT-04 — High — A zero grace period killed a fed dog, forever

```gdscript
var grace: float = hunger_interval * _number(config, "starve_grace_intervals", 1.0)
if starving_seconds >= grace:
    _die(Cause.STARVATION, now_unix)
```

With `grace = 0.0`, `starving_seconds` is **also** `0.0` — the line above resets
it for a dog that is not hungry — and `0.0 >= 0.0` is true. A perfectly fed dog
died of starvation on the first processed frame. And again on the first frame
after the owner started another, appending a `history.json` record each time.
Real play became unplayable with nothing on screen to say why.

**Fix, in two layers:**

- `CareSettings.real_play_from()` floors `starve_grace_intervals` (0.1),
  `age_day_intervals` (0.1 — zero divides by zero and makes the age infinite)
  and `vet_visit_heals` (1.0 — a vet that heals nothing leaves an ill dog with
  no way back). The dictionary is **duplicated**, so clamping for a read cannot
  rewrite `Settings.data` and get saved over the owner's file.
- `LifeModel.advance` refuses a non-positive grace whatever it is handed.

**Why two layers:** `LifeModel` is the one model in this app where being wrong
costs somebody their pet, and it should not depend on its caller for that.

**Why `sickness_rise_intervals` and `illness_mean_intervals` are deliberately
*not* floored:** every use of them already guards against zero, where they mean
"an illness never gets worse" and "the dog never falls ill". A floor there would
*introduce* a death rather than prevent one — the wrong direction to be wrong in
— and would take away a setting somebody might be using on purpose.

#### RT-05 — Medium — A room with tiny tiles froze the window

`_draw_tiled_background` steps by the tile's own drawn size, so the cost of a
room is the window's area divided by the tile's. Measured:

| Window | Tile | Draw calls / frame |
|---|---|---|
| 540×760 | 32×32 | 425 |
| 540×760 | 4×4 | 25,785 |
| 540×760 | 1×1 | 410,940 |
| 2560×1440 | 1×1 | **3,688,960** |

A hard freeze — and the owner cannot reach Settings to pick another room from
inside a frozen window, while the choice is remembered in `settings.json`, so
restarting lands straight back in it.

**Fix, in two layers:** `ScenePack` measures each tile from its PNG header and
raises `tile_scale` until the drawn tile is at least `MIN_TILE_PIXELS` (8) on
both axes; `SceneView` caps either loop at `MAX_TILES_PER_AXIS` (256) and
stretches one tile instead if exceeded.

**Why two layers:** the loader handles every case where the size can be read
from the header; the drawing cap covers the case it cannot — a picture that is
not a PNG, whose size is only known once decoded.

**Why raise rather than refuse:** a pack with small tiles is far likelier
well-meant than hostile, and pixel art is scaled by whole numbers everywhere
here anyway. 1×1 now costs 14,560 calls at 2560×1440 — a **253× reduction** —
and the shipped 32×32 rooms are untouched.

#### RT-06 — Medium — The last good save was deleted before its replacement

```gdscript
if FileAccess.file_exists(bak_path):
    DirAccess.remove_absolute(bak_path)          # old backup gone first
if DirAccess.rename_absolute(path, bak_path) != OK:
    DirAccess.remove_absolute(path)              # and now the only good save
```

Three faults: the old backup went **before** anyone knew a new one could be
made; when the rename failed the only good save was deleted and the result of
that deletion ignored; and the function still returned `true`.

On Windows that rename fails routinely whenever something holds the file open —
antivirus mid-scan, OneDrive or Dropbox syncing, Explorer's preview pane — or
when `.bak` has picked up a read-only flag.

**Proven:** with `pet.json.bak` made unusable, the save reported success, the
backup was gone, and a subsequent corruption left `recovered dog: <THE DOG IS
GONE>`.

**Fix:** copy-then-replace (§11.2), plus `last_write_kept_backup` so
`Needs.save_now` can warn that the net under the next write is older than it
should be. `PetHistory.save_records` was routed through the same function.

**Why the order:** nothing good may be destroyed before its replacement is in
place. The comment that justified the old order — "Windows will not rename onto
a file that already exists" — **is wrong for this build**; checked directly
(§17.3).

#### RT-07 — Medium — A forward clock jump killed the pet

`elapsed_between` floors at zero, guarding a clock that moved **backwards**. A
clock that jumps **forwards** — the likelier fault, since a dead CMOS battery
usually reads 2099 rather than 1970 — produced an arbitrarily large `elapsed`
that flowed into the catch-up with no ceiling. A save a year old meant a year of
starvation credited during the catch-up, so in Real play the dog was dead before
the window opened. The same path also produced a `NaN`: with an infinite
`elapsed`, `well_fed_for = elapsed - starving_for` is `inf - inf`, and
`NaN > 0.0` is false, so the well-fed leg was silently skipped.

**The planned fix was wrong, and the test proved it.** A 30-day cap was
implemented; the dog still died, because 30 days of starvation is far past any
grace period. And **no cap can work**, because the requirements pull apart: to
stop a clock jump killing the pet the cap must be *below* one grace period; to
leave genuine absences alone it must be far *above* one.

**What reconciles them:** a catch-up does two different kinds of thing.

- **Reversible** — the needs drain. A maxed bar is one click from fixed.
- **Irreversible** — ageing, illness, death.

The app cannot tell a bad clock from a real year away; that is not solvable. But
it can decline to take an *irreversible* action on a number it does not believe,
while still taking the reversible one.

**Fix:** `NeedsModel.capped_elapsed()` clamps at `MAX_CATCH_UP_SECONDS`
(30 days) and treats a non-finite value as zero. Past the cap the needs still
drain in full and `_catch_up_life` is **skipped entirely**. The log says so and
the away card tells the owner the clock looked wrong.

**The behaviour change, stated plainly:** a dog genuinely left for forty days now
survives to be looked at rather than being found dead. Everything up to thirty
days is unchanged, and a starving dog still dies within one grace period of the
owner opening the window. **This was put to the owner and kept**, and is recorded
in `CLAUDE.md` §6.3 beside the original offline-starvation decision it qualifies
— so the spec and the code cannot drift apart on it.

#### RT-08 — Low — "Replace this pack" merged into it instead

`_do_import` backed the old folder up and extracted straight into it, and
`extract` removes nothing — so every file the new pack did not happen to
overwrite survived. A `pet.json` that no longer listed a walk strip, with the old
`walk.png` still beside it. The dialog said "replaced"; the behaviour was a
merge.

**Fix:** `PackArchive.empty_folder()` empties the target — **only after
`_back_up` has confirmed success**, which is the same ordering principle as
RT-06. Moved to `PackArchive` because `PackTransfer` is a Node naming three
autoloads and so is untestable.

#### RT-09 — Low — Infinities from a save file reached the screen

JSON cannot write `inf`, but it can write `1e999`, which Godot's parser reads as
`inf` — and `JSON.stringify` writes it back out as `1e99999`, so **once an
infinity is in a save file it round-trips and stays there**. Results:

```
format_age(INF)       = -9223372036854775808 days old
format_countdown(INF) = ~-9223372036854775808m
format_date(1e999)    = 27 Jan -292277022657, 08:29
```

`int(floor(inf))` is undefined and lands on `INT64_MIN`. Nothing crashed, but the
scoreboard — the memorial feature — printed nonsense of exactly the kind that
makes an owner think the app has lost their dog.

**Fix, at both ends:** `is_finite` added to `LifeModel._number`,
`NeedsModel.from_dictionary` and `CareSettings.merge_into`'s float branch; and
`format_age`, `format_countdown`, `format_duration` and `format_date` now answer
"unknown" for anything non-finite **or absurd** (past `MAX_PLAUSIBLE_DAYS`,
`MAX_PLAUSIBLE_SECONDS`, `MAX_PLAUSIBLE_UNIX`).

**Why both ends:** the boundary checks should mean the formatters never see one,
but the formatters are what the owner actually reads, and "unknown" is a fine
thing for a memorial to say about a figure nobody can establish.

#### RT-10 — Low — The PNG size guard skipped the very files it existed for

`png_size_from_header` read the two 32-bit header fields correctly as 64-bit
GDScript integers and then packed them into a `Vector2i` — **whose components
are 32-bit**. A declared width of `4294967295` became `-1`, and `is_too_large`
treats `size.x <= 0` as "not known", documented as never too large. So the file
went to the decoder: exactly what the guard existed to prevent.

**Fix:** **saturate instead of truncating** — `mini(value, MAX_SIDE)` with
`MAX_SIDE = 0x7FFFFFFF`. Honest (the file really is at least that big), still
positive so it reads as *known*, and refused on the spot — while
`Vector2i.ZERO` keeps meaning "could not be read".

Also deleted `PetPack._png_size`, a **second** header reader that checked
neither the PNG signature nor the size, so an enormous sheet was listed as
usable and only refused later. One reader now.

#### RT-11 — Low — The log rotated only at startup

`_rotate_if_large` was called once, from `_ready`. The 1 MB ceiling was enforced
at launch and never again — and this app is meant to be left in the tray for
days.

**Fix:** a running byte count in `_write`, rotating when it passes `MAX_BYTES`,
seeded from the real file size at startup and reset on rotation.

**Why counted rather than measured:** this script's whole design is one open,
one line, one close; a `get_length()` per line would quietly make it something
else.

#### RT-12 — Low — `saves/notify.vbs` was written, then executed

With the `wscript` launcher, every notification wrote `saves/notify.vbs` and ran
it. The base64 payload itself is safe, but the **file** was a script at a
predictable path in a folder whose permissions depend on where the app was
unzipped. Unzip DogPet somewhere several accounts can reach — a shared folder, a
`C:\Tools\DogPet` left writable by `Users`, a USB stick — and anyone who can
write there can replace it and have it run as the owner.

**Fix:** write it to `OS.get_user_data_dir()` (per-user whatever the app
folder's permissions are), under an unpredictable name, and sweep the previous
one away at startup and before each new one.

**A defect introduced while fixing it:** the plan used
`get_tree().create_timer(...)` to delete the file. `get_tree()` is **null** in an
autoload before it enters the tree, and a notification genuinely can be raised
from there. Sweeping needs nothing but a folder listing, so the timer was
removed. *Caught by running the probe, not by reading the diff.*

Fixing RT-01 mattered far more here: with RT-01 open this route carried the same
injected script.

#### RT-13 — Info — Windows device names passed the zip-entry check

`is_safe_entry` correctly refused `..`, absolute paths and drive letters, but not
`CON`, `NUL`, `COM1.png` — which Win32 resolves to **devices** whatever folder
they sit in and whatever extension they carry.

Reported **Unconfirmed**, honestly: `FileAccess.open` on such a path fails and
`extract` handles that properly. The one case that could not be ruled out is a
machine with a real `COM1`, where opening a serial port can block.

**Fix:** a refusal list matched on the part before the first dot,
case-insensitively, inside the loop that already walks the parts — so
`console.png`, `aux_bits/` and `nullify.png` are still allowed.

**Why fix an unconfirmed finding:** it is tidying a gap in an otherwise careful
check, and "probably fine" is worth five lines to be rid of.

### 14.3 What was attacked and held

Worth recording, so a rebuild does not undo protections that are already right:

- **Zip-slip.** `..`, `..\`, mixed separators, drive letters, nested `a./../b`,
  leading `/` — all refused before anything is unpacked, and `extract`
  re-checks rather than trusting `inspect`.
- **Corrupt and truncated saves.** Empty, truncated JSON, an array instead of an
  object, missing required keys, wrong types per field — all fall back cleanly.
- **`NaN` in a save.** `JSON.stringify` replaces `NaN` with `null` and warns, so
  a `NaN` cannot corrupt `pet.json` into an unparseable file and take the `.bak`
  down with it.
- **Broken packs.** Missing manifest, invalid JSON, unknown `kind`, missing
  model or sheet, a sheet whose width does not divide by its frame count, no
  `idle`, unknown state names, zero/negative `target_height` and
  `display_height_px`, unknown background type, unknown role, missing props —
  every one described and either skipped or fallen back.
- **Division by zero.** `seconds_to_critical`, `starving_fraction`,
  `seconds_to_fatal`, `integer_scale` and `ScenePainter._layer_range` all guard
  their divisors, and the layer range is bounded by view width over spacing.
- **Overlapping transitions** (D-6) and **actions on a dead dog** (D-3) both
  hold.
- **The `--script` sandbox** genuinely keeps the suites off the real `saves/`.

---

## 15. Roadmap

### 15.1 Phases as built

| Version | Phase | What landed |
|---|---|---|
| v1.0 | — | Starter kit and build blueprint |
| v1.1 | — | Pug credit and licence links |
| v1.2 | — | Git repo and auto-save conventions |
| v1.3 | **0** | Public GitHub repo, README, MIT `LICENSE` |
| v1.4 | **1** | Skeleton: `project.godot`, `Paths`/`Log`/`Settings`/`Needs`, `NeedsModel`/`CareSettings`/`SaveFile`, `Main`/`NeedsBar`/`AwayCard`, debug screen, 129 checks |
| v1.5 | **2** | Pets: `AssetLibrary`, `PetPack`/`PetLoader`/`PetPose`/`PetMotion`/`PetAnimator`/`PetView`, `builtin/pets/`, 222 checks |
| v1.6 | **3** | Rooms and actions: `ScenePack`/`SceneView`/`SceneStage`/`ActionPlan`/`ActionRunner`, `builtin/scenes/`, 300 checks |
| v1.7 | **4** | Tray and notifications: `Notifier`/`Tray`, `UiPack`, `NotificationRules`, `Banner`, `builtin/ui/`, 362 checks |
| v1.8 | **5** | Settings and pack sharing: `SettingsPanel` (7 sections), `PackArchive`/`PackTransfer`/`CreditsList`, 418 checks |
| v1.9 | **6** | Shipped: export preset, `build.ps1`, edge-case pass, first release |
| v1.10 | — | Screenshots; scenery scales with the window (**D-1**) |
| v1.11 | — | Build stops growing (**D-2**) |
| v1.12 | **7** | Menu bar, rename dialog, `HelpPanel` |
| v1.13 | **8** | Casual and Real Pet: `LifeModel`, Sickness bar, Take To Vet, vet room, `generated`/`room` style |
| v1.14 | — | Sickness bar icon |
| v1.15 | — | A nurse in the vet clinic |
| v1.16 | **9** | Scoreboard: `PetHistory`, `Scoreboard`, 542 checks |
| v1.17 | — | Real play fixes (**D-3**), 560 checks |
| v1.18 | — | Three settings floors (**D-4**), 576 checks |
| v1.19 | — | `test_integration`: tests that start the whole app, 606 checks |
| v1.20 | — | Image size limit, overlapping rooms (**D-6**), four scripts split out, 637 checks |
| v1.21 | — | The zip unpacks into a folder of its own (**D-5**) |
| v1.22 | — | **Audit:** RT-01, RT-02 (the two Criticals) |
| v1.23 | — | **Audit:** RT-03, RT-04 (the two Highs), 686 checks |
| v1.24 | — | **Audit:** RT-05 … RT-13 (the remaining nine), 760 checks |
| v1.25 | — | The catch-up bound written into `CLAUDE.md` |
| v1.26 | — | The audit write-up joins the repo |

### 15.2 Not done, deliberately

Each with its reason, so a rebuild does not "fix" something that was decided:

- **`Settings._save` is not atomic.** A mangled `settings.json` self-heals on the
  next launch from the merged defaults, so it costs preferences at worst, never
  the dog.
- **Files the owner drops into `assets/` by hand have no size limit.** That is
  their own folder and they are invited to fill it; the *import* path is the one
  that takes files from strangers.
- **`sickness_rise_intervals` / `illness_mean_intervals` have no floors.** Zero
  already means "never happens", and a floor would introduce a death (RT-04).
- **Pet names may contain anything**, including `$`. After RT-01 they are safe.
- **`PetPack`/`ScenePack` store pack URLs verbatim.** Nothing acts on them
  unchecked now, and parsing is their job.
- **No Zip64 support on import.** It exists for archives over 4 GB or 65,535
  entries; a pack is neither, and supporting it would only let bigger things
  through the size check.
- **Notifications say "Windows PowerShell".** Avoiding it means registering an
  application, which a portable app that installs nothing cannot do.
- **The taskbar button stays visible** when minimised to tray. Godot exposes no
  flag to drop it.

### 15.3 Open and unverified

- **Not re-tested since v1.21:** the real tray icon, close-to-tray, and the
  packaged build from `tools/build.ps1`. Everything since has been verified
  headlessly plus live PowerShell toasts. **A run of the shipped zip on a clean
  folder is the outstanding manual test.**
- No GitHub Release has been cut for v1.22–v1.26.
- `redteam/` is committed as of v1.26; the flaws it documents are all fixed and
  none of the versions carrying them was ever released.

### 15.4 Plausible next work

Not planned, but the natural candidates: a `sleep` state driven by time of day
(the animation exists and is unused); more shipped rooms per role, now that
several can offer themselves for one slot; a built-in fallback for the vet room,
which is the one role without one; localisation (all strings are currently
inline); and an `.exe`-side signature so notifications can carry DogPet's own
name.

---

## 16. Recommended build order for a rebuild

Build in this order, stopping to test at each step. It mirrors how the app was
actually built, and each phase leaves something runnable.

1. **Project skeleton.** `project.godot` per §2.1. Create `assets/`, `saves/`,
   `docs/`, `build/` each with a `.gdignore`. Add `icons/`.
2. **`Paths` and `Log`.** Get the base-folder logic, the write probe, the
   fallback, `startup_notes` and `tool_script_mode` right **first** — everything
   else sits on them.
3. **`NeedsModel` + `CareSettings` + `SaveFile`, and `test_needs`.** Pure, no
   nodes. Write the tests alongside. This is the heart of the app and the
   cheapest place to be correct.
4. **`Settings` and `Needs`.** Thin wrappers. Add autosave, the offline
   catch-up and the signals.
5. **`Main.tscn` + `NeedsBar.tscn` + `AwayCard.tscn`.** A plain debug screen:
   three bars, countdowns, the interval picker, the Demo toggle, instant care
   buttons. *Testable by eye for the first time.*
6. **`PetPack`, `PetLoader`, `PetMotion`, `PetPose`, `PetAnimator`,
   `PetView.tscn`.** Both pet kinds, the AABB normalising, procedural states,
   the mood state. Add `builtin/pets/`. `test_pets`.
7. **`ScenePack`, `SceneView`, `SceneStage`, `ScenePainter`, `ActionPlan`,
   `ActionRunner`.** All three background types, props, transitions, the three
   action sequences. Add `builtin/scenes/`. `test_scenes`.
8. **`UiPack`, `NotificationRules`, `Notifier`, `Tray`, `Banner.tscn`.** Tray
   icon, close-to-tray, toasts, banners, reminders, pause, low-power.
   **Build the toast script with base64 + DOM from the start** (RT-01). Add
   `builtin/ui/`. `test_notify`.
9. **`SettingsPanel`, `UiBits`, `PackArchive`, `ZipSizes`, `PackLinks`,
   `PackTransfer`, `CreditsList`, `ImageLimits`.** The seven sections, import
   and export with **the size limits and the entry safety in place from the
   start**, and the credits with `PackLinks` validation. `test_packs`.
10. **`AppMenu`, `HelpPanel`.** The menu bar and the in-app instructions.
11. **`LifeModel`, `DeathCard.tscn`, the Sickness bar, the vet room.** Real play,
    with the floors from `CareSettings.real_play_from` in place from the start
    (RT-04). `test_life`.
12. **`PetHistory`, `Scoreboard.tscn`.** `test_history`.
13. **`test_integration`.** Do not leave this to last in spirit — the wiring
    between correct parts is where the expensive bugs live (§12.1).
14. **Export preset and `build.ps1`.** Then the edge-case pass: missing
    `assets/`, a read-only folder, a corrupt save, a broken `pet.json`.
15. **Run the shipped zip from a clean folder on the desktop.** The one test
    nothing else substitutes for.

### 16.1 Invariants to preserve

If you change nothing else, keep these:

1. Pure logic has **no** autoload references (§5.1).
2. The offline catch-up **never** uses Demo speed.
3. The irreversible half of a catch-up is skipped when the clock is not
   believable (RT-07).
4. Nothing is destroyed before its replacement is in place (RT-06, RT-08).
5. Untrusted values are **never** interpolated into another language (RT-01).
6. Only `http(s)` reaches `OS.shell_open` from pack data (RT-02).
7. A size is checked **before** the allocation (RT-03, §8.5).
8. Security limits are hard-coded, not in `settings.json`.
9. A broken pack is described and skipped; the app never crashes on assets.
10. Every pack's `credit` is displayed verbatim — it is a licence obligation.

---

## 17. Appendices

### 17.1 Every tuning constant

**Needs** (`NeedsModel`): `WARNING_BADNESS` 70.0 · `EPSILON` 0.001 ·
`RESTLESS_ENERGY` 85.0 · `SAD_HAPPINESS` 25.0 · `SAD_HUNGER` 85.0 ·
`HAPPY_AFTER_ACTION_SECONDS` 4.0

**Needs wrapper** (`Needs`): `AUTOSAVE_SECONDS` 30.0 ·
`AWAY_CARD_MIN_SECONDS` 60.0 · `MAX_CATCH_UP_SECONDS` 2,592,000 (30 days) ·
`DEFAULT_PET_NAME` "Biscuit" · `DEFAULT_PET_PACK_ID` "pug_3d"

**Life** (`LifeModel`): `PUPPY_DAYS` 3.0 · `YOUNG_DAYS` 10.0 · `ADULT_DAYS`
40.0 · `ILLNESS_START` 4.0 · `MAX_PLAUSIBLE_DAYS` 1,000,000

**Floors** (`CareSettings`): `MIN_REMINDER_SECONDS` 10.0 · `MIN_ACTION_SECONDS`
0.5 · `MIN_STARVE_GRACE_INTERVALS` 0.1 · `MIN_AGE_DAY_INTERVALS` 0.1 ·
`MIN_VET_VISIT_HEALS` 1.0

**Text** (`NeedsText`): `MAX_PLAUSIBLE_SECONDS` 3,153,600,000 (100 years)

**History** (`PetHistory`): `MAX_RECORDS` 200 · `MAX_PLAUSIBLE_UNIX`
95,617,584,000 (~year 5000)

**Images** (`ImageLimits`): `MAX_PIXELS` 33,554,432 · `MAX_SIDE` 0x7FFFFFFF ·
`HEADER_BYTES` 24

**Packs** (`PackArchive`): `MAX_MANIFEST_BYTES` 262,144 · `MAX_FILE_BYTES`
67,108,864 · `MAX_TOTAL_BYTES` 268,435,456 · `MAX_ENTRIES` 512

**Scenes**: `ScenePack.MIN_TILE_PIXELS` 8 · `ScenePack.DEFAULT_PET_SPOT`
(0.5, 0.82) · `SceneView.MAX_TILES_PER_AXIS` 256 ·
`SceneStage.TRANSITION_SECONDS` 0.5 · `ScenePainter.SKY_BANDS` 48 ·
cloud spacing 0.52 / parallax 0.25 · tree spacing 0.46 / parallax 0.6 ·
bush spacing 0.34 · stone spacing 0.17

**Animation**: `PetAnimator.BLEND_SECONDS` 0.3 · `FIDGET_MIN_GAP` 4.0 ·
`FIDGET_MAX_GAP` 9.0 · `PetMotion.BREATH_SECONDS` 3.0 · `HAPPY_HOP_SECONDS`
0.45 · `HAPPY_HOPS` 3 · `FIDGET_SECONDS` 0.9 · `PetView.SPOT_TWEEN_SECONDS`
0.5 · `SHADOW_WIDTH` 128 · `SHADOW_HEIGHT` 56

**Window and tray**: `Main.MIN_WINDOW_SIZE` (420, 600) · `Tray.HIDDEN_FPS` 5 ·
`Tray.TOOLTIP_SECONDS` 10.0 · `Notifier.PAUSE_SECONDS` 3600.0 ·
`Banner.SHOW_SECONDS` 7.0 · `Banner.SLIDE_SECONDS` 0.25 · `Log.MAX_BYTES`
1,048,576

### 17.2 JSON schema summary

| File | Required | Notable optional |
|---|---|---|
| `pet.json` (model3d) | `kind`, `model`, `credit` | `id`, `name`, `target_height`, `rotation_y_degrees`, `animations`, `license`, `license_url`, `source_url` |
| `pet.json` (sprite2d) | `kind`, `animations.idle`, `credit` | `pixel_art`, `display_height_px`, `faces`, same licence fields |
| `scene.json` | `role` (or folder name), `background` | `name`, `props[]`, `pet_spot`, `transition`, licence fields |
| `ui.json` | `tray_icon` | `tray_icon_alert`, `icons{}`, `buttons{}`, `icon_scale` |
| `pet.json` (save) | `hunger`, `happiness`, `energy`, `last_saved_unix` | `pet_name`, `pet_pack_id`, `life{}` |
| `settings.json` | — (all defaulted) | see §11.3 |
| `history.json` | `pets[].name` | `born_unix`, `died_unix`, `age_days`, `cause` |

A pack `id` becomes a folder name on import, so it is cleaned to
`[a-z0-9_-]` with everything else becoming `_`, and leading/trailing `_-`
stripped.

### 17.3 Engine behaviours worth knowing — read this first

Verified on Godot **4.7.2 stable, Windows**. Several cost real time to
discover, and two were documented *wrongly* in the project's own spec.

| # | Behaviour | Consequence |
|---|---|---|
| 1 | **A script naming an autoload cannot compile under `--script`.** The run is compiled before autoloads are registered as names. | The entire pure-class architecture (§5.1). Fetch autoloads via `root.get_node("Needs")` in tests. |
| 2 | **`Vector2i` components are 32-bit**, though GDScript `int` is 64-bit. | A value past 2^31 wraps negative silently (RT-10). |
| 3 | **`DirAccess.rename_absolute` *does* overwrite an existing file on Windows.** The project's own comment said it does not. | Made RT-06's safe ordering possible. **Verify claims like this.** |
| 4 | **`ZIPReader` has no size API** — only `open`, `close`, `get_files`, `read_file`, `file_exists`, `get_compression_level`. `CLAUDE.md`'s claim that `get_file_info()` exists since 4.4 is wrong. | RT-03 had to parse the zip central directory by hand. |
| 5 | **`ZIPReader.read_file` allocates exactly the entry's *declared* uncompressed size.** | The declaration *is* the allocation, which is what makes checking it a real defence (RT-03). |
| 6 | **`JSON.parse_string("1e999")` → `inf`; `JSON.stringify(inf)` → `1e99999`.** | An infinity in a save file round-trips forever (RT-09). |
| 7 | **`JSON.stringify(NAN)` → `null`**, with a warning. | A `NaN` cannot corrupt a save into unparseability. |
| 8 | **`int()` of a non-finite float is undefined** — lands on `INT64_MIN`. | `"-9223372036854775808 days old"` (RT-09). |
| 9 | **`Marshalls.raw_to_base64()` pushes an engine error on an empty buffer.** | Guard for empty strings (RT-01). |
| 10 | **`get_tree()` is null in an autoload before it enters the tree.** | No timers in early autoload code paths (RT-12). |
| 11 | **`Window.hide()` does nothing to the root window on Windows.** | Minimise via `DisplayServer.window_set_mode` instead (§10.2). |
| 12 | **The root `Window`'s `visible`/`mode`/`has_focus()` report wrongly while minimised.** | Ask `DisplayServer`. |
| 13 | **`@"…"@` is PowerShell's *expandable* here-string.** | Interpolating untrusted text into one is code execution (RT-01). |
| 14 | **`OS.shell_open` is `ShellExecuteW`** — it launches programs, resolves names off `PATH`, and honours protocol handlers. | Never hand it unvalidated data (RT-02). |
| 15 | **Appending to a `PackedStringArray` held in a `Dictionary` does mutate the stored value** in 4.7.2. | Verified deliberately — had it not, every zip-safety refusal would have been silently discarded. |
| 16 | `Time.get_datetime_dict_from_unix_time` handles extreme values arithmetically (no hang), but returns nonsense years. | Cosmetic only. |
| 17 | **A `.glb` inside `res://` is imported as a `PackedScene`** and must be `load()`ed; one outside needs `GLTFDocument`. | The `is_builtin()` branch (§8.4). |
| 18 | **A fresh clone has no `.godot/`**, and without it Godot cannot resolve `class_name` references. | `build.ps1` runs `--import` before the tests (§13). |
| 19 | **Capturing a native program's stderr in Windows PowerShell wraps each line as an error**, aborting under `$ErrorActionPreference = "Stop"`. | Relax it around the test loop; trust the exit code (§13). |

### 17.4 Licensing obligations

The code is **MIT**. The art is **not** all under one licence and some of it
requires visible credit:

- **Pug** (default 3D pet) — by Smirnoff Alexander, **CC-BY 3.0**, via Poly
  Pizza. **Its credit must stay visible in the app and in the public README.**
- **Pawsome** (3D) — by Orlando Perez.
- **Pixel Pug, rooms, props, icons** — Nasha's Cozy Pets Pack
  (`assets/licenses/Nashas_Cozy_Pets_Pack_LICENSE.txt`).
- **Sickness icon and vet nurse** — Mini Clinic Pixel pack; credit optional,
  given anyway.
- **Vet clinic props** — Isometric Veterinary Clinic Starter by ThirdAngle
  (Playworks North); credit appreciated, given anyway.
- **Tray and exe icons** — DogPack (`assets/licenses/DogPack_LICENSE.txt`).

`assets/licenses/` must not be deleted. `assets/CREDITS.txt` is the single
source shown in Settings → About and copied into the shipped `README.txt` by
`build.ps1`.

---

*End of blueprint. Companion documents: `CLAUDE.md` (the original spec),
`CHANGELOG.txt` (what changed when and why), `redteam/99-master-report.md` (the
security engagement in full).*
