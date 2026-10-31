extends SceneTree
## RT-12 probe: the wscript notification helper used to be written to
## saves/notify.vbs - a predictable path, beside the exe, in a folder whose
## permissions depend on where the app was unzipped - and then executed.
##
## Checks where it goes now, that each one gets its own name, that only one
## exists at a time, and that nothing lands in saves/. Real toasts appear.

func _initialize() -> void:
	var waited: int = 0
	while not root.has_node("Notifier") and waited < 120:
		await process_frame
		waited += 1
	var paths: Node = root.get_node("Paths")
	var settings: Node = root.get_node("Settings")
	var notifier: Node = root.get_node("Notifier")

	# A sandbox saves folder, so this can prove nothing is written there.
	var sandbox: String = OS.get_user_data_dir().path_join("rt_vbs_saves")
	DirAccess.make_dir_recursive_absolute(sandbox)
	paths.saves_dir = sandbox
	settings.data["notification_launcher"] = "wscript"
	notifier._sweep_stale_helpers()

	var names: PackedStringArray = []
	for round_number in 3:
		notifier.send_toast("Biscuit needs you (%d)" % round_number, "Time to feed.")
		var now: PackedStringArray = _helpers()
		print("after toast %d: %d helper(s)  %s" % [round_number, now.size(), now])
		if now.size() == 1:
			names.append(now[0])

	print("")
	print("only ever one at a time:  ", names.size() == 3)
	print("each got its own name:    ", names[0] != names[1] and names[1] != names[2])
	print("none is the old fixed one: ", not names[0].contains("notify.vbs"))
	print("")
	print("files in saves/:          ", DirAccess.get_files_at(sandbox))
	print("a file called notify.vbs: ", FileAccess.file_exists(sandbox.path_join("notify.vbs")))
	print("where they go instead:    ", OS.get_user_data_dir())

	notifier._sweep_stale_helpers()
	print("after a final sweep:      ", _helpers().size(), " helper(s)")
	quit(0)

func _helpers() -> PackedStringArray:
	var out: PackedStringArray = []
	for name in DirAccess.get_files_at(OS.get_user_data_dir()):
		if name.begins_with("dogpet_notify_") and name.ends_with(".vbs"):
			out.append(name)
	return out
