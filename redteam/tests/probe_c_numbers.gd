extends SceneTree
const Model := preload("res://scripts/needs_model.gd")
const Life := preload("res://scripts/life_model.gd")
const Save := preload("res://scripts/save_file.gd")
const Limits := preload("res://scripts/image_limits.gd")
const Text := preload("res://scripts/needs_text.gd")
const Care := preload("res://scripts/care_settings.gd")

func _init() -> void:
	print("--- JSON extremes ---")
	var parsed: Variant = JSON.parse_string('{"a": 1e999, "b": -1e999}')
	print("1e999 parses to: ", parsed)
	print("is_inf(a): ", is_inf(float((parsed as Dictionary)["a"])))

	print("stringify INF: ", JSON.stringify({"x": INF}))
	print("stringify NAN: ", JSON.stringify({"y": NAN}))
	print("reparse of NAN payload is Dictionary: ",
		JSON.parse_string(JSON.stringify({"y": NAN})) is Dictionary)

	print("--- NeedsModel with an infinite elapsed ---")
	var m = Model.new()
	m.set_value(Model.HUNGER, 0.0)
	var elapsed: float = Model.elapsed_between(-INF, 1.0)
	print("elapsed_between(-inf, now) = ", elapsed)
	m.catch_up(elapsed, {Model.HUNGER: 10800.0, Model.HAPPINESS: 12600.0, Model.ENERGY: 14400.0})
	print("needs after: ", m.describe())
	var starving: float = Model.seconds_at_critical(Model.HUNGER, 0.0, elapsed, 10800.0)
	print("seconds_at_critical = ", starving)
	print("well_fed_for = elapsed - starving = ", elapsed - starving,
		"  is_nan: ", is_nan(elapsed - starving))

	print("--- LifeModel with infinite seconds ---")
	var life = Life.new()
	life.reset(0.0)
	var news: Dictionary = life.advance(INF, false, false, 10800.0, {}, 0.5, 0.0)
	print("age_days after advance(INF): ", life.age_days, " news: ", news)
	print("to_dictionary: ", life.to_dictionary())
	print("stringify of that: ", JSON.stringify(life.to_dictionary()))

	print("--- LifeModel: a zero starve grace in settings.json (RT-04) ---")
	var l2 = Life.new()
	l2.reset(0.0)
	var r: Dictionary = l2.advance(0.016, false, true, 10800.0,
		{"starve_grace_intervals": 0.0}, 0.99, 100.0)
	print("not hungry at all, grace 0 -> died: ", r.get("died"), " alive: ", l2.alive)
	var l3 = Life.new()
	l3.reset(0.0)
	var r3: Dictionary = l3.advance(0.016, false, true, 10800.0,
		{"starve_grace_intervals": -5.0}, 0.99, 100.0)
	print("negative grace -> died: ", r3.get("died"))

	print("--- and through the settings layer ---")
	for asked in [0.0, -5.0]:
		var floored: Dictionary = Care.real_play_from(
			{"real_play": {"starve_grace_intervals": asked}})
		print("settings.json asking for grace %s -> CareSettings gives %s" % [
			asked, floored["starve_grace_intervals"]])
	var sane: Dictionary = Care.real_play_from(
		{"real_play": {"starve_grace_intervals": 0.0}})
	var fed = Life.new()
	fed.reset(0.0)
	fed.advance(3600.0, false, true, 10800.0, sane, 1.0, 100.0)
	print("a fed dog with that settings file survives: ", fed.alive)
	var hungry = Life.new()
	hungry.reset(0.0)
	for _step in 100:
		hungry.advance(3600.0, true, true, 10800.0, sane, 1.0, 100.0)
	print("a starving dog still dies on time: ", not hungry.alive)

	print("--- ImageLimits overflow ---")
	var huge := Vector2i(4294967295, 4294967295)
	print("4294967295 x 4294967295 product = ", huge.x * huge.y)
	print("is_too_large says: ", Limits.is_too_large(huge))
	var h2 := Vector2i(3037000500, 3037000500)
	print("3037000500^2 = ", h2.x * h2.y, " is_too_large: ", Limits.is_too_large(h2))

	print("--- format_duration / countdown with inf ---")
	print("format_duration(INF) = ", Text.format_duration(INF))
	print("format_countdown(INF) = ", Text.format_countdown(INF))
	quit(0)
