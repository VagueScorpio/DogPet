extends SceneTree
## Does DirAccess.rename_absolute overwrite an existing file on Windows?
## RT-06's reordering depends on the answer: if it does, the new save can go
## into place last; if not, the old one has to be moved aside first.

func _init() -> void:
	var dir: String = OS.get_user_data_dir().path_join("rt_rename")
	DirAccess.make_dir_recursive_absolute(dir)
	var a: String = dir.path_join("a.txt")
	var b: String = dir.path_join("b.txt")
	for p in [a, b]:
		DirAccess.remove_absolute(p)

	var f: FileAccess = FileAccess.open(a, FileAccess.WRITE)
	f.store_string("NEW")
	f.close()
	f = FileAccess.open(b, FileAccess.WRITE)
	f.store_string("OLD")
	f.close()

	var err: int = DirAccess.rename_absolute(a, b)
	print("rename onto an existing file -> error code ", err, " (0 is OK)")
	print("b.txt now holds: ", FileAccess.get_file_as_string(b) if FileAccess.file_exists(b) else "<gone>")
	print("a.txt still there: ", FileAccess.file_exists(a))

	print("")
	print("--- and copy_absolute onto an existing file ---")
	var c: String = dir.path_join("c.txt")
	f = FileAccess.open(c, FileAccess.WRITE)
	f.store_string("TARGET")
	f.close()
	f = FileAccess.open(a, FileAccess.WRITE)
	f.store_string("SOURCE")
	f.close()
	print("copy -> error code ", DirAccess.copy_absolute(a, c))
	print("c.txt now holds: ", FileAccess.get_file_as_string(c))
	quit(0)
