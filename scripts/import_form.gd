class_name ImportForm
extends RefCounted
## The questions the import wizard asks, and the answers read back out.
##
## Everything a pet.json or scene.json needs that cannot be measured from the
## files themselves is asked here, in words rather than in field names: "how
## big is the dog", not "target_height"; "where in the room", not "x: 0.78".
## The numbers those answers turn into are PackBuilder business.
##
## Built in code because the questions depend on what was chosen - one row
## per picture, and a different set of rows for a dog than for a room. Holds
## no files and writes nothing; the wizard reads answers() when it is ready.

signal changed()

const Builder := preload("res://scripts/pack_builder.gd")

## How big the dog ends up, in the 3D units target_height is counted in.
const SIZES: Array[float] = [0.75, 1.0, 1.3]
const SIZE_LABELS: PackedStringArray = ["A small dog", "A normal dog", "A big dog"]

## Where a prop sits, as fractions of the window. x is its middle, y is the
## bottom edge, so a prop sits on the floor rather than floating.
const ACROSS: Array[float] = [0.2, 0.5, 0.8]
const ACROSS_LABELS: PackedStringArray = ["On the left", "In the middle", "On the right"]
const DEPTH: Array[float] = [0.62, 0.74, 0.86]
const DEPTH_LABELS: PackedStringArray = ["Towards the back", "Mid floor", "Near the front"]
const PROP_SCALES: Array[int] = [2, 3, 5]
const PROP_SCALE_LABELS: PackedStringArray = ["Small", "Medium", "Large"]

## The jobs a picture can be given in a room.
const JOB_UNUSED := "Not used"
const JOB_BACKGROUND := "The whole background"
const JOB_WALL := "Wall tile, repeated"
const JOB_FLOOR := "Floor tile, repeated"
const JOB_PROP := "A thing in the room"
const ROOM_JOBS: PackedStringArray = [
	JOB_BACKGROUND, JOB_WALL, JOB_FLOOR, JOB_PROP, JOB_UNUSED,
]

## What a prop can be for. The dog walks to the bowl to eat and chases the toy.
const PROP_ROLES: PackedStringArray = ["", ScenePack.ROLE_FOOD_BOWL, ScenePack.ROLE_TOY,
	ScenePack.ROLE_VET_TABLE]
const PROP_ROLE_LABELS: PackedStringArray = [
	"Just scenery", "The food bowl", "The toy to chase", "The vet table",
]

## The most pieces one trip through the wizard asks about. A tile sheet can
## hold a hundred, and a form a hundred rows long is not a form.
const MAX_PIECES := 24

## Art drawn no taller than this is pixel art, and should keep its edges.
const PIXEL_ART_HEIGHT := 96

## A room can be painted in code instead of made of pictures, which is how
## the shipped play and walk scenes are drawn. That makes a couple of props,
## or nothing at all, enough for a whole room.
const DRAWN_LABELS: PackedStringArray = [
	"From the pictures below", "Drawn: an indoor room",
	"Drawn: a grassy yard", "Drawn: a park with a path",
]
const DRAWN_STYLES: PackedStringArray = ["", "room", "yard", "park"]

const ROLE_BLURBS: Dictionary = {
	"home": "Home - where the dog lives",
	"eat": "Eat - where it is fed",
	"play": "Play - where it plays",
	"walk": "Walk - where it is walked",
	"vet": "Vet - where it is taken when ill",
}

var kind: int = Builder.Kind.UNKNOWN

var _name: LineEdit = null
var _folder: LineEdit = null
var _folder_touched: bool = false
var _own_work: CheckBox = null
var _credit: LineEdit = null
var _license: LineEdit = null
var _license_url: LineEdit = null
var _source_url: LineEdit = null

var _size: OptionButton = null
var _facing: HSlider = null
var _pixel_art: CheckBox = null
var _display_px: SpinBox = null
var _faces: OptionButton = null
var _role: OptionButton = null
var _drawn: OptionButton = null
var _floor_ratio: SpinBox = null
var _tile_scale: SpinBox = null

## One entry per chosen picture: its path and the controls asking about it.
var _pictures: Array[Dictionary] = []

## What the sheet reader found in the chosen pictures, for a sprite pack.
var _found: Array[Dictionary] = []

## The job the youngest drawing of the current life cycle was given, so the
## older ones can be offered the same one.
var _last_staged_state: String = "idle"

var _model: String = ""
var _extras: PackedStringArray = []


## Build the questions for a kind into a column. Called once; the wizard
## throws the column away and builds again if the kind changes.
func build(into: VBoxContainer, which_kind: int, sources: Dictionary) -> void:
	kind = which_kind
	_pictures.clear()
	_found.clear()
	_model = ""
	_extras = PackedStringArray()

	var images: PackedStringArray = sources["images"]
	var models: PackedStringArray = sources["models"]
	if not models.is_empty():
		_model = models[0]
		_extras = sources["extras"]
		# Only one dog per pack, so any further models are companion files as
		# far as this is concerned - a .gltf beside its own .bin, usually.
		for index in range(1, models.size()):
			_extras.append(models[index])

	_build_naming(into, images, models)
	match kind:
		Builder.Kind.PET_MODEL:
			_build_model_questions(into)
		Builder.Kind.PET_SPRITE:
			_build_sprite_questions(into, images)
		Builder.Kind.ROOM:
			_build_room_questions(into, images)
	_build_credits(into)


## Everything the wizard needs to install this pack.
func answers() -> Dictionary:
	var given: Dictionary = {
		"id": Builder.clean_id(_folder.text),
		"name": _name.text.strip_edges(),
		"credit": _credit.text.strip_edges(),
		"credit_not_required": _own_work.button_pressed,
		"license": _license.text.strip_edges(),
		"license_url": _license_url.text.strip_edges(),
		"source_url": _source_url.text.strip_edges(),
	}
	match kind:
		Builder.Kind.PET_MODEL:
			given["model"] = _model
			given["extras"] = _extras
			given["target_height"] = SIZES[maxi(0, _size.selected)]
			given["rotation_y_degrees"] = _facing.value
		Builder.Kind.PET_SPRITE:
			given["pixel_art"] = _pixel_art.button_pressed
			given["display_height_px"] = int(_display_px.value)
			given["faces"] = "right" if _faces.selected == 0 else "left"
			given["sheets"] = _sheets()
		Builder.Kind.ROOM:
			given.merge(_room_answers())
	return given


## How tall the dog is asked to be, so the preview can match it.
func wanted_height() -> float:
	return SIZES[maxi(0, _size.selected)] if _size != null else 1.0


## Which way the dog is being turned, for the live preview.
func facing_degrees() -> float:
	return _facing.value if _facing != null else 0.0


# --- The questions -------------------------------------------------------

func _build_naming(into: VBoxContainer, images: PackedStringArray, models: PackedStringArray) -> void:
	var first: String = models[0] if not models.is_empty() else (
		images[0] if not images.is_empty() else "pack"
	)
	var suggested: String = Builder.suggest_name(first)
	_name = _line(into, "Call it", suggested, "The name shown in the settings list.")
	_folder = _line(into, "Folder", Builder.clean_id(suggested),
		"The folder it will live in, inside assets.")
	_folder.text_changed.connect(func(_text: String) -> void: _folder_touched = true)
	_name.text_changed.connect(func(text: String) -> void:
		if not _folder_touched:
			_folder.text = Builder.clean_id(text)
		changed.emit()
	)


func _build_model_questions(into: VBoxContainer) -> void:
	into.add_child(UiBits.heading("The dog", 15))
	into.add_child(UiBits.dim(
		"DogPet measures the model and scales it for you, so it does not matter"
		+ " what size it was made at.", 11
	))
	_size = _choice(into, "How big", SIZE_LABELS, 1)

	var row: HBoxContainer = UiBits.row(into)
	row.add_child(UiBits.dim("Which way", 13, 110, false))
	_facing = HSlider.new()
	_facing.min_value = -180.0
	_facing.max_value = 180.0
	_facing.step = 1.0
	_facing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_facing)
	var reading: Label = UiBits.dim("0 degrees", 11, 80, false)
	row.add_child(reading)
	_facing.value_changed.connect(func(value: float) -> void:
		reading.text = "%d degrees" % int(value)
		changed.emit()
	)
	into.add_child(UiBits.dim(
		"Drag until the dog in the picture above is looking at you.", 11
	))


func _build_sprite_questions(into: VBoxContainer, images: PackedStringArray) -> void:
	into.add_child(UiBits.heading("The pictures", 15))

	# The sheet reader has already been over these: it has found the rows of
	# a grid sheet, the runs of numbered files, and which of them hold one
	# animal moving rather than several different ones. What is left to ask
	# is what each piece is for.
	var found: Dictionary = SheetPlan.read(images)
	_found = found["pieces"]
	into.add_child(UiBits.dim(
		"DogPet has looked at %d file%s and found %d thing%s in %s. Give the ones you"
		% [
			images.size(), "" if images.size() == 1 else "s",
			_found.size(), "" if _found.size() == 1 else "s",
			"it" if images.size() == 1 else "them",
		]
		+ " want a job. Anything cut in the wrong place can be given a different"
		+ " number of frames here.", 11
	))
	for note in PackedStringArray(found["notes"]):
		into.add_child(UiBits.dim(note, 11, 0.0, true, Color(1.0, 0.85, 0.4)))

	var states: PackedStringArray = ["Not used"]
	for state in PetPack.VALID_STATES:
		states.append(state.capitalize())

	var taken: PackedStringArray = []
	var tallest: int = 0
	for index in mini(_found.size(), MAX_PIECES):
		var piece: Dictionary = _found[index]
		tallest = maxi(tallest, Vector2i(piece["size"]).y)
		var frames: int = int(piece["frames"])

		into.add_child(UiBits.dim(str(piece["label"]), 12))
		var row: HBoxContainer = UiBits.row(into)
		var job: OptionButton = _picker(row, states, _suggest(piece, index, states, taken))
		row.add_child(UiBits.dim("frames", 11, 0.0, false))
		# A run of numbered files has exactly as many frames as it has files,
		# so there is nothing there to correct.
		var count: SpinBox = _spin(row, frames, 1, 64, 1)
		count.editable = PackedStringArray(piece["cut"]["paths"]).size() <= 1 or frames == 1
		row.add_child(UiBits.dim("per second", 11, 0.0, false))
		var fps: SpinBox = _spin(row, Builder.DEFAULT_FPS if frames > 1 else 1.0, 1, 30, 1)
		_pictures.append({"piece": index, "job": job, "frames": count, "fps": fps})

	if _found.size() > MAX_PIECES:
		into.add_child(UiBits.dim(
			"There are %d more pieces in there. Install these, then add the rest."
			% (_found.size() - MAX_PIECES), 11, 0.0, true, Color(1.0, 0.85, 0.4)
		))

	# Small art is pixel art, near enough: nobody paints a dog 48 pixels tall
	# and wants it smoothed. It is a tick box, so a wrong guess costs a click.
	_pixel_art = _check(into, "Pixel art - keep the hard edges", tallest <= PIXEL_ART_HEIGHT)
	_display_px = _spin_row(into, "On screen", PetPack.DEFAULT_DISPLAY_HEIGHT_PX, 32, 480, 8,
		"How tall the dog is drawn, in pixels.")
	_faces = _choice(into, "The art faces", ["Right", "Left"], 0)


# Which job to offer a piece. The engine's reading of its name comes first -
# a file called walk.png is the walk - and the first piece left over is
# offered as idle, which is the one a pet pack cannot do without.
func _suggest(
	piece: Dictionary, index: int, states: PackedStringArray, taken: PackedStringArray
) -> int:
	var wanted: String = str(piece["state"])
	# The drawings of one life cycle are the same job at different ages, so
	# they are meant to share a state rather than compete for it: the four
	# sleeping dogs are all "sleep". Only the youngest claims the name, and
	# the rest fall in behind it.
	var staged: bool = not str(piece.get("stage", "")).is_empty()
	if staged and int(piece.get("stage_index", -1)) > 0:
		return maxi(0, states.find(_last_staged_state.capitalize()))
	if not wanted.is_empty() and not taken.has(wanted):
		taken.append(wanted)
		_last_staged_state = wanted
		return maxi(0, states.find(wanted.capitalize()))
	if index == 0 and not taken.has("idle"):
		taken.append("idle")
		_last_staged_state = "idle"
		return maxi(0, states.find("Idle"))
	if staged:
		# A life cycle whose state could not be read from the name still
		# wants one job across all of its ages; idle is the safe one.
		_last_staged_state = "idle"
		return maxi(0, states.find("Idle"))
	return 0


func _build_room_questions(into: VBoxContainer, images: PackedStringArray) -> void:
	var labels: PackedStringArray = []
	for role in ScenePack.ROLES:
		labels.append(str(ROLE_BLURBS.get(role, role.capitalize())))
	_role = _choice(into, "Used for", labels, 0)
	into.add_child(UiBits.dim(
		"Rooms do not replace each other. Add a second kitchen and you choose"
		+ " between them in Settings.", 11
	))

	_drawn = _choice(into, "Background", DRAWN_LABELS, 0)
	into.add_child(UiBits.dim(
		"A drawn background needs no pictures at all - the pictures below then only"
		+ " put things in the room.", 11
	))

	into.add_child(UiBits.heading("The pictures", 15))
	for index in images.size():
		var path: String = images[index]
		var size: Vector2i = ImageLimits.png_size_from_header(path)
		into.add_child(UiBits.dim("%s   (%d x %d)" % [path.get_file(), size.x, size.y], 12))
		var row: HBoxContainer = UiBits.row(into)
		# A big picture is almost certainly the backdrop; a small one is a
		# tile or a thing standing in the room.
		var guess: int = 0 if index == 0 and size.x >= 200 else ROOM_JOBS.size() - 1
		if index == 0 and size.x < 200:
			guess = ROOM_JOBS.find(JOB_PROP)
		var job: OptionButton = _picker(row, ROOM_JOBS, guess)
		var across: OptionButton = _picker(row, ACROSS_LABELS, 1)
		var depth: OptionButton = _picker(row, DEPTH_LABELS, 1)
		var prop_size: OptionButton = _picker(row, PROP_SCALE_LABELS, 1)
		var what: OptionButton = _picker(row, PROP_ROLE_LABELS, 0)
		var picture: Dictionary = {
			"path": path, "job": job, "across": across, "depth": depth,
			"scale": prop_size, "role": what,
		}
		_pictures.append(picture)
		job.item_selected.connect(func(_index: int) -> void:
			_only_for_props(picture)
			changed.emit()
		)
		_only_for_props(picture)

	_floor_ratio = _spin_row(into, "Floor takes", 38, 5, 95, 1,
		"Percent of the window the floor fills, when wall and floor tiles are used.")
	_tile_scale = _spin_row(into, "Tiles at", 4, 1, 16, 1, "How many times each tile is enlarged.")


func _build_credits(into: VBoxContainer) -> void:
	into.add_child(UiBits.heading("Where it came from", 15))
	into.add_child(UiBits.dim(
		"Credit is not decoration: a lot of free art may only be used while its"
		+ " credit stays visible. Whatever is typed here is shown in Settings, About.", 11
	))
	# Your own work is the case the credit rule was not written for. Ticking
	# this writes credit_not_required into the pack, and the app stops asking.
	_own_work = _check(into, "My own art - no credit needed", false)
	_credit = _line(into, "Credit", "", "Who made it, and under what licence.")
	_license = _line(into, "Licence", "", "CC-BY 3.0, CC0, and so on. Optional.")
	_license_url = _line(into, "Licence link", "", "Optional.")
	_source_url = _line(into, "Found at", "", "Optional.")


# --- Reading the answers back --------------------------------------------

func _sheets() -> Array:
	var sheets: Array = []
	for picture in _pictures:
		var job: OptionButton = picture["job"]
		if job.selected <= 0:
			continue
		# The piece carries its own instructions for being cut out, so what
		# goes into the pack is a strip made to measure rather than whatever
		# file it happened to come from.
		var piece: Dictionary = SheetPlan.recount(
			_found[int(picture["piece"])], int((picture["frames"] as SpinBox).value)
		)
		sheets.append({
			"cut": piece["cut"],
			"state": PetPack.VALID_STATES[job.selected - 1],
			# Empty for ordinary art. When the sheet reader found a life
			# cycle, this is which age the piece is, and PackBuilder gathers
			# the ages of one state back into a "stages" list.
			"stage": str(piece.get("stage", "")),
			"frames": int(piece["frames"]),
			"fps": float((picture["fps"] as SpinBox).value),
		})
	return sheets


func _room_answers() -> Dictionary:
	var given: Dictionary = {
		"role": ScenePack.ROLES[maxi(0, _role.selected)],
		"floor_ratio": _floor_ratio.value / 100.0,
		"tile_scale": int(_tile_scale.value),
		"background": Builder.BG_IMAGE,
		"props": [],
	}
	var drawn: int = maxi(0, _drawn.selected)
	if drawn > 0:
		given["background"] = Builder.BG_GENERATED
		given["style"] = DRAWN_STYLES[drawn]

	var props: Array = []
	for picture in _pictures:
		var path: String = str(picture["path"])
		match ROOM_JOBS[maxi(0, (picture["job"] as OptionButton).selected)]:
			JOB_BACKGROUND:
				if drawn == 0:
					given["image"] = path
			JOB_WALL:
				if drawn == 0:
					given["wall"] = path
			JOB_FLOOR:
				if drawn == 0:
					given["floor"] = path
			JOB_PROP:
				props.append({
					"path": path,
					"x": ACROSS[maxi(0, (picture["across"] as OptionButton).selected)],
					"y": DEPTH[maxi(0, (picture["depth"] as OptionButton).selected)],
					"scale": PROP_SCALES[maxi(0, (picture["scale"] as OptionButton).selected)],
					"role": PROP_ROLES[maxi(0, (picture["role"] as OptionButton).selected)],
				})
	given["props"] = props
	# Two tiles describe a tiled room; one picture is simply the backdrop.
	if given.has("wall") and given.has("floor"):
		given["background"] = Builder.BG_TILED
	return given


# A prop is the only job with a place and a purpose, so the rest of the row
# is greyed out until that is what the picture is.
func _only_for_props(picture: Dictionary) -> void:
	var is_prop: bool = (
		ROOM_JOBS[maxi(0, (picture["job"] as OptionButton).selected)] == JOB_PROP
	)
	for key in ["across", "depth", "scale", "role"]:
		(picture[key] as OptionButton).disabled = not is_prop


# --- The small pieces ----------------------------------------------------

func _line(into: VBoxContainer, label: String, value: String, hint: String) -> LineEdit:
	var row: HBoxContainer = UiBits.row(into)
	row.add_child(UiBits.dim(label, 13, 110, false))
	var field := LineEdit.new()
	field.text = value
	field.placeholder_text = hint
	field.tooltip_text = hint
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(func(_text: String) -> void: changed.emit())
	row.add_child(field)
	return field


func _spin(into: Control, value: float, low: float, high: float, step: float) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.value = value
	box.custom_minimum_size = Vector2(70, 0)
	box.value_changed.connect(func(_value: float) -> void: changed.emit())
	into.add_child(box)
	return box


func _spin_row(
	into: VBoxContainer, label: String, value: float, low: float, high: float,
	step: float, hint: String
) -> SpinBox:
	var row: HBoxContainer = UiBits.row(into)
	row.add_child(UiBits.dim(label, 13, 110, false))
	var box: SpinBox = _spin(row, value, low, high, step)
	row.add_child(UiBits.dim(hint, 11))
	return box


func _picker(into: Control, items: PackedStringArray, selected: int) -> OptionButton:
	var picker := OptionButton.new()
	for item in items:
		picker.add_item(item)
	picker.select(clampi(selected, 0, items.size() - 1))
	picker.item_selected.connect(func(_index: int) -> void: changed.emit())
	into.add_child(picker)
	return picker


func _choice(
	into: VBoxContainer, label: String, items: PackedStringArray, selected: int
) -> OptionButton:
	var row: HBoxContainer = UiBits.row(into)
	row.add_child(UiBits.dim(label, 13, 110, false))
	var picker: OptionButton = _picker(row, items, selected)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return picker


func _check(into: VBoxContainer, label: String, on: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = on
	box.toggled.connect(func(_pressed: bool) -> void: changed.emit())
	into.add_child(box)
	return box
