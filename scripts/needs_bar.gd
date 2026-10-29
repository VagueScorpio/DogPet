extends VBoxContainer
## One need: its name, a bar, a word for how it is doing, and a countdown.
##
## Colour is never the only signal here. The word on the right says "Fine",
## "Getting low" or "Needs care now" in plain text, the countdown says how
## long is left, and the hint underneath spells out what a full bar means -
## because a full Hunger bar is bad news while a full Happiness bar is good.

## Bar colours per level. The word beside the bar carries the same meaning,
## so these are a help, not the message.
const FINE_COLOR := Color(0.36, 0.72, 0.45)
const WARNING_COLOR := Color(0.92, 0.69, 0.23)
const CRITICAL_COLOR := Color(0.85, 0.32, 0.29)

@onready var _name_label: Label = %NameLabel
@onready var _status_label: Label = %StatusLabel
@onready var _bar: ProgressBar = %Bar
@onready var _countdown_label: Label = %CountdownLabel
@onready var _hint_label: Label = %HintLabel
@onready var _icon: TextureRect = %Icon

var _key: StringName = &""

# Built once and re-tinted, rather than making a new StyleBox every frame.
var _fill_style := StyleBoxFlat.new()
var _background_style := StyleBoxFlat.new()


## Point this bar at one of the three needs. Main calls this right after
## instancing the scene.
func setup(key: StringName) -> void:
	_key = key
	_name_label.text = NeedsModel.display_name(key)
	_hint_label.text = NeedsModel.full_bar_means(key)
	_load_icon(key)

	_background_style.bg_color = Color(1, 1, 1, 0.10)
	_background_style.set_corner_radius_all(3)
	# Square ends on the fill: a rounded fill still draws a sliver at value
	# 0, so an empty bar would look very slightly full.
	_fill_style.set_corner_radius_all(0)
	_bar.add_theme_stylebox_override("background", _background_style)
	_bar.add_theme_stylebox_override("fill", _fill_style)

	# The status word and the colour only change when the level changes, so
	# they ride on the signal. The bar and the countdown move continuously,
	# so they are refreshed in _process below.
	Needs.threshold_crossed.connect(_on_threshold_crossed)
	_apply_level(Needs.level_of(key))


# The need's icon from assets/ui, drawn at its own size so the pixel art
# stays crisp. No icon simply means no icon.
func _load_icon(key: StringName) -> void:
	if AssetLibrary.ui == null:
		return
	var path: String = AssetLibrary.ui.need_icon_path(String(key))
	if path.is_empty():
		return
	var texture: Texture2D = PetLoader.load_texture(path)
	if texture == null:
		return
	_icon.texture = texture
	_icon.show()


func _process(_delta: float) -> void:
	if _key == &"":
		return
	_bar.value = Needs.value_of(_key)
	var countdown: String = Needs.countdown_text(_key)
	var line: String = "needs care now" if countdown == "now" else "needs care in " + countdown
	if _countdown_label.text != line:
		_countdown_label.text = line


func _on_threshold_crossed(key: StringName, level: int) -> void:
	if key != _key:
		return  # Every bar hears about every need; this one is not ours.
	_apply_level(level)


func _apply_level(level: int) -> void:
	_status_label.text = NeedsModel.level_label(level)
	var color: Color = FINE_COLOR
	match level:
		int(NeedsModel.Level.WARNING):
			color = WARNING_COLOR
		int(NeedsModel.Level.CRITICAL):
			color = CRITICAL_COLOR
	_fill_style.bg_color = color
	_status_label.add_theme_color_override("font_color", color)
