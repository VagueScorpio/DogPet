# RT-18 — `pet.json` may name art outside its own pack folder

Severity: **Medium**
Location: `scripts/pet_sprite_art.gd:74`, and the same pattern in
`scripts/pet_pack.gd:147`, `scripts/scene_pack.gd:188/198/309`,
`scripts/ui_pack.gd:85`
Probe: `redteam/tests/probe_p4_install.gd`, case [3]

## The finding

```gdscript
var file: String = str(spec.get("file", "")).strip_edges()
...
var path: String = folder.path_join(file)
if not FileAccess.file_exists(path):
```

`file` comes out of a `pet.json` that may have arrived in a pack somebody
downloaded. It is joined to the pack folder with no check that it stays there.

The previous engagement closed zip-slip properly — `PackArchive.is_safe_entry`
refuses `..`, drive letters, leading slashes and the Windows device names, and
I could not get past it. But that guards the **entries** of the zip. A zip
whose every entry is impeccable can still carry a manifest that points
outwards, and nothing read the manifest with the same suspicion.

```
[3] a hand-written pet.json whose file field climbs out of the pack
    PetPack: usable=true problems=[]
    *** idle resolved to a file outside the pack: ../../secret.png ***
```

Accepted, called usable, no problems. The pack then draws a PNG from two
folders above itself. A drive-absolute path fails harmlessly, because
`path_join` glues it onto the folder and the result does not exist.

The same hole is in four other places, all reading a name out of a manifest
and joining it to a folder: the pet pack's `model`, the scene pack's
background `file`, `wall` and `floor` and its props' `file`, and the UI pack's
icons.

## What it is worth

Little, and worth being straight about. The app reads the file as a picture
and draws it; there is no execution, and DogPet talks to nothing, so nothing
leaves the machine. The realistic harms are that a shared pack can display a
PNG from the machine it is installed on, and — the more likely annoyance —
that such a pack silently stops working when it is passed on, because the file
it depended on was never in the zip.

It is on the list because the pack folder is the app's trust boundary and
this is the one place that treats it as a base for joining rather than as a
boundary to stay inside.

## How it should be fixed, and why that way

One helper, used by all five callers:

```gdscript
static func inside(folder: String, file: String) -> String:
	return "" if not is_safe_entry(file) else folder.path_join(file)
```

It goes in `PackArchive`, next to `is_safe_entry`, because that function
already encodes exactly this judgement and is already what the installer uses
for the names it writes. The import and the read then agree on what a pack may
contain, which is the property worth having: one rule, one place, and a pack
cannot be read in a way it could not have been installed.

`is_safe_entry` allows **subfolders** (`art/idle.png`), and that is deliberate
and kept — a pack may organise its own files, and the shipped packs' flat
layout is a convention rather than a rule. What it refuses is leaving.

Each caller then complains in its own words, in the same plain English as its
other complaints, rather than the helper inventing a message: the wording of
those strings is read by the tests and shown in Settings → About.

---

## What was fixed

**`scripts/pack_archive.gd`** — the helper, beside `is_safe_entry`:

```gdscript
## Where one file named by a pack's own manifest really sits, or "" when the
## name tries to leave the pack folder.
##
## A zip with impeccable entries can still carry a pet.json naming
## "../../x.png": the entries are what is_safe_entry guards, and this is the
## other half of the same rule. One judgement, so a pack cannot be read in a
## way it could not have been installed.
static func inside(folder: String, file: String) -> String:
	var cleaned: String = file.strip_edges()
	if cleaned.is_empty() or not is_safe_entry(cleaned):
		return ""
	return folder.path_join(cleaned)
```

**`scripts/pet_sprite_art.gd`** — the finding's own line:

```gdscript
-	var path: String = folder.path_join(file)
-	if not FileAccess.file_exists(path):
+	var path: String = PackArchive.inside(folder, file)
+	if path.is_empty():
+		problems.append(
+			"the %s animation names %s, which is outside the pack" % [state, file]
+		)
+		return {}
+	if not FileAccess.file_exists(path):
```

**`scripts/pet_pack.gd`** — `model_path` and its complaint:

```gdscript
 func model_path() -> String:
-	return dir.path_join(model_file)
+	return PackArchive.inside(dir, model_file)
```

with `_read_model3d` gaining the case where that is empty:

```gdscript
	if model_file.is_empty():
		problems.append("no \"model\" file named")
	elif model_path().is_empty():
		problems.append("the model %s is outside the pack" % model_file)
	elif not FileAccess.file_exists(model_path()):
```

**`scripts/scene_pack.gd`** — the three background readers and the props, each
keeping its own wording:

```gdscript
-	if file.is_empty() or not FileAccess.file_exists(dir.path_join(file)):
+	if not _has(file):
 		_fall_back_background("the background picture %s is missing" % file)
```

with

```gdscript
# Is this file, named by the manifest, both inside the pack and really there?
# A name that leaves the pack is treated as missing: a pack that reaches
# outside itself is broken in the same way whether the file exists or not.
func _has(file: String) -> bool:
	var path: String = PackArchive.inside(dir, file)
	return not path.is_empty() and FileAccess.file_exists(path)
```

and `_tile_scale_for` reading through `PackArchive.inside` as well.

**`scripts/ui_pack.gd`** — `_path` and `_checked` the same way.

## Test result after the fix

```
[3] a hand-written pet.json whose file field climbs out of the pack
    PetPack: usable=false problems=[
      "the idle animation names ../../secret.png, which is outside the pack",
      "a sprite pack needs at least an idle animation"]
[3b] the same with a drive-absolute path
    PetPack: usable=false problems=[
      "the idle animation names C:/.../secret.png, which is outside the pack", ...]
```

Refused, with a complaint that says what is actually wrong — rather than the
old `3b` message, which reported a nonsense doubled path as "missing".

Suites after the fix: **1070 checks, 0 failures**. The six new checks in
`test_pets` and `test_scenes` fail against the old code.

## How it relates to the rest of the app

`PackArchive.inside` is now the single answer to "where does this manifest's
file sit", with five callers:

- `PetSpriteArt.one` — every sprite state and every life stage of one.
- `PetPack.model_path` — read by `PetLoader` when it loads the `.glb`, so the
  3D path is covered by the same change.
- `ScenePack`'s image, tiled and prop readers, and `_tile_scale_for`.
- `UiPack`'s icons.

`PackArchive.is_safe_entry` is unchanged, so the zip import behaves exactly as
it did and the installer's own naming is untouched. The two now share one
rule, which is the point of putting it there.

`UiPack` is strictly outside this engagement's scope — `ui.json` is not
something the wizard installs — but it is the same three lines of the same
hole, and leaving it open for the sake of a scope boundary would have been
silly.

The regression guards are in `tests/test_pets.gd` (a `pet.json` naming
`../x.png` for a state, for a life stage, and for a model) and
`tests/test_scenes.gd` (a `scene.json` naming one for its background and for a
prop).
