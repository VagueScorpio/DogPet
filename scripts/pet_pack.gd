class_name PetPack
extends RefCounted
## One pet pack: everything pet.json says, checked over and ready to use.
##
## A pack is a folder with a pet.json in it. Two kinds are supported, a 3D
## model (.glb or .gltf) and a 2D sprite sheet, and the rest of the app
## mostly does not care which it is looking at.
##
## Parsing and checking happen here, apart from any loading, so a bad pack is
## found and described before anything tries to put it on screen. Nothing in
## this file touches a node, which is also what lets the tests drive it.

const KIND_MODEL3D := "model3d"
const KIND_SPRITE2D := "sprite2d"

## The state names the app knows. A pack may supply art for any of them;
## anything missing falls back to idle plus the procedural motion.
const VALID_STATES: PackedStringArray = [
	"idle", "happy", "sad", "eat", "play", "walk", "restless", "sleep",
]

const PET_JSON := "pet.json"
const DEFAULT_TARGET_HEIGHT := 1.0
const DEFAULT_DISPLAY_HEIGHT_PX := 160.0

var id: String = ""
var display_name: String = ""
var kind: String = KIND_MODEL3D
## The folder holding pet.json: a path on disk, or a res:// path for the
## built-in fallback pack packed inside the exe.
var dir: String = ""

var credit: String = ""
var license: String = ""
var license_url: String = ""
var source_url: String = ""

# --- model3d ---
var model_file: String = ""
## How tall the dog should end up, in 3D units, whatever size the artist
## happened to model it at.
var target_height: float = DEFAULT_TARGET_HEIGHT
## Spin applied so the dog faces the camera.
var rotation_y_degrees: float = 0.0
## Optional map of app state to a clip name inside the .glb. Both of the
## packs that ship with DogPet are static meshes with no clips at all, so
## the procedural motion is the normal path, not a fallback.
var clip_names: Dictionary = {}

# --- sprite2d ---
var pixel_art: bool = true
var display_height_px: float = DEFAULT_DISPLAY_HEIGHT_PX
var faces_right: bool = true
## state -> {"file": String, "frames": int, "fps": float}
var sprite_animations: Dictionary = {}

## Everything wrong with this pack, in plain English. Empty means usable.
var problems: PackedStringArray = []


## Read and check the pet.json in this folder. Always returns a pack; ask
## is_valid() before using it, and read problems to find out why not.
static func load_from_dir(folder: String) -> PetPack:
	var json_path: String = folder.path_join(PET_JSON)
	if not FileAccess.file_exists(json_path):
		return _broken(folder, "no %s in %s" % [PET_JSON, folder])
	var text: String = FileAccess.get_file_as_string(json_path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _broken(folder, "%s is not valid JSON" % json_path)
	return from_dictionary(parsed, folder)


## Build a pack from already-parsed JSON. Split out from the file reading so
## the tests can feed it dictionaries directly.
static func from_dictionary(data: Dictionary, folder: String) -> PetPack:
	var pack := PetPack.new()
	pack.dir = folder
	# A missing id falls back to the folder name, which is almost always
	# what the author meant anyway.
	pack.id = str(data.get("id", folder.get_file())).strip_edges()
	pack.display_name = str(data.get("name", pack.id)).strip_edges()
	pack.kind = str(data.get("kind", KIND_MODEL3D)).strip_edges()
	pack.credit = str(data.get("credit", "")).strip_edges()
	pack.license = str(data.get("license", "")).strip_edges()
	pack.license_url = str(data.get("license_url", "")).strip_edges()
	pack.source_url = str(data.get("source_url", "")).strip_edges()

	if pack.id.is_empty():
		pack.problems.append("the pack has no id")

	match pack.kind:
		KIND_MODEL3D:
			pack._read_model3d(data)
		KIND_SPRITE2D:
			pack._read_sprite2d(data)
		_:
			pack.problems.append(
				"kind \"%s\" is not one of %s or %s" % [pack.kind, KIND_MODEL3D, KIND_SPRITE2D]
			)

	if pack.credit.is_empty():
		# Not fatal, but credit is a licence requirement for some art, so
		# it should never pass unnoticed.
		pack.problems.append("no credit line")

	return pack


func is_valid() -> bool:
	return problems.is_empty()


## Usable even with a complaint or two, as long as there is art to show.
## A missing credit line should not stop the dog appearing.
func is_usable() -> bool:
	for problem in problems:
		if problem != "no credit line":
			return false
	return true


func is_builtin() -> bool:
	return dir.begins_with("res://")


func model_path() -> String:
	return dir.path_join(model_file)


func sprite_path(state: String) -> String:
	var spec: Dictionary = sprite_animations.get(state, {})
	return dir.path_join(str(spec.get("file", "")))


## The clip inside the .glb for this state, or "" to use procedural motion.
func clip_for(state: String) -> String:
	return str(clip_names.get(state, ""))


## True when this pack has its own art for the state. Anything else falls
## back to idle art plus the procedural layer.
func has_art_for(state: String) -> bool:
	if kind == KIND_SPRITE2D:
		return sprite_animations.has(state)
	return not clip_for(state).is_empty()


# --- Pure geometry, kept here so it can be tested without a model --------

## How to scale and shift a loaded model so every dog is the same height,
## stands on the floor and is centred left to right.
##
## Models come in wildly different sizes: the two packs that ship with
## DogPet differ by about 3x before this runs. Returns the uniform scale and
## the shift to apply to the model *before* that scale.
static func fit_transform(bounds: AABB, wanted_height: float) -> Dictionary:
	var scale: float = 1.0
	if bounds.size.y > 0.0 and wanted_height > 0.0:
		scale = wanted_height / bounds.size.y
	# Feet to y = 0, and centred on x and z.
	var offset := Vector3(
		-(bounds.position.x + bounds.size.x * 0.5),
		-bounds.position.y,
		-(bounds.position.z + bounds.size.z * 0.5)
	)
	return {"scale": scale, "offset": offset}


## The largest whole-number scale that keeps a frame within the wanted
## height. Pixel art must never be scaled by a fraction, or the pixels come
## out uneven. Never smaller than 1.
static func integer_scale(frame_height: int, wanted_height_px: float) -> int:
	if frame_height <= 0:
		return 1
	return maxi(1, int(floor(wanted_height_px / float(frame_height))))


## The height of the tallest frame in the pack.
##
## One scale is chosen for the whole pack from this, rather than one per
## animation. The pixel pug's idle frames are 43px tall and its walk frames
## are 32px, so scaling each to fit on its own would make the dog visibly
## change size the moment it started walking.
func tallest_frame_height() -> int:
	var tallest: int = 0
	for state in sprite_animations.keys():
		var spec: Dictionary = sprite_animations[state]
		tallest = maxi(tallest, int(spec.get("frame_height", 0)))
	return tallest


# --- Reading each kind ---------------------------------------------------

func _read_model3d(data: Dictionary) -> void:
	model_file = str(data.get("model", "")).strip_edges()
	target_height = float(data.get("target_height", DEFAULT_TARGET_HEIGHT))
	rotation_y_degrees = float(data.get("rotation_y_degrees", 0.0))

	var clips: Variant = data.get("animations", {})
	if clips is Dictionary:
		for state in clips.keys():
			var name: String = str(clips[state]).strip_edges()
			if not name.is_empty():
				clip_names[str(state)] = name

	if model_file.is_empty():
		problems.append("no \"model\" file named")
	elif not FileAccess.file_exists(model_path()):
		problems.append("the model file %s is missing" % model_path())

	if target_height <= 0.0:
		problems.append("target_height must be greater than 0")
		target_height = DEFAULT_TARGET_HEIGHT


func _read_sprite2d(data: Dictionary) -> void:
	pixel_art = bool(data.get("pixel_art", true))
	display_height_px = float(data.get("display_height_px", DEFAULT_DISPLAY_HEIGHT_PX))
	faces_right = str(data.get("faces", "right")).strip_edges().to_lower() != "left"

	var clips: Variant = data.get("animations", {})
	if not clips is Dictionary or (clips as Dictionary).is_empty():
		problems.append("no animations listed")
		return

	for raw_state in (clips as Dictionary).keys():
		var state: String = str(raw_state)
		if not VALID_STATES.has(state):
			problems.append("\"%s\" is not a state DogPet knows" % state)
			continue
		var spec: Variant = (clips as Dictionary)[raw_state]
		if not spec is Dictionary:
			problems.append("the %s animation is not described properly" % state)
			continue
		_read_one_sprite_animation(state, spec)

	if not sprite_animations.has("idle"):
		problems.append("a sprite pack needs at least an idle animation")

	if display_height_px <= 0.0:
		problems.append("display_height_px must be greater than 0")
		display_height_px = DEFAULT_DISPLAY_HEIGHT_PX


func _read_one_sprite_animation(state: String, spec: Dictionary) -> void:
	var file: String = str(spec.get("file", "")).strip_edges()
	var frames: int = int(spec.get("frames", 1))
	var fps: float = float(spec.get("fps", 1.0))

	if file.is_empty():
		problems.append("the %s animation names no file" % state)
		return
	if frames < 1:
		problems.append("the %s animation needs at least one frame" % state)
		return
	if fps <= 0.0:
		fps = 1.0

	var path: String = dir.path_join(file)
	if not FileAccess.file_exists(path):
		problems.append("the %s image %s is missing" % [state, path])
		return

	# Measure the sheet now, so the frame size is known before anything is
	# drawn and a sheet that does not divide evenly is caught here.
	var size: Vector2i = _png_size(path)
	if size.x <= 0 or size.y <= 0:
		problems.append("could not read the size of %s" % path)
		return
	if size.x % frames != 0:
		problems.append(
			"%s is %d wide, which does not divide into %d frames" % [file, size.x, frames]
		)
		return

	sprite_animations[state] = {
		"file": file,
		"frames": frames,
		"fps": fps,
		"frame_width": size.x / frames,
		"frame_height": size.y,
	}


# Read width and height straight out of the PNG header, without decoding the
# whole image. Every PNG begins with an 8-byte signature, then an IHDR chunk
# whose width and height are two big-endian 32-bit numbers at offset 16.
static func _png_size(path: String) -> Vector2i:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 24:
		return Vector2i.ZERO
	file.big_endian = true
	file.seek(16)
	var width: int = file.get_32()
	var height: int = file.get_32()
	file.close()
	return Vector2i(width, height)


static func _broken(folder: String, reason: String) -> PetPack:
	var pack := PetPack.new()
	pack.dir = folder
	pack.id = folder.get_file()
	pack.display_name = pack.id
	pack.problems.append(reason)
	return pack
