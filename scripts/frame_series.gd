class_name FrameSeries
extends RefCounted
## Spotting a numbered run of files: run_000.png, run_001.png, run_002.png.
##
## A lot of animation arrives this way rather than as a strip - one PNG per
## frame, named with a counter - and handed to DogPet as it stands it would
## become twenty still pictures of a dog mid-stride. The frames belong
## together, and the only thing saying so is their names.
##
## Pure string work: no files are opened, so the tests can hand it a list of
## names that never existed. Whether the frames are really the same size is
## SheetPlan's problem, after this has said which ones to compare.

## The fewest frames a numbered run needs before it is a run rather than a
## coincidence. Two is enough: idle_1 and idle_2 is a two-frame blink.
const MIN_FRAMES := 2

## A gap this big between numbers breaks the run in two. Exporters skip the
## odd number; they do not skip fifty.
const MAX_GAP := 4

## A prefix shorter than this says nothing useful, so the folder the files
## are in gets to name the run instead - "l_000.png" inside jump/ is the
## jump, whatever the l stands for.
const WEAK_PREFIX := 3

## The most digits a frame counter can have.
##
## Past this it is not a counter - it is a date, a hash, or a number too big
## for int() to read without an engine error, which then saturates to
## INT64_MAX and glues unrelated files into one run. Twelve digits is a
## trillion frames, so nothing real is refused.
const MAX_DIGITS := 12


## Group paths into numbered runs. Returns
## {"series": Array[Dictionary], "loose": PackedStringArray}, where each
## series is {"name", "paths", "numbers"} and the loose ones belong to no run.
##
## Order is kept: a series appears where its first file appeared, so what
## the owner chose in the dialog is roughly what they see back.
static func group(paths: PackedStringArray) -> Dictionary:
	var buckets: Dictionary = {}
	var order: Array[String] = []
	var loose: PackedStringArray = []

	for path in paths:
		var split: Dictionary = split_number(path.get_file())
		if split.is_empty():
			loose.append(path)
			continue
		# The folder is part of the key: run/rr_000.png and jump/rr_000.png
		# are two different animations that happen to be named alike.
		var key: String = "%s|%s|%s|%d" % [
			path.get_base_dir(), split["prefix"], split["suffix"], int(split["digits"]),
		]
		if not buckets.has(key):
			buckets[key] = []
			order.append(key)
		buckets[key].append({"path": path, "number": int(split["number"])})

	var series: Array[Dictionary] = []
	for key in order:
		var entries: Array = buckets[key]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["number"]) < int(b["number"])
		)
		for run in _unbroken(entries):
			if PackedStringArray(run["paths"]).size() < MIN_FRAMES:
				loose.append_array(run["paths"])
				continue
			run["name"] = _name_for(run["paths"])
			series.append(run)
	return {"series": series, "loose": loose}


## Split "run_007.png" into its parts: {"prefix", "number", "digits",
## "suffix"}. Empty when the name has no number on the end of it.
##
## The number has to be the last run of digits before the extension, with
## nothing after it but letters that are part of the name - "dog2_walk.png"
## is not frame two of anything, so its number is the 2 and its suffix is
## "_walk", which keeps it in a bucket of its own.
static func split_number(file_name: String) -> Dictionary:
	var base: String = file_name.get_basename()
	var last: int = -1
	for index in base.length():
		if base[index].is_valid_int():
			last = index
	if last < 0:
		return {}
	var first: int = last
	while first > 0 and base[first - 1].is_valid_int():
		first -= 1
	var digits: String = base.substr(first, last - first + 1)
	# "sheet (2).png" is Windows saying it already had a sheet.png, not
	# frame two of an animation. A number in brackets is never a counter.
	if first > 0 and base[first - 1] == "(" and base.substr(last + 1).begins_with(")"):
		return {}
	if digits.length() > MAX_DIGITS:
		return {}
	return {
		"prefix": base.substr(0, first),
		"number": int(digits),
		"digits": digits.length(),
		"suffix": base.substr(last + 1),
	}


# Split a sorted bucket wherever the numbering jumps. Two downloads dropped
# in the same folder - frames 0 to 17 and frames 100 to 112 - are two
# animations, not one with a hole in the middle.
static func _unbroken(entries: Array) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	var paths: PackedStringArray = []
	var numbers: PackedInt32Array = []
	var previous: int = -MAX_GAP - 1
	for entry in entries:
		var number: int = int(entry["number"])
		if not paths.is_empty() and number - previous > MAX_GAP:
			runs.append({"paths": paths, "numbers": numbers})
			paths = PackedStringArray()
			numbers = PackedInt32Array()
		paths.append(str(entry["path"]))
		numbers.append(number)
		previous = number
	if not paths.is_empty():
		runs.append({"paths": paths, "numbers": numbers})
	return runs


# What to call the run. The prefix if it says anything, the folder if it
# does not, and the first file's name if neither does.
static func _name_for(paths: PackedStringArray) -> String:
	var first: String = paths[0]
	var prefix: String = str(split_number(first.get_file()).get("prefix", ""))
	var trimmed: String = prefix.strip_edges().trim_suffix("_").trim_suffix("-")
	if trimmed.length() >= WEAK_PREFIX:
		return trimmed
	var folder: String = first.get_base_dir().get_file()
	return folder if not folder.is_empty() else first.get_file().get_basename()
