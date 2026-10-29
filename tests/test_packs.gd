extends SceneTree
## Headless tests for importing and exporting pack zips.
##
## Run them from the project root with:
##
##   godot --headless --path . --script res://tests/test_packs.gd
##
## These build real zips in a scratch folder and read them back, because the
## interesting cases - a pack nested in a folder, a zip with no manifest, an
## archive trying to write outside the folder it is unpacked into - are all
## about what is actually in the file rather than what we meant to put there.

const Archive := preload("res://scripts/pack_archive.gd")

var _passed: int = 0
var _failed: int = 0
var _scratch: String = ""


func _initialize() -> void:
	print("")
	print("DogPet pack tests")
	print("=================")

	_scratch = ProjectSettings.globalize_path("user://test_packs")
	_clean()
	DirAccess.make_dir_recursive_absolute(_scratch)

	_test_zip_slip()
	_test_inspect()
	_test_round_trip()
	_test_broken_zips()

	_clean()

	print("")
	print("=================")
	print("%d passed, %d failed" % [_passed, _failed])
	print("TESTS FAILED" if _failed > 0 else "All good.")
	quit(1 if _failed > 0 else 0)


# --- The nasty case ------------------------------------------------------

func _test_zip_slip() -> void:
	_begin("Entries that try to escape the folder are refused")
	# A zip can name its entries anything at all, and an import that trusts
	# them will happily write wherever it is told.
	for nasty in [
		"../evil.txt",
		"..\\evil.txt",
		"pack/../../evil.txt",
		"/etc/passwd",
		"C:/Windows/System32/evil.dll",
		"C:\\Windows\\evil.dll",
		"pack/../../../home/someone/.ssh/authorized_keys",
	]:
		_ok("refuses %s" % nasty, not Archive.is_safe_entry(nasty))

	_begin("Ordinary entries are allowed")
	for fine in ["pet.json", "pack/pet.json", "pack/art/idle.png", "a/b/c/d.png"]:
		_ok("allows %s" % fine, Archive.is_safe_entry(fine))
	_ok("refuses an empty name", not Archive.is_safe_entry(""))
	# A file merely containing dots is not the same as a ".." path part.
	_ok("allows a file with dots in it", Archive.is_safe_entry("pack/my..thing.png"))

	_begin("A zip containing an escape is rejected whole")
	var path: String = _scratch.path_join("nasty.zip")
	var packer := ZIPPacker.new()
	packer.open(path)
	_add(packer, "pet.json", '{"id":"x","kind":"model3d","model":"m.glb","credit":"c"}')
	_add(packer, "../escaped.txt", "gotcha")
	packer.close()

	var found: Dictionary = Archive.inspect(path)
	_ok("it is not usable", not found["problems"].is_empty())
	_ok("and it says why", str(found["problems"][0]).contains("unsafe"))


# --- Looking inside a zip ------------------------------------------------

func _test_inspect() -> void:
	_begin("A pet pack at the top level")
	var flat: String = _scratch.path_join("flat.zip")
	var packer := ZIPPacker.new()
	packer.open(flat)
	_add(packer, "pet.json", '{"id":"beagle","name":"Beagle","kind":"model3d","credit":"me"}')
	_add(packer, "model.glb", "not really a model")
	packer.close()

	var found: Dictionary = Archive.inspect(flat)
	_ok("nothing wrong with it", found["problems"].is_empty())
	_ok("it is a pet pack", found["kind"] == Archive.Kind.PET)
	_ok("its id came through", found["id"] == "beagle")
	_ok("its name came through", found["name"] == "Beagle")
	_ok("there is no folder to strip", str(found["root"]).is_empty())

	_begin("A pet pack inside one folder")
	var nested: String = _scratch.path_join("nested.zip")
	packer = ZIPPacker.new()
	packer.open(nested)
	_add(packer, "beagle_pack/pet.json", '{"id":"beagle","kind":"sprite2d","credit":"me"}')
	_add(packer, "beagle_pack/idle.png", "x")
	packer.close()

	found = Archive.inspect(nested)
	_ok("still fine", found["problems"].is_empty())
	_ok("the folder is noted so it can be flattened", found["root"] == "beagle_pack")

	_begin("A room pack declares the slot it fills")
	var room: String = _scratch.path_join("room.zip")
	packer = ZIPPacker.new()
	packer.open(room)
	_add(packer, "night_kitchen/scene.json", '{"id":"night_kitchen","role":"eat","name":"Night"}')
	packer.close()

	found = Archive.inspect(room)
	_ok("nothing wrong with it", found["problems"].is_empty())
	_ok("it is a room", found["kind"] == Archive.Kind.SCENE)
	_ok("its role came through", found["role"] == "eat")

	_begin("A room filling no known slot is refused")
	var bad_room: String = _scratch.path_join("bad_room.zip")
	packer = ZIPPacker.new()
	packer.open(bad_room)
	_add(packer, "scene.json", '{"id":"bathroom","role":"bathroom"}')
	packer.close()
	found = Archive.inspect(bad_room)
	_ok("it is rejected", not found["problems"].is_empty())

	_begin("Ids are made safe to use as folder names")
	var messy: String = _scratch.path_join("messy.zip")
	packer = ZIPPacker.new()
	packer.open(messy)
	_add(packer, "pet.json", '{"id":"My Dog/../x","kind":"model3d","credit":"me"}')
	packer.close()
	found = Archive.inspect(messy)
	var id: String = str(found["id"])
	_ok("no slashes survive", not id.contains("/"))
	_ok("no dots survive", not id.contains(".."))
	_ok("it is lower case", id == id.to_lower())
	_ok("and there is still something left", not id.is_empty())


# --- Out and back again --------------------------------------------------

func _test_round_trip() -> void:
	_begin("A real pet pack exports and imports again")
	var source: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	source = source.path_join("assets/pets/pug_pixel")
	var zip_path: String = _scratch.path_join("pug_pixel.zip")

	var problems: PackedStringArray = Archive.write_pack(source, zip_path, "Nasha's Cozy Pets Pack")
	_ok("it exported without complaint", problems.is_empty())
	_ok("the zip exists", FileAccess.file_exists(zip_path))

	var found: Dictionary = Archive.inspect(zip_path)
	_ok("and reads back as a pet pack", found["kind"] == Archive.Kind.PET)
	_ok("with nothing wrong", found["problems"].is_empty())
	_ok("keeping its id", found["id"] == "pug_pixel")

	var files: PackedStringArray = found["files"]
	_ok("pet.json is in there", files.has("pet.json"))
	_ok("so is the idle art", files.has("idle.png"))
	_ok("and the walk strip", files.has("walk.png"))
	_ok("and a credits file travels with it", files.has(Archive.CREDITS_FILE))

	_begin("Unpacking puts the files where they belong")
	var target: String = _scratch.path_join("imported_pug")
	problems = Archive.extract(zip_path, str(found["root"]), target)
	_ok("it unpacked without complaint", problems.is_empty())
	_ok("pet.json landed", FileAccess.file_exists(target.path_join("pet.json")))
	_ok("idle.png landed", FileAccess.file_exists(target.path_join("idle.png")))
	_ok("walk.png landed", FileAccess.file_exists(target.path_join("walk.png")))

	_begin("And the unpacked copy is a working pack")
	var pack: PetPack = PetPack.load_from_dir(target)
	_ok("it loads", pack.is_usable())
	_ok("it is the pixel pug", pack.id == "pug_pixel")
	_ok("its frames measure the same", pack.tallest_frame_height() == 43)
	_ok("its credit survived the trip", not pack.credit.is_empty())

	_begin("A nested pack is flattened on the way in")
	var nested: String = _scratch.path_join("nested2.zip")
	var packer := ZIPPacker.new()
	packer.open(nested)
	_add(packer, "some_folder/pet.json", '{"id":"x","kind":"model3d","model":"m.glb","credit":"c"}')
	_add(packer, "some_folder/m.glb", "fake")
	packer.close()
	var info: Dictionary = Archive.inspect(nested)
	var flat_target: String = _scratch.path_join("flattened")
	Archive.extract(nested, str(info["root"]), flat_target)
	_ok("pet.json is at the top", FileAccess.file_exists(flat_target.path_join("pet.json")))
	_ok(
		"not still inside its folder",
		not FileAccess.file_exists(flat_target.path_join("some_folder/pet.json"))
	)


# --- Zips that are no good ----------------------------------------------

func _test_broken_zips() -> void:
	_begin("A zip with no pack in it")
	var empty_ish: String = _scratch.path_join("nothing.zip")
	var packer := ZIPPacker.new()
	packer.open(empty_ish)
	_add(packer, "readme.txt", "hello")
	packer.close()
	var found: Dictionary = Archive.inspect(empty_ish)
	_ok("it is rejected", not found["problems"].is_empty())
	_ok("it says what is missing", str(found["problems"][0]).contains("pet.json"))

	_begin("A pack whose manifest is not JSON")
	var broken: String = _scratch.path_join("broken.zip")
	packer = ZIPPacker.new()
	packer.open(broken)
	_add(packer, "pet.json", "{ this is not json")
	packer.close()
	found = Archive.inspect(broken)
	_ok("it is rejected", not found["problems"].is_empty())
	_ok("and it says so plainly", str(found["problems"][0]).contains("not valid JSON"))

	_begin("A file that is not a zip at all")
	var not_zip: String = _scratch.path_join("notazip.zip")
	var file: FileAccess = FileAccess.open(not_zip, FileAccess.WRITE)
	file.store_string("I am a text file wearing a hat")
	file.close()
	found = Archive.inspect(not_zip)
	_ok("it is rejected", not found["problems"].is_empty())

	_begin("A zip that is not there")
	found = Archive.inspect(_scratch.path_join("ghost.zip"))
	_ok("it is rejected rather than crashing", not found["problems"].is_empty())

	_begin("Exporting a folder that does not exist")
	var problems: PackedStringArray = Archive.write_pack(
		_scratch.path_join("no_such_folder"), _scratch.path_join("out.zip"), ""
	)
	_ok("says there was nothing to pack", not problems.is_empty())


# --- Small helpers -------------------------------------------------------

func _add(packer: ZIPPacker, name: String, contents: String) -> void:
	packer.start_file(name)
	packer.write_file(contents.to_utf8_buffer())
	packer.close_file()


func _clean() -> void:
	_remove_tree(_scratch)


func _remove_tree(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			if dir.current_is_dir():
				_remove_tree(folder.path_join(name))
			else:
				DirAccess.remove_absolute(folder.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(folder)


func _begin(section: String) -> void:
	print("")
	print(section)


func _ok(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
