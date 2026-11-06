extends SceneTree
## RT probe P7: RT-14 on the owner's own art.
##
## probe_p3 proved the inversion on a drawn blob. This does it on the real
## thing: three poses cut out of art-source/pet_poses_sprite_sheet.png and
## laid edge to edge on the sheet's own cream paper, which is exactly what an
## artist does before handing a strip to the wizard. Trimmed tight, the dog
## covers more of the strip than the page does - and that was the whole bug.
##
## Then it installs that strip through PackInstall, reads the pack back with
## PetPack, and writes out what actually landed, so the two runs - with the
## fix and without - can be put side by side.
##
## Usage:
##   godot --headless --path . --script res://redteam/tests/probe_p7_real_art.gd \
##       -- --out <folder> --tag <before|after>

const Builder := preload("res://scripts/pack_builder.gd")
const Install := preload("res://scripts/pack_install.gd")

const SHEET := "art-source/pet_poses_sprite_sheet.png"
const MARGIN := 6

var out_dir: String = ""
var tag: String = "after"
var work: String = ""


func _init() -> void:
	_read_arguments()
	work = OS.get_user_data_dir().path_join("rt_p7")
	DirAccess.make_dir_recursive_absolute(work)
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)

	print("--- %s ---" % tag)
	var strip: String = _make_tight_strip()
	if strip.is_empty():
		quit(1)
		return
	_what_the_reader_sees(strip)
	_install_it(strip, "real")
	_the_real_sheet()

	# And the case that actually trips it, kept beside the real one so the
	# difference between "art that happens to be safe" and "art that is not"
	# is visible rather than argued about.
	print("")
	var tight: String = _make_flat_colour_strip()
	_what_the_reader_sees(tight)
	_install_it(tight, "flat")
	quit(0)


func _read_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--out" and index + 1 < args.size():
			out_dir = args[index + 1]
		elif args[index] == "--tag" and index + 1 < args.size():
			tag = args[index + 1]


# --- Making the strip out of real poses -----------------------------------

# Three poses off the owner's sheet, trimmed to the ink and laid side by side
# with a few pixels of its own cream paper around them.
func _make_tight_strip() -> String:
	if not FileAccess.file_exists(SHEET):
		print("  %s is not here, so there is nothing real to test with" % SHEET)
		return ""
	var paper: Color = Color(SheetScan.read(SHEET)["background"])
	var found: Dictionary = SheetPlan.read(PackedStringArray([SHEET]))
	var pieces: Array = found["pieces"]
	print("  the sheet itself holds %d pieces; taking the first three" % pieces.size())
	if pieces.size() < 3:
		return ""

	var poses: Array[Image] = []
	for index in 3:
		var drawn: Image = SheetCutter.render((pieces[index] as Dictionary)["cut"])
		if drawn == null:
			print("  pose %d could not be rendered" % (index + 1))
			return ""
		# Trimmed to what is actually drawn, which is what makes the crop
		# tight and the dog the majority of the picture.
		var box: Rect2i = drawn.get_used_rect()
		poses.append(drawn if box.size.x <= 0 else drawn.get_region(box))

	var cell := Vector2i.ZERO
	for pose in poses:
		cell.x = maxi(cell.x, pose.get_width())
		cell.y = maxi(cell.y, pose.get_height())
	cell += Vector2i(MARGIN, MARGIN) * 2

	# Scaled down to something a pet pack would really use. The poses are
	# 850 pixels wide off a sheet this size, and nobody ships that.
	var shrink: float = 220.0 / float(cell.y)
	var strip: Image = Image.create(
		cell.x * poses.size(), cell.y, false, Image.FORMAT_RGBA8
	)
	# On the sheet's own paper, not on white: a cream page is what the art
	# came on, and keying it is the job.
	strip.fill(Color(paper.r, paper.g, paper.b, 1.0))
	for index in poses.size():
		var pose: Image = poses[index]
		# Blended, not blitted: blit copies the alpha too and would punch the
		# pose's transparent corners straight through the page, leaving a
		# strip that is already part-transparent. An artist flattening layers
		# gets a solid page with the dog composited onto it, which is the
		# shape the wizard is really handed.
		strip.blend_rect(
			pose, Rect2i(0, 0, pose.get_width(), pose.get_height()),
			Vector2i(
				index * cell.x + (cell.x - pose.get_width()) / 2,
				cell.y - pose.get_height() - MARGIN
			)
		)
	strip.resize(
		int(float(strip.get_width()) * shrink),
		int(float(strip.get_height()) * shrink),
		Image.INTERPOLATE_LANCZOS
	)

	var path: String = work.path_join("real_strip.png")
	strip.save_png(path)
	_also_save(strip, "1-source-strip")
	print("  built a %d x %d three-pose strip on the sheet's own cream paper" % [
		strip.get_width(), strip.get_height(),
	])
	return path


# A flat-coloured cartoon dog, cropped tight: three frames, one flat body
# colour, a thin page around it. Flat fills are how cartoon art is drawn, and
# they are what makes the subject's single commonest colour beat the page's.
func _make_flat_colour_strip() -> String:
	print("  and a flat-coloured cartoon strip, cropped tight:")
	var cell: int = 150
	var strip: Image = Image.create(cell * 3, cell, false, Image.FORMAT_RGBA8)
	strip.fill(Color.WHITE)
	var body := Color8(74, 56, 44)
	for index in 3:
		var left: int = index * cell
		# Body, head and a leg that moves, all one flat colour.
		_box(strip, Rect2i(left + 8, 30, cell - 16, cell - 48), body)
		_box(strip, Rect2i(left + 14, 10, 54, 34), body)
		_box(strip, Rect2i(left + 20 + index * 24, cell - 18, 44, 18), body)
	var path: String = work.path_join("flat_strip.png")
	strip.save_png(path)
	_also_save(strip, "3-flat-source")
	return path


func _box(image: Image, area: Rect2i, colour: Color) -> void:
	var clipped: Rect2i = area.intersection(
		Rect2i(0, 0, image.get_width(), image.get_height())
	)
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			image.set_pixel(x, y, colour)


# --- What the engine makes of it ------------------------------------------

func _what_the_reader_sees(strip: String) -> void:
	var scan: Dictionary = SheetScan.read(strip)
	var paper: Color = scan["background"]
	print("  paper read as #%s, %.1f%% of the strip counted as drawn on" % [
		paper.to_html(false), float(scan["coverage"]) * 100.0,
	])
	var found: Dictionary = SheetPlan.read(PackedStringArray([strip]))
	for piece in found["pieces"]:
		print("  read as: %s" % str((piece as Dictionary)["label"]))


# --- Installing it, and looking at what landed ----------------------------

func _install_it(strip: String, which: String) -> void:
	var found: Dictionary = SheetPlan.read(PackedStringArray([strip]))
	var pieces: Array = found["pieces"]
	if pieces.is_empty():
		print("  nothing to install")
		return
	var piece: Dictionary = pieces[0]
	var target: String = work.path_join("pack_%s" % which)
	PackArchive.empty_folder(target)

	var answers: Dictionary = {
		"id": "pack_%s" % which, "name": "Pack", "credit_not_required": true,
		"pixel_art": false, "display_height_px": 200, "faces": "right",
		"sheets": [{
			"cut": piece["cut"], "state": "idle", "stage": "",
			"frames": int(piece["frames"]), "fps": 3.0,
		}],
	}
	var problems: PackedStringArray = Install.check(Builder.Kind.PET_SPRITE, answers)
	print("  check: %s" % ("nothing wrong" if problems.is_empty() else str(problems)))
	var wrote: PackedStringArray = Install.write(
		Install.plan(Builder.Kind.PET_SPRITE, answers, target)
	)
	print("  write: %s" % ("installed" if wrote.is_empty() else str(wrote)))

	var pack: PetPack = PetPack.load_from_dir(target)
	if pack == null or not pack.is_usable():
		print("  the pack does not load")
		return
	var spec: Dictionary = pack.sprite_animations.get("idle", {})
	print("  pet.json: idle = %s, %d frames of %dx%d" % [
		str(spec.get("file", "-")), int(spec.get("frames", 0)),
		int(spec.get("frame_width", 0)), int(spec.get("frame_height", 0)),
	])

	# And what is actually in the file the pack now points at.
	var installed: Image = Image.load_from_file(
		target.path_join(str(spec.get("file", "")))
	)
	if installed == null:
		print("  the installed strip cannot be read")
		return
	installed.convert(Image.FORMAT_RGBA8)
	_also_save(installed, "%s-installed" % ("2-real" if which == "real" else "4-flat"))
	_describe_what_landed(installed)


# The thing that matters: is the dog in the file, or the hole it left?
func _describe_what_landed(image: Image) -> void:
	var clear: int = 0
	var opaque: int = 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a < 0.03:
				clear += 1
			else:
				opaque += 1
	var total: int = maxi(1, clear + opaque)
	print("  the installed file is %.1f%% drawing, %.1f%% transparent" % [
		100.0 * float(opaque) / float(total), 100.0 * float(clear) / float(total),
	])
	# A dog cut off a page keeps roughly the share of the strip it covered.
	# Far less than that means the page was kept and the dog thrown away.
	if float(opaque) / float(total) < 0.25:
		print("  *** almost nothing is drawn: the dog was keyed out as the paper ***")


# --- The sheet the owner really has, before and after ---------------------

# A regression check on real art: the fix changes how every sheet with paper
# on it is read, so the owner's own sheet has to read the same as it did.
func _the_real_sheet() -> void:
	var scan: Dictionary = SheetScan.read(SHEET)
	var found: Dictionary = SheetPlan.read(PackedStringArray([SHEET]))
	print("  the owner's sheet: paper #%s, %.1f%% drawn, %d pieces" % [
		Color(scan["background"]).to_html(false),
		float(scan["coverage"]) * 100.0,
		(found["pieces"] as Array).size(),
	])


func _also_save(image: Image, name: String) -> void:
	if out_dir.is_empty():
		return
	image.save_png(out_dir.path_join("%s-%s.png" % [tag, name]))
