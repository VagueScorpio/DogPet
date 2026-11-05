extends "res://tests/suite.gd"
## Headless tests for building a pack out of loose files - what the import
## wizard does once the questions have been answered.
##
## Run them from the project root with:
##
##   godot --headless --path . --script res://tests/test_builder.gd
##
## These write real PNGs into a scratch folder, install real packs out of
## them, and then read those packs back with PetPack and ScenePack. That last
## step is the whole point: a wizard that writes a manifest the app cannot
## load has not helped anybody.

const Builder := preload("res://scripts/pack_builder.gd")
const Install := preload("res://scripts/pack_install.gd")

var _scratch: String = ""
var _source: String = ""


func _initialize() -> void:
	_open("DogPet pack builder tests")

	_scratch = ProjectSettings.globalize_path("user://test_builder")
	_source = _scratch.path_join("source")
	_clean()
	DirAccess.make_dir_recursive_absolute(_source)

	_test_sorting()
	_test_names()
	_test_frames()
	_test_checks()
	_test_sprite_pack()
	_test_model_pack()
	_test_room_pack()

	_clean()
	_report()


# --- Working out what the owner handed over ------------------------------

func _test_sorting() -> void:
	_begin("Chosen files are sorted by what they are")
	var sorted: Dictionary = Builder.sort_sources([
		"a/dog.glb", "b/scene.gltf", "c/idle.PNG", "d/pack.zip",
		"e/dog.bin", "f/notes.txt",
	])
	_ok("finds the models", PackedStringArray(sorted["models"]).size() == 2)
	_ok("finds the pictures whatever the case", PackedStringArray(sorted["images"]).size() == 1)
	_ok("finds the zip", PackedStringArray(sorted["archives"]).size() == 1)
	_ok("keeps a .bin as a companion file", PackedStringArray(sorted["extras"]).size() == 1)
	_ok("lists what it cannot use", PackedStringArray(sorted["ignored"]).size() == 1)

	_begin("What those files could become")
	_ok("a model is a pet and nothing else",
		Builder.kinds_for(Builder.sort_sources(["a/dog.glb"])) == [Builder.Kind.PET_MODEL])
	_ok("a zip goes to the pack importer",
		Builder.kinds_for(Builder.sort_sources(["a/p.zip"])) == [Builder.Kind.PACK_ZIP])
	# A PNG is the ambiguous one: it could be a dog or it could be a wall.
	_ok("a picture could be either",
		Builder.kinds_for(Builder.sort_sources(["a/x.png"]))
		== [Builder.Kind.PET_SPRITE, Builder.Kind.ROOM])
	_ok("nothing usable offers nothing",
		Builder.kinds_for(Builder.sort_sources(["a/notes.txt"])).is_empty())


func _test_names() -> void:
	_begin("Names and file names are suggested, not demanded")
	_ok("a file name becomes a readable name",
		Builder.suggest_name("C:/art/pixel_pug-walk.png") == "Pixel Pug Walk")
	_ok("spaces and brackets are reduced",
		Builder.safe_file_name("C:/art/Walk Cycle (final).PNG") == "walk_cycle__final.png")
	_ok("an id is cleaned into something that can be a folder",
		Builder.clean_id("  My Cool Dog! ") == "my_cool_dog")
	# CON.png reduces to con.png, which Windows still reads as the console.
	_ok("a device name is prefixed rather than kept",
		Builder.safe_file_name("C:/art/CON.png") == "pack_con.png")


func _test_frames() -> void:
	_begin("Frame counts are guessed from the sheet")
	_ok("a four-frame strip of squares is spotted", Builder.guess_frames(Vector2i(128, 32)) == 4)
	_ok("a single square frame is one", Builder.guess_frames(Vector2i(32, 32)) == 1)
	# 45 x 43 is the shipped idle sheet: almost square, so one frame.
	_ok("an odd size falls back to one frame", Builder.guess_frames(Vector2i(45, 43)) == 1)
	_ok("an unreadable size is one frame", Builder.guess_frames(Vector2i(0, 0)) == 1)

	_begin("A sheet that does not divide evenly is refused")
	_ok("a clean division is fine",
		Builder.sheet_problem("walk.png", Vector2i(128, 32), 4).is_empty())
	_ok("an uneven one says so",
		Builder.sheet_problem("walk.png", Vector2i(45, 32), 4).contains("does not divide"))
	_ok("zero frames says so",
		Builder.sheet_problem("walk.png", Vector2i(45, 32), 0).contains("at least one frame"))
	_ok("an enormous sheet says so",
		Builder.sheet_problem("huge.png", Vector2i(20000, 20000), 1).contains("more than"))


# --- The answers are checked before anything is copied -------------------

func _test_checks() -> void:
	_begin("Incomplete answers are caught before anything is written")
	var empty: PackedStringArray = Install.check(Builder.Kind.PET_SPRITE, {})
	_ok("a missing folder name is caught", _says(empty, "folder name"))
	_ok("a missing display name is caught", _says(empty, "name to show"))
	_ok("no pictures given a job is caught", _says(empty, "given a job"))

	var idle_path: String = _write_png("idle.png", 32, 32)
	var no_idle: PackedStringArray = Install.check(Builder.Kind.PET_SPRITE, {
		"id": "dog", "name": "Dog",
		"sheets": [{"path": idle_path, "state": "walk", "frames": 1, "fps": 1.0}],
	})
	_ok("a pack with no idle picture is caught", _says(no_idle, "idle"))

	var twice: PackedStringArray = Install.check(Builder.Kind.PET_SPRITE, {
		"id": "dog", "name": "Dog",
		"sheets": [
			{"path": idle_path, "state": "idle", "frames": 1, "fps": 1.0},
			{"path": idle_path, "state": "idle", "frames": 1, "fps": 1.0},
		],
	})
	_ok("the same job given twice is caught", _says(twice, "pick one each"))

	var room: PackedStringArray = Install.check(Builder.Kind.ROOM, {
		"id": "kitchen", "name": "Kitchen", "role": "kitchen",
		"background": "image", "image": idle_path,
	})
	_ok("a room with an unknown slot is caught", _says(room, "which slot"))

	var gone: PackedStringArray = Install.check(Builder.Kind.PET_MODEL, {
		"id": "dog", "name": "Dog", "model": _source.path_join("not_here.glb"),
		"target_height": 1.0,
	})
	_ok("a model that has been moved away is caught", _says(gone, "could not be found"))


# --- Installing, then reading the pack back ------------------------------

func _test_sprite_pack() -> void:
	_begin("A sprite pet is installed and loads back")
	var idle_path: String = _write_png("Idle Frame.png", 32, 32)
	var walk_path: String = _write_png("walk.png", 128, 32)
	var target: String = _scratch.path_join("pets/pixel_dog")
	var plan: Dictionary = Install.plan(Builder.Kind.PET_SPRITE, {
		"id": "pixel_dog", "name": "Pixel Dog", "credit": "Someone, CC-BY",
		"pixel_art": true, "display_height_px": 160, "faces": "right",
		"sheets": [
			{"path": idle_path, "state": "idle", "frames": 1, "fps": 1.0},
			{"path": walk_path, "state": "walk", "frames": 4, "fps": 6.0},
		],
	}, target)

	_ok("the manifest is a pet.json", str(plan["manifest_name"]) == "pet.json")
	_ok("the awkward file name is cleaned on the way in",
		Dictionary(plan["copies"]).has("idle_frame.png"))
	_ok("installing reports no problems", Install.write(plan).is_empty())
	_ok("the pet.json is on the disk", FileAccess.file_exists(target.path_join("pet.json")))

	var pack: PetPack = PetPack.load_from_dir(target)
	_ok("the pack loads with no problems", pack.problems.is_empty())
	_ok("it is a sprite pack", pack.kind == PetPack.KIND_SPRITE2D)
	_ok("it kept the name", pack.display_name == "Pixel Dog")
	_ok("it kept the credit", pack.credit == "Someone, CC-BY")
	_ok("the walk has four frames", int(pack.sprite_animations["walk"]["frames"]) == 4)
	# Measured from the sheet rather than taken on trust: 128 / 4.
	_ok("the frame width was worked out", int(pack.sprite_animations["walk"]["frame_width"]) == 32)
	_ok("the pack is usable", pack.is_usable())


func _test_model_pack() -> void:
	_begin("A 3D pet keeps its own file names")
	# Not a real model - nothing here loads it. What matters is that a .gltf
	# and the .bin it refers to by name both arrive under those names.
	var model: String = _write_bytes("Dog Model.gltf", "{}")
	var bin: String = _write_bytes("Dog Model.bin", "x")
	var target: String = _scratch.path_join("pets/dog3d")
	var answers: Dictionary = {
		"id": "dog3d", "name": "Dog", "model": model, "extras": [bin],
		"target_height": 0.85, "rotation_y_degrees": -29.0, "credit": "Someone, CC-BY",
	}
	var plan: Dictionary = Install.plan(Builder.Kind.PET_MODEL, answers, target)

	var copies: Dictionary = plan["copies"]
	_ok("the model keeps its name", copies.has("Dog Model.gltf"))
	_ok("the companion file comes too, under its own name", copies.has("Dog Model.bin"))
	_ok("the manifest points at the model",
		str(Dictionary(plan["manifest"])["model"]) == "Dog Model.gltf")
	_ok("the facing was kept",
		is_equal_approx(float(Dictionary(plan["manifest"])["rotation_y_degrees"]), -29.0))
	_ok("installing reports no problems", Install.write(plan).is_empty())
	_ok("both files landed", FileAccess.file_exists(target.path_join("Dog Model.bin")))

	var pack: PetPack = PetPack.load_from_dir(target)
	_ok("the pack loads with no problems", pack.problems.is_empty())
	_close("the height was kept", pack.target_height, 0.85)

	_begin("What is said before installing, without standing in the way")
	# A credit-less pack installs fine and is then listed by the app as a
	# pack with a problem, so the wizard says so while the field is still up.
	answers.erase("credit")
	_ok("a missing credit is warned about",
		_says(Install.warnings(Builder.Kind.PET_MODEL, answers), "credit"))
	_ok("a .gltf is warned about too",
		_says(Install.warnings(Builder.Kind.PET_MODEL, answers), "separate files"))
	answers["credit"] = "Someone"
	answers["model"] = _write_bytes("dog.glb", "glTF")
	_ok("a credited .glb has nothing to warn about",
		Install.warnings(Builder.Kind.PET_MODEL, answers).is_empty())
	_ok("and nothing standing in its way either",
		Install.check(Builder.Kind.PET_MODEL, answers).is_empty())

	# Your own art is the case the credit rule was never written for.
	answers.erase("credit")
	answers["credit_not_required"] = true
	_ok("a pack of your own art is not asked for a credit",
		Install.warnings(Builder.Kind.PET_MODEL, answers).is_empty())
	var mine: Dictionary = Builder.model_pet_manifest(answers)
	_ok("and the pack says so in writing", bool(mine["credit_not_required"]))
	_ok("with no empty credit left behind", not mine.has("credit"))
	answers["credit_not_required"] = false
	_ok("a pack that does not say so is still asked",
		_says(Install.warnings(Builder.Kind.PET_MODEL, answers), "credit"))
	_ok("and says nothing in writing either",
		not Builder.model_pet_manifest(answers).has("credit_not_required"))


func _test_room_pack() -> void:
	_begin("A room is installed and loads back")
	var wall: String = _write_png("wall.png", 32, 32)
	var floor_tile: String = _write_png("floor.png", 32, 32)
	var bowl: String = _write_png("bowl.png", 64, 64)
	var target: String = _scratch.path_join("scenes/my_kitchen")
	var plan: Dictionary = Install.plan(Builder.Kind.ROOM, {
		"id": "my_kitchen", "name": "My Kitchen", "role": "eat",
		"background": "tiled", "wall": wall, "floor": floor_tile,
		"floor_ratio": 0.38, "tile_scale": 4,
		"props": [{"path": bowl, "x": 0.78, "y": 0.78, "scale": 3, "role": "food_bowl"}],
	}, target)

	_ok("the manifest is a scene.json", str(plan["manifest_name"]) == "scene.json")
	_ok("installing reports no problems", Install.write(plan).is_empty())

	var room: ScenePack = ScenePack.load_from_dir(target)
	_ok("the room loads with no problems", room.problems.is_empty())
	_ok("it fills the eat slot", room.role == ScenePack.EAT)
	_ok("it is tiled", str(room.background["type"]) == ScenePack.BG_TILED)
	_ok("the bowl came with it", not room.prop_with_role(ScenePack.ROLE_FOOD_BOWL).is_empty())
	_ok("the room is usable", room.is_usable())

	_begin("Two pictures with the same name do not overwrite each other")
	DirAccess.make_dir_recursive_absolute(_source.path_join("other"))
	var second: String = _write_png("other/wall.png", 16, 16)
	var clash: Dictionary = Install.plan(Builder.Kind.ROOM, {
		"id": "clash", "name": "Clash", "role": "home",
		"background": "image", "image": wall,
		"props": [{"path": second, "x": 0.5, "y": 0.8, "scale": 1, "role": ""}],
	}, _scratch.path_join("scenes/clash"))
	_ok("the second one is renamed", Dictionary(clash["copies"]).has("wall_2.png"))
	_ok("the prop points at the renamed copy",
		str(Dictionary(clash["manifest"])["props"][0]["file"]) == "wall_2.png")


# --- Scratch files -------------------------------------------------------

# A real PNG of the given size, so ImageLimits can read its header and
# PetPack can measure its frames.
func _write_png(name: String, width: int, height: int) -> String:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.4, 0.2, 1.0))
	var path: String = _source.path_join(name)
	image.save_png(path)
	return path


func _write_bytes(name: String, contents: String) -> String:
	var path: String = _source.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)
		file.close()
	return path


func _says(problems: PackedStringArray, phrase: String) -> bool:
	for problem in problems:
		if problem.contains(phrase):
			return true
	return false


func _clean() -> void:
	PackArchive.empty_folder(_scratch)
	DirAccess.remove_absolute(_scratch)
