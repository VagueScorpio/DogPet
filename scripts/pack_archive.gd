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

const PET_JSON := "pet.json"
const SCENE_JSON := "scene.json"
const CREDITS_FILE := "CREDITS.txt"

## Files that have no business being in a pack.
const SKIPPED_NAMES: PackedStringArray = [".gdignore", "Thumbs.db", ".DS_Store", "desktop.ini"]


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

	# Every entry has to be safe before anything is unpacked anywhere.
	for entry in entries:
		if not is_safe_entry(entry):
			result["problems"].append("the zip contains an unsafe path: %s" % entry)
	if not result["problems"].is_empty():
		reader.close()
		return result

	var manifest: String = _find_manifest(entries)
	if manifest.is_empty():
		result["problems"].append("no %s or %s found in the zip" % [PET_JSON, SCENE_JSON])
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

	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		if not is_safe_entry(entry):
			problems.append("skipped an unsafe path: %s" % entry)
			continue
		if not prefix.is_empty() and not entry.begins_with(prefix):
			continue

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
