extends SceneTree
## RT-01 follow-up: is a non-ASCII pet name intact inside PowerShell, or did
## the base64 round-trip break it?
##
## Asks PowerShell to report the code points rather than the characters, so
## the answer cannot be distorted by whatever codepage its stdout uses.

func _initialize() -> void:
	var waited: int = 0
	while not root.has_node("Notifier") and waited < 120:
		await process_frame
		waited += 1
	var notifier: Node = root.get_node("Notifier")

	var name: String = "Bíscuit 日本 ok"
	print("name in Godot:        ", name)
	print("code points in Godot: ", _points(name))

	var script: String = notifier._toast_script(name, "body")
	# Report the decoded title as numbers, which no codepage can mangle.
	var probe: String = script.split("$doc = New-Object")[0] \
		+ "Write-Output ([int[]][char[]]$title -join ',')\n"
	var out: Array = []
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive",
		"-ExecutionPolicy", "Bypass", "-EncodedCommand",
		Marshalls.raw_to_base64(probe.to_utf16_buffer())], out, true)
	var said: String = "".join(out).split("<Objs")[0].strip_edges().replace("#< CLIXML", "").strip_edges()
	print("code points in PowerShell: ", said)
	print("they match: ", said == _points(name))
	quit(0)

func _points(text: String) -> String:
	var parts: PackedStringArray = []
	for index in text.length():
		parts.append(str(text.unicode_at(index)))
	return ",".join(parts)
