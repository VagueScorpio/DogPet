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

## Whether the last write left a usable backup behind it.
##
## Apart from the return value on purpose: a write can perfectly well succeed
## while the backup could not be refreshed, and the caller wants to know that
## the net under the next write is older than it should be - or missing.
static var last_write_kept_backup: bool = true


## Write the save, then put it into place. Returns false only if the save
## itself did not land, which is the caller's cue to tell the owner. Check
## last_write_kept_backup for whether the fallback survived with it.
##
## The order here is the whole point. It used to move the old save aside to
## make room, deleting it outright if the move failed - so a pet.json that
## something else had open (antivirus mid-scan, a sync client, Explorer's
## preview pane) was destroyed, the backup had already been removed a line
## earlier to clear the way, and the function still reported success. The next
## corrupt write then had nothing to fall back on, which is the one thing this
## file exists to prevent.
##
## Nothing good is destroyed now. The backup is refreshed by *copying*, which
## leaves the original in place while it happens, and the new save goes in last
## by renaming over the old one - which Godot's rename does handle on Windows,
## contrary to the comment that used to be here justifying the old order.
static func write_atomic(path: String, payload: Dictionary) -> bool:
	var tmp_path: String = path + TMP_SUFFIX
	var bak_path: String = path + BAK_SUFFIX
	var bak_tmp_path: String = bak_path + TMP_SUFFIX

	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		last_write_kept_backup = FileAccess.file_exists(bak_path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	# Refresh the backup from the save that is about to be replaced. Written to
	# its own temp file first, so an interrupted copy cannot leave a half-built
	# backup where a whole one used to be.
	last_write_kept_backup = true
	if FileAccess.file_exists(path):
		var kept: bool = DirAccess.copy_absolute(path, bak_tmp_path) == OK
		if kept:
			kept = DirAccess.rename_absolute(bak_tmp_path, bak_path) == OK
		if not kept:
			DirAccess.remove_absolute(bak_tmp_path)
			# Whatever backup is already there stays. A slightly stale dog is
			# worth incomparably more than no dog.
			last_write_kept_backup = FileAccess.file_exists(bak_path)

	if DirAccess.rename_absolute(tmp_path, path) != OK:
		# The old save is still sitting there, untouched and still good.
		DirAccess.remove_absolute(tmp_path)
		return false
	return true


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
