extends SceneTree
## Headless tests for ageing, illness and death.
##
## Run them from the project root with:
##
##   godot --headless --path . --script res://tests/test_life.gd
##
## This is the suite that matters most. Everywhere else a bug costs a
## wrong-looking bar; here it costs somebody's pet. The two rules worth
## stating plainly, because every check below is really about one of them:
##
##   In Casual play nothing can ever kill the dog.
##   In Real play a starving dog gets one full care interval of grace.

const Life := preload("res://scripts/life_model.gd")
const Config := preload("res://scripts/care_settings.gd")

const HOUR := 3600.0
# Moderate hunger, which is what the defaults use.
const INTERVAL := 3.0 * HOUR

var _passed: int = 0
var _failed: int = 0
var _tuning: Dictionary = {}


func _initialize() -> void:
	print("")
	print("DogPet life tests")
	print("=================")
	_tuning = Config.DEFAULTS["real_play"]

	_test_casual_never_kills()
	_test_ageing()
	_test_starving()
	_test_illness()
	_test_vet()
	_test_saving()

	print("")
	print("=================")
	print("%d passed, %d failed" % [_passed, _failed])
	print("TESTS FAILED" if _failed > 0 else "All good.")
	quit(1 if _failed > 0 else 0)


# A dog that is always starving, always unlucky, for as long as you like.
func _run(life: LifeModel, seconds: float, starving: bool, real: bool, roll: float = 1.0) -> Dictionary:
	return life.advance(seconds, starving, real, INTERVAL, _tuning, roll, 1000.0)


func _fresh() -> LifeModel:
	var life := Life.new()
	life.reset(0.0)
	return life


# --- The promise of Casual play -------------------------------------------

func _test_casual_never_kills() -> void:
	_begin("Casual play cannot kill the dog, whatever happens")
	var life: LifeModel = _fresh()
	# A fortnight of being starved, with the worst luck possible.
	for _step in 200:
		_run(life, HOUR, true, false, 0.0)
	_ok("still alive", life.alive)
	_ok("never fell ill", not life.ill)
	_ok("no sickness at all", is_equal_approx(life.sickness, 0.0))
	_ok("the starving clock never even started", is_equal_approx(life.starving_seconds, 0.0))
	_ok("but it did get older", life.age_days > 0.0)

	_begin("Switching to Casual clears anything Real play left behind")
	var ill: LifeModel = _fresh()
	_run(ill, HOUR, false, true, 0.0)
	_run(ill, INTERVAL * 0.5, false, true)
	_ok("it was ill in Real play", ill.ill and ill.sickness > 0.0)
	_run(ill, 1.0, false, false)
	_ok("Casual cures it on the spot", not ill.ill)
	_ok("and empties the bar", is_equal_approx(ill.sickness, 0.0))


# --- Ageing ----------------------------------------------------------------

func _test_ageing() -> void:
	_begin("The dog ages at two hunger intervals to the day")
	var life: LifeModel = _fresh()
	_run(life, INTERVAL * 2.0, false, true)
	_close("one day", life.age_days, 1.0)
	_run(life, INTERVAL * 2.0 * 9.0, false, true)
	_close("ten days", life.age_days, 10.0)

	_begin("Ageing happens in Casual play too")
	var casual: LifeModel = _fresh()
	_run(casual, INTERVAL * 2.0 * 5.0, false, false)
	_close("five days", casual.age_days, 5.0)

	_begin("Life stages")
	_ok("a newborn is a Puppy", Life.stage_for(0.0) == "Puppy")
	_ok("so is a two-day-old", Life.stage_for(2.9) == "Puppy")
	_ok("three days is Young", Life.stage_for(3.0) == "Young")
	_ok("ten days is Adult", Life.stage_for(10.0) == "Adult")
	_ok("forty days is Senior", Life.stage_for(40.0) == "Senior")
	_ok("and stays Senior", Life.stage_for(900.0) == "Senior")

	_begin("Old age is not fatal, as chosen")
	var ancient: LifeModel = _fresh()
	# Three years of dog-days, fed and well throughout.
	_run(ancient, INTERVAL * 2.0 * 1000.0, false, true)
	_ok("a very old dog is still alive", ancient.alive)
	_ok("and is a Senior", ancient.stage() == "Senior")

	_begin("Age reads plainly")
	_ok("newborn", Life.format_age(0.0) == "newborn")
	_ok("hours while young", Life.format_age(0.5) == "12 hours old")
	_ok("one day", Life.format_age(1.0) == "1 day old")
	_ok("many days", Life.format_age(12.7) == "12 days old")


# --- Starving --------------------------------------------------------------

func _test_starving() -> void:
	_begin("A starving dog gets one full interval of grace")
	var life: LifeModel = _fresh()
	_run(life, INTERVAL * 0.99, true, true)
	_ok("not yet", life.alive)
	_close("the clock has been running", life.starving_seconds, INTERVAL * 0.99)
	_run(life, INTERVAL * 0.02, true, true)
	_ok("and then it is over", not life.alive)
	_ok("of starvation", life.cause == Life.Cause.STARVATION)

	_begin("Feeding the dog stops the clock")
	var fed: LifeModel = _fresh()
	_run(fed, INTERVAL * 0.9, true, true)
	_ok("it was nearly gone", fed.starving_fraction(INTERVAL) > 0.85)
	_run(fed, 1.0, false, true)
	_close("and now the clock is back to nothing", fed.starving_seconds, 0.0)
	_run(fed, INTERVAL * 0.9, true, true)
	_ok("so it survives another long spell", fed.alive)

	_begin("The clock only runs while hunger is actually at the bad end")
	var comfy: LifeModel = _fresh()
	for _step in 100:
		_run(comfy, HOUR, false, true)
	_ok("a fed dog never starts starving", is_equal_approx(comfy.starving_seconds, 0.0))
	_ok("and lives", comfy.alive)

	_begin("Death while the app was closed")
	# The owner chose that catch-up can kill, so a long absence must.
	var away: LifeModel = _fresh()
	_run(away, 3.0 * 24.0 * HOUR, true, true)
	_ok("three days of starving is fatal", not away.alive)
	_ok("of starvation", away.cause == Life.Cause.STARVATION)

	_begin("Nothing happens to a dog that is already dead")
	var gone: LifeModel = _fresh()
	_run(gone, INTERVAL * 2.0, true, true)
	var age_at_death: float = gone.age_days
	_run(gone, INTERVAL * 50.0, true, true, 0.0)
	_close("it does not keep ageing", gone.age_days, age_at_death)
	_ok("and does not fall ill in the grave", not gone.ill)


# --- Illness ---------------------------------------------------------------

func _test_illness() -> void:
	_begin("Falling ill is a matter of luck")
	var unlucky: LifeModel = _fresh()
	var news: Dictionary = _run(unlucky, HOUR, false, true, 0.0)
	_ok("the unluckiest roll falls ill", unlucky.ill)
	_ok("and it is reported", bool(news["fell_ill"]))
	_ok("the bar starts somewhere visible", unlucky.sickness > 0.0)

	var lucky: LifeModel = _fresh()
	_run(lucky, HOUR, false, true, 1.0)
	_ok("the luckiest roll does not", not lucky.ill)

	_begin("A longer wait makes illness likelier")
	# Same roll, different lengths: the short one survives it, the long one
	# does not. This is what keeps a week away from being as safe as a
	# minute away.
	var brief: LifeModel = _fresh()
	_run(brief, 60.0, false, true, 0.2)
	var long: LifeModel = _fresh()
	_run(long, INTERVAL * 20.0, false, true, 0.2)
	_ok("a minute is probably fine", not brief.ill)
	_ok("a very long absence is not", long.ill)

	_begin("An untreated illness becomes fatal")
	var ill: LifeModel = _fresh()
	_run(ill, HOUR, false, true, 0.0)
	_run(ill, INTERVAL * 1.4, false, true)
	_ok("still alive at 1.4 intervals", ill.alive)
	_ok("but the bar is high", ill.sickness > 80.0)
	_run(ill, INTERVAL * 0.2, false, true)
	_ok("and fatal by 1.5", not ill.alive)
	_ok("of illness", ill.cause == Life.Cause.SICKNESS)

	_begin("A well dog cannot fall ill twice over")
	var once: LifeModel = _fresh()
	_run(once, HOUR, false, true, 0.0)
	var before: float = once.sickness
	var again: Dictionary = _run(once, HOUR, false, true, 0.0)
	_ok("the second roll is not reported as new", not bool(again["fell_ill"]))
	_ok("the illness simply carries on", once.sickness > before)


# --- The vet ---------------------------------------------------------------

func _test_vet() -> void:
	_begin("A trip to the vet brings the bar down")
	var life: LifeModel = _fresh()
	_run(life, HOUR, false, true, 0.0)
	_run(life, INTERVAL * 1.4, false, true)
	var before: float = life.sickness
	var heals: float = float(_tuning["vet_visit_heals"])
	var cured: bool = life.treat(heals)
	_close("down by the visit's worth", life.sickness, before - heals)
	_ok("but one visit was not enough", not cured)
	_ok("so the dog is still ill", life.ill)

	_begin("Going back finishes the job")
	cured = life.treat(heals)
	_ok("cured", cured)
	_ok("not ill any more", not life.ill)
	_close("and the bar is empty", life.sickness, 0.0)

	_begin("The vet cannot make things worse")
	var well: LifeModel = _fresh()
	_ok("treating a well dog is harmless", well.treat(heals))
	_close("the bar stays at nothing", well.sickness, 0.0)
	_ok("and it is still well", not well.ill)

	_begin("A cured dog carries on living")
	var recovered: LifeModel = _fresh()
	_run(recovered, HOUR, false, true, 0.0)
	recovered.treat(100.0)
	_run(recovered, INTERVAL * 5.0, false, true, 1.0)
	_ok("alive", recovered.alive)
	_ok("and well", not recovered.ill)


# --- Saving ----------------------------------------------------------------

func _test_saving() -> void:
	_begin("The whole of a life survives a save and load")
	var life: LifeModel = _fresh()
	_run(life, HOUR, true, true, 0.0)
	_run(life, INTERVAL * 0.3, true, true)

	var copy: LifeModel = Life.new()
	copy.from_dictionary(life.to_dictionary())
	_close("age", copy.age_days, life.age_days, 0.0001)
	_close("sickness", copy.sickness, life.sickness, 0.0001)
	_ok("illness", copy.ill == life.ill)
	_close("the starving clock", copy.starving_seconds, life.starving_seconds, 0.0001)
	_ok("alive", copy.alive == life.alive)
	_close("birthday", copy.born_unix, life.born_unix, 0.0001)

	_begin("A save from before Real play existed does not break")
	var old: LifeModel = Life.new()
	old.from_dictionary({})
	_ok("the dog is alive", old.alive)
	_ok("and well", not old.ill)
	_close("and newborn", old.age_days, 0.0)

	_begin("Nonsense in the save file is ignored")
	var junk: LifeModel = Life.new()
	junk.from_dictionary({"age_days": "yesterday", "sickness": 5000.0, "born_unix": -3.0})
	_close("a bad age falls back to nothing", junk.age_days, 0.0)
	_close("sickness is clamped", junk.sickness, 100.0)

	_begin("Starting again wipes the slate")
	var reborn: LifeModel = _fresh()
	_run(reborn, INTERVAL * 2.0, true, true)
	_ok("the old dog died", not reborn.alive)
	reborn.reset(555.0)
	_ok("the new one is alive", reborn.alive)
	_close("newborn", reborn.age_days, 0.0)
	_close("with a birthday", reborn.born_unix, 555.0)
	_ok("no cause of death hanging about", reborn.cause == Life.Cause.NONE)

	_begin("Death is described plainly")
	_ok("starvation", Life.death_line("Biscuit", Life.Cause.STARVATION) == "Biscuit starved.")
	_ok("illness", Life.death_line("Biscuit", Life.Cause.SICKNESS).contains("did not recover"))


# --- Small helpers ---------------------------------------------------------

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


func _close(label: String, got: float, want: float, tolerance: float = 0.01) -> void:
	if absf(got - want) <= tolerance:
		_ok(label, true)
	else:
		_ok(label, false)
		print("          got %.4f, wanted %.4f" % [got, want])
