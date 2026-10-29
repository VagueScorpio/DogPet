class_name UiPack
extends RefCounted
## The icons: the tray icon and its alert version, the three need icons and
## the three button icons.
##
## Same idea as a pet pack or a room - a folder with a JSON file in it, read
## off the disk at runtime - so the icons can be changed without rebuilding.
## Anything missing simply does not get drawn; no icon is ever load-bearing.

const UI_JSON := "ui.json"

var dir: String = ""
var icon_scale: int = 1

var tray_icon: String = ""
var tray_icon_alert: String = ""

## Need key ("hunger") to file name.
var need_icons: Dictionary = {}
## Action name ("feed") to file name.
var button_icons: Dictionary = {}

var problems: PackedStringArray = []


static func load_from_dir(folder: String) -> UiPack:
	var pack := UiPack.new()
	pack.dir = folder
	var json_path: String = folder.path_join(UI_JSON)
	if not FileAccess.file_exists(json_path):
		pack.problems.append("no %s in %s" % [UI_JSON, folder])
		return pack
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not parsed is Dictionary:
		pack.problems.append("%s is not valid JSON" % json_path)
		return pack

	var data: Dictionary = parsed
	pack.icon_scale = maxi(1, int(data.get("icon_scale", 1)))
	pack.tray_icon = pack._checked(str(data.get("tray_icon", "")), "tray icon")
	pack.tray_icon_alert = pack._checked(str(data.get("tray_icon_alert", "")), "tray alert icon")

	var icons: Variant = data.get("icons", {})
	if icons is Dictionary:
		for key in (icons as Dictionary).keys():
			var file: String = pack._checked(str((icons as Dictionary)[key]), "%s icon" % key)
			if not file.is_empty():
				pack.need_icons[str(key)] = file

	var buttons: Variant = data.get("buttons", {})
	if buttons is Dictionary:
		for key in (buttons as Dictionary).keys():
			var file: String = pack._checked(str((buttons as Dictionary)[key]), "%s button" % key)
			if not file.is_empty():
				pack.button_icons[str(key)] = file

	return pack


## True when there is at least a tray icon to show.
func is_usable() -> bool:
	return not tray_icon.is_empty()


func tray_icon_path() -> String:
	return _path(tray_icon)


func tray_alert_path() -> String:
	# Fall back to the ordinary icon rather than showing nothing at all.
	return _path(tray_icon_alert if not tray_icon_alert.is_empty() else tray_icon)


func need_icon_path(key: String) -> String:
	return _path(str(need_icons.get(key, "")))


func button_icon_path(action: String) -> String:
	return _path(str(button_icons.get(action, "")))


func _path(file: String) -> String:
	if file.is_empty():
		return ""
	return dir.path_join(file)


func _checked(file: String, what: String) -> String:
	var cleaned: String = file.strip_edges()
	if cleaned.is_empty():
		return ""
	if not FileAccess.file_exists(dir.path_join(cleaned)):
		problems.append("the %s (%s) is missing" % [what, cleaned])
		return ""
	return cleaned
