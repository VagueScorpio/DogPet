extends Control
## The phase 1 debug screen: the three needs, their countdowns, the care
## setting, the Demo Speed toggle and the "While you were away" card.
##
## The dog itself, the rooms and the real action sequences arrive in later
## phases. What is wired up here is the plumbing underneath them: needs
## ticking in real time, saving to disk, and catching up on however long the
## app was closed.

const MIN_WINDOW_SIZE := Vector2i(420, 600)
const NEEDS_BAR_SCENE := preload("res://scenes/NeedsBar.tscn")

@onready var _title_label: Label = %TitleLabel
@onready var _demo_badge: Label = %DemoBadge
@onready var _notice_panel: PanelContainer = %NoticePanel
@onready var _notice_label: Label = %NoticeLabel
@onready var _notice_dismiss: Button = %NoticeDismiss
@onready var _bars: VBoxContainer = %Bars
@onready var _reaction_label: Label = %ReactionLabel
@onready var _feed_button: Button = %FeedButton
@onready var _play_button: Button = %PlayButton
@onready var _walk_button: Button = %WalkButton
@onready var _demo_toggle: CheckButton = %DemoToggle
@onready var _interval_picker: OptionButton = %IntervalPicker
@onready var _reset_button: Button = %ResetButton
@onready var _footer_label: Label = %FooterLabel
@onready var _away_card: Control = %AwayCard


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE

	_build_bars()
	_fill_interval_picker()
	_connect_controls()
	_refresh_window_title()
	_refresh_demo_badge()
	_refresh_footer()
	_show_startup_notice()

	Settings.changed.connect(_on_settings_changed)
	Needs.pet_name_changed.connect(_on_pet_name_changed)

	# The autoloads all finish before this scene exists, so there was nobody
	# listening when the catch-up happened. Needs held the summary for us.
	var summary: Dictionary = Needs.take_away_summary()
	if not summary.is_empty():
		_away_card.show_summary(summary, Needs.pet_name)


func _process(_delta: float) -> void:
	var line: String = Needs.reaction_line()
	if _reaction_label.text != line:
		_reaction_label.text = line


# --- Building the screen --------------------------------------------------

# One bar per need, built from the same scene, so there is a single place to
# change how a bar looks.
func _build_bars() -> void:
	for key in NeedsModel.KEYS:
		var bar: Node = NEEDS_BAR_SCENE.instantiate()
		_bars.add_child(bar)
		bar.setup(key)


# "Frequent  (40m / 45m / 50m)" and so on, so the choice is not a mystery.
func _fill_interval_picker() -> void:
	_interval_picker.clear()
	for index in CareSettings.CARE_INTERVALS.size():
		var name: String = CareSettings.CARE_INTERVALS[index]
		_interval_picker.add_item("%s  (%s)" % [name.capitalize(), _describe_row(name)])
		if name == Settings.care_interval():
			_interval_picker.select(index)


func _describe_row(name: String) -> String:
	var row: Dictionary = CareSettings.intervals_from(CareSettings.DEFAULTS, name)
	var parts: PackedStringArray = []
	for key in NeedsModel.KEYS:
		parts.append(_short_duration(float(row.get(key, 0.0))))
	return " / ".join(parts)


func _short_duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%ds" % roundi(seconds)
	if seconds < 3600.0:
		return "%dm" % roundi(seconds / 60.0)
	var hours: float = seconds / 3600.0
	if is_equal_approx(hours, roundf(hours)):
		return "%dh" % roundi(hours)
	return "%.1fh" % hours


func _connect_controls() -> void:
	_feed_button.pressed.connect(_on_action_pressed.bind(&"feed"))
	_play_button.pressed.connect(_on_action_pressed.bind(&"play"))
	_walk_button.pressed.connect(_on_action_pressed.bind(&"walk"))
	_demo_toggle.button_pressed = Settings.demo_speed()
	_demo_toggle.toggled.connect(Settings.set_demo_speed)
	_interval_picker.item_selected.connect(_on_interval_selected)
	_reset_button.pressed.connect(Needs.reset_to_cared)
	_reset_button.tooltip_text = "Put all three needs back to fully cared for."
	_notice_dismiss.pressed.connect(_notice_panel.hide)


# --- Reacting to changes -------------------------------------------------

func _on_action_pressed(action: StringName) -> void:
	Needs.apply_action(action)


func _on_interval_selected(index: int) -> void:
	if index < 0 or index >= CareSettings.CARE_INTERVALS.size():
		return
	Settings.set_care_interval(CareSettings.CARE_INTERVALS[index])


func _on_settings_changed(key: String) -> void:
	if key == "demo_speed":
		_refresh_demo_badge()
	elif key == "care_interval":
		_fill_interval_picker()


func _on_pet_name_changed(_new_name: String) -> void:
	_refresh_window_title()


func _refresh_window_title() -> void:
	get_window().title = "DogPet - " + Needs.pet_name
	_title_label.text = Needs.pet_name


func _refresh_demo_badge() -> void:
	var on: bool = Settings.demo_speed()
	_demo_badge.visible = on
	# Keep the toggle honest when the change came from somewhere else.
	_demo_toggle.set_pressed_no_signal(on)


func _refresh_footer() -> void:
	_footer_label.text = "v%s    saves: %s    assets: %s" % [
		Log.app_version(),
		Paths.saves_dir,
		Paths.assets_dir,
	]


# Anything Paths had to say at startup: saves moved because the app folder
# is read-only, or a missing assets folder.
func _show_startup_notice() -> void:
	if Paths.startup_notes.is_empty():
		return
	_notice_label.text = "\n".join(Paths.startup_notes)
	_notice_panel.show()
