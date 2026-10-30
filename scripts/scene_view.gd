class_name SceneView
extends Control
## Draws one room: its background, then its props.
##
## Everything is drawn directly in _draw rather than built out of nodes.
## That keeps the three very different background types in one place, makes
## the scrolling park a matter of one offset, and means a room can be thrown
## away and replaced without tidying up a tree of children.
##
## Props are drawn after the background and in depth order, so something low
## in the window overlaps whatever is further back. The dog is drawn above
## all of this, on its own layer.

## How many bands the sky gradient is painted in. Enough to look smooth,
## few enough to cost nothing.
const SKY_BANDS := 48

## Scenery is sized as a fraction of the view height rather than in fixed
## pixels, so it keeps its proportions against the dog - who is also sized
## from the view - however big the window is. With fixed pixel sizes the
## dog ended up towering over the trees.
const CLOUD_SPACING := 0.52
const CLOUD_PARALLAX := 0.25
const TREE_SPACING := 0.46
const TREE_PARALLAX := 0.6
const BUSH_SPACING := 0.34
const STONE_SPACING := 0.17

var pack: ScenePack = null

# Loaded once per room and kept, so _draw never touches the disk.
var _textures: Dictionary = {}

# How far the scenery has travelled, for the scrolling park.
var _scroll: float = 0.0

# The thrown toy's displacement from where the prop normally sits.
var _toy_offset := Vector2.ZERO
var _toy_hidden: bool = false


func _init() -> void:
	# Pixel art everywhere, so never smooth it.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Show a room. Loads every picture it needs once, up front.
func setup(room: ScenePack) -> void:
	pack = room
	_textures.clear()
	_scroll = 0.0
	_toy_offset = Vector2.ZERO
	_toy_hidden = false
	if pack == null:
		return

	var type: String = str(pack.background.get("type", ScenePack.BG_GENERATED))
	if type == ScenePack.BG_IMAGE or type == ScenePack.BG_TILED:
		for key in ["file", "wall", "floor"]:
			if pack.background.has(key):
				_load(str(pack.background[key]))
	for prop in pack.props:
		_load(str(prop["file"]))

	set_process(pack.scrolls())
	queue_redraw()


func _process(delta: float) -> void:
	_scroll += float(pack.background.get("scroll_speed_px", 0.0)) * delta
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _load(file: String) -> void:
	if file.is_empty() or _textures.has(file):
		return
	var texture: ImageTexture = PetLoader.load_texture(pack.dir.path_join(file))
	if texture == null:
		Log.warn("Could not read %s for the room \"%s\"." % [file, pack.id])
		return
	_textures[file] = texture


# --- Where things are ----------------------------------------------------

## Where a prop sits on screen, in this view's coordinates: the middle of
## it, along the ground. The dog walks to this to eat.
func prop_screen_position(role: String) -> Vector2:
	if pack == null:
		return size * 0.5
	var prop: Dictionary = pack.prop_with_role(role)
	if prop.is_empty():
		return Vector2(size.x * pack.pet_spot.x, size.y * pack.pet_spot.y)
	return Vector2(size.x * float(prop["x"]), size.y * float(prop["y"]))


## Throw the toy about for a while: an arc out and back, a few times over.
func throw_toy(seconds: float) -> void:
	if pack == null or pack.prop_with_role(ScenePack.ROLE_TOY).is_empty():
		return
	var throws: int = maxi(2, int(seconds / 2.6))
	var tween: Tween = create_tween()
	for index in throws:
		# Alternate sides so the dog has to turn and chase.
		var reach: float = size.x * (0.3 if index % 2 == 0 else -0.3)
		tween.tween_method(_arc_toy.bind(reach), 0.0, 1.0, seconds / throws * 0.6)
		tween.tween_interval(seconds / throws * 0.4)
	tween.tween_callback(func() -> void: _toy_offset = Vector2.ZERO)


# One throw: across in a straight line, up and down in an arc.
func _arc_toy(amount: float, reach: float) -> void:
	_toy_offset = Vector2(reach * amount, -size.y * 0.22 * sin(amount * PI))
	queue_redraw()


# --- Drawing -------------------------------------------------------------

func _draw() -> void:
	if pack == null:
		return
	match str(pack.background.get("type", ScenePack.BG_GENERATED)):
		ScenePack.BG_IMAGE:
			_draw_image_background()
		ScenePack.BG_TILED:
			_draw_tiled_background()
		_:
			_draw_generated_background()
	_draw_props()


# One picture, scaled to cover the window. Cropped rather than stretched,
# so nothing comes out the wrong shape when the window is resized.
func _draw_image_background() -> void:
	var texture: Texture2D = _textures.get(str(pack.background.get("file", "")), null)
	if texture == null:
		return
	var source: Vector2 = texture.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var scale: float = maxf(size.x / source.x, size.y / source.y)
	var drawn: Vector2 = source * scale
	draw_texture_rect(texture, Rect2((size - drawn) * 0.5, drawn), false)


# Repeating wall and floor tiles, with the wall lined up to finish exactly
# at the floor so the join is clean however tall the window is.
func _draw_tiled_background() -> void:
	var wall: Texture2D = _textures.get(str(pack.background.get("wall", "")), null)
	var floor_tex: Texture2D = _textures.get(str(pack.background.get("floor", "")), null)
	var tile_scale: int = int(pack.background.get("tile_scale", 1))
	var floor_y: float = size.y * (1.0 - float(pack.background.get("floor_ratio", 0.38)))

	if wall != null:
		var tile: Vector2 = wall.get_size() * tile_scale
		if tile.x > 0.0 and tile.y > 0.0:
			# Walk upwards from the floor line so the bottom row is whole.
			var y: float = floor_y - tile.y
			while y > -tile.y:
				var x: float = 0.0
				while x < size.x:
					draw_texture_rect(wall, Rect2(Vector2(x, y), tile), false)
					x += tile.x
				y -= tile.y

	if floor_tex != null:
		var tile: Vector2 = floor_tex.get_size() * tile_scale
		if tile.x > 0.0 and tile.y > 0.0:
			var y: float = floor_y
			while y < size.y:
				var x: float = 0.0
				while x < size.x:
					draw_texture_rect(floor_tex, Rect2(Vector2(x, y), tile), false)
					x += tile.x
				y += tile.y

	# A thin darker line where the wall meets the floor, so the room reads
	# as having a corner rather than being a flat pattern.
	draw_rect(Rect2(0.0, floor_y - 2.0, size.x, 2.0), Color(0, 0, 0, 0.22))


# A background drawn entirely in code: sky, ground, and some scenery that
# scrolls past at different speeds to give a sense of depth.
func _draw_generated_background() -> void:
	var style: String = str(pack.background.get("style", "yard"))
	if style == "room":
		_draw_room_background()
		return
	var ground_y: float = size.y * (1.0 - float(pack.background.get("ground_ratio", 0.4)))
	var sky_top: Color = pack.background.get("sky_top", Color.SKY_BLUE)
	var sky_bottom: Color = pack.background.get("sky_bottom", Color.WHITE)
	var ground: Color = pack.background.get("ground", Color.GREEN)

	# Sky, painted as a stack of bands from one colour to the other.
	var band: float = ground_y / float(SKY_BANDS)
	for index in SKY_BANDS:
		var mix: float = float(index) / float(SKY_BANDS - 1)
		draw_rect(
			Rect2(0.0, index * band, size.x, band + 1.0),
			sky_top.lerp(sky_bottom, mix)
		)

	_draw_clouds(ground_y)

	draw_rect(Rect2(0.0, ground_y, size.x, size.y - ground_y), ground)
	draw_rect(Rect2(0.0, ground_y, size.x, 2.0), ground.darkened(0.25))

	if style == "park":
		_draw_trees(ground_y)
		if pack.background.has("path"):
			_draw_path(ground_y, pack.background["path"])
	_draw_bushes(ground_y, ground)


# A plain indoor room: a painted wall, a band of skirting along the
# bottom of it, and a floor. No pictures at all, so a room like this costs
# nothing to ship and takes its colours from its scene.json.
func _draw_room_background() -> void:
	var floor_y: float = size.y * (1.0 - float(pack.background.get("floor_ratio", 0.42)))
	var wall: Color = pack.background.get("wall_color", Color(0.91, 0.89, 0.81))
	var wainscot: Color = pack.background.get("wainscot_color", Color(0.33, 0.52, 0.62))
	var floor_colour: Color = pack.background.get("floor_color", Color(0.80, 0.86, 0.85))

	draw_rect(Rect2(0.0, 0.0, size.x, floor_y), wall)

	# The band of skirting, a fifth of the wall, with a lighter rail on top.
	var band: float = floor_y * 0.2
	draw_rect(Rect2(0.0, floor_y - band, size.x, band), wainscot)
	draw_rect(Rect2(0.0, floor_y - band, size.x, maxf(2.0, band * 0.08)), wainscot.lightened(0.3))

	draw_rect(Rect2(0.0, floor_y, size.x, size.y - floor_y), floor_colour)
	draw_rect(Rect2(0.0, floor_y, size.x, 2.0), wainscot.darkened(0.25))

	# Faint seams across the floor, so it reads as a surface rather than a
	# block of colour. Spaced by height, like everything else drawn here.
	var seam: Color = floor_colour.darkened(0.07)
	var spacing: float = size.y * 0.09
	var y: float = floor_y + spacing
	while y < size.y:
		draw_rect(Rect2(0.0, y, size.x, 1.0), seam)
		y += spacing
	var x: float = 0.0
	while x < size.x:
		draw_rect(Rect2(x, floor_y, 1.0, size.y - floor_y), seam)
		x += spacing * 1.6


func _draw_clouds(ground_y: float) -> void:
	var white := Color(1, 1, 1, 0.75)
	var spacing: float = size.y * CLOUD_SPACING
	for index in _layer_range(spacing, CLOUD_PARALLAX):
		var x: float = index * spacing - _scroll * CLOUD_PARALLAX
		var y: float = ground_y * (0.12 + 0.3 * _jitter(index, 1.0))
		var width: float = size.y * (0.07 + 0.045 * _jitter(index, 2.0))
		draw_circle(Vector2(x, y), width * 0.7, white)
		draw_circle(Vector2(x + width * 0.6, y + 3.0), width * 0.55, white)
		draw_circle(Vector2(x - width * 0.6, y + 4.0), width * 0.45, white)


func _draw_trees(ground_y: float) -> void:
	var spacing: float = size.y * TREE_SPACING
	for index in _layer_range(spacing, TREE_PARALLAX):
		var x: float = index * spacing - _scroll * TREE_PARALLAX
		var height: float = size.y * (0.34 + 0.18 * _jitter(index, 3.0))
		var base: float = ground_y + 4.0
		var trunk := Color(0.42, 0.29, 0.18)
		var leaves := Color(0.24, 0.49, 0.25).lightened(0.12 * _jitter(index, 4.0))
		var trunk_width: float = maxf(4.0, height * 0.09)
		draw_rect(
			Rect2(x - trunk_width * 0.5, base - height * 0.45, trunk_width, height * 0.45),
			trunk
		)
		var crown := Vector2(x, base - height * 0.6)
		draw_circle(crown, height * 0.3, leaves)
		draw_circle(crown + Vector2(-height * 0.2, height * 0.1), height * 0.24, leaves)
		draw_circle(crown + Vector2(height * 0.2, height * 0.1), height * 0.24, leaves)


func _draw_path(ground_y: float, colour: Color) -> void:
	var top: float = ground_y + (size.y - ground_y) * 0.45
	draw_rect(Rect2(0.0, top, size.x, size.y - top), colour)
	draw_rect(Rect2(0.0, top, size.x, 2.0), colour.darkened(0.18))
	# Stones scudding past at full speed, which is what makes the ground
	# read as moving rather than the whole picture sliding.
	var stone := colour.darkened(0.12)
	var spacing: float = size.y * STONE_SPACING
	for index in _layer_range(spacing, 1.0):
		var x: float = index * spacing - _scroll
		var y: float = top + (size.y - top) * (0.25 + 0.6 * _jitter(index, 5.0))
		draw_circle(Vector2(x, y), size.y * (0.006 + 0.008 * _jitter(index, 6.0)), stone)


func _draw_bushes(ground_y: float, ground: Color) -> void:
	var bush: Color = ground.darkened(0.22)
	var spacing: float = size.y * BUSH_SPACING
	for index in _layer_range(spacing, 1.0):
		var x: float = index * spacing - _scroll
		var radius: float = size.y * (0.035 + 0.028 * _jitter(index, 7.0))
		var y: float = ground_y + 2.0 + radius * 0.3
		draw_circle(Vector2(x, y), radius, bush)
		draw_circle(Vector2(x + radius * 0.8, y + 2.0), radius * 0.7, bush)


func _draw_props() -> void:
	var toy: Dictionary = pack.prop_with_role(ScenePack.ROLE_TOY)
	for prop in pack.props:
		var texture: Texture2D = _textures.get(str(prop["file"]), null)
		if texture == null:
			continue
		var scale: int = int(prop["scale"])
		var drawn: Vector2 = texture.get_size() * scale
		# x is the middle of the prop, y is the bottom of it, so props sit
		# on the floor instead of floating above it.
		var where := Vector2(
			size.x * float(prop["x"]) - drawn.x * 0.5,
			size.y * float(prop["y"]) - drawn.y
		)
		if not toy.is_empty() and prop == toy:
			if _toy_hidden:
				continue
			where += _toy_offset
		draw_texture_rect(texture, Rect2(where, drawn), false)


# --- Scrolling layers ----------------------------------------------------

# Which copies of a repeating layer are on screen right now. Returning the
# indices rather than positions is what lets a layer scroll forever without
# anything accumulating.
func _layer_range(spacing: float, parallax: float) -> Array[int]:
	var shift: float = _scroll * parallax
	var first: int = int(floor(shift / spacing)) - 1
	var last: int = int(floor((shift + size.x) / spacing)) + 1
	var out: Array[int] = []
	for index in range(first, last + 1):
		out.append(index)
	return out


# A repeatable number between 0 and 1 for a given item, so the scenery looks
# varied but is identical every time it comes round again.
static func _jitter(index: int, salt: float) -> float:
	var value: float = sin(index * 12.9898 + salt * 78.233) * 43758.5453
	return value - floor(value)
