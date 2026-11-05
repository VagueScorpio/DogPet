class_name SheetScan
extends RefCounted
## Measuring a picture: which pixels are drawn on the paper, and where.
##
## Everything else in the sheet reader works from the numbers this produces,
## so this is the only part that looks at pixels one at a time. SheetPaper
## says what the background is; this says what is on it, and how much of it
## is down each column and across each row.
##
## A scan is a plain Dictionary rather than an object, because SheetGrid and
## SheetPlan are pure maths over it and the tests build one by hand without
## ever opening a file.
##
## No nodes, no autoloads: a --script test run compiles this on its own.

## A picture bigger than this is measured at a reduced size. The grid is then
## counted in cells rather than in pixels, and the cell size is worked back
## out of the full width, so nothing is lost by it - a sheet that really is
## eight cells across is eight cells across at either size.
const MAX_SCAN_PIXELS := 2097152


## Measure a PNG. Returns a scan; read "problem" first, because everything
## else is empty when it is not.
static func read(path: String) -> Dictionary:
	var size: Vector2i = ImageLimits.png_size_from_header(path)
	if ImageLimits.is_too_large(size):
		return _nothing(path, ImageLimits.describe(path, size))
	var image: Image = Image.load_from_file(path)
	if image == null:
		return _nothing(path, "%s is not a picture this app can read" % path.get_file())
	return of_image(path, image)


## The same, for an image already in hand. The tests use this; so does the
## wizard, which has the picture open for its preview already.
static func of_image(path: String, image: Image) -> Dictionary:
	if image.get_width() <= 0 or image.get_height() <= 0:
		return _nothing(path, "%s is empty" % path.get_file())
	var full := Vector2i(image.get_width(), image.get_height())

	var small: Image = image.duplicate()
	small.convert(Image.FORMAT_RGBA8)
	var step: int = _scan_step(full)
	if step > 1:
		# Nearest, not bilinear: a gutter between cells has to stay empty,
		# and smoothing would smear the art across it.
		small.resize(
			maxi(1, full.x / step), maxi(1, full.y / step), Image.INTERPOLATE_NEAREST
		)

	var scan_size := Vector2i(small.get_width(), small.get_height())
	var paper: Array[Color] = SheetPaper.of_image(small)
	var ink: PackedByteArray = _ink(small, paper)
	# A picture that is all one colour - a plain wall tile, a flat backdrop -
	# would be keyed away to nothing, and then there would be no picture
	# left to install. Something covering the whole of itself is not a
	# background: it is the subject, and it keeps every pixel.
	if _coverage(ink) <= 0.0 and not paper.is_empty():
		paper = []
		ink = _ink(small, paper)

	var scan: Dictionary = {
		"path": path,
		"size": full,
		"scale": step,
		"scan_size": scan_size,
		"ink": ink,
		"columns": _tally(ink, scan_size, true),
		"rows": _tally(ink, scan_size, false),
		"background": paper[0] if not paper.is_empty() else Color(0, 0, 0, 0),
		"keyed": not paper.is_empty(),
		"problem": "",
	}
	scan["bounds"] = _bounds(scan)
	scan["coverage"] = _coverage(ink)
	return scan


## True where this scan found something drawn at all.
static func has_ink(scan: Dictionary) -> bool:
	return float(scan.get("coverage", 0.0)) > 0.0


## Is the pixel at a scanned position drawn? Positions are in scan
## coordinates, which are full-size coordinates divided by "scale".
static func ink_at(scan: Dictionary, x: int, y: int) -> bool:
	var size: Vector2i = scan["scan_size"]
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return false
	return PackedByteArray(scan["ink"])[y * size.x + x] == 1


## How much ink a rectangle of scan coordinates holds, 0.0 to 1.0.
static func ink_share(scan: Dictionary, area: Rect2i) -> float:
	if area.size.x <= 0 or area.size.y <= 0:
		return 0.0
	var size: Vector2i = scan["scan_size"]
	var ink: PackedByteArray = scan["ink"]
	var count: int = 0
	for y in range(maxi(0, area.position.y), mini(size.y, area.end.y)):
		var line: int = y * size.x
		for x in range(maxi(0, area.position.x), mini(size.x, area.end.x)):
			count += ink[line + x]
	return float(count) / float(area.size.x * area.size.y)


## The box around everything drawn inside a rectangle of scan coordinates,
## or a zero-size rect when it holds nothing. Still in scan coordinates.
static func ink_bounds(scan: Dictionary, area: Rect2i) -> Rect2i:
	var size: Vector2i = scan["scan_size"]
	var ink: PackedByteArray = scan["ink"]
	var left: int = area.end.x
	var right: int = area.position.x - 1
	var top: int = area.end.y
	var bottom: int = area.position.y - 1
	for y in range(maxi(0, area.position.y), mini(size.y, area.end.y)):
		var line: int = y * size.x
		for x in range(maxi(0, area.position.x), mini(size.x, area.end.x)):
			if ink[line + x] == 0:
				continue
			left = mini(left, x)
			right = maxi(right, x)
			top = mini(top, y)
			bottom = maxi(bottom, y)
	if right < left or bottom < top:
		return Rect2i(area.position, Vector2i.ZERO)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


## How much is drawn down each column of a rectangle, in scan coordinates.
static func column_tally(scan: Dictionary, area: Rect2i) -> PackedInt32Array:
	var tally: PackedInt32Array = []
	tally.resize(maxi(0, area.size.x))
	for x in area.size.x:
		var column := Rect2i(area.position.x + x, area.position.y, 1, area.size.y)
		tally[x] = int(roundf(ink_share(scan, column) * float(area.size.y)))
	return tally


# --- Working it out -------------------------------------------------------

# How many pixels one scanned sample stands for, as a whole number so the
# geometry maps back cleanly.
static func _scan_step(size: Vector2i) -> int:
	var step: int = 1
	while (size.x / step) * (size.y / step) > MAX_SCAN_PIXELS:
		step += 1
	return step


# One byte per pixel: 1 where something is drawn.
static func _ink(image: Image, paper: Array[Color]) -> PackedByteArray:
	var data: PackedByteArray = image.get_data()
	var pixels: int = image.get_width() * image.get_height()
	var ink: PackedByteArray = []
	ink.resize(pixels)
	# Compared as bytes rather than as floats: the same question, asked a few
	# million times, and this way it is integer arithmetic throughout.
	var limit: int = SheetPaper.byte_limit()
	var reds: PackedByteArray = []
	var greens: PackedByteArray = []
	var blues: PackedByteArray = []
	for sheet in paper:
		reds.append(sheet.r8)
		greens.append(sheet.g8)
		blues.append(sheet.b8)

	for index in pixels:
		var at: int = index * 4
		if data[at + 3] < SheetPaper.CLEAR_ALPHA:
			continue
		var drawn: int = 1
		for which in reds.size():
			if (
				absi(data[at] - reds[which])
				+ absi(data[at + 1] - greens[which])
				+ absi(data[at + 2] - blues[which])
			) <= limit:
				drawn = 0
				break
		ink[index] = drawn
	return ink


# How much ink there is down each column, or across each row.
static func _tally(ink: PackedByteArray, size: Vector2i, by_column: bool) -> PackedInt32Array:
	var counts: PackedInt32Array = []
	counts.resize(size.x if by_column else size.y)
	for y in size.y:
		var line: int = y * size.x
		for x in size.x:
			if ink[line + x] == 0:
				continue
			if by_column:
				counts[x] += 1
			else:
				counts[y] += 1
	return counts


static func _bounds(scan: Dictionary) -> Rect2i:
	var size: Vector2i = scan["scan_size"]
	var box: Rect2i = ink_bounds(scan, Rect2i(Vector2i.ZERO, size))
	var step: int = int(scan["scale"])
	return Rect2i(box.position * step, box.size * step)


static func _coverage(ink: PackedByteArray) -> float:
	if ink.is_empty():
		return 0.0
	var count: int = 0
	for value in ink:
		count += value
	return float(count) / float(ink.size())


static func _nothing(path: String, problem: String) -> Dictionary:
	return {
		"path": path,
		"size": Vector2i.ZERO,
		"scale": 1,
		"scan_size": Vector2i.ZERO,
		"ink": PackedByteArray(),
		"columns": PackedInt32Array(),
		"rows": PackedInt32Array(),
		"bounds": Rect2i(),
		"background": Color(0, 0, 0, 0),
		"keyed": false,
		"coverage": 0.0,
		"problem": problem,
	}
