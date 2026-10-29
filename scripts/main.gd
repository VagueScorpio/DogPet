extends Control
## The main window: the three needs along the top, the dog in its room in
## the middle, and the care buttons along the bottom.
##
## Everything adjustable moved into the settings screen in phase 5, so what
## is left here is the window itself and the few things that belong on it.

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
@onready var _settings_button: Button = %SettingsButton
@onready var _pet_view: Control = %PetView
@onready var _pet_area: PanelContainer = %PetArea
@onready var _away_card: Control = %AwayCard
@onready var _banner: Control = %Banner
@onready var _settings_panel: Control = %SettingsPanel
@onready var _help_panel: Control = %HelpPanel
@onready var _menu_host: PanelContainer = %MenuHost

var _stage: SceneStage = null
var _runner: ActionRunner = null


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE

	_build_menu()
	_build_stage()
	_build_bars()
	_connect_controls()
	_refresh_window_title()
	_refresh_demo_badge()
	_show_startup_notice()

	Settings.changed.connect(_on_settings_changed)
	Needs.pet_name_changed.connect(_on_pet_name_changed)
	Notifier.banner_requested.connect(_banner.show_message)

	# The autoloads all finish before this scene exists, so there was nobody
	# listening when the catch-up happened. Needs held the summary for us.
	var summary: Dictionary = Needs.take_away_summary()
	if not summary.is_empty():
		_away_card.show_summary(summary, Needs.pet_name)


func _process(_delta: float) -> void:
	var line: String = Needs.reaction_line()
	if _reaction_label.text != line:
		_reaction_label.text = line


# The menu bar is built in code because most of what it shows is the state
# of something - which care speed is on, whether there is a tray to hide
# into - and that is easier to keep honest from one place.
func _build_menu() -> void:
	var menu := AppMenu.new()
	menu.name = "AppMenu"
	_menu_host.add_child(menu)
	menu.rename_requested.connect(_ask_for_name)
	menu.instructions_requested.connect(_help_panel.open)
	menu.settings_requested.connect(_settings_panel.open)


# A small dialog rather than a trip into Settings, since renaming the dog is
# the sort of thing done on a whim.
func _ask_for_name() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Change the dog's name"
	dialog.ok_button_text = "Rename"
	dialog.add_cancel_button("Cancel")

	var field := LineEdit.new()
	field.text = Needs.pet_name
	field.placeholder_text = "Biscuit"
	field.custom_minimum_size = Vector2(220, 0)
	dialog.add_child(field)
	# So Enter does the obvious thing instead of nothing.
	dialog.register_text_enter(field)

	dialog.confirmed.connect(func() -> void:
		Needs.set_pet_name(field.text)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	field.grab_focus()
	field.select_all()


# --- Building the window --------------------------------------------------

# The room goes underneath the dog, inside the same panel, so the dog
# stands in front of whatever room is showing.
func _build_stage() -> void:
	_stage = SceneStage.new()
	_pet_area.add_child(_stage)
	_pet_area.move_child(_stage, 0)

	_runner = ActionRunner.new()
	_runner.name = "ActionRunner"
	add_child(_runner)
	_runner.setup(_stage, _pet_view)
	_runner.started.connect(_on_action_started)
	_runner.finished.connect(_on_action_finished)


# One bar per need, built from the same scene, so there is a single place to
# change how a bar looks.
func _build_bars() -> void:
	for key in NeedsModel.KEYS:
		var bar: Node = NEEDS_BAR_SCENE.instantiate()
		_bars.add_child(bar)
		bar.setup(key)


func _connect_controls() -> void:
	_feed_button.pressed.connect(_on_action_pressed.bind(&"feed"))
	_play_button.pressed.connect(_on_action_pressed.bind(&"play"))
	_walk_button.pressed.connect(_on_action_pressed.bind(&"walk"))
	_settings_button.pressed.connect(_settings_panel.open)
	_settings_button.tooltip_text = "Settings"
	_notice_dismiss.pressed.connect(_notice_panel.hide)
	_load_button_icons()


# The care buttons take their icons from assets/ui, like everything else.
# A missing icon just means a button with only words on it.
func _load_button_icons() -> void:
	if AssetLibrary.ui == null:
		return
	var buttons: Dictionary = {
		"feed": _feed_button, "play": _play_button, "walk": _walk_button,
	}
	for action in buttons.keys():
		var path: String = AssetLibrary.ui.button_icon_path(action)
		if path.is_empty():
			continue
		var texture: Texture2D = PetLoader.load_texture(path)
		if texture != null:
			buttons[action].icon = texture


# --- Reacting to things ---------------------------------------------------

func _on_action_pressed(action: StringName) -> void:
	_runner.run(action)


# While an action is running the care buttons are locked, so nothing can be
# started twice or interrupted halfway through. Settings stays reachable:
# changing a room mid-walk is harmless, and locking the owner out of their
# own settings would be worse.
func _on_action_started(_action: StringName) -> void:
	_set_actions_enabled(false)


func _on_action_finished(_action: StringName) -> void:
	_set_actions_enabled(true)


func _set_actions_enabled(enabled: bool) -> void:
	for button in [_feed_button, _play_button, _walk_button]:
		button.disabled = not enabled


func _on_settings_changed(key: String) -> void:
	if key == "demo_speed":
		_refresh_demo_badge()


func _on_pet_name_changed(_new_name: String) -> void:
	_refresh_window_title()


func _refresh_window_title() -> void:
	get_window().title = "DogPet - " + Needs.pet_name
	_title_label.text = Needs.pet_name


func _refresh_demo_badge() -> void:
	_demo_badge.visible = Settings.demo_speed()


# Anything Paths had to say at startup: saves moved because the app folder
# is read-only, or a missing assets folder.
func _show_startup_notice() -> void:
	if Paths.startup_notes.is_empty():
		return
	_notice_label.text = "\n".join(Paths.startup_notes)
	_notice_panel.show()
