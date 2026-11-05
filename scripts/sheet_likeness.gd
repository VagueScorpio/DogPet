class_name SheetLikeness
extends RefCounted
## Is this row one animal moving, or several different things?
##
## The whole sheet reader turns on this one question. A row of walk frames
## and a row of different monsters look identical to anything that only
## counts cells, and the answer decides whether what comes out is one
## animation or that many still pictures.
##
## It is answered on the evidence rather than on the file name: frames of an
## animation are mostly the same shape in nearly the same place, because
## they are one animal moving. So each cell is compared with the one beside
## it, and a row whose neighbours overlap well enough is an animation.
##
## Pure arithmetic over a scan. No nodes, no files, nothing to log to.

## How much two neighbouring cells have to overlap, once lined up, before
## they are taken to be the same animal in two poses.
const SAME_ANIMAL := 0.5

## A cell holding less than this share of the biggest cell in its row is not
## a frame: it is a palette swatch, a caption, or a number printed in a
## corner. Measured against the biggest rather than the middle one, because
## half a row of swatches drags the middle down to meet them.
const OUTLIER_SHARE := 0.18

## Two shapes whose heights are further apart than this are different
## animals, whatever happens to overlap.
const SIZE_RATIO := 0.5

## Past this many cells it is a tile set, not an animation.
const MAX_FRAMES := 64


## Do these cells hold one animal moving? Rectangles are in the scan's own
## coordinates.
static func one_animal(scan: Dictionary, scan_rects: Array) -> bool:
	if scan_rects.size() > MAX_FRAMES:
		return false
	return mean(scan, scan_rects) >= SAME_ANIMAL


## How alike a row is, averaged over each neighbouring pair. Zero for a row
## with nothing to compare.
static func mean(scan: Dictionary, scan_rects: Array) -> float:
	if scan_rects.size() < 2:
		return 0.0
	var total: float = 0.0
	for index in range(1, scan_rects.size()):
		total += between(scan, scan_rects[index - 1], scan_rects[index])
	return total / float(scan_rects.size() - 1)


## How alike two cells are, 0 to 1.
##
## The shapes are lined up by their own outlines first - bottom edges and
## middles together, which is how an animal stands whatever its cell - and
## then the overlap is measured against the two put together. A walk cycle
## scores high; a bunny beside a frog scores near nothing.
static func between(scan: Dictionary, first: Rect2i, second: Rect2i) -> float:
	var one: Rect2i = SheetScan.ink_bounds(scan, first)
	var two: Rect2i = SheetScan.ink_bounds(scan, second)
	if one.size.x <= 0 or two.size.x <= 0:
		return 0.0
	var ratio: float = (
		float(mini(one.size.y, two.size.y)) / float(maxi(one.size.y, two.size.y))
	)
	if ratio < SIZE_RATIO:
		return 0.0

	var width: int = maxi(one.size.x, two.size.x)
	var height: int = maxi(one.size.y, two.size.y)
	var shared: int = 0
	var either: int = 0
	for y in height:
		for x in width:
			var a: bool = SheetScan.ink_at(
				scan,
				one.position.x + x - (width - one.size.x) / 2,
				one.end.y - height + y
			)
			var b: bool = SheetScan.ink_at(
				scan,
				two.position.x + x - (width - two.size.x) / 2,
				two.end.y - height + y
			)
			if a and b:
				shared += 1
			if a or b:
				either += 1
	return 0.0 if either == 0 else float(shared) / float(either)


## Which of these cells are frames at all, as indices into the list.
##
## Cells far smaller than the rest of their row are not frames of anything:
## the swatches down the side of a palette sheet, the caption under a pose,
## the 01/02/03 printed on a contact sheet.
static func without_outliers(scan: Dictionary, scan_rects: Array) -> PackedInt32Array:
	var areas: PackedInt32Array = []
	var biggest: int = 0
	for rect in scan_rects:
		var box: Rect2i = SheetScan.ink_bounds(scan, rect)
		areas.append(box.size.x * box.size.y)
		biggest = maxi(biggest, areas[areas.size() - 1])
	var keep: PackedInt32Array = []
	for index in areas.size():
		if areas[index] > 0 and float(areas[index]) >= float(biggest) * OUTLIER_SHARE:
			keep.append(index)
	return keep
