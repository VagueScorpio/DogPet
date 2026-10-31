extends Node
## Appends a timestamped line to saves/dogpet.log and mirrors it to the
## console.
##
## Deliberately dumb: open the file, append one line, close it. The volume is
## tiny, and this way nothing is lost if the app is killed or the power goes
## out. If the log cannot be written the app carries on in silence rather
## than complaining every line.

## Rotate the log once it passes this size, so it cannot grow forever.
const MAX_BYTES := 1024 * 1024

var _path: String = ""
var _writable: bool = true

# How many bytes are in the log now, so the ceiling holds while the app is
# running rather than only when it starts - which matters because DogPet is
# meant to be left in the tray for days, and rotating once at launch let the
# file grow without limit for the whole session.
#
# Counted rather than measured: this script's whole design is one open, one
# line, one close, and a get_length() per line would quietly make it something
# else. Seeded from the real size below so a restart does not forget.
var _bytes: int = 0


func _ready() -> void:
	_path = Paths.log_path()
	_bytes = _size_on_disk()
	_rotate_if_large()
	info("--- DogPet v%s starting ---" % app_version())
	info("Godot %s" % Engine.get_version_info().get("string", "?"))
	info("Base folder:  %s" % Paths.base_dir)
	info("Assets folder: %s (%s)" % [
		Paths.assets_dir,
		"found" if Paths.assets_available else "MISSING",
	])
	info("Saves folder: %s" % Paths.saves_dir)
	# Replay anything Paths wanted to say before this script existed.
	for note in Paths.startup_notes:
		warn(note)


## The version from project.godot, which is the one place it is stored.
func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0"))


func info(message: String) -> void:
	_write("INFO", message)


func warn(message: String) -> void:
	_write("WARN", message)
	push_warning("DogPet: " + message)


func error(message: String) -> void:
	_write("ERROR", message)
	push_error("DogPet: " + message)


func _write(level: String, message: String) -> void:
	var stamp: String = Time.get_datetime_string_from_system(false, true)
	var line: String = "%s [%s] %s" % [stamp, level, message]
	print(line)
	if not _writable or _path.is_empty():
		return
	var file: FileAccess = _open_for_append()
	if file == null:
		# Say so once, through Godot's own channel, then stop trying.
		_writable = false
		push_warning("DogPet: cannot write the log file at " + _path)
		return
	file.store_line(line)
	file.close()
	# +1 for the newline store_line adds.
	_bytes += line.to_utf8_buffer().size() + 1
	if _bytes >= MAX_BYTES:
		_rotate_if_large()


# Godot 4 has no append mode, so open read-write and jump to the end.
# A file that does not exist yet cannot be opened read-write at all.
func _open_for_append() -> FileAccess:
	if not FileAccess.file_exists(_path):
		return FileAccess.open(_path, FileAccess.WRITE)
	var file: FileAccess = FileAccess.open(_path, FileAccess.READ_WRITE)
	if file != null:
		file.seek_end()
	return file


func _rotate_if_large() -> void:
	if _bytes < MAX_BYTES or not FileAccess.file_exists(_path):
		return
	var old: String = _path + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(_path, old) == OK:
		_bytes = 0


# Only asked once, at startup, so the running count starts from the truth.
func _size_on_disk() -> int:
	if not FileAccess.file_exists(_path):
		return 0
	var file: FileAccess = FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return 0
	var size: int = file.get_length()
	file.close()
	return size
