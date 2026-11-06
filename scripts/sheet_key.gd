class_name SheetKey
extends RefCounted
## Taking the page off a sheet without taking the dog with it.
##
## SheetPaper says what colour the page is. Acting on that by clearing every
## pixel of that colour, wherever it sits, is what DogPet used to do, and it
## has one failure that ruins a pack outright: a dog the colour of its own
## page is erased along with the page. The owner's first aged sheet was a
## black-and-tan puppy drawn on a dark navy ground, and what was installed
## was an outline with nothing inside it - 38,071 pixels cleared, 7,262 left
## - which is the "completely transparent" pet they reported. *(v1.46)*
##
## The page is not a colour. The page is the part of the picture the edge
## can reach. So the clearing starts at the border and spreads inwards
## through pixels of the paper's colour, stopping at the first pixel that is
## not one. A dark dog on a dark page keeps every pixel its outline encloses,
## because the fill cannot get in.
##
## What this gives up is the gap a dog leaves between its legs, which stays
## page-coloured when the outline closes round it. That is the same bargain
## the magic wand in any paint program makes, and it is the right way round:
## a bit of page behind the dog is a blemish, a dog with no body is not
## installable at all.
##
## Pure: an Image and a list of colours in, pixels cleared out. No nodes.


## Clear the page out of an image, in place. Returns how many pixels went.
##
## "paper" is what SheetPaper.of_image found; an empty list means the
## background was already transparent and there is nothing to do.
static func clear_page(image: Image, paper: Array) -> int:
	if paper.is_empty() or image == null:
		return 0
	var size: Vector2i = _ready_for_work(image)
	if size.x <= 0:
		return 0

	var data: PackedByteArray = image.get_data()
	var seen: PackedByteArray = _reached_from_border(data, size, paper)
	var cleared: int = 0
	for index in size.x * size.y:
		if seen[index] == 1 and data[index * 4 + 3] != 0:
			data[index * 4 + 3] = 0
			cleared += 1
	if cleared > 0:
		_write_back(image, size, data)
	return cleared


## Put back the pixels an older DogPet cleared from inside the art.
##
## Repair, not import: a pack installed before v1.46 may have had its dog
## keyed out along with its page, and the colours are all still there under
## the cleared alpha - only the alpha was thrown away. Anything cleared that
## the border cannot reach was never page, so its alpha goes back on.
##
## Returns how many pixels came back.
static func restore_enclosed(image: Image) -> int:
	if image == null:
		return 0
	var size: Vector2i = _ready_for_work(image)
	if size.x <= 0:
		return 0

	var data: PackedByteArray = image.get_data()
	var seen: PackedByteArray = _reached_from_border(data, size, [])
	var restored: int = 0
	for index in size.x * size.y:
		if seen[index] == 0 and data[index * 4 + 3] == 0:
			data[index * 4 + 3] = 255
			restored += 1
	if restored > 0:
		_write_back(image, size, data)
	return restored


# --- The fill -------------------------------------------------------------

# Which pixels the edge of the picture can reach, as one byte each.
#
# A pixel is passable when it is already clear, or - with colours given -
# when it is close enough to one of them. With no colours this is the plain
# "what is transparent and connected to the outside" question that the
# repair above asks.
#
# Spans rather than single pixels: popping one pixel and dealing with its
# whole row at once is what keeps a two-megapixel sheet to a sensible number
# of steps in GDScript.
static func _reached_from_border(
	data: PackedByteArray, size: Vector2i, paper: Array
) -> PackedByteArray:
	# Unpacked once: the comparison below runs a few million times, and
	# reading r8/g8/b8 off a Color object every pixel is not free.
	var reds := PackedInt32Array()
	var greens := PackedInt32Array()
	var blues := PackedInt32Array()
	for entry in paper:
		var colour: Color = entry
		reds.append(colour.r8)
		greens.append(colour.g8)
		blues.append(colour.b8)
	var limit: int = SheetPaper.byte_limit()

	var width: int = size.x
	var height: int = size.y
	var seen := PackedByteArray()
	seen.resize(width * height)

	# Every pixel of the border is a starting point. A page the art divides
	# in two - a dog standing on a line drawn across the sheet - is still
	# page on both sides of it, and both sides touch the edge.
	var stack := PackedInt32Array()
	for x in width:
		stack.append(x)
		stack.append((height - 1) * width + x)
	for y in height:
		stack.append(y * width)
		stack.append(y * width + width - 1)

	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if seen[at] == 1:
			continue
		var y: int = at / width
		var row: int = y * width
		var x: int = at - row
		if not _is_page(data, at, reds, greens, blues, limit):
			continue

		var left: int = x
		while left > 0 and seen[row + left - 1] == 0 and _is_page(
			data, row + left - 1, reds, greens, blues, limit
		):
			left -= 1
		var right: int = x
		while right < width - 1 and seen[row + right + 1] == 0 and _is_page(
			data, row + right + 1, reds, greens, blues, limit
		):
			right += 1

		# Only the first pixel of each run on the rows above and below is
		# pushed; the rest of that run is reached by spreading sideways when
		# it is popped.
		var above_run: bool = false
		var below_run: bool = false
		for across in range(left, right + 1):
			var index: int = row + across
			seen[index] = 1
			if y > 0:
				var up: int = index - width
				var up_ok: bool = seen[up] == 0 and _is_page(
					data, up, reds, greens, blues, limit
				)
				if up_ok and not above_run:
					stack.append(up)
				above_run = up_ok
			if y < height - 1:
				var down: int = index + width
				var down_ok: bool = seen[down] == 0 and _is_page(
					data, down, reds, greens, blues, limit
				)
				if down_ok and not below_run:
					stack.append(down)
				below_run = down_ok
	return seen


# Is this pixel part of the page? Either it is already transparent - a sheet
# whose background was half taken off before it got here - or it is close
# enough to one of the paper colours.
static func _is_page(
	data: PackedByteArray, index: int,
	reds: PackedInt32Array, greens: PackedInt32Array, blues: PackedInt32Array,
	limit: int
) -> bool:
	var at: int = index * 4
	if data[at + 3] < SheetPaper.CLEAR_ALPHA:
		return true
	for which in reds.size():
		if (
			absi(data[at] - reds[which])
			+ absi(data[at + 1] - greens[which])
			+ absi(data[at + 2] - blues[which])
		) <= limit:
			return true
	return false


static func _ready_for_work(image: Image) -> Vector2i:
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var size: Vector2i = image.get_size()
	return size if size.x > 0 and size.y > 0 else Vector2i.ZERO


# Image.get_data hands back a copy, so the edits have to be put back for
# them to count.
static func _write_back(image: Image, size: Vector2i, data: PackedByteArray) -> void:
	image.copy_from(
		Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)
	)
