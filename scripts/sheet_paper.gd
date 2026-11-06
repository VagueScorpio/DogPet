class_name SheetPaper
extends RefCounted
## What colour the page is, under the art.
##
## A sheet of sprites is drawn on something: white paper, a flat grey, or
## the grey checkerboard a drawing program puts behind transparency and a
## screenshot keeps. Everything the sheet reader does afterwards depends on
## telling that apart from the art, so it is worked out here and nowhere
## else, and the answer is a list of colours - empty when the background was
## already transparent and there is nothing to key out.
##
## No nodes, no autoloads, nothing but an Image in and colours out.

## How far from a paper colour a pixel may be and still be that colour. Low
## enough to keep a pale dog on white paper, high enough to swallow the
## paper's own gradient and the fuzz around a pasted sprite.
const PAPER_TOLERANCE := 0.09

## Alpha below this is nothing at all, whatever colour it claims to be.
const CLEAR_ALPHA := 8

## How much of the picture one colour has to cover before it is the paper.
const PAPER_SHARE := 0.22

## Two colours covering this much between them are a checkerboard. Both
## count as paper.
const CHECKER_SHARE := 0.45
const CHECKER_SECOND := 0.12

## How alike the two squares of a checkerboard have to be. They are one
## colour in two shades; two colours further apart than this are a picture.
const CHECKER_LIKENESS := 0.22

## A picture with this much real transparency has had its background taken
## off already, whatever else it is mostly made of.
const ALREADY_CLEAR := 0.1

## How much of the picture's outer ring a colour has to cover before it is
## the background.
##
## Counting alone cannot tell a background from a subject: a sheet cropped
## tight has more dog on it than page, and either reading is arithmetically
## respectable. What settles it is where the colour is. A background is what
## the edge of the page is made of, which is true of every sheet anybody will
## hand this app and false of every dog, because a dog is drawn in the middle
## of its cell.
##
## Half rather than all of it, because art legitimately reaches the edge -
## feet on the bottom row, a tail running off the side - and that should not
## cost a sheet its background.
const BORDER_SHARE := 0.5

## How deep the ring is, in pixels. Four corners is the cheap version of this
## test and too easily fooled: a sprite in the corner of the first cell, or
## one stray mark, flips it. A few pixels on all four sides is thousands of
## samples and cannot be swung by a blot. Scaled down for a small picture,
## where three pixels would be most of it.
const BORDER_DEPTH := 3

## How many colours are tried as the paper, commonest first. Enough to get
## past a subject drawn in two or three flat colours.
const MAX_CANDIDATES := 4


## The paper colours of an image, which must already be RGBA8. Empty means
## the background is transparent, so every visible pixel is art.
static func of_image(image: Image) -> Array[Color]:
	var data: PackedByteArray = image.get_data()
	var pixels: int = image.get_width() * image.get_height()
	var clear: int = 0
	var tally: Dictionary = {}
	# Every fourth pixel. A background covering a fifth of the picture is
	# still a fifth of any even sample of it, and this runs four times less.
	var sampled: int = 0
	for index in range(0, pixels, 4):
		var at: int = index * 4
		if data[at + 3] < CLEAR_ALPHA:
			clear += 1
			continue
		sampled += 1
		var key: int = ((data[at] >> 3) << 10) | ((data[at + 1] >> 3) << 5) | (data[at + 2] >> 3)
		tally[key] = int(tally.get(key, 0)) + 1

	var counted: int = clear + sampled
	if counted == 0 or float(clear) / float(counted) > ALREADY_CLEAR:
		return []

	# Taken as neighbourhoods rather than buckets. A flat colour out of a
	# paint program lands in one bucket; a background with the faintest
	# gradient or compression noise on it is spread over a dozen, and
	# counting buckets alone would then find no background at all - which is
	# how a whole contact sheet ended up being read as one picture.
	var candidates: Array[Vector2i] = _candidates(tally)
	var paper: Array[Color] = []
	if candidates.is_empty():
		return paper
	var ring: Dictionary = _border(image)

	var first: Color = _from_key(candidates[0].x)
	var second: Color = _from_key(candidates[1].x) if candidates.size() > 1 else first
	# The pair is asked about first, because a checkerboard splits its own
	# vote: two greys covering half the sheet between them are plainly the
	# background, and neither of them on its own looks like much.
	if (
		candidates.size() > 1
		and float(candidates[1].y) / float(counted) >= CHECKER_SECOND
		and float(candidates[0].y + candidates[1].y) / float(counted) >= CHECKER_SHARE
		# Both squares of a checkerboard are the same colour in two shades.
		# Without this, a blue box on a white page is two colours covering
		# the whole picture between them, and the box is read as background.
		and apart(first, second) <= CHECKER_LIKENESS
		# And a checkerboard reaches the border, like any other background.
		and _ring_share(ring, [first, second]) >= BORDER_SHARE
	):
		paper.append(first)
		paper.append(second)
		return paper

	# The commonest colour is not always the paper. A sheet cropped tight has
	# more dog on it than page, and taking the dog for the background keys the
	# dog out and installs the hole it left. So the candidates are tried in
	# order and the first one that is also what the border is made of wins -
	# which in that case is the page, sitting second on count.
	for candidate in candidates:
		if float(candidate.y) / float(counted) < PAPER_SHARE:
			break
		var colour: Color = _from_key(candidate.x)
		if _ring_share(ring, [colour]) >= BORDER_SHARE:
			paper.append(colour)
			return paper
	return paper


## How far apart two colours are, averaged over the three channels.
static func apart(one: Color, two: Color) -> float:
	return (absf(one.r - two.r) + absf(one.g - two.g) + absf(one.b - two.b)) / 3.0


## The same comparison the scanner makes, as whole bytes: cheaper, and the
## answer to the same question asked a few million times.
static func byte_limit() -> int:
	return int(PAPER_TOLERANCE * 255.0 * 3.0)


# The paper candidates, commonest first, as (key, count) pairs. Each one is
# claimed out of the tally as it is taken, so the next is a different colour
# and not the same background one shade along.
static func _candidates(tally: Dictionary) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for _which in MAX_CANDIDATES:
		var key: int = _biggest(tally)
		if key < 0:
			break
		found.append(Vector2i(key, _claim(tally, key)))
	return found


# A tally of the picture's outer ring, as {"tally": Dictionary, "counted": int}.
#
# Walked as four strips rather than as the whole picture with the middle
# skipped, so a sheet of two million pixels costs a few thousand reads here
# rather than two million comparisons.
static func _border(image: Image) -> Dictionary:
	var data: PackedByteArray = image.get_data()
	var width: int = image.get_width()
	var height: int = image.get_height()
	var depth: int = clampi(mini(width, height) / 8, 1, BORDER_DEPTH)
	var ring: Dictionary = {"tally": {}, "counted": 0}

	var top: int = mini(depth, height)
	var bottom: int = maxi(top, height - depth)
	_tally_rect(ring, data, width, Rect2i(0, 0, width, top))
	_tally_rect(ring, data, width, Rect2i(0, bottom, width, height - bottom))
	var middle: int = bottom - top
	if middle > 0:
		var side: int = mini(depth, width)
		var right: int = maxi(side, width - depth)
		_tally_rect(ring, data, width, Rect2i(0, top, side, middle))
		_tally_rect(ring, data, width, Rect2i(right, top, width - right, middle))
	return ring


# One rectangle of the picture, into a ring tally.
static func _tally_rect(
	ring: Dictionary, data: PackedByteArray, width: int, area: Rect2i
) -> void:
	var tally: Dictionary = ring["tally"]
	var counted: int = int(ring["counted"])
	for y in range(area.position.y, area.end.y):
		var line: int = y * width
		for x in range(area.position.x, area.end.x):
			var at: int = (line + x) * 4
			if at + 3 >= data.size():
				continue
			if data[at + 3] < CLEAR_ALPHA:
				continue
			counted += 1
			var key: int = (
				((data[at] >> 3) << 10) | ((data[at + 1] >> 3) << 5) | (data[at + 2] >> 3)
			)
			tally[key] = int(tally.get(key, 0)) + 1
	ring["counted"] = counted


# How much of the ring these colours cover between them, 0.0 to 1.0. A ring
# with nothing opaque in it answers 1.0: a picture whose whole edge is
# transparent has no border to argue with, so the count decides alone.
static func _ring_share(ring: Dictionary, colours: Array) -> float:
	var counted: int = int(ring["counted"])
	if counted <= 0:
		return 1.0
	var tally: Dictionary = ring["tally"]
	var total: int = 0
	for key in tally:
		var found: Color = _from_key(key)
		for colour in colours:
			if apart(found, colour) <= PAPER_TOLERANCE:
				total += int(tally[key])
				break
	return float(total) / float(counted)


# The bucket holding the most, or -1 when the tally is spent.
static func _biggest(tally: Dictionary) -> int:
	var best: int = -1
	var most: int = 0
	for key in tally:
		if int(tally[key]) > most:
			most = tally[key]
			best = key
	return best


# Everything close enough to this colour to be the same colour, counted and
# then taken out of the tally so the next-biggest is a different colour and
# not the same background one shade along.
static func _claim(tally: Dictionary, key: int) -> int:
	if key < 0:
		return 0
	var colour: Color = _from_key(key)
	var total: int = 0
	var spent: Array[int] = []
	for other in tally:
		if apart(_from_key(other), colour) > PAPER_TOLERANCE:
			continue
		total += int(tally[other])
		spent.append(other)
	for other in spent:
		tally.erase(other)
	return total


# Quantised keys lose the bottom three bits; putting them back in the middle
# of the range keeps the colour within half a step of the original.
static func _from_key(key: int) -> Color:
	return Color8(
		((key >> 10) & 31) << 3 | 4, ((key >> 5) & 31) << 3 | 4, (key & 31) << 3 | 4
	)
