extends SceneTree
## Headless tests for the notification rules and the icon pack.
##
## Run them from the project root with:
##
##   godot --headless --path . --script res://tests/test_notify.gd
##
## The part worth testing here is the decision of whether to speak at all.
## Being told once when a need goes bad is helpful; being told every frame
## it stays bad would be unbearable, and the difference is one comparison.

const Rules := preload("res://scripts/notification_rules.gd")
const Icons := preload("res://scripts/ui_pack.gd")
const Model := preload("res://scripts/needs_model.gd")

const FINE := 0
const WARNING := 1
const CRITICAL := 2

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	print("")
	print("DogPet notification tests")
	print("=========================")

	_test_when_to_speak()
	_test_what_to_say()
	_test_tray_display()
	_test_icon_pack()

	print("")
	print("=========================")
	print("%d passed, %d failed" % [_passed, _failed])
	print("TESTS FAILED" if _failed > 0 else "All good.")
	quit(1 if _failed > 0 else 0)


func _test_when_to_speak() -> void:
	_begin("Speak up when things get worse")
	_ok("fine to getting low", Rules.is_worth_announcing(FINE, WARNING))
	_ok("getting low to needs care now", Rules.is_worth_announcing(WARNING, CRITICAL))
	_ok("fine straight to critical", Rules.is_worth_announcing(FINE, CRITICAL))

	_begin("Stay quiet otherwise")
	# This is the one that matters: the level is re-checked constantly, so
	# without it the owner would be told every single frame.
	_ok("still at the same level", not Rules.is_worth_announcing(WARNING, WARNING))
	_ok("still critical", not Rules.is_worth_announcing(CRITICAL, CRITICAL))
	_ok("recovering to getting low", not Rules.is_worth_announcing(CRITICAL, WARNING))
	_ok("back to fine is good news", not Rules.is_worth_announcing(CRITICAL, FINE))
	_ok("fine to fine", not Rules.is_worth_announcing(FINE, FINE))

	_begin("Levels line up with the needs model")
	_ok("fine", int(Model.Level.FINE) == FINE)
	_ok("warning", int(Model.Level.WARNING) == WARNING)
	_ok("critical", int(Model.Level.CRITICAL) == CRITICAL)


func _test_what_to_say() -> void:
	_begin("Every need has something to say at every level")
	for key in Model.KEYS:
		for level in [WARNING, CRITICAL]:
			var title: String = Rules.title_for(key, level, "Biscuit")
			var body: String = Rules.body_for(key, level)
			_ok("%s at level %d names the dog" % [key, level], title.contains("Biscuit"))
			_ok("%s at level %d says something" % [key, level], title.length() > 10)
			_ok("%s at level %d suggests what to do" % [key, level], not body.is_empty())

	_begin("The wording matches the blueprint")
	_ok(
		"getting hungry",
		Rules.title_for(Model.HUNGER, WARNING, "Biscuit") == "Biscuit is getting hungry."
	)
	_ok(
		"starving",
		Rules.title_for(Model.HUNGER, CRITICAL, "Biscuit") == "Biscuit is starving!"
	)
	_ok("time to feed", Rules.body_for(Model.HUNGER, CRITICAL) == "Time to feed.")

	_begin("Critical reads more urgently than a warning")
	for key in Model.KEYS:
		var warn: String = Rules.title_for(key, WARNING, "Biscuit")
		var crit: String = Rules.title_for(key, CRITICAL, "Biscuit")
		_ok("%s says something different when critical" % key, warn != crit)

	_begin("A dog called anything still works")
	var odd: String = Rules.title_for(Model.HUNGER, CRITICAL, "Rex & \"Bear\"")
	_ok("the name comes through as given", odd.contains("Rex & \"Bear\""))


func _test_tray_display() -> void:
	_begin("The tray tooltip reports all three needs")
	var values: Dictionary = {Model.HUNGER: 62.0, Model.HAPPINESS: 40.0, Model.ENERGY: 75.4}
	var tooltip: String = Rules.tooltip_for(values, "Biscuit")
	_ok("it names the dog", tooltip.contains("Biscuit"))
	_ok("hunger", tooltip.contains("Hunger 62%"))
	_ok("happiness", tooltip.contains("Happiness 40%"))
	_ok("energy is rounded", tooltip.contains("Energy 75%"))

	_begin("The alert icon goes up as soon as anything needs care")
	var calm: Dictionary = {Model.HUNGER: FINE, Model.HAPPINESS: FINE, Model.ENERGY: FINE}
	_ok("all fine, normal icon", not Rules.wants_alert_icon(calm))
	for key in Model.KEYS:
		var one_bad: Dictionary = calm.duplicate()
		one_bad[key] = WARNING
		_ok("%s getting low raises it" % key, Rules.wants_alert_icon(one_bad))
		one_bad[key] = CRITICAL
		_ok("%s critical raises it" % key, Rules.wants_alert_icon(one_bad))


func _test_icon_pack() -> void:
	_begin("The shipped icon pack loads")
	var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var pack: UiPack = Icons.load_from_dir(root.path_join("assets/ui"))
	_ok("it is usable", pack.is_usable())
	for problem in pack.problems:
		print("          %s" % problem)
	_ok("there is a tray icon", not pack.tray_icon_path().is_empty())
	_ok("and an alert version", pack.tray_icon_alert != "")
	_ok("they are different files", pack.tray_icon != pack.tray_icon_alert)

	_begin("Every need and button has an icon")
	for key in Model.KEYS:
		_ok("%s icon" % key, not pack.need_icon_path(String(key)).is_empty())
	for action in ["feed", "play", "walk"]:
		_ok("%s button icon" % action, not pack.button_icon_path(action).is_empty())

	_begin("A missing icon pack does not crash")
	var nothing: UiPack = Icons.load_from_dir("res://nowhere")
	_ok("it is not usable", not nothing.is_usable())
	_ok("it says why", not nothing.problems.is_empty())
	_ok("asking for a path gives nothing back", nothing.tray_icon_path().is_empty())
	_ok("and so does an unknown need", nothing.need_icon_path("hunger").is_empty())

	_begin("The alert icon falls back to the normal one")
	var half := Icons.new()
	half.dir = "res://x"
	half.tray_icon = "a.png"
	_ok("rather than leaving the tray blank", half.tray_alert_path().ends_with("a.png"))


# --- Small helpers -------------------------------------------------------

func _begin(section: String) -> void:
	print("")
	print(section)


func _ok(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)
