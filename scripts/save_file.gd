class_name SaveFile
extends RefCounted
## Writing and reading the dog's save file, safely.
##
## Every function here is static and touches nothing but the filesystem: no
## nodes, no autoloads. That is what lets the headless tests drive it
## directly, including the corrupt-save case.
##
## A save is written to pet.json.tmp first and only moved into place once it
## is complete, so a crash or a pulled plug halfway through a write cannot
## leave a half-written pet.json behind. The file being replaced is kept as
## pet.json.bak, and a pet.json that will not parse falls back to it.

const FORMAT_VERSION := 1
const TMP_SUFFIX := ".tmp"
const BAK_SUFFIX := ".bak"

## A save missing any of these is not a save worth trusting.
const REQUIRED_KEYS: PackedStringArray = ["hunger", "happiness", "energy", "last_saved_unix"]

## Which file the last read actually came from: "main", "backup" or "none".
## Needs.gd logs this; the tests check it.
static var last_read_source: String = "none"


## Write the save, then swap it into place. Returns false if nothing could be
## written at all, which is the caller's cue to tell the owner.
static func write_atomic(path: String, payload: Dictionary) -> bool:
	var tmp_path: String = path + TMP_SUFFIX
	var bak_path: String = path + BAK_SUFFIX

	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	# Keep the file we are about to replace as the backup. Windows will not
	# rename onto a file that already exists, so clear the way first.
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		if DirAccess.rename_absolute(path, bak_path) != OK:
			# No backup this time, but a good save still beats a stale one.
			DirAccess.remove_absolute(path)

	return DirAccess.rename_absolute(tmp_path, path) == OK


## Read the save, falling back to the backup if the main file is missing,
## empty, unparseable or incomplete. Returns an empty Dictionary when there
## is nothing usable, which means "start a fresh dog".
static func read_with_fallback(path: String) -> Dictionary:
	var main: Dictionary = read_one(path)
	if not main.is_empty():
		last_read_source = "main"
		return main
	var backup: Dictionary = read_one(path + BAK_SUFFIX)
	last_read_source = "backup" if not backup.is_empty() else "none"
	return backup


## Read and validate one file. An empty Dictionary means "unusable".
static func read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	for key in REQUIRED_KEYS:
		if not data.has(key):
			return {}
	return data
