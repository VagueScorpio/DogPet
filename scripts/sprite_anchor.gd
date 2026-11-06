class_name SpriteAnchor
extends RefCounted
## Where the drawing actually sits inside the frames of a strip.
##
## A strip is a row of equal cells, but what the artist drew rarely fills
## one. There may be fifty pixels of nothing down the left of every frame
## and a hundred along the bottom. Standing the *cell* on the floor and
## centring the *cell* on the spot therefore puts the dog wherever its
## margins happen to put it - which is how the owner's raccoon came to
## float above the floor, hang off the side of the window, and be drawn at
## three times the size it had asked for. *(v1.46)*
##
## So the app asks this instead: of the whole strip, which part is drawn on?
## That box is what gets stood on the floor, centred on the spot, and
## measured for the scale, and then every pack lands in the same place
## whatever its margins - the ones the import wizard cut, the ones somebody
## wrote a pet.json for by hand, and the ones already installed.
##
## One box for the whole animation rather than one per frame, because the
## difference between frames is the animation: a dog that leans left on
## frame three should lean, not be nudged back to the middle.
##
## Pure: an Image in, a rectangle out. No nodes.


## The box the art occupies within one frame, measured across every frame of
## the strip. Falls back to the whole frame for a strip with nothing drawn
## on it at all.
static func of_strip(sheet: Image, frames: int) -> Rect2i:
	var whole := Rect2i(0, 0, 0, 0)
	if sheet == null:
		return whole
	var count: int = maxi(1, frames)
	var height: int = sheet.get_height()
	var width: int = sheet.get_width() / count
	whole = Rect2i(0, 0, width, height)
	if width <= 0 or height <= 0:
		return whole

	var found: bool = false
	var box := Rect2i()
	for index in count:
		var cell: Image = sheet.get_region(Rect2i(index * width, 0, width, height))
		var used: Rect2i = cell.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		box = used if not found else box.merge(used)
		found = true
	return box if found else whole
