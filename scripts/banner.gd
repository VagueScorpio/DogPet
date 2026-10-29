extends Control
## The in-app message strip.
##
## When the owner is already looking at the window, a Windows notification
## would be silly - it would appear over the very app it is talking about.
## This says the same thing inside the app instead, slides out of the way on
## its own, and can be dismissed early.

## How long a message stays before it leaves by itself.
const SHOW_SECONDS := 7.0
const SLIDE_SECONDS := 0.25

@onready var _card: PanelContainer = %Card
@onready var _icon: TextureRect = %Icon
@onready var _title_label: Label = %TitleLabel
@onready var _body_label: Label = %BodyLabel
@onready var _close_button: Button = %CloseButton

var _hide_left: float = 0.0


func _ready() -> void:
	_close_button.pressed.connect(dismiss)
	_close_button.tooltip_text = "Dismiss"
	_card.add_theme_stylebox_override("panel", _card_style())
	_load_icon()
	set_process(false)


func _process(delta: float) -> void:
	_hide_left -= delta
	if _hide_left <= 0.0:
		dismiss()


## Show a message. A second message while one is up simply replaces it,
## rather than queueing, because the newer one is the more useful.
func show_message(title: String, body: String) -> void:
	_title_label.text = title
	_body_label.text = body
	_body_label.visible = not body.is_empty()
	_hide_left = SHOW_SECONDS
	set_process(true)

	if visible:
		return
	show()
	# Slide down from just above its own position, so it arrives rather
	# than simply appearing.
	var settled: float = position.y
	position.y = settled - size.y
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:y", settled, SLIDE_SECONDS)
	tween.tween_property(self, "modulate:a", 1.0, SLIDE_SECONDS)


func dismiss() -> void:
	set_process(false)
	if not visible:
		return
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, SLIDE_SECONDS)
	tween.tween_callback(hide)


# The tray icon doubles as the banner's icon, so the in-app message and the
# Windows one look like they came from the same place.
func _load_icon() -> void:
	if AssetLibrary.ui == null:
		return
	var texture: Texture2D = PetLoader.load_texture(AssetLibrary.ui.tray_icon_path())
	if texture == null:
		return
	_icon.texture = texture
	_icon.show()


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.19, 0.24)
	style.border_color = Color(0.99, 0.83, 0.3, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style
