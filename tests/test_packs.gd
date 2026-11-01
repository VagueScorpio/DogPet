extends "res://tests/suite.gd"
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
const Links := preload("res://scripts/pack_links.gd")
const Sizes := preload("res://scripts/zip_sizes.gd")

var _scratch: String = ""


func _initialize() -> void:
	_open("DogPet pack tests")

	_scratch = ProjectSettings.globalize_path("user://test_packs")
	_clean()
	DirAccess.make_dir_recursive_absolute(_scratch)

	_test_zip_slip()
	_test_zip_sizes()
	_test_pack_links()
	_test_inspect()
	_test_round_trip()
	_test_broken_zips()

	_clean()

	_report()


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

	# RT-13. Windows resolves these to devices rather than files whatever folder
	# they sit in and whatever extension they carry, so assets/pets/x/CON is the
	# console. Nothing was known to go wrong, but a serial port can block when
	# opened, and that is a "probably fine" not worth keeping.
	for device in ["CON", "sub/NUL", "COM1.png", "lpt3", "CON.txt", "pack/aux"]:
		_ok("refuses the device name %s" % device, not Archive.is_safe_entry(device))
	# And names that merely look like one are still perfectly fine, which is
	# why this is not a prefix match.
	for fine in ["console.png", "aux_bits/idle.png", "nullify.png", "common/pet.json"]:
		_ok("still allows %s" % fine, Archive.is_safe_entry(fine))

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


# --- How big the zip says it is ------------------------------------------

# A zip's compression ratio has no ceiling, so a pack of a few hundred KB can
# declare gigabytes - and ZIPReader.read_file allocates whatever an entry
# declares before reading a byte of it. The declared sizes are read out of the
# zip's index first, and anything implausible is refused rather than read.
func _test_zip_sizes() -> void:
	_begin("A zip is measured from its index before it is read")

	# A perfectly ordinary pack, for the figures to be checked against.
	var plain: String = _scratch.path_join("sizes.zip")
	var plain_manifest := '{"id":"sizes","kind":"model3d","model":"m.glb","credit":"x"}'
	var packer := ZIPPacker.new()
	packer.open(plain)
	_add(packer, "pet.json", plain_manifest)
	_add(packer, "notes.txt", "0123456789")
	packer.close()

	var measured: Dictionary = Sizes.read(plain)
	_ok("an ordinary zip can be measured", str(measured["problem"]).is_empty())
	_ok("it reports the right size for a known entry",
		Sizes.size_of(measured["sizes"], "notes.txt") == 10)
	_ok("and the right total",
		int(measured["total"]) == 10 + plain_manifest.to_utf8_buffer().size())
	_ok("an entry it does not list comes back as -1",
		Sizes.size_of(measured["sizes"], "nothing.png") == -1)
	_ok("and such a zip is still accepted", Archive.inspect(plain)["problems"].is_empty())

	# A manifest far larger than any manifest needs to be. Compressible
	# padding, exactly as a real bomb would use, with a valid manifest behind
	# it so nothing but the size can refuse it.
	var bomb: String = _scratch.path_join("bomb.zip")
	var padding: String = " ".repeat(Archive.MAX_MANIFEST_BYTES + 1024)
	packer = ZIPPacker.new()
	packer.open(bomb)
	_add(packer, "pet.json", padding + '{"id":"bomb","kind":"model3d","model":"m.glb","credit":"x"}')
	packer.close()
	var bomb_found: Dictionary = Archive.inspect(bomb)
	_ok("an over-large manifest is refused", not bomb_found["problems"].is_empty())
	_ok("the owner is told it was the size",
		not bomb_found["problems"].is_empty()
		and str(bomb_found["problems"][0]).contains("more than"))
	_ok("the zip on disk is far smaller than what it declared",
		FileAccess.open(bomb, FileAccess.READ).get_length() < Archive.MAX_MANIFEST_BYTES)

	# And extracting one is refused too, in case anything ever skips inspect.
	var unpacked: String = _scratch.path_join("bomb_out")
	var extract_problems: PackedStringArray = Archive.extract(bomb, "", unpacked)
	_ok("extracting it is refused as well", not extract_problems.is_empty())
	_ok("and nothing of it was written",
		not FileAccess.file_exists(unpacked.path_join("pet.json")))

	# Too many entries to be a pack.
	var many: String = _scratch.path_join("many.zip")
	packer = ZIPPacker.new()
	packer.open(many)
	_add(packer, "pet.json", '{"id":"many","kind":"model3d","model":"m.glb","credit":"x"}')
	for index in Archive.MAX_ENTRIES + 1:
		_add(packer, "f%d.txt" % index, "x")
	packer.close()
	_ok("a zip with too many files in it is refused",
		not Archive.inspect(many)["problems"].is_empty())

	# Things that are not measurable at all are refused, not read hopefully.
	var not_a_zip: String = _scratch.path_join("notazip.zip")
	var file: FileAccess = FileAccess.open(not_a_zip, FileAccess.WRITE)
	file.store_string("this is not a zip, whatever its name says")
	file.close()
	_ok("a file that is not a zip cannot be measured",
		not str(Sizes.read(not_a_zip)["problem"]).is_empty())

	var truncated: String = _scratch.path_join("truncated.zip")
	var whole: PackedByteArray = FileAccess.get_file_as_bytes(plain)
	var cut: FileAccess = FileAccess.open(truncated, FileAccess.WRITE)
	cut.store_buffer(whole.slice(0, whole.size() / 2))
	cut.close()
	_ok("a zip cut in half cannot be measured",
		not str(Sizes.read(truncated)["problem"]).is_empty())
	_ok("and is refused rather than read",
		not Archive.inspect(truncated)["problems"].is_empty())

	_ok("a missing file cannot be measured",
		not str(Sizes.read(_scratch.path_join("nothing-here.zip"))["problem"]).is_empty())

	_ok("sizes are described in words the owner can read",
		Sizes.describe_bytes(512) == "512 bytes"
		and Sizes.describe_bytes(262144) == "256.0 KB"
		and Sizes.describe_bytes(629145600) == "600.0 MB")


# --- The other nasty case ------------------------------------------------

# A pack says in its own JSON where its licence and source links point, and a
# clicked link reaches OS.shell_open - which will launch a program, open a
# document, resolve a bare name off the PATH, or hand the string to any
# protocol handler. So only a plain web address may ever be made clickable.
func _test_pack_links() -> void:
	_begin("Only plain web addresses become clickable links")

	# The two the shipped pug pack actually uses.
	for good in [
		"https://creativecommons.org/licenses/by/3.0/",
		"https://poly.pizza/m/3nFZQW8yojl",
		"http://example.com/licence.txt",
	]:
		_ok("allowed: %s" % good, Links.is_web_url(good))

	_ok("the scheme is matched whatever its case",
		Links.is_web_url("HTTPS://Example.COM/x"))
	_ok("surrounding whitespace is trimmed rather than refused",
		Links.web_url("  https://example.com/x  ") == "https://example.com/x")

	var backslash: String = String.chr(92)
	for bad in [
		"calc.exe",                                   # resolved off the PATH
		"C:/Windows/System32/calc.exe",               # a program by full path
		"file:///C:/Windows/System32/calc.exe",       # the same, as a URI
		backslash + backslash + "host" + backslash + "share" + backslash + "p.exe",
		"ms-settings:",                               # a protocol handler
		"javascript:alert(1)",
		"pack.zip",
		"",
		"   ",
		"https://",                                   # nothing to open
		"https://example.com/a b",                    # whitespace inside
		"https://example.com/a" + String.chr(10) + "calc.exe",
	]:
		_ok("refused: %s" % (bad if not bad.strip_edges().is_empty() else "(blank)"),
			not Links.is_web_url(bad))


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

	# RT-08. Importing over an existing pack wrote the new files on top and
	# removed nothing, so every file the new pack did not happen to overwrite
	# survived - a pet.json with no walk strip listed, and the old walk.png
	# still sitting beside it. "Replace" has to mean replace.
	_begin("Replacing a pack does not leave the old one's files behind")
	var existing: String = _scratch.path_join("existing_pack")
	DirAccess.make_dir_recursive_absolute(existing.path_join("extra"))
	for stale in ["pet.json", "walk.png", "extra/old.png"]:
		var leftover: FileAccess = FileAccess.open(existing.path_join(stale), FileAccess.WRITE)
		leftover.store_string("stale")
		leftover.close()
	_ok("the stale files are there to begin with",
		FileAccess.file_exists(existing.path_join("walk.png")))

	Archive.empty_folder(existing)
	_ok("the folder itself survives", DirAccess.dir_exists_absolute(existing))
	_ok("the stale file is gone", not FileAccess.file_exists(existing.path_join("walk.png")))
	_ok("so is the stale manifest", not FileAccess.file_exists(existing.path_join("pet.json")))
	_ok("and a nested stale folder with it",
		not DirAccess.dir_exists_absolute(existing.path_join("extra")))

	# Then the new pack goes in, and only the new pack is there.
	Archive.extract(zip_path, "", existing)
	_ok("the replacing pack landed", FileAccess.file_exists(existing.path_join("pet.json")))
	_ok("and it loads", PetPack.load_from_dir(existing).is_usable())
	# Emptying a folder that is not there must simply do nothing rather than
	# error, because _do_import reaches it on paths that may not exist yet.
	var absent: String = _scratch.path_join("never_existed")
	Archive.empty_folder(absent)
	_ok("emptying a folder that is not there is harmless",
		not DirAccess.dir_exists_absolute(absent))


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
