class_name AppMenu
extends MenuBar
## The menu bar across the top of the window.
##
## Everything here is also reachable somewhere else - in Settings, or on the
## tray icon - but a menu bar is where people look first, and it puts the
## handful of things done most often one click away instead of two.
##
## The menus are built in code because most of them describe the state of
## something: which care speed is chosen, whether Demo is on. They are
## refreshed each time a menu is opened rather than kept in step by hand,
## which is a great deal harder to get wrong.

signal rename_requested()
signal instructions_requested()
signal settings_requested()
signal scoreboard_requested()

# Pet menu
const PET_RENAME := 0
const PET_SETTINGS := 1

# Care menu. The interval items take the index of CareSettings.CARE_INTERVALS
# so there is no second list to keep in step.
const CARE_DEMO := 100

# Assets menu
const ASSETS_OPEN := 0
const ASSETS_RELOAD := 1
const ASSETS_HELP := 2

# Window menu
const WINDOW_TRAY := 0
const WINDOW_QUIT := 1

# Mode menu. The ids are indexes into CareSettings.PLAY_MODES.
const MODE_SCOREBOARD := 100

var _care_menu: PopupMenu = null
var _window_menu: PopupMenu = null
var _mode_menu: PopupMenu = null


func _ready() -> void:
	_build_pet_menu()
	_build_mode_menu()
	_build_care_menu()
	_build_assets_menu()
	_build_window_menu()


# --- Pet ------------------------------------------------------------------

func _build_pet_menu() -> void:
	var menu := PopupMenu.new()
	menu.name = "Pet"
	add_child(menu)
	menu.add_item("Change Name...", PET_RENAME)
	menu.add_separator()
	menu.add_item("Settings...", PET_SETTINGS)
	menu.id_pressed.connect(_on_pet_pressed)


func _on_pet_pressed(id: int) -> void:
	match id:
		PET_RENAME:
			rename_requested.emit()
		PET_SETTINGS:
			settings_requested.emit()


# --- Mode -----------------------------------------------------------------

func _build_mode_menu() -> void:
	_mode_menu = PopupMenu.new()
	_mode_menu.name = "Mode"
	add_child(_mode_menu)
	_mode_menu.add_radio_check_item("Casual   (the dog cannot die)", 0)
	_mode_menu.add_radio_check_item("Real Pet   (it can)", 1)
	_mode_menu.add_separator()
	_mode_menu.add_item("Scoreboard...", MODE_SCOREBOARD)
	_mode_menu.id_pressed.connect(_on_mode_pressed)
	_mode_menu.about_to_popup.connect(_refresh_mode_menu)


func _refresh_mode_menu() -> void:
	for index in CareSettings.PLAY_MODES.size():
		_mode_menu.set_item_checked(
			_mode_menu.get_item_index(index),
			CareSettings.PLAY_MODES[index] == Settings.play_mode()
		)
	# Reachable in Casual as well: it still shows the dog you have now, and
	# any from an earlier spell of Real play.


func _on_mode_pressed(id: int) -> void:
	if id == MODE_SCOREBOARD:
		scoreboard_requested.emit()
		return
	if id < 0 or id >= CareSettings.PLAY_MODES.size():
		return
	var wanted: String = CareSettings.PLAY_MODES[id]
	if wanted == Settings.play_mode():
		return
	# Turning Real play on is worth a word of warning. Turning it off is
	# not: nothing bad can happen in Casual.
	if wanted == CareSettings.REAL:
		_confirm_real_play()
		return
	Settings.set_play_mode(wanted)


func _confirm_real_play() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Switch to Real Pet?"
	dialog.dialog_text = (
		"%s can get ill and can die, of starvation or of an illness left"
		% Needs.pet_name
		+ " untreated. That happens while DogPet is closed as well as while it"
		+ " is open.\n\nYou would then start again with a new dog."
	)
	dialog.ok_button_text = "Switch"
	dialog.confirmed.connect(func() -> void:
		Settings.set_play_mode(CareSettings.REAL)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


# --- Care -----------------------------------------------------------------

func _build_care_menu() -> void:
	_care_menu = PopupMenu.new()
	_care_menu.name = "Care"
	add_child(_care_menu)
	for index in CareSettings.CARE_INTERVALS.size():
		var name: String = CareSettings.CARE_INTERVALS[index]
		_care_menu.add_radio_check_item("%s   (%s)" % [name.capitalize(), _summary(name)], index)
	_care_menu.add_separator()
	_care_menu.add_check_item("Demo Speed", CARE_DEMO)
	_care_menu.set_item_tooltip(
		_care_menu.get_item_index(CARE_DEMO),
		"Everything runs in under a minute, for trying things out."
	)
	_care_menu.id_pressed.connect(_on_care_pressed)
	_care_menu.about_to_popup.connect(_refresh_care_menu)


# How long each setting takes, so the choice can be made from the menu
# without going and looking it up.
func _summary(name: String) -> String:
	var row: Dictionary = CareSettings.intervals_from(Settings.data, name)
	var parts: PackedStringArray = []
	for key in NeedsModel.KEYS:
		parts.append(_short(float(row[key])))
	return " / ".join(parts)


func _short(seconds: float) -> String:
	if seconds < 60.0:
		return "%ds" % roundi(seconds)
	if seconds < 3600.0:
		return "%dm" % roundi(seconds / 60.0)
	var hours: float = seconds / 3600.0
	if is_equal_approx(hours, roundf(hours)):
		return "%dh" % roundi(hours)
	return "%.1fh" % hours


func _refresh_care_menu() -> void:
	var chosen: String = Settings.care_interval()
	for index in CareSettings.CARE_INTERVALS.size():
		_care_menu.set_item_checked(
			_care_menu.get_item_index(index),
			CareSettings.CARE_INTERVALS[index] == chosen
		)
	_care_menu.set_item_checked(_care_menu.get_item_index(CARE_DEMO), Settings.demo_speed())


func _on_care_pressed(id: int) -> void:
	if id == CARE_DEMO:
		Settings.set_demo_speed(not Settings.demo_speed())
		return
	if id >= 0 and id < CareSettings.CARE_INTERVALS.size():
		Settings.set_care_interval(CareSettings.CARE_INTERVALS[id])


# --- Assets ---------------------------------------------------------------

func _build_assets_menu() -> void:
	var menu := PopupMenu.new()
	menu.name = "Assets"
	add_child(menu)
	menu.add_item("Open Assets Folder", ASSETS_OPEN)
	menu.set_item_tooltip(
		menu.get_item_index(ASSETS_OPEN),
		"Opens the folder holding the pets, rooms and icons."
	)
	menu.add_item("Reload Assets", ASSETS_RELOAD)
	menu.add_separator()
	menu.add_item("How to Change Pets or Scenes...", ASSETS_HELP)
	menu.id_pressed.connect(_on_assets_pressed)


func _on_assets_pressed(id: int) -> void:
	match id:
		ASSETS_OPEN:
			open_assets_folder()
		ASSETS_RELOAD:
			AssetLibrary.reload()
			Notifier.banner_requested.emit("Assets reloaded.", "")
		ASSETS_HELP:
			instructions_requested.emit()


## Open the assets folder in the system's file manager.
func open_assets_folder() -> void:
	Paths.open_in_file_manager(Paths.assets_dir)


# --- Window ---------------------------------------------------------------

func _build_window_menu() -> void:
	_window_menu = PopupMenu.new()
	_window_menu.name = "Window"
	add_child(_window_menu)
	_window_menu.add_item("Minimise to Tray", WINDOW_TRAY)
	_window_menu.add_separator()
	_window_menu.add_item("Quit DogPet", WINDOW_QUIT)
	_window_menu.id_pressed.connect(_on_window_pressed)
	_window_menu.about_to_popup.connect(_refresh_window_menu)


# Without a tray there is nowhere to minimise to, so say so rather than
# offering something that will not happen.
func _refresh_window_menu() -> void:
	var index: int = _window_menu.get_item_index(WINDOW_TRAY)
	_window_menu.set_item_disabled(index, not Tray.supported)
	_window_menu.set_item_tooltip(
		index,
		"" if Tray.supported else "No system tray is available here."
	)


func _on_window_pressed(id: int) -> void:
	match id:
		WINDOW_TRAY:
			if Tray.supported:
				Tray.hide_to_tray()
		WINDOW_QUIT:
			Tray.quit_app()
