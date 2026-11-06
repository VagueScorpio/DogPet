extends SceneTree
## RT probe P6: the worst case for the wizard's UI thread.
##
## ImportForm._build_sprite_questions calls SheetPlan.read inline while the
## window is up, with no progress bar and no way to cancel. The question is
## how long the nastiest allowed input takes.

var dir: String = ""


func _init() -> void:
	dir = OS.get_user_data_dir().path_join("rt_p6")
	DirAccess.make_dir_recursive_absolute(dir)
	_wide_touching()
	_many_files()
	_with_ceiling()
	quit(0)


# A wide strip with no lanes in it: the one shape split_touching has to guess
# at, tried at every division from 2 to 16, each one a full likeness compare.
func _wide_touching() -> void:
	for wide in [2048, 4096, 8192]:
		var high: int = 1024
		var image: Image = Image.create(wide, high, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		# One continuous mass of ink with texture in it, so no even division
		# has a clean gutter and every candidate is scored the hard way.
		for y in range(80, high - 40):
			for x in range(40, wide - 40):
				if (x * 7 + y * 13) % 29 > 3:
					image.set_pixel(x, y, Color8(
						60 + (x % 40), 45 + (y % 30), 35
					))
		var path: String = dir.path_join("wide_%d.png" % wide)
		image.save_png(path)
		var started: int = Time.get_ticks_msec()
		var found: Dictionary = SheetPlan.read(PackedStringArray([path]))
		var took: int = Time.get_ticks_msec() - started
		var pieces: Array = found["pieces"]
		print("%dx%d strip: %6d ms, %d pieces%s" % [
			wide, high, took, pieces.size(),
			"" if pieces.is_empty() else " (first: %s)" % str(
				(pieces[0] as Dictionary)["label"]
			),
		])


# Several hundred PNGs chosen at once, which a Ctrl+A in a frames folder does.
func _many_files() -> void:
	var folder: String = dir.path_join("frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var paths: PackedStringArray = []
	for index in 400:
		var image: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		for y in range(40, 220):
			for x in range(40 + index % 20, 200 + index % 20):
				image.set_pixel(x, y, Color.SADDLE_BROWN)
		var path: String = folder.path_join("shot_%03d.png" % index)
		image.save_png(path)
		paths.append(path)
	var started: int = Time.get_ticks_msec()
	var found: Dictionary = SheetPlan.read(paths)
	print("400 numbered 256x256 files: %d ms, %d pieces, notes %s" % [
		Time.get_ticks_msec() - started, (found["pieces"] as Array).size(),
		str(found["notes"]),
	])

	# The same files renamed so they are not a run: 400 separate pictures.
	var loose: PackedStringArray = []
	for index in paths.size():
		var renamed: String = folder.path_join("pose_%c%c.png" % [
			65 + index / 26, 65 + index % 26,
		])
		DirAccess.copy_absolute(paths[index], renamed)
		loose.append(renamed)
	started = Time.get_ticks_msec()
	var scattered: Dictionary = SheetPlan.read(loose)
	print("400 unrelated 256x256 files: %d ms, %d pieces" % [
		Time.get_ticks_msec() - started, (scattered["pieces"] as Array).size(),
	])


# The same four hundred unrelated files, asked with the ceiling the wizard
# now passes. RT-15.
func _with_ceiling() -> void:
	var folder: String = dir.path_join("frames")
	var loose: PackedStringArray = []
	var access: DirAccess = DirAccess.open(folder)
	access.list_dir_begin()
	var name: String = access.get_next()
	while not name.is_empty():
		if name.begins_with("pose_"):
			loose.append(folder.path_join(name))
		name = access.get_next()
	access.list_dir_end()
	var started: int = Time.get_ticks_msec()
	var capped: Dictionary = SheetPlan.read(loose, 24)
	print("%d unrelated files with a ceiling of 24: %d ms, %d pieces" % [
		loose.size(), Time.get_ticks_msec() - started,
		(capped["pieces"] as Array).size(),
	])
	for note in PackedStringArray(capped["notes"]):
		print("    note: %s" % note)
