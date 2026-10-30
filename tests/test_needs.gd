extends SceneTree
## Headless tests for the needs maths and the save file.
##
## Run them from the project root with:
##
##   godot --headless --path . --script res://tests/test_needs.gd
##
## On a fresh clone, run this once first so Godot builds its caches:
##
##   godot --headless --path . --import
##
## Without it the tests still pass, but the autoloads - which load
## alongside and do use class names - print parse errors on the way past.
##
## Prints PASS or FAIL for every check, then exits 0 only if everything
## passed, so a build script can rely on the exit code.
##
## The scripts are reached through preload rather than by their class_name,
## because a fresh checkout has no editor-generated class cache yet and these
## tests should run in it anyway. The names here are deliberately not the
## class names, so nothing is shadowed.

const Model := preload("res://scripts/needs_model.gd")
const Save := preload("res://scripts/save_file.gd")
const Config := preload("res://scripts/care_settings.gd")

const MINUTE := 60.0
const HOUR := 3600.0
const DAY := 86400.0

var _passed: int = 0
var _failed: int = 0
var _section: String = ""


func _initialize() -> void:
	print("")
	print("DogPet needs tests")
	print("==================")

	_test_interval_table()
	_test_drain_rates()
	_test_clamping()
	_test_thresholds()
	_test_catch_up()
	_test_catch_up_ignores_demo()
	_test_seconds_at_critical()
	_test_actions()
	_test_formatting()
	_test_corrupt_save_falls_back()

	print("")
	print("==================")
	print("%d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("TESTS FAILED")
	else:
		print("All good.")
	quit(1 if _failed > 0 else 0)


# --- The checks -----------------------------------------------------------

func _test_interval_table() -> void:
	_begin("Interval table matches the spec")
	var want: Dictionary = {
		Config.FREQUENT: [40.0 * MINUTE, 45.0 * MINUTE, 50.0 * MINUTE],
		Config.MODERATE: [3.0 * HOUR, 3.5 * HOUR, 4.0 * HOUR],
		Config.LONG: [10.0 * HOUR, 11.0 * HOUR, 12.0 * HOUR],
		Config.DEMO: [45.0, 50.0, 55.0],
	}
	for name in want.keys():
		var row: Dictionary = _intervals(name)
		var expected: Array = want[name]
		_close("%s hunger interval" % name, row[Model.HUNGER], expected[0])
		_close("%s happiness interval" % name, row[Model.HAPPINESS], expected[1])
		_close("%s energy interval" % name, row[Model.ENERGY], expected[2])


func _test_drain_rates() -> void:
	_begin("Drain rates, for every setting")
	for name in [Config.FREQUENT, Config.MODERATE, Config.LONG, Config.DEMO]:
		var row: Dictionary = _intervals(name)
		for key in Model.KEYS:
			var interval: float = row[key]

			# Half the interval should be exactly half way to critical.
			var half := Model.new()
			half.drain(interval * 0.5, row)
			_close("%s %s is 50%% gone at half the interval" % [name, key], half.badness(key), 50.0)

			# The whole interval should land exactly on critical.
			var full := Model.new()
			full.drain(interval, row)
			_close(
				"%s %s hits %d after the full interval" % [name, key, Model.critical_value(key)],
				full.get_value(key),
				Model.critical_value(key)
			)
			_ok(
				"%s %s reads as critical there" % [name, key],
				full.level_of(key) == Model.Level.CRITICAL
			)

	_begin("Drain is linear and one-way")
	var row_mod: Dictionary = _intervals(Config.MODERATE)
	var step := Model.new()
	step.drain(HOUR, row_mod)
	var one_hour: float = step.get_value(Model.HUNGER)
	step.drain(HOUR, row_mod)
	_close("a second hour adds the same amount", step.get_value(Model.HUNGER), one_hour * 2.0)

	var still := Model.new()
	still.drain(0.0, row_mod)
	_close("zero seconds changes nothing", still.badness(Model.HUNGER), 0.0)
	still.drain(-5.0, row_mod)
	_close("negative seconds changes nothing", still.badness(Model.HUNGER), 0.0)


func _test_clamping() -> void:
	_begin("Clamping at the bad end")
	var row: Dictionary = _intervals(Config.DEMO)
	var model := Model.new()
	model.drain(row[Model.HUNGER] * 10.0, row)
	_close("hunger stops at 100", model.get_value(Model.HUNGER), 100.0)
	_close("happiness stops at 0", model.get_value(Model.HAPPINESS), 0.0)
	_close("energy stops at 100", model.get_value(Model.ENERGY), 100.0)
	_ok("the dog is still here, just unhappy", model.level_of(Model.HUNGER) == Model.Level.CRITICAL)

	_begin("Clamping at the good end")
	var good := Model.new()
	good.set_value(Model.HUNGER, -40.0)
	_close("hunger cannot go below 0", good.get_value(Model.HUNGER), 0.0)
	good.set_value(Model.HAPPINESS, 180.0)
	_close("happiness cannot go above 100", good.get_value(Model.HAPPINESS), 100.0)


func _test_thresholds() -> void:
	_begin("Warning and critical crossings")
	var model := Model.new()

	model.set_value(Model.HUNGER, 69.9)
	_ok("hunger 69.9 is Fine", model.level_of(Model.HUNGER) == Model.Level.FINE)
	model.set_value(Model.HUNGER, 70.0)
	_ok("hunger 70 is a Warning", model.level_of(Model.HUNGER) == Model.Level.WARNING)
	model.set_value(Model.HUNGER, 99.9)
	_ok("hunger 99.9 is still a Warning", model.level_of(Model.HUNGER) == Model.Level.WARNING)
	model.set_value(Model.HUNGER, 100.0)
	_ok("hunger 100 is Critical", model.level_of(Model.HUNGER) == Model.Level.CRITICAL)

	model.set_value(Model.HAPPINESS, 30.1)
	_ok("happiness 30.1 is Fine", model.level_of(Model.HAPPINESS) == Model.Level.FINE)
	model.set_value(Model.HAPPINESS, 30.0)
	_ok("happiness 30 is a Warning", model.level_of(Model.HAPPINESS) == Model.Level.WARNING)
	model.set_value(Model.HAPPINESS, 0.0)
	_ok("happiness 0 is Critical", model.level_of(Model.HAPPINESS) == Model.Level.CRITICAL)

	model.set_value(Model.ENERGY, 70.0)
	_ok("energy 70 is a Warning", model.level_of(Model.ENERGY) == Model.Level.WARNING)
	model.set_value(Model.ENERGY, 100.0)
	_ok("energy 100 is Critical", model.level_of(Model.ENERGY) == Model.Level.CRITICAL)

	_begin("Crossings arrive by draining, not just by being set")
	var row: Dictionary = _intervals(Config.MODERATE)
	var drained := Model.new()
	drained.drain(row[Model.HUNGER] * 0.7, row)
	_ok("70% of the way through, hunger warns", drained.level_of(Model.HUNGER) == Model.Level.WARNING)
	var not_yet := Model.new()
	not_yet.drain(row[Model.HUNGER] * 0.69, row)
	_ok("69% of the way through, it does not", not_yet.level_of(Model.HUNGER) == Model.Level.FINE)

	_begin("Level wording")
	_ok("Fine", Model.level_label(Model.Level.FINE) == "Fine")
	_ok("Getting low", Model.level_label(Model.Level.WARNING) == "Getting low")
	_ok("Needs care now", Model.level_label(Model.Level.CRITICAL) == "Needs care now")


func _test_catch_up() -> void:
	var row: Dictionary = _intervals(Config.MODERATE)

	_begin("Catch-up after 0 seconds")
	var zero := Model.new()
	zero.catch_up(0.0, row)
	_close("hunger unchanged", zero.get_value(Model.HUNGER), 0.0)
	_close("happiness unchanged", zero.get_value(Model.HAPPINESS), 100.0)
	_close("energy unchanged", zero.get_value(Model.ENERGY), 0.0)

	_begin("Catch-up after 1 hour on Moderate")
	var hour := Model.new()
	hour.catch_up(HOUR, row)
	# Moderate hunger is 3 h, so one hour is a third of the way.
	_close("hunger is a third gone", hour.get_value(Model.HUNGER), 100.0 / 3.0)
	# Happiness is 3.5 h, so one hour is 100/3.5 = 28.57 off full.
	_close("happiness dropped by 100/3.5", hour.get_value(Model.HAPPINESS), 100.0 - 100.0 / 3.5)
	# Energy is 4 h, so one hour is a quarter.
	_close("energy is a quarter gone", hour.get_value(Model.ENERGY), 25.0)

	_begin("Catch-up after 3 days")
	var days := Model.new()
	days.catch_up(3.0 * DAY, row)
	_close("hunger maxed", days.get_value(Model.HUNGER), 100.0)
	_close("happiness bottomed", days.get_value(Model.HAPPINESS), 0.0)
	_close("energy maxed", days.get_value(Model.ENERGY), 100.0)

	_begin("Catch-up with a clock that went backwards")
	var back := Model.new()
	back.set_value(Model.HUNGER, 40.0)
	back.catch_up(-9999.0, row)
	_close("a negative elapsed time heals nothing", back.get_value(Model.HUNGER), 40.0)
	_close("elapsed_between never returns a negative", Model.elapsed_between(500.0, 100.0), 0.0)
	_close("elapsed_between measures forwards", Model.elapsed_between(100.0, 460.0), 360.0)


func _test_catch_up_ignores_demo() -> void:
	_begin("Catch-up ignores Demo Speed")
	var config: Dictionary = Config.DEFAULTS.duplicate(true)
	config["care_interval"] = Config.MODERATE
	config["demo_speed"] = true

	_ok(
		"the live drain uses the Demo row while Demo is on",
		Config.live_interval_name(config) == Config.DEMO
	)
	_ok(
		"the catch-up still uses the real setting",
		Config.catch_up_interval_name(config) == Config.MODERATE
	)

	# The whole point: an hour away with Demo left on must not max the bars.
	var caught := Model.new()
	caught.catch_up(HOUR, Config.intervals_from(config, Config.catch_up_interval_name(config)))
	_close("an hour away is a third of Moderate hunger", caught.get_value(Model.HUNGER), 100.0 / 3.0)
	_ok("and hunger is not critical", caught.level_of(Model.HUNGER) != Model.Level.CRITICAL)

	# Compare with what the Demo row would have done, to prove they differ.
	var wrong := Model.new()
	wrong.catch_up(HOUR, Config.intervals_from(config, Config.DEMO))
	_close("the Demo row would have maxed it", wrong.get_value(Model.HUNGER), 100.0)

	config["demo_speed"] = false
	_ok(
		"with Demo off the live drain uses the real setting too",
		Config.live_interval_name(config) == Config.MODERATE
	)


# How much of an absence a need spent at its bad end. Real play's starving
# clock is built on this: an absence is not the same thing as a starvation,
# and the difference is a dog's life.
func _test_seconds_at_critical() -> void:
	var hunger_interval: float = 3.0 * HOUR

	_begin("Time spent critical during an absence")
	_close(
		"a dog fed just before closing, away a minute over the interval",
		Model.seconds_at_critical(Model.HUNGER, 0.0, hunger_interval + MINUTE, hunger_interval),
		MINUTE
	)
	_close(
		"away for exactly the interval, and so starving for no time at all",
		Model.seconds_at_critical(Model.HUNGER, 0.0, hunger_interval, hunger_interval),
		0.0
	)
	_close(
		"away for less than the interval",
		Model.seconds_at_critical(Model.HUNGER, 0.0, HOUR, hunger_interval),
		0.0
	)
	_close(
		"half starved already when the app closed",
		Model.seconds_at_critical(Model.HUNGER, 50.0, 2.0 * HOUR, hunger_interval),
		0.5 * HOUR
	)
	_close(
		"already starving, so the whole absence counts",
		Model.seconds_at_critical(Model.HUNGER, 100.0, 5.0 * HOUR, hunger_interval),
		5.0 * HOUR
	)

	_begin("Time spent critical reads the need's own direction")
	# Happiness runs the other way: 100 is cared for, 0 is the bad end.
	_close(
		"a happy dog takes the full interval to get there",
		Model.seconds_at_critical(Model.HAPPINESS, 100.0, hunger_interval + MINUTE, hunger_interval),
		MINUTE
	)
	_close(
		"a miserable one is already there",
		Model.seconds_at_critical(Model.HAPPINESS, 0.0, HOUR, hunger_interval),
		HOUR
	)

	_begin("Time spent critical with nothing to measure")
	_close("no time away", Model.seconds_at_critical(Model.HUNGER, 100.0, 0.0, hunger_interval), 0.0)
	_close("a clock that went backwards", Model.seconds_at_critical(Model.HUNGER, 100.0, -HOUR, hunger_interval), 0.0)
	_close("an interval of zero means do not drain", Model.seconds_at_critical(Model.HUNGER, 100.0, HOUR, 0.0), 0.0)


func _test_actions() -> void:
	var effects: Dictionary = Config.DEFAULTS["action_effects"]

	_begin("Feed: hunger to 0, happiness +5")
	var fed := _model_at(80.0, 50.0, 50.0)
	fed.apply_action(&"feed", effects)
	_close("hunger", fed.get_value(Model.HUNGER), 0.0)
	_close("happiness", fed.get_value(Model.HAPPINESS), 55.0)
	_close("energy untouched", fed.get_value(Model.ENERGY), 50.0)

	_begin("Play: happiness to 100, energy -15, hunger +5")
	var played := _model_at(50.0, 20.0, 60.0)
	played.apply_action(&"play", effects)
	_close("happiness", played.get_value(Model.HAPPINESS), 100.0)
	_close("energy", played.get_value(Model.ENERGY), 45.0)
	_close("hunger", played.get_value(Model.HUNGER), 55.0)

	_begin("Walk: energy to 0, happiness +10, hunger +10")
	var walked := _model_at(50.0, 50.0, 90.0)
	walked.apply_action(&"walk", effects)
	_close("energy", walked.get_value(Model.ENERGY), 0.0)
	_close("happiness", walked.get_value(Model.HAPPINESS), 60.0)
	_close("hunger", walked.get_value(Model.HUNGER), 60.0)

	_begin("Action side effects clamp")
	var low := _model_at(0.0, 98.0, 5.0)
	low.apply_action(&"play", effects)
	_close("energy cannot go below 0", low.get_value(Model.ENERGY), 0.0)
	_close("happiness cannot go above 100", low.get_value(Model.HAPPINESS), 100.0)
	_close("hunger rose from 0", low.get_value(Model.HUNGER), 5.0)

	var topped := _model_at(0.0, 96.0, 50.0)
	topped.apply_action(&"feed", effects)
	_close("feeding a full dog keeps hunger at 0", topped.get_value(Model.HUNGER), 0.0)
	_close("and happiness clamps at 100", topped.get_value(Model.HAPPINESS), 100.0)

	_begin("An unknown action does nothing")
	var untouched := _model_at(42.0, 42.0, 42.0)
	untouched.apply_action(&"fly", effects)
	_close("hunger", untouched.get_value(Model.HUNGER), 42.0)


func _test_formatting() -> void:
	_begin("Countdown wording")
	var row: Dictionary = _intervals(Config.MODERATE)
	var model := Model.new()
	_close("a fresh dog has the full 3 h", model.seconds_to_critical(Model.HUNGER, row), 3.0 * HOUR)
	model.set_value(Model.HUNGER, 100.0)
	_close("a critical need has no time left", model.seconds_to_critical(Model.HUNGER, row), 0.0)

	_ok("0 seconds reads 'now'", Model.format_countdown(0.0) == "now")
	_ok("40 seconds reads '~40s'", Model.format_countdown(40.0) == "~40s")
	_ok("20 minutes reads '~20m'", Model.format_countdown(20.0 * MINUTE) == "~20m")
	_ok("80 minutes reads '~1h 20m'", Model.format_countdown(80.0 * MINUTE) == "~1h 20m")
	_ok("2 hours reads '~2h'", Model.format_countdown(2.0 * HOUR) == "~2h")

	_begin("Away-card duration wording")
	_ok("30 seconds", Model.format_duration(30.0) == "less than a minute")
	_ok("3h 12m", Model.format_duration(3.0 * HOUR + 12.0 * MINUTE) == "3h 12m")
	_ok("2d 4h", Model.format_duration(2.0 * DAY + 4.0 * HOUR) == "2d 4h")

	_begin("The dog says something sensible")
	var starving := _model_at(100.0, 100.0, 0.0)
	_ok("starving", starving.reaction_line("Biscuit") == "Biscuit is starving!")
	var fine := _model_at(10.0, 90.0, 10.0)
	_ok("doing fine", fine.reaction_line("Biscuit") == "Biscuit is doing just fine.")


func _test_corrupt_save_falls_back() -> void:
	_begin("A corrupt save falls back to the backup")
	var dir: String = ProjectSettings.globalize_path("user://test_saves")
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join("pet.json")
	_clean_up(path)

	_ok("nothing to read yet", Save.read_with_fallback(path).is_empty())
	_ok("and it says so", Save.last_read_source == "none")

	# First save becomes the backup once the second one lands.
	_ok("first write succeeds", Save.write_atomic(path, _payload(11.0, 1000.0)))
	_ok("second write succeeds", Save.write_atomic(path, _payload(22.0, 2000.0)))
	_ok("the backup file exists", FileAccess.file_exists(path + ".bak"))
	_ok("the temp file is gone", not FileAccess.file_exists(path + ".tmp"))

	var good: Dictionary = Save.read_with_fallback(path)
	_close("a healthy save reads back the newest values", float(good["hunger"]), 22.0)
	_ok("from the main file", Save.last_read_source == "main")

	# Now wreck pet.json the way a power cut might. Godot prints its own
	# "Parse JSON failed" error for this on purpose - that IS the test.
	print("  ....  the JSON error below is deliberate")
	var broken: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{\"hunger\": 22.0, \"happ")
	broken.close()

	var recovered: Dictionary = Save.read_with_fallback(path)
	_ok("the corrupt file is not used", not recovered.is_empty())
	_close("the backup's values come back instead", float(recovered["hunger"]), 11.0)
	_ok("and it says it used the backup", Save.last_read_source == "backup")

	# A save that parses but is missing fields is no good either.
	var partial: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	partial.store_string("{\"hunger\": 50.0}")
	partial.close()
	var from_bak: Dictionary = Save.read_with_fallback(path)
	_close("an incomplete save falls back too", float(from_bak["hunger"]), 11.0)

	# And with no backup at all, a corrupt save means a fresh dog.
	DirAccess.remove_absolute(path + ".bak")
	_ok("no backup, no save", Save.read_with_fallback(path).is_empty())

	_clean_up(path)


# --- Small helpers --------------------------------------------------------

func _intervals(name: String) -> Dictionary:
	return Config.intervals_from(Config.DEFAULTS, name)


func _model_at(hunger: float, happiness: float, energy: float) -> Object:
	var model := Model.new()
	model.set_value(Model.HUNGER, hunger)
	model.set_value(Model.HAPPINESS, happiness)
	model.set_value(Model.ENERGY, energy)
	return model


func _payload(hunger: float, saved_at: float) -> Dictionary:
	return {
		"format_version": Save.FORMAT_VERSION,
		"hunger": hunger,
		"happiness": 50.0,
		"energy": 50.0,
		"pet_name": "Biscuit",
		"pet_pack_id": "pug_3d",
		"last_saved_unix": saved_at,
	}


func _clean_up(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


func _begin(section: String) -> void:
	_section = section
	print("")
	print(section)


func _ok(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)


func _close(label: String, got: float, want: float, tolerance: float = 0.01) -> void:
	if absf(got - want) <= tolerance:
		_ok(label, true)
	else:
		_ok(label, false)
		print("          got %.4f, wanted %.4f" % [got, want])
