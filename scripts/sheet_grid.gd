class_name SheetGrid
extends RefCounted
## Finding the grid in a sheet: how many cells across, how many down, and
## which of them hold anything.
##
## This is arithmetic over the two tallies SheetScan produced - how much is
## drawn down each column, and across each row - and nothing else. It never
## opens a file and never looks at a pixel, which is what lets the tests hand
## it a hand-written array of numbers and check the answer exactly.
##
## The method is the obvious one done carefully: a sheet is cut into cells by
## the empty lanes between them, so the lanes are found first, counted, and
## then checked against the width. A sheet whose lanes do not line up is
## reported as irregular rather than guessed at, because a wrong grid cuts
## every dog on it in half.

## The most cells this will look for along one side. Past this the sheet is
## a tile set rather than anything a pet pack has a use for.
const MAX_DIVISIONS := 64

## A cell holding less ink than this is empty - a blank square in a sheet
## that does not fill every slot.
const EMPTY_CELL := 0.004

## How thin the join between two touching frames has to be, against the
## average for the strip, before it counts as a join at all.
const JOIN_DIP := 0.85

## How far the lanes may drift from evenly spaced and still count as a grid.
const PITCH_DRIFT := 0.22


## The spans of a tally that hold something, as (start, length) pairs.
static func runs(tally: PackedInt32Array, floor_level: int = 0) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var start: int = -1
	for index in tally.size():
		if tally[index] > floor_level:
			if start < 0:
				start = index
			continue
		if start >= 0:
			found.append(Vector2i(start, index - start))
			start = -1
	if start >= 0:
		found.append(Vector2i(start, tally.size() - start))
	return found


## How many cells this tally is divided into, and how wide one is.
##
## Returns {"count", "cell", "regular"}. "regular" is the part worth reading:
## false means the lanes were found but do not sit at even spacing, so the
## count is what was seen rather than a grid that can be cut by multiplying.
static func divisions(tally: PackedInt32Array, floor_level: int = 0) -> Dictionary:
	var length: int = tally.size()
	if length <= 0:
		return {"count": 0, "cell": 0, "regular": false}
	var spans: Array[Vector2i] = runs(tally, floor_level)
	if spans.is_empty():
		return {"count": 0, "cell": 0, "regular": false}
	if spans.size() == 1:
		return {"count": 1, "cell": length, "regular": true}

	# The pitch is the step from one cell to the next, and the smallest step
	# is the one to take: a blank cell leaves a double step, never a half
	# one. Steps far below the rest are thrown out first, because two
	# sprites a pixel apart inside one cell would otherwise make the pitch
	# one pixel and the sheet sixty-four cells wide.
	var steps: PackedInt32Array = []
	for index in range(1, spans.size()):
		steps.append(spans[index].x - spans[index - 1].x)
	steps.sort()
	var pitch: int = 0
	var middle: int = steps[steps.size() / 2]
	for step in steps:
		if float(step) >= float(middle) * 0.5:
			pitch = step
			break
	if pitch <= 0:
		return {"count": spans.size(), "cell": 0, "regular": false}

	# The count the pitch implies, and the count actually seen. They agree on
	# a full sheet; they differ when some cells are blank, and then the pitch
	# is the one to believe - a row of three bunnies with a gap in the middle
	# is still a four-cell row.
	var by_pitch: int = int(roundf(float(length) / float(pitch)))
	var count: int = clampi(maxi(by_pitch, spans.size()), 1, MAX_DIVISIONS)
	var even: bool = _evenly_spaced(spans, pitch)

	# A grid divides the side it is on. When it does not, the sheet has a
	# margin down one edge, and the lanes themselves are the better answer.
	if length % count == 0 and even:
		return {"count": count, "cell": length / count, "regular": true}
	if even and absi(count * pitch - length) <= pitch:
		return {"count": count, "cell": pitch, "regular": true}
	return {"count": spans.size(), "cell": 0, "regular": false}


## The grid of a whole scan, in the scan's own coordinates and in the
## picture's. Returns:
##
##   {"columns", "rows"}        how many cells each way
##   {"cell", "scan_cell"}      one cell, in full pixels and scanned ones
##   {"regular"}                true when both sides divided cleanly
##   {"occupied"}               one byte per cell, row by row, 1 = holds art
##   {"filled"}                 how many cells hold art
static func of_scan(scan: Dictionary) -> Dictionary:
	var scan_size: Vector2i = scan["scan_size"]
	if scan_size.x <= 0 or scan_size.y <= 0:
		return _nothing()

	# A stray pixel left by anti-aliasing should not fill a lane, so a lane
	# is allowed a little ink before it stops being a lane.
	var across: Dictionary = divisions(scan["columns"], _floor_for(scan_size.y))
	var down: Dictionary = divisions(scan["rows"], _floor_for(scan_size.x))
	var columns: int = int(across["count"])
	var rows: int = int(down["count"])
	if columns <= 0 or rows <= 0:
		return _nothing()

	var size: Vector2i = scan["size"]
	# Counted in cells and worked back out of the full width, so a sheet
	# measured at half size still reports the cell it really has.
	var cell := Vector2i(size.x / columns, size.y / rows)
	var scan_cell := Vector2i(scan_size.x / columns, scan_size.y / rows)
	var regular: bool = (
		bool(across["regular"]) and bool(down["regular"])
		and size.x % columns == 0 and size.y % rows == 0
		and scan_cell.x > 0 and scan_cell.y > 0
	)

	var occupied: PackedByteArray = []
	var filled: int = 0
	if regular:
		occupied.resize(columns * rows)
		for row in rows:
			for column in columns:
				var area := Rect2i(
					Vector2i(column * scan_cell.x, row * scan_cell.y), scan_cell
				)
				var holds: int = 1 if SheetScan.ink_share(scan, area) > EMPTY_CELL else 0
				occupied[row * columns + column] = holds
				filled += holds

	return {
		"columns": columns,
		"rows": rows,
		"cell": cell,
		"scan_cell": scan_cell,
		"regular": regular,
		"occupied": occupied,
		"filled": filled,
	}


## Which cells of one row hold art, left to right.
static func cells_in_row(grid: Dictionary, row: int) -> PackedInt32Array:
	var found: PackedInt32Array = []
	var columns: int = int(grid.get("columns", 0))
	var occupied: PackedByteArray = grid.get("occupied", PackedByteArray())
	for column in columns:
		var at: int = row * columns + column
		if at < occupied.size() and occupied[at] == 1:
			found.append(column)
	return found


## Where one cell sits, in the picture's own pixels.
static func cell_rect(grid: Dictionary, row: int, column: int) -> Rect2i:
	var cell: Vector2i = grid.get("cell", Vector2i.ZERO)
	return Rect2i(Vector2i(column * cell.x, row * cell.y), cell)


## The same cell in the coordinates the scan was measured at.
static func scan_cell_rect(grid: Dictionary, row: int, column: int) -> Rect2i:
	var cell: Vector2i = grid.get("scan_cell", Vector2i.ZERO)
	return Rect2i(Vector2i(column * cell.x, row * cell.y), cell)


## A rectangle cut into equal columns. The last one takes the remainder, so
## nothing is lost when the width does not divide at the measured size.
static func even_parts(rect: Rect2i, count: int) -> Array[Rect2i]:
	var parts: Array[Rect2i] = []
	var width: int = rect.size.x / count
	for index in count:
		var left: int = rect.position.x + index * width
		var wide: int = rect.end.x - left if index == count - 1 else width
		parts.append(Rect2i(left, rect.position.y, wide, rect.size.y))
	return parts


## True when any of these rectangles holds nothing at all.
static func any_blank(scan: Dictionary, parts: Array[Rect2i]) -> bool:
	for part in parts:
		if SheetScan.ink_share(scan, part) <= 0.0:
			return true
	return false


## Is there less drawn where an even division into this many would cut than
## there is on average?
##
## Two figures standing on the same floor still leave a thinner column
## between them than through their middles. A wide picture that is simply
## full of ink has no such dip anywhere, and should be left whole - without
## this, a backdrop handed to the wizard is sliced into four identical
## rectangles and called a four-frame animation.
static func dips_at_joins(tally: PackedInt32Array, count: int) -> bool:
	if tally.size() < count * 2:
		return false
	var average: float = 0.0
	for value in tally:
		average += float(value)
	average /= float(tally.size())
	if average <= 0.0:
		return false
	for index in range(1, count):
		var at: int = int(roundf(float(tally.size()) * float(index) / float(count)))
		var thinnest: int = mini(
			tally[clampi(at, 0, tally.size() - 1)],
			tally[clampi(at - 1, 0, tally.size() - 1)]
		)
		if float(thinnest) > average * JOIN_DIP:
			return false
	return true


# A lane may hold this much ink and still be a lane: a fraction of the side
# crossing it, so a long sheet is not held to the same pixel count as a
# short one, and never less than one pixel.
static func _floor_for(crossing: int) -> int:
	return maxi(0, int(float(crossing) * 0.004))


static func _evenly_spaced(spans: Array[Vector2i], pitch: int) -> bool:
	var allowed: float = maxf(1.5, float(pitch) * PITCH_DRIFT)
	for index in range(1, spans.size()):
		var step: int = spans[index].x - spans[index - 1].x
		# A blank cell leaves a double step, which is still the same grid.
		var multiple: int = maxi(1, int(roundf(float(step) / float(pitch))))
		if absf(float(step) - float(multiple * pitch)) > allowed:
			return false
	return true


static func _nothing() -> Dictionary:
	return {
		"columns": 0,
		"rows": 0,
		"cell": Vector2i.ZERO,
		"scan_cell": Vector2i.ZERO,
		"regular": false,
		"occupied": PackedByteArray(),
		"filled": 0,
	}
