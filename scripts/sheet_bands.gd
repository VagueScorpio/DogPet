class_name SheetBands
extends RefCounted
## Where the frames are on the page.
##
## A sheet is read a row at a time, and this works out what the rows are and
## which cells each of them holds. There are two ways to it. A sheet with a
## grid in it hands the rows over for nothing: SheetGrid has already found
## them. A sheet without one - sprites dropped on a page at whatever spacing
## somebody felt like - has its rows found from the bands of ink across it,
## and its cells from where those bands meet the bands of ink down it.
##
## Then there is the third case, where the frames touch and there is no lane
## anywhere to find them by. That is split_touching, and it has to guess.
##
## A band is {"columns", "rects", "scan_rects", "even"}: the cells in full
## pixels and in the scan's own, left to right. Pure, like the rest.

## A band shorter than this share of the usual band height is not a row.
const THIN_BAND := 0.45

## A single cell this many times wider than it is tall is a strip whose
## frames touch, with no lane between them to find.
const WIDE_CELL := 1.5

## The most ways a touching strip is tried at, and the narrowest frame worth
## believing in.
const MAX_SPLIT := 16
const MIN_FRAME_WIDTH := 6

## How much better a split has to score before more frames beat fewer.
const SPLIT_MARGIN := 0.05

## How much ink a row of the page may hold and still be the gap between two
## rows: a fraction of the width, so a wide sheet is not held to the same
## pixel count as a narrow one.
const ROW_FLOOR := 250


## The rows of a sheet, in reading order.
static func of_scan(scan: Dictionary, grid: Dictionary) -> Array[Dictionary]:
	return _from_grid(grid) if bool(grid["regular"]) else _from_ink(scan)


## A strip whose frames touch, cut by trying every even division and keeping
## the one whose pieces look most like each other.
##
## There is no lane to find in a strip like this - the dogs are drawn edge to
## edge - so the only evidence left is that the right division is the one
## that makes every piece a dog. Three pugs across a 96-pixel band score well
## at three and badly at two, because two leaves a pug and a half in each.
##
## Returns {"rects", "scan_rects"}, or empty when nothing convincing fits.
static func split_touching(scan: Dictionary, rect: Rect2i, scan_rect: Rect2i) -> Dictionary:
	if float(rect.size.x) < float(rect.size.y) * WIDE_CELL:
		return {}
	var tally: PackedInt32Array = SheetScan.column_tally(scan, scan_rect)
	var scores: Dictionary = {}
	var best: float = 0.0
	for count in range(2, MAX_SPLIT + 1):
		if rect.size.x % count != 0:
			continue
		if rect.size.x / count < MIN_FRAME_WIDTH:
			break
		var parts: Array[Rect2i] = SheetGrid.even_parts(scan_rect, count)
		if SheetGrid.any_blank(scan, parts) or not SheetGrid.dips_at_joins(tally, count):
			continue
		var score: float = SheetLikeness.mean(scan, parts)
		if score < SheetLikeness.SAME_ANIMAL:
			continue
		scores[count] = score
		best = maxf(best, score)

	# The most frames that still scores about as well as the best division.
	# Four frames read as two pairs scores nearly as well as four, and four
	# is the honest answer.
	var chosen: int = 0
	for count in scores:
		if float(scores[count]) >= best - SPLIT_MARGIN and count > chosen:
			chosen = count
	if chosen == 0:
		return {}
	return {
		"rects": SheetGrid.even_parts(rect, chosen),
		"scan_rects": SheetGrid.even_parts(scan_rect, chosen),
	}


# One band per row of a regular grid, holding the rects of its filled cells.
static func _from_grid(grid: Dictionary) -> Array[Dictionary]:
	var bands: Array[Dictionary] = []
	for row in int(grid["rows"]):
		var columns: PackedInt32Array = SheetGrid.cells_in_row(grid, row)
		if columns.is_empty():
			continue
		var rects: Array[Rect2i] = []
		var scan_rects: Array[Rect2i] = []
		for column in columns:
			rects.append(SheetGrid.cell_rect(grid, row, column))
			scan_rects.append(SheetGrid.scan_cell_rect(grid, row, column))
		bands.append({
			"columns": columns, "rects": rects, "scan_rects": scan_rects, "even": true,
		})
	return bands


# The same for a sheet with no grid in it.
static func _from_ink(scan: Dictionary) -> Array[Dictionary]:
	var step: int = int(scan["scale"])
	var size: Vector2i = scan["scan_size"]
	var down: Array[Vector2i] = SheetGrid.runs(scan["rows"], maxi(0, size.x / ROW_FLOOR))
	var bands: Array[Dictionary] = []
	for span in down:
		var strip := Rect2i(0, span.x, size.x, span.y)
		var across: Array[Vector2i] = _columns_in(scan, strip)
		if across.is_empty():
			continue
		var rects: Array[Rect2i] = []
		var scan_rects: Array[Rect2i] = []
		var columns: PackedInt32Array = []
		for index in across.size():
			var cell := Rect2i(across[index].x, span.x, across[index].y, span.y)
			scan_rects.append(cell)
			rects.append(Rect2i(cell.position * step, cell.size * step))
			columns.append(index)
		bands.append({
			"columns": columns, "rects": rects, "scan_rects": scan_rects, "even": false,
		})
	return _without_thin_bands(bands)


# A band a fraction of the height of the rest of them is not a row of the
# sheet: it is the strip of colour swatches printed above each row of a
# palette sheet, or the caption under one. Dropped, because kept it becomes
# a four-frame animation of coloured dots.
static func _without_thin_bands(bands: Array[Dictionary]) -> Array[Dictionary]:
	if bands.size() < 2:
		return bands
	var heights: PackedInt32Array = []
	for band in bands:
		heights.append(Rect2i(band["scan_rects"][0]).size.y)
	var sorted: PackedInt32Array = heights.duplicate()
	sorted.sort()
	# With two bands the median is simply the taller of them, which is the
	# comparison wanted anyway: a row of captions under a row of dogs is a
	# third of its height or less. Held to the same bar as a sheet with
	# three bands on it, rather than to a looser one, because a caption is a
	# caption whether or not anything else was printed below it.
	var middle: int = sorted[sorted.size() / 2]
	var kept: Array[Dictionary] = []
	for index in bands.size():
		if float(heights[index]) >= float(middle) * THIN_BAND:
			kept.append(bands[index])
	return kept if not kept.is_empty() else bands


# The columns holding ink inside one horizontal band.
static func _columns_in(scan: Dictionary, strip: Rect2i) -> Array[Vector2i]:
	var spans: Array[Vector2i] = SheetGrid.runs(SheetScan.column_tally(scan, strip), 0)
	var found: Array[Vector2i] = []
	for span in spans:
		found.append(Vector2i(strip.position.x + span.x, span.y))
	return found
