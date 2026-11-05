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

	# Taken as two neighbourhoods rather than two buckets. A flat colour out
	# of a paint program lands in one bucket; a background with the faintest
	# gradient or compression noise on it is spread over a dozen, and
	# counting buckets alone would then find no background at all - which is
	# how a whole contact sheet ended up being read as one picture.
	var first: int = _biggest(tally)
	var first_count: int = _claim(tally, first)
	var second: int = _biggest(tally)
	var second_count: int = _claim(tally, second) if second >= 0 else 0

	var paper: Array[Color] = []
	if first < 0:
		return paper
	# The pair is asked about first, because a checkerboard splits its own
	# vote: two greys covering half the sheet between them are plainly the
	# background, and neither of them on its own looks like much.
	if (
		second >= 0
		and float(second_count) / float(counted) >= CHECKER_SECOND
		and float(first_count + second_count) / float(counted) >= CHECKER_SHARE
		# Both squares of a checkerboard are the same colour in two shades.
		# Without this, a blue box on a white page is two colours covering
		# the whole picture between them, and the box is read as background.
		and apart(_from_key(first), _from_key(second)) <= CHECKER_LIKENESS
	):
		paper.append(_from_key(first))
		paper.append(_from_key(second))
		return paper
	if float(first_count) / float(counted) >= PAPER_SHARE:
		paper.append(_from_key(first))
	return paper


## How far apart two colours are, averaged over the three channels.
static func apart(one: Color, two: Color) -> float:
	return (absf(one.r - two.r) + absf(one.g - two.g) + absf(one.b - two.b)) / 3.0


## The same comparison the scanner makes, as whole bytes: cheaper, and the
## answer to the same question asked a few million times.
static func byte_limit() -> int:
	return int(PAPER_TOLERANCE * 255.0 * 3.0)


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
