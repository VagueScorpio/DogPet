# DogPet: Build Blueprint for Claude Code (v1.2)

You are building **DogPet**, a portable Windows virtual pet app, in **Godot 4 with GDScript**. This file is the full spec. Read all of it before writing code. Build in the phases listed at the end, and stop after each phase so the owner can test.

The owner is new to Godot. When a step needs him to click something in the Godot editor, say exactly where it is and what to click.

---

## 1. What the app is

- A dog lives in its own app window. It has three needs: **Hunger**, **Happiness**, and **Energy**.
- Needs change over time, **including while the app is closed**. On launch, the app works out how long it was closed and catches the needs up.
- The owner cares for the dog with three actions: **Feed**, **Play**, and **Walk**. Each action plays an animation and switches to its own background scene.
- The window can minimize to a **system tray icon**. While it is in the tray, the app sends **Windows notifications** when a need is getting low or is critical.
- The care interval is chosen in settings: **Frequent**, **Moderate**, or **Long**, plus a **Demo Speed** toggle for testing.
- All art lives in a loose **`assets/`** folder next to the .exe. Users can add, swap, import, and export pets and backgrounds without rebuilding.
- The final product is a zip: `DogPet.exe` + `assets/` (+ `saves/`, which the app creates on first run).

## 2. Hard rules

- **Engine:** Godot 4.4 or newer, standard (non-.NET) build. **GDScript only.** No C#, no GDExtensions, and no third-party addons.
- **Renderer:** Compatibility.
- **No installs on the user's PC.** The exported app must run from an unzipped folder. Anything that calls out to Windows may only use tools built into Windows 10/11 (PowerShell 5.1).
- **Static typing** in GDScript (`var x: float`, typed function signatures) everywhere.
- **No hard-coded art paths** in game logic. All art comes from `assets/` through the loader (section 5). The only art packed into the .exe is the fallback set (section 5.6) and the exe icon.
- **Versioning:** the app starts at **v1.0** and increments with each change. Store the version in one place (`application/config/version` in `project.godot`) and show it in Settings → About.
- **Changelog:** keep the rolling `CHANGELOG.txt` in the project root. Append every change with what, why, and how, under a heading for the version. Keep the table of contents at the top current.

## 3. Folder layout

### Project (development)

```
DogPet/                     ← Godot project root (open this folder in Godot)
├── project.godot
├── CLAUDE.md               ← this file
├── CHANGELOG.txt
├── README.md               ← repo front page (phase 0)
├── .gitignore              ← provided
├── .gitattributes          ← provided
├── icons/app_icon.ico      ← exe icon (already provided)
├── icons/app_icon.png
├── scripts/                ← all .gd files
├── scenes/                 ← all .tscn files
├── builtin/                ← fallback art packed into the exe (section 5.6)
├── tests/                  ← headless test scripts
├── tools/build.ps1         ← export + zip script (phase 6)
├── assets/                 ← loose art (already provided) — contains .gdignore
└── saves/                  ← dev saves — contains .gdignore
```

`assets/` and `saves/` each contain an empty `.gdignore` file. **Keep those files.** They stop the Godot editor from importing these folders, so the art is never baked into the .pck and is always loaded at runtime from disk, exactly as it will be in the shipped app.

### Shipped zip

```
DogPet-v1.0/
├── DogPet.exe              ← single file, Embed PCK on
├── assets/                 ← copied from the project
├── README.txt
└── (saves/ is created by the app on first run)
```

## 4. Paths

Create an autoload `Paths.gd`:

- **Base folder**
  - Exported build: `OS.get_executable_path().get_base_dir()`
  - Running from the editor (`OS.has_feature("editor")`): `ProjectSettings.globalize_path("res://")`
- `assets_dir = base/assets`, `saves_dir = base/saves`
- `saves/history.json` holds the scoreboard of past pets *(v1.16)*. It is kept apart from `pet.json` because it outlives every pet in it: starting a new dog wipes the save and must not wipe the record of the one before.
- On startup, create `saves/` if it is missing, then test-write a temp file there. If the write fails (for example, the app was unzipped into `C:\Program Files`), fall back to `OS.get_user_data_dir() + "/saves"`. Show a one-time notice that says where saves now live.
- If `assets/` is missing or unreadable, use the built-in fallback set (5.6) and show a notice. **Never crash** on missing or broken assets.

## 5. The asset system

### 5.1 Pet packs: `assets/pets/<pack_id>/pet.json`

Every folder in `assets/pets/` with a valid `pet.json` is a selectable pet. Two kinds are supported.

**3D model pet** (`"kind": "model3d"`), using .glb or .gltf:

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
  "credit": "Pug by Smirnoff Alexander [CC-BY] (https://creativecommons.org/licenses/by/3.0/) via Poly Pizza (https://poly.pizza/m/3nFZQW8yojl)",
  "license": "CC-BY 3.0",
  "license_url": "https://creativecommons.org/licenses/by/3.0/",
  "source_url": "https://poly.pizza/m/3nFZQW8yojl"
}
```

`credit` is required. `license`, `license_url`, and `source_url` are optional. The same optional fields work in 2D `pet.json` files and `scene.json` files.

**Credits are a license requirement, not decoration.** The default Pug is CC-BY 3.0, so its credit line must be visible in the app. Show it in Settings → About, as described in section 8.

- Load at runtime with `GLTFDocument.append_from_file()` + `GLTFState` → `generate_scene()`. Do not use `load()`. The files are not imported resources.
- **Auto-normalize size:** compute the combined AABB of all `MeshInstance3D` children, scale uniformly so the height equals `target_height`, and move the model so its feet sit at y = 0 and it is centered on x/z. Models from different sources come in wildly different scales. The two provided models differ by about 3×.
- Apply `rotation_y_degrees` so the dog faces the camera.
- `animations` optionally maps app states to clip names inside the .glb, for example `{"walk": "Walk_Cycle", "idle": "Idle"}`. If a state has a mapped clip and the .glb has an `AnimationPlayer`, play the clip. **Otherwise, use the procedural animation for that state (5.3).** Both provided models are static meshes with no rig and no clips, so procedural animation is the main path, not an edge case.

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

- Each animation is a horizontal strip with `frames` equal-width cells. Load the PNGs with `Image.load_from_file()` → `ImageTexture.create_from_image()` and build `SpriteFrames` at runtime with `AtlasTexture` cells.
- If `pixel_art` is true, use nearest-neighbor filtering and scale by **whole numbers only**. Pick the largest integer scale that does not exceed `display_height_px`.
- `faces` says which way the art faces. Flip horizontally to face the other way.
- Any state without its own animation falls back to `idle` plus the procedural layer.

**Valid state names** for both kinds: `idle`, `happy`, `sad`, `eat`, `play`, `walk`, `restless`, `sleep`.

### 5.2 Rendering both kinds in one layout

- The main view is 2D. Stack: background layer → props layer → **pet layer** → UI layer.
- For `model3d`, the pet layer is a `SubViewportContainer` with a `SubViewport` set to `transparent_bg = true`. The viewport holds the model, a `Camera3D` at a slight 3/4 overhead angle, a `DirectionalLight3D`, and soft ambient light. This lets a 3D dog stand in front of any 2D background.
- Draw a soft dark ellipse "blob shadow" under the pet for both kinds. It sells the dog as standing on the floor.
- The pet's on-screen spot can be moved per scene (see `pet_spot` in 5.4) and is tweened when it changes.

### 5.3 Procedural animation (works on any pet, including static meshes)

Build a `PetAnimator` that drives the pet's root transform with `Tween`s and per-frame math. For 2D, apply the same motion to the sprite's position, rotation, and scale.

| State | Motion |
|---|---|
| `idle` | Slow breathing (scale Y ±2%, about 3 s cycle). Every 4–9 s (random), do one of: a head-tilt (roll ±8°), a small turn toward the camera and back, or a little hop. |
| `happy` | 2–3 quick hops with squash-and-stretch on landing. A small spin (360° yaw) 30% of the time. |
| `sad` | Sink about 8% lower, tilt the nose down (pitch), and halve the breathing speed. Darken or desaturate the pet slightly. Rare, slow side-to-side sways. |
| `eat` | Move to the bowl's spot, then repeat a nod (pitch down 20°, back up) about 2.5 times per second for the length of the action. A tiny crumb particle burst is optional. |
| `play` | A toy prop tweens in an arc across the scene. The dog follows: turn, run (fast hop bob), pounce (jump + squash). Repeat 2–3 times. |
| `walk` | A steady trot bob (about 4 Hz, small) with the dog facing sideways. The background scrolls (5.4). 2D packs with a `walk` strip play it. |
| `restless` | Energy is very high. Quick pacing left and right with faster bobs and occasional zoomie spins. |
| `sleep` | Optional, for idle at night. Lie low (scale Y 0.85, slight roll), very slow breathing, floating "z" labels. |

States blend. Use short tweens (0.2–0.4 s) to move from one state's resting pose to the next, so nothing snaps.

**Mood state** when no action is running: `restless` if Energy ≥ 85%, else `sad` if Happiness ≤ 25% or Hunger ≥ 85%, else `happy` for a few seconds right after an action, else `idle`.

### 5.4 Scene packs: `assets/scenes/<any_name>/scene.json`

There are five fixed **roles**: `home` (default view), `eat`, `play`, `walk`, and `vet` *(v1.13, used by Real play)*.

A room says which role it fills with its own `"role"` field, so the folder may
be named anything, and **several rooms can offer themselves for the same role**
for the owner to pick between in Settings. A folder with no `"role"` falls back
to its folder name, so `assets/scenes/home/` is still the living room with no
change. The chosen room per role is saved in `settings.json` under `rooms`.

*(Changed in v1.6, at the owner's request. Originally this was one fixed folder
per role. It needed no change to the file format, because `scene.json` already
carried a `"role"` field.)*

```json
{
  "format_version": 1,
  "role": "eat",
  "name": "Kitchen",
  "background": { "type": "tiled", "wall": "wall.png", "floor": "floor.png", "floor_ratio": 0.38, "tile_scale": 4 },
  "props": [
    { "file": "raised_wooden_pet_feeding_station_with_two_bowls.png", "x": 0.78, "y": 0.78, "scale": 3, "role": "food_bowl" }
  ],
  "transition": "fade"
}
```

`background.type` is one of:

- `"image"` with `"file"`: one picture, scaled to cover the window (crop, don't stretch).
- `"tiled"` with `"wall"`, `"floor"`, `"floor_ratio"` (fraction of the window height for the floor), and `"tile_scale"` (integer, nearest filter): repeating tiles. Draw a thin darker line where wall meets floor.
- `"generated"` with a `"style"` of `"yard"`, `"park"` or `"room"`, plus colors. `"room"` *(v1.13)* is a plain indoor wall, skirting band and floor, taking `wall_color`, `wainscot_color`, `floor_color` and `floor_ratio` — no pictures at all, which is how the vet clinic's room is drawn. For `"yard"` and `"park"`: drawn in code (gradient sky, ground, a few clouds; trees and bushes for park; a dirt path when `"path"` is given). If `"scroll": true`, the scene scrolls horizontally at `scroll_speed_px`, with parallax: clouds slow, trees medium, path fast. This is how the walk scene moves.

Props:

- `x`/`y` are fractions of the window (0–1). `y` is the prop's **bottom** edge, so things sit on the floor.
- `scale` is an integer for pixel art.
- Draw props in order of `y`, lowest first, so nearer things overlap farther things.
- `role` is optional. `food_bowl` marks where the dog walks to eat. `toy` marks the prop that gets thrown during play. The first prop with the role wins; `_alt` roles are backups.
- Optional `"pet_spot": {"x": 0.5, "y": 0.82}` sets where the dog stands. Default is center, bottom 82%.

**Transitions:** `fade` cross-fades about 0.5 s. `slide` pushes the old scene out sideways (used when starting a walk). Each action switches from `home` to its role's scene, plays, then transitions back.

If a referenced file is missing, skip that one prop or fall back to a `generated` background. Write a warning to the log (`saves/dogpet.log`). Never crash.

### 5.5 UI pack: `assets/ui/ui.json`

This holds the tray icon, the tray alert icon, the three need icons, and the three action button icons. All are already provided. Load the same way: missing file means fall back to the built-in set.

### 5.6 Built-in fallback set

Copy the following into `res://builtin/` so it is packed inside the exe:

- the default pet: copy `assets/pets/pug_3d/`
- the four `scene.json` files with their images
- the `ui/` folder

If `assets/` is missing, damaged, or a pack fails to load, the app falls back to these files. This is the only place art is packed into the exe. Because `builtin/` is inside `res://`, files there are loaded with `load()` or with `FileAccess` on `res://` paths. Write the loader so it can read a pack from either a disk path or a `res://` path. Note that a `.glb` in `res://` gets imported by the editor, so for the fallback pet, load the imported scene with `load()` instead of `GLTFDocument`.

### 5.7 Asset management in Settings

- **Pet picker:** list every valid pet pack with its name, kind, and credit. Show a small live preview if practical. Switching pets keeps the needs; it is the same dog in a new body.
- **Open assets folder:** `OS.shell_open(assets_dir)`.
- **Reload assets:** rescan without restarting.
- **Import pack (.zip):** open a native file dialog (`DisplayServer.file_dialog_show`). Read the zip with `ZIPReader`. It must contain a `pet.json` (pet pack) or a `scene.json` (scene pack) at its root or in one top-level folder. Validate the JSON, then extract to `assets/pets/<id>/` or `assets/scenes/<id>/`, where a room's `<id>` is its folder name rather than its role, so importing a second kitchen adds one rather than replacing the first. Ask before overwriting a folder that already exists. A replaced pack is backed up to `assets/_backup/<id>-<timestamp>/` first. Reject paths containing `..` or absolute paths (zip-slip).
- **Export pack (.zip):** pick a pet pack or scene role, then write a zip with `ZIPPacker` to a location chosen in a save dialog. Include the pack's credit line in a `CREDITS.txt` inside the zip.

## 6. The needs system (autoload `Needs.gd`)

### 6.1 Meanings

All values are 0–100.

| Need | Direction over time | Bad end | Fixed by |
|---|---|---|---|
| **Hunger** | rises | 100 = starving | Feed |
| **Happiness** | falls | 0 = miserable | Play |
| **Energy** | rises (pent-up energy) | 100 = bouncing off the walls | Walk |

Show each need as a bar with its icon, a word label (Fine / Getting low / Needs care now), and a "needs care in ~1h 20m" countdown. **Do not rely on color alone.** Hunger and Energy bars fill as things get worse. Label them clearly so that's obvious.

### 6.2 Care intervals

The interval is the time from **fully cared for** to **critical**. Hunger 0→100, Happiness 100→0, Energy 0→100. Each need drains linearly at `100 / interval` per second.

| Setting | Hunger | Happiness | Energy |
|---|---|---|---|
| Frequent | 40 min | 45 min | 50 min |
| Moderate | 3 h | 3.5 h | 4 h |
| Long | 10 h | 11 h | 12 h |
| ⚡ Demo Speed | 45 s | 50 s | 55 s |

The needs are staggered slightly on purpose, so all three don't hit critical at the same moment. Put these numbers in `saves/settings.json` under `intervals_seconds`, so they can be tuned without code changes. Write the defaults when the file is missing.

**Demo Speed** is a toggle, not a fourth setting. When it is on, the live drain uses the Demo row. When it is off, the live drain uses the selected setting. Show a visible ⚡ badge while Demo is on.

### 6.3 Thresholds

- **Warning:** 70% of the way to critical (Hunger ≥ 70, Happiness ≤ 30, Energy ≥ 70).
- **Critical:** at the bad end (Hunger 100, Happiness 0, Energy 100).
- Values clamp at the bad end.
- **Casual play (the default): the dog never dies or runs away.** It stays sad until cared for.
- **Real Pet play** *(added v1.13, at the owner's request)*: the dog can die, and the owner then starts again with a new one.
  - **Starvation.** Hunger reaching 100 starts a countdown of one further care interval (`real_play.starve_grace_intervals`). On Moderate that is 3 h to reach starving, then 3 h more. The countdown resets the moment the dog is fed. **This can happen during the offline catch-up**, which was the owner's explicit choice.
  - **Illness.** At random — on average every 8 hunger intervals — the dog falls ill. A fourth **Sickness** bar climbs from 0 to 100 over 1.5 hunger intervals; at 100 the dog dies. **Take To Vet** takes 60 off the bar, so a badly ill dog needs more than one visit. The bar and the button appear only in Real play.
  - **Ageing.** The dog ages at two hunger intervals to the dog-day, through Puppy / Young / Adult / Senior. Ageing happens in both modes. **Old age is never fatal** — the owner chose that too.
  - All of these numbers live in `settings.json` under `real_play`, counted in hunger intervals so they scale with the care setting.
  - **Scoreboard** *(v1.16)*: every dog that has died is written to `saves/history.json` the moment it dies, with its name, birth date, death date, age and cause. Reached from **Mode → Scoreboard…**, which also lists the dog you have now. The pure logic is `PetHistory.gd`, tested by `tests/test_history.gd`.
  - The pure logic is `LifeModel.gd`, with no nodes and time passed in, tested by `tests/test_life.gd`.

### 6.4 Actions

Each action:

1. locks the action buttons,
2. transitions to its scene,
3. plays its animation for its duration (Feed 5 s, Play 8 s, Walk 10 s; Demo mode uses the same lengths),
4. applies its effects,
5. transitions home and unlocks.

| Action | Main effect | Side effects |
|---|---|---|
| Feed | Hunger → 0 | Happiness +5 |
| Play | Happiness → 100 | Energy −15, Hunger +5 |
| Walk | Energy → 0 | Happiness +10, Hunger +10 |

Put the side-effect numbers in `settings.json` under `action_effects`.

### 6.5 Time while closed (offline catch-up)

- `saves/pet.json` stores the three values, the pet name, the active pet pack id, and `last_saved_unix` from `Time.get_unix_time_from_system()`.
- Autosave every 30 s, on minimize to tray, and on quit. Write atomically: write `pet.json.tmp`, then rename over `pet.json`. Keep the previous file as `pet.json.bak`. On load, if `pet.json` is corrupt, use `.bak`.
- On launch: `elapsed = now − last_saved_unix`. If `elapsed < 0` (the clock moved backward), treat it as 0. Apply `elapsed` seconds of drain.
- **Catch-up always uses the selected real setting (Frequent, Moderate, or Long), never Demo speed,** even if Demo was on when the app closed. Otherwise a demo session would max every bar the moment the app reopened.
- If `elapsed > 60 s`, show a "While you were away (3h 12m)…" card on launch listing each need's before → after and the dog's reaction, for example "Biscuit is very hungry!".

### 6.6 Testability

Put the pure math (drain, clamp, thresholds, catch-up, action effects) in a class with **no node or scene dependencies** (`NeedsModel.gd`), with time passed in as an argument. `Needs.gd` wraps it.

Write `tests/test_needs.gd`, an `extends SceneTree` script that runs with:

```
godot --headless --path . --script res://tests/test_needs.gd
```

It should print PASS/FAIL per check and exit with code 0 on success or 1 on failure. Cover:

- drain rates for each setting
- clamping
- warning and critical crossings
- catch-up after 0 s, 1 h, 3 days, and a negative elapsed time
- catch-up ignores Demo
- each action's effects
- loading a corrupt save falls back to `.bak`

Run the tests after any change to needs logic.

## 7. Window, tray, and notifications

### 7.1 Window

- Default 540×760, resizable, minimum 420×600. Stretch mode `canvas_items`, aspect `expand`. Layout must not break when resized.
- Window title: `DogPet — <pet name>`. Set the exe icon in the export preset from `icons/app_icon.ico`. Also use `icons/app_icon.png` as the project icon.
- Top bar: the three need bars. Bottom bar: Feed, Play, and Walk buttons with icons and text, plus a ⚙ Settings button.
- Pixel-art packs use nearest filtering. UI text uses Godot's default font at a readable size; the UI scales with the window.

### 7.2 Tray icon (`StatusIndicator`)

- Use a `StatusIndicator` node with a `PopupMenu`. Follow the "Creating applications" page of the Godot docs.
- Menu items: Open DogPet, Pause notifications for 1 hour (checkable), Quit.
- Tooltip: `Hunger 62% · Happiness 40% · Energy 75%`, updated every 10 s.
- Show `tray_icon_alert.png` while any need is at Warning or worse; otherwise show `tray_icon.png`.
- Left-click restores the window.
- **Close button behavior** (setting, default **Minimize to tray**): set `get_tree().auto_accept_quit = false`. On `NOTIFICATION_WM_CLOSE_REQUEST`, either minimize to tray or save and quit, depending on the setting.
  - **Godot's `Window.hide()` does nothing to the root window on Windows** (checked in 4.7.2 with `IsWindowVisible`: the window stays fully up). Minimize with `DisplayServer.window_set_mode(WINDOW_MODE_MINIMIZED)` instead, and restore with `window_set_mode(WINDOW_MODE_WINDOWED)` **plus** `DisplayServer.window_move_to_foreground()` — the mode change alone leaves it minimized. The taskbar button stays visible; Godot has no flag to drop it. *(v1.7)*
  - The root `Window`'s own `visible`, `mode` and `has_focus()` all report wrongly while it is minimized, so ask `DisplayServer` instead when deciding whether the owner can see the window. *(v1.7)* Quit from the tray menu always saves first. The first time the window hides to the tray, show a one-time notification: "DogPet is still running in the tray."
- The tray icon does not work when the game is embedded in the editor. Check `DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR) and not Engine.is_embedded_in_editor()`. When unsupported, the close button quits normally. Tell the owner how to turn off game embedding in the editor to test the tray.
- Keep the needs ticking while hidden. Lower the frame rate while minimized or hidden: `Engine.max_fps = 5` and `OS.low_processor_usage_mode = true`. Restore both on show.

### 7.3 Windows notifications

Godot has no built-in way to send a Windows toast notification. Send one with **PowerShell 5.1**, which ships with Windows:

- Build a short script that uses `Windows.UI.Notifications.ToastNotificationManager` with a ToastGeneric XML payload (title + body + the app icon from `assets/ui/tray_icon.png` as `appLogoOverride`). To avoid needing an app registration, use the standard PowerShell AppUserModelID: `{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe`.
- Launch it with `OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-EncodedCommand", <base64 UTF-16LE script>])` so it doesn't block the game. Escape any text going into the XML.
- **Verify no console window flashes** when a notification fires. If one does, launch through a tiny generated `.vbs` file run by `wscript.exe`, which is also built into Windows, with window style 0.
- When to notify, only while the window is hidden, minimized, or unfocused:
  - when a need crosses **Warning**: "Biscuit is getting hungry."
  - when a need reaches **Critical**: "Biscuit is starving! Time to feed."
  - at most once per crossing. The flag resets when that need is cared for.
  - while Critical, a reminder every 30 min (Frequent), 60 min (Moderate), or 120 min (Long). With Demo on, every 60 s.
  - never during "Pause notifications".
- While the window is visible and focused, show the same messages as an in-app banner instead.
- Settings: Notifications on/off, plus a Test notification button.
- Notifications will show "Windows PowerShell" as the sender. This is expected and acceptable for v1.

## 8. Settings screen

Sections:

1. **Care:** Frequent / Moderate / Long (radio). Show the interval table so the choice is clear. ⚡ Demo Speed toggle.
2. **Pet:** name field (default "Biscuit"), pet pack picker (5.7).
2b. **Rooms:** one picker per role (Home, Eat, Play, Walk), listing every room offering itself for that role. Saved to `settings.json` under `rooms`.
3. **Assets:** Open folder, Reload, Import pack, Export pack.
4. **Window:** close-button behavior (Minimize to tray / Quit), Start minimized (off by default).
5. **Notifications:** on/off, Test.
6. **About:** version, a credits list, and the save and asset folder paths (click to open). The credits list shows every pack's `credit` line exactly as written. When a pack has `license_url` or `source_url`, show them as clickable links (`OS.shell_open`). Also show the full text of `assets/CREDITS.txt`. The active pet's credit always appears first.

Save to `saves/settings.json` immediately on change.

## 9. Code structure

- **Autoloads:** `Paths`, `Log`, `Settings`, `Needs`, `AssetLibrary`, `Notifier`, `Tray`.
- **Scenes:** `Main.tscn` (layout + scene switching), `PetView.tscn` (2D or 3D pet + `PetAnimator`), `NeedsBar.tscn`, `SettingsPanel.tscn`, `AwayCard.tscn`, `Banner.tscn`.
- Communicate with signals (`Needs.need_changed`, `Needs.threshold_crossed`, `AssetLibrary.pet_changed`, and so on). Don't reach across nodes with long `get_node` paths.
- Keep each script focused and under about 300 lines. Comment the non-obvious parts in plain English; the owner is learning Godot from this code.

## 10. Build and package (`tools/build.ps1`)

Write a PowerShell 5.1 script that:

1. Reads the version from `project.godot`.
2. Runs `godot --headless --path <project> --export-release "Windows Desktop" build/DogPet-v<ver>/DogPet.exe`. Take the Godot exe path as a `-GodotPath` parameter, defaulting to `godot` on the PATH.
3. Copies `assets/` into the build folder, **excluding `.gdignore`** and `_backup/`.
4. Writes `README.txt`: how to run, where saves go, how to add pets and backgrounds, and the full asset credits copied from `assets/CREDITS.txt`.
5. Creates `build/DogPet-v<ver>.zip` with `Compress-Archive`.
6. Prints the zip path and size.

The export preset (`export_presets.cfg`, which you create) uses Windows Desktop, x86_64, **Embed PCK on**, the icon from `icons/app_icon.ico`, the product name DogPet, and the version from the project. Before the first export, the owner must install export templates (Editor → Manage Export Templates → Download and Install). Tell him when it's time.

## 11. Git and GitHub (auto-save)

The project lives in a **public** GitHub repo named **DogPet**. Claude Code creates it and saves work to it automatically.

### 11.1 Repo setup (phase 0, done once)

1. Check that `git --version` works. Check that `git config user.name` and `git config user.email` are set; if not, ask the owner for them.
2. Run `git init -b main` in the project root. `.gitignore` and `.gitattributes` are already provided. Keep them.
3. Write `README.md` for the repo: what DogPet is, a screenshot placeholder, how to open it in Godot, how to build with `tools/build.ps1`, and a **Credits** section copied from `assets/CREDITS.txt`. The Pug is CC-BY 3.0, so its credit must stay in the public README.
4. Ask the owner once whether to add an MIT `LICENSE` file for the code. The art keeps its own licenses in `assets/licenses/`. Say that in the README either way.
5. Make the first commit: `Phase 0: starter kit v1.2`.
6. Create the remote and push, using the first method that works:
   - **GitHub CLI:** if `gh auth status` succeeds, run `gh repo create DogPet --public --source . --remote origin --push --description "Portable Windows virtual pet dog, built in Godot 4"`.
   - **Connected GitHub tools:** if this Claude Code session has GitHub tools, create the public repo `DogPet` with them, then `git remote add origin <url>` and `git push -u origin main`.
   - **Manual:** ask the owner to create an empty public repo named DogPet on github.com (no README, no .gitignore, no license), paste the URL, then add the remote and push.
7. Report the repo URL to the owner.

### 11.2 Auto-save rules

- **Commit and push after every working step,** meaning each finished chunk of work that runs. Examples: "save/load works", "pug_3d loads and normalizes", "kitchen scene draws". Don't wait to be asked.
- Before each commit: if needs logic changed, run `tests/test_needs.gd` and commit only when it passes. Check that Godot opens the project without script errors, using `godot --headless --path . --quit` when Godot is on the PATH.
- If a step is half-done and the owner stops the session, commit it anyway with `WIP:` at the start of the message, so nothing is lost. Make the next commit finish it.
- Commit message format: `Phase N: <what changed>`, in plain English, one line, with detail in the body when useful.
- Push right after each commit: `git push`. If a push fails, tell the owner why. **Never force-push, never rewrite pushed history, and never commit to a branch other than `main`** unless the owner asks.
- Never commit `saves/` contents, `build/`, `.godot/`, logs, or anything with personal paths in it. `.gitignore` covers these. Check `git status` before committing.

### 11.3 End of each phase

1. Bump the version in `project.godot` (the minor number: v1.0 → v1.1 → ...).
2. Add the phase's entry to `CHANGELOG.txt`.
3. Commit, then tag: `git tag -a v<ver> -m "Phase N complete"`, then `git push && git push --tags`.
4. After phase 6, create a GitHub Release for the tag and attach `build/DogPet-v<ver>.zip`. With the GitHub CLI: `gh release create v<ver> build/DogPet-v<ver>.zip --title "DogPet v<ver>" --notes-file <notes>`. Otherwise, tell the owner how to upload the zip on the repo's Releases page.

## 12. Build phases

Stop at the end of each phase. Tell the owner exactly how to test it, and wait for his OK before going on. Update `CHANGELOG.txt` each phase. Follow section 11 for saving to GitHub throughout.

0. **Repo.** Section 11.1. *Test:* the owner opens the repo URL and sees the files.
1. **Skeleton + needs.** Project setup, autoloads, paths, saves, settings file, `NeedsModel` + tests passing, a plain debug screen with the three bars, the countdowns, the Demo toggle, and catch-up with the "While you were away" card. *Test:* Demo on, watch the bars move. Close the app, wait a minute, reopen.
2. **Pets.** `AssetLibrary` pet loading (3D + 2D), the size normalizing, `PetView` in front of a plain background, all procedural states, and the mood state. *Test:* switch between pug_3d, pawsome_3d, and pug_pixel; watch idle, sad, and restless at Demo speed.
3. **Scenes + actions.** Scene packs (tiled, image, and generated, including the scrolling park), props, transitions, and the Feed, Play, and Walk sequences. *Test:* each action plays in its scene and the bars respond.
4. **Tray + notifications.** `StatusIndicator`, close-to-tray, the alert icon, toasts, banners, reminders, pause, and the low-power mode while hidden. *Test:* Demo on, close to tray, wait for the notifications.
5. **Settings + asset tools.** The full settings screen, pet picker, import and export of zip packs, and credits. *Test:* export pug_pixel as a zip, delete the folder, import it back.
6. **Ship.** The export preset, `build.ps1`, the README, and a final pass on edge cases: missing `assets/`, read-only folder, corrupt save, and a broken `pet.json`. *Test:* run the zip on a clean folder on the Desktop.

## 13. Provided assets (already in `assets/`)

- `CREDITS.txt`: credits for all included art.
- `pets/pug_3d/`: **default pet.** Pug by Smirnoff Alexander, CC-BY 3.0, via Poly Pizza. A static .glb (2,706 vertices, one texture) with no rig and no animations. It faces about 29° off +Z, so `rotation_y_degrees` is −29. Tune if needed.
- `pets/pawsome_3d/`: a static .glb with 8 flat-color materials and no texture, about a third the size of the pug before normalizing.
- `pets/pug_pixel/`: from Nasha's Cozy Pets Pack. `walk.png` is a 4-frame strip (43×32 per frame, 6 fps). `idle.png` is a single 45×43 frame.
- `scenes/home`, `scenes/eat`: tiled rooms (32×32 wall and floor tiles) plus props, all from the Cozy pack.
- `scenes/play`: a generated yard plus toy props. `scenes/walk`: a generated scrolling park.
- `ui/`: tray icons (a 32×32 pug from DogPack, plus an alert version with a red dot), need icons, and button icons.
- `licenses/`: the license files for both 2D packs. Do not delete these.

All the 2D art is small pixel art. Use nearest filtering and integer scales everywhere it's drawn.
