class_name SheetStages
extends RefCounted
## Is this row the same dog growing up, or the same dog moving?
##
## SheetLikeness already answers "one animal, or several different things",
## and a life-cycle row answers that question *yes* - a puppy and the senior
## it becomes are plainly the same animal in the same pose. So likeness
## cannot tell the two apart, and a row of four ages read as an animation
## gives you a dog that flickers through its own lifetime four times a
## second.
##
## What separates them is what the owner said separates them: the drawing
## grows, and the colour drains out of it. An animation's frames are all one
## size and one palette, because they are one dog a tenth of a second apart.
## A life cycle starts small and dark and ends large and grey.
##
## Pure: a scan, an image and some rectangles in, a judgement out. No nodes.

## The fewest drawings worth reading as a progression. Two could as easily
## be a two-frame blink, and guessing wrong there costs more than it gains.
const MIN_STAGES := 3

## How much smaller the first drawing has to be than every other one. A
## puppy is unmistakably smaller than the dog it grows into; an animation's
## first frame is the same size as its last.
const PUPPY_SHARE := 0.85

## How much bigger the largest drawing has to be than the first.
const GROWTH := 1.3

## How far the size may fall back between one drawing and the next. Dogs
## stop growing, and a senior is often drawn a little smaller than an adult,
## so a plateau and a mild shrink are both normal; a collapse is not.
const DIP := 0.75

## How much colour has to drain away between the first drawing and the last
## before it counts as greying.
const GREYING := 0.05

## How far saturation may climb again between one drawing and the next and
## still count as draining away. Ageing only goes one way; a frame that gets
## its colour back is a frame of an animation.
const REGAIN := 0.04

## Roughly how many pixels of each cell to average. A cell is sampled on a
## lattice coarse enough to come to about this many, because an average
## colour does not get meaningfully better past a few thousand samples and
## these cells can be a megapixel each.
const COLOUR_SAMPLES := 4096


## Read a row of cells. Returns:
##
##   {"is_stages", "count", "late_bloom", "growth", "greying", "sizes"}
##
## is_stages is the answer; the rest is the evidence behind it, which the
## wizard shows and tools/read_sheet.gd prints.
static func of_cells(
	scan: Dictionary, image: Image, scan_rects: Array, rects: Array
) -> Dictionary:
	var count: int = scan_rects.size()
	if count < MIN_STAGES or count > LifeStages.MAX_STAGES or rects.size() != count:
		return _no(count)

	var sizes: PackedInt32Array = []
	for rect in scan_rects:
		var box: Rect2i = SheetScan.ink_bounds(scan, rect)
		sizes.append(box.size.x * box.size.y)
	if sizes[0] <= 0:
		return _no(count)

	var colours: Array[Vector2] = []
	for rect in rects:
		colours.append(_colour_of(image, rect))

	var grown: float = float(_largest(sizes)) / float(sizes[0])
	var greyed: float = colours[0].x - colours[count - 1].x
	# Two ways to be a life cycle, because the two sheets that prompted this
	# fail different halves of it. A row of standing dogs grows plainly from
	# puppy to adult. A row of sleeping ones hardly grows at all - a curled
	# puppy and a curled senior take up much the same room - but the colour
	# drains out of it just as plainly.
	#
	# So greying stands on its own, with no size test under it. There is no
	# honest one to apply: the drawings are the same size, which is the
	# whole difficulty. What keeps it from firing on an animation is that
	# the draining has to be steady and one-way over the whole row, and a
	# walk cycle's colour wanders instead.
	var by_size: bool = _first_is_smallest(sizes) and grown >= GROWTH
	var by_colour: bool = _drains(colours, greyed)
	var is_stages: bool = (by_size or by_colour) and not _collapses(sizes)
	return {
		"is_stages": is_stages,
		"count": count,
		"late_bloom": _late_bloom(colours),
		"growth": grown,
		"greying": greyed,
		"sizes": sizes,
	}


# Not a progression: the same shape of answer, so a caller never has to
# check whether the keys are there before reading them.
static func _no(count: int) -> Dictionary:
	return {
		"is_stages": false,
		"count": count,
		"late_bloom": false,
		"growth": 1.0,
		"greying": 0.0,
		"sizes": PackedInt32Array(),
	}


## The stage names for a row this judgement came from, youngest first.
static func names_for(judgement: Dictionary) -> PackedStringArray:
	return LifeStages.names_for(
		int(judgement.get("count", 0)), bool(judgement.get("late_bloom", false))
	)


# --- The measurements -----------------------------------------------------

# The average saturation and lightness of what is drawn in a rectangle, as
# a Vector2 of (saturation, lightness). Transparent pixels are skipped: the
# paper is not part of the dog, and counting it would make every cell on a
# white sheet look equally pale.
## Read straight out of the byte buffer rather than through get_pixel, which
## is the same decision SheetPaper and SheetCutter made and for the same
## reason: get_pixel on a sheet this size takes minutes, and saturation out
## of three bytes is two comparisons and a divide.
static func _colour_of(image: Image, rect: Rect2i) -> Vector2:
	var area: Rect2i = rect.intersection(
		Rect2i(0, 0, image.get_width(), image.get_height())
	)
	if area.size.x <= 0 or area.size.y <= 0:
		return Vector2.ZERO
	var data: PackedByteArray = image.get_data()
	var width: int = image.get_width()
	# Four bytes a pixel is an assumption, and one that was read off the end
	# of the buffer when it did not hold. Cheaper to ask than to be wrong.
	if data.size() < width * image.get_height() * 4:
		return Vector2.ZERO
	var step: int = maxi(1, int(sqrt(
		float(area.size.x * area.size.y) / float(COLOUR_SAMPLES)
	)))

	var saturation: float = 0.0
	var lightness: float = 0.0
	var counted: int = 0
	var y: int = area.position.y
	while y < area.end.y:
		var line: int = y * width
		var x: int = area.position.x
		while x < area.end.x:
			var at: int = (line + x) * 4
			x += step
			if data[at + 3] < 128:
				continue
			var red: int = data[at]
			var green: int = data[at + 1]
			var blue: int = data[at + 2]
			var high: int = maxi(red, maxi(green, blue))
			var low: int = mini(red, mini(green, blue))
			if high > 0:
				saturation += float(high - low) / float(high)
			lightness += float(high) / 255.0
			counted += 1
		y += step
	if counted == 0:
		return Vector2.ZERO
	return Vector2(saturation / float(counted), lightness / float(counted))


# Is the first drawing clearly the smallest of them all?
static func _first_is_smallest(sizes: PackedInt32Array) -> bool:
	for index in range(1, sizes.size()):
		if float(sizes[0]) > float(sizes[index]) * PUPPY_SHARE:
			return false
	return true


# Does the size fall off a cliff anywhere? A plateau is fine; halving is not.
static func _collapses(sizes: PackedInt32Array) -> bool:
	for index in range(1, sizes.size()):
		if float(sizes[index]) < float(sizes[index - 1]) * DIP:
			return true
	return false


# Does the colour drain steadily away across the row?
#
# The total drop has to be there, and it has to be one-way. An animation
# whose frames happen to differ in colour wanders up and down; a dog going
# grey never gets its colour back.
static func _drains(colours: Array[Vector2], greyed: float) -> bool:
	if greyed < GREYING:
		return false
	for index in range(1, colours.size()):
		if colours[index].x > colours[index - 1].x + REGAIN:
			return false
	return true


static func _largest(sizes: PackedInt32Array) -> int:
	var most: int = 0
	for size in sizes:
		most = maxi(most, size)
	return most


# Where in the row the colour starts draining away.
#
# At five drawings this decides between the owner's two readings. Greying
# that has already begun by the second-to-last drawing means the extra stage
# sits late in life - an older adult before the senior. Greying that waits
# until the very last one means the extra stage sits early, and is a young
# adult instead.
static func _late_bloom(colours: Array[Vector2]) -> bool:
	var count: int = colours.size()
	if count < 4:
		return false
	var before: float = colours[0].x - colours[count - 2].x
	var only_at_the_end: float = colours[count - 2].x - colours[count - 1].x
	return before > GREYING and before >= only_at_the_end
