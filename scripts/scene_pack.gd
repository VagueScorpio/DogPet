class_name ScenePack
extends RefCounted
## One room: everything scene.json says, checked over and ready to draw.
##
## A room is a folder with a scene.json in it, exactly like a pet pack is a
## folder with a pet.json. Each room declares which of the four roles it
## fills - home, eat, play or walk - so the folder can be called anything,
## and several rooms can offer themselves for the same role for the owner
## to choose between.
##
## Nothing here touches a node. Parsing, checking and sorting all happen
## before anything is drawn, so a broken room is described rather than
## discovered halfway through a frame.

const SCENE_JSON := "scene.json"

const HOME := "home"
const EAT := "eat"
const PLAY := "play"
const WALK := "walk"
const ROLES: PackedStringArray = [HOME, EAT, PLAY, WALK]

const BG_IMAGE := "image"
const BG_TILED := "tiled"
const BG_GENERATED := "generated"

const TRANSITION_FADE := "fade"
const TRANSITION_SLIDE := "slide"

## Props can claim a job as well as a place. The dog walks to the food bowl
## to eat, and the toy is the thing thrown during play. An "_alt" prop is a
## backup used only when the main one is missing.
const ROLE_FOOD_BOWL := "food_bowl"
const ROLE_TOY := "toy"

## Where the dog stands when the room does not say otherwise.
const DEFAULT_PET_SPOT := Vector2(0.5, 0.82)

var id: String = ""
var role: String = HOME
var display_name: String = ""
var dir: String = ""

var credit: String = ""
var license: String = ""
var license_url: String = ""
var source_url: String = ""

## The background, already sorted out: "type" plus whatever that type needs.
var background: Dictionary = {}

## Props in the order they should be drawn, farthest first.
var props: Array[Dictionary] = []

var transition: String = TRANSITION_FADE
var pet_spot: Vector2 = DEFAULT_PET_SPOT

var problems: PackedStringArray = []


static func load_from_dir(folder: String) -> ScenePack:
	var json_path: String = folder.path_join(SCENE_JSON)
	if not FileAccess.file_exists(json_path):
		return _broken(folder, "no %s in %s" % [SCENE_JSON, folder])
	var text: String = FileAccess.get_file_as_string(json_path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _broken(folder, "%s is not valid JSON" % json_path)
	return from_dictionary(parsed, folder)


static func from_dictionary(data: Dictionary, folder: String) -> ScenePack:
	var pack := ScenePack.new()
	pack.dir = folder
	pack.id = str(data.get("id", folder.get_file())).strip_edges()
	# The role is what decides which slot this room fills. Folders named
	# after their role still work, because the folder name is the fallback.
	pack.role = str(data.get("role", folder.get_file())).strip_edges().to_lower()
	pack.display_name = str(data.get("name", pack.id)).strip_edges()
	pack.credit = str(data.get("credit", "")).strip_edges()
	pack.license = str(data.get("license", "")).strip_edges()
	pack.license_url = str(data.get("license_url", "")).strip_edges()
	pack.source_url = str(data.get("source_url", "")).strip_edges()

	if not ROLES.has(pack.role):
		pack.problems.append(
			"role \"%s\" is not one of %s" % [pack.role, ", ".join(ROLES)]
		)

	pack.transition = str(data.get("transition", TRANSITION_FADE)).strip_edges().to_lower()
	if pack.transition != TRANSITION_FADE and pack.transition != TRANSITION_SLIDE:
		pack.problems.append("transition \"%s\" is not fade or slide" % pack.transition)
		pack.transition = TRANSITION_FADE

	var spot: Variant = data.get("pet_spot", null)
	if spot is Dictionary:
		pack.pet_spot = Vector2(
			clampf(float((spot as Dictionary).get("x", DEFAULT_PET_SPOT.x)), 0.0, 1.0),
			clampf(float((spot as Dictionary).get("y", DEFAULT_PET_SPOT.y)), 0.0, 1.0)
		)

	pack._read_background(data.get("background", {}))
	pack._read_props(data.get("props", []))
	return pack


func is_valid() -> bool:
	return problems.is_empty()


## A room is worth showing as long as it knows which slot it fills. A
## missing picture costs a prop or falls the background back to something
## drawn in code; it never stops the room appearing.
func is_usable() -> bool:
	return ROLES.has(role)


func is_builtin() -> bool:
	return dir.begins_with("res://")


## The prop doing a particular job, or an empty Dictionary if the room has
## none. The main role wins; "<role>_alt" is only used as a backup.
func prop_with_role(wanted: String) -> Dictionary:
	for prop in props:
		if str(prop.get("role", "")) == wanted:
			return prop
	for prop in props:
		if str(prop.get("role", "")) == wanted + "_alt":
			return prop
	return {}


## Where the dog should stand to use that prop, or the room's normal spot.
func spot_for_role(wanted: String) -> Vector2:
	var prop: Dictionary = prop_with_role(wanted)
	if prop.is_empty():
		return pet_spot
	# Stand beside the prop, not on it. Nudging back towards the middle of
	# the room keeps the dog from covering the bowl it is eating from, and
	# from hanging off the edge when the prop is near one.
	return Vector2(lerpf(float(prop["x"]), 0.5, 0.35), float(prop["y"]))


func scrolls() -> bool:
	return bool(background.get("scroll", false))


# --- Reading the background ----------------------------------------------

func _read_background(raw: Variant) -> void:
	if not raw is Dictionary:
		_fall_back_background("the background is not described properly")
		return
	var data: Dictionary = raw
	var type: String = str(data.get("type", BG_GENERATED)).strip_edges().to_lower()

	match type:
		BG_IMAGE:
			_read_image_background(data)
		BG_TILED:
			_read_tiled_background(data)
		BG_GENERATED:
			_read_generated_background(data)
		_:
			_fall_back_background("background type \"%s\" is not one it knows" % type)


func _read_image_background(data: Dictionary) -> void:
	var file: String = str(data.get("file", "")).strip_edges()
	if file.is_empty() or not FileAccess.file_exists(dir.path_join(file)):
		_fall_back_background("the background picture %s is missing" % file)
		return
	background = {"type": BG_IMAGE, "file": file}


func _read_tiled_background(data: Dictionary) -> void:
	var wall: String = str(data.get("wall", "")).strip_edges()
	var floor_file: String = str(data.get("floor", "")).strip_edges()
	for file in [wall, floor_file]:
		if file.is_empty() or not FileAccess.file_exists(dir.path_join(file)):
			_fall_back_background("the tile image %s is missing" % file)
			return
	background = {
		"type": BG_TILED,
		"wall": wall,
		"floor": floor_file,
		# How much of the height the floor takes up.
		"floor_ratio": clampf(float(data.get("floor_ratio", 0.38)), 0.05, 0.95),
		# Whole numbers only; these are pixel art tiles.
		"tile_scale": maxi(1, int(data.get("tile_scale", 1))),
	}


func _read_generated_background(data: Dictionary) -> void:
	var style: String = str(data.get("style", "yard")).strip_edges().to_lower()
	if style != "yard" and style != "park":
		problems.append("background style \"%s\" is not yard or park" % style)
		style = "yard"
	background = {
		"type": BG_GENERATED,
		"style": style,
		"sky_top": _color(data, "sky_top", Color(0.56, 0.79, 0.94)),
		"sky_bottom": _color(data, "sky_bottom", Color(0.84, 0.94, 1.0)),
		"ground": _color(data, "ground", Color(0.49, 0.76, 0.42)),
		"ground_ratio": clampf(float(data.get("ground_ratio", 0.4)), 0.05, 0.95),
		"scroll": bool(data.get("scroll", false)),
		"scroll_speed_px": float(data.get("scroll_speed_px", 60.0)),
	}
	# A path is optional; only the park usually has one.
	if data.has("path"):
		background["path"] = _color(data, "path", Color(0.85, 0.76, 0.60))


# Anything unreadable becomes a plain drawn background rather than nothing.
# The room still appears; it just appears simpler than the author intended.
func _fall_back_background(reason: String) -> void:
	problems.append(reason + "; falling back to a drawn background")
	background = {
		"type": BG_GENERATED,
		"style": "yard",
		"sky_top": Color(0.56, 0.79, 0.94),
		"sky_bottom": Color(0.84, 0.94, 1.0),
		"ground": Color(0.49, 0.76, 0.42),
		"ground_ratio": 0.4,
		"scroll": false,
		"scroll_speed_px": 0.0,
	}


static func _color(data: Dictionary, key: String, fallback: Color) -> Color:
	if not data.has(key):
		return fallback
	return Color.from_string(str(data[key]), fallback)


# --- Reading the props ---------------------------------------------------

func _read_props(raw: Variant) -> void:
	if not raw is Array:
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			continue
		var data: Dictionary = entry
		var file: String = str(data.get("file", "")).strip_edges()
		if file.is_empty():
			continue
		# A missing picture costs that one prop and nothing else.
		if not FileAccess.file_exists(dir.path_join(file)):
			problems.append("the prop %s is missing; skipping it" % file)
			continue
		props.append({
			"file": file,
			# Fractions of the window. x is the middle of the prop, y is the
			# bottom of it, so props sit on things rather than float.
			"x": clampf(float(data.get("x", 0.5)), 0.0, 1.0),
			"y": clampf(float(data.get("y", 0.8)), 0.0, 1.0),
			"scale": maxi(1, int(data.get("scale", 1))),
			"role": str(data.get("role", "")).strip_edges(),
		})

	# Farthest first. Something lower down the window is nearer the viewer,
	# so it should be drawn later and overlap what is behind it.
	props.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["y"]) < float(b["y"])
	)


static func _broken(folder: String, reason: String) -> ScenePack:
	var pack := ScenePack.new()
	pack.dir = folder
	pack.id = folder.get_file()
	pack.display_name = pack.id
	pack.role = folder.get_file().to_lower()
	pack.problems.append(reason)
	pack._fall_back_background("there is nothing to draw")
	return pack
