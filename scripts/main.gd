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
@onready var _pet_picker: OptionButton = %PetPicker
@onready var _state_picker: OptionButton = %StatePicker
@onready var _pet_view: Control = %PetView
@onready var _pet_area: PanelContainer = %PetArea
@onready var _role_picker: OptionButton = %RolePicker
@onready var _room_picker: OptionButton = %RoomPicker

var _stage: SceneStage = null
var _runner: ActionRunner = null
@onready var _footer_label: Label = %FooterLabel
@onready var _away_card: Control = %AwayCard


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE

	_build_stage()
	_build_bars()
	_fill_interval_picker()
	_fill_pet_picker()
	_fill_state_picker()
	_fill_role_picker()
	_fill_room_picker()
	_connect_controls()
	_refresh_window_title()
	_refresh_demo_badge()
	_refresh_footer()
	_show_startup_notice()

	Settings.changed.connect(_on_settings_changed)
	Needs.pet_name_changed.connect(_on_pet_name_changed)
	AssetLibrary.library_reloaded.connect(_fill_pet_picker)
	AssetLibrary.pet_changed.connect(_on_pet_changed)
	AssetLibrary.scene_changed.connect(_on_scene_changed)

	# The autoloads all finish before this scene exists, so there was nobody
	# listening when the catch-up happened. Needs held the summary for us.

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
	_pet_picker.item_selected.connect(_on_pet_selected)
	_state_picker.item_selected.connect(_on_state_selected)
	_role_picker.item_selected.connect(_on_role_selected)
	_room_picker.item_selected.connect(_on_room_selected)
	_reset_button.tooltip_text = "Put all three needs back to fully cared for."
	_notice_dismiss.pressed.connect(_notice_panel.hide)


# --- Reacting to changes -------------------------------------------------

func _on_action_pressed(action: StringName) -> void:
	_runner.run(action)


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


# While an action is running the buttons are locked, so nothing can be
# started twice or interrupted halfway through.
func _on_action_started(_action: StringName) -> void:
	_set_actions_enabled(false)


func _on_action_finished(_action: StringName) -> void:
	_set_actions_enabled(true)
	_fill_role_picker()
	_fill_room_picker()


func _set_actions_enabled(enabled: bool) -> void:
	for button in [_feed_button, _play_button, _walk_button]:
		button.disabled = not enabled
	_state_picker.disabled = not enabled
	_role_picker.disabled = not enabled
	_reset_button.disabled = not enabled


# Which of the four slots to look at, without running an action for it.
func _fill_role_picker() -> void:
	_role_picker.clear()
	for index in ScenePack.ROLES.size():
		var role: String = ScenePack.ROLES[index]
		_role_picker.add_item("Show: " + role.capitalize())
		if _stage != null and _stage.current_role == role:
			_role_picker.select(index)


# Every room offering itself for the slot being shown.
func _fill_room_picker() -> void:
	_room_picker.clear()
	var role: String = _stage.current_role if _stage != null else ScenePack.HOME
	var rooms: Array[ScenePack] = AssetLibrary.scenes_for(role)
	var active: ScenePack = AssetLibrary.active_scene(role)
	for index in rooms.size():
		_room_picker.add_item(rooms[index].display_name)
		if active != null and rooms[index].id == active.id:
			_room_picker.select(index)
	_room_picker.disabled = rooms.size() < 2
	if rooms.size() < 2 and rooms.size() == 1:
		_room_picker.tooltip_text = "Add another folder under assets/scenes to get a choice here."


func _on_role_selected(index: int) -> void:
	if index < 0 or index >= ScenePack.ROLES.size() or _stage == null:
		return
	var role: String = ScenePack.ROLES[index]
	_stage.show_role(role)
	var room: ScenePack = AssetLibrary.active_scene(role)
	if room != null:
		_pet_view.set_pet_spot(room.pet_spot)
	_fill_room_picker()


func _on_room_selected(index: int) -> void:
	var role: String = _stage.current_role if _stage != null else ScenePack.HOME
	var rooms: Array[ScenePack] = AssetLibrary.scenes_for(role)
	if index < 0 or index >= rooms.size():
		return
	AssetLibrary.set_active_scene(role, rooms[index].id)


func _on_scene_changed(_role: String, _pack: ScenePack) -> void:
	_fill_room_picker()


# Every valid pet pack the loader found, so switching bodies can be tried
# without leaving the app. The needs do not change - it is the same dog.
func _fill_pet_picker() -> void:
	_pet_picker.clear()
	var packs: Array[PetPack] = AssetLibrary.pets
	for index in packs.size():
		var pack: PetPack = packs[index]
		_pet_picker.add_item("%s  (%s)" % [pack.display_name, pack.kind])
		if AssetLibrary.active_pet != null and pack.id == AssetLibrary.active_pet.id:
			_pet_picker.select(index)
	_pet_picker.disabled = packs.size() < 2


# "Mood (automatic)" plus every state, so each one can be watched on demand
# rather than waiting for the needs to produce it.
func _fill_state_picker() -> void:
	_state_picker.clear()
	_state_picker.add_item("Mood (automatic)")
	for state in PetMotion.STATES:
		_state_picker.add_item(String(state).capitalize())
	_state_picker.select(0)


# Keep the picker showing whichever pet is actually on screen, even when
# something other than the picker changed it.
func _on_pet_changed(pack: PetPack) -> void:
	var packs: Array[PetPack] = AssetLibrary.pets
	for index in packs.size():
		if packs[index].id == pack.id:
			_pet_picker.select(index)
			return


func _on_pet_selected(index: int) -> void:
	var packs: Array[PetPack] = AssetLibrary.pets
	if index < 0 or index >= packs.size():
		return
	AssetLibrary.set_active_pet(packs[index].id)


func _on_state_selected(index: int) -> void:
	if index <= 0:
		_pet_view.resume_mood()
		return
	_pet_view.play_state(PetMotion.STATES[index - 1])


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
	# Kept to one line so it cannot wrap and push the window out of shape.
	# The full paths are in the tooltip, and in Settings > About later.
	_footer_label.text = "v%s    saves and assets are beside the app" % Log.app_version()
	_footer_label.tooltip_text = "saves: %s
assets: %s" % [Paths.saves_dir, Paths.assets_dir]


# Anything Paths had to say at startup: saves moved because the app folder
# is read-only, or a missing assets folder.
func _show_startup_notice() -> void:
	if Paths.startup_notes.is_empty():
		return
	_notice_label.text = "\n".join(Paths.startup_notes)
	_notice_panel.show()
