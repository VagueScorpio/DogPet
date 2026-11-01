extends SceneTree
## Cut one row of poses out of a grid sheet and write it as a strip DogPet
## can use.
##
## Most "pose sheet" downloads are contact sheets: a grid of sets and ages,
## on a solid background, with titles, labels and rules drawn over it. DogPet
## reads one horizontal row of equal cells and nothing else, so a sheet like
## that has to be cut up before it is any use.
##
## This takes a rectangle holding one row, finds the poses inside it by
## looking for what is not background, throws away the small stuff - the
## 01/02/03 labels and the grid lines - and writes the poses out side by side
## as equal cells with a transparent background.
##
##   godot --headless --path . --script res://tools/slice_sheet.gd -- \
##       --in <sheet.png> --out <strip.png> --rect x,y,w,h [--frames 3]
##
## It prints the geometry it found, so a wrong rectangle is obvious rather
## than silently producing a strip of grid lines.

## How different from the background a pixel has to be to count as part of a
## pose. Low enough to keep a pale dog, high enough to drop the paper.
const CONTENT_TOLERANCE := 0.10

## A gap this wide (in pixels) between columns of content separates one pose
## from the next.
const MIN_GAP := 14

## A band of pixels covering this much of the row, and no thicker than
## RULE_THICKNESS, is a rule drawn on the sheet rather than anything alive.
const RULE_COVERAGE := 0.6
const RULE_THICKNESS := 6

## Blobs smaller than this fraction of the biggest one in a cell are the
## labels and the stray ends of grid lines, and are dropped.
const MIN_BLOB_SHARE := 0.05

## Breathing room left around the poses in the finished strip.
const PADDING := 6


func _initialize() -> void:
	var options: Dictionary = _options()
	if not options.has("in") or not options.has("out") or not options.has("rect"):
		print("usage: --in <sheet.png> --out <strip.png> --rect x,y,w,h [--frames N]")
		quit(1)
		return

	var sheet: Image = Image.load_from_file(str(options["in"]))
	if sheet == null:
		print("could not read %s" % options["in"])
		quit(1)
		return
	sheet.convert(Image.FORMAT_RGBA8)
	print("sheet is %d x %d" % [sheet.get_width(), sheet.get_height()])

	var numbers: PackedStringArray = str(options["rect"]).split(",")
	var area := Rect2i(
		int(numbers[0]), int(numbers[1]), int(numbers[2]), int(numbers[3])
	)
	var row: Image = sheet.get_region(area)
	var background: Color = _background_colour(row)
	print("background looks like %s" % background.to_html(false))

	var mask: Array = _content_mask(row, background)
	# The rules go first, before anything is measured or joined up: on this
	# sheet they pass close enough to the ears to touch them, and a rule
	# touching a dog is one shape with it from then on.
	_erase_rules(mask, row.get_width(), row.get_height())
	# Then the labels, over the whole row at once. Done per pose instead, a
	# mark between two poses would be measured as part of both.
	_drop_small_blobs(mask, 0, row.get_width() - 1, row.get_height())
	var cells: Array[Rect2i] = _split_into_cells(mask, row.get_width(), row.get_height())
	print("found %d poses:" % cells.size())
	for cell in cells:
		print("  %d,%d  %d x %d" % [cell.position.x, cell.position.y, cell.size.x, cell.size.y])

	var wanted: int = int(options.get("frames", cells.size()))
	if cells.is_empty() or cells.size() != wanted:
		print("expected %d poses - adjust --rect, or pass --frames %d" % [wanted, cells.size()])
		quit(1)
		return

	var strip: Image = _compose(row, mask, cells)
	var error: int = strip.save_png(str(options["out"]))
	if error != OK:
		print("could not write %s (error %d)" % [options["out"], error])
		quit(1)
		return
	print("wrote %s: %d x %d, %d frames of %d x %d" % [
		options["out"], strip.get_width(), strip.get_height(), cells.size(),
		strip.get_width() / cells.size(), strip.get_height(),
	])
	quit(0)


# --- Finding the poses ----------------------------------------------------

# The commonest colour in the row, which on a contact sheet is the paper.
func _background_colour(row: Image) -> Color:
	var tally: Dictionary = {}
	var best: Color = row.get_pixel(0, 0)
	var best_count: int = 0
	for y in range(0, row.get_height(), 2):
		for x in range(0, row.get_width(), 2):
			# Rounded, so the paper's faint gradient counts as one colour.
			var key: int = (
				(int(row.get_pixel(x, y).r * 32.0) << 10)
				| (int(row.get_pixel(x, y).g * 32.0) << 5)
				| int(row.get_pixel(x, y).b * 32.0)
			)
			var count: int = int(tally.get(key, 0)) + 1
			tally[key] = count
			if count > best_count:
				best_count = count
				best = row.get_pixel(x, y)
	return best


# One row of booleans per line of the image: true where something is drawn.
func _content_mask(row: Image, background: Color) -> Array:
	var mask: Array = []
	for y in row.get_height():
		var line: PackedByteArray = []
		line.resize(row.get_width())
		for x in row.get_width():
			var pixel: Color = row.get_pixel(x, y)
			var apart: float = (
				absf(pixel.r - background.r)
				+ absf(pixel.g - background.g)
				+ absf(pixel.b - background.b)
			) / 3.0
			line[x] = 1 if apart > CONTENT_TOLERANCE else 0
		mask.append(line)
	return mask


# A thin band of pixels stretching across most of the row is a rule drawn on
# the sheet, whatever it happens to be touching. Wiped out of the mask a band
# at a time, before the poses are found.
func _erase_rules(mask: Array, width: int, height: int) -> void:
	var y: int = 0
	while y < height:
		if _coverage(mask, width, y) < RULE_COVERAGE:
			y += 1
			continue
		var last: int = y
		while last + 1 < height and _coverage(mask, width, last + 1) >= RULE_COVERAGE:
			last += 1
		# Only a thin one. A band this wide that is also tall is the poses
		# themselves, lined up, and must be left alone.
		if last - y + 1 <= RULE_THICKNESS:
			for line in range(y, last + 1):
				for x in width:
					mask[line][x] = 0
		y = last + 1


static func _coverage(mask: Array, width: int, y: int) -> float:
	var count: int = 0
	for x in width:
		count += mask[y][x]
	return float(count) / float(width)


# Columns holding something, grouped into poses, each trimmed to what it
# actually holds once the small blobs are gone.
func _split_into_cells(mask: Array, width: int, height: int) -> Array[Rect2i]:
	var busy: PackedByteArray = []
	busy.resize(width)
	for x in width:
		# The longest unbroken run down the column, not the total: a rule
		# crossing the row leaves two or three pixels in every column it
		# passes, and would otherwise make the whole row look occupied.
		var run: int = 0
		var longest: int = 0
		for y in height:
			run = run + 1 if mask[y][x] == 1 else 0
			longest = maxi(longest, run)
		busy[x] = 1 if longest >= 8 else 0

	var cells: Array[Rect2i] = []
	var start: int = -1
	var gap: int = 0
	for x in width:
		if busy[x] == 1:
			if start < 0:
				start = x
			gap = 0
			continue
		if start < 0:
			continue
		gap += 1
		if gap >= MIN_GAP:
			cells.append(_trim(mask, start, x - gap, height))
			start = -1
	if start >= 0:
		cells.append(_trim(mask, start, width - 1, height))

	# The widest pose sets the bar; anything a fraction of it is a label that
	# happened to sit on its own.
	var widest: int = 0
	for cell in cells:
		widest = maxi(widest, cell.size.x)
	var kept: Array[Rect2i] = []
	for cell in cells:
		if cell.size.x >= int(widest * 0.3) and cell.size.y > 8:
			kept.append(cell)
	return kept


# The box around one pose, with the labels and rule ends flood-filled away.
func _trim(mask: Array, left: int, right: int, height: int) -> Rect2i:
	var top: int = height
	var bottom: int = -1
	var first: int = right
	var last: int = left
	for y in height:
		for x in range(left, right + 1):
			if mask[y][x] == 0:
				continue
			top = mini(top, y)
			bottom = maxi(bottom, y)
			first = mini(first, x)
			last = maxi(last, x)
	if bottom < 0:
		return Rect2i(left, 0, 0, 0)
	return Rect2i(first, top, last - first + 1, bottom - top + 1)


# Everything drawn in this column that is not part of the main shape gets
# wiped out of the mask: the 01/02/03 labels, and whatever the grid lines
# left behind.
func _drop_small_blobs(mask: Array, left: int, right: int, height: int) -> void:
	var seen: Dictionary = {}
	var blobs: Array = []
	for y in height:
		for x in range(left, right + 1):
			if mask[y][x] == 0 or seen.has(y * 100000 + x):
				continue
			var blob: Array = []
			var stack: Array = [Vector2i(x, y)]
			seen[y * 100000 + x] = true
			while not stack.is_empty():
				var at: Vector2i = stack.pop_back()
				blob.append(at)
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = at + step
					if next.x < left or next.x > right or next.y < 0 or next.y >= height:
						continue
					if mask[next.y][next.x] == 0 or seen.has(next.y * 100000 + next.x):
						continue
					seen[next.y * 100000 + next.x] = true
					stack.append(next)
			blobs.append(blob)

	var biggest: int = 0
	for blob in blobs:
		biggest = maxi(biggest, blob.size())
	for blob in blobs:
		var box: Rect2i = _blob_box(blob)
		# Two ways of not being a pose. Too small is the 01/02/03 labels.
		# Long and flat is a rule drawn across the sheet, which covers more
		# pixels than a label does and is still not a dog - so it is judged
		# by its shape rather than by its size.
		var small: bool = blob.size() < int(biggest * MIN_BLOB_SHARE)
		# Judged by proportion, not by length: the rules on a contact sheet
		# are broken into a segment per cell by the lines crossing them, so
		# "as wide as the row" misses them. Nothing drawn of an animal is
		# six times as wide as it is tall and only a few pixels thick.
		var rule: bool = box.size.y <= maxi(6, height / 20) and box.size.x >= box.size.y * 6
		if not small and not rule:
			continue
		for at in blob:
			mask[at.y][at.x] = 0


static func _blob_box(blob: Array) -> Rect2i:
	var box := Rect2i(blob[0], Vector2i.ZERO)
	for at in blob:
		box = box.expand(at)
	# expand leaves the far edge exclusive; one pixel each way puts it back.
	return Rect2i(box.position, box.size + Vector2i.ONE)


# --- Writing the strip ----------------------------------------------------

# Equal cells, each pose centred across and standing on the bottom, with
# everything that was paper left transparent.
func _compose(row: Image, mask: Array, cells: Array[Rect2i]) -> Image:
	var cell_width: int = 0
	var cell_height: int = 0
	for cell in cells:
		cell_width = maxi(cell_width, cell.size.x)
		cell_height = maxi(cell_height, cell.size.y)
	cell_width += PADDING * 2
	cell_height += PADDING * 2

	var strip: Image = Image.create(
		cell_width * cells.size(), cell_height, false, Image.FORMAT_RGBA8
	)
	strip.fill(Color(0, 0, 0, 0))
	for index in cells.size():
		var cell: Rect2i = cells[index]
		var offset_x: int = index * cell_width + (cell_width - cell.size.x) / 2
		var offset_y: int = cell_height - PADDING - cell.size.y
		for y in cell.size.y:
			for x in cell.size.x:
				if mask[cell.position.y + y][cell.position.x + x] == 0:
					continue
				strip.set_pixel(
					offset_x + x, offset_y + y,
					row.get_pixel(cell.position.x + x, cell.position.y + y)
				)
	return strip


func _options() -> Dictionary:
	var given: Dictionary = {}
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < arguments.size():
		var name: String = arguments[index].lstrip("-")
		if index + 1 < arguments.size():
			given[name] = arguments[index + 1]
		index += 2
	return given
