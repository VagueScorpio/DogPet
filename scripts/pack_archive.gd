class_name PackArchive
extends RefCounted
## Reading and writing pack .zip files, so packs can be shared.
##
## A pack zip holds a pet.json or a scene.json, either at the top level or
## inside one folder, plus whatever art it refers to. Exporting writes one;
## importing reads one, checks it over and unpacks it into assets/.
##
## Nothing here logs or touches a node, so the tests can make a zip, break
## it in a specific way, and check what happens - including the nasty case,
## an archive whose entries try to escape the folder they are unpacked into.

enum Kind { UNKNOWN, PET, SCENE }

# Reached by preload rather than by its class_name: a newly added script is not
# in the editor-generated class cache until the editor has rescanned.
const ZipSizes := preload("res://scripts/zip_sizes.gd")

const PET_JSON := "pet.json"
const SCENE_JSON := "scene.json"
const CREDITS_FILE := "CREDITS.txt"

## Files that have no business being in a pack.
const SKIPPED_NAMES: PackedStringArray = [".gdignore", "Thumbs.db", ".DS_Store", "desktop.ini"]

## Names Windows resolves to devices rather than to files, whatever folder they
## sit in and whatever extension they carry: assets/pets/x/CON is the console.
##
## Nothing is known to go wrong - FileAccess.open on one of these fails and
## extract records that and carries on - but opening a serial port can block,
## and that is a "probably fine" worth five lines to be rid of.
const DEVICE_NAMES: PackedStringArray = [
	"CON", "PRN", "AUX", "NUL",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
]

## How much this will read out of a zip.
##
## A zip's compression ratio is unbounded, so a pack of a few hundred KB can
## hold gigabytes - and ZIPReader.read_file allocates whatever an entry says it
## is before reading a byte of it. A 597 KB zip took 3 GB this way. These are
## the ceilings, checked against the sizes in the zip's own index before
## anything is read.
##
## Hard-coded on purpose, where every other number in this app lives in
## settings.json: a limit the owner can edit is a limit an imported pack could
## edit, and then it is not a limit.
##
## A manifest is a few hundred bytes in practice; the shipped pug's pet.json is
## about five hundred. This ceiling also covers turning it into a String
## afterwards, which costs up to four bytes for every byte read.
const MAX_MANIFEST_BYTES := 262144
## Generous for a .glb or a sprite sheet, both of which run to a few MB.
const MAX_FILE_BYTES := 67108864
const MAX_TOTAL_BYTES := 268435456
const MAX_ENTRIES := 512


## Look inside a zip without unpacking it.
##
## Returns what kind of pack it is, which folder inside the zip holds it,
## the id it wants to be unpacked as, and anything wrong with it. An empty
## "problems" means it is safe to extract.
static func inspect(zip_path: String) -> Dictionary:
	var result: Dictionary = {
		"kind": Kind.UNKNOWN,
		"root": "",
		"id": "",
		"name": "",
		"role": "",
		"files": PackedStringArray(),
		"problems": PackedStringArray(),
	}

	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		result["problems"].append("that file could not be opened as a zip")
		return result

	var entries: PackedStringArray = reader.get_files()
	if entries.is_empty():
		result["problems"].append("the zip is empty")
		reader.close()
		return result

	# Every entry has to be safe before anything is unpacked anywhere, and
	# small enough to read before anything is read at all.
	for entry in entries:
		if not is_safe_entry(entry):
			result["problems"].append("the zip contains an unsafe path: %s" % entry)
	var measured: Dictionary = measure(zip_path, entries)
	for problem in measured["problems"]:
		result["problems"].append(problem)
	if not result["problems"].is_empty():
		reader.close()
		return result

	var manifest: String = _find_manifest(entries)
	if manifest.is_empty():
		result["problems"].append("no %s or %s found in the zip" % [PET_JSON, SCENE_JSON])
		reader.close()
		return result

	# The manifest has a tighter ceiling than the art does, because it is the
	# one entry that gets turned into a String and parsed.
	var manifest_bytes: int = ZipSizes.size_of(measured["sizes"], manifest)
	if manifest_bytes > MAX_MANIFEST_BYTES:
		result["problems"].append("the pack's %s is %s, more than the %s this app will read" % [
			manifest.get_file(),
			ZipSizes.describe_bytes(manifest_bytes),
			ZipSizes.describe_bytes(MAX_MANIFEST_BYTES),
		])
		reader.close()
		return result

	result["root"] = manifest.get_base_dir()
	result["kind"] = Kind.PET if manifest.get_file() == PET_JSON else Kind.SCENE
	result["files"] = entries

	var text: String = reader.read_file(manifest).get_string_from_utf8()
	reader.close()

	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		result["problems"].append("the %s in the zip is not valid JSON" % manifest.get_file())
		return result

	var data: Dictionary = parsed
	# Fall back to the folder inside the zip, then to the zip's own name, so
	# a pack without an id still lands somewhere sensible.
	var fallback: String = result["root"] if not str(result["root"]).is_empty() \
		else zip_path.get_file().get_basename()
	result["id"] = _clean_id(str(data.get("id", fallback)))
	result["name"] = str(data.get("name", result["id"]))
	result["role"] = str(data.get("role", "")).to_lower()

	if str(result["id"]).is_empty():
		result["problems"].append("the pack has no usable id")

	if result["kind"] == Kind.SCENE:
		var role: String = str(result["role"])
		if role.is_empty():
			# A room with no role gets one from its folder name, same as on
			# disk. If that is no good either, say so.
			result["role"] = _clean_id(fallback)
			role = str(result["role"])
		if not ScenePack.ROLES.has(role):
			result["problems"].append(
				"the room fills no known slot (role \"%s\")" % role
			)

	return result


## Unpack a checked zip into a folder, flattening the pack's own folder away
## so the files land directly inside the target.
static func extract(zip_path: String, root_inside_zip: String, target_dir: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		problems.append("that file could not be opened as a zip")
		return problems

	if DirAccess.make_dir_recursive_absolute(target_dir) != OK:
		problems.append("could not make the folder %s" % target_dir)
		reader.close()
		return problems

	var prefix: String = root_inside_zip
	if not prefix.is_empty() and not prefix.ends_with("/"):
		prefix += "/"

	# Measured once, up front, for the same reason inspect does it: read_file
	# allocates whatever an entry claims to be, so the claim is checked before
	# the read rather than after it.
	var measured: Dictionary = ZipSizes.read(zip_path)
	var sizes: Dictionary = measured["sizes"]
	var measurable: bool = str(measured["problem"]).is_empty()
	if not measurable:
		problems.append("could not measure the zip: %s" % str(measured["problem"]))
		reader.close()
		return problems
	var written_bytes: int = 0

	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		if not is_safe_entry(entry):
			problems.append("skipped an unsafe path: %s" % entry)
			continue
		if not prefix.is_empty() and not entry.begins_with(prefix):
			continue

		var bytes: int = ZipSizes.size_of(sizes, entry)
		# A manifest keeps its own tighter ceiling here as well as in inspect.
		# It is not about this write - a 60 MB pet.json on disk would be within
		# the per-file limit and harmless to copy - but about every later read
		# of it: PetPack and ScenePack load it with get_file_as_string and
		# parse it on each AssetLibrary.reload().
		var ceiling: int = MAX_FILE_BYTES
		var file_name: String = entry.get_file()
		if file_name == PET_JSON or file_name == SCENE_JSON:
			ceiling = MAX_MANIFEST_BYTES
		if bytes < 0 or bytes > ceiling:
			problems.append("skipped %s: %s" % [
				file_name,
				"the zip's index does not mention it" if bytes < 0
				else "it is %s, more than the %s this app will read" % [
					ZipSizes.describe_bytes(bytes),
					ZipSizes.describe_bytes(ceiling),
				],
			])
			continue
		if written_bytes + bytes > MAX_TOTAL_BYTES:
			problems.append("stopped at %s: the pack is past the %s this app will unpack" % [
				entry.get_file(), ZipSizes.describe_bytes(MAX_TOTAL_BYTES),
			])
			break
		written_bytes += bytes

		var relative: String = entry.substr(prefix.length())
		if relative.is_empty() or SKIPPED_NAMES.has(relative.get_file()):
			continue

		var destination: String = target_dir.path_join(relative)
		var folder: String = destination.get_base_dir()
		if folder != target_dir and DirAccess.make_dir_recursive_absolute(folder) != OK:
			problems.append("could not make the folder %s" % folder)
			continue

		var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			problems.append("could not write %s" % relative)
			continue
		file.store_buffer(reader.read_file(entry))
		file.close()

	reader.close()
	return problems


## Write a folder out as a pack zip, with a CREDITS.txt alongside so the
## credit travels with the art rather than being left behind.
static func write_pack(folder: String, zip_path: String, credit: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	var packer := ZIPPacker.new()
	if packer.open(zip_path) != OK:
		problems.append("could not write to %s" % zip_path)
		return problems

	var written: int = 0
	for name in _files_in(folder):
		if SKIPPED_NAMES.has(name.get_file()):
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(folder.path_join(name))
		if bytes.is_empty() and FileAccess.get_open_error() != OK:
			problems.append("could not read %s" % name)
			continue
		packer.start_file(name)
		packer.write_file(bytes)
		packer.close_file()
		written += 1

	if not credit.strip_edges().is_empty():
		packer.start_file(CREDITS_FILE)
		packer.write_file(_credits_text(credit).to_utf8_buffer())
		packer.close_file()

	packer.close()
	if written == 0:
		problems.append("there was nothing in %s to pack" % folder)
	return problems


## Read the zip's own index and say whether what it claims to hold is within
## the ceilings above.
##
## Returns {"sizes": {entry: bytes}, "problems": PackedStringArray}. The sizes
## are the figures ZIPReader.read_file will allocate from, so checking them is
## checking the memory. A zip that cannot be measured is refused outright
## rather than read hopefully.
static func measure(zip_path: String, entries: PackedStringArray) -> Dictionary:
	var problems: PackedStringArray = []

	if entries.size() > MAX_ENTRIES:
		problems.append("the zip holds %d files, more than the %d this app will unpack" % [
			entries.size(), MAX_ENTRIES,
		])
		return {"sizes": {}, "problems": problems}

	var measured: Dictionary = ZipSizes.read(zip_path)
	if not str(measured["problem"]).is_empty():
		problems.append(str(measured["problem"]))
		return {"sizes": {}, "problems": problems}

	var sizes: Dictionary = measured["sizes"]
	if int(measured["total"]) > MAX_TOTAL_BYTES:
		problems.append("the pack unpacks to %s, more than the %s this app will read" % [
			ZipSizes.describe_bytes(int(measured["total"])),
			ZipSizes.describe_bytes(MAX_TOTAL_BYTES),
		])
		return {"sizes": sizes, "problems": problems}

	for entry in entries:
		var bytes: int = ZipSizes.size_of(sizes, entry)
		if bytes < 0:
			problems.append("the zip's index does not mention %s" % entry)
			continue
		if bytes > MAX_FILE_BYTES:
			problems.append("%s is %s, more than the %s this app will read" % [
				entry.get_file(),
				ZipSizes.describe_bytes(bytes),
				ZipSizes.describe_bytes(MAX_FILE_BYTES),
			])

	return {"sizes": sizes, "problems": problems}


## Empty a folder without removing the folder itself.
##
## What makes "Replace this pack?" mean it. Importing over an existing pack used
## to write the new files on top and remove nothing, so every file the new pack
## did not happen to overwrite survived - a pet.json that no longer lists a walk
## strip, with the old walk.png still beside it. The dialog said "replaced"; the
## behaviour was a merge.
##
## The caller must have taken a backup first. PackTransfer does, and checks it
## worked before calling this.
static func empty_folder(folder: String) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			if dir.current_is_dir():
				empty_folder(folder.path_join(name))
			DirAccess.remove_absolute(folder.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()


## Is this zip entry safe to unpack?
##
## An archive can name its entries anything it likes, including "..\..\
## Windows\System32\something.dll". Everything that could climb out of the
## folder we are unpacking into gets refused.
static func is_safe_entry(entry: String) -> bool:
	if entry.is_empty():
		return false
	var name: String = entry.replace("\\", "/")
	if name.begins_with("/"):
		return false
	# A Windows drive letter, or any other scheme.
	if name.contains(":"):
		return false
	for part in name.split("/"):
		if part == "..":
			return false
		# Matched on the part before the first dot, without case: COM1.png,
		# com1 and CON.txt are all the device. "console.png" and "nullify.png"
		# are not, which is why this is not a prefix match.
		if DEVICE_NAMES.has(part.get_slice(".", 0).to_upper()):
			return false
	return true


# The manifest nearest the top of the zip wins, so a pack folder containing
# a stray nested pet.json cannot hijack the import.
static func _find_manifest(entries: PackedStringArray) -> String:
	var best: String = ""
	var best_depth: int = 1 << 30
	for entry in entries:
		var file: String = entry.get_file()
		if file != PET_JSON and file != SCENE_JSON:
			continue
		var depth: int = entry.count("/")
		if depth < best_depth:
			best = entry
			best_depth = depth
	return best


# An id becomes a folder name, so it may only contain things that are safe
# in one. Anything else becomes an underscore.
const ID_ALLOWED := "abcdefghijklmnopqrstuvwxyz0123456789_-"


static func _clean_id(raw: String) -> String:
	var cleaned: String = raw.strip_edges().to_lower()
	var out: String = ""
	for index in cleaned.length():
		var character: String = cleaned[index]
		out += character if ID_ALLOWED.contains(character) else "_"
	return out.lstrip("_-").rstrip("_-")


# Every file under a folder, as paths relative to it.
static func _files_in(folder: String, prefix: String = "") -> PackedStringArray:
	var found: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var relative: String = prefix + name
			if dir.current_is_dir():
				found.append_array(_files_in(folder.path_join(name), relative + "/"))
			else:
				found.append(relative)
		name = dir.get_next()
	dir.list_dir_end()
	return found


static func _credits_text(credit: String) -> String:
	return """DOGPET PACK CREDITS
===================

%s

Please keep this credit with the pack if you pass it on. Some of the art
DogPet ships with is licensed on condition that its credit stays visible.
""" % credit
