extends Control
## Every dog that has lived here, newest first.
##
## The one on screen now comes first, marked as still living, because a
## scoreboard that only lists the dead is a strange thing to open when
## your dog is fine. Everything below it is read from saves/history.json.

const LIVING_COLOR := Color(0.36, 0.72, 0.45)
const GONE_COLOR := Color(1, 1, 1, 0.55)

@onready var _frame: PanelContainer = %Frame
@onready var _done_button: Button = %DoneButton
@onready var _summary_label: Label = %SummaryLabel
@onready var _entries: VBoxContainer = %Entries


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.18)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	_frame.add_theme_stylebox_override("panel", style)
	_done_button.pressed.connect(hide)


func open() -> void:
	_rebuild()
	show()
	_done_button.grab_focus()


func _rebuild() -> void:
	for child in _entries.get_children():
		child.queue_free()

	var past: Array[Dictionary] = PetHistory.load_records(Paths.history_path())

	if Needs.life.alive:
		_entries.add_child(_living_entry())

	for record in past:
		_entries.add_child(_past_entry(record))

	_summary_label.text = _summary(past)


# What the whole record adds up to. Worth saying, because "six dogs, the
# longest 11 days" is the actual point of keeping one.
func _summary(past: Array[Dictionary]) -> String:
	if past.is_empty():
		if Settings.is_real_play():
			return "No dog has died yet. Long may that continue."
		return "Nothing here yet. Dogs are only at risk in Real Pet play."
	var oldest: float = 0.0
	var oldest_name: String = ""
	var starved: int = 0
	var ill: int = 0
	for record in past:
		var age: float = float(record.get("age_days", 0.0))
		if age > oldest:
			oldest = age
			oldest_name = str(record.get("name", "?"))
		match int(record.get("cause", 0)):
			int(LifeModel.Cause.STARVATION):
				starved += 1
			int(LifeModel.Cause.SICKNESS):
				ill += 1
	# One sentence rather than fragments stapled together with full stops.
	var tail: PackedStringArray = []
	if not oldest_name.is_empty():
		tail.append("the oldest %s at %s" % [oldest_name, LifeModel.format_age(oldest)])
	if starved > 0:
		tail.append("%d lost to starvation" % starved)
	if ill > 0:
		tail.append("%d to illness" % ill)
	var opening: String = "%d dog%s remembered" % [past.size(), "" if past.size() == 1 else "s"]
	if tail.is_empty():
		return opening + "."
	return "%s: %s." % [opening, ", ".join(tail)]


# --- One entry -------------------------------------------------------------

func _living_entry() -> Control:
	var box: VBoxContainer = _entry_box()
	box.add_child(_name_row(Needs.pet_name, "still with you", LIVING_COLOR))
	box.add_child(_detail("Born", PetHistory.format_date(Needs.life.born_unix)))
	box.add_child(_detail("Age", "%s  (%s)" % [
		LifeModel.format_age(Needs.life.age_days), Needs.life.stage(),
	]))
	if not Settings.is_real_play():
		box.add_child(_detail("Mode", "Casual, so nothing can happen to them"))
	elif Needs.life.ill:
		box.add_child(_detail("Health", "unwell, and needs a vet"))
	return box


func _past_entry(record: Dictionary) -> Control:
	var box: VBoxContainer = _entry_box()
	var cause: int = int(record.get("cause", 0))
	box.add_child(_name_row(
		str(record.get("name", "?")),
		"died of %s" % LifeModel.cause_name(cause),
		GONE_COLOR
	))
	box.add_child(_detail("Born", PetHistory.format_date(float(record.get("born_unix", 0.0)))))
	box.add_child(_detail("Died", PetHistory.format_date(float(record.get("died_unix", 0.0)))))
	box.add_child(_detail("Age", LifeModel.format_age(float(record.get("age_days", 0.0)))))
	# Dog-days and real time are not the same thing - a dog on Demo speed
	# ages a year in an afternoon - so both are worth showing.
	box.add_child(_detail("Lived for", PetHistory.format_lifespan(
		float(record.get("born_unix", 0.0)), float(record.get("died_unix", 0.0))
	)))
	return box


func _entry_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	return box


func _name_row(name: String, note: String, colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = name
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)
	var tag := Label.new()
	tag.text = note
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", colour)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tag)
	return row


func _detail(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name := Label.new()
	name.text = key
	name.custom_minimum_size = Vector2(72, 0)
	name.add_theme_font_size_override("font_size", 12)
	name.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	row.add_child(name)
	var detail := Label.new()
	detail.text = value
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	row.add_child(detail)
	return row
