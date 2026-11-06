extends SceneTree
## RT probe P4: PackInstall, end to end, with answers the wizard can produce.
##
## Everything is written into Godot's user data folder; the project's assets
## folder is never touched.

const Builder := preload("res://scripts/pack_builder.gd")
const Install := preload("res://scripts/pack_install.gd")

var dir: String = ""
var out: String = ""


func _init() -> void:
	dir = OS.get_user_data_dir().path_join("rt_p4")
	out = dir.path_join("installed")
	DirAccess.make_dir_recursive_absolute(dir)
	_recount_overshoot()
	_name_collision()
	_manifest_traversal()
	_stage_name_in_file_name()
	quit(0)


func listing(folder: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var access: DirAccess = DirAccess.open(folder)
	if access == null:
		return found
	access.list_dir_begin()
	var name: String = access.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			found.append(name)
		name = access.get_next()
	access.list_dir_end()
	found.sort()
	return found


func fresh(name: String) -> String:
	var target: String = out.path_join(name)
	if DirAccess.dir_exists_absolute(target):
		PackArchive.empty_folder(target)
	DirAccess.make_dir_recursive_absolute(target)
	return target


# A small picture, told in the wizard that it holds 64 frames. The SpinBox
# allows 1..64 for any single-file piece, so this is three keystrokes away.
func _recount_overshoot() -> void:
	print("[1] a 30x30 picture asked for 64 frames")
	var image: Image = Image.create(30, 30, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for y in range(6, 24):
		for x in range(6, 24):
			image.set_pixel(x, y, Color.SADDLE_BROWN)
	var path: String = dir.path_join("small.png")
	image.save_png(path)

	var found: Dictionary = SheetPlan.read(PackedStringArray([path]))
	var piece: Dictionary = (found["pieces"] as Array)[0]
	var asked: Dictionary = SheetPlan.recount(piece, 64)
	print("    recounted to %d frames, cell size %s" % [
		int(asked["frames"]), str(asked["size"]),
	])

	var answers: Dictionary = {
		"id": "overshoot", "name": "Overshoot", "credit_not_required": true,
		"pixel_art": true, "display_height_px": 160, "faces": "right",
		"sheets": [{
			"cut": asked["cut"], "state": "idle", "stage": "",
			"frames": int(asked["frames"]), "fps": 6.0,
		}],
	}
	var problems: PackedStringArray = Install.check(Builder.Kind.PET_SPRITE, answers)
	print("    PackInstall.check says: %s" % (
		"nothing wrong" if problems.is_empty() else str(problems)
	))

	var target: String = fresh("overshoot")
	var plan: Dictionary = Install.plan(Builder.Kind.PET_SPRITE, answers, target)
	var wrote: PackedStringArray = Install.write(plan)
	print("    PackInstall.write says: %s" % str(wrote))
	print("    the folder now holds: %s" % str(listing(target)))
	var pack: PetPack = PetPack.load_from_dir(target)
	print("    PetPack reads it back: usable=%s problems=%s" % [
		str(pack != null and pack.is_usable()),
		str(pack.problems if pack != null else PackedStringArray()),
	])


# A cut strip is named after its job - idle.png - while a copied file keeps
# its own name. A chosen file literally called idle.png collides with it.
func _name_collision() -> void:
	print("[2] a chosen file called idle.png beside a cut strip given the idle job")
	var walk: Image = Image.create(96, 32, false, Image.FORMAT_RGBA8)
	walk.fill(Color.WHITE)
	for index in 3:
		for y in range(8, 28):
			for x in range(index * 32 + 6, index * 32 + 26):
				walk.set_pixel(x, y, Color.SADDLE_BROWN)
	var walk_path: String = dir.path_join("walkstrip.png")
	walk.save_png(walk_path)

	var idle: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	idle.fill(Color(0, 0, 0, 0))
	for y in range(8, 28):
		for x in range(6, 26):
			idle.set_pixel(x, y, Color.DARK_GREEN)
	var idle_path: String = dir.path_join("idle.png")
	idle.save_png(idle_path)

	var found: Dictionary = SheetPlan.read(PackedStringArray([walk_path]))
	var strip: Dictionary = (found["pieces"] as Array)[0]

	var answers: Dictionary = {
		"id": "collide", "name": "Collide", "credit_not_required": true,
		"pixel_art": true, "display_height_px": 160, "faces": "right",
		"sheets": [
			# The cut strip, given the idle job: it will be written as idle.png.
			{
				"cut": strip["cut"], "state": "idle", "stage": "",
				"frames": int(strip["frames"]), "fps": 6.0,
			},
			# A plain file that is already called idle.png, given the walk job.
			{"path": idle_path, "state": "walk", "stage": "", "frames": 1, "fps": 1.0},
		],
	}
	var problems: PackedStringArray = Install.check(Builder.Kind.PET_SPRITE, answers)
	print("    check says: %s" % (
		"nothing wrong" if problems.is_empty() else str(problems)
	))
	var target: String = fresh("collide")
	var plan: Dictionary = Install.plan(Builder.Kind.PET_SPRITE, answers, target)
	print("    copies: %s" % str(plan["copies"]))
	print("    cuts:   %s" % str((plan["cuts"] as Dictionary).keys()))
	print("    manifest animations: %s" % str((plan["manifest"] as Dictionary)["animations"]))
	var wrote: PackedStringArray = Install.write(plan)
	print("    write says: %s" % str(wrote))
	print("    folder holds: %s" % str(listing(target)))
	var pack: PetPack = PetPack.load_from_dir(target)
	if pack != null:
		print("    read back: usable=%s problems=%s" % [
			str(pack.is_usable()), str(pack.problems),
		])
		for state in ["idle", "walk"]:
			var spec: Dictionary = pack.sprite_animations.get(state, {})
			print("      %s -> file %s, %d frames, %dx%d" % [
				state, str(spec.get("file", "-")), int(spec.get("frames", 0)),
				int(spec.get("frame_width", 0)), int(spec.get("frame_height", 0)),
			])


# A pet.json that names a file outside its own folder. Nothing in the zip is
# unsafe; the manifest is.
func _manifest_traversal() -> void:
	print("[3] a hand-written pet.json whose file field climbs out of the pack")
	var outside: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	outside.fill(Color.MAGENTA)
	outside.save_png(dir.path_join("secret.png"))

	var target: String = fresh("escape")
	var manifest: Dictionary = {
		"format_version": 1, "id": "escape", "name": "Escape",
		"kind": "sprite2d", "pixel_art": true, "display_height_px": 160,
		"faces": "right", "credit": "nobody",
		"animations": {"idle": {"file": "../../secret.png", "frames": 1, "fps": 1}},
	}
	var file: FileAccess = FileAccess.open(target.path_join("pet.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()
	var pack: PetPack = PetPack.load_from_dir(target)
	print("    PetPack: usable=%s problems=%s" % [
		str(pack != null and pack.is_usable()),
		str(pack.problems if pack != null else PackedStringArray()),
	])
	if pack != null and pack.sprite_animations.has("idle"):
		print("    *** idle resolved to a file outside the pack: %s ***"
			% str(pack.sprite_animations["idle"]["file"]))

	print("[3b] the same with a drive-absolute path")
	var target2: String = fresh("escape2")
	manifest["animations"] = {
		"idle": {"file": dir.path_join("secret.png"), "frames": 1, "fps": 1},
	}
	var file2: FileAccess = FileAccess.open(target2.path_join("pet.json"), FileAccess.WRITE)
	file2.store_string(JSON.stringify(manifest, "  "))
	file2.close()
	var pack2: PetPack = PetPack.load_from_dir(target2)
	print("    PetPack: usable=%s problems=%s" % [
		str(pack2 != null and pack2.is_usable()),
		str(pack2.problems if pack2 != null else PackedStringArray()),
	])


# The stage a piece carries goes straight into a file name. Where does it come
# from, and what happens if it is not one of the known names?
func _stage_name_in_file_name() -> void:
	print("[4] a sheet entry whose stage is not a known stage name")
	var image: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(8, 28):
		for x in range(6, 26):
			image.set_pixel(x, y, Color.DARK_GREEN)
	var path: String = dir.path_join("stage_src.png")
	image.save_png(path)

	for stage in ["puppy", "../../../oops", "con", "a b/c"]:
		var answers: Dictionary = {
			"id": "stages", "name": "Stages", "credit_not_required": true,
			"pixel_art": true, "display_height_px": 160, "faces": "right",
			"sheets": [{
				"cut": {
					"paths": PackedStringArray([path]),
					"rects": [Rect2i(0, 0, 32, 32)] as Array[Rect2i],
					"key": false, "align": false,
				},
				"state": "idle", "stage": stage, "frames": 1, "fps": 1.0,
			}],
		}
		var plan: Dictionary = Install.plan(
			Builder.Kind.PET_SPRITE, answers, fresh("stage_test")
		)
		print("    stage %s -> cut file name %s" % [
			stage, str((plan["cuts"] as Dictionary).keys()),
		])
