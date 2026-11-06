extends SceneTree
## Point the sheet reader at some files and print what it makes of them.
##
## The import wizard runs the same engine behind a few questions; this is it
## with the questions taken off, which is how a sheet that comes out wrong
## gets looked at without clicking through a dialog five times.
##
##   godot --headless --path . --script res://tools/read_sheet.gd -- \
##       --in <file-or-folder> [--out <folder>] [--quiet] [--grid]
##
## --grid prints the measurements behind the answer - the paper colour, the
## cells found, and how alike the neighbours in each row are - which is what
## a sheet cut in the wrong places has to be looked at through.
##
## --in may be one PNG or a folder, which is read one level deep so a folder
## of numbered frames beside a folder of sheets is handled in one go. With
## --out, every piece is cut and written there as the strip it would be
## installed as, so the result can be looked at rather than taken on trust.

const Plan := preload("res://scripts/sheet_plan.gd")
const Cutter := preload("res://scripts/sheet_cutter.gd")
const Scan := preload("res://scripts/sheet_scan.gd")
const Grid := preload("res://scripts/sheet_grid.gd")


func _initialize() -> void:
	var options: Dictionary = _options()
	if not options.has("in"):
		print("usage: --in <file-or-folder> [--out <folder>] [--quiet]")
		quit(1)
		return

	var sources: PackedStringArray = _gather(str(options["in"]))
	if sources.is_empty():
		print("no PNGs under %s" % options["in"])
		quit(1)
		return
	print("reading %d files" % sources.size())
	if options.has("grid"):
		for path in sources:
			_measure(path)

	var found: Dictionary = Plan.read(sources)
	var pieces: Array = found["pieces"]
	for note in PackedStringArray(found["notes"]):
		print("  note: %s" % note)

	var animations: int = 0
	var stills: int = 0
	var staged: int = 0
	for entry in pieces:
		var piece: Dictionary = entry
		if bool(piece["animated"]):
			animations += 1
		else:
			stills += 1
		if not str(piece.get("stage", "")).is_empty():
			staged += 1
		if not options.has("quiet"):
			var notes: PackedStringArray = []
			if not str(piece["state"]).is_empty():
				notes.append("state: %s" % piece["state"])
			if not str(piece.get("stage", "")).is_empty():
				notes.append("stage: %s" % piece["stage"])
			print("  %-60s %2d frame(s)  %d x %d  %s" % [
				piece["label"], piece["frames"],
				Vector2i(piece["size"]).x, Vector2i(piece["size"]).y,
				" ".join(notes),
			])
	print("%d animations, %d still pictures (%d of them life stages)" % [
		animations, stills, staged,
	])

	if options.has("out"):
		quit(_write_all(pieces, str(options["out"])))
		return
	quit(0)


# What the scan and the grid make of one file, before any of it is judged.
func _measure(path: String) -> void:
	var scan: Dictionary = Scan.read(path)
	if not str(scan["problem"]).is_empty():
		print("  %s: %s" % [path.get_file(), scan["problem"]])
		return
	print("  %s: %d x %d, measured at 1/%d, paper %s, %.1f%% drawn on" % [
		path.get_file(), Vector2i(scan["size"]).x, Vector2i(scan["size"]).y,
		int(scan["scale"]),
		Color(scan["background"]).to_html(false) if bool(scan["keyed"]) else "already clear",
		float(scan["coverage"]) * 100.0,
	])
	var grid: Dictionary = Grid.of_scan(scan)
	print("    grid: %d across, %d down, cell %d x %d, %s, %d cells used" % [
		int(grid["columns"]), int(grid["rows"]),
		Vector2i(grid["cell"]).x, Vector2i(grid["cell"]).y,
		"regular" if bool(grid["regular"]) else "IRREGULAR", int(grid["filled"]),
	])


func _write_all(pieces: Array, folder: String) -> int:
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		print("could not make %s" % folder)
		return 1
	var failures: int = 0
	var used: Dictionary = {}
	for entry in pieces:
		var piece: Dictionary = entry
		var name: String = str(piece["name"])
		while used.has(name):
			name += "_x"
		used[name] = true
		var trouble: String = Cutter.write(
			piece["cut"], folder.path_join("%s.png" % name)
		)
		if trouble.is_empty():
			continue
		print("  %s" % trouble)
		failures += 1
	print("wrote %d strips into %s" % [pieces.size() - failures, folder])
	return 1 if failures > 0 else 0


# One file, or every PNG in a folder and in the folders directly inside it.
func _gather(where: String) -> PackedStringArray:
	if FileAccess.file_exists(where):
		return PackedStringArray([where])
	var found: PackedStringArray = []
	_add_pngs(where, found)
	for folder in DirAccess.get_directories_at(where):
		_add_pngs(where.path_join(folder), found)
	return found


func _add_pngs(folder: String, into: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() == "png":
			into.append(folder.path_join(file))


func _options() -> Dictionary:
	var given: Dictionary = {}
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < arguments.size():
		var name: String = arguments[index].lstrip("-")
		var value: String = ""
		if index + 1 < arguments.size() and not arguments[index + 1].begins_with("--"):
			value = arguments[index + 1]
			index += 1
		given[name] = value
		index += 1
	return given
