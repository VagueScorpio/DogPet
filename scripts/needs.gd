extends Node
## The live needs: drains them every frame, saves them, and catches them up
## for however long the app was closed.
##
## All the arithmetic lives in NeedsModel, which knows nothing about nodes or
## clocks. This script is the half that has a clock, a save file and signals.
##
## It also owns the dog's name and which pet pack it is wearing, because both
## are saved in pet.json alongside the three needs.

## A need's displayed percentage changed. Fires when the rounded number
## changes, not every frame, so connecting to it is cheap.
signal need_changed(key: StringName, value: float)

## A need moved between Fine, Getting low and Needs care now. The level is a
## NeedsModel.Level, passed as an int so the signal stays simple.
signal threshold_crossed(key: StringName, level: int)

signal pet_name_changed(new_name: String)

## Real play only. The dog has died; the owner must start a new one.
signal pet_died(cause: int, pet_name: String, age_days: float)
signal fell_ill()
signal healed()
## A new dog has been started, so everything on screen should reset.
signal pet_started()

const AUTOSAVE_SECONDS := 30.0

## Only bother with the "While you were away" card for a real absence.
const AWAY_CARD_MIN_SECONDS := 60.0

const DEFAULT_PET_NAME := "Biscuit"
const DEFAULT_PET_PACK_ID := "pug_3d"

var model := NeedsModel.new()

## Ageing, illness and death. Does nothing at all in Casual play.
var life := LifeModel.new()

var _rng := RandomNumberGenerator.new()

var pet_name: String = DEFAULT_PET_NAME
var pet_pack_id: String = DEFAULT_PET_PACK_ID

# Last level we announced per need, so threshold_crossed fires once per
# crossing rather than every frame the need sits there.
var _levels: Dictionary[StringName, int] = {}

# Last whole percentage we announced per need, for the same reason.
var _shown: Dictionary[StringName, int] = {}

var _autosave_left: float = AUTOSAVE_SECONDS

# The catch-up summary, waiting for Main to collect it. The autoloads all
# run before the first scene exists, so there is nobody listening to a
# signal yet; Main asks for this in its own _ready instead.
var _away_summary: Dictionary = {}

# How long since the last care action, so the dog can look pleased with
# itself for a few seconds afterwards. Negative means nothing has happened
# yet this run.
var _since_action: float = -1.0


func _ready() -> void:
	# Under --script there is no game, only a script: the headless tests.
	# Don't load, drain or overwrite the owner's real save.
	if Paths.tool_script_mode:
		set_process(false)
		return

	var elapsed: float = 0.0
	var before: Dictionary = {}

	var save: Dictionary = SaveFile.read_with_fallback(Paths.pet_save_path())
	_rng.randomize()

	if save.is_empty():
		Log.info("No usable save found; starting a fresh, fully cared-for dog.")
		model.reset_to_cared()
		life.reset(Time.get_unix_time_from_system())
	else:
		if SaveFile.last_read_source == "backup":
			Log.warn("pet.json was unusable, so the dog was restored from pet.json.bak.")
		model.from_dictionary(save)
		pet_name = str(save.get("pet_name", DEFAULT_PET_NAME))
		pet_pack_id = str(save.get("pet_pack_id", DEFAULT_PET_PACK_ID))
		before = model.to_dictionary()
		elapsed = NeedsModel.elapsed_between(
			float(save.get("last_saved_unix", 0.0)),
			Time.get_unix_time_from_system()
		)
		# Always the real care setting here, never Demo Speed. See
		# Settings.catch_up_interval_name for why.
		life.from_dictionary(save.get("life", {}))
		if life.born_unix <= 0.0:
			# A save from before Real play existed. Treat the dog as born
			# when it was last saved rather than at the epoch.
			life.born_unix = float(save.get("last_saved_unix", Time.get_unix_time_from_system()))
		model.catch_up(elapsed, Settings.catch_up_intervals())
		# The hunger the dog started the absence with, so the starving clock
		# only counts the part of it the bowl was actually empty.
		_catch_up_life(elapsed, float(before.get(String(NeedsModel.HUNGER), 0.0)))
		Log.info("Loaded a save from %s ago. Needs now: %s%s" % [
			NeedsModel.format_duration(elapsed),
			model.describe(),
			"" if life.alive else "  (died of %s while away)" % LifeModel.cause_name(life.cause),
		])

	_levels = model.levels()
	for key in NeedsModel.KEYS:
		_shown[key] = roundi(model.get_value(key))

	if elapsed > AWAY_CARD_MIN_SECONDS:
		_away_summary = {
			"elapsed": elapsed,
			"before": before,
			"after": model.to_dictionary(),
			# The death-aware line: a dog that starved while the app was shut
			# should not be described as merely "very hungry".
			"reaction": reaction_line(),
		}

	save_now()


func _process(delta: float) -> void:
	# A dead dog does not get hungrier. Everything stops until the owner
	# starts a new one.
	if not life.alive:
		return
	model.drain(delta, Settings.live_intervals())
	_advance_life(
		delta,
		Settings.live_interval_for(NeedsModel.HUNGER),
		model.level_of(NeedsModel.HUNGER) >= int(NeedsModel.Level.CRITICAL)
	)
	_announce_changes()
	if _since_action >= 0.0:
		_since_action += delta
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		save_now()


func _notification(what: int) -> void:
	if not is_inside_tree() or Paths.tool_script_mode:
		return
	# Save on the way out, however the app is closing.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_now()


# --- Reading the needs ---------------------------------------------------

func value_of(key: StringName) -> float:
	return model.get_value(key)


func level_of(key: StringName) -> int:
	return int(model.level_of(key))


## Seconds until this need is critical, at the rate it is draining now.
func seconds_to_critical(key: StringName) -> float:
	return model.seconds_to_critical(key, Settings.live_intervals())


## "~1h 20m", or "now".
func countdown_text(key: StringName) -> String:
	return NeedsModel.format_countdown(seconds_to_critical(key))


## What the dog looks like it is feeling, in one line.
##
## Illness and death come first: a dog with a fever is not "doing just
## fine" however full its bowl is.
func reaction_line() -> String:
	if not life.alive:
		return LifeModel.death_line(pet_name, life.cause)
	if life.ill:
		return "%s is unwell." % pet_name
	return model.reaction_line(pet_name)


# --- Ageing, illness and death -------------------------------------------

# The catch-up runs at the real care setting, never Demo, exactly as the
# needs do - otherwise a demo session would kill the dog overnight.
#
# The absence is split in two: the stretch before hunger reached the bad end,
# and the stretch after it. Only the second one feeds the starving clock. Done
# in one piece instead, a dog fed right before the app closed and away for
# three hours and a minute on Moderate would be credited with three hours and
# a minute of starvation and die on the spot, when in truth it had been
# starving for one minute.
func _catch_up_life(elapsed: float, hunger_before: float) -> void:
	var interval: float = float(Settings.catch_up_intervals().get(NeedsModel.HUNGER, 0.0))
	var starving_for: float = NeedsModel.seconds_at_critical(
		NeedsModel.HUNGER, hunger_before, elapsed, interval
	)
	var well_fed_for: float = elapsed - starving_for
	if well_fed_for > 0.0:
		_advance_life(well_fed_for, interval, false, true)
	if starving_for > 0.0 and life.alive:
		_advance_life(starving_for, interval, true, true)


func _advance_life(
	seconds: float,
	hunger_interval: float,
	hunger_is_critical: bool,
	catching_up: bool = false
) -> void:
	var was_ill: bool = life.ill
	var news: Dictionary = life.advance(
		seconds,
		hunger_is_critical,
		Settings.is_real_play(),
		hunger_interval,
		Settings.real_play(),
		_rng.randf(),
		Time.get_unix_time_from_system()
	)
	if bool(news.get("fell_ill", false)) and not was_ill:
		Log.info("%s has fallen ill." % pet_name)
		if not catching_up:
			fell_ill.emit()
	if bool(news.get("died", false)):
		Log.info("%s died of %s at %s." % [
			pet_name, LifeModel.cause_name(life.cause), LifeModel.format_age(life.age_days),
		])
		_remember_this_dog()
		save_now()
		# While catching up there is no scene yet, so nothing is listening and
		# the signal would simply be lost. Main looks at life.alive in its own
		# _ready instead, which also covers reopening an already-dead save.
		if not catching_up:
			pet_died.emit(life.cause, pet_name, life.age_days)
		return
	if catching_up:
		save_now()


# Write the dog into the record the moment it dies, rather than when the
# owner gets round to starting another. Done here and nowhere else, so a
# reload of an already-dead save cannot record the same dog twice:
# LifeModel.advance returns early once alive is false.
func _remember_this_dog() -> void:
	var record: Dictionary = PetHistory.make_record(
		pet_name, life.born_unix, life.died_unix, life.age_days, life.cause
	)
	if not PetHistory.remember(Paths.history_path(), record):
		Log.error("Could not write %s into the record." % pet_name)


## Take the dog to the vet. Returns true if that was enough to cure it.
func take_to_vet() -> bool:
	# The button is hidden and the action runner refuses, but this is the
	# door all of them go through, so the guard belongs here as well.
	if not life.alive:
		return false
	var cured: bool = life.treat(float(Settings.real_play().get("vet_visit_heals", 60.0)))
	save_now()
	if cured:
		Log.info("%s is well again." % pet_name)
		healed.emit()
	return cured


## Bury the old dog and start a new one. Everything resets.
func start_new_pet(new_name: String) -> void:
	var cleaned: String = new_name.strip_edges()
	if not cleaned.is_empty():
		pet_name = cleaned
	model.reset_to_cared()
	life.reset(Time.get_unix_time_from_system())
	# Announced rather than quietly written over the old levels: the bars and
	# the notifier both learn what a need is doing from threshold_crossed, so
	# resetting silently left a brand-new dog's bars still reading "Needs care
	# now" in red, and left the notifier thinking it had already warned.
	_announce_changes()
	_since_action = -1.0
	save_now()
	Log.info("A new dog: %s." % pet_name)
	pet_name_changed.emit(pet_name)
	pet_started.emit()


## Which animation state suits the dog right now, when it is not busy doing
## something the owner asked for.
func mood_state() -> StringName:
	# An ill dog mopes, whatever its needs say.
	if not life.alive or life.ill:
		return &"sad"
	return model.mood_state(_since_action)


func seconds_since_action() -> float:
	return _since_action


## Hand Main the catch-up summary, once. Empty when there is nothing to show.
func take_away_summary() -> Dictionary:
	var summary: Dictionary = _away_summary
	_away_summary = {}
	return summary


# --- Changing the needs --------------------------------------------------

## Run a care action: "feed", "play" or "walk".
##
## This is only the effect on the needs. The animation, the scene change and
## the button locking are Main's job, and arrive in a later phase.
func apply_action(action: StringName) -> void:
	# Same reasoning as take_to_vet: a dead dog's needs are not topped up,
	# whichever caller asks for it.
	if not life.alive:
		return
	model.apply_action(action, Settings.action_effects())
	_since_action = 0.0
	Log.info("%s: %s" % [String(action).capitalize(), model.describe()])
	_announce_changes()
	save_now()


## Remember which pet pack the dog is wearing. AssetLibrary calls this;
## the needs themselves are untouched, because it is the same dog.
func set_pet_pack_id(id: String) -> void:
	if id.is_empty() or id == pet_pack_id:
		return
	pet_pack_id = id
	save_now()


func set_pet_name(new_name: String) -> void:
	var cleaned: String = new_name.strip_edges()
	if cleaned.is_empty() or cleaned == pet_name:
		return
	pet_name = cleaned
	save_now()
	pet_name_changed.emit(pet_name)


## Put every need back to fully cared for. A debug convenience.
func reset_to_cared() -> void:
	model.reset_to_cared()
	_announce_changes()
	save_now()


# --- Saving --------------------------------------------------------------

func save_now() -> void:
	var payload: Dictionary = {
		"format_version": SaveFile.FORMAT_VERSION,
		"pet_name": pet_name,
		"pet_pack_id": pet_pack_id,
		"last_saved_unix": Time.get_unix_time_from_system(),
		"life": life.to_dictionary(),
	}
	payload.merge(model.to_dictionary())
	if not SaveFile.write_atomic(Paths.pet_save_path(), payload):
		Log.error("Could not save the dog to " + Paths.pet_save_path())


# --- Signals -------------------------------------------------------------

func _announce_changes() -> void:
	for key in NeedsModel.KEYS:
		var value: float = model.get_value(key)
		var shown: int = roundi(value)
		if _shown.get(key, -1) != shown:
			_shown[key] = shown
			need_changed.emit(key, value)
		var level: int = int(model.level_of(key))
		if _levels.get(key, -1) != level:
			_levels[key] = level
			threshold_crossed.emit(key, level)
