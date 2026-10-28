extends Control
## The "While you were away" card, shown on launch after a real absence.
##
## It lists each need's before and after, so the owner can see exactly what
## the time away cost, and ends with the dog's own reaction to it.

## Matches the bar colours, so a row that got worse reads the same way the
## bar above it does.
const WORSE_COLOR := Color(0.92, 0.69, 0.23)
const SAME_COLOR := Color(1, 1, 1, 0.7)

@onready var _title_label: Label = %TitleLabel
@onready var _rows_box: VBoxContainer = %RowsBox
@onready var _reaction_label: Label = %ReactionLabel
@onready var _close_button: Button = %CloseButton
@onready var _card: PanelContainer = $Center/Card


func _ready() -> void:
	_close_button.pressed.connect(hide)
	_card.add_theme_stylebox_override("panel", _card_style())


# The default panel is translucent, which left the screen behind showing
# through the card's own text.
func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.17, 0.21)
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


## Fill in and show the card. The summary comes from Needs.take_away_summary.
func show_summary(summary: Dictionary, pet_name: String) -> void:
	var elapsed: float = float(summary.get("elapsed", 0.0))
	var before: Dictionary = summary.get("before", {})
	var after: Dictionary = summary.get("after", {})

	_title_label.text = "While you were away (%s)..." % NeedsModel.format_duration(elapsed)

	for child in _rows_box.get_children():
		child.queue_free()

	for key in NeedsModel.KEYS:
		var field: String = String(key)
		var was: float = float(before.get(field, 0.0))
		var now: float = float(after.get(field, 0.0))
		_rows_box.add_child(_build_row(key, was, now))

	_reaction_label.text = str(summary.get("reaction", ""))
	show()
	_close_button.grab_focus()


# One line such as "Hunger      20  ->  100   (+80)".
func _build_row(key: StringName, was: float, now: float) -> Control:
	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = NeedsModel.display_name(key)
	name_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(name_label)

	var change_label := Label.new()
	change_label.text = "%d  ->  %d" % [roundi(was), roundi(now)]
	change_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(change_label)

	# How far it moved towards its own bad end, so a drop in Happiness and a
	# rise in Hunger both read as "worse".
	var moved: float = (was - now) if key == NeedsModel.HAPPINESS else (now - was)
	var delta_label := Label.new()
	delta_label.custom_minimum_size = Vector2(70, 0)
	delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if roundi(moved) > 0:
		delta_label.text = "worse by %d" % roundi(moved)
		delta_label.add_theme_color_override("font_color", WORSE_COLOR)
	else:
		delta_label.text = "no change"
		delta_label.add_theme_color_override("font_color", SAME_COLOR)
	row.add_child(delta_label)

	return row
