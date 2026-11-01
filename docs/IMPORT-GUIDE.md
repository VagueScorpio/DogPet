# Adding art with **Add Art** — a guide to every option

DogPet keeps all its art in the `assets/` folder beside the app, and every pet
or room in there is described by a small text file: `pet.json` for a dog,
`scene.json` for a room. **Add Art** writes that file for you. You point it at
what you have, answer a few questions in plain English, and it works out the
rest, copies the files into place and tells the app to pick them up.

Two ways in, both the same wizard:

- **Assets → Add Art…** in the menu bar
- **Settings → Assets → Add art…**

---

## The three steps

| Step | What happens |
|---|---|
| **1. Choose the files** | You pick one or more files. The wizard sorts them and decides what they could be. |
| **2. What are they?** | Only appears when the answer is ambiguous — pictures could be a dog or a room. |
| **3. A few questions** | Only what cannot be measured from the files. Then **Install**. |

A preview sits above the questions the whole time: a live 3D view for a model
(which you can turn), or the pictures themselves, unsmoothed and unscaled.

---

## Step 1 — choosing the files

Hold **Ctrl** while clicking to pick several files at once. That is how a dog
with a standing picture *and* a walking strip goes in together.

| What you pick | What it becomes |
|---|---|
| `.glb` | A dog, as a 3D model. Straight to step 3. |
| `.gltf` | The same, but pick its companion files too (see below). |
| `.png` | Either a dog drawn in pictures, or a room. You choose in step 2. |
| `.zip` | A pack somebody already made. Installed as it is, no questions. |
| `.bin`, `.jpg`, `.jpeg`, `.webp`, `.ktx2` | Carried along as a model's companion files. |
| anything else | Listed as ignored; it is never copied. |

**`.glb` versus `.gltf`.** A `.glb` holds the model, its textures and its
geometry in one file, so one click is enough — prefer it. A `.gltf` is just the
description, and refers to a `.bin` and its texture files *by name* sitting
beside it. Select all of them together. The wizard copies those under their
**original names**, because renaming them would break the model in a way
nothing could see. (It warns you when it spots a `.gltf`.)

---

## Step 2 — "what are these pictures?"

| Option | Meaning |
|---|---|
| **A dog, drawn as pictures** | The PNGs are frames of an animal: a still pose, a walk strip, and so on. |
| **A room for the dog to be in** | The PNGs are a backdrop, repeating tiles, or things that stand in a room. |

---

## Step 3 — the questions

### Asked for everything

| Question | What it does | Written as |
|---|---|---|
| **Call it** | The name shown in the pet or room picker in Settings. Suggested from the file name — `pixel_pug-walk.png` becomes "Pixel Pug Walk". | `"name"` |
| **Folder** | The folder it lives in, inside `assets/pets/` or `assets/scenes/`. Follows what you type in **Call it** until you edit it yourself, then it stays put. Reduced to lower-case letters, digits, `_` and `-`; anything else becomes `_`. | `"id"` |
| **Credit** | Who made it, and under what licence. **Not decoration** — a lot of free art may only be used while its credit stays visible. Shown in Settings → About. Leave it empty and the wizard warns you, and the app will list the pack as having a problem. | `"credit"` |
| **Licence** | "CC-BY 3.0", "CC0"… Optional. | `"license"` |
| **Licence link** | Optional. Becomes a clickable link in About. | `"license_url"` |
| **Found at** | Where you got it. Optional, also a link. | `"source_url"` |

### A dog, as a 3D model

| Question | Options | What it does |
|---|---|---|
| **How big** | A small dog · A normal dog · A big dog | Sets the height the dog is drawn at: `0.75`, `1.0` or `1.3`. It does **not** matter what size the model was made at — DogPet measures the model's geometry and scales it, puts its feet on the floor and centres it. This only picks the final size on screen. |
| **Which way** | a slider, −180° to 180° | Spins the model so it looks at you. **Drag it and watch the preview** — this is the one question no amount of measuring can answer, because nothing in a model file says which way is "the front". The pug that ships with DogPet is modelled 29° off, which is why its file says `-29`. |

Written as `"target_height"` and `"rotation_y_degrees"`. `"animations"` is left
empty: a static model gets DogPet's own procedural motion — breathing, head
tilts, hops, a trot while walking — so it never needs a rig.

### A dog, drawn as pictures

One row per picture, showing its pixel size:

| Field | Options | What it does |
|---|---|---|
| **job** | Not used · Idle · Happy · Sad · Eat · Play · Walk · Restless · Sleep | Which state this picture is for. The first picture is offered as **Idle**; the rest start at **Not used**. Any state you leave out falls back to Idle plus the procedural motion, so one picture is a complete dog. **Idle is required.** |
| **frames** | 1–64 | How many frames are in the strip. Already counted for you from the sheet's proportions; correct it if the guess is wrong. |
| **per second** | 1–30 | How fast the frames play. Defaults to 6 for a strip, 1 for a single frame. |

| Question | Options | What it does |
|---|---|---|
| **Pixel art** | on / off | On: hard edges kept (nearest-neighbour) and the dog is only ever enlarged by **whole numbers**, so pixels stay square. Off: smoothed, any scale. Leave it on for pixel art, off for a drawn or rendered picture. Written as `"pixel_art"`. |
| **On screen** | 32–480 px | How tall the dog is drawn, in pixels. With **Pixel art** on, the largest whole-number scale that fits under this is used. Written as `"display_height_px"`. |
| **The art faces** | Right / Left | Which way the drawing already faces, so DogPet knows when to flip it. Written as `"faces"`. |

#### How a sprite sheet has to be laid out

**One horizontal row. Equal-width cells. The full height of the image is one
frame.** The width must divide exactly by the number of frames, or the wizard
refuses it and says so.

```
 one row, 4 frames of 43x32:        a grid - NOT supported:
 +----+----+----+----+              +----+----+----+
 | 1  | 2  | 3  | 4  |              | 1  | 2  | 3  |
 +----+----+----+----+              +----+----+----+
                                    | 4  | 5  | 6  |
                                    +----+----+----+
```

A grid sheet — several rows of poses, which is how most "pose sheet" downloads
come — has to be **cut up first**, one row saved per animation, before the
wizard can use it. Otherwise each "frame" is a slab of the grid with several
poses in it.

> This is worth watching for. The `pet_poses_sprite_sheet.png` that came in
> during testing is 2752 × 1536, so the wizard guessed 2 frames (the width is
> about twice the height, and divides exactly) — but it is a grid, so each of
> those two "frames" is a 1376 × 1536 block holding several poses at once. Cut
> one pose row out as its own PNG and import that instead.

#### Cutting a row out of a grid sheet

`tools/slice_sheet.gd` does it for you. Give it the rectangle holding one row
and it finds the poses inside, drops the rules and the 01/02/03 labels, makes
the background transparent, and writes the row out as equal cells side by
side:

```powershell
godot --headless --path . --script res://tools/slice_sheet.gd -- --in "sheet.png" --out "idle.png" --rect 2110,1026,640,152 --frames 3
```

`--rect` is `x,y,w,h` in pixels on the source sheet. It prints the sheet's
size, the poses it found and the strip it wrote, so a rectangle that is off by
a row is obvious at once — if it reports one enormous pose, the rectangle is
catching the rules; if it reports four, it has caught a neighbouring row.
Open the result and look at it before importing. Then hand that strip to **Add
Art** like any other picture.

### A room for the dog to be in

| Question | Options | What it does |
|---|---|---|
| **Used for** | Home · Eat · Play · Walk · Vet | Which slot the room fills: where the dog lives, where it is fed, where it plays, where it is walked, where it goes when ill. Rooms **do not replace each other** — add a second kitchen and you pick between them in Settings → Rooms. Written as `"role"`. |
| **Background** | From the pictures below · Drawn: an indoor room · Drawn: a grassy yard · Drawn: a park with a path | Where the backdrop comes from. The three **drawn** options need no pictures at all: DogPet paints them from colours, so a couple of props make a whole room. A park gets a dirt path, and a room in the **Walk** slot gets a background that scrolls past as the dog trots (60 px/s) — only the Walk slot does, since a living room sliding sideways all day would be a surprise. |

Then one row per picture:

| Field | Options | What it does |
|---|---|---|
| **job** | The whole background · Wall tile, repeated · Floor tile, repeated · A thing in the room · Not used | What this picture is. A big first picture is offered as the background, a small one as a thing in the room. Pick **wall** *and* **floor** to get a tiled room with a floor line. If you chose a **drawn** background above, background/wall/floor picks are ignored and not copied. |
| **where across** | On the left · In the middle · On the right | Horizontal spot: `0.2`, `0.5`, `0.8` of the window width. |
| **how near** | Towards the back · Mid floor · Near the front | How far down the window its base sits: `0.62`, `0.74`, `0.86`. Things lower down are drawn in front of things higher up, so this is also depth. |
| **size** | Small · Medium · Large | Enlarges the picture by 2, 3 or 5 — whole numbers, because it is pixel art. |
| **what it is** | Just scenery · The food bowl · The toy to chase · The vet table | Gives the prop a job. The dog **walks to the food bowl** to eat, **chases the toy** during play, and stands at the **vet table** at the clinic. The first prop with each job wins. Scenery just sits there. |

| Question | What it does |
|---|---|
| **Floor takes** | Percent of the window height the floor fills, for a **tiled** room (default 38). Ignored by the other background kinds. Written as `"floor_ratio"` (as a fraction). |
| **Tiles at** | How many times each tile is enlarged, 1–16 (default 4). Tiny tiles are raised automatically if they would be ruinous to draw. Written as `"tile_scale"`. |

The place and size options write plain numbers into `scene.json`, so you can
nudge them afterwards: `"x": 0.78` and so on, as fractions of the window.

---

## What happens when you press Install

1. **Your answers are checked.** Anything that would not work is said in amber
   at the bottom and nothing is written.
2. **If that folder already exists**, you are asked first. What is there is
   copied to `assets/_backup/<folder>-<date>/`, and only then replaced — replace
   really means replace, so a stale file from the old pack cannot survive.
3. **The files are copied in.** Pictures are renamed to safe lower-case names;
   models and their companions keep their own names. Two files with the same
   name from different folders don't collide — the second becomes `walk_2.png`.
4. **The `pet.json` or `scene.json` is written**, indented, so you can open it
   in Notepad later and change anything by hand.
5. **The app reloads its assets**, and the Done step offers **Use this dog now**
   or **Put the dog in it now**. Switching bodies keeps the same dog and the
   same needs.

Nothing is ever moved or changed in the folder you picked the files from.

---

## The messages, and what they mean

### Warnings — amber, but Install still works

| Message | What to do |
|---|---|
| "No credit line…" | Type who made it. Without it, the app lists the pack as having a problem, and some licences are broken by leaving it out. |
| "A .gltf keeps its geometry and textures in separate files…" | Go back and pick those files too, or use a `.glb`. |

### Refusals — nothing is written until you fix them

| Message | Why |
|---|---|
| "the pack needs a folder name" / "a name to show in the list" | Both fields have to say something. |
| "none of the pictures has been given a job yet" | Every row is still **Not used**. |
| "one of the pictures has to be the idle one" | Idle is the state the dog spends most of its life in. |
| "two pictures are both set to walk; pick one each" | One picture per state. |
| "… is 2752 wide, which does not divide into 3 frames" | Wrong frame count, or a grid sheet that needs cutting. |
| "… is 20000 x 20000, which is more than this app will load" | Over 33.5 million pixels. Shrink it. |
| "the room needs to say which slot it fills" | Pick **Used for**. |
| "the image picture has not been chosen" / "the wall picture…" | A picture background needs a backdrop; a tiled one needs **both** tiles. Or switch **Background** to one DogPet draws. |
| "the model file could not be found any more" | It was moved or renamed between choosing and installing. |
| "That model could not be read…" | Not a model DogPet can parse. A `.glb` from Poly Pizza or Sketchfab is the safest kind. |

A `.zip` has its own checks: it must hold a `pet.json` or a `scene.json`, its
entries may not point outside their folder, and it is capped at 64 MB per file,
256 MB unpacked and 512 files.

---

## Two worked examples

**A pug from Poly Pizza.** Download the `.glb`. Add Art → Choose files → pick
it. Leave **How big** at *A normal dog*, drag **Which way** until it looks at
you, paste the credit line the download page gives you into **Credit**, and
Install. Then **Use this dog now**.

**A kitchen of your own.** Save a wall tile and a floor tile as PNGs, plus a
bowl. Add Art → Ctrl-click all three → *A room for the dog to be in*. **Used
for: Eat**. Background: *From the pictures below*. Set the wall to **Wall tile**,
the floor to **Floor tile**, and the bowl to **A thing in the room**, *On the
right*, *Mid floor*, *Medium*, **The food bowl**. Install, then Settings →
Rooms → Eat to pick between your kitchen and the original.

---

## If you want to change something afterwards

Open the folder (**Assets → Open Assets Folder**), edit the `pet.json` or
`scene.json` in Notepad, then **Assets → Reload Assets**. Nothing is baked into
the app. The in-app instructions (**Assets → How to Change Pets or Scenes…**)
walk through doing the whole job by hand, which is worth a read once the wizard
has shown you what the files look like.
