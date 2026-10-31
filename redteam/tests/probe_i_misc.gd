extends SceneTree
const Life := preload("res://scripts/life_model.gd")
const Archive := preload("res://scripts/pack_archive.gd")
const Hist := preload("res://scripts/pet_history.gd")

func _init() -> void:
	print("--- what an infinite age_days looks like on screen ---")
	print("format_age(INF) = ", Life.format_age(INF))
	print("stage_for(INF)  = ", Life.stage_for(INF))
	print("format_age(1e18) = ", Life.format_age(1e18))

	print("")
	print("--- a Windows device name as a zip entry ---")
	for entry in ["CON", "sub/NUL", "COM1.png", "a./../b", "..\\escape.txt",
			"C:/absolute.txt", "ok/file.png", "trailing ", "dots..."]:
		print("  is_safe_entry(%s) = %s" % [entry, Archive.is_safe_entry(entry)])

	print("")
	print("--- history.json with a hostile shape ---")
	var dir: String = OS.get_user_data_dir().path_join("rt_misc_probe")
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join("history.json")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"pets": [{"name": "A", "died_unix": 1e999, "born_unix": -1e999, "age_days": 1e999, "cause": 99}]}')
	f.close()
	var records: Array[Dictionary] = Hist.load_records(path)
	print("records read: ", records.size())
	for r in records:
		print("  describe: ", Hist.describe(r))
		print("  born: ", Hist.format_date(float(r.get("born_unix", 0.0))))
		print("  died: ", Hist.format_date(float(r.get("died_unix", 0.0))))
		print("  lifespan: ", Hist.format_lifespan(
			float(r.get("born_unix", 0.0)), float(r.get("died_unix", 0.0))))
	quit(0)
