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

const AUTOSAVE_SECONDS := 30.0

## Only bother with the "While you were away" card for a real absence.
const AWAY_CARD_MIN_SECONDS := 60.0

const DEFAULT_PET_NAME := "Biscuit"
const DEFAULT_PET_PACK_ID := "pug_3d"

var model := NeedsModel.new()

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


func _ready() -> void:
	# Under --script there is no game, only a script: the headless tests.
	# Don't load, drain or overwrite the owner's real save.
	if Paths.tool_script_mode:
		set_process(false)
		return

	var elapsed: float = 0.0
	var before: Dictionary = {}

	var save: Dictionary = SaveFile.read_with_fallback(Paths.pet_save_path())
	if save.is_empty():
		Log.info("No usable save found; starting a fresh, fully cared-for dog.")
		model.reset_to_cared()
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
		model.catch_up(elapsed, Settings.catch_up_intervals())
		Log.info("Loaded a save from %s ago. Needs now: %s" % [
			NeedsModel.format_duration(elapsed),
			model.describe(),
		])

	_levels = model.levels()
	for key in NeedsModel.KEYS:
		_shown[key] = roundi(model.get_value(key))

	if elapsed > AWAY_CARD_MIN_SECONDS:
		_away_summary = {
			"elapsed": elapsed,
			"before": before,
			"after": model.to_dictionary(),
			"reaction": model.reaction_line(pet_name),
		}

	save_now()


func _process(delta: float) -> void:
	model.drain(delta, Settings.live_intervals())
	_announce_changes()
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


func reaction_line() -> String:
	return model.reaction_line(pet_name)


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
	model.apply_action(action, Settings.action_effects())
	Log.info("%s: %s" % [String(action).capitalize(), model.describe()])
	_announce_changes()
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
