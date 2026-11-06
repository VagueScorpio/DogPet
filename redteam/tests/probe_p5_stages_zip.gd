extends SceneTree
## RT probe P5: does an unchecked stage name really write outside the pack,
## and does a life-stage pack survive a zip round trip?

const Builder := preload("res://scripts/pack_builder.gd")
const Install := preload("res://scripts/pack_install.gd")

var dir: String = ""


func _init() -> void:
	dir = OS.get_user_data_dir().path_join("rt_p5")
	DirAccess.make_dir_recursive_absolute(dir)
	_escape_write()
	_stage_round_trip()
	_stage_bounds()
	quit(0)


func fresh(name: String) -> String:
	var target: String = dir.path_join(name)
	if DirAccess.dir_exists_absolute(target):
		PackArchive.empty_folder(target)
	DirAccess.make_dir_recursive_absolute(target)
	return target


func a_dog(wide: int, high: int) -> Image:
	var image: Image = Image.create(wide, high, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(high / 4, high - 2):
		for x in range(2, wide - 2):
			image.set_pixel(x, y, Color.SADDLE_BROWN)
	return image


# The stage name is pasted into a file name with no sanitising. Does the write
# actually land outside the pack folder? Aimed at a harmless scratch folder.
func _escape_write() -> void:
	print("[1] does an unsanitised stage name escape the pack folder?")
	var sandbox: String = fresh("sandbox")
	var nested: String = sandbox.path_join("a/b/pack")
	DirAccess.make_dir_recursive_absolute(nested)
	var source: String = dir.path_join("dog.png")
	a_dog(32, 32).save_png(source)

	var answers: Dictionary = {
		"id": "pack", "name": "Pack", "credit_not_required": true,
		"pixel_art": true, "display_height_px": 160, "faces": "right",
		"sheets": [{
			"cut": {
				"paths": PackedStringArray([source]),
				"rects": [Rect2i(0, 0, 32, 32)] as Array[Rect2i],
				"key": false, "align": false,
			},
			"state": "idle", "stage": "../../../../../../escaped", "frames": 1, "fps": 1.0,
		}],
	}
	var plan: Dictionary = Install.plan(Builder.Kind.PET_SPRITE, answers, nested)
	print("    cut target: %s" % str((plan["cuts"] as Dictionary).keys()))
	var problems: PackedStringArray = Install.write(plan)
	print("    write says: %s" % str(problems))
	var landed: String = sandbox.path_join("a/idle_../../../../../../escaped.png")
	var escaped: String = sandbox.path_join("idle_escaped.png")
	print("    file exists two folders up (%s): %s" % [
		escaped.get_file(), str(FileAccess.file_exists(escaped)),
	])
	print("    anything at all in the sandbox root: %s" % str(_listing(sandbox)))
	print("    inside the pack folder: %s" % str(_listing(nested)))
	if not FileAccess.file_exists(landed):
		pass


# A life-stage pack written by the installer, exported and imported again.
func _stage_round_trip() -> void:
	print("[2] a four-stage pack through export and import")
	var source_dir: String = fresh("stage_src")
	var sizes: Array[int] = [18, 26, 34, 34]
	var paths: PackedStringArray = []
	for index in sizes.size():
		var path: String = source_dir.path_join("age_%d.png" % index)
		a_dog(sizes[index], sizes[index]).save_png(path)
		paths.append(path)

	var sheets: Array = []
	var names: PackedStringArray = LifeStages.names_for(4, false)
	for index in paths.size():
		sheets.append({
			"cut": {
				"paths": PackedStringArray([paths[index]]),
				"rects": [Rect2i(0, 0, sizes[index], sizes[index])] as Array[Rect2i],
				"key": false, "align": false,
			},
			"state": "idle", "stage": names[index], "frames": 1, "fps": 1.0,
		})
	var answers: Dictionary = {
		"id": "ages", "name": "Ages", "credit_not_required": true,
		"pixel_art": true, "display_height_px": 160, "faces": "right",
		"sheets": sheets,
	}
	var problems: PackedStringArray = Install.check(Builder.Kind.PET_SPRITE, answers)
	print("    check: %s" % ("nothing wrong" if problems.is_empty() else str(problems)))
	var target: String = fresh("ages")
	var wrote: PackedStringArray = Install.write(
		Install.plan(Builder.Kind.PET_SPRITE, answers, target)
	)
	print("    write: %s" % str(wrote))
	print("    folder: %s" % str(_listing(target)))

	var pack: PetPack = PetPack.load_from_dir(target)
	print("    read back: usable=%s stage_count=%d problems=%s" % [
		str(pack.is_usable()), pack.stage_count(), str(pack.problems),
	])

	var zip: String = dir.path_join("ages.zip")
	var exported: PackedStringArray = PackArchive.write_pack(target, zip, "nobody")
	print("    export: %s" % ("ok" if exported.is_empty() else str(exported)))
	var looked: Dictionary = PackArchive.inspect(zip)
	print("    inspect: kind=%d id=%s problems=%s" % [
		int(looked["kind"]), str(looked["id"]), str(looked["problems"]),
	])
	var back: String = fresh("ages_back")
	var pulled: PackedStringArray = PackArchive.extract(zip, str(looked["root"]), back)
	print("    extract: %s -> %s" % [str(pulled), str(_listing(back))])
	var again: PetPack = PetPack.load_from_dir(back)
	print("    re-read: usable=%s stage_count=%d problems=%s" % [
		str(again.is_usable()), again.stage_count(), str(again.problems),
	])
	for age in [0.0, 1.0, 5.0, 20.0, 100.0, 1e9, -5.0]:
		var spec: Dictionary = again.sprite_for("idle", age)
		print("      at %.1f days -> %s" % [age, str(spec.get("file", "NOTHING"))])


# A pack whose stages list is longer or shorter than anything sane.
func _stage_bounds() -> void:
	print("[3] a pet.json with a malformed stages list")
	var target: String = fresh("odd_stages")
	a_dog(32, 32).save_png(target.path_join("idle.png"))
	var cases: Dictionary = {
		"empty list": [],
		"nine stages": _repeat({"file": "idle.png", "frames": 1, "fps": 1}, 9),
		"a string in the list": ["idle.png"],
		"null in the list": [null],
		"negative frames": [{"file": "idle.png", "frames": -4, "fps": 1}],
		"stages not a list": "idle.png",
	}
	for label in cases:
		var manifest: Dictionary = {
			"format_version": 1, "id": "odd", "name": "Odd", "kind": "sprite2d",
			"pixel_art": true, "display_height_px": 160, "faces": "right",
			"credit": "nobody",
			"animations": {"idle": {"stages": cases[label]}},
		}
		var file: FileAccess = FileAccess.open(
			target.path_join("pet.json"), FileAccess.WRITE
		)
		file.store_string(JSON.stringify(manifest))
		file.close()
		var pack: PetPack = PetPack.load_from_dir(target)
		print("    %-22s -> usable=%s problems=%s" % [
			label, str(pack != null and pack.is_usable()),
			str(pack.problems if pack != null else PackedStringArray()),
		])


func _repeat(what: Variant, times: int) -> Array:
	var out: Array = []
	for _index in times:
		out.append(what)
	return out


func _listing(folder: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var access: DirAccess = DirAccess.open(folder)
	if access == null:
		return found
	access.list_dir_begin()
	var name: String = access.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			found.append(name + ("/" if access.current_is_dir() else ""))
		name = access.get_next()
	access.list_dir_end()
	found.sort()
	return found
