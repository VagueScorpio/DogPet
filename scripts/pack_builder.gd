class_name PackBuilder
extends RefCounted
## Turning loose files into a pack.
##
## PackArchive installs a zip somebody else already made. This does the other
## half: the owner points at a .glb or a sprite sheet, answers a few questions
## in the import wizard, and the pet.json or scene.json the rest of the app
## insists on gets written for them. Nobody has to know what a manifest is.
##
## Nothing here touches a node or an autoload, so the tests can hand it a
## folder of files and read back exactly what it would install.

## What a set of chosen files could be turned into.
enum Kind { UNKNOWN, PET_MODEL, PET_SPRITE, ROOM, PACK_ZIP }

const MODEL_EXTENSIONS: PackedStringArray = ["glb", "gltf"]
const IMAGE_EXTENSIONS: PackedStringArray = ["png"]
const ARCHIVE_EXTENSIONS: PackedStringArray = ["zip"]
## A .gltf keeps its geometry and its textures in files beside it, so those
## have to travel into the pack as well even though nothing names them.
const EXTRA_EXTENSIONS: PackedStringArray = ["bin", "jpg", "jpeg", "webp", "ktx2"]

## What the file dialog offers. The first line is what is wanted almost
## always: everything DogPet can do something with.
const FILE_FILTER: PackedStringArray = [
	"*.glb,*.gltf,*.png,*.zip ; Anything DogPet can use",
	"*.glb,*.gltf ; 3D models",
	"*.png ; Pictures and sprite sheets",
	"*.zip ; Ready-made packs",
]

const DEFAULT_FPS := 6.0
const DEFAULT_FLOOR_RATIO := 0.38
const DEFAULT_PROP_SCALE := 3

const BG_IMAGE := "image"
const BG_TILED := "tiled"
const BG_GENERATED := "generated"


## Sort chosen paths by what they are. Anything unrecognised is listed under
## "ignored" rather than quietly dropped, so the wizard can say so.
static func sort_sources(paths: PackedStringArray) -> Dictionary:
	var found: Dictionary = {
		"models": PackedStringArray(),
		"images": PackedStringArray(),
		"archives": PackedStringArray(),
		"extras": PackedStringArray(),
		"ignored": PackedStringArray(),
	}
	for path in paths:
		var extension: String = path.get_extension().to_lower()
		if MODEL_EXTENSIONS.has(extension):
			found["models"].append(path)
		elif IMAGE_EXTENSIONS.has(extension):
			found["images"].append(path)
		elif ARCHIVE_EXTENSIONS.has(extension):
			found["archives"].append(path)
		elif EXTRA_EXTENSIONS.has(extension):
			found["extras"].append(path)
		else:
			found["ignored"].append(path)
	return found


## The kinds of pack these files could become, best guess first. Empty means
## there is nothing here to build with.
##
## A model settles it: a .glb is a pet and nothing else. Pictures are the
## ambiguous case - the same PNG could be a dog or a wall - so both are
## offered and the owner says which.
static func kinds_for(sources: Dictionary) -> Array[int]:
	var kinds: Array[int] = []
	if not PackedStringArray(sources["archives"]).is_empty():
		kinds.append(Kind.PACK_ZIP)
		return kinds
	if not PackedStringArray(sources["models"]).is_empty():
		kinds.append(Kind.PET_MODEL)
		return kinds
	if not PackedStringArray(sources["images"]).is_empty():
		kinds.append(Kind.PET_SPRITE)
		kinds.append(Kind.ROOM)
	return kinds


static func kind_title(kind: int) -> String:
	match kind:
		Kind.PET_MODEL: return "A dog, as a 3D model"
		Kind.PET_SPRITE: return "A dog, drawn as pictures"
		Kind.ROOM: return "A room for the dog to be in"
		Kind.PACK_ZIP: return "A ready-made pack"
	return "Something else"


## "pixel_pug_walk.png" becomes "Pixel Pug Walk". It can be typed over; this
## only has to be better than an empty field.
static func suggest_name(path: String) -> String:
	var words: String = path.get_file().get_basename().replace("_", " ").replace("-", " ")
	return words.strip_edges().capitalize()


## An id becomes a folder name, so PackArchive rules for one apply here too.
static func clean_id(raw: String) -> String:
	return PackArchive.clean_id(raw)


## What a chosen file should be called once it is inside the pack.
##
## A folder of someone elses art may hold "Walk Cycle (final).png"; pet.json
## names its files by hand and the app reads them straight off the disk, so
## what lands in the pack is reduced to the characters an id may contain.
static func safe_file_name(path: String) -> String:
	var base: String = clean_id(path.get_file().get_basename())
	if base.is_empty():
		base = "file"
	var extension: String = path.get_extension().to_lower()
	var name: String = base if extension.is_empty() else "%s.%s" % [base, extension]
	# CON.png reduces to con.png, which Windows still resolves to the console
	# rather than to a file. Anything PackArchive would refuse in a zip is
	# refused here too, for the same reason.
	return name if PackArchive.is_safe_entry(name) else "pack_" + name


## How many frames a sprite sheet probably holds.
##
## Frames are square-ish far more often than not, so the width divided by the
## height is the guess - but only when it divides exactly. Anything else is
## one frame, which is always a safe answer and never a wrong-looking one.
static func guess_frames(size: Vector2i) -> int:
	if size.x <= 0 or size.y <= 0:
		return 1
	var guess: int = int(roundf(float(size.x) / float(size.y)))
	if guess < 2 or size.x % guess != 0:
		return 1
	return guess


## What is wrong with this sheet, in plain English, or "" if nothing is.
static func sheet_problem(path: String, size: Vector2i, frames: int) -> String:
	if size.x <= 0 or size.y <= 0:
		return "%s is not a PNG this app can read" % path.get_file()
	if ImageLimits.is_too_large(size):
		return "%s is %d x %d, which is more than this app will load" % [
			path.get_file(), size.x, size.y,
		]
	if frames < 1:
		return "%s needs at least one frame" % path.get_file()
	if size.x % frames != 0:
		return "%s is %d wide, which does not divide into %d frames" % [
			path.get_file(), size.x, frames,
		]
	return ""


# --- The manifests -------------------------------------------------------

## The pet.json for a 3D pet. File names here are the ones inside the pack.
static func model_pet_manifest(answers: Dictionary) -> Dictionary:
	var data: Dictionary = {
		"format_version": 1,
		"id": str(answers.get("id", "")),
		"name": str(answers.get("name", "")),
		"kind": PetPack.KIND_MODEL3D,
		"model": str(answers.get("model", "")),
		"target_height": _rounded(
			float(answers.get("target_height", PetPack.DEFAULT_TARGET_HEIGHT))
		),
		"rotation_y_degrees": _rounded(float(answers.get("rotation_y_degrees", 0.0))),
		# Both packs DogPet ships with are static meshes, so an empty map and
		# the procedural motion is the normal answer rather than a gap.
		"animations": {},
	}
	_add_credits(data, answers)
	return data


## The pet.json for a pet drawn as pictures.
static func sprite_pet_manifest(answers: Dictionary) -> Dictionary:
	var animations: Dictionary = {}
	for entry in answers.get("sheets", []):
		var sheet: Dictionary = entry
		var state: String = str(sheet.get("state", ""))
		if state.is_empty() or animations.has(state):
			continue
		animations[state] = {
			"file": str(sheet.get("file", "")),
			"frames": maxi(1, int(sheet.get("frames", 1))),
			"fps": _rounded(float(sheet.get("fps", DEFAULT_FPS))),
		}
	var data: Dictionary = {
		"format_version": 1,
		"id": str(answers.get("id", "")),
		"name": str(answers.get("name", "")),
		"kind": PetPack.KIND_SPRITE2D,
		"pixel_art": bool(answers.get("pixel_art", true)),
		"display_height_px": int(
			answers.get("display_height_px", PetPack.DEFAULT_DISPLAY_HEIGHT_PX)
		),
		"faces": str(answers.get("faces", "right")),
		"animations": animations,
	}
	_add_credits(data, answers)
	return data


## The scene.json for a room.
static func room_manifest(answers: Dictionary) -> Dictionary:
	var props: Array = []
	for entry in answers.get("props", []):
		var prop: Dictionary = entry
		var written: Dictionary = {
			"file": str(prop.get("file", "")),
			"x": _rounded(clampf(float(prop.get("x", 0.5)), 0.0, 1.0)),
			"y": _rounded(clampf(float(prop.get("y", 0.8)), 0.0, 1.0)),
			"scale": maxi(1, int(prop.get("scale", DEFAULT_PROP_SCALE))),
		}
		var role: String = str(prop.get("role", "")).strip_edges()
		if not role.is_empty():
			written["role"] = role
		props.append(written)

	var data: Dictionary = {
		"format_version": 1,
		"id": str(answers.get("id", "")),
		"role": str(answers.get("role", ScenePack.HOME)),
		"name": str(answers.get("name", "")),
		"background": _background(answers),
		"props": props,
		"transition": ScenePack.TRANSITION_FADE,
	}
	_add_credits(data, answers)
	return data


## The manifest for whichever kind this is.
static func manifest_for(kind: int, answers: Dictionary) -> Dictionary:
	match kind:
		Kind.PET_MODEL: return model_pet_manifest(answers)
		Kind.PET_SPRITE: return sprite_pet_manifest(answers)
		Kind.ROOM: return room_manifest(answers)
	return {}


## The manifest as it will be written: indented, so it can be opened in
## Notepad afterwards and read by a person.
static func manifest_text(data: Dictionary) -> String:
	return JSON.stringify(data, "  ") + "\n"


## Which file the manifest goes in, for a kind.
static func manifest_name(kind: int) -> String:
	return ScenePack.SCENE_JSON if kind == Kind.ROOM else PetPack.PET_JSON


## Which folder under assets/ a kind belongs in.
static func subdir_for(kind: int) -> String:
	return "scenes" if kind == Kind.ROOM else "pets"


static func _background(answers: Dictionary) -> Dictionary:
	# A room needs no pictures at all: DogPet can paint an indoor room, a
	# yard or a park in code, which is how the shipped play and walk scenes
	# are drawn. That makes a handful of props enough for a whole room.
	if str(answers.get("background", BG_IMAGE)) == BG_GENERATED:
		var style: String = str(answers.get("style", "room"))
		var drawn: Dictionary = {"type": BG_GENERATED, "style": style}
		if style == "park":
			drawn["path"] = "#d9c29a"
		# Only the walk scene is meant to go past. A living room that slid
		# sideways all day would be a surprise.
		if str(answers.get("role", "")) == ScenePack.WALK:
			drawn["scroll"] = true
			drawn["scroll_speed_px"] = 60.0
		return drawn

	if str(answers.get("background", BG_IMAGE)) == BG_TILED:
		return {
			"type": BG_TILED,
			"wall": str(answers.get("wall", "")),
			"floor": str(answers.get("floor", "")),
			"floor_ratio": _rounded(clampf(
				float(answers.get("floor_ratio", DEFAULT_FLOOR_RATIO)), 0.05, 0.95
			)),
			"tile_scale": maxi(1, int(answers.get("tile_scale", 1))),
		}
	return {"type": BG_IMAGE, "file": str(answers.get("image", ""))}


# Credit travels with the art or the licence is broken, so it is written
# whenever there is one - and left out entirely when there is not, rather
# than written as an empty string nobody can tell from a forgotten one.
static func _add_credits(data: Dictionary, answers: Dictionary) -> void:
	for key in ["credit", "license", "license_url", "source_url"]:
		var value: String = str(answers.get(key, "")).strip_edges()
		if not value.is_empty():
			data[key] = value


# Two decimal places. A rotation nudged with a slider arrives as 28.999998,
# and a manifest meant to be read by a person should not say so.
static func _rounded(value: float) -> float:
	return snappedf(value, 0.01)
