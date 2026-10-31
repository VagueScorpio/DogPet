extends SceneTree
## RT probe F: SaveFile.write_atomic deletes the previous good save before
## the new one is in place, and ignores whether the deletion worked. Once
## pet.json.bak cannot be replaced, every later save silently leaves the
## app with no fallback at all - which is the one thing the .bak is for.

const Save := preload("res://scripts/save_file.gd")

func _init() -> void:
	var dir: String = OS.get_user_data_dir().path_join("rt_save_probe")
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join("pet.json")
	for leftover in ["pet.json", "pet.json.tmp"]:
		DirAccess.remove_absolute(dir.path_join(leftover))
	# Clear any previous run's bak, directory or file.
	DirAccess.remove_absolute(path + ".bak/blocker.txt")
	DirAccess.remove_absolute(path + ".bak")

	var good: Dictionary = {"hunger": 11.0, "happiness": 22.0, "energy": 33.0,
		"last_saved_unix": 1000.0, "pet_name": "Biscuit"}
	print("first save ok: ", Save.write_atomic(path, good))
	var second: Dictionary = good.duplicate()
	second["pet_name"] = "Rex"
	print("second save ok: ", Save.write_atomic(path, second))
	print("bak now holds: ", Save.read_one(path + ".bak").get("pet_name", "<none>"))

	# Now make pet.json.bak something that cannot be removed or renamed over:
	# a non-empty directory. Antivirus holding the file open, a backup agent,
	# or a stray read-only flag all land in the same place.
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.make_dir_recursive_absolute(path + ".bak")
	var blocker: FileAccess = FileAccess.open(path + ".bak/blocker.txt", FileAccess.WRITE)
	blocker.store_string("in the way")
	blocker.close()

	var third: Dictionary = good.duplicate()
	third["pet_name"] = "Pickle"
	print("")
	print("with pet.json.bak unusable:")
	print("  third save reports: ", Save.write_atomic(path, third))
	print("  pet.json now holds: ", Save.read_one(path).get("pet_name", "<none>"))
	print("  a usable backup exists: ", not Save.read_one(path + ".bak").is_empty())

	# And this is what it costs: corrupt pet.json, with nothing to fall back to.
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var recovered: Dictionary = Save.read_with_fallback(path)
	print("  after pet.json is corrupted, recovery source: ", Save.last_read_source)
	print("  recovered dog: ", recovered.get("pet_name", "<THE DOG IS GONE>"))
	quit(0)
