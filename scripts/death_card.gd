extends Control
## Shown in Real play when the dog dies.
##
## Deliberately plain. It says what happened, how old the dog was, and
## offers the only thing left to do, which is start another one. There is
## no way to dismiss it and carry on, because there is nothing to carry on
## with - the dog is gone and everything else is frozen behind it.

signal new_pet_requested(name: String)

@onready var _frame: PanelContainer = %Frame
@onready var _title_label: Label = %TitleLabel
@onready var _detail_label: Label = %DetailLabel
@onready var _name_field: LineEdit = %NameField
@onready var _start_button: Button = %StartButton


func _ready() -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.15, 0.13, 0.14)
    style.border_color = Color(0.85, 0.32, 0.29, 0.7)
    style.set_border_width_all(1)
    style.set_corner_radius_all(8)
    _frame.add_theme_stylebox_override("panel", style)

    _start_button.pressed.connect(_start)
    _name_field.text_submitted.connect(func(_text: String) -> void: _start())


## Tell the owner what happened and offer a fresh start.
func show_death(pet_name: String, cause: int, age_days: float) -> void:
    _title_label.text = LifeModel.death_line(pet_name, cause)
    _detail_label.text = "%s was %s.\n\nIn Real Pet play there is no going back. You can start again with a new dog, and the scoreboard will remember this one." % [
        pet_name, LifeModel.format_age(age_days),
    ]
    _name_field.text = ""
    _name_field.placeholder_text = "A name for the new dog"
    show()
    _name_field.grab_focus()


func _start() -> void:
    var chosen: String = _name_field.text.strip_edges()
    if chosen.is_empty():
        chosen = "Biscuit"
    hide()
    new_pet_requested.emit(chosen)
