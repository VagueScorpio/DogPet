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

## The backgrounds drawn from colours rather than pictures - the yard, the
## park and the plain indoor room - live in ScenePainter, along with the
## sizes and parallax of their scenery. What is left here is the room's own
## job: loading its pictures, drawing them and its props, and scrolling.

## The most tiles either axis will ever be covered with.
##
## ScenePack raises a room's tile_scale when its tiles are tiny, which handles
## every case where the size could be read from the file's header. This is the
## backstop for the case it cannot: a picture that is not a PNG, whose size is
## only known once it has been decoded into a texture. Past this the tile is
## stretched instead, which looks wrong and keeps the window alive - and
## ScenePack will have said something in the log.
const MAX_TILES_PER_AXIS := 256

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
			ScenePainter.draw_background(self, pack, _scroll)
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
		var tile: Vector2 = _tile_step(wall.get_size() * tile_scale, Vector2(size.x, floor_y))
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
		var tile: Vector2 = _tile_step(
			floor_tex.get_size() * tile_scale, Vector2(size.x, size.y - floor_y)
		)
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


# The step to actually tile with: the tile's own size, unless that would mean
# covering the area with more than MAX_TILES_PER_AXIS of them, in which case it
# is grown until it would not. Stretched pixel art looks wrong; a window that
# has stopped responding is worse, and the owner cannot reach Settings to pick
# another room from inside a frozen one.
func _tile_step(tile: Vector2, area: Vector2) -> Vector2:
	if tile.x <= 0.0 or tile.y <= 0.0:
		return tile
	var grow: float = maxf(
		area.x / (tile.x * MAX_TILES_PER_AXIS),
		area.y / (tile.y * MAX_TILES_PER_AXIS)
	)
	if grow <= 1.0:
		return tile
	return tile * ceil(grow)


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
