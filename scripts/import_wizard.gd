extends Control
## The import wizard: add art to DogPet without knowing how DogPet works.
##
## The old Import button took a .zip that already held a pet.json, which is
## no use to anybody who has just downloaded a model or drawn a dog. This
## asks for the files, asks what they are, asks the few things that cannot be
## measured - which way the model faces, how many frames are in a strip, what
## the room is for - and then writes the manifest and installs the pack
## itself. A .zip that is already a pack still goes straight to PackArchive.
##
## The thinking lives in PackBuilder and PackInstall, which have no nodes in
## them and are tested headlessly. This is the part that has to be clicked.

signal installed(message: String)

const Builder := preload("res://scripts/pack_builder.gd")
const Install := preload("res://scripts/pack_install.gd")
const Form := preload("res://scripts/import_form.gd")
const Preview := preload("res://scripts/import_preview.gd")

enum Step { FILES, KIND, DETAILS, DONE }

const STEP_BLURBS: Dictionary = {
	Step.FILES: "Step 1 of 3 - choose the files",
	Step.KIND: "Step 2 of 3 - what are they?",
	Step.DETAILS: "Step 3 of 3 - a few questions",
	Step.DONE: "Done",
}

const KIND_BLURBS: Dictionary = {
	Builder.Kind.PET_SPRITE: "Pictures of a dog: one still frame, or a strip of frames.",
	Builder.Kind.ROOM: "A background, a pair of tiles, or things to stand in a room.",
}

@onready var _frame: PanelContainer = %Frame
@onready var _step_label: Label = %StepLabel
@onready var _stage: PanelContainer = %Stage
@onready var _body: VBoxContainer = %Body
@onready var _message: Label = %MessageLabel
@onready var _back_button: Button = %BackButton
@onready var _next_button: Button = %NextButton
@onready var _close_button: Button = %CloseButton

var _transfer: PackTransfer = null
var _preview: Preview = null
var _form: Form = null
var _notes: Label = null

var _step: int = Step.FILES
var _sources: Dictionary = {}
var _kinds: Array[int] = []
var _kind: int = Builder.Kind.UNKNOWN
var _done_text: String = ""
var _installed_id: String = ""


func _ready() -> void:
	_frame.add_theme_stylebox_override(
		"panel", UiBits.panel_style(UiBits.PANEL_FILL, UiBits.PANEL_BORDER, 8)
	)
	_stage.add_theme_stylebox_override(
		"panel", UiBits.panel_style(Color(0.08, 0.09, 0.12), UiBits.PANEL_BORDER, 6)
	)
	_transfer = PackTransfer.new()
	add_child(_transfer)
	_transfer.finished.connect(_on_zip_finished)
	_preview = Preview.new()
	_stage.add_child(_preview)

	_close_button.pressed.connect(close)
	_back_button.pressed.connect(_go_back)
	_next_button.pressed.connect(_go_next)


func open() -> void:
	_step = Step.FILES
	_sources = {}
	_kinds = []
	_kind = Builder.Kind.UNKNOWN
	_form = null
	_installed_id = ""
	show()
	_rebuild()


func close() -> void:
	_preview.clear()
	hide()


# --- Building whichever step we are on -----------------------------------

func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	_notes = null
	_message.text = ""
	_step_label.text = str(STEP_BLURBS[_step])

	match _step:
		Step.FILES:
			_build_files()
		Step.KIND:
			_build_kind()
		Step.DETAILS:
			_build_details()
		Step.DONE:
			_build_done()

	_back_button.visible = _step == Step.KIND or _step == Step.DETAILS
	_next_button.visible = _step == Step.KIND or _step == Step.DETAILS
	_next_button.text = "Install" if _step == Step.DETAILS else "Next"
	_close_button.text = "Close" if _step == Step.DONE else "Cancel"


func _build_files() -> void:
	_preview.clear()
	_body.add_child(UiBits.heading("What have you got?", 16))
	_body.add_child(UiBits.dim(
		"Pick the files and DogPet will do the rest: it measures them, writes the"
		+ " description file it needs, and copies everything into the right folder."
		+ " Nothing is moved from where you keep it.", 12
	))
	var choose: Button = UiBits.button("Choose files...", _ask_for_files)
	choose.custom_minimum_size = Vector2(0, 40)
	_body.add_child(choose)

	_body.add_child(UiBits.dim(
		"A 3D model (.glb or .gltf) becomes a dog.\n"
		+ "Pictures (.png) become a dog drawn in frames, or a room.\n"
		+ "A pack someone made (.zip) is installed as it is.\n\n"
		+ "You can pick several files at once - hold Ctrl while clicking - which is"
		+ " how a dog with a standing picture and a walking strip gets added in one go.", 12
	))


func _build_kind() -> void:
	_show_pictures()
	_body.add_child(UiBits.heading("What are these pictures?", 16))
	var group := ButtonGroup.new()
	for kind in _kinds:
		var radio := CheckBox.new()
		radio.text = Builder.kind_title(kind)
		radio.button_group = group
		radio.button_pressed = kind == _kinds[0]
		radio.pressed.connect(func() -> void: _kind = kind)
		_body.add_child(radio)
		_body.add_child(UiBits.dim(str(KIND_BLURBS.get(kind, "")), 11))
	_kind = _kinds[0]


func _build_details() -> void:
	_form = Form.new()
	_form.build(_body, _kind, _sources)
	_form.changed.connect(_on_form_changed)

	_notes = UiBits.dim("", 11, 0.0, true, Color(1.0, 0.85, 0.4))
	_body.add_child(_notes)

	if _kind == Builder.Kind.PET_MODEL:
		var model: String = PackedStringArray(_sources["models"])[0]
		if not _preview.show_model(model, _form.wanted_height(), _form.facing_degrees()):
			_message.text = "That model could not be read. A .glb from Poly Pizza or"\
				+ " Sketchfab is the safest kind."
	else:
		_show_pictures()
	_refresh_notes()


func _build_done() -> void:
	_preview.clear()
	_body.add_child(UiBits.heading("Installed", 16))
	_body.add_child(UiBits.dim(_done_text, 13))

	if not _installed_id.is_empty():
		if _kind == Builder.Kind.ROOM:
			_body.add_child(UiBits.button("Put the dog in it now", func() -> void:
				AssetLibrary.set_active_scene(_form.answers()["role"], _installed_id)
				_message.text = "This room is now the one in use."
			))
		else:
			_body.add_child(UiBits.button("Use this dog now", func() -> void:
				AssetLibrary.set_active_pet(_installed_id)
				_message.text = "The dog has changed body. Its needs are unchanged."
			))

	_body.add_child(UiBits.button("Add something else", func() -> void: open()))
	_body.add_child(UiBits.button(
		"Open the assets folder", func() -> void: Paths.open_in_file_manager(Paths.assets_dir)
	))


# --- Moving between the steps --------------------------------------------

func _ask_for_files() -> void:
	_transfer.pick(
		"Choose art to add to DogPet",
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILES,
		"",
		Builder.FILE_FILTER,
		_on_files_chosen
	)


func _on_files_chosen(paths: PackedStringArray) -> void:
	_sources = Builder.sort_sources(paths)
	_kinds = Builder.kinds_for(_sources)

	# A zip is already a pack, so it goes the way packs always went.
	if _kinds.size() == 1 and _kinds[0] == Builder.Kind.PACK_ZIP:
		_transfer.import_zip(PackedStringArray(_sources["archives"])[0])
		return

	if _kinds.is_empty():
		_message.text = "None of those is something DogPet can use. It needs a .glb,"\
			+ " a .gltf, a .png or a .zip."
		return

	_kind = _kinds[0]
	_step = Step.DETAILS if _kinds.size() == 1 else Step.KIND
	_rebuild()


func _go_back() -> void:
	_step = Step.KIND if _step == Step.DETAILS and _kinds.size() > 1 else Step.FILES
	_rebuild()


func _go_next() -> void:
	if _step == Step.KIND:
		_step = Step.DETAILS
		_rebuild()
		return
	_install()


func _on_form_changed() -> void:
	if _kind == Builder.Kind.PET_MODEL:
		_preview.set_height(_form.wanted_height())
		_preview.set_facing(_form.facing_degrees())
	_refresh_notes()


# The warnings are shown while the answers are still on screen, and never
# stand in the way of installing: a pack with no credit line works, it is
# just listed afterwards as a pack with something wrong with it.
func _refresh_notes() -> void:
	if _notes == null:
		return
	var notes: PackedStringArray = Install.warnings(_kind, _form.answers())
	_notes.text = "\n".join(notes)
	_notes.visible = not notes.is_empty()


func _show_pictures() -> void:
	_preview.show_pictures(_sources["images"])


# --- Installing ----------------------------------------------------------

func _install() -> void:
	var answers: Dictionary = _form.answers()
	var problems: PackedStringArray = Install.check(_kind, answers)
	if not problems.is_empty():
		_message.text = problems[0] if problems.size() == 1 else "%s  (and %d more)" % [
			problems[0], problems.size() - 1,
		]
		return

	var id: String = str(answers["id"])
	var target: String = Paths.assets_subdir(Builder.subdir_for(_kind)).path_join(id)
	if DirAccess.dir_exists_absolute(target):
		_transfer.confirm(
			"Replace \"%s\"?" % id,
			"There is already something installed in that folder. It will be copied into"
			+ " assets/_backup first, then replaced.",
			func() -> void: _write(answers, target, id)
		)
		return
	_write(answers, target, id)


func _write(answers: Dictionary, target: String, id: String) -> void:
	if DirAccess.dir_exists_absolute(target):
		if not _transfer.back_up(target, id):
			_message.text = "Could not back up what is already there, so nothing was changed."
			return
		PackArchive.empty_folder(target)

	var plan: Dictionary = Install.plan(_kind, answers, target)
	var problems: PackedStringArray = Install.write(plan)
	AssetLibrary.reload()

	var name: String = str(answers["name"])
	if problems.is_empty():
		Log.info("Installed %s into %s" % [id, target])
		_done_text = "\"%s\" is installed, in assets/%s/%s." % [
			name, Builder.subdir_for(_kind), id,
		]
		_installed_id = id
	else:
		Log.warn("Install problems: %s" % ", ".join(problems))
		_done_text = "\"%s\" was installed with problems: %s" % [name, problems[0]]
		_installed_id = ""

	installed.emit(_done_text)
	_step = Step.DONE
	_rebuild()


# A .zip went to PackArchive, which reports back through PackTransfer.
func _on_zip_finished(message: String) -> void:
	_done_text = message
	_installed_id = ""
	_step = Step.DONE
	installed.emit(message)
	_rebuild()
