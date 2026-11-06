class_name SheetPlan
extends RefCounted
## The decision the whole sheet reader exists to make: is this row of
## pictures one animation, or several separate pictures?
##
## This is the front door of the sheet reader, and the part that puts the
## rest of it together. SheetScan says what is drawn, SheetGrid and
## SheetBands say where the cells are, SheetLikeness says whether a row of
## them is one animal moving, and FrameSeries says which files belong
## together. What comes out is in the terms the rest of DogPet uses: a piece
## is either one still picture or one strip of frames, and either way it
## comes with the instructions for cutting it out.
##
## Nothing here is final - every piece is shown to the owner to correct, and
## recount re-cuts one that was read wrong.

## Which word in a file name means which state. Checked longest first, so
## "restless" is not read as "rest".
const STATE_WORDS: Dictionary = {
	"restless": "restless", "zoomie": "restless", "pace": "restless",
	"sleep": "sleep", "nap": "sleep", "asleep": "sleep",
	"happy": "happy", "bark": "happy", "wag": "happy", "woof": "happy",
	"sad": "sad", "cry": "sad", "sick": "sad", "ill": "sad",
	"eat": "eat", "feed": "eat", "food": "eat", "chew": "eat", "bowl": "eat",
	"play": "play", "jump": "play", "fetch": "play", "toy": "play", "bounce": "play",
	"walk": "walk", "run": "walk", "trot": "walk", "step": "walk",
	"idle": "idle", "stand": "idle", "still": "idle", "sit": "idle",
}


## Read a set of chosen files and say what is in them.
##
## Returns {"pieces", "notes"}. Each piece is one thing that could be
## installed: see _piece for the shape. The notes are anything worth saying
## out loud - a file that could not be read, a sheet too busy to cut.
static func read(paths: PackedStringArray) -> Dictionary:
	var pieces: Array[Dictionary] = []
	var notes: PackedStringArray = []

	var grouped: Dictionary = FrameSeries.group(paths)
	for entry in grouped["series"]:
		var series: Dictionary = entry
		var files: PackedStringArray = series["paths"]
		var scan: Dictionary = SheetScan.read(files[0])
		if not str(scan["problem"]).is_empty():
			notes.append(str(scan["problem"]))
			continue
		# Frames of one animation are exported at one size. Different sizes
		# mean these files only looked like a run, so they are left alone.
		if not _all_one_size(files, scan["size"]):
			notes.append(
				"%s and the files numbered with it are different sizes, so they were"
				% files[0].get_file()
				+ " kept as separate pictures."
			)
			grouped["loose"].append_array(files)
			continue
		pieces.append(_series_piece(series, scan))

	for path in PackedStringArray(grouped["loose"]):
		var opened: Dictionary = SheetScan.open(path)
		var scan: Dictionary = opened["scan"]
		if not str(scan["problem"]).is_empty():
			notes.append(str(scan["problem"]))
			continue
		if not SheetScan.has_ink(scan):
			notes.append("%s looks blank." % path.get_file())
			continue
		pieces.append_array(_pieces_in(scan, opened["image"], notes))

	return {"pieces": pieces, "notes": notes}


## The same piece, cut into a different number of frames.
##
## The count this engine arrives at is a reading of a picture, and a reading
## can be wrong. Rather than send the owner back to the sheet with a photo
## editor, whatever the piece covers is simply divided again into however
## many frames they say it holds.
##
## A run of numbered files is the one thing that cannot be recounted: there
## are as many frames as there are files, and no arithmetic changes that.
static func recount(piece: Dictionary, frames: int) -> Dictionary:
	var cut: Dictionary = piece["cut"]
	var paths: PackedStringArray = cut["paths"]
	var rects: Array = cut["rects"]
	if paths.is_empty() or frames < 1 or frames == int(piece["frames"]):
		return piece
	for path in paths:
		if path != paths[0]:
			return piece

	var whole: Rect2i = rects[0]
	for rect in rects:
		whole = whole.merge(rect)
	var parts: Array[Rect2i] = SheetGrid.even_parts(whole, frames)
	var again: PackedStringArray = []
	for _part in parts:
		again.append(paths[0])

	var changed: Dictionary = piece.duplicate(true)
	changed["frames"] = frames
	changed["animated"] = frames > 1
	changed["size"] = parts[0].size
	changed["cut"] = {
		"paths": again, "rects": parts, "key": cut["key"], "align": false,
	}
	return changed


## Which DogPet state a name is asking for, or "" when it says nothing.
##
## The word has to start where a word starts. Without that rule "creatures"
## asks to be fed, because somewhere in the middle of it is "eat".
static func state_for(text: String) -> String:
	var found: String = _state_in(text.get_file().get_basename())
	# Frames exported one per file are named l_000.png and rr_000.png; what
	# they are is written on the folder they came in, not on them.
	return found if not found.is_empty() else _state_in(text.get_base_dir().get_file())


static func _state_in(name: String) -> String:
	var lowered: String = name.to_lower()
	var best: String = ""
	var longest: int = 0
	for word in STATE_WORDS:
		if word.length() > longest and _starts_a_word(lowered, word):
			longest = word.length()
			best = str(STATE_WORDS[word])
	return best


const LETTERS := "abcdefghijklmnopqrstuvwxyz"


static func _starts_a_word(text: String, word: String) -> bool:
	var at: int = text.find(word)
	while at >= 0:
		if at == 0 or not LETTERS.contains(text[at - 1]):
			return true
		at = text.find(word, at + 1)
	return false


# --- What is in one picture ----------------------------------------------

static func _pieces_in(
	scan: Dictionary, image: Image, notes: PackedStringArray
) -> Array[Dictionary]:
	var bands: Array[Dictionary] = SheetBands.of_scan(scan, SheetGrid.of_scan(scan))
	if bands.is_empty():
		return [_whole_piece(scan)]

	var pieces: Array[Dictionary] = []
	for index in bands.size():
		pieces.append_array(_row_pieces(scan, image, bands[index], index, bands.size()))
	if pieces.size() > SheetLikeness.MAX_FRAMES:
		notes.append(
			"%s is cut into %d pieces. Give a job to the ones you want and leave the rest."
			% [str(scan["path"]).get_file(), pieces.size()]
		)
	return pieces


# Judge one band: one animation, or that many separate pictures.
static func _row_pieces(
	scan: Dictionary, image: Image, band: Dictionary, row: int, of_rows: int
) -> Array[Dictionary]:
	var keep: PackedInt32Array = SheetLikeness.without_outliers(scan, band["scan_rects"])
	var rects: Array[Rect2i] = []
	var scan_rects: Array[Rect2i] = []
	for index in keep:
		rects.append(band["rects"][index])
		scan_rects.append(band["scan_rects"][index])
	if rects.is_empty():
		return []
	if rects.size() == 1:
		var split: Dictionary = SheetBands.split_touching(scan, rects[0], scan_rects[0])
		if not split.is_empty():
			rects = split["rects"]
			scan_rects = split["scan_rects"]

	var file: String = str(scan["path"]).get_file()
	var name: String = file.get_basename()
	var where: String = "" if of_rows <= 1 else ", row %d" % (row + 1)

	# Asked before the animation question, and it has to be: a puppy and the
	# senior it grows into are the same animal in the same pose, so a life
	# cycle passes the one-animal test with flying colours and would be
	# installed as an animation of the dog ageing four times a second.
	if image != null:
		var ages: Dictionary = SheetStages.of_cells(scan, image, scan_rects, rects)
		if bool(ages["is_stages"]):
			return _stage_pieces(scan, rects, ages, name, file, where)

	if rects.size() > 1 and SheetLikeness.one_animal(scan, scan_rects):
		return [_piece(
			"%s%s - %d frames, one animation" % [file, where, rects.size()],
			"%s%s" % [name, "" if of_rows <= 1 else "_%d" % (row + 1)],
			scan, rects, true
		)]

	var pieces: Array[Dictionary] = []
	for index in rects.size():
		var which: String = "" if rects.size() <= 1 else " %d" % (index + 1)
		pieces.append(_piece(
			"%s%s%s - one picture" % [file, where, which],
			"%s%s%s" % [
				name,
				"" if of_rows <= 1 else "_%d" % (row + 1),
				"" if rects.size() <= 1 else "_%d" % (index + 1),
			],
			scan, [rects[index]], false
		))
	return pieces


# One piece per age, each a still picture of the dog at that point in its
# life. They carry the stage they belong to, so the wizard can offer them as
# a set rather than as four unrelated drawings the owner has to sort out.
static func _stage_pieces(
	scan: Dictionary, rects: Array[Rect2i], ages: Dictionary,
	name: String, file: String, where: String
) -> Array[Dictionary]:
	var names: PackedStringArray = SheetStages.names_for(ages)
	var pieces: Array[Dictionary] = []
	for index in rects.size():
		var stage: String = names[index] if index < names.size() else "stage_%d" % (index + 1)
		var piece: Dictionary = _piece(
			"%s%s - %s (%d of %d life stages)" % [
				file, where, LifeStages.label_for(stage), index + 1, rects.size(),
			],
			"%s_%s" % [name, stage], scan, [rects[index]], false
		)
		piece["stage"] = stage
		piece["stage_index"] = index
		piece["stage_count"] = rects.size()
		pieces.append(piece)
	return pieces


# --- Building the pieces --------------------------------------------------

static func _series_piece(series: Dictionary, scan: Dictionary) -> Dictionary:
	var files: PackedStringArray = series["paths"]
	var name: String = str(series["name"])
	var rects: Array[Rect2i] = []
	for _file in files:
		rects.append(Rect2i(Vector2i.ZERO, scan["size"]))
	var piece: Dictionary = _piece(
		"%s - %d numbered files, one animation" % [name, files.size()],
		name, scan, rects, true
	)
	piece["cut"]["paths"] = files
	piece["state"] = state_for(name)
	return piece


static func _whole_piece(scan: Dictionary) -> Dictionary:
	var name: String = str(scan["path"]).get_file().get_basename()
	return _piece(
		"%s - one picture" % str(scan["path"]).get_file(), name, scan,
		[Rect2i(Vector2i.ZERO, scan["size"])], false
	)


# One thing that could be installed. "cut" is everything SheetCutter needs:
# which file each frame comes out of, which part of it, whether the paper
# has to be keyed out, and whether the frames need lining up afterwards.
static func _piece(
	label: String, name: String, scan: Dictionary, rects: Array[Rect2i], animated: bool
) -> Dictionary:
	var paths: PackedStringArray = []
	var widest: int = 0
	var tallest: int = 0
	for rect in rects:
		paths.append(str(scan["path"]))
		widest = maxi(widest, rect.size.x)
		tallest = maxi(tallest, rect.size.y)
	# Cells of one size are already registered to each other, so they are
	# left where they are; anything cut out of a loose sheet is not, and has
	# to be stood on a common baseline or the animation jitters.
	var even: bool = true
	for rect in rects:
		even = even and rect.size == rects[0].size
	return {
		"label": label,
		"name": PackArchive.clean_id(name),
		"frames": rects.size(),
		"animated": animated and rects.size() > 1,
		"size": Vector2i(widest, tallest),
		"state": state_for(str(scan["path"])),
		# Filled in by _stage_pieces for a life-cycle row. Every piece
		# carries them so nothing downstream has to check first.
		"stage": "",
		"stage_index": -1,
		"stage_count": 0,
		"cut": {
			"paths": paths,
			"rects": rects,
			"key": bool(scan["keyed"]),
			"align": not even,
		},
	}


static func _all_one_size(paths: PackedStringArray, size: Vector2i) -> bool:
	for path in paths:
		if ImageLimits.png_size_from_header(path) != size:
			return false
	return true
