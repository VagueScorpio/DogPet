extends SceneTree
## RT probe P1: the pure halves of the import engine, fed rubbish.
##
## Nothing here opens a file in the project. Every image is built in memory.

func _init() -> void:
	_dict_append()
	_even_parts()
	_recount()
	_life_stages()
	_frame_series()
	_tiny_images()
	_state_words()
	quit(0)


func say(what: String) -> void:
	print("  ", what)


# --- 1. Does appending to a Packed array inside a Dictionary stick? --------
func _dict_append() -> void:
	print("[1] dictionary-held PackedStringArray mutation")
	var d: Dictionary = {"loose": PackedStringArray(["a"])}
	d["loose"].append_array(PackedStringArray(["b", "c"]))
	say("after append_array, size = %d (want 3)" % PackedStringArray(d["loose"]).size())


# --- 2. SheetGrid.even_parts with a zero / negative count ------------------
func _even_parts() -> void:
	print("[2] SheetGrid.even_parts(rect, 0) and (rect, -3)")
	var r := Rect2i(0, 0, 64, 32)
	var zero: Array[Rect2i] = SheetGrid.even_parts(r, 0)
	say("count 0 -> %d parts" % zero.size())
	var neg: Array[Rect2i] = SheetGrid.even_parts(r, -3)
	say("count -3 -> %d parts" % neg.size())
	print("[2b] SheetGrid.dips_at_joins(tally, 0)")
	var tally: PackedInt32Array = [1, 2, 3, 4]
	say("dips_at_joins(.., 0) -> %s" % str(SheetGrid.dips_at_joins(tally, 0)))
	print("[2c] even_parts where count > width")
	var thin: Array[Rect2i] = SheetGrid.even_parts(Rect2i(0, 0, 10, 10), 64)
	say("10px into 64 -> first part %s, last %s" % [str(thin[0]), str(thin[63])])


# --- 3. SheetPlan.recount with silly frame counts -------------------------
func _recount() -> void:
	print("[3] SheetPlan.recount")
	var piece: Dictionary = {
		"label": "x", "name": "x", "frames": 1, "animated": false,
		"size": Vector2i(10, 10), "state": "", "stage": "", "stage_index": -1,
		"stage_count": 0,
		"cut": {
			"paths": PackedStringArray(["a.png"]),
			"rects": [Rect2i(0, 0, 10, 10)] as Array[Rect2i],
			"key": false, "align": false,
		},
	}
	var zero: Dictionary = SheetPlan.recount(piece, 0)
	say("recount to 0 -> frames %d (unchanged expected)" % int(zero["frames"]))
	var neg: Dictionary = SheetPlan.recount(piece, -5)
	say("recount to -5 -> frames %d" % int(neg["frames"]))
	var wide: Dictionary = SheetPlan.recount(piece, 64)
	var rects: Array = wide["cut"]["rects"]
	say("recount 10px wide to 64 frames -> %d rects, first %s, size field %s" % [
		rects.size(), str(rects[0]), str(wide["size"]),
	])
	var zero_wide: int = 0
	for rect in rects:
		if Rect2i(rect).size.x <= 0:
			zero_wide += 1
	say("...of which %d have zero width" % zero_wide)
	print("[3b] recount on a piece whose rects list is empty")
	var broken: Dictionary = piece.duplicate(true)
	broken["cut"]["rects"] = [] as Array[Rect2i]
	var out: Dictionary = SheetPlan.recount(broken, 4)
	say("survived, frames = %d" % int(out["frames"]))


# --- 4. LifeStages with counts nobody should pass it ----------------------
func _life_stages() -> void:
	print("[4] LifeStages")
	for count in [-3, 0, 1, 2, 7, 8, 9, 64]:
		var names: PackedStringArray = LifeStages.names_for(count, false)
		say("names_for(%d) -> %d names %s" % [count, names.size(), str(names)])
	for count in [-3, 0, 1, 4]:
		say("index_for(5.0, %d) -> %d" % [count, LifeStages.index_for(5.0, count)])
	say("index_for(NAN, 4) -> %d" % LifeStages.index_for(NAN, 4))
	say("index_for(INF, 4) -> %d" % LifeStages.index_for(INF, 4))
	say("index_for(-1e30, 4) -> %d" % LifeStages.index_for(-1e30, 4))
	say("label_for('') -> '%s'" % LifeStages.label_for(""))
	say("label_for('___') -> '%s'" % LifeStages.label_for("___"))


# --- 5. FrameSeries on names people really have --------------------------
func _frame_series() -> void:
	print("[5] FrameSeries.split_number")
	for name in [
		".png", "0001.png", "run_99999999999999999999.png", "sheet (2).png",
		"(3).png", "a1b2c3.png", "walk_-5.png", "run_007", "....png",
	]:
		var split: Dictionary = FrameSeries.split_number(name)
		say("%-32s -> %s" % [name, str(split)])
	print("[5b] group with a huge run and a single stray")
	var paths: PackedStringArray = []
	for index in 2000:
		paths.append("C:/x/run_%04d.png" % index)
	var started: int = Time.get_ticks_msec()
	var grouped: Dictionary = FrameSeries.group(paths)
	say("2000 numbered files grouped in %d ms -> %d series, %d loose" % [
		Time.get_ticks_msec() - started,
		(grouped["series"] as Array).size(),
		PackedStringArray(grouped["loose"]).size(),
	])
	var series: Dictionary = (grouped["series"] as Array)[0]
	say("first series name '%s', %d frames" % [
		str(series["name"]), PackedStringArray(series["paths"]).size(),
	])
	say("SheetCutter.too_many_frames(2000) -> %s, room_for -> %d" % [
		str(SheetCutter.too_many_frames(2000)), SheetCutter.room_for(2000),
	])


# --- 6. Scans of degenerate pictures -------------------------------------
func _tiny_images() -> void:
	print("[6] SheetScan on degenerate images")
	var one: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	one.fill(Color.RED)
	_report("1x1 solid", SheetScan.of_image("one.png", one))

	var line: Image = Image.create(4096, 1, false, Image.FORMAT_RGBA8)
	line.fill(Color.WHITE)
	line.set_pixel(10, 0, Color.BLACK)
	_report("4096x1", SheetScan.of_image("line.png", line))

	var tall: Image = Image.create(1, 4096, false, Image.FORMAT_RGBA8)
	tall.fill(Color.WHITE)
	_report("1x4096", SheetScan.of_image("tall.png", tall))

	var clear: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	clear.fill(Color(0, 0, 0, 0))
	_report("64x64 fully clear", SheetScan.of_image("clear.png", clear))

	print("[6b] SheetScan.of_image handed a non-RGBA8 image")
	var rgb: Image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	rgb.fill(Color.WHITE)
	for x in 20:
		rgb.set_pixel(x + 10, 30, Color.BLACK)
	var scan: Dictionary = SheetScan.of_image("rgb.png", rgb)
	say("scan of an RGB8 image: coverage %.4f, problem '%s'" % [
		float(scan["coverage"]), str(scan["problem"]),
	])
	say("now asking SheetStages about it, which reads 4 bytes a pixel...")
	var rects: Array[Rect2i] = [
		Rect2i(0, 0, 21, 64), Rect2i(21, 0, 21, 64), Rect2i(42, 0, 22, 64),
	]
	var judged: Dictionary = SheetStages.of_cells(scan, rgb, rects, rects)
	say("SheetStages survived: is_stages %s" % str(judged["is_stages"]))


func _report(what: String, scan: Dictionary) -> void:
	var grid: Dictionary = SheetGrid.of_scan(scan)
	var bands: Array[Dictionary] = SheetBands.of_scan(scan, grid)
	say("%-20s coverage %.4f  grid %dx%d regular=%s  bands %d  problem '%s'" % [
		what, float(scan["coverage"]), int(grid["columns"]), int(grid["rows"]),
		str(grid["regular"]), bands.size(), str(scan["problem"]),
	])


# --- 7. state_for on names designed to confuse it ------------------------
func _state_words() -> void:
	print("[7] SheetPlan.state_for")
	for name in [
		"C:/art/creatures.png", "C:/art/Walkabout.png", "C:/art/sitting-duck.png",
		"C:/art/UNSTEADY.png", "C:/art/", "", "C:/sleep/x.png", "C:/art/food_bowl.png",
	]:
		say("%-28s -> '%s'" % [name, SheetPlan.state_for(name)])
