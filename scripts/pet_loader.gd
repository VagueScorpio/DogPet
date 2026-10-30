class_name PetLoader
extends RefCounted
## Turns a PetPack into something that can be put on screen.
##
## The art in assets/ is deliberately not imported by Godot - those folders
## carry a .gdignore - so none of it can be reached with load(). It is all
## read off the disk at runtime instead, which is exactly how it will work
## in the shipped app, where assets/ sits loose beside the .exe and the owner
## can change it without rebuilding anything.
##
## The one exception is the built-in fallback pack inside res://builtin/.
## That one *is* imported, because it is packed into the exe, so it is loaded
## the ordinary way with load(). Both paths end up at the same place.

## Build the 3D model for a pack, already scaled to the right height and
## standing on the floor. Returns null if it could not be loaded.
static func load_model(pack: PetPack) -> Node3D:
	var model: Node3D = _instantiate_model(pack)
	if model == null:
		return null

	# A holder so the normalising shift and scale live somewhere of their
	# own, leaving the model's own transform untouched.
	var holder := Node3D.new()
	holder.name = "Normalised"
	holder.add_child(model)
	normalise(model, holder, pack.target_height)
	return holder


## Scale and shift a loaded model so every dog ends up the same height, with
## its feet on the floor and centred left to right.
##
## Models arrive at wildly different sizes: the pug and the pawsome packs
## differ by roughly 3x before this runs, and a pack someone else makes
## could be anything at all. Measuring the actual geometry is the only
## reliable way to make them agree.
static func normalise(model: Node3D, holder: Node3D, wanted_height: float) -> void:
	var bounds: AABB = combined_aabb(model)
	if bounds.size.y <= 0.0:
		Log.warn("Pet model has no measurable size; leaving it as it came.")
		return
	var fit: Dictionary = PetPack.fit_transform(bounds, wanted_height)
	# The shift is in the model's own units, so it goes on the model and the
	# scale goes on the holder above it.
	model.position = fit["offset"]
	var scale: float = fit["scale"]
	holder.scale = Vector3(scale, scale, scale)


## The box around every mesh in the model, in the model's own space.
static func combined_aabb(root: Node3D) -> AABB:
	var bounds := AABB()
	var found: bool = false
	for mesh in find_mesh_instances(root):
		var local: AABB = mesh.get_aabb()
		var where: Transform3D = relative_transform(mesh, root)
		var piece: AABB = where * local
		if found:
			bounds = bounds.merge(piece)
		else:
			bounds = piece
			found = true
	return bounds


static func find_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root)
	for child in root.get_children():
		found.append_array(find_mesh_instances(child))
	return found


## Where a node sits relative to an ancestor, worked out by walking up the
## chain. Done by hand rather than with global_transform, because the model
## has not been added to the scene tree yet when this runs.
static func relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


## The AnimationPlayer inside a loaded model, if it brought one. Both packs
## that ship with DogPet are static meshes, so this is usually null and the
## procedural motion does all the work.
static func find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found: AnimationPlayer = find_animation_player(child)
		if found != null:
			return found
	return null


# --- 2D sprite packs -----------------------------------------------------

## Slice every sprite sheet in the pack into frames.
##
## Each sheet is one horizontal row of equal-width cells. The cells are not
## copied; each frame is an AtlasTexture pointing at a region of the one
## loaded image, so a four-frame walk costs one texture, not four.
static func build_sprite_frames(pack: PetPack) -> SpriteFrames:
	var frames := SpriteFrames.new()
	# SpriteFrames always starts with a "default" animation we do not want.
	frames.remove_animation("default")

	for state in pack.sprite_animations.keys():
		var spec: Dictionary = pack.sprite_animations[state]
		var texture: ImageTexture = load_texture(pack.dir.path_join(str(spec["file"])))
		if texture == null:
			Log.warn("Could not read %s for the %s animation." % [spec["file"], state])
			continue

		var count: int = int(spec["frames"])
		var frame_width: int = int(spec["frame_width"])
		var frame_height: int = int(spec["frame_height"])

		frames.add_animation(state)
		frames.set_animation_speed(state, float(spec["fps"]))
		frames.set_animation_loop(state, true)
		for index in count:
			var cell := AtlasTexture.new()
			cell.atlas = texture
			cell.region = Rect2(index * frame_width, 0, frame_width, frame_height)
			frames.add_frame(state, cell)

	return frames


## Read a PNG off the disk into a texture. Image.load_from_file works on a
## real path; load() would not, because assets/ is never imported.
##
## The file's header is read before any of it is decoded, so a picture far
## too big to show is refused rather than allocated. See ImageLimits.
static func load_texture(path: String) -> ImageTexture:
	if path.begins_with("res://"):
		var imported: Variant = load(path)
		if imported is Texture2D:
			# Already a texture; wrap its image so callers get one type back.
			return ImageTexture.create_from_image((imported as Texture2D).get_image())
		return null

	var header_size: Vector2i = ImageLimits.png_size_from_header(path)
	if ImageLimits.is_too_large(header_size):
		Log.warn(ImageLimits.describe(path, header_size))
		return null

	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	# A file whose header could not be read gets measured here instead -
	# after decoding, which is the best that can be done for a format this
	# does not know, but it still keeps the enormous one off the screen.
	if ImageLimits.is_too_large(image.get_size()):
		Log.warn(ImageLimits.describe(path, image.get_size()))
		return null
	return ImageTexture.create_from_image(image)


# --- Loading the model itself -------------------------------------------

static func _instantiate_model(pack: PetPack) -> Node3D:
	var path: String = pack.model_path()
	if pack.is_builtin():
		return _instantiate_imported(path)
	return _instantiate_gltf(path)


# The built-in pack lives in res://, so the editor has already imported it
# into a PackedScene and the normal loader works.
static func _instantiate_imported(path: String) -> Node3D:
	var packed: Variant = load(path)
	if not packed is PackedScene:
		Log.error("The built-in pet at %s is not a scene." % path)
		return null
	var node: Node = (packed as PackedScene).instantiate()
	if node is Node3D:
		return node
	Log.error("The built-in pet at %s is not 3D." % path)
	return null


# Everything in assets/ is read at runtime, so a .glb there has to be parsed
# by hand rather than loaded as a resource.
static func _instantiate_gltf(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		Log.error("No model file at %s" % path)
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error: int = document.append_from_file(path, state)
	if error != OK:
		Log.error("Could not read the model %s (error %d)." % [path, error])
		return null
	var scene: Node = document.generate_scene(state)
	if scene == null:
		Log.error("The model %s produced nothing to show." % path)
		return null
	if scene is Node3D:
		return scene
	scene.queue_free()
	Log.error("The model %s is not 3D." % path)
	return null
