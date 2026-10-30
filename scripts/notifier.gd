extends Node
## Tells the owner when the dog needs something.
##
## While the window is in front, that means a banner inside the app. While
## it is hidden in the tray, minimised or simply behind something else, it
## means a real Windows notification.
##
## Godot cannot raise a Windows toast by itself, so one is raised through
## PowerShell, which ships with every Windows 10 and 11. The script is handed
## over base64-encoded, which saves worrying about quoting entirely, and the
## process is launched without waiting for it so the game never stutters.
##
## Notifications will show up as coming from "Windows PowerShell". That is
## expected: avoiding it would mean registering an application with Windows,
## which a portable app that must install nothing cannot do.

## A banner, for when the owner is already looking at the window.
signal banner_requested(title: String, body: String)

const PAUSE_SECONDS := 3600.0

## The AppUserModelID Windows already knows about, so no registration is
## needed. This is PowerShell's own.
const POWERSHELL_APP_ID := "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe"

# The worst level already announced for each need, so a crossing is
# mentioned once rather than every frame it stays there.
var _announced: Dictionary = {}

# Seconds until the next reminder for a need that is still critical.
var _reminder_left: Dictionary = {}

var _pause_left: float = 0.0


func _ready() -> void:
	if Paths.tool_script_mode:
		set_process(false)
		return
	Needs.threshold_crossed.connect(_on_threshold_crossed)
	_adopt_current_levels()


# Needs has already done its offline catch-up by the time this runs, and it
# did it before anything was listening - so a need can be sitting at Critical
# with no crossing to hear about, ever. Without this, a dog that was left
# starving overnight and reopened straight into the tray was never once
# mentioned again. The levels are taken as read rather than announced: at
# launch the owner is usually looking at the window, where the away card has
# just said the same thing.
func _adopt_current_levels() -> void:
	for key in NeedsModel.KEYS:
		var level: int = Needs.level_of(key)
		if level <= int(NeedsModel.Level.FINE):
			continue
		_announced[key] = level
		if level >= int(NeedsModel.Level.CRITICAL):
			_reminder_left[key] = Settings.critical_reminder_seconds()


func _process(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left = maxf(0.0, _pause_left - delta)
	_tick_reminders(delta)


# --- Pausing -------------------------------------------------------------

func is_paused() -> bool:
	return _pause_left > 0.0


## Pause for an hour, as the tray menu offers. Not remembered across runs:
## reopening the app is a clear enough sign of wanting to be told again.
func pause_for(seconds: float = PAUSE_SECONDS) -> void:
	_pause_left = seconds
	Log.info("Notifications paused for %d minutes." % roundi(seconds / 60.0))


func resume() -> void:
	_pause_left = 0.0
	Log.info("Notifications resumed.")


func pause_minutes_left() -> int:
	return int(ceil(_pause_left / 60.0))


# --- Deciding what to say ------------------------------------------------

func _on_threshold_crossed(key: StringName, level: int) -> void:
	var already: int = int(_announced.get(key, int(NeedsModel.Level.FINE)))

	# Things got better. Clear the flag so the next slide down is announced
	# again, and stop nagging about it.
	if level < already:
		_announced[key] = level
		_reminder_left.erase(key)
		return

	if not NotificationRules.is_worth_announcing(already, level):
		return

	_announced[key] = level
	if level >= int(NeedsModel.Level.CRITICAL):
		_reminder_left[key] = Settings.critical_reminder_seconds()
	announce(key, level)


# While a need stays critical, say so again every so often: every half hour
# on Frequent, every two hours on Long, every minute in Demo.
func _tick_reminders(delta: float) -> void:
	for key in _reminder_left.keys():
		if Needs.level_of(key) < int(NeedsModel.Level.CRITICAL):
			_reminder_left.erase(key)
			continue
		_reminder_left[key] = float(_reminder_left[key]) - delta
		if float(_reminder_left[key]) <= 0.0:
			_reminder_left[key] = Settings.critical_reminder_seconds()
			announce(key, int(NeedsModel.Level.CRITICAL))


## Say something about one need, through whichever channel suits.
func announce(key: StringName, level: int) -> void:
	var title: String = NotificationRules.title_for(key, level, Needs.pet_name)
	var body: String = NotificationRules.body_for(key, level)
	deliver(title, body)


## Send a message by whichever route fits right now.
func deliver(title: String, body: String) -> void:
	if not Settings.notifications_enabled():
		return
	if is_paused():
		return
	if window_is_watching():
		# No need for a system notification when the owner is looking
		# straight at the app.
		banner_requested.emit(title, body)
		return
	send_toast(title, body)


## A notification the owner asked for, which ignores the on/off setting and
## the pause - they pressed the button, so they want to see it work.
func send_test() -> void:
	var title: String = "%s says hello." % Needs.pet_name
	var body: String = "Notifications are working."
	if window_is_watching():
		banner_requested.emit(title, body)
	send_toast(title, body)


## True when the owner can already see the window, so a banner is enough.
##
## Asked of DisplayServer rather than of the Window node, because the root
## Window's own visible and mode properties do not follow what actually
## happens to the window on Windows - it reported itself visible, windowed
## and focused while sitting minimised in the tray.
func window_is_watching() -> bool:
	if Tray.hidden_to_tray:
		return false
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		return false
	return DisplayServer.window_is_focused()


# --- Actually raising a toast --------------------------------------------

func send_toast(title: String, body: String) -> void:
	var script: String = _toast_script(title, body)
	# -EncodedCommand takes base64 of UTF-16, which sidesteps every quoting
	# and escaping problem between here and PowerShell.
	var encoded: String = Marshalls.raw_to_base64(script.to_utf16_buffer())

	if str(Settings.data.get("notification_launcher", "powershell")) == "wscript":
		_launch_via_wscript(encoded)
	else:
		_launch_via_powershell(encoded)


# The ordinary route. Godot creates the process without a console window, so
# nothing should flash on screen.
func _launch_via_powershell(encoded: String) -> void:
	var arguments: PackedStringArray = [
		"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
		"-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded,
	]
	if OS.create_process("powershell.exe", arguments) <= 0:
		Log.warn("Could not start PowerShell to show a notification.")


# The belt-and-braces route, for if a console window ever does flash.
# wscript.exe ships with Windows too, and runs with no window at all.
func _launch_via_wscript(encoded: String) -> void:
	var vbs_path: String = Paths.saves_dir.path_join("notify.vbs")
	var line: String = (
		"CreateObject(\"WScript.Shell\").Run \"powershell.exe -NoProfile "
		+ "-NonInteractive -ExecutionPolicy Bypass -EncodedCommand "
		+ encoded + "\", 0, False"
	)
	var file: FileAccess = FileAccess.open(vbs_path, FileAccess.WRITE)
	if file == null:
		Log.warn("Could not write the notification helper; falling back to PowerShell.")
		_launch_via_powershell(encoded)
		return
	file.store_line(line)
	file.close()
	if OS.create_process("wscript.exe", [vbs_path]) <= 0:
		Log.warn("Could not start wscript to show a notification.")


func _toast_script(title: String, body: String) -> String:
	var icon: String = ""
	if AssetLibrary.ui != null:
		icon = AssetLibrary.ui.tray_icon_path()

	var image_tag: String = ""
	if not icon.is_empty():
		image_tag = "<image placement=\"appLogoOverride\" src=\"file:///%s\"/>" % _file_uri(icon)

	return """$ErrorActionPreference = 'SilentlyContinue'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null
$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml(@"
<toast><visual><binding template="ToastGeneric"><text>{TITLE}</text><text>{BODY}</text>{IMAGE}</binding></visual></toast>
"@)
$toast = New-Object Windows.UI.Notifications.ToastNotification $doc
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{APPID}').Show($toast)
""".replace("{TITLE}", _xml_escape(title)) \
   .replace("{BODY}", _xml_escape(body)) \
   .replace("{IMAGE}", image_tag) \
   .replace("{APPID}", POWERSHELL_APP_ID)


# The dog's name goes straight into XML, and a dog could be called anything.
static func _xml_escape(text: String) -> String:
	return (text
		.replace("&", "&amp;")
		.replace("<", "&lt;")
		.replace(">", "&gt;")
		.replace("\"", "&quot;")
		.replace("'", "&apos;"))


# Spaces are the one thing that reliably trips up a file:// URI, and this
# app's own folder may well have them in it.
static func _file_uri(path: String) -> String:
	return path.replace("\\", "/").replace(" ", "%20")
