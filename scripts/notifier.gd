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
	Needs.pet_started.connect(_forget_previous_dog)
	_adopt_current_levels()


# A new dog inherits nothing from the last one, and least of all this.
# _announced holds the worst level already mentioned for each need, and a dog
# that died hungry leaves CRITICAL sitting in it; the new dog's first warning
# then reads as an improvement on that and is swallowed silently. A nag left
# in _reminder_left would go off for a dog that is no longer here.
func _forget_previous_dog() -> void:
	_announced.clear()
	_reminder_left.clear()


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

	# Nothing the dog is called, and no file name out of assets/, is allowed to
	# become part of this script. The three values arrive as base64 and the XML
	# is built through the DOM, so the script text below is a constant.
	#
	# It used to be pasted together instead, with the name escaped for XML and
	# dropped into an @"..."@ here-string - which PowerShell expands. The name
	# was therefore in the script's own source before PowerShell had parsed it,
	# so a dog called $(...) had its name run as code. Escaping for XML was
	# right as far as it went; the trouble was that two parsers read that text
	# one after the other, and it only ever satisfied the second one.
	return """$ErrorActionPreference = 'SilentlyContinue'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null
$title = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{TITLE}'))
$body = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{BODY}'))
$icon = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{ICON}'))
$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml('<toast><visual><binding template="ToastGeneric"><text></text><text></text></binding></visual></toast>')
$texts = $doc.GetElementsByTagName('text')
$texts.Item(0).AppendChild($doc.CreateTextNode($title)) | Out-Null
$texts.Item(1).AppendChild($doc.CreateTextNode($body)) | Out-Null
if ($icon -ne '') {
	$image = $doc.CreateElement('image')
	$image.SetAttribute('placement', 'appLogoOverride')
	$image.SetAttribute('src', 'file:///' + $icon)
	$doc.GetElementsByTagName('binding').Item(0).AppendChild($image) | Out-Null
}
$toast = New-Object Windows.UI.Notifications.ToastNotification $doc
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{APPID}').Show($toast)
""".replace("{TITLE}", _base64(title)) \
   .replace("{BODY}", _base64(body)) \
   .replace("{ICON}", _base64(_file_uri(icon))) \
   .replace("{APPID}", POWERSHELL_APP_ID)


# The one way a value is allowed into the script: as base64, inside a
# single-quoted PowerShell string. Base64 is only A-Za-z0-9+/=, so nothing a
# dog could be called can end that literal, and a single-quoted string does
# not expand $ in any case. The XML escaping that used to live here is done by
# CreateTextNode and SetAttribute above, which is the layer that knows what
# needs escaping.
#
# An empty string is answered directly: raw_to_base64 pushes an engine error
# when handed nothing, and nothing is perfectly normal here - there may be no
# icon, and a body is sometimes left blank.
static func _base64(text: String) -> String:
	if text.is_empty():
		return ""
	return Marshalls.raw_to_base64(text.to_utf8_buffer())


# A file:// URI wants forward slashes whatever Windows hands us. Spaces used to
# be percent-encoded here as well; they no longer need to be, because the path
# goes in through SetAttribute rather than into XML by hand.
static func _file_uri(path: String) -> String:
	return path.replace("\\", "/")
