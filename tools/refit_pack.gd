extends SceneTree
## Repairing a sprite pack that was installed by an older DogPet.
##
##   godot --headless --path . --script res://tools/refit_pack.gd -- \
##       --pack assets/pets/<id> [--unkey] [--dry]
##
## Two things the import wizard got wrong before v1.46, both of which can be
## put right on the installed files:
##
## --unkey   Puts back the pixels the old keying cleared from inside the
##           art. It used to clear every pixel of the page's colour wherever
##           it sat, so a dog drawn in the colour of its own page came out as
##           a hollow outline. Only the alpha was thrown away - the colours
##           are all still there underneath - so anything cleared that the
##           border cannot reach gets its alpha back. Run it only on a pack
##           damaged that way: on a healthy pack it would fill in holes the
##           artist meant to be holes.
##
## (always) Every frame is trimmed to what is drawn on it and stood in one
##           place: on the bottom of the cell, centred across it. Frames left
##           where the artist happened to draw them put the dog in a
##           different spot on every frame, which is what sent the owner's
##           raccoon off the side of the window.
##
## The originals are copied to assets/_backup/<id>-<timestamp>/ first, the
## same place the wizard puts a pack it replaces.

const BACKUP := "assets/_backup"


func _initialize() -> void:
	var options: Dictionary = _arguments()
	var folder: String = str(options.get("pack", ""))
	if folder.is_empty():
		print("usage: --pack assets/pets/<id> [--unkey] [--dry]")
		quit(1)
		return

	var pack: PetPack = PetPack.load_from_dir(folder)
	if pack.kind != PetPack.KIND_SPRITE2D:
		print("%s is not a sprite pack." % folder)
		quit(1)
		return
	if not pack.is_valid():
		print("%s cannot be read: %s" % [folder, ", ".join(pack.problems)])
		quit(1)
		return

	var dry: bool = options.has("dry")
	var sheets: Dictionary = _sheets_of(pack)
	print("%s: %d sheet%s" % [pack.id, sheets.size(), "" if sheets.size() == 1 else "s"])
	if not dry and not _backed_up(pack, sheets.keys()):
		quit(1)
		return

	for file in sheets:
		_refit(folder.path_join(file), int(sheets[file]), options.has("unkey"), dry)
	if dry:
		print("(nothing was written)")
	quit()


# file name -> how many frames the manifest says are in it. A pack whose art
# ages has several files for one state, and every one of them needs doing.
func _sheets_of(pack: PetPack) -> Dictionary:
	var found: Dictionary = {}
	for state in pack.sprite_animations:
		found[str(pack.sprite_animations[state]["file"])] = int(
			pack.sprite_animations[state]["frames"]
		)
	for state in pack.sprite_stages:
		for spec in pack.sprite_stages[state]:
			found[str(spec["file"])] = int(spec["frames"])
	return found


func _refit(path: String, frames: int, unkey: bool, dry: bool) -> void:
	var before: Vector2i = ImageLimits.png_size_from_header(path)
	if before.x <= 0:
		print("  %s could not be read" % path.get_file())
		return

	if unkey:
		var image: Image = Image.load_from_file(path)
		if image == null:
			print("  %s could not be read" % path.get_file())
			return
		var back: int = SheetKey.restore_enclosed(image)
		print("  %s: %d pixel%s put back" % [
			path.get_file(), back, "" if back == 1 else "s",
		])
		if back > 0 and not dry:
			image.save_png(path)

	# Through the cutter, so the repaired pack is laid out by exactly the
	# same code as a freshly imported one.
	var width: int = before.x / maxi(1, frames)
	var paths := PackedStringArray()
	var rects: Array[Rect2i] = []
	for index in frames:
		paths.append(path)
		rects.append(Rect2i(index * width, 0, width, before.y))
	var strip: Image = SheetCutter.render({"paths": paths, "rects": rects, "key": false})
	if strip == null:
		print("  %s could not be re-cut" % path.get_file())
		return
	print("  %s: %dx%d -> %dx%d" % [
		path.get_file(), before.x, before.y, strip.get_width(), strip.get_height(),
	])
	if not dry:
		strip.save_png(path)


# The pack's pictures copied aside before anything is written over them.
func _backed_up(pack: PetPack, files: Array) -> bool:
	var into: String = BACKUP.path_join("%s-%d" % [pack.id, Time.get_unix_time_from_system()])
	if DirAccess.make_dir_recursive_absolute(into) != OK:
		print("could not make %s; nothing was changed." % into)
		return false
	for file in files:
		var from: String = pack.dir.path_join(str(file))
		if DirAccess.copy_absolute(from, into.path_join(str(file))) != OK:
			print("could not copy %s; nothing was changed." % from)
			return false
	print("originals copied to %s" % into)
	return true


func _arguments() -> Dictionary:
	var options: Dictionary = {}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < args.size():
		var word: String = args[index]
		if not word.begins_with("--"):
			index += 1
			continue
		var name: String = word.substr(2)
		var value: String = ""
		if index + 1 < args.size() and not args[index + 1].begins_with("--"):
			value = args[index + 1]
			index += 1
		options[name] = value
		index += 1
	return options
