extends SceneTree
## What does ZIPReader actually offer in this Godot build? RT-03 needs an
## entry's uncompressed size BEFORE it reads it, or the limit is pointless.

func _init() -> void:
	print("Godot ", Engine.get_version_info().get("string", "?"))
	print("--- ZIPReader methods ---")
	for info in ClassDB.class_get_method_list("ZIPReader", true):
		var args: PackedStringArray = []
		for a in info.get("args", []):
			args.append(str(a.get("name", "?")))
		print("  %s(%s)" % [info.get("name", "?"), ", ".join(args)])
	print("--- FileAccess helpers for reading the zip by hand ---")
	for method in ["get_32", "get_64", "get_16", "seek", "seek_end", "get_position",
			"get_length", "get_buffer"]:
		print("  FileAccess.%s: %s" % [method, ClassDB.class_has_method("FileAccess", method, true)])
	quit(0)
