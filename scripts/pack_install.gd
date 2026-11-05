class_name PackInstall
extends RefCounted
## Checking the wizard answers over, then writing the pack into assets/.
##
## PackBuilder decides what the manifest should say. This decides what lands
## on the disk: which file is copied where, under what name, and whether the
## answers hold together well enough to copy anything at all.
##
## Split from PackBuilder because this half touches files and that half does
## not. Both are free of nodes and autoloads, so the tests drive them
## directly - a folder of real PNGs in, a real pack folder out, read back
## with PetPack.load_from_dir to prove the app can use what was written.

# Reached by preload rather than by its class_name, like ZipSizes in
# PackArchive: a script added in the same change is not in the editor class
# cache yet, and a --script test run would not compile at all.
const Builder := preload("res://scripts/pack_builder.gd")


## Everything wrong with these answers, in plain English. Empty means the
## pack can be written.
##
## Checked here rather than left to PetPack: the owner should hear "that
## sheet is 45 wide, which does not divide into 4 frames" while the number
## is still on screen and editable, not after the pack is installed and the
## pet silently fails to appear.
static func check(kind: int, answers: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	if str(answers.get("id", "")).is_empty():
		problems.append("the pack needs a folder name")
	if str(answers.get("name", "")).strip_edges().is_empty():
		problems.append("the pack needs a name to show in the list")

	match kind:
		Builder.Kind.PET_MODEL:
			_check_model(answers, problems)
		Builder.Kind.PET_SPRITE:
			_check_sprites(answers, problems)
		Builder.Kind.ROOM:
			_check_room(answers, problems)
		_:
			problems.append("there is nothing here to install")
	return problems


## What is worth saying before installing, without standing in the way.
##
## A pack with no credit line installs perfectly well and then shows up in
## the app as a pack with a problem, because PetPack treats a missing credit
## as one - some of the art DogPet ships with is licensed on condition that
## the credit stays visible. Saying so here, while the field is still on
## screen, is kinder than letting it be discovered later.
##
## Unless the pack is the owner's own art and says so, which is the case
## that rule was never written for. Then there is nothing to say.
static func warnings(kind: int, answers: Dictionary) -> PackedStringArray:
	var notes: PackedStringArray = []
	if (
		str(answers.get("credit", "")).strip_edges().is_empty()
		and not bool(answers.get("credit_not_required", false))
	):
		notes.append(
			"No credit line. Some art may only be used while its credit stays visible,"
			+ " so DogPet will list this pack as having a problem until one is given."
		)
	if kind == Builder.Kind.PET_MODEL and str(answers.get("model", "")).get_extension()\
			.to_lower() == "gltf":
		notes.append(
			"A .gltf keeps its geometry and textures in separate files. Choose those files"
			+ " too, or use a .glb, which holds everything in one."
		)
	return notes


static func _check_model(answers: Dictionary, problems: PackedStringArray) -> void:
	var model: String = str(answers.get("model", ""))
	if model.is_empty() or not FileAccess.file_exists(model):
		problems.append("the model file could not be found any more")
	if float(answers.get("target_height", 1.0)) <= 0.0:
		problems.append("the height has to be more than zero")


static func _check_sprites(answers: Dictionary, problems: PackedStringArray) -> void:
	var sheets: Array = answers.get("sheets", [])
	var states: PackedStringArray = []
	for entry in sheets:
		var sheet: Dictionary = entry
		var path: String = str(sheet.get("path", ""))
		var state: String = str(sheet.get("state", ""))
		if state.is_empty():
			continue
		if states.has(state):
			problems.append("two pictures are both set to %s; pick one each" % state)
			continue
		states.append(state)
		if not FileAccess.file_exists(path):
			problems.append("%s could not be found any more" % path.get_file())
			continue
		var trouble: String = Builder.sheet_problem(
			path, ImageLimits.png_size_from_header(path), int(sheet.get("frames", 1))
		)
		if not trouble.is_empty():
			problems.append(trouble)
	if states.is_empty():
		problems.append("none of the pictures has been given a job yet")
	elif not states.has("idle"):
		# Without idle the dog has no art for standing still, which is most
		# of its life. PetPack falls everything else back to idle.
		problems.append("one of the pictures has to be the idle one")


static func _check_room(answers: Dictionary, problems: PackedStringArray) -> void:
	if not ScenePack.ROLES.has(str(answers.get("role", ""))):
		problems.append("the room needs to say which slot it fills")
	var background: String = str(answers.get("background", ""))
	# A drawn background needs no pictures, so there is nothing to check.
	var wanted: PackedStringArray = PackedStringArray()
	if background == Builder.BG_TILED:
		wanted = ["wall", "floor"]
	elif background == Builder.BG_IMAGE:
		wanted = ["image"]
	for key in wanted:
		var path: String = str(answers.get(key, ""))
		if path.is_empty():
			problems.append("the %s picture has not been chosen" % key)
		elif not FileAccess.file_exists(path):
			problems.append("the %s picture could not be found any more" % key)
		elif ImageLimits.is_too_large(ImageLimits.png_size_from_header(path)):
			problems.append("the %s picture is larger than this app will load" % key)
	for entry in answers.get("props", []):
		var path: String = str((entry as Dictionary).get("path", ""))
		if not FileAccess.file_exists(path):
			problems.append("the prop %s could not be found any more" % path.get_file())


## What will be copied where, and what the manifest will say.
##
## Returns {"target", "manifest_name", "manifest", "copies"}, where copies
## maps the name a file will have inside the pack to where it is being copied
## from. The manifest is built from those inside-the-pack names, so the pack
## never refers to anything outside its own folder.
static func plan(kind: int, answers: Dictionary, target: String) -> Dictionary:
	var copies: Dictionary = {}
	var local: Dictionary = answers.duplicate(true)

	match kind:
		Builder.Kind.PET_MODEL:
			# Models keep their own file names. A .gltf refers to its .bin and
			# its textures by name, so renaming them would break the model in
			# a way nothing here could see.
			local["model"] = _take(copies, str(answers.get("model", "")), true)
			for extra in answers.get("extras", []):
				_take(copies, str(extra), true)
			local.erase("extras")
		Builder.Kind.PET_SPRITE:
			var sheets: Array = []
			for entry in answers.get("sheets", []):
				var sheet: Dictionary = (entry as Dictionary).duplicate()
				if str(sheet.get("state", "")).is_empty():
					continue
				sheet["file"] = _take(copies, str(sheet.get("path", "")), false)
				sheet.erase("path")
				sheets.append(sheet)
			local["sheets"] = sheets
		Builder.Kind.ROOM:
			for key in ["image", "wall", "floor"]:
				if not str(answers.get(key, "")).is_empty():
					local[key] = _take(copies, str(answers[key]), false)
			var props: Array = []
			for entry in answers.get("props", []):
				var prop: Dictionary = (entry as Dictionary).duplicate()
				prop["file"] = _take(copies, str(prop.get("path", "")), false)
				prop.erase("path")
				props.append(prop)
			local["props"] = props

	return {
		"target": target,
		"manifest_name": Builder.manifest_name(kind),
		"manifest": Builder.manifest_for(kind, local),
		"copies": copies,
	}


## Carry out a plan. Returns the problems; empty means it all landed.
static func write(plan_data: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	var target: String = str(plan_data["target"])
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		problems.append("could not make the folder %s" % target)
		return problems

	var copies: Dictionary = plan_data["copies"]
	for name in copies:
		var from: String = str(copies[name])
		if not FileAccess.file_exists(from):
			problems.append("%s could not be found any more" % from.get_file())
			continue
		if DirAccess.copy_absolute(from, target.path_join(name)) != OK:
			problems.append("could not copy %s into the pack" % name)

	var manifest: String = Builder.manifest_text(plan_data["manifest"])
	var file: FileAccess = FileAccess.open(
		target.path_join(str(plan_data["manifest_name"])), FileAccess.WRITE
	)
	if file == null:
		problems.append("could not write %s" % str(plan_data["manifest_name"]))
		return problems
	file.store_string(manifest)
	file.close()
	return problems


# Register one file to copy and answer with the name it will have inside the
# pack. Two files called idle.png from different folders would otherwise
# overwrite each other, so the second one becomes idle_2.png.
static func _take(copies: Dictionary, source: String, keep_name: bool) -> String:
	if source.is_empty():
		return ""
	var wanted: String = (
		source.get_file() if keep_name and PackArchive.is_safe_entry(source.get_file())
		else Builder.safe_file_name(source)
	)
	var name: String = wanted
	var attempt: int = 2
	while copies.has(name) and str(copies[name]) != source:
		name = "%s_%d.%s" % [wanted.get_basename(), attempt, wanted.get_extension()]
		attempt += 1
	copies[name] = source
	return name
