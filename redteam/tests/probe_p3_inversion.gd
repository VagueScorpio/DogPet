extends SceneTree
## RT probe P3: what SheetPaper calls the paper.
##
## SheetPaper takes the commonest colour as the background. A sheet whose
## subject covers more of the page than its background does therefore has the
## subject keyed out, and what gets installed is the hole the dog left.

var dir: String = ""


func _init() -> void:
	dir = OS.get_user_data_dir().path_join("rt_p3")
	DirAccess.make_dir_recursive_absolute(dir)
	_tight_crop()
	_filled_gradient()
	_thin_lines()
	quit(0)


# A 3-frame strip, tightly cropped: a dark dog on a white page, the dog taking
# up more of the sheet than the page does. Exactly what a cropped cartoon
# sheet looks like.
func _tight_crop() -> void:
	print("[1] a tightly cropped strip: dog 60%% of the sheet, paper 40%%")
	var cell: int = 120
	var image: Image = Image.create(cell * 3, cell, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var dog := Color8(60, 45, 35)
	for index in 3:
		var left: int = index * cell
		# A fat blob with a leg that moves, so the frames differ a little.
		for y in range(12, cell - 8):
			for x in range(left + 8, left + cell - 8):
				image.set_pixel(x, y, dog)
		for y in range(cell - 8, cell):
			for x in range(left + 10 + index * 20, left + 40 + index * 20):
				image.set_pixel(x, y, dog)
	var path: String = dir.path_join("tight.png")
	image.save_png(path)
	_describe("tight.png", path, dog)

	print("[1b] the same sheet with a wide margin, so paper wins on count")
	var roomy: Image = Image.create(cell * 3, cell, false, Image.FORMAT_RGBA8)
	roomy.fill(Color.WHITE)
	for index in 3:
		var left: int = index * cell
		for y in range(40, cell - 30):
			for x in range(left + 35, left + cell - 35):
				roomy.set_pixel(x, y, dog)
	var roomy_path: String = dir.path_join("roomy.png")
	roomy.save_png(roomy_path)
	_describe("roomy.png", roomy_path, dog)


func _describe(what: String, path: String, dog: Color) -> void:
	var opened: Dictionary = SheetScan.open(path)
	var scan: Dictionary = opened["scan"]
	var paper: Color = scan["background"]
	print("    paper read as #%s  (the dog is #%s, the page is #ffffff)" % [
		paper.to_html(false), dog.to_html(false),
	])
	print("    keyed: %s, %.1f%% of the sheet counted as drawn on" % [
		str(scan["keyed"]), float(scan["coverage"]) * 100.0,
	])
	var found: Dictionary = SheetPlan.read(PackedStringArray([path]))
	var pieces: Array = found["pieces"]
	print("    read as %d piece(s)" % pieces.size())
	for piece in pieces:
		print("      %s" % str((piece as Dictionary)["label"]))

	# Now cut it out exactly as the installer would, and count what survived.
	if pieces.is_empty():
		return
	var cut: Dictionary = (pieces[0] as Dictionary)["cut"]
	var strip: Image = SheetCutter.render(cut)
	if strip == null:
		print("      the cut could not be rendered")
		return
	var dog_left: int = 0
	var page_left: int = 0
	var clear: int = 0
	for y in strip.get_height():
		for x in strip.get_width():
			var pixel: Color = strip.get_pixel(x, y)
			if pixel.a < 0.03:
				clear += 1
			elif SheetPaper.apart(pixel, dog) < 0.06:
				dog_left += 1
			else:
				page_left += 1
	var total: int = strip.get_width() * strip.get_height()
	print("      strip %dx%d: %.1f%% dog, %.1f%% page, %.1f%% transparent" % [
		strip.get_width(), strip.get_height(),
		100.0 * float(dog_left) / float(total),
		100.0 * float(page_left) / float(total),
		100.0 * float(clear) / float(total),
	])
	if dog_left == 0:
		print("      *** THE DOG IS GONE. What was installed is the hole it left. ***")


# A real photographic backdrop, every pixel filled.
func _filled_gradient() -> void:
	print("[2] a filled 2048x1024 gradient backdrop")
	var image: Image = Image.create(2048, 1024, false, Image.FORMAT_RGBA8)
	for y in 1024:
		for x in 2048:
			image.set_pixel(x, y, Color(
				float(x) / 2048.0, float(y) / 1024.0, 0.4
			))
	var path: String = dir.path_join("gradient.png")
	image.save_png(path)
	var found: Dictionary = SheetPlan.read(PackedStringArray([path]))
	print("    %d pieces, notes: %s" % [
		(found["pieces"] as Array).size(), str(found["notes"]),
	])


# Line art at a size that makes SheetScan measure at a reduced scale, using
# nearest sampling. Does a hairline survive being sampled away?
func _thin_lines() -> void:
	print("[3] 3000x2400 line art (measured at a reduced scale, nearest)")
	var image: Image = Image.create(3000, 2400, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	# Four rows of three outline squares: 1-pixel strokes only.
	for row in 4:
		for column in 3:
			var box := Rect2i(column * 1000 + 100, row * 600 + 80, 800, 440)
			for x in range(box.position.x, box.end.x):
				image.set_pixel(x, box.position.y, Color.BLACK)
				image.set_pixel(x, box.end.y - 1, Color.BLACK)
			for y in range(box.position.y, box.end.y):
				image.set_pixel(box.position.x, y, Color.BLACK)
				image.set_pixel(box.end.x - 1, y, Color.BLACK)
	var path: String = dir.path_join("lines.png")
	image.save_png(path)
	var opened: Dictionary = SheetScan.open(path)
	var scan: Dictionary = opened["scan"]
	print("    measured at 1/%d, %.3f%% drawn on" % [
		int(scan["scale"]), float(scan["coverage"]) * 100.0,
	])
	var found: Dictionary = SheetPlan.read(PackedStringArray([path]))
	print("    %d pieces, notes: %s" % [
		(found["pieces"] as Array).size(), str(found["notes"]),
	])
	for piece in found["pieces"]:
		print("      %s" % str((piece as Dictionary)["label"]))
