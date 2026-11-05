class_name SheetCutter
extends RefCounted
## Carrying out a cut: the pixels come out of the sheets and go into one
## strip that DogPet can read.
##
## DogPet knows exactly one layout for drawn art - a horizontal row of equal
## cells, read left to right - so everything the sheet reader finds, however
## it was arranged on the page, ends up in that shape here. One frame is the
## same thing with one cell in it.
##
## Two jobs beyond copying pixels. The paper gets keyed out, so a dog cut off
## a white page is not installed as a dog in a white box. And frames cut from
## uneven places get stood on a common baseline, centred, because frames that
## are not registered to each other make the animation jitter on the spot.

## Breathing room around each frame, in pixels, when frames are being lined
## up rather than left in the cells they came from.
const PADDING := 2


## Render a cut into one strip. Null when the sources cannot be read.
static func render(cut: Dictionary) -> Image:
	var paths: PackedStringArray = cut.get("paths", PackedStringArray())
	var rects: Array = cut.get("rects", [])
	if paths.is_empty() or rects.size() != paths.size():
		return null

	var opened: Dictionary = {}
	var papers: Dictionary = {}
	var frames: Array[Image] = []
	for index in paths.size():
		var path: String = paths[index]
		if not opened.has(path):
			var loaded: Image = Image.load_from_file(path)
			if loaded == null:
				return null
			loaded.convert(Image.FORMAT_RGBA8)
			opened[path] = loaded
			papers[path] = SheetPaper.of_image(loaded) if bool(cut.get("key", false)) else []
		var source: Image = opened[path]
		var area: Rect2i = _inside(rects[index], source)
		if area.size.x <= 0 or area.size.y <= 0:
			return null
		var frame: Image = source.get_region(area)
		if not PackedColorArray(papers[path]).is_empty():
			_key_out(frame, papers[path])
		frames.append(frame)

	if bool(cut.get("align", false)):
		frames = _trimmed(frames)
	return _lay_out(frames)


## Render a cut and save it. Returns "" when it worked, or what went wrong.
static func write(cut: Dictionary, destination: String) -> String:
	var strip: Image = render(cut)
	if strip == null:
		return "could not read the pictures %s was cut from" % destination.get_file()
	if ImageLimits.is_too_large(Vector2i(strip.get_width(), strip.get_height())):
		return "%s would be larger than this app will load" % destination.get_file()
	return (
		"" if strip.save_png(destination) == OK
		else "could not write %s" % destination.get_file()
	)


## How many frames a cut holds. One is a still picture.
static func frames_in(cut: Dictionary) -> int:
	return PackedStringArray(cut.get("paths", PackedStringArray())).size()


# --- The pixels -----------------------------------------------------------

# Clipped to the picture, so a rect measured on a scan that was rounded by a
# pixel cannot ask for a region that is not there.
static func _inside(rect: Rect2i, image: Image) -> Rect2i:
	return rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))


# Everything the colour of the paper becomes transparent. Done by hand on
# the raw bytes rather than through set_pixel, because a sheet is a lot of
# pixels and this is the same comparison a few hundred thousand times.
static func _key_out(image: Image, paper: Array) -> void:
	var data: PackedByteArray = image.get_data()
	var limit: int = SheetPaper.byte_limit()
	var pixels: int = image.get_width() * image.get_height()
	var changed: bool = false
	for index in pixels:
		var at: int = index * 4
		if data[at + 3] < SheetPaper.CLEAR_ALPHA:
			continue
		for sheet in paper:
			var colour: Color = sheet
			if (
				absi(data[at] - colour.r8)
				+ absi(data[at + 1] - colour.g8)
				+ absi(data[at + 2] - colour.b8)
			) > limit:
				continue
			data[at + 3] = 0
			changed = true
			break
	if changed:
		# Rebuilt rather than written through: Image.get_data hands back a
		# copy, so the edits have to be put back for them to count.
		var keyed: Image = Image.create_from_data(
			image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data
		)
		image.copy_from(keyed)


# Each frame cut down to what is actually drawn on it. The sizes still
# differ afterwards; _lay_out is what makes them equal.
static func _trimmed(frames: Array[Image]) -> Array[Image]:
	var cut: Array[Image] = []
	for frame in frames:
		var box: Rect2i = frame.get_used_rect()
		cut.append(frame if box.size.x <= 0 or box.size.y <= 0 else frame.get_region(box))
	return cut


# The frames side by side in equal cells: centred across, standing on the
# bottom. Bottom rather than centre because an animal's feet are the part
# that should not move between frames.
static func _lay_out(frames: Array[Image]) -> Image:
	var cell := Vector2i.ZERO
	for frame in frames:
		cell.x = maxi(cell.x, frame.get_width())
		cell.y = maxi(cell.y, frame.get_height())
	if cell.x <= 0 or cell.y <= 0:
		return null
	# Padding only where the frames were trimmed to different sizes; cells
	# taken whole out of a grid already carry their own spacing.
	var even: bool = true
	for frame in frames:
		even = even and frame.get_width() == cell.x and frame.get_height() == cell.y
	if not even:
		cell += Vector2i(PADDING, PADDING) * 2

	var strip: Image = Image.create(
		cell.x * frames.size(), cell.y, false, Image.FORMAT_RGBA8
	)
	strip.fill(Color(0, 0, 0, 0))
	for index in frames.size():
		var frame: Image = frames[index]
		var at := Vector2i(
			index * cell.x + (cell.x - frame.get_width()) / 2,
			cell.y - frame.get_height() - (0 if even else PADDING)
		)
		strip.blit_rect(
			frame, Rect2i(0, 0, frame.get_width(), frame.get_height()), at
		)
	return strip
