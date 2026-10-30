extends Control
## The settings screen.
##
## The sections are built in code rather than laid out by hand in the scene,
## because almost all of them are lists of whatever happens to be installed:
## the pets found in assets/, the rooms offering themselves for each slot,
## the credit line of every pack. None of that can be known in advance.
##
## Building a section is always the same shape - a heading, some rows - so
## the small helpers at the bottom do most of the work and each section
## reads as a description of itself.

@onready var _frame: PanelContainer = %Frame
@onready var _done_button: Button = %DoneButton
@onready var _sections: VBoxContainer = %Sections

var _transfer: PackTransfer = null
var _pet_list: VBoxContainer = null
var _about: VBoxContainer = null


func _ready() -> void:
	# The default panel is translucent, which left the whole window showing
	# through the settings screen.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.18)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	_frame.add_theme_stylebox_override("panel", style)

	_done_button.pressed.connect(close)
	_transfer = PackTransfer.new()
	add_child(_transfer)
	_transfer.finished.connect(_on_transfer_finished)
	AssetLibrary.library_reloaded.connect(rebuild)
	rebuild()


func open() -> void:
	rebuild()
	show()
	_done_button.grab_focus()


func close() -> void:
	hide()


## Throw the whole screen away and build it again. Cheap, and it means
## nothing can drift out of step with what is actually installed.
func rebuild() -> void:
	for child in _sections.get_children():
		child.queue_free()
	_build_care()
	_build_pet()
	_build_rooms()
	_build_assets()
	_build_window()
	_build_notifications()
	_build_about()


# --- 1. Care --------------------------------------------------------------

func _build_care() -> void:
	var box: VBoxContainer = _section("Care", "How fast the needs run down.")

	var group := ButtonGroup.new()
	for name in CareSettings.CARE_INTERVALS:
		var radio := CheckBox.new()
		radio.text = name.capitalize()
		radio.button_group = group
		radio.button_pressed = (name == Settings.care_interval())
		radio.pressed.connect(Settings.set_care_interval.bind(name))
		box.add_child(radio)

	# The table, so the choice is not a guess.
	var table := GridContainer.new()
	table.columns = 4
	table.add_theme_constant_override("h_separation", 16)
	box.add_child(table)
	for heading in ["", "Hunger", "Happiness", "Energy"]:
		table.add_child(UiBits.dim(heading, 12, 0.0, false))
	for name in [CareSettings.FREQUENT, CareSettings.MODERATE, CareSettings.LONG, CareSettings.DEMO]:
		table.add_child(UiBits.dim(name.capitalize(), 12, 0.0, false))
		var row: Dictionary = CareSettings.intervals_from(Settings.data, name)
		for key in NeedsModel.KEYS:
			table.add_child(UiBits.dim(UiBits.duration(float(row[key])), 12, 0.0, false))

	var demo := CheckButton.new()
	demo.text = "Demo Speed"
	demo.tooltip_text = "Everything runs in under a minute, for trying things out."
	demo.button_pressed = Settings.demo_speed()
	demo.toggled.connect(Settings.set_demo_speed)
	box.add_child(demo)
	box.add_child(UiBits.dim(
		"Time away is always caught up at the real setting above, never at Demo speed.", 11
	))


# --- 2. Pet ---------------------------------------------------------------

func _build_pet() -> void:
	var box: VBoxContainer = _section("Pet", "")

	var name_row: HBoxContainer = UiBits.row(box)
	name_row.add_child(UiBits.dim("Name", 13, 60, false))
	var field := LineEdit.new()
	field.text = Needs.pet_name
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(func(text: String) -> void: Needs.set_pet_name(text))
	field.focus_exited.connect(func() -> void: Needs.set_pet_name(field.text))
	name_row.add_child(field)

	box.add_child(UiBits.dim("Switching body keeps the same dog, and the same needs.", 11))
	_pet_list = VBoxContainer.new()
	_pet_list.add_theme_constant_override("separation", 4)
	box.add_child(_pet_list)
	_fill_pet_list()


func _fill_pet_list() -> void:
	for child in _pet_list.get_children():
		child.queue_free()
	var group := ButtonGroup.new()
	for pack in AssetLibrary.pets:
		var line := VBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		var radio := CheckBox.new()
		radio.text = "%s   (%s)" % [pack.display_name, pack.kind]
		radio.button_group = group
		radio.button_pressed = (
			AssetLibrary.active_pet != null and AssetLibrary.active_pet.id == pack.id
		)
		radio.pressed.connect(AssetLibrary.set_active_pet.bind(pack.id))
		line.add_child(radio)
		if not pack.credit.is_empty():
			var credit: Label = UiBits.dim(pack.credit, 10)
			credit.custom_minimum_size = Vector2(0, 0)
			line.add_child(credit)
		_pet_list.add_child(line)


# --- 3. Rooms -------------------------------------------------------------

func _build_rooms() -> void:
	var box: VBoxContainer = _section(
		"Rooms", "One per slot. Add a folder to assets/scenes to get a choice here."
	)
	for role in ScenePack.ROLES:
		var row: HBoxContainer = UiBits.row(box)
		row.add_child(UiBits.dim(role.capitalize(), 13, 90, false))
		var rooms: Array[ScenePack] = AssetLibrary.scenes_for(role)
		if rooms.is_empty():
			row.add_child(UiBits.dim("(none found)", 12))
			continue
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active: ScenePack = AssetLibrary.active_scene(role)
		for index in rooms.size():
			picker.add_item(rooms[index].display_name)
			if active != null and rooms[index].id == active.id:
				picker.select(index)
		picker.disabled = rooms.size() < 2
		picker.item_selected.connect(func(index: int) -> void:
			AssetLibrary.set_active_scene(role, rooms[index].id)
		)
		row.add_child(picker)


# --- 4. Assets ------------------------------------------------------------

func _build_assets() -> void:
	var box: VBoxContainer = _section(
		"Assets", "All the art lives in a folder beside the app. Change it freely."
	)

	var row: HBoxContainer = UiBits.row(box)
	row.add_child(UiBits.button(
		"Open folder", func() -> void: Paths.open_in_file_manager(Paths.assets_dir)
	))
	row.add_child(UiBits.button("Reload", func() -> void:
		AssetLibrary.reload()
		_note("Assets reloaded.")
	))

	var transfer_row: HBoxContainer = UiBits.row(box)
	transfer_row.add_child(UiBits.button("Import pack...", func() -> void: _transfer.import_pack()))
	transfer_row.add_child(UiBits.button("Export pet...", func() -> void:
		if AssetLibrary.active_pet != null:
			_transfer.export_pet(AssetLibrary.active_pet)
	))

	var export_row: HBoxContainer = UiBits.row(box)
	export_row.add_child(UiBits.dim("Room", 13, 60, false))
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for role in ScenePack.ROLES:
		var room: ScenePack = AssetLibrary.active_scene(role)
		picker.add_item("%s - %s" % [role.capitalize(), room.display_name if room else "none"])
	export_row.add_child(picker)
	export_row.add_child(UiBits.button("Export", func() -> void:
		var role: String = ScenePack.ROLES[maxi(0, picker.selected)]
		var room: ScenePack = AssetLibrary.active_scene(role)
		if room != null:
			_transfer.export_room(room)
	))


func _on_transfer_finished(message: String) -> void:
	_note(message)
	rebuild()


func _note(message: String) -> void:
	Notifier.banner_requested.emit(message, "")


# --- 5. Window ------------------------------------------------------------

func _build_window() -> void:
	var box: VBoxContainer = _section("Window", "")

	var quits := CheckBox.new()
	quits.text = "Close button quits DogPet"
	quits.button_pressed = Settings.close_button_quits()
	quits.toggled.connect(Settings.set_close_button_quits)
	box.add_child(quits)
	box.add_child(UiBits.dim(
		"Left off, closing the window tucks DogPet into the tray and the dog carries on."
		+ ("" if Tray.supported else "  (No tray available here, so the close button quits.)"),
		11
	))

	var minimised := CheckBox.new()
	minimised.text = "Start minimised to the tray"
	minimised.button_pressed = Settings.start_minimized()
	minimised.toggled.connect(Settings.set_start_minimized)
	minimised.disabled = not Tray.supported
	box.add_child(minimised)


# --- 6. Notifications -----------------------------------------------------

func _build_notifications() -> void:
	var box: VBoxContainer = _section("Notifications", "")

	var on := CheckBox.new()
	on.text = "Tell me when the dog needs something"
	on.button_pressed = Settings.notifications_enabled()
	on.toggled.connect(Settings.set_notifications_enabled)
	box.add_child(on)

	var row: HBoxContainer = UiBits.row(box)
	row.add_child(UiBits.button("Test notification", Notifier.send_test))
	if Notifier.is_paused():
		row.add_child(UiBits.button("Resume now", func() -> void:
			Notifier.resume()
			rebuild()
		))
		row.add_child(UiBits.dim("Paused for %d more minutes" % Notifier.pause_minutes_left(), 11))

	box.add_child(UiBits.dim(
		"Notifications arrive from \"Windows PowerShell\". That is expected: DogPet installs"
		+ " nothing, so it has no name of its own to announce itself with.", 11
	))


# --- 7. About -------------------------------------------------------------

func _build_about() -> void:
	_about = _section("About", "")
	_about.add_child(UiBits.dim("DogPet v%s     Godot %s" % [
		Log.app_version(), Engine.get_version_info().get("string", "?"),
	], 12))

	for row in [["Saves", Paths.saves_dir], ["Assets", Paths.assets_dir]]:
		var line: HBoxContainer = UiBits.row(_about)
		line.add_child(UiBits.dim(row[0], 12, 60, false))
		var open := LinkButton.new()
		open.text = row[1]
		open.tooltip_text = "Open this folder"
		open.add_theme_font_size_override("font_size", 11)
		var folder: String = row[1]
		open.pressed.connect(func() -> void: Paths.open_in_file_manager(folder))
		line.add_child(open)

	_about.add_child(UiBits.heading("Credits", 15))
	_about.add_child(UiBits.dim(
		"The art DogPet ships with is not all under the same licence. Some of it"
		+ " requires that its credit stays visible, so here it is.", 11
	))
	CreditsList.build_into(_about, self)


# --- The one builder that needs the panel itself ------------------------

func _section(title: String, blurb: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UiBits.heading(title, 18))
	if not blurb.is_empty():
		box.add_child(UiBits.dim(blurb, 11))
	_sections.add_child(box)
	return box


