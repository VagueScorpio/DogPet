extends Node
## Works out which folders DogPet reads and writes, and makes sure the saves
## folder can actually be written to.
##
## In an exported build the base folder is whatever folder DogPet.exe sits in,
## so the app stays portable: unzip it anywhere and assets/ and saves/ are
## right beside it. In the editor the base folder is the project folder, so
## development behaves the same way the shipped app does.
##
## Paths is the first autoload, so it cannot use Log yet (Log does not exist
## until a moment later). Anything worth logging goes into startup_notes, and
## Log prints those lines as soon as it comes up.

const ASSETS_FOLDER := "assets"
const SAVES_FOLDER := "saves"
const PET_SAVE_FILE := "pet.json"
const SETTINGS_FILE := "settings.json"
const LOG_FILE := "dogpet.log"
const WRITE_PROBE_FILE := ".write_test"

var base_dir: String = ""
var assets_dir: String = ""
var saves_dir: String = ""

## True when saves had to move to the Windows user data folder because the
## app's own folder is read-only - unzipped into Program Files, say. Main
## shows a one-time notice when this happens, so saves are never silently
## somewhere else.
var saves_moved_to_user_dir: bool = false

## False when assets/ is missing or unreadable. The asset loader falls back
## to the art packed inside the exe. The app must never crash over this.
var assets_available: bool = false

## Notes gathered before Log existed. Log drains this in its own _ready.
var startup_notes: PackedStringArray = []

## True when Godot was started with --script, which is how the headless
## tests run. There is no game then, only a script, so the autoloads skip
## their startup work and leave the real save files alone.
var tool_script_mode: bool = false


func _ready() -> void:
	tool_script_mode = OS.get_cmdline_args().has("--script")
	base_dir = _find_base_dir()
	assets_dir = base_dir.path_join(ASSETS_FOLDER)
	saves_dir = base_dir.path_join(SAVES_FOLDER)

	if not _prepare_saves_dir(saves_dir):
		var fallback: String = OS.get_user_data_dir().path_join(SAVES_FOLDER)
		if _prepare_saves_dir(fallback):
			saves_dir = fallback
			saves_moved_to_user_dir = true
			startup_notes.append("The app folder is read-only, so saves now live in " + fallback)
		else:
			startup_notes.append("Could not write saves anywhere. The dog will not be remembered.")

	assets_available = DirAccess.dir_exists_absolute(assets_dir)
	if not assets_available:
		startup_notes.append("No assets folder at " + assets_dir + "; using the built-in art.")


## Full path of the dog's save file.
func pet_save_path() -> String:
	return saves_dir.path_join(PET_SAVE_FILE)


## Full path of the settings file.
func settings_path() -> String:
	return saves_dir.path_join(SETTINGS_FILE)


## Full path of the log file.
func log_path() -> String:
	return saves_dir.path_join(LOG_FILE)


## Show a folder in whatever file manager Windows is set to use.
##
## Handing it to the system rather than naming Explorer means a replacement
## file manager gets it instead if one is installed. Godot holds paths with
## forward slashes, which Explorer is unreliable about, so they are turned
## back into backslashes on the way out.
##
## The folder is made if it is missing, because assets/ genuinely can be -
## the app falls back to its built-in art and carries on - and opening
## nothing would be a puzzling way to find that out.
func open_in_file_manager(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
		Log.warn("The folder was missing, so an empty one was made at " + folder)
	var native: String = folder.replace("/", "\\")
	Log.info("Opening " + native)
	OS.shell_open(native)


## A folder inside assets/, for example pets_dir("pug_3d").
func assets_subdir(sub: String) -> String:
	return assets_dir.path_join(sub)


# The editor runs from res://; an exported build runs next to the exe.
func _find_base_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").trim_suffix("/")
	return OS.get_executable_path().get_base_dir()


# Make the folder if it is missing, then prove we can really write in it.
# Creating a folder can succeed on Windows where writing a file still fails,
# so the probe file is the part that matters.
func _prepare_saves_dir(dir: String) -> bool:
	if not DirAccess.dir_exists_absolute(dir):
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			return false
	var probe: String = dir.path_join(WRITE_PROBE_FILE)
	var file: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("ok")
	file.close()
	DirAccess.remove_absolute(probe)
	return true
