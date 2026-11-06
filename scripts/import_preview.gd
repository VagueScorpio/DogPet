class_name ImportPreview
extends Control
## The picture at the top of the import wizard: what is about to be installed.
##
## It earns its keep on the one question nothing can answer for the owner.
## DogPet measures a model and scales it, but it cannot know which way the
## dog was built facing - the shipped pug is 29 degrees off - so the wizard
## asks, and this shows the answer as it is dragged.
##
## For drawn art it shows the strips that are about to be written, not the
## files they were cut from: see CutPreview for why those are different
## pictures. The chosen files themselves are still shown while the wizard is
## only asking what they are, before there is a cut to draw.
##
## Everything here is drawn over a checkerboard, as a paint program does.
## Transparency against a dark panel looks like a dark drawing, and "the dog
## came out hollow" is the one fault this preview exists to catch. *(v1.47)*

const HEIGHT := 190.0

## One strip's height on screen, and the size of one square of the
## checkerboard behind it.
const STRIP_HEIGHT := 64.0
const CHECK := 8

var _world: SubViewport = null
var _holder: Node3D = null
var _facing: Node3D = null
var _row: HBoxContainer = null
var _checks: ImageTexture = null


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	clip_contents = true


## Show a 3D model, straight from wherever the owner keeps it. Returns false
## if it could not be read, which is worth saying out loud.
func show_model(path: String, height: float, degrees: float) -> bool:
	_clear()
	var pack: PetPack = PetPack.from_dictionary({
		"id": "preview", "kind": PetPack.KIND_MODEL3D,
		"model": path.get_file(), "target_height": height,
	}, path.get_base_dir())
	# The stage is built before the model is read, so a model that cannot be
	# read leaves an empty stage rather than a half-built one.
	_build_world()
	# Loaded from wherever the owner keeps it, not from the pack: there is no
	# pack yet, and this is how we find out whether there ever can be.
	var model: Node3D = PetLoader.load_model(pack)
	if model == null:
		return false
	_holder = model
	_facing.add_child(_holder)
	_facing.rotation_degrees.y = degrees
	return true


## Turn the model, without loading it again.
func set_facing(degrees: float) -> void:
	if _facing != null:
		_facing.rotation_degrees.y = degrees


## Re-measure the model against a new wanted height.
func set_height(height: float) -> void:
	if _holder == null or _holder.get_child_count() == 0:
		return
	var model: Node3D = _holder.get_child(0)
	PetLoader.normalise(model, _holder, height)


## Show the chosen pictures side by side, unscaled and unsmoothed.
func show_pictures(paths: PackedStringArray) -> void:
	_clear()
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_row)
	for path in paths:
		var texture: ImageTexture = PetLoader.load_texture(path)
		if texture == null:
			continue
		var frame := TextureRect.new()
		frame.texture = texture
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.custom_minimum_size = Vector2(0, HEIGHT - 20.0)
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_row.add_child(frame)


## Show the strips that are about to be installed, one per row, each with
## the job it has been given written above it.
##
## "strips" is what CutPreview.of_sheets hands back. They are listed down the
## panel rather than across it because a strip is a wide, short picture: side
## by side, six frames of dog would be a few pixels each and the owner could
## not see what they were being shown. More than fits is scrolled to.
func show_strips(strips: Array) -> void:
	_clear()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	for entry in strips:
		var strip: Dictionary = entry
		column.add_child(UiBits.dim(str(strip["label"]), 11, 0.0, false))
		column.add_child(_over_checks(strip["image"]))


func clear() -> void:
	_clear()


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_world = null
	_holder = null
	_facing = null
	_row = null


# One strip, laid over a checkerboard so that a cleared pixel reads as
# cleared whatever colour the art is.
func _over_checks(image: Image) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(0, STRIP_HEIGHT)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.clip_contents = true

	var behind := TextureRect.new()
	behind.texture = _checkerboard()
	behind.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	behind.stretch_mode = TextureRect.STRETCH_TILE
	behind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(behind)
	behind.set_anchors_preset(Control.PRESET_FULL_RECT)

	var front := TextureRect.new()
	front.texture = ImageTexture.create_from_image(image)
	front.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	front.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	front.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(front)
	front.set_anchors_preset(Control.PRESET_FULL_RECT)
	return box


# Built once and kept: two greys in a 2x2 of squares, tiled.
func _checkerboard() -> ImageTexture:
	if _checks != null:
		return _checks
	var tile: Image = Image.create(CHECK * 2, CHECK * 2, false, Image.FORMAT_RGBA8)
	tile.fill(Color(0.20, 0.21, 0.25))
	tile.fill_rect(Rect2i(0, 0, CHECK, CHECK), Color(0.30, 0.31, 0.36))
	tile.fill_rect(Rect2i(CHECK, CHECK, CHECK, CHECK), Color(0.30, 0.31, 0.36))
	_checks = ImageTexture.create_from_image(tile)
	return _checks


# The same arrangement PetView uses: a transparent viewport so the dog can
# stand in front of whatever is behind it, seen slightly from above.
func _build_world() -> void:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_world = SubViewport.new()
	_world.transparent_bg = true
	_world.own_world_3d = true
	_world.size = Vector2i(maxi(1, int(size.x)), int(HEIGHT))
	box.add_child(_world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.64, 0.66, 0.74)
	environment.ambient_light_energy = 0.65
	var world := WorldEnvironment.new()
	world.environment = environment
	_world.add_child(world)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.85, 2.2)
	camera.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	camera.fov = 40.0
	_world.add_child(camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	key.light_energy = 1.1
	_world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 145.0, 0.0)
	_world.add_child(fill)

	_facing = Node3D.new()
	_world.add_child(_facing)
