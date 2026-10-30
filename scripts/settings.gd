extends Node
## Reads and writes saves/settings.json, and hands out the numbers the rest
## of the app runs on. Every change saves straight away, so the file on disk
## always matches what the owner just clicked.
##
## The data itself - the defaults and the pure lookups over them - lives in
## CareSettings, which has no nodes in it and can be tested headlessly. This
## script is the part that has a file, signals and a place in the tree.

signal changed(key: String)

var data: Dictionary = {}


func _ready() -> void:
	data = CareSettings.DEFAULTS.duplicate(true)

	# Under --script there is no game, only a script: the headless tests.
	# Leave the owner's real settings file alone.
	if Paths.tool_script_mode:
		return

	var loaded: Dictionary = _read_file()
	if loaded.is_empty():
		Log.info("No settings file yet; writing the defaults to " + Paths.settings_path())
	else:
		CareSettings.merge_into(data, loaded)
	# Always write on startup, so a missing or half-filled file is repaired.
	_save()
	Log.info("Care setting: %s%s" % [
		care_interval(),
		"   [DEMO SPEED ON]" if demo_speed() else "",
	])


# --- The settings the owner changes ---------------------------------------

func care_interval() -> String:
	return CareSettings.care_interval_name(data)


func set_care_interval(name: String) -> void:
	if not CareSettings.CARE_INTERVALS.has(name) or name == care_interval():
		return
	data["care_interval"] = name
	_save()
	Log.info("Care setting changed to " + name)
	changed.emit("care_interval")


func demo_speed() -> bool:
	return bool(data.get("demo_speed", false))


func set_demo_speed(on: bool) -> void:
	if on == demo_speed():
		return
	data["demo_speed"] = on
	_save()
	Log.info("Demo Speed " + ("ON" if on else "off"))
	changed.emit("demo_speed")


## "casual" or "real". Casual is the original game, where the dog cannot
## die; Real adds illness and death.
func play_mode() -> String:
	var name: String = str(data.get("play_mode", CareSettings.CASUAL))
	return name if CareSettings.PLAY_MODES.has(name) else CareSettings.CASUAL


func is_real_play() -> bool:
	return play_mode() == CareSettings.REAL


func set_play_mode(name: String) -> void:
	if not CareSettings.PLAY_MODES.has(name) or name == play_mode():
		return
	data["play_mode"] = name
	_save()
	Log.info("Play mode changed to " + name)
	changed.emit("play_mode")


## The Real play tuning numbers, all counted in hunger intervals.
func real_play() -> Dictionary:
	return data.get("real_play", {})


## How long the current care setting gives a starving dog before it dies.
func starve_grace_seconds() -> float:
	var interval: float = live_interval_for(NeedsModel.HUNGER)
	return interval * float(real_play().get("starve_grace_intervals", 1.0))


func notifications_enabled() -> bool:
	return bool(data.get("notifications_enabled", true))


func set_notifications_enabled(on: bool) -> void:
	if on == notifications_enabled():
		return
	data["notifications_enabled"] = on
	_save()
	changed.emit("notifications_enabled")


func close_button_quits() -> bool:
	return str(data.get("close_button", "tray")) == "quit"


func set_close_button_quits(quits: bool) -> void:
	var want: String = "quit" if quits else "tray"
	if want == str(data.get("close_button", "tray")):
		return
	data["close_button"] = want
	_save()
	changed.emit("close_button")


func start_minimized() -> bool:
	return bool(data.get("start_minimized", false))


func set_start_minimized(on: bool) -> void:
	if on == start_minimized():
		return
	data["start_minimized"] = on
	_save()
	changed.emit("start_minimized")


# --- The numbers the needs system asks for -------------------------------

## The intervals the bars drain at right now: the Demo row if Demo Speed is
## on, otherwise the chosen care setting.
func live_intervals() -> Dictionary:
	return CareSettings.intervals_from(data, CareSettings.live_interval_name(data))


## The intervals the offline catch-up uses: always the real care setting.
func catch_up_intervals() -> Dictionary:
	return CareSettings.intervals_from(data, CareSettings.catch_up_interval_name(data))


## Seconds from fully cared for to critical, for one need, right now.
func live_interval_for(key: StringName) -> float:
	return float(live_intervals().get(key, 0.0))


## Which room the owner picked for a slot, or "" for the first one found.
func room_for(role: String) -> String:
	var rooms: Dictionary = data.get("rooms", {})
	return str(rooms.get(role, ""))


func set_room(role: String, id: String) -> void:
	var rooms: Dictionary = data.get("rooms", {})
	if str(rooms.get(role, "")) == id:
		return
	rooms[role] = id
	data["rooms"] = rooms
	_save()
	Log.info("Room for %s set to %s" % [role, id])
	changed.emit("rooms")


## Store a plain value and save at once. Used for the small remembered
## facts that have no setting of their own, like whether the tray notice
## has already been shown.
func remember(key: String, value: Variant) -> void:
	if not data.has(key) or data[key] == value:
		return
	data[key] = value
	_save()
	changed.emit(key)


func action_effects() -> Dictionary:
	return data.get("action_effects", {})


func action_seconds(action: String) -> float:
	return CareSettings.action_seconds_from(data, action)


## How long to wait before nagging again about an already-critical need.
func critical_reminder_seconds() -> float:
	return CareSettings.reminder_seconds_from(data)


# --- The file itself ------------------------------------------------------

func _read_file() -> Dictionary:
	var path: String = Paths.settings_path()
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		Log.warn("settings.json could not be read; falling back to the defaults.")
		return {}
	return parsed


func _save() -> void:
	var path: String = Paths.settings_path()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		Log.error("Could not write settings to " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
