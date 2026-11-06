extends SceneTree
## RT probe P2: how long the sheet reader takes on sheets people really have.
##
## The wizard runs SheetPlan.read on the UI thread with no progress and no
## way out, so anything slow here is a frozen window.
##
## Writes its scratch PNGs into Godot's own user data folder, never the
## project's assets.

var dir: String = ""


func _init() -> void:
	dir = OS.get_user_data_dir().path_join("rt_p2")
	DirAccess.make_dir_recursive_absolute(dir)
	_grid_sheet("grid16", 16, 16, 96)        # 1536x1536, 256 cells
	_grid_sheet("grid32", 32, 32, 48)        # 1536x1536, 1024 cells
	_grid_sheet("grid64", 64, 64, 32)        # 2048x2048, 4096 cells
	_flat("backdrop", 4096, 2048)
	_flat("huge", 8192, 4096)                # exactly MAX_PIXELS
	_touching("strip3", 3, 320, 320)
	print("--- done ---")
	quit(0)


func timed(what: String, path: String) -> void:
	var started: int = Time.get_ticks_msec()
	var found: Dictionary = SheetPlan.read(PackedStringArray([path]))
	var took: int = Time.get_ticks_msec() - started
	var pieces: Array = found["pieces"]
	var frames: int = 0
	for piece in pieces:
		frames += int((piece as Dictionary)["frames"])
	print("%-12s %7d ms   %4d pieces, %d frames total, %d notes" % [
		what, took, pieces.size(), frames, PackedStringArray(found["notes"]).size(),
	])


# A sheet of cells with a blob in each, on white paper: the ordinary case.
func _grid_sheet(name: String, across: int, down: int, cell: int) -> void:
	var image: Image = Image.create(across * cell, down * cell, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for row in down:
		for column in across:
			var centre := Vector2i(
				column * cell + cell / 2, row * cell + cell / 2
			)
			var radius: int = cell / 3
			for y in range(-radius, radius):
				for x in range(-radius, radius):
					if x * x + y * y <= radius * radius:
						image.set_pixel(centre.x + x, centre.y + y, Color.SADDLE_BROWN)
	var path: String = dir.path_join("%s.png" % name)
	image.save_png(path)
	timed("%s (%dx%d)" % [name, across, down], path)


# A plain photo-ish backdrop: no cells, no lanes, lots of ink.
func _flat(name: String, wide: int, high: int) -> void:
	var image: Image = Image.create(wide, high, false, Image.FORMAT_RGBA8)
	for y in range(0, high, 4):
		for x in range(0, wide, 4):
			image.set_pixel(x, y, Color(
				float(x) / float(wide), float(y) / float(high), 0.5
			))
	var path: String = dir.path_join("%s.png" % name)
	image.save_png(path)
	timed("%s %dx%d" % [name, wide, high], path)


# Frames drawn edge to edge, which is the case split_touching has to guess at.
func _touching(name: String, count: int, cell: int, high: int) -> void:
	var image: Image = Image.create(cell * count, high, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for index in count:
		var left: int = index * cell
		for y in range(high / 4, high - 10):
			for x in range(left + 20, left + cell - 20):
				image.set_pixel(x, y, Color.SADDLE_BROWN)
	var path: String = dir.path_join("%s.png" % name)
	image.save_png(path)
	timed("%s x%d" % [name, count], path)
