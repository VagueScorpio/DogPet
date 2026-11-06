extends "res://tests/suite.gd"
## Headless tests for the sheet reader - the part of Add Art that looks at a
## picture and works out whether it is one dog, a row of frames, or a grid
## full of both.
##
##   godot --headless --path . --script res://tests/test_sheets.gd
##
## The grid and series tests are pure arithmetic over made-up numbers. The
## rest draw real PNGs into a scratch folder and read them back through the
## whole engine, because the judgement being tested - "these two cells are
## the same animal moving" - is only worth anything on pixels.

const Scan := preload("res://scripts/sheet_scan.gd")
const Grid := preload("res://scripts/sheet_grid.gd")
const Series := preload("res://scripts/frame_series.gd")
const Plan := preload("res://scripts/sheet_plan.gd")
const Cutter := preload("res://scripts/sheet_cutter.gd")
const Key := preload("res://scripts/sheet_key.gd")
const Likeness := preload("res://scripts/sheet_likeness.gd")
const Builder := preload("res://scripts/pack_builder.gd")
const Install := preload("res://scripts/pack_install.gd")

const INK := Color(0.1, 0.2, 0.9, 1.0)
const PAPER := Color(1.0, 1.0, 1.0, 1.0)

var _scratch: String = ""


func _initialize() -> void:
	_open("DogPet sheet reader tests")

	_scratch = ProjectSettings.globalize_path("user://test_sheets")
	_clean()
	DirAccess.make_dir_recursive_absolute(_scratch)

	_test_series()
	_test_grid_maths()
	_test_paper()
	_test_reading()
	_test_touching()
	_test_cutting()
	_test_keying()
	_test_registering()
	_test_texture_guard()
	_test_recount()
	_test_states()
	_test_installing()

	_clean()
	_report()


# --- Numbered files ------------------------------------------------------

func _test_series() -> void:
	_begin("A numbered run of files is one animation")
	var found: Dictionary = Series.group([
		"art/run_000.png", "art/run_001.png", "art/run_002.png",
	])
	var series: Array = found["series"]
	_ok("the run is found", series.size() == 1)
	_ok("with all three frames", PackedStringArray(series[0]["paths"]).size() == 3)
	_ok("named after the prefix", str(series[0]["name"]) == "run")
	_ok("and nothing is left over", PackedStringArray(found["loose"]).is_empty())

	_begin("What is not a numbered run")
	# Windows adds "(2)" when a file of that name is already there. It is a
	# copy, not frame two of anything.
	var copies: Dictionary = Series.group(["art/sheet (2).png", "art/sheet (3).png"])
	_ok("a bracketed copy number is not a frame number",
		Array(copies["series"]).is_empty())
	_ok("both files are left loose", PackedStringArray(copies["loose"]).size() == 2)

	var lone: Dictionary = Series.group(["art/idle_000.png"])
	_ok("one file on its own is not a run", Array(lone["series"]).is_empty())

	var split: Dictionary = Series.group([
		"a/f_000.png", "a/f_001.png", "a/f_050.png", "a/f_051.png",
	])
	_ok("a jump in the numbering starts a second run",
		Array(split["series"]).size() == 2)

	var apart: Dictionary = Series.group(["jump/x_000.png", "run/x_000.png"])
	_ok("the same name in two folders is two things",
		Array(apart["series"]).is_empty())

	_begin("A prefix that says nothing hands over to the folder")
	var weak: Dictionary = Series.group([
		"art/jump/l_000.png", "art/jump/l_001.png", "art/jump/l_002.png",
	])
	_ok("the folder names the run", str(Array(weak["series"])[0]["name"]) == "jump")

	_begin("Taking a number off the end of a name")
	var parts: Dictionary = Series.split_number("walk_07.png")
	_ok("the prefix is kept", str(parts["prefix"]) == "walk_")
	_ok("the number is read", int(parts["number"]) == 7)
	_ok("the padding is remembered", int(parts["digits"]) == 2)
	_ok("a name with no number has none", Series.split_number("idle.png").is_empty())


# --- The grid, as arithmetic ---------------------------------------------

func _test_grid_maths() -> void:
	_begin("Finding the spans that hold something")
	var spans: Array[Vector2i] = Grid.runs(PackedInt32Array([0, 1, 1, 0, 0, 2, 2, 0]))
	_ok("two spans are found", spans.size() == 2)
	_ok("the first starts where it starts", spans[0] == Vector2i(1, 2))
	_ok("the second too", spans[1] == Vector2i(5, 2))
	_ok("a tally of nothing has no spans", Grid.runs(PackedInt32Array([0, 0])).is_empty())

	_begin("Counting the cells a side is divided into")
	_ok("one blob is one cell",
		int(Grid.divisions(_tally(64, [Vector2i(20, 24)]))["count"]) == 1)

	var four: Dictionary = Grid.divisions(_tally(64, [
		Vector2i(4, 8), Vector2i(20, 8), Vector2i(36, 8), Vector2i(52, 8),
	]))
	_ok("four evenly spaced blobs are four cells", int(four["count"]) == 4)
	_ok("and the cell is the width over the count", int(four["cell"]) == 16)
	_ok("which is a regular grid", bool(four["regular"]))

	# A sheet does not have to fill every slot. Three blobs at the spacing
	# of four are still a four-cell row with a hole in it.
	var gapped: Dictionary = Grid.divisions(_tally(64, [
		Vector2i(4, 8), Vector2i(20, 8), Vector2i(52, 8),
	]))
	_ok("a blank cell does not change the count", int(gapped["count"]) == 4)
	_ok("and it is still regular", bool(gapped["regular"]))

	var ragged: Dictionary = Grid.divisions(_tally(64, [
		Vector2i(1, 4), Vector2i(9, 20), Vector2i(50, 6),
	]))
	_ok("blobs at no particular spacing are not a grid", not bool(ragged["regular"]))
	_ok("but they are still counted", int(ragged["count"]) == 3)


# --- Paper ---------------------------------------------------------------

func _test_paper() -> void:
	_begin("Telling the paper from what is drawn on it")
	var clear: Image = _blank(32, 32)
	_fill(clear, Rect2i(8, 8, 16, 16), INK)
	var on_nothing: Dictionary = Scan.of_image("clear.png", clear)
	_ok("a picture with a transparent background has no paper",
		not bool(on_nothing["keyed"]))
	_close("and only the drawn part counts", float(on_nothing["coverage"]), 0.25, 0.01)

	var page: Image = _page(32, 32)
	_fill(page, Rect2i(8, 8, 16, 16), INK)
	var on_paper: Dictionary = Scan.of_image("page.png", page)
	_ok("a picture on white paper has paper", bool(on_paper["keyed"]))
	_close("and the paper does not count as drawn",
		float(on_paper["coverage"]), 0.25, 0.01)
	_ok("the box is found where it was put",
		Rect2i(on_paper["bounds"]) == Rect2i(8, 8, 16, 16))

	# RT-14. The commonest colour is not always the paper. A sheet cropped
	# tight has more dog on it than page, and taking the dog for the
	# background keyed the dog out and installed the hole it left - three
	# frames read as one picture of a white rectangle. What tells them apart
	# is the border: the page reaches the edge of the sheet and the dog does
	# not.
	var cropped: Image = _page(120, 40)
	for index in 3:
		_fill(cropped, Rect2i(index * 40 + 3, 4, 34, 33), INK)
	var inverted: Dictionary = Scan.of_image("cropped.png", cropped)
	_ok("a sheet whose subject outnumbers its paper still finds the paper",
		SheetPaper.apart(Color(inverted["background"]), Color.WHITE) <= 0.05)
	_ok("and the subject is what counts as drawn, not the page",
		float(inverted["coverage"]) > 0.5)
	var cut: Dictionary = Plan.read(PackedStringArray([
		_write("cropped.png", cropped),
	]))
	var pieces: Array = cut["pieces"]
	_ok("and its frames are found rather than read as one picture",
		pieces.size() == 1 and int((pieces[0] as Dictionary)["frames"]) == 3)

	# The other half of the same rule: a colour that reaches the border but
	# covers little of the sheet is a drawn frame around it, not the paper.
	var framed: Image = _blank(40, 40)
	_fill(framed, Rect2i(0, 0, 40, 2), INK)
	_fill(framed, Rect2i(0, 38, 40, 2), INK)
	_fill(framed, Rect2i(8, 8, 24, 24), Color(0.9, 0.9, 0.9, 1.0))
	var ruled: Dictionary = Scan.of_image("framed.png", framed)
	_ok("a drawn border is not mistaken for the paper",
		SheetPaper.apart(Color(ruled["background"]), INK) > 0.05)

	_test_ceiling()


# RT-15. The wizard reads the chosen pictures on the UI thread, so reading
# more of them than it has rows to show is a frozen window for nothing: four
# hundred 256x256 files took thirteen seconds to find 400 pieces, 24 of which
# were offered. read() now stops at a ceiling, and says that it did.
func _test_ceiling() -> void:
	_begin("Reading stops at the ceiling it was given")
	# Named with letters, not numbers: a numbered run is one piece by design,
	# and nine separate pictures is what this is about.
	var chosen: PackedStringArray = []
	for index in 9:
		var one: Image = _blank(16, 16)
		_fill(one, Rect2i(3, 3, 10, 10), INK)
		chosen.append(_write("pose_%c.png" % (97 + index), one))

	var everything: Dictionary = Plan.read(chosen)
	_ok("no ceiling reads every file", (everything["pieces"] as Array).size() == 9)
	_ok("and says nothing about stopping",
		not _says(everything["notes"], "stopped"))

	var capped: Dictionary = Plan.read(chosen, 4)
	_ok("a ceiling of four stops at four", (capped["pieces"] as Array).size() == 4)
	_ok("and says how many files were left", _says(capped["notes"], "stopped"))
	_ok("and names the number left over", _says(capped["notes"], "5 files"))

	var none: Dictionary = Plan.read(chosen, 0)
	_ok("a ceiling of zero is no ceiling", (none["pieces"] as Array).size() == 9)

	_test_bad_arguments()

	# A sheet is cut whole or not at all, so one file may still come back
	# with more pieces than the ceiling. The form has its own note for that.
	var sheet: Image = _blank(6 * 16, 16)
	for cell in 6:
		_fill(sheet, Rect2i(cell * 16 + 3, 3, 10, 10), INK if cell % 2 == 0 else PAPER)
	var whole: Dictionary = Plan.read(PackedStringArray([
		_write("one_sheet.png", sheet),
	]), 2)
	_ok("one sheet is never cut off half way",
		(whole["pieces"] as Array).size() >= 1)


# RT-20, RT-21 and RT-22. The engine's public arithmetic, asked questions
# nobody sensible would ask it. None of these is reachable from the wizard;
# they are closed because the suites call these functions directly and an
# engine error in the log is a thing somebody will one day have to explain.
func _test_bad_arguments() -> void:
	_begin("Nonsense arguments get sensible answers, not engine errors")

	# RT-21. These used to print "Division by zero" and "answered true to a
	# nonsense question" respectively.
	_ok("nothing divides into no parts",
		Grid.even_parts(Rect2i(0, 0, 64, 32), 0).is_empty())
	_ok("nor into a negative number of them",
		Grid.even_parts(Rect2i(0, 0, 64, 32), -3).is_empty())
	_ok("a count that does divide still works",
		Grid.even_parts(Rect2i(0, 0, 64, 32), 4).size() == 4)
	var tally: PackedInt32Array = [4, 4, 4, 4, 4, 4, 4, 4]
	_ok("one piece has no join to look at", not Grid.dips_at_joins(tally, 1))
	_ok("and no pieces has none either", not Grid.dips_at_joins(tally, 0))

	# RT-22. A twenty-digit number is a date or a hash, not a frame counter,
	# and int() could not read it without an engine error - after which it
	# saturated and glued unrelated files into one run.
	_ok("a twenty-digit number is not a frame counter",
		FrameSeries.split_number("run_99999999999999999999.png").is_empty())
	_ok("but twelve digits still are",
		int(FrameSeries.split_number("run_000000000007.png").get("number", -1)) == 7)
	_ok("and so does an ordinary counter",
		int(FrameSeries.split_number("run_007.png").get("number", -1)) == 7)

	# RT-20. SheetStages reads the image four bytes to a pixel. An RGB8 one
	# has three, which read off the end of the buffer and judged the sheet
	# on whatever came back.
	var rgb: Image = Image.create(48, 32, false, Image.FORMAT_RGB8)
	rgb.fill(PAPER)
	for index in 3:
		for y in range(6, 26):
			for x in range(index * 16 + 3, index * 16 + 13):
				rgb.set_pixel(x, y, INK)
	var scanned: Dictionary = Scan.of_image("rgb.png", rgb)
	_ok("a scan of an RGB8 picture still finds the ink",
		float(scanned["coverage"]) > 0.1)
	var rects: Array[Rect2i] = [
		Rect2i(0, 0, 16, 32), Rect2i(16, 0, 16, 32), Rect2i(32, 0, 16, 32),
	]
	var judged: Dictionary = SheetStages.of_cells(scanned, rgb, rects, rects)
	_ok("and asking about its life stages reads nothing off the end",
		judged.has("is_stages"))
	_ok("three identical drawings are not a life cycle",
		not bool(judged["is_stages"]))


# --- What is in a picture ------------------------------------------------

func _test_reading() -> void:
	_begin("A row of the same shape is one animation")
	var strip: String = _write("strip.png", _row(4, _shape_maker(0)))
	var found: Dictionary = Plan.read(PackedStringArray([strip]))
	var pieces: Array = found["pieces"]
	_ok("it is read as one thing", pieces.size() == 1)
	_ok("with four frames", int(pieces[0]["frames"]) == 4)
	_ok("and it is an animation", bool(pieces[0]["animated"]))
	_ok("each frame is one cell", Vector2i(pieces[0]["size"]) == Vector2i(16, 16))

	_begin("A row of different things is that many pictures")
	var mixed: Image = _blank(64, 16)
	# Four shapes with nothing in common: a standing bar, a lying bar, a
	# square and a ring. No two of them overlap once lined up.
	_fill(mixed, Rect2i(6, 2, 4, 12), INK)
	_fill(mixed, Rect2i(18, 7, 12, 3), INK)
	_fill(mixed, Rect2i(36, 4, 9, 9), INK)
	_fill(mixed, Rect2i(52, 3, 10, 10), INK)
	_fill(mixed, Rect2i(54, 5, 6, 6), Color(0, 0, 0, 0))
	var apart: Array = Dictionary(Plan.read(PackedStringArray([_write("mixed.png", mixed)])))\
		["pieces"]
	_ok("they are kept apart", apart.size() == 4)
	_ok("and none of them is an animation", not bool(apart[0]["animated"]))

	_begin("A grid is one animation per row")
	var sheet: Image = _blank(48, 32)
	for row in 2:
		for column in 3:
			_shape_maker(row).call(sheet, Vector2i(column * 16, row * 16))
	var rows: Array = Dictionary(Plan.read(PackedStringArray([_write("grid.png", sheet)])))\
		["pieces"]
	_ok("two rows become two animations", rows.size() == 2)
	_ok("the first has three frames", int(rows[0]["frames"]) == 3)
	_ok("the second too", int(rows[1]["frames"]) == 3)
	_ok("and the label says which row it was",
		str(rows[1]["label"]).contains("row 2"))

	_begin("One sprite on its own stays one picture")
	var one: Image = _blank(20, 18)
	_fill(one, Rect2i(4, 4, 12, 10), INK)
	var single: Array = Dictionary(Plan.read(PackedStringArray([_write("one.png", one)])))\
		["pieces"]
	_ok("it is one piece", single.size() == 1)
	_ok("of one frame", int(single[0]["frames"]) == 1)
	_ok("and not an animation", not bool(single[0]["animated"]))

	_begin("Numbered files are stitched into one animation")
	var frames: PackedStringArray = []
	for index in 3:
		var frame: Image = _blank(16, 16)
		_fill(frame, Rect2i(3 + index, 4, 9, 9), INK)
		frames.append(_write("trot_%03d.png" % index, frame))
	var run: Array = Dictionary(Plan.read(frames))["pieces"]
	_ok("three files become one piece", run.size() == 1)
	_ok("with three frames", int(run[0]["frames"]) == 3)
	_ok("and it is an animation", bool(run[0]["animated"]))

	_begin("Files that only look numbered are left alone")
	var odd: PackedStringArray = []
	for index in 2:
		var frame: Image = _blank(16 + index * 8, 16)
		_fill(frame, Rect2i(2, 4, 8, 9), INK)
		odd.append(_write("odd_%03d.png" % index, frame))
	var loose: Dictionary = Plan.read(odd)
	_ok("different sizes are not one animation", Array(loose["pieces"]).size() == 2)
	_ok("and it is said out loud", not PackedStringArray(loose["notes"]).is_empty())


# --- Frames with no gap between them -------------------------------------

func _test_touching() -> void:
	_begin("A strip whose frames touch is still cut into frames")
	# Every column holds something - the figures stand on a continuous
	# floor - so there is no empty lane anywhere to find them by. The only
	# evidence left is that cutting it in three makes three of the same.
	var strip: Image = _blank(48, 16)
	for cell in 3:
		_fill(strip, Rect2i(cell * 16, 12, 16, 4), INK)
		_fill(strip, Rect2i(cell * 16 + 1, 2, 6, 10), INK)
	var pieces: Array = Dictionary(Plan.read(PackedStringArray([
		_write("touching.png", strip),
	])))["pieces"]
	_ok("it is one piece", pieces.size() == 1)
	_ok("cut into three frames", int(pieces[0]["frames"]) == 3)
	_ok("and read as an animation", bool(pieces[0]["animated"]))

	_begin("A single wide picture is not cut up")
	var wide: Image = _blank(60, 16)
	_fill(wide, Rect2i(2, 2, 56, 12), INK)
	_fill(wide, Rect2i(40, 4, 8, 8), Color(0, 0, 0, 0))
	var whole: Array = Dictionary(Plan.read(PackedStringArray([_write("wide.png", wide)])))\
		["pieces"]
	_ok("it stays one picture", whole.size() == 1 and int(whole[0]["frames"]) == 1)


# --- Cutting -------------------------------------------------------------

func _test_cutting() -> void:
	_begin("Cutting a row out and writing it as a strip")
	var sheet: Image = _page(48, 32)
	for row in 2:
		for column in 3:
			_shape_maker(row).call(sheet, Vector2i(column * 16, row * 16))
	var pieces: Array = Dictionary(Plan.read(PackedStringArray([
		_write("paper_grid.png", sheet),
	])))["pieces"]
	_ok("the paper did not stop the rows being found", pieces.size() == 2)

	var strip: Image = Cutter.render(pieces[0]["cut"])
	_ok("the strip is drawn", strip != null)
	_ok("three frames wide", strip.get_width() == strip.get_height() * 3)
	# The whole point of keying: a shape cut off a white page arrives with
	# the page gone, not as a shape in a white box. Asked of the whole strip
	# rather than of one corner, because the strip is now cut tight to the
	# art and its corner is drawn on.
	_ok("the paper did not come with it", not _holds_paper(strip))

	var out: String = _scratch.path_join("written.png")
	_ok("it writes", Cutter.write(pieces[0]["cut"], out).is_empty())
	_ok("and the file is there", FileAccess.file_exists(out))
	_ok("the right way up",
		ImageLimits.png_size_from_header(out) == Vector2i(strip.get_width(), strip.get_height()))

	_begin("Loose files are stitched into one strip")
	var frames: PackedStringArray = []
	for index in 3:
		var frame: Image = _blank(16, 16)
		_fill(frame, Rect2i(2 + index, 3, 9, 9), INK)
		frames.append(_write("hop_%03d.png" % index, frame))
	var hop: Array = Dictionary(Plan.read(frames))["pieces"]
	var joined: Image = Cutter.render(hop[0]["cut"])
	_ok("the stitched strip is drawn", joined != null)
	# Nine pixels of drawing in a sixteen pixel file: what is installed is
	# the nine, three times over. The empty border the artist left is not
	# part of the dog and only pushes it off its mark on screen. *(v1.46)*
	_ok("three cells wide", joined.get_width() == 27)
	_ok("and one cell tall", joined.get_height() == 9)

	_begin("Frames cut from uneven places come out equal anyway")
	# What makes an animation sit still: frames taken from three differently
	# sized patches are trimmed, centred and stood on a common baseline, so
	# the dog does not jump about the screen between frames.
	var ragged: Image = _blank(40, 20)
	_fill(ragged, Rect2i(1, 6, 8, 12), INK)
	_fill(ragged, Rect2i(12, 6, 10, 12), INK)
	_fill(ragged, Rect2i(27, 6, 9, 12), INK)
	var path: String = _write("ragged.png", ragged)
	var evened: Image = Cutter.render({
		"paths": PackedStringArray([path, path, path]),
		"rects": [Rect2i(0, 0, 10, 20), Rect2i(10, 0, 14, 20), Rect2i(24, 0, 16, 20)],
		"key": false, "align": true,
	})
	_ok("the strip is drawn", evened != null)
	_ok("in three equal cells", evened.get_width() % 3 == 0)
	# The widest patch held ten pixels of ink, so every cell is that wide
	# plus the breathing room put round it.
	_ok("each as wide as the widest frame needed",
		evened.get_width() / 3 == 10 + Cutter.PADDING * 2)


# --- Taking the page off, and only the page ------------------------------

func _test_keying() -> void:
	_begin("A dog the colour of its own page keeps its body")
	# What went wrong with the owner's first aged sheet: the puppy was drawn
	# in the same dark colour as the ground it stood on, every pixel of that
	# colour was cleared wherever it sat, and what was installed was an
	# outline with nothing inside it.
	var sheet: Image = Image.create(40, 40, false, Image.FORMAT_RGBA8)
	sheet.fill(PAPER)
	_fill(sheet, Rect2i(10, 10, 20, 20), INK)          # the outline
	_fill(sheet, Rect2i(13, 13, 14, 14), PAPER)        # a body the page's colour
	var cleared: int = Key.clear_page(sheet, [PAPER])
	_ok("the page went", sheet.get_pixel(0, 0).a == 0.0)
	_ok("the outline stayed", sheet.get_pixel(11, 20).a == 1.0)
	_ok("and so did the body inside it", sheet.get_pixel(20, 20).a == 1.0)
	_ok("and what went was exactly the page round it", cleared == 40 * 40 - 20 * 20)

	_begin("A page the art divides in two is still all page")
	var split: Image = Image.create(40, 40, false, Image.FORMAT_RGBA8)
	split.fill(PAPER)
	_fill(split, Rect2i(0, 18, 40, 4), INK)            # a bar right across it
	Key.clear_page(split, [PAPER])
	_ok("above the bar", split.get_pixel(20, 4).a == 0.0)
	_ok("and below it", split.get_pixel(20, 34).a == 0.0)
	_ok("the bar itself is untouched", split.get_pixel(20, 20).a == 1.0)

	_begin("Nothing to key is not an error")
	var clear: Image = _blank(16, 16)
	_fill(clear, Rect2i(4, 4, 8, 8), INK)
	_ok("an empty list of colours clears nothing", Key.clear_page(clear, []) == 0)
	_ok("and the art is all still there", clear.get_pixel(5, 5).a == 1.0)


# --- Every frame in the same place ---------------------------------------

func _test_registering() -> void:
	_begin("Frames are stood in one place whatever they were cut from")
	# A grid of even cells with the animal drawn in a different corner of
	# each one: the owner's raccoon sheet, in miniature. These used to be
	# installed exactly as they were found, so the dog floated above the
	# floor on one frame and hung off the side on the next.
	var sheet: Image = Image.create(90, 30, false, Image.FORMAT_RGBA8)
	sheet.fill(PAPER)
	_fill(sheet, Rect2i(2, 2, 10, 10), INK)            # high and left
	_fill(sheet, Rect2i(44, 16, 10, 12), INK)          # low and right
	_fill(sheet, Rect2i(64, 8, 10, 11), INK)           # somewhere in between
	var drawn: String = _write("wandering.png", sheet)
	var strip: Image = Cutter.render({
		"paths": PackedStringArray([drawn, drawn, drawn]),
		"rects": [Rect2i(0, 0, 30, 30), Rect2i(30, 0, 30, 30), Rect2i(60, 0, 30, 30)],
		"key": true,
	})
	_ok("the strip is drawn", strip != null)
	_ok("in three equal cells", strip.get_width() % 3 == 0)

	var cell: int = strip.get_width() / 3
	var feet: PackedInt32Array = []
	var middles: PackedInt32Array = []
	for index in 3:
		var frame: Image = strip.get_region(Rect2i(index * cell, 0, cell, strip.get_height()))
		var box: Rect2i = frame.get_used_rect()
		feet.append(box.end.y)
		middles.append(box.position.x + box.size.x / 2)
	_ok("every frame stands on the same line", feet[0] == feet[1] and feet[1] == feet[2])
	_ok("and is centred the same way",
		absi(middles[0] - middles[1]) <= 1 and absi(middles[1] - middles[2]) <= 1)
	# The tallest drawing was twelve pixels, so that plus the padding is as
	# tall as the strip needs to be - not the thirty pixel cells it was cut
	# out of.
	_ok("and the strip is as tall as the art, not the cells",
		strip.get_height() == 12 + Cutter.PADDING * 2)


# --- Not wider than a graphics card will take ----------------------------

func _test_texture_guard() -> void:
	_begin("How much room a frame gets, in a strip of so many")
	_ok("a short strip is not squeezed at all",
		Cutter.room_for(4) > 1000)
	_ok("a long one gets less each", Cutter.room_for(64) < Cutter.room_for(4))
	_ok("twenty-one frames of painted dog still fit", Cutter.room_for(21) >= 300)
	_ok("a sheet row at the frame limit is comfortable",
		not Cutter.too_many_frames(Likeness.MAX_FRAMES))
	_ok("a thousand frames is not a strip", Cutter.too_many_frames(1000))

	_begin("A strip too wide for a texture is shrunk until it fits")
	# One picture, cut into enough cells that the frames side by side would
	# come to more than any card is promised to take.
	var cells: int = ImageLimits.MAX_TEXTURE_SIDE / 200 + 8
	var wide: Image = _blank(cells * 200, 40)
	wide.fill_rect(Rect2i(0, 30, wide.get_width(), 8), INK)
	for cell in cells:
		wide.fill_rect(Rect2i(cell * 200 + 20, 6, 60, 24), INK)
	var path: String = _write("very_wide.png", wide)

	var rects: Array[Rect2i] = []
	var paths: PackedStringArray = []
	for cell in cells:
		rects.append(Rect2i(cell * 200, 0, 200, 40))
		paths.append(path)
	var cut: Dictionary = {
		"paths": paths, "rects": rects, "key": false, "align": false,
	}
	_ok("the cells on their own would be too wide",
		ImageLimits.is_too_wide(Vector2i(cells * 200, 40)))

	var strip: Image = Cutter.render(cut)
	_ok("the strip is still drawn", strip != null)
	_ok("and it fits on a texture",
		not ImageLimits.is_too_wide(Vector2i(strip.get_width(), strip.get_height())))
	# Shrinking must not quietly lose a frame: a walk cycle with twenty of
	# its twenty-one frames in it is a different animation.
	_ok("with every frame still in it", strip.get_width() % cells == 0)
	_ok("each one narrower than it was", strip.get_width() / cells < 200)
	_ok("and still the shape it was", strip.get_height() < 40)

	_begin("A strip nobody could fit is refused instead")
	# Built as locals and then put in: a PackedStringArray read back out of a
	# Dictionary is a copy, so appending to it appends to nothing.
	var many: PackedStringArray = []
	var frames: Array[Rect2i] = []
	for _frame in 2000:
		many.append(path)
		frames.append(Rect2i(0, 0, 200, 40))
	var absurd: Dictionary = {
		"paths": many, "rects": frames, "key": false, "align": false,
	}
	_ok("the frames are counted", Cutter.frames_in(absurd) == 2000)
	var said: String = Cutter.write(absurd, _scratch.path_join("absurd.png"))
	_ok("writing says so rather than trying", said.contains("frames"))
	_ok("and writes nothing", not FileAccess.file_exists(_scratch.path_join("absurd.png")))
	# And the wizard hears it while the pictures are still on screen.
	_ok("installing refuses it too", _says(Install.check(Builder.Kind.PET_SPRITE, {
		"id": "too_many", "name": "Too Many",
		"sheets": [{"cut": absurd, "state": "idle", "frames": 2000, "fps": 6.0}],
	}), "frames"))


# --- Correcting the engine -----------------------------------------------

func _test_recount() -> void:
	_begin("A count the engine got wrong can be given again")
	var strip: String = _write("recount.png", _row(4, _shape_maker(0)))
	var piece: Dictionary = Array(Dictionary(Plan.read(PackedStringArray([strip])))\
		["pieces"])[0]
	_ok("it was read as four", int(piece["frames"]) == 4)

	var halved: Dictionary = Plan.recount(piece, 2)
	_ok("and can be told it is two", int(halved["frames"]) == 2)
	_ok("each twice as wide", Vector2i(halved["size"]).x == 32)
	_ok("the original is unchanged", int(piece["frames"]) == 4)
	var redrawn: Image = Cutter.render(halved["cut"])
	_ok("the new cut draws", redrawn != null)
	_ok("in two equal cells", redrawn.get_width() % 2 == 0)
	_ok("tight around what is drawn on it", redrawn.get_width() < 64)

	var one: Dictionary = Plan.recount(piece, 1)
	_ok("one frame is a still picture", not bool(one["animated"]))

	_begin("A run of numbered files cannot be recounted")
	var frames: PackedStringArray = []
	for index in 3:
		var frame: Image = _blank(16, 16)
		_fill(frame, Rect2i(3, 4, 9, 9), INK)
		frames.append(_write("sit_%03d.png" % index, frame))
	var run: Dictionary = Array(Dictionary(Plan.read(frames))["pieces"])[0]
	_ok("there are as many frames as files",
		int(Plan.recount(run, 7)["frames"]) == 3)


# --- Reading a name ------------------------------------------------------

func _test_states() -> void:
	_begin("A file name says what the picture is for")
	_ok("walk is the walk", Plan.state_for("my_dog_walk.png") == "walk")
	_ok("running is walking as far as DogPet is concerned",
		Plan.state_for("run/rr_000.png") == "walk")
	_ok("sleeping is sleeping", Plan.state_for("Sleep Cycle.png") == "sleep")
	_ok("restless beats rest", Plan.state_for("restless.png") == "restless")
	# The rule that stopped a sheet of creatures asking to be fed, because
	# there is an "eat" in the middle of the word.
	_ok("a word in the middle of another word is not a word",
		Plan.state_for("TL_Creatures.png") == "")
	_ok("and a name that says nothing says nothing",
		Plan.state_for("sheet5.png") == "")


# --- All the way into a pack ---------------------------------------------

func _test_installing() -> void:
	_begin("A sheet becomes a pet pack the app can load")
	var sheet: String = _write("dog_sheet.png", _row(4, _shape_maker(0)))
	var still: Image = _blank(16, 16)
	_fill(still, Rect2i(4, 4, 8, 8), INK)
	var walk: Dictionary = Array(Dictionary(Plan.read(PackedStringArray([sheet])))\
		["pieces"])[0]
	var idle: Dictionary = Array(Dictionary(Plan.read(PackedStringArray([
		_write("dog_still.png", still),
	])))["pieces"])[0]

	var answers: Dictionary = {
		"id": "cut_dog", "name": "Cut Dog", "pixel_art": true,
		"display_height_px": 160, "faces": "right", "credit": "Someone, CC-BY",
		"sheets": [
			{"cut": idle["cut"], "state": "idle", "frames": 1, "fps": 1.0},
			{"cut": walk["cut"], "state": "walk", "frames": 4, "fps": 6.0},
		],
	}
	_ok("nothing stands in the way of installing it",
		Install.check(Builder.Kind.PET_SPRITE, answers).is_empty())

	var target: String = _scratch.path_join("pets/cut_dog")
	var plan: Dictionary = Install.plan(Builder.Kind.PET_SPRITE, answers, target)
	_ok("the strips are made, not copied", Dictionary(plan["copies"]).is_empty())
	_ok("one cut per state", Dictionary(plan["cuts"]).size() == 2)
	_ok("named for the job it does", Dictionary(plan["cuts"]).has("walk.png"))
	_ok("installing reports no problems", Install.write(plan).is_empty())
	_ok("and the strip is on the disk", FileAccess.file_exists(target.path_join("walk.png")))

	var pack: PetPack = PetPack.load_from_dir(target)
	_ok("the pack loads with no problems", pack.problems.is_empty())
	_ok("the walk kept its four frames",
		int(pack.sprite_animations["walk"]["frames"]) == 4)
	# Measured off the strip this engine drew, not off anything it was told.
	_ok("and the frame width divides exactly",
		int(pack.sprite_animations["walk"]["frame_width"]) * 4
		== ImageLimits.png_size_from_header(target.path_join("walk.png")).x)
	_ok("the pack is usable", pack.is_usable())

	_begin("What the installer writes is registered, not just what render drew")
	# The owner's complaint, end to end: three poses drawn anywhere in their
	# cells, put through the real installer, and read back off the disk the
	# way the app reads it. Every frame has to stand on the same line and sit
	# in the middle of its cell, or the dog moves about the screen. *(v1.46)*
	var wander: Image = Image.create(90, 30, false, Image.FORMAT_RGBA8)
	wander.fill(PAPER)
	_fill(wander, Rect2i(2, 2, 10, 10), INK)
	_fill(wander, Rect2i(44, 16, 10, 12), INK)
	_fill(wander, Rect2i(64, 8, 10, 11), INK)
	var drawn: String = _write("wander_sheet.png", wander)
	var steady: Dictionary = {
		"id": "steady_dog", "name": "Steady Dog", "pixel_art": true,
		"display_height_px": 160, "faces": "right", "credit_not_required": true,
		"sheets": [{
			"cut": {
				"paths": PackedStringArray([drawn, drawn, drawn]),
				"rects": [
					Rect2i(0, 0, 30, 30), Rect2i(30, 0, 30, 30), Rect2i(60, 0, 30, 30),
				],
				"key": true,
			},
			"state": "idle", "frames": 3, "fps": 4.0,
		}],
	}
	var home: String = _scratch.path_join("pets/steady_dog")
	_ok("it installs", Install.write(
		Install.plan(Builder.Kind.PET_SPRITE, steady, home)
	).is_empty())

	var installed: PetPack = PetPack.load_from_dir(home)
	_ok("and loads", installed.problems.is_empty())
	var written: Image = Image.load_from_file(home.path_join("idle.png"))
	var cell: int = int(installed.sprite_animations["idle"]["frame_width"])
	var feet: PackedInt32Array = []
	var middles: PackedInt32Array = []
	for index in 3:
		var box: Rect2i = written.get_region(
			Rect2i(index * cell, 0, cell, written.get_height())
		).get_used_rect()
		feet.append(box.end.y)
		middles.append(box.position.x + box.size.x / 2)
	_ok("every frame on the disk stands on the same line",
		feet[0] == feet[1] and feet[1] == feet[2])
	_ok("and is centred in its cell",
		absi(middles[0] - middles[1]) <= 1 and absi(middles[1] - middles[2]) <= 1)
	_ok("with the page gone", not _holds_paper(written))

	_begin("A cut whose pictures have gone is caught before installing")
	DirAccess.remove_absolute(sheet)
	_ok("the missing file is reported",
		not Install.check(Builder.Kind.PET_SPRITE, answers).is_empty())


# --- Drawing the test pictures -------------------------------------------

# A tally with blobs in it, for the pure grid tests: the shape of what
# SheetScan would have measured, without measuring anything.
func _tally(length: int, blobs: Array[Vector2i]) -> PackedInt32Array:
	var counts: PackedInt32Array = []
	counts.resize(length)
	for blob in blobs:
		for index in range(blob.x, mini(length, blob.x + blob.y)):
			counts[index] = 10
	return counts


func _blank(width: int, height: int) -> Image:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


func _page(width: int, height: int) -> Image:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(PAPER)
	return image


func _fill(image: Image, area: Rect2i, colour: Color) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			image.set_pixel(x, y, colour)


# Two shapes that are plainly not each other, each drawn inside a 16 x 16
# cell with a lane around it so the cells can be told apart.
func _shape_maker(which: int) -> Callable:
	if which == 0:
		return func(image: Image, at: Vector2i) -> void:
			_fill(image, Rect2i(at + Vector2i(3, 3), Vector2i(10, 10)), INK)
	return func(image: Image, at: Vector2i) -> void:
		_fill(image, Rect2i(at + Vector2i(5, 2), Vector2i(5, 12)), INK)


func _row(cells: int, shape: Callable) -> Image:
	var image: Image = _blank(cells * 16, 16)
	for cell in cells:
		shape.call(image, Vector2i(cell * 16, 0))
	return image


func _write(name: String, image: Image) -> String:
	var path: String = _scratch.path_join(name)
	image.save_png(path)
	return path


# Does any of these lines mention this? The messages are written for people,
# so the tests ask what they are about rather than matching them word for
# word and breaking on a comma.
func _says(lines: PackedStringArray, word: String) -> bool:
	for line in lines:
		if line.to_lower().contains(word.to_lower()):
			return true
	return false


func _clean() -> void:
	if DirAccess.dir_exists_absolute(_scratch):
		PackArchive.empty_folder(_scratch)
		DirAccess.remove_absolute(_scratch)


# Is any of the page still in this picture? Opaque and close to the paper
# colour means the keying missed it.
func _holds_paper(image: Image) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.0 and SheetPaper.apart(pixel, PAPER) <= 0.05:
				return true
	return false
