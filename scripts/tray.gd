extends Node
## The system tray icon, and what the close button does.
##
## Closing the window normally tucks DogPet into the tray rather than
## quitting it, because a pet that stops existing when you close the window
## is not much of a pet. The needs keep ticking while it is hidden, and the
## frame rate drops right down so it costs almost nothing to leave running.
##
## The tray does not work when the game is embedded in the Godot editor, so
## this checks and quietly falls back to a close button that really closes.

const TOOLTIP_SECONDS := 10.0

const MENU_OPEN := 0
const MENU_PAUSE := 1
const MENU_QUIT := 2

## Frames per second while hidden. Enough to keep the needs ticking and the
## tooltip current, little enough to be invisible in Task Manager.
const HIDDEN_FPS := 5

## True when there is a tray to put an icon in at all.
var supported: bool = false
var hidden_to_tray: bool = false

var _indicator: StatusIndicator = null
var _menu: PopupMenu = null
var _normal_icon: Texture2D = null
var _alert_icon: Texture2D = null
var _showing_alert: bool = false
var _tooltip_left: float = 0.0
var _low_power: bool = false


func _ready() -> void:
	if Paths.tool_script_mode:
		set_process(false)
		return

	# We decide what the close button does, so Godot must stop deciding.
	get_tree().auto_accept_quit = false

	supported = (
		DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR)
		and not Engine.is_embedded_in_editor()
	)
	if not supported:
		Log.info(
			"No system tray available here"
			+ (" (the game is embedded in the editor)" if Engine.is_embedded_in_editor() else "")
			+ "; the close button will quit instead."
		)
		return

	_build_menu()
	_build_indicator()
	_refresh_tooltip()
	_refresh_icon()
	Log.info("Tray icon ready.")

	if Settings.start_minimized():
		hide_to_tray()


func _process(delta: float) -> void:
	_tooltip_left -= delta
	if _tooltip_left <= 0.0:
		_tooltip_left = TOOLTIP_SECONDS
		_refresh_tooltip()
		_refresh_icon()
	_follow_window_state()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	# Needs saves itself on this same notification, so the dog is safe
	# either way round.
	if supported and not Settings.close_button_quits():
		hide_to_tray()
	else:
		quit_app()


# --- Showing and hiding ---------------------------------------------------

func hide_to_tray() -> void:
	if not supported:
		return
	Needs.save_now()
	# Godot's Window.hide() does nothing at all to the root window on
	# Windows - checked with IsWindowVisible, the window stays fully up - so
	# minimising is how DogPet gets out of the way. The one difference from a
	# true hide is that the taskbar button stays; Godot exposes no flag to
	# drop it.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	hidden_to_tray = true
	_set_low_power(true)
	Log.info("Hidden to the tray.")

	# Say so once, ever, so nobody thinks they have quit the app and left it
	# eating battery.
	if not bool(Settings.data.get("tray_notice_shown", false)):
		Settings.remember("tray_notice_shown", true)
		Notifier.send_toast(
			"DogPet is still running in the tray.",
			"Click the tray icon to bring %s back." % Needs.pet_name
		)


func show_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Setting the mode back is not enough on its own; without this the window
	# stays minimised even though Godot thinks it is restored.
	DisplayServer.window_move_to_foreground()
	get_window().grab_focus()
	hidden_to_tray = false
	_set_low_power(false)


func quit_app() -> void:
	Needs.save_now()
	Log.info("Quitting.")
	get_tree().quit()


# --- The icon and its menu -----------------------------------------------

func _build_menu() -> void:
	_menu = PopupMenu.new()
	_menu.name = "TrayMenu"
	add_child(_menu)
	_menu.add_item("Open DogPet", MENU_OPEN)
	_menu.add_check_item("Pause notifications for 1 hour", MENU_PAUSE)
	_menu.add_separator()
	_menu.add_item("Quit", MENU_QUIT)
	_menu.id_pressed.connect(_on_menu_pressed)
	_menu.about_to_popup.connect(_refresh_menu)


func _build_indicator() -> void:
	_indicator = StatusIndicator.new()
	_indicator.name = "StatusIndicator"
	add_child(_indicator)
	_indicator.menu = _indicator.get_path_to(_menu)
	_indicator.pressed.connect(_on_indicator_pressed)
	_load_icons()


func _load_icons() -> void:
	var pack: UiPack = AssetLibrary.ui
	if pack == null:
		return
	_normal_icon = PetLoader.load_texture(pack.tray_icon_path())
	_alert_icon = PetLoader.load_texture(pack.tray_alert_path())
	if _normal_icon == null:
		Log.warn("No tray icon could be loaded.")


func _refresh_menu() -> void:
	var paused: bool = Notifier.is_paused()
	var index: int = _menu.get_item_index(MENU_PAUSE)
	_menu.set_item_checked(index, paused)
	_menu.set_item_text(
		index,
		"Paused for %d more minutes" % Notifier.pause_minutes_left() if paused
		else "Pause notifications for 1 hour"
	)


func _refresh_tooltip() -> void:
	if _indicator == null:
		return
	var values: Dictionary = {}
	for key in NeedsModel.KEYS:
		values[key] = Needs.value_of(key)
	_indicator.tooltip = NotificationRules.tooltip_for(values, Needs.pet_name)


# The alert icon goes up as soon as anything needs attention, so the tray
# itself carries the message without a notification having to.
func _refresh_icon() -> void:
	if _indicator == null:
		return
	var levels: Dictionary = {}
	for key in NeedsModel.KEYS:
		levels[key] = Needs.level_of(key)
	var wants_alert: bool = NotificationRules.wants_alert_icon(levels)
	if wants_alert == _showing_alert and _indicator.icon != null:
		return
	_showing_alert = wants_alert
	var icon: Texture2D = _alert_icon if wants_alert else _normal_icon
	if icon != null:
		_indicator.icon = icon


func _on_indicator_pressed(mouse_button: int, _position: Vector2) -> void:
	# Left click brings the window back; right click is the menu, which the
	# indicator opens by itself.
	if mouse_button == MOUSE_BUTTON_LEFT:
		show_window()


func _on_menu_pressed(id: int) -> void:
	match id:
		MENU_OPEN:
			show_window()
		MENU_PAUSE:
			if Notifier.is_paused():
				Notifier.resume()
			else:
				Notifier.pause_for()
		MENU_QUIT:
			quit_app()


# --- Keeping quiet while nobody is looking -------------------------------

# Minimising counts as being out of the way too, so the frame rate drops for
# that as well as for hiding in the tray.
func _follow_window_state() -> void:
	var out_of_sight: bool = (
		hidden_to_tray
		or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	)
	if out_of_sight != _low_power:
		_set_low_power(out_of_sight)


func _set_low_power(on: bool) -> void:
	_low_power = on
	Engine.max_fps = HIDDEN_FPS if on else 0
	OS.low_processor_usage_mode = on
