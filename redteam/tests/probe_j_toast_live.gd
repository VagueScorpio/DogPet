extends SceneTree
## RT-01 regression check: the fixed notification still actually works.
##
## Closing an injection is no good if it quietly stops the toasts. This loads
## the real assets/ui icons, builds the real script for a hostile pet name,
## and runs it with PowerShell's errors turned back on so any failure shows.
## A toast should appear on screen.

func _initialize() -> void:
	var waited: int = 0
	while not root.has_node("Notifier") and waited < 120:
		await process_frame
		waited += 1
	var paths: Node = root.get_node("Paths")
	var library: Node = root.get_node("AssetLibrary")
	var notifier: Node = root.get_node("Notifier")

	# Point the library at the project's real art, the way the integration
	# suite does, so there is a genuine tray icon to put on the toast.
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	paths.assets_dir = project.path_join("assets")
	paths.assets_available = DirAccess.dir_exists_absolute(paths.assets_dir)
	paths.tool_script_mode = false
	library._ready()
	print("icons loaded: ", library.ui != null and library.ui.is_usable())
	print("tray icon: ", library.ui.tray_icon_path() if library.ui != null else "<none>")

	var nasty: String = "$(Write-Output no) & <Rex> \"quoted\" 'apostrophe' Bíscuit"
	var script: String = notifier._toast_script("%s is starving!" % nasty, "Time to feed.")
	print("name present in script source: ", script.contains(nasty))
	print("icon present in script source: ", script.contains("appLogoOverride"))

	# Errors turned back on, so a broken script cannot pass silently.
	var loud: String = script.replace("SilentlyContinue", "Continue")
	var out: Array = []
	var code: int = OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive",
		"-ExecutionPolicy", "Bypass", "-EncodedCommand",
		Marshalls.raw_to_base64(loud.to_utf16_buffer())], out, true)
	var said: String = "".join(out).strip_edges()
	print("powershell exit code: ", code)
	print("powershell output (empty means no errors): ", "<empty>" if said.is_empty() else said)

	# And prove the name reached the toast intact, as text.
	var show_xml: String = loud.replace(
		"$toast = New-Object Windows.UI.Notifications.ToastNotification $doc",
		"Write-Output $doc.GetXml()\n$toast = New-Object Windows.UI.Notifications.ToastNotification $doc"
	)
	var out2: Array = []
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive",
		"-ExecutionPolicy", "Bypass", "-EncodedCommand",
		Marshalls.raw_to_base64(show_xml.to_utf16_buffer())], out2, true)
	print("--- the XML the toast was built from ---")
	print("".join(out2).split("<Objs")[0].strip_edges())
	quit(0)
