class_name ScenePainter
extends RefCounted
## Paints the backgrounds that have no pictures: the yard, the park and the
## plain indoor room.
##
## A "generated" background in scene.json is drawn in code from a handful of
## colours, which is how the walk scrolls forever without a single image and
## how the vet's room ships without one. The alternative - a picture - is
## loaded and drawn by SceneView itself; this is only the painting.
##
## Everything is scaled by the view's height rather than in fixed pixels, so
## the scenery keeps its proportions whatever size the window is. With fixed
## sizes the dog ended up towering over the trees.
##
## Nothing is stored here: each call is handed the view to draw into, the
## room to draw, and how far the scenery has scrolled. That keeps the
## scrolling state in one place, in SceneView, where _process can move it.

## How many bands the sky gradient is painted in.
const SKY_BANDS := 48

## Spacing and parallax for the repeating layers, as fractions of the view's
## height. Parallax 1.0 travels with the ground; lower is further away.
const CLOUD_SPACING := 0.52
const CLOUD_PARALLAX := 0.25
const TREE_SPACING := 0.46
const TREE_PARALLAX := 0.6
const BUSH_SPACING := 0.34
const STONE_SPACING := 0.17


## Paint one generated background into the view.
static func draw_background(view: Control, pack: ScenePack, scroll: float) -> void:
	var style: String = str(pack.background.get("style", "yard"))
	if style == "room":
		_draw_room(view, pack)
		return

	var size: Vector2 = view.size
	var ground_y: float = size.y * (1.0 - float(pack.background.get("ground_ratio", 0.4)))
	var sky_top: Color = pack.background.get("sky_top", Color.SKY_BLUE)
	var sky_bottom: Color = pack.background.get("sky_bottom", Color.WHITE)
	var ground: Color = pack.background.get("ground", Color.GREEN)

	# Sky, painted as a stack of bands from one colour to the other.
	var band: float = ground_y / float(SKY_BANDS)
	for index in SKY_BANDS:
		var mix: float = float(index) / float(SKY_BANDS - 1)
		view.draw_rect(
			Rect2(0.0, index * band, size.x, band + 1.0),
			sky_top.lerp(sky_bottom, mix)
		)

	_draw_clouds(view, ground_y, scroll)

	view.draw_rect(Rect2(0.0, ground_y, size.x, size.y - ground_y), ground)
	view.draw_rect(Rect2(0.0, ground_y, size.x, 2.0), ground.darkened(0.25))

	if style == "park":
		_draw_trees(view, ground_y, scroll)
		if pack.background.has("path"):
			_draw_path(view, ground_y, pack.background["path"], scroll)
	_draw_bushes(view, ground_y, ground, scroll)


# A plain indoor room: a painted wall, a band of skirting along the
# bottom of it, and a floor. No pictures at all, so a room like this costs
# nothing to ship and takes its colours from its scene.json.
static func _draw_room(view: Control, pack: ScenePack) -> void:
	var size: Vector2 = view.size
	var floor_y: float = size.y * (1.0 - float(pack.background.get("floor_ratio", 0.42)))
	var wall: Color = pack.background.get("wall_color", Color(0.91, 0.89, 0.81))
	var wainscot: Color = pack.background.get("wainscot_color", Color(0.33, 0.52, 0.62))
	var floor_colour: Color = pack.background.get("floor_color", Color(0.80, 0.86, 0.85))

	view.draw_rect(Rect2(0.0, 0.0, size.x, floor_y), wall)

	# The band of skirting, a fifth of the wall, with a lighter rail on top.
	var band: float = floor_y * 0.2
	view.draw_rect(Rect2(0.0, floor_y - band, size.x, band), wainscot)
	view.draw_rect(
		Rect2(0.0, floor_y - band, size.x, maxf(2.0, band * 0.08)),
		wainscot.lightened(0.3)
	)

	view.draw_rect(Rect2(0.0, floor_y, size.x, size.y - floor_y), floor_colour)
	view.draw_rect(Rect2(0.0, floor_y, size.x, 2.0), wainscot.darkened(0.25))

	# Faint seams across the floor, so it reads as a surface rather than a
	# block of colour. Spaced by height, like everything else drawn here.
	var seam: Color = floor_colour.darkened(0.07)
	var spacing: float = size.y * 0.09
	var y: float = floor_y + spacing
	while y < size.y:
		view.draw_rect(Rect2(0.0, y, size.x, 1.0), seam)
		y += spacing
	var x: float = 0.0
	while x < size.x:
		view.draw_rect(Rect2(x, floor_y, 1.0, size.y - floor_y), seam)
		x += spacing * 1.6


static func _draw_clouds(view: Control, ground_y: float, scroll: float) -> void:
	var size: Vector2 = view.size
	var white := Color(1, 1, 1, 0.75)
	var spacing: float = size.y * CLOUD_SPACING
	for index in _layer_range(size, scroll, spacing, CLOUD_PARALLAX):
		var x: float = index * spacing - scroll * CLOUD_PARALLAX
		var y: float = ground_y * (0.12 + 0.3 * _jitter(index, 1.0))
		var width: float = size.y * (0.07 + 0.045 * _jitter(index, 2.0))
		view.draw_circle(Vector2(x, y), width * 0.7, white)
		view.draw_circle(Vector2(x + width * 0.6, y + 3.0), width * 0.55, white)
		view.draw_circle(Vector2(x - width * 0.6, y + 4.0), width * 0.45, white)


static func _draw_trees(view: Control, ground_y: float, scroll: float) -> void:
	var size: Vector2 = view.size
	var spacing: float = size.y * TREE_SPACING
	for index in _layer_range(size, scroll, spacing, TREE_PARALLAX):
		var x: float = index * spacing - scroll * TREE_PARALLAX
		var height: float = size.y * (0.34 + 0.18 * _jitter(index, 3.0))
		var base: float = ground_y + 4.0
		var trunk := Color(0.42, 0.29, 0.18)
		var leaves := Color(0.24, 0.49, 0.25).lightened(0.12 * _jitter(index, 4.0))
		var trunk_width: float = maxf(4.0, height * 0.09)
		view.draw_rect(
			Rect2(x - trunk_width * 0.5, base - height * 0.45, trunk_width, height * 0.45),
			trunk
		)
		var crown := Vector2(x, base - height * 0.6)
		view.draw_circle(crown, height * 0.3, leaves)
		view.draw_circle(crown + Vector2(-height * 0.2, height * 0.1), height * 0.24, leaves)
		view.draw_circle(crown + Vector2(height * 0.2, height * 0.1), height * 0.24, leaves)


static func _draw_path(view: Control, ground_y: float, colour: Color, scroll: float) -> void:
	var size: Vector2 = view.size
	var top: float = ground_y + (size.y - ground_y) * 0.45
	view.draw_rect(Rect2(0.0, top, size.x, size.y - top), colour)
	view.draw_rect(Rect2(0.0, top, size.x, 2.0), colour.darkened(0.18))
	# Stones scudding past at full speed, which is what makes the ground
	# read as moving rather than the whole picture sliding.
	var stone := colour.darkened(0.12)
	var spacing: float = size.y * STONE_SPACING
	for index in _layer_range(size, scroll, spacing, 1.0):
		var x: float = index * spacing - scroll
		var y: float = top + (size.y - top) * (0.25 + 0.6 * _jitter(index, 5.0))
		view.draw_circle(Vector2(x, y), size.y * (0.006 + 0.008 * _jitter(index, 6.0)), stone)


static func _draw_bushes(view: Control, ground_y: float, ground: Color, scroll: float) -> void:
	var size: Vector2 = view.size
	var bush: Color = ground.darkened(0.22)
	var spacing: float = size.y * BUSH_SPACING
	for index in _layer_range(size, scroll, spacing, 1.0):
		var x: float = index * spacing - scroll
		var radius: float = size.y * (0.035 + 0.028 * _jitter(index, 7.0))
		var y: float = ground_y + 2.0 + radius * 0.3
		view.draw_circle(Vector2(x, y), radius, bush)
		view.draw_circle(Vector2(x + radius * 0.8, y + 2.0), radius * 0.7, bush)


# --- Scrolling layers ----------------------------------------------------

## Which copies of a repeating layer are on screen right now. Returning the
## indices rather than positions is what lets a layer scroll forever without
## anything accumulating.
static func _layer_range(
	size: Vector2, scroll: float, spacing: float, parallax: float
) -> Array[int]:
	var shift: float = scroll * parallax
	var first: int = int(floor(shift / spacing)) - 1
	var last: int = int(floor((shift + size.x) / spacing)) + 1
	var out: Array[int] = []
	for index in range(first, last + 1):
		out.append(index)
	return out


## A repeatable number between 0 and 1 for a given item, so the scenery looks
## varied but is identical every time it comes round again.
static func _jitter(index: int, salt: float) -> float:
	var value: float = sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return value - floor(value)
