extends "res://tests/suite.gd"
## Integration tests: the real autoloads, and the real Main scene.
##
## Every other suite here tests a pure class on its own, and that is exactly
## why the v1.16 audit found all eight of its defects in the wiring between
## them: a death announced to an empty room, actions that still worked on a
## dead dog, reminders that were never scheduled. None of it was arithmetic,
## so none of it was visible to a pure test.
##
## Run it the same way as the others:
##
##   godot --headless --path . --script res://tests/test_integration.gd
##
## Each scenario is a cold launch in a Godot process of its own, because a
## cold launch is the thing being tested. The run below starts one child per
## scenario and tallies what it prints; a child is this same script with
## "--scenario <name>" after a bare --.
##
## Nothing here touches the real saves/ folder. A child points Paths at a
## sandbox under the user data folder and writes its fixtures there, which
## is also what lets it drive the autoloads at all: they skip their startup
## under --script precisely so the other suites cannot eat a save.

const Model := preload("res://scripts/needs_model.gd")
const Life := preload("res://scripts/life_model.gd")
const Install := preload("res://scripts/pack_install.gd")

const SCENARIOS: PackedStringArray = [
	"dead_save_shows_death_card",
	"actions_refused_when_dead",
	"critical_at_launch_schedules_reminders",
	"new_pet_clears_notifier_memory",
	"reminder_gap_is_clamped",
	"overlapping_room_changes",
	"panels_build",
	"import_wizard_installs",
	"clock_jumped_forward",
]

const SANDBOX_FOLDER := "integration_sandbox"
const MAIN_SCENE := "res://scenes/Main.tscn"

## Enough frames for a signal to land and a _process tick to happen, without
## making the suite slow.
const SETTLE_FRAMES := 3

## How long to wait for the engine's own startup before giving up on it.
const BOOT_FRAME_LIMIT := 120


# The autoloads, fetched from the tree rather than written as Paths, Needs
# and so on. A script run with --script is compiled before the autoload
# singletons are registered as names, so naming them here would not compile
# at all - the error reads "Identifier not found: Needs".
var paths: Node = null
var settings: Node = null
var needs: Node = null
var library: Node = null
var notifier: Node = null


func _initialize() -> void:
	var wanted: String = _scenario_wanted()
	if wanted.is_empty():
		_run_children()
		return
	paths = root.get_node("Paths")
	settings = root.get_node("Settings")
	needs = root.get_node("Needs")
	library = root.get_node("AssetLibrary")
	notifier = root.get_node("Notifier")
	await _run_scenario(wanted)
	_report()


# --- The parent run -------------------------------------------------------

# One child process per scenario. Slower than calling the scenarios in a
# row, and worth it: the autoloads are singletons that load a save once, and
# "what happens when the app starts" cannot be tested twice in one start.
func _run_children() -> void:
	print("")
	print("DogPet integration tests")
	print("========================")
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	for name in SCENARIOS:
		print("")
		print(name)
		var output: Array = []
		var code: int = OS.execute(OS.get_executable_path(), [
			"--headless", "--path", project,
			"--script", "res://tests/test_integration.gd",
			"--", "--scenario", name,
		], output, true)
		_count_child_results("".join(output), code)
	_report()


func _count_child_results(text: String, exit_code: int) -> void:
	var seen: int = 0
	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges(false, true)
		if line.begins_with("  PASS"):
			_passed += 1
			seen += 1
			print(line)
		elif line.begins_with("  FAIL"):
			_failed += 1
			seen += 1
			print(line)
	if seen > 0:
		return
	# A scenario that printed nothing is a failure of its own: the child
	# crashed, or never reached its checks. Its output is the evidence.
	_failed += 1
	print("  FAIL  the scenario printed no results (exit %d)" % exit_code)
	print(text)


# Overrides the shared one on purpose. This suite reports from two places: the
# parent run, which has printed a heading, and a child scenario, which has not.
# The shared version underlines with a rule the width of the heading it printed,
# which in a child would be nothing at all - so the rule is spelled out here.
func _report() -> void:
	print("")
	print("========================")
	print("%d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("TESTS FAILED")
	else:
		print("All good.")
	quit(1 if _failed > 0 else 0)


func _scenario_wanted() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--scenario")
	if at < 0 or at + 1 >= args.size():
		return ""
	return args[at + 1]


func _run_scenario(name: String) -> void:
	match name:
		"dead_save_shows_death_card":
			await _dead_save_shows_death_card()
		"actions_refused_when_dead":
			await _actions_refused_when_dead()
		"critical_at_launch_schedules_reminders":
			await _critical_at_launch_schedules_reminders()
		"new_pet_clears_notifier_memory":
			await _new_pet_clears_notifier_memory()
		"reminder_gap_is_clamped":
			await _reminder_gap_is_clamped()
		"overlapping_room_changes":
			await _overlapping_room_changes()
		"panels_build":
			await _panels_build()
		"import_wizard_installs":
			await _import_wizard_installs()
		"clock_jumped_forward":
			await _clock_jumped_forward()
		_:
			_ok("a scenario called %s exists" % name, false)

	# The check every scenario gets, last, because getting this one wrong
	# does not fail a test: it quietly writes over the owner's own dog. It
	# has happened once already, when the boot above waited one frame for
	# the engine instead of waiting for Paths.
	_ok(
		"saves never left the sandbox",
		paths.saves_dir == OS.get_user_data_dir().path_join(SANDBOX_FOLDER)
	)


# --- The scenarios --------------------------------------------------------

# F1. The one that made Real play unplayable: a dog that died while the app
# was closed came up with no death card, no working buttons and no way to
# start another, because pet_died had been emitted before the scene existed.
func _dead_save_shows_death_card() -> void:
	var main: Node = await _boot(_dead_dog_save(), _real_play(), true)
	_ok("the save loads as a dead dog", not needs.life.alive)
	_ok("the death card is up", main._death_card.visible)
	_ok("Feed is locked", main._feed_button.disabled)
	_ok("Play is locked", main._play_button.disabled)
	_ok("Walk is locked", main._walk_button.disabled)
	_ok("the vet is locked too", main._vet_button.disabled)

	# And the way out has to work, or the card is just a nicer dead end.
	main._death_card._name_field.text = "Rex"
	main._death_card._start()
	await _settle()
	_ok("naming a new dog starts one", needs.life.alive)
	_ok("the new dog has the name given", needs.pet_name == "Rex")
	_ok("the death card is gone", not main._death_card.visible)
	_ok("Feed works again", not main._feed_button.disabled)
	_ok("the new dog is not hungry", needs.level_of(Model.HUNGER) == int(Model.Level.FINE))


# F2 and F6. Nothing can be fed, played with or treated once it has died,
# whichever door the attempt comes through.
func _actions_refused_when_dead() -> void:
	var main: Node = await _boot(_dead_dog_save(), _real_play(), true)
	var hunger: float = needs.value_of(Model.HUNGER)
	var sickness: float = needs.life.sickness

	main._runner.run(&"feed")
	await _settle()
	_ok("the action runner refuses to start", not main._runner.running)
	_close("hunger is untouched", needs.value_of(Model.HUNGER), hunger)

	_ok("the vet refuses a dead dog", not needs.take_to_vet())
	_close("sickness is untouched", needs.life.sickness, sickness)

	needs.apply_action(&"feed")
	_close("the effects are refused as well", needs.value_of(Model.HUNGER), hunger)
	_ok("the buttons are still locked afterwards", main._feed_button.disabled)
	_ok("and the death card is still up", main._death_card.visible)


# F3. A dog that was already starving when the app opened. There is no
# crossing to hear, because the catch-up happened before the notifier was
# listening - so it has to read the levels for itself.
func _critical_at_launch_schedules_reminders() -> void:
	await _boot(_starving_save(), _casual_demo(), false)
	_ok("hunger is critical at launch", needs.level_of(Model.HUNGER) == int(Model.Level.CRITICAL))
	_ok(
		"the notifier knows hunger is critical",
		int(notifier._announced.get(Model.HUNGER, 0)) == int(Model.Level.CRITICAL)
	)
	_ok("a reminder is scheduled for it", notifier._reminder_left.has(Model.HUNGER))
	_close(
		"and it is the demo gap of a minute",
		float(notifier._reminder_left.get(Model.HUNGER, 0.0)), 60.0
	)
	_ok(
		"a need that is fine schedules nothing",
		not notifier._reminder_left.has(Model.ENERGY)
	)


# F4. The notifier's memory must not outlive the dog it belongs to.
func _new_pet_clears_notifier_memory() -> void:
	await _boot(_starving_save(), _casual_demo(), false)
	_ok(
		"the notifier starts out knowing hunger is critical",
		int(notifier._announced.get(Model.HUNGER, 0)) == int(Model.Level.CRITICAL)
	)

	# Set by hand as well, so this scenario still fails if the notifier is
	# left holding a dead dog's levels even in a build where the launch
	# itself never adopted them. The two findings are separate, and the test
	# for one should not pass just because the other is also broken.
	notifier._announced[Model.HUNGER] = int(Model.Level.CRITICAL)
	notifier._reminder_left[Model.HUNGER] = 60.0

	needs.start_new_pet("Rex")
	await _settle()
	_ok("the new dog inherits no announcements", notifier._announced.is_empty())
	_ok("nor a reminder from the dog before it", notifier._reminder_left.is_empty())

	# The bug itself: a warning is a lower level than the dead dog's
	# critical, so it used to read as an improvement and be swallowed.
	needs.model.set_value(Model.HUNGER, 75.0)
	needs._announce_changes()
	await _settle()
	_ok(
		"the new dog's first warning is heard",
		int(notifier._announced.get(Model.HUNGER, 0)) == int(Model.Level.WARNING)
	)


# F5. A zero in settings.json used to mean a reminder every frame, and every
# reminder raised while the window is hidden starts a PowerShell process.
func _reminder_gap_is_clamped() -> void:
	var tuning: Dictionary = _casual_demo()
	tuning["critical_reminder_minutes"] = {"demo": 0.0}
	await _boot(_starving_save(), tuning, false)

	_close("the live gap is held at the floor", settings.critical_reminder_seconds(), 10.0)
	var first: float = float(notifier._reminder_left.get(Model.HUNGER, 0.0))
	_close("the scheduled reminder starts at the floor", first, 10.0)
	for _i in 20:
		await process_frame
	var later: float = float(notifier._reminder_left.get(Model.HUNGER, 0.0))
	var counting_down: bool = later < first and later > 0.0
	_ok("it counts down rather than firing every frame", counting_down)
	if not counting_down:
		print("          first %.4f, later %.4f, notifier processing: %s" % [
			first, later, notifier.is_processing(),
		])


# F11. Two transitions at once, which is what happens if a room is picked in
# Settings while an action's own transition is still running. The first one
# used to free the second one's room, clear the busy flag early and announce
# a room that had already been left.
func _overlapping_room_changes() -> void:
	var main: Node = await _boot(_starving_save(), _casual_demo(), true)
	var stage: Node = main._stage
	var arrivals: Array = []
	stage.transition_finished.connect(func(role: String) -> void: arrivals.append(role))

	# Deliberately not awaited: the second call has to land while the first
	# is still running, which is the whole point of the scenario.
	stage.show_role("eat", "fade")
	await process_frame
	stage.show_role("play", "fade")

	# Waited out in real seconds, not frames: the transitions are driven by
	# a timer, and a headless run gets through frames far faster than that.
	# Read off the stage's own script rather than preloaded: scene_stage.gd
	# names AssetLibrary, and a script that names an autoload cannot even be
	# compiled from here, let alone preloaded.
	var seconds: float = float(
		stage.get_script().get_script_constant_map().get("TRANSITION_SECONDS", 0.5)
	)
	await create_timer(seconds * 3.0).timeout

	_ok("the room on screen is the one asked for last", stage.current_role == "play")
	_ok("the stage is not left busy", not stage.is_busy())
	_ok("only one room is left on the stage", stage.get_child_count() == 1)
	_ok(
		"only the room arrived in was announced",
		arrivals.size() == 1 and String(arrivals[0]) == "play"
	)


# Not one of the audit's five. The settings screen puts seven sections of UI
# together from code, and it does that for real only with the autoloads and
# the scene tree - so a mistake in any of it used to show up when the owner
# opened Settings and not before.
func _panels_build() -> void:
	var main: Node = await _boot(_starving_save(), _casual_demo(), true)
	var panel: Node = main._settings_panel
	_ok("the settings screen built its seven sections", panel._sections.get_child_count() == 7)

	panel.open()
	await _settle()
	_ok("it builds them again when opened", panel._sections.get_child_count() == 7)
	_ok("and the screen is showing", panel.visible)
	panel.close()
	_ok("and hides again when done", not panel.visible)

	main._help_panel.open()
	await _settle()
	_ok("the instructions open", main._help_panel.visible)
	main._scoreboard.open()
	await _settle()
	_ok("so does the scoreboard", main._scoreboard.visible)


# The import wizard, driven the way a person drives it: choose files, say
# what they are, answer the questions, install.
#
# Worth a scenario of its own rather than a pure test, because the questions
# are controls and the answers are read back off them. PackBuilder can be
# proved correct on its own all day while the wizard hands it the wrong
# field, and only this notices.
func _import_wizard_installs() -> void:
	var main: Node = await _boot(_starving_save(), _casual_demo(), true)

	# Installing writes into assets/, so this one points assets/ at the
	# sandbox. Nothing may land in the project folder.
	var sandbox: String = OS.get_user_data_dir().path_join(SANDBOX_FOLDER)
	var art: String = sandbox.path_join("wizard_assets")
	var source: String = sandbox.path_join("wizard_source")
	PackArchive.empty_folder(art)
	DirAccess.make_dir_recursive_absolute(art)
	DirAccess.make_dir_recursive_absolute(source)
	paths.assets_dir = art
	paths.assets_available = true
	library.reload()
	await _settle()

	var idle: String = _write_png(source.path_join("my dog.png"), 32, 32)
	var walk: String = _write_png(source.path_join("walk.png"), 128, 32)

	var wizard: Node = main._import_wizard
	wizard.open()
	await _settle()
	_ok("the wizard opens", wizard.visible)
	_ok("it starts by asking for files", wizard._step == 0)

	# What the file dialog would have handed back.
	wizard._on_files_chosen(PackedStringArray([idle, walk]))
	await _settle()
	_ok("pictures could be a dog or a room, so it asks", wizard._step == 1)

	wizard._go_next()
	await _settle()
	_ok("then it asks the questions", wizard._step == 2)
	_ok("and it built some", wizard._body.get_child_count() > 4)

	var form: RefCounted = wizard._form
	_ok("the name came from the file", str(form.answers()["name"]) == "My Dog")
	_ok("the folder name was cleaned", str(form.answers()["id"]) == "my_dog")
	# The first picture is offered as idle; the strip is given a job by hand,
	# and its four frames were counted from its width.
	form._pictures[1]["job"].select(PetPack.VALID_STATES.find("walk") + 1)
	form._credit.text = "Someone, CC-BY"
	var sheets: Array = form.answers()["sheets"]
	_ok("both pictures have a job now", sheets.size() == 2)
	_ok("the strip was counted at four frames", int(sheets[1]["frames"]) == 4)

	wizard._go_next()
	await _settle()
	_ok("it says it is done", wizard._step == 3)
	var installed: String = art.path_join("pets/my_dog")
	_ok("a pet.json was written", FileAccess.file_exists(installed.path_join("pet.json")))
	_ok("the awkward file name was cleaned on the way in",
		FileAccess.file_exists(installed.path_join("my_dog.png")))
	_ok("the pack loads with no problems",
		PetPack.load_from_dir(installed).problems.is_empty())
	_ok("and the app can see it now", library.pet_ids().has("my_dog"))

	# The same picture, installed as a room instead - with a background
	# DogPet draws itself, so the one small picture is just a thing standing
	# in the room rather than the backdrop.
	wizard.open()
	wizard._on_files_chosen(PackedStringArray([idle]))
	wizard._kind = 3  # PackBuilder.Kind.ROOM
	wizard._step = 2
	wizard._rebuild()
	await _settle()
	var room_form: RefCounted = wizard._form
	room_form._name.text = "Spare Room"
	room_form._folder.text = "spare_room"
	room_form._credit.text = "Someone"
	_ok("a room made only of props is refused while nothing draws it",
		not Install.check(3, room_form.answers()).is_empty())
	room_form._drawn.select(1)  # an indoor room, painted in code
	wizard._go_next()
	await _settle()
	_ok("a room installs too", FileAccess.file_exists(
		art.path_join("scenes/spare_room/scene.json")
	))
	var room: ScenePack = ScenePack.load_from_dir(art.path_join("scenes/spare_room"))
	_ok("it fills the slot it was given", room.role == ScenePack.HOME)
	_ok("and DogPet paints it rather than needing a picture",
		str(room.background["type"]) == ScenePack.BG_GENERATED)
	_ok("the prop came with it", room.props.size() == 1)
	_ok("and it is offered for that slot", _room_ids(library.scenes_for("home")).has("spare_room"))

	# And a real 3D model, the shipped pug, pointed at from outside assets/.
	# This is the path with nothing to fall back on: the model is read with
	# GLTFDocument, measured, and shown in the preview so the owner can turn
	# it to face the camera.
	var pug: String = ProjectSettings.globalize_path("res://assets/pets/pug_3d/model.glb")
	wizard.open()
	wizard._on_files_chosen(PackedStringArray([pug]))
	await _settle()
	_ok("a model goes straight to the questions", wizard._step == 2)
	# The preview stage itself, rather than what it shows: the model inside
	# it cannot be read under --script at all, because a static call on a
	# global class finds nothing there - which is also why the app's own
	# SceneView prints errors in this suite. The real app loads it fine.
	_ok("and the preview stage was built", wizard._preview._world != null)
	var model_form: RefCounted = wizard._form
	model_form._name.text = "Second Pug"
	model_form._folder.text = "second_pug"
	model_form._credit.text = "Smirnoff Alexander, CC-BY 3.0"
	model_form._facing.value = -29.0
	wizard._go_next()
	await _settle()
	var pet: PetPack = PetPack.load_from_dir(art.path_join("pets/second_pug"))
	_ok("the model pack installed", pet.problems.is_empty())
	_ok("the model file came with it", FileAccess.file_exists(
		art.path_join("pets/second_pug/model.glb")
	))
	_close("the facing was written down", pet.rotation_y_degrees, -29.0)
	_ok("and the pack it wrote is one the app will use", pet.is_usable())

	wizard.close()
	_ok("the wizard closes", not wizard.visible)
	PackArchive.empty_folder(art)


func _room_ids(rooms: Array) -> PackedStringArray:
	var ids: PackedStringArray = []
	for room in rooms:
		ids.append(room.id)
	return ids


# A real PNG, so the wizard can read its size out of the header the way it
# will when the owner points at one.
func _write_png(path: String, width: int, height: int) -> String:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.4, 0.2, 1.0))
	image.save_png(path)
	return path


# --- Booting the real thing -----------------------------------------------

# Point Paths at a sandbox, write the fixtures, then run the startup the
# autoloads skipped. They have done nothing at all yet, so calling _ready
# here connects each signal once rather than twice.
func _boot(save: Dictionary, settings_json: Dictionary, with_scene: bool) -> Node:
	# Wait for the engine to finish starting up before touching anything. A
	# --script run arrives in _initialize before the autoloads have had their
	# own _ready, and setting the folders up before that looks like it works
	# and then quietly comes undone: Paths._ready arrives afterwards, reads
	# --script back out of the command line and puts every folder back. The
	# cost of getting this wrong is not a failing test but a passing one that
	# writes the owner's real saves/pet.json, so the wait is on Paths having
	# actually run - base_dir is empty until it has - and then two more
	# frames for the autoloads behind it, which would otherwise take their
	# guarded path and switch their own processing off again.
	var waited: int = 0
	while paths.base_dir.is_empty() and waited < BOOT_FRAME_LIMIT:
		await process_frame
		waited += 1
	await _settle()

	# Paths works out its folders from OS.has_feature("editor"), which is
	# false under --script however the engine was started, so it had picked
	# the folder the Godot binary sits in. Both folders are set here: the
	# sandbox to write to, and the project's real assets/ to read, so these
	# scenarios run against the shipped art rather than the fallback set.
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var sandbox: String = OS.get_user_data_dir().path_join(SANDBOX_FOLDER)
	DirAccess.make_dir_recursive_absolute(sandbox)
	paths.saves_dir = sandbox
	paths.assets_dir = project.path_join("assets")
	paths.assets_available = DirAccess.dir_exists_absolute(paths.assets_dir)
	for leftover in ["pet.json", "pet.json.bak", "pet.json.tmp", "settings.json", "history.json"]:
		DirAccess.remove_absolute(sandbox.path_join(leftover))
	if not save.is_empty():
		_write_json(paths.pet_save_path(), save)
	_write_json(paths.settings_path(), settings_json)

	paths.tool_script_mode = false
	settings._ready()
	library._ready()
	needs._ready()
	notifier._ready()
	# _ready turned processing off on the way past, before Paths was safe.
	needs.set_process(true)
	notifier.set_process(true)

	if not with_scene:
		return null
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _settle()
	return main


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


func _write_json(path: String, payload: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_ok("could write the fixture to " + path, false)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


# --- Fixtures -------------------------------------------------------------

# A dog that starved to death two minutes after the app was last closed,
# which is the save the owner's own saves/ folder was left holding.
func _dead_dog_save() -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	return {
		"format_version": 1,
		"pet_name": "Biscuit",
		"pet_pack_id": "pug_3d",
		"hunger": 100.0,
		"happiness": 0.0,
		"energy": 100.0,
		"last_saved_unix": now - 120.0,
		"life": {
			"born_unix": now - 400000.0,
			"age_days": 7.4,
			"sickness": 0.0,
			"ill": false,
			"starving_seconds": 20000.0,
			"alive": false,
			"died_unix": now - 3600.0,
			"cause": int(Life.Cause.STARVATION),
		},
	}


# Alive, but at the bad end of hunger, and saved two minutes ago so there is
# a catch-up to do on the way in.
func _starving_save() -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	return {
		"format_version": 1,
		"pet_name": "Biscuit",
		"pet_pack_id": "pug_3d",
		"hunger": 100.0,
		"happiness": 100.0,
		"energy": 0.0,
		"last_saved_unix": now - 120.0,
		"life": {
			"born_unix": now - 400000.0,
			"age_days": 7.4,
			"sickness": 0.0,
			"ill": false,
			"starving_seconds": 0.0,
			"alive": true,
			"died_unix": 0.0,
			"cause": int(Life.Cause.NONE),
		},
	}


# RT-07. A system clock that jumps forward is indistinguishable from a real
# absence from inside the app, and used to be acted on in full: a save a year
# old meant a year of starvation credited during the catch-up, so the dog was
# dead before the window opened. A year is now treated as the cap instead, and
# the owner is told the clock looked wrong.
func _clock_jumped_forward() -> void:
	# A dog that was perfectly well when the app closed, and a clock that now
	# claims a year has gone by.
	var save: Dictionary = _starving_save()
	save["hunger"] = 0.0
	save["last_saved_unix"] = Time.get_unix_time_from_system() - 365.0 * 86400.0
	var main: Node = await _boot(save, _real_play(), true)

	_ok("the dog is still alive after a year-long absence", needs.life.alive)
	_ok("so there is no death card", not main._death_card.visible)
	_ok("and the care buttons still work", not main._feed_button.disabled)

	var summary: Dictionary = main._away_card._shown_summary
	_ok("the absence was capped rather than acted on in full",
		float(summary.get("elapsed", 0.0)) <= needs.MAX_CATCH_UP_SECONDS + 1.0)
	_ok("the owner is told the clock looked wrong",
		bool(summary.get("clock_looks_wrong", false)))

	# The cap must not soften the game: a month of neglect still ruins
	# everything, which is why it is set where it is.
	_ok("hunger is still maxed", needs.level_of(Model.HUNGER) == int(Model.Level.CRITICAL))
	_ok("happiness is still bottomed",
		needs.level_of(Model.HAPPINESS) == int(Model.Level.CRITICAL))


# Notifications are off in every scenario on purpose. The notifier would
# otherwise try to raise a real Windows toast from a test run, and a toast
# means starting a PowerShell process. What is being tested here is what
# gets scheduled and remembered, which happens either way.
func _real_play() -> Dictionary:
	return {"play_mode": "real", "notifications_enabled": false}


func _casual_demo() -> Dictionary:
	return {"play_mode": "casual", "demo_speed": true, "notifications_enabled": false}
