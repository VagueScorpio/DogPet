class_name PackTransfer
extends Node
## The import and export flow: file dialogs, confirmation, backups.
##
## PackArchive does the reading and writing; this is the part that has to
## talk to the owner. It asks before replacing anything, and takes a copy of
## whatever it is about to overwrite first, because the folder being
## replaced may be the only copy of a pack somebody made.

signal finished(message: String)

const BACKUP_DIR := "_backup"
const ZIP_FILTER: PackedStringArray = ["*.zip ; Pack files"]


# --- Export ---------------------------------------------------------------

func export_pet(pack: PetPack) -> void:
	_export(pack.dir, pack.id, pack.credit, "pet")


func export_room(pack: ScenePack) -> void:
	_export(pack.dir, pack.id, pack.credit, "room")


func _export(folder: String, id: String, credit: String, what: String) -> void:
	if folder.begins_with("res://"):
		finished.emit("That is the built-in %s, which cannot be exported." % what)
		return
	_pick_file(
		"Export %s \"%s\"" % [what, id],
		true,
		id + ".zip",
		func(path: String) -> void:
			var target: String = path if path.to_lower().ends_with(".zip") else path + ".zip"
			var problems: PackedStringArray = PackArchive.write_pack(folder, target, credit)
			if problems.is_empty():
				Log.info("Exported %s to %s" % [id, target])
				finished.emit("Exported \"%s\" to %s" % [id, target.get_file()])
			else:
				Log.warn("Export failed: %s" % problems[0])
				finished.emit("Could not export: %s" % problems[0])
	)


# --- Import ---------------------------------------------------------------

func import_pack() -> void:
	_pick_file("Import a pack", false, "", _on_import_chosen)


func _on_import_chosen(zip_path: String) -> void:
	var found: Dictionary = PackArchive.inspect(zip_path)
	if not found["problems"].is_empty():
		Log.warn("Import refused: %s" % found["problems"][0])
		finished.emit("That is not a pack DogPet can use: %s" % found["problems"][0])
		return

	var id: String = str(found["id"])
	var subdir: String = "pets" if found["kind"] == PackArchive.Kind.PET else "scenes"
	var target: String = Paths.assets_subdir(subdir).path_join(id)

	if DirAccess.dir_exists_absolute(target):
		_confirm(
			"Replace \"%s\"?" % id,
			"There is already a %s called \"%s\". The one you have will be copied into"
			% [subdir.trim_suffix("s"), id]
			+ " assets/_backup first, then replaced.",
			func() -> void: _do_import(zip_path, found, target, id)
		)
		return
	_do_import(zip_path, found, target, id)


func _do_import(zip_path: String, found: Dictionary, target: String, id: String) -> void:
	if DirAccess.dir_exists_absolute(target) and not _back_up(target, id):
		finished.emit("Could not back up the existing \"%s\", so nothing was changed." % id)
		return

	var problems: PackedStringArray = PackArchive.extract(zip_path, str(found["root"]), target)
	if not problems.is_empty():
		Log.warn("Import problems: %s" % ", ".join(problems))
		finished.emit("Imported \"%s\" with problems: %s" % [id, problems[0]])
	else:
		Log.info("Imported %s into %s" % [id, target])
		finished.emit("Imported \"%s\"." % str(found["name"]))
	AssetLibrary.reload()


# Keep whatever is about to be replaced, stamped with the time so repeated
# imports do not overwrite each other's backups either.
func _back_up(folder: String, id: String) -> bool:
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var destination: String = Paths.assets_subdir(BACKUP_DIR).path_join("%s-%s" % [id, stamp])
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return false
	if not _copy_tree(folder, destination):
		return false
	Log.info("Backed up %s to %s" % [id, destination])
	return true


func _copy_tree(from: String, to: String) -> bool:
	var dir: DirAccess = DirAccess.open(from)
	if dir == null:
		return false
	DirAccess.make_dir_recursive_absolute(to)
	dir.list_dir_begin()
	var name: String = dir.get_next()
	var fine: bool = true
	while not name.is_empty():
		if name != "." and name != "..":
			if dir.current_is_dir():
				fine = _copy_tree(from.path_join(name), to.path_join(name)) and fine
			elif DirAccess.copy_absolute(from.path_join(name), to.path_join(name)) != OK:
				fine = false
		name = dir.get_next()
	dir.list_dir_end()
	return fine


# --- Dialogs --------------------------------------------------------------

# Windows has a perfectly good file picker, so use it where it is offered.
# Godot's own dialog is the fallback, and works everywhere.
func _pick_file(title: String, saving: bool, suggested: String, action: Callable) -> void:
	var start: String = Paths.assets_dir
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var mode: int = (
			DisplayServer.FILE_DIALOG_MODE_SAVE_FILE if saving
			else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
		)
		var error: int = DisplayServer.file_dialog_show(
			title, start, suggested, false, mode, ZIP_FILTER,
			func(accepted: bool, paths: PackedStringArray, _filter: int) -> void:
				if accepted and not paths.is_empty():
					action.call(paths[0])
		)
		if error == OK:
			return
		Log.warn("The system file dialog would not open; using Godot's own.")

	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = (
		FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	)
	dialog.title = title
	dialog.filters = ZIP_FILTER
	dialog.current_dir = start
	if not suggested.is_empty():
		dialog.current_file = suggested
	dialog.file_selected.connect(func(path: String) -> void:
		action.call(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.8)


func _confirm(title: String, message: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.ok_button_text = "Replace"
	dialog.confirmed.connect(func() -> void:
		action.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
