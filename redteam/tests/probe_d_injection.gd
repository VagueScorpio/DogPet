extends SceneTree
## RT-01 probe: can a pet's name get itself run as PowerShell?
##
## Drives the REAL Notifier._toast_script rather than a copy of it, so this
## cannot drift away from the shipped code, and launches the result the same
## way Notifier does. The payload only writes a marker file.
##
## Before the fix: the marker appeared, and the toast's <text> came out empty
## because PowerShell had eaten the subexpression.
## After the fix: no marker, and the name survives in full as inert text.
##
## Run from _initialize, not _init: a --script run reaches _init before the
## autoloads are in the tree, so Notifier does not exist yet.

func _initialize() -> void:
	var waited: int = 0
	while not root.has_node("Notifier") and waited < 120:
		await process_frame
		waited += 1
	var notifier: Node = root.get_node("Notifier")

	var dir: String = OS.get_user_data_dir().path_join("rt_inject_probe")
	DirAccess.make_dir_recursive_absolute(dir)
	var marker: String = dir.path_join("rt_marker.txt")
	DirAccess.remove_absolute(marker)

	# No quotes in the payload, so the old _xml_escape had nothing to catch.
	var payload: String = "$(Set-Content -Path " + marker + " -Value pwned-via-pet-name; Rex)"
	var script: String = notifier._toast_script("%s is starving!" % payload, "Time to feed.")

	print("--- is the name anywhere in the script source? ", script.contains(payload), " ---")
	print("--- the script Notifier would run ---")
	print(script)

	# Launched exactly as Notifier._launch_via_powershell does, but waited on
	# so the probe can report what came back.
	var encoded: String = Marshalls.raw_to_base64(script.to_utf16_buffer())
	var out: Array = []
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive",
		"-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded], out, true)

	waited = 0
	while not FileAccess.file_exists(marker) and waited < 200:
		OS.delay_msec(10)
		waited += 1
	print("--- marker exists: ", FileAccess.file_exists(marker), " ---")
	if FileAccess.file_exists(marker):
		print("CODE RAN. marker contents: ", FileAccess.get_file_as_string(marker).strip_edges())
	else:
		print("the name was never executed.")
	quit(0)
