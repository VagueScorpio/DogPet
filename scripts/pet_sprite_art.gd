class_name PetSpriteArt
extends RefCounted
## Reading the "animations" block of a sprite pack's pet.json.
##
## Lifted out of PetPack, which had grown to carry the whole of this on top
## of everything else it does. Nothing here changed on the way out: the
## checks are the same checks in the same order, and the wording of every
## complaint is identical, because those strings are what the tests and the
## import wizard both read.
##
## A state is either one drawing or a list of them, one per life stage,
## youngest first. Each stage is an ordinary animation spec and is checked
## as one, so a stage may itself be a single picture or a whole animation -
## which is exactly the distinction the sheet reader makes when it cuts art
## up in the first place.
##
## Pure: paths and dictionaries in, specs and complaints out. No nodes, and
## nothing is written anywhere.


## Read a whole "animations" block.
##
## Returns {"animations", "stages", "problems"}:
##
##   animations  state -> one spec. For a state drawn at several ages this
##               holds the grown dog, so everything that only wants "the
##               walk animation" reads it and never learns the pack ages.
##   stages      state -> Array of specs, youngest first; only for states
##               that are drawn at several ages.
##   problems    everything wrong, in plain English.
static func read(
	folder: String, clips: Dictionary, valid_states: PackedStringArray
) -> Dictionary:
	var animations: Dictionary = {}
	var stages: Dictionary = {}
	var problems: PackedStringArray = []

	for raw_state in clips.keys():
		var state: String = str(raw_state)
		if not valid_states.has(state):
			problems.append("\"%s\" is not a state DogPet knows" % state)
			continue
		var spec: Variant = clips[raw_state]
		if not spec is Dictionary:
			problems.append("the %s animation is not described properly" % state)
			continue
		_read_state(folder, state, spec as Dictionary, animations, stages, problems)

	return {"animations": animations, "stages": stages, "problems": problems}


## One animation spec: the file, how many frames are in it, how fast it
## plays, and the frame size measured off the sheet.
##
## Returns an empty Dictionary when it could not be read, having said why
## in problems. Public because the stage reader below calls it once per
## age, and because it is the whole of what one animation means.
static func one(
	folder: String, state: String, spec: Dictionary, problems: PackedStringArray
) -> Dictionary:
	var file: String = str(spec.get("file", "")).strip_edges()
	var frames: int = int(spec.get("frames", 1))
	var fps: float = float(spec.get("fps", 1.0))

	if file.is_empty():
		problems.append("the %s animation names no file" % state)
		return {}
	if frames < 1:
		problems.append("the %s animation needs at least one frame" % state)
		return {}
	if fps <= 0.0:
		fps = 1.0

	var path: String = folder.path_join(file)
	if not FileAccess.file_exists(path):
		problems.append("the %s image %s is missing" % [state, path])
		return {}

	# Measure the sheet now, so the frame size is known before anything is
	# drawn and a sheet that does not divide evenly is caught here.
	#
	# Through ImageLimits rather than a reader of its own: the copy that used to
	# live in PetPack checked neither the PNG signature nor the size, so a
	# sheet far too big to show was listed as usable and only refused later, by
	# PetLoader, after the pack had been offered to the owner.
	var size: Vector2i = ImageLimits.png_size_from_header(path)
	if size.x <= 0 or size.y <= 0:
		problems.append("could not read the size of %s" % path)
		return {}
	if ImageLimits.is_too_large(size):
		problems.append(ImageLimits.describe(path, size))
		return {}
	if size.x % frames != 0:
		problems.append(
			"%s is %d wide, which does not divide into %d frames" % [file, size.x, frames]
		)
		return {}

	return {
		"file": file,
		"frames": frames,
		"fps": fps,
		"frame_width": size.x / frames,
		"frame_height": size.y,
	}


# One state's art: either a single drawing, or one per life stage.
static func _read_state(
	folder: String, state: String, spec: Dictionary,
	animations: Dictionary, stages: Dictionary, problems: PackedStringArray
) -> void:
	var staged: Variant = spec.get("stages", null)
	if not staged is Array:
		var single: Dictionary = one(folder, state, spec, problems)
		if not single.is_empty():
			animations[state] = single
		return

	var list: Array = staged as Array
	if list.is_empty():
		problems.append("the %s animation lists no life stages" % state)
		return
	if list.size() > LifeStages.MAX_STAGES:
		problems.append(
			"the %s animation lists %d life stages, which is more than the %d this app"
			% [state, list.size(), LifeStages.MAX_STAGES]
			+ " can tell apart"
		)
		return

	var read_so_far: Array[Dictionary] = []
	for index in list.size():
		if not list[index] is Dictionary:
			problems.append(
				"life stage %d of the %s animation is not described properly"
				% [index + 1, state]
			)
			return
		# Each stage is checked exactly as a lone animation would be, so a
		# missing file or a sheet that does not divide is caught per stage.
		var drawing: Dictionary = one(folder, state, list[index] as Dictionary, problems)
		if drawing.is_empty():
			return
		read_so_far.append(drawing)

	stages[state] = read_so_far
	# What the rest of the app sees by default is the grown dog, so a pack
	# that ages looks exactly like any other until something asks its age.
	animations[state] = read_so_far[
		LifeStages.index_for_stage("Adult", read_so_far.size())
	]
