# DogPet

A portable Windows virtual pet dog, built in **Godot 4** with GDScript.

A dog lives in its own little window on your desktop. It has three needs —
**Hunger**, **Happiness** and **Energy** — and they keep changing while the app
is closed, so the dog is genuinely waiting for you when you come back. Care for
it with **Feed**, **Play** and **Walk**. Minimize it to the system tray and it
sends you a Windows notification when the dog needs something.

All the art lives in a loose `assets/` folder next to the .exe, so you can swap
in your own dogs and rooms without rebuilding the app.

## Screenshot

<!-- TODO: add a screenshot once the app has a face. -->
_Coming once Phase 2 is done._

## Features

- Three needs that drain in real time, **and while the app is closed**
- A "While you were away" summary on launch
- Feed, Play and Walk, each with its own animation and its own background scene
- Procedural animation, so even a static 3D model breathes, hops, bobs and tilts
- Both 3D (`.glb`/`.gltf`) and 2D pixel-art sprite pets, loaded at runtime
- System tray icon with Windows toast notifications
- Care interval you pick: Frequent, Moderate or Long, plus a ⚡ Demo Speed toggle
- Import and export pet and scene packs as `.zip` files
- Fully portable: unzip and run, nothing is installed

## Status

Under construction, built in phases. See `CHANGELOG.txt` for what is done.

| Phase | What | Done |
|---|---|---|
| 0 | Repo | ✅ |
| 1 | Skeleton + needs | ✅ |
| 2 | Pets | ⬜ |
| 3 | Scenes + actions | ⬜ |
| 4 | Tray + notifications | ⬜ |
| 5 | Settings + asset tools | ⬜ |
| 6 | Ship | ⬜ |

## Open it in Godot

1. Install **Godot 4.4 or newer**, the standard (non-.NET) build, from
   [godotengine.org](https://godotengine.org/download/windows/).
2. Launch Godot. In the Project Manager, click **Import**.
3. Browse to this folder and pick `project.godot`, then click
   **Import & Edit**.
4. Press **F5** to run.

GDScript only — no C#, no GDExtensions, no addons.

## Build the shipped zip

From the project root, in PowerShell:

```powershell
.\tools\build.ps1
```

If `godot` is not on your PATH, point the script at it:

```powershell
.\tools\build.ps1 -GodotPath "C:\Godot\Godot_v4.4-stable_win64.exe"
```

The script exports the .exe, copies `assets/` next to it, writes a `README.txt`
and zips the lot into `build/DogPet-v<version>.zip`.

Before your first export, in the Godot editor go to
**Editor → Manage Export Templates → Download and Install**.

## Run the tests

The needs math is pure and headless-testable - 129 checks covering the drain
rates, clamping, every threshold crossing, offline catch-up and the save file:

```powershell
godot --headless --path . --script res://tests/test_needs.gd
```

It prints PASS or FAIL per check and exits non-zero if anything failed. On a
fresh clone, run this once first so Godot builds its caches:

```powershell
godot --headless --path . --import
```

## Add your own dog

Drop a folder into `assets/pets/` with a `model.glb` and a `pet.json`. Size and
orientation do not matter — the app normalizes every model to the same height.
See `assets/README.txt` for the details, including 2D sprite packs and editing
the rooms.

## License

The **code** in this repository is MIT licensed — see [LICENSE](LICENSE).

The **art** in `assets/` is **not** covered by that license. Every art pack
keeps its own license, and those license files live in `assets/licenses/`.
Please keep them, and keep the credit lines in `pet.json` and `scene.json` if
you share a pack. In particular the default Pug model is CC-BY 3.0, which
requires that its credit line stay visible.

## Credits

Art credits, copied from `assets/CREDITS.txt`:

**Pug** (default 3D pet, `assets/pets/pug_3d/`)
Pug by Smirnoff Alexander [CC-BY](https://creativecommons.org/licenses/by/3.0/),
via [Poly Pizza](https://poly.pizza/m/3nFZQW8yojl)

**Pawsome** (`assets/pets/pawsome_3d/`)
Pawsome by Orlando Perez

**Pixel Pug, rooms, props and icons** (`assets/pets/pug_pixel/`, `assets/scenes/`, `assets/ui/`)
Nasha's Cozy Pets Pack — license: `assets/licenses/Nashas_Cozy_Pets_Pack_LICENSE.txt`

**Tray icons and exe icon** (`assets/ui/tray_icon.png`, `assets/ui/tray_icon_alert.png`)
DogPack — license: `assets/licenses/DogPack_LICENSE.txt`
