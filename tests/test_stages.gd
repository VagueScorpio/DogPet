extends "res://tests/suite.gd"
## Headless tests for life-cycle art: telling a dog growing up from a dog
## moving, naming however many ages a sheet turned out to hold, and drawing
## the right one for the dog's age.
##
##   godot --headless --path . --script res://tests/test_stages.gd
##
## The naming and the age arithmetic are pure and are checked exactly. The
## reading is checked on drawn pixels, because "this row is the same animal
## at four ages" is a judgement about pictures and nothing else.

const Stages := preload("res://scripts/sheet_stages.gd")
const Ages := preload("res://scripts/life_stages.gd")
const Scan := preload("res://scripts/sheet_scan.gd")
const Plan := preload("res://scripts/sheet_plan.gd")
const Life := preload("res://scripts/life_model.gd")
const Pack := preload("res://scripts/pet_pack.gd")

const PAPER := Color(1, 1, 1, 1)

var _scratch: String = ""


func _initialize() -> void:
	_open("DogPet life-stage tests")

	_scratch = ProjectSettings.globalize_path("user://test_stages")
	_clean()
	DirAccess.make_dir_recursive_absolute(_scratch)

	_test_names()
	_test_age_mapping()
	_test_reading_a_cycle()
	_test_not_a_cycle()
	_test_pack_stages()

	_clean()
	_report()


# --- Naming --------------------------------------------------------------

func _test_names() -> void:
	_begin("However many ages a sheet holds, they get names")
	_ok("three are puppy, adult, senior",
		Ages.names_for(3) == PackedStringArray(["puppy", "adult", "senior"]))
	_ok("four put a juvenile in the middle",
		Ages.names_for(4) == PackedStringArray(["puppy", "juvenile", "adult", "senior"]))
	_ok("five with late greying give an older adult",
		Ages.names_for(5, true) == PackedStringArray(
			["puppy", "juvenile", "adult", "older_adult", "senior"]))
	_ok("five with early greying give a young adult",
		Ages.names_for(5, false) == PackedStringArray(
			["puppy", "juvenile", "young_adult", "adult", "senior"]))
	_ok("one drawing is just the dog", Ages.names_for(1) == PackedStringArray(["adult"]))
	# Two is a puppy and a grown dog; calling either one "senior" would be
	# a claim the sheet never made.
	_ok("two do not reach senior", not Ages.names_for(2).has("senior"))

	_begin("Every count starts young and ends old")
	for count in range(3, Ages.MAX_STAGES + 1):
		var names: PackedStringArray = Ages.names_for(count)
		_ok("%d names, no repeats" % count, _unique(names) and names.size() == count)
		_ok("%d starts at puppy" % count, names[0] == "puppy")
		_ok("%d ends at senior" % count, names[count - 1] == "senior")

	_begin("Names are shown as words")
	_ok("young_adult reads as Young Adult", Ages.label_for("young_adult") == "Young Adult")
	_ok("puppy reads as Puppy", Ages.label_for("puppy") == "Puppy")


# --- Which drawing for which age -----------------------------------------

func _test_age_mapping() -> void:
	_begin("A dog is drawn at the age it has reached")
	_ok("a newborn is the first drawing", Ages.index_for(0.0, 4) == 0)
	_ok("a very old dog is the last", Ages.index_for(1000.0, 4) == 3)
	_ok("one drawing is always drawing zero", Ages.index_for(1000.0, 1) == 0)
	# Four drawings are meant to line up with LifeModel's own four stages,
	# which is the case the whole scale was built around.
	_ok("a puppy maps to the puppy drawing",
		Ages.index_for(Life.PUPPY_DAYS * 0.5, 4) == 0)
	_ok("a young dog maps to the second",
		Ages.index_for((Life.PUPPY_DAYS + Life.YOUNG_DAYS) * 0.5, 4) == 1)
	_ok("an adult maps to the third",
		Ages.index_for((Life.YOUNG_DAYS + Life.ADULT_DAYS) * 0.5, 4) == 2)
	_ok("a senior maps to the fourth",
		Ages.index_for(Life.ADULT_DAYS + 1.0, 4) == 3)

	_begin("The answer is always one of the drawings")
	for count in range(1, Ages.MAX_STAGES + 1):
		var fine: bool = true
		for days in [-5.0, 0.0, 1.0, 9.0, 39.0, 100.0, 100000.0]:
			var at: int = Ages.index_for(float(days), count)
			fine = fine and at >= 0 and at < count
		_ok("%d drawings stay in range at every age" % count, fine)

	_begin("Ageing never goes backwards")
	var previous: int = 0
	var forwards: bool = true
	for step in 200:
		var at: int = Ages.index_for(float(step) * 0.5, 5)
		forwards = forwards and at >= previous
		previous = at
	_ok("the drawing only ever moves on", forwards)


# --- Reading a sheet ------------------------------------------------------

func _test_reading_a_cycle() -> void:
	_begin("A row that grows and greys is a life cycle")
	# Four dogs: each a little bigger than the last, and the colour draining
	# out of them. That is what a life cycle looks like to the engine.
	var path: String = _write("cycle.png", _progression(4, true, true))
	var opened: Dictionary = Scan.open(path)
	var found: Dictionary = Plan.read(PackedStringArray([path]))
	var pieces: Array = found["pieces"]
	_ok("it comes back as four pieces", pieces.size() == 4)
	_ok("all four are life stages", _all_staged(pieces))
	_ok("none of them is an animation", _none_animated(pieces))
	_ok("they are named youngest first",
		pieces.size() == 4 and str(pieces[0]["stage"]) == "puppy"
		and str(pieces[3]["stage"]) == "senior")
	_ok("each knows its place", pieces.size() == 4 and int(pieces[2]["stage_index"]) == 2)
	_ok("each knows how many there are",
		pieces.size() == 4 and int(pieces[0]["stage_count"]) == 4)
	_ok("the scan read it", opened["image"] != null)

	_begin("Greying alone is enough, for a dog that hardly grows")
	# A sleeping dog is much the same size at every age, so the size test
	# cannot carry this one and the colour has to.
	var lying: String = _write("lying.png", _progression(4, false, true))
	var lying_pieces: Array = Plan.read(PackedStringArray([lying]))["pieces"]
	_ok("it is still read as a life cycle", _all_staged(lying_pieces))


func _test_not_a_cycle() -> void:
	_begin("A row that does neither is an animation, as before")
	# Same size, same colour, four times over: a walk cycle.
	var path: String = _write("walk.png", _progression(4, false, false))
	var pieces: Array = Plan.read(PackedStringArray([path]))["pieces"]
	_ok("it is one piece", pieces.size() == 1)
	_ok("it is an animation", pieces.size() == 1 and bool(pieces[0]["animated"]))
	_ok("it is not a life cycle", pieces.size() == 1 and str(pieces[0]["stage"]).is_empty())

	_begin("Growth alone is not enough when the colour comes back")
	# Saturation that climbs again partway is a frame of something, not a
	# dog ageing: ageing only goes one way.
	var wobble: Array[Vector2] = [
		Vector2(0.8, 0.5), Vector2(0.5, 0.5), Vector2(0.9, 0.5), Vector2(0.4, 0.5),
	]
	_ok("colour that recovers is refused", not Stages._drains(wobble, 0.4))
	var draining: Array[Vector2] = [
		Vector2(0.8, 0.5), Vector2(0.7, 0.5), Vector2(0.6, 0.5), Vector2(0.4, 0.5),
	]
	_ok("colour that only falls is accepted", Stages._drains(draining, 0.4))

	_begin("Two drawings are too few to call a life cycle")
	var pair: String = _write("pair.png", _progression(2, true, true))
	var pieces_two: Array = Plan.read(PackedStringArray([pair]))["pieces"]
	_ok("a pair is not staged", not _all_staged(pieces_two))


# --- The pack format ------------------------------------------------------

func _test_pack_stages() -> void:
	_begin("A pack can carry one drawing per age")
	var folder: String = _scratch.path_join("staged")
	DirAccess.make_dir_recursive_absolute(folder)
	for stage in ["puppy", "adult", "senior"]:
		_blank_sprite().save_png(folder.path_join("idle_%s.png" % stage))
	_write_json(folder.path_join("pet.json"), {
		"format_version": 1, "id": "staged", "name": "Staged", "kind": "sprite2d",
		"credit_not_required": true,
		"animations": {"idle": {"stages": [
			{"file": "idle_puppy.png", "frames": 1, "fps": 1},
			{"file": "idle_adult.png", "frames": 1, "fps": 1},
			{"file": "idle_senior.png", "frames": 1, "fps": 1},
		]}},
	})

	var pack: PetPack = Pack.load_from_dir(folder)
	_ok("the pack is usable", pack.is_valid())
	_ok("it knows it has three ages", pack.stage_count() == 3)
	_ok("a puppy gets the puppy drawing",
		str(pack.sprite_for("idle", 0.0).get("file", "")) == "idle_puppy.png")
	_ok("an old dog gets the senior drawing",
		str(pack.sprite_for("idle", 1000.0).get("file", "")) == "idle_senior.png")
	# Everything that does not care about age still finds an idle animation
	# exactly where it always was.
	_ok("the plain animation list still has idle", pack.sprite_animations.has("idle"))
	_ok("a state it does not draw answers empty", pack.sprite_for("walk", 1.0).is_empty())

	_begin("A pack with one drawing per state is untouched")
	var plain: String = _scratch.path_join("plain")
	DirAccess.make_dir_recursive_absolute(plain)
	_blank_sprite().save_png(plain.path_join("idle.png"))
	_write_json(plain.path_join("pet.json"), {
		"format_version": 1, "id": "plain", "name": "Plain", "kind": "sprite2d",
		"credit_not_required": true,
		"animations": {"idle": {"file": "idle.png", "frames": 1, "fps": 1}},
	})
	var simple: PetPack = Pack.load_from_dir(plain)
	_ok("it loads", simple.is_valid())
	_ok("it reports one age", simple.stage_count() == 1)
	_ok("it answers the same drawing at any age",
		str(simple.sprite_for("idle", 0.0).get("file", ""))
		== str(simple.sprite_for("idle", 900.0).get("file", "")))


# --- Drawing the sheets ---------------------------------------------------

# A row of blobs, left to right. growing makes each one taller than the
# last; greying drains the colour out of them along the way.
func _progression(cells: int, growing: bool, greying: bool) -> Image:
	var cell: int = 64
	var image: Image = Image.create(cells * cell, cell, false, Image.FORMAT_RGBA8)
	image.fill(PAPER)
	for index in cells:
		var share: float = 0.0 if cells < 2 else float(index) / float(cells - 1)
		var tall: int = int(20.0 + (24.0 * share if growing else 0.0))
		var wide: int = int(20.0 + (14.0 * share if growing else 0.0))
		# Saturation falls away while lightness holds, which is what going
		# grey looks like to the measurement.
		var colour: Color = Color.from_hsv(0.08, 0.9 - (0.75 * share if greying else 0.0), 0.6)
		var at := Vector2i(index * cell + (cell - wide) / 2, cell - tall - 4)
		for y in tall:
			for x in wide:
				image.set_pixel(at.x + x, at.y + y, colour)
	return image


func _blank_sprite() -> Image:
	var image: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.3, 0.2, 1.0))
	return image


func _write(name: String, image: Image) -> String:
	var path: String = _scratch.path_join(name)
	image.save_png(path)
	return path


func _write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()


func _all_staged(pieces: Array) -> bool:
	if pieces.is_empty():
		return false
	for entry in pieces:
		if str((entry as Dictionary).get("stage", "")).is_empty():
			return false
	return true


func _none_animated(pieces: Array) -> bool:
	for entry in pieces:
		if bool((entry as Dictionary)["animated"]):
			return false
	return true


func _unique(names: PackedStringArray) -> bool:
	var seen: PackedStringArray = []
	for name in names:
		if seen.has(name):
			return false
		seen.append(name)
	return true


func _clean() -> void:
	if DirAccess.dir_exists_absolute(_scratch):
		PackArchive.empty_folder(_scratch)
		DirAccess.remove_absolute(_scratch)
