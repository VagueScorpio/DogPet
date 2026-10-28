class_name NeedsModel
extends RefCounted
## The needs maths, with no nodes, no scenes and no clock of its own.
##
## Time always arrives as an argument, so the exact same code runs the live
## game, the offline catch-up and the headless tests. Needs.gd is the wrapper
## that owns a clock and a save file; everything here is pure arithmetic you
## can reason about on paper.
##
## All three needs are 0-100, but they do not all point the same way:
##
##   Hunger     rises over time. 100 means starving.
##   Happiness  falls over time. 0 means miserable.
##   Energy     rises over time. 100 means bouncing off the walls.
##
## "Badness" below is how far a need has travelled towards its own bad end,
## always 0 (just cared for) to 100 (critical). It lets one piece of code
## handle all three without special cases.

enum Level {
	FINE,
	WARNING,
	CRITICAL,
}

const HUNGER := &"hunger"
const HAPPINESS := &"happiness"
const ENERGY := &"energy"
const KEYS: Array[StringName] = [HUNGER, HAPPINESS, ENERGY]

## How far towards critical a need gets before we start warning: 70%.
const WARNING_BADNESS := 70.0

## Floating point slack, used at both thresholds.
##
## Draining for exactly 70% of an interval lands on 69.99999, not 70, and a
## full interval lands on 99.99999, not 100. Without this slack a need could
## sit one ten-millionth below a threshold, showing "70" in the UI while
## still reading as Fine, and its warning would never fire.
const EPSILON := 0.001

var values: Dictionary[StringName, float] = {
	HUNGER: 0.0,
	HAPPINESS: 100.0,
	ENERGY: 0.0,
}


# --- Which way does each need point ---------------------------------------

## True for the needs that climb over time (Hunger and Energy).
static func is_rising(key: StringName) -> bool:
	return key != HAPPINESS


## The value a need has right after it is cared for.
static func cared_value(key: StringName) -> float:
	return 100.0 if key == HAPPINESS else 0.0


## The value a need has when it is critical.
static func critical_value(key: StringName) -> float:
	return 0.0 if key == HAPPINESS else 100.0


## A friendly name for the UI.
static func display_name(key: StringName) -> String:
	match key:
		HUNGER:
			return "Hunger"
		HAPPINESS:
			return "Happiness"
		ENERGY:
			return "Energy"
	return String(key)


## Said plainly, so nobody has to guess what a full bar means.
static func full_bar_means(key: StringName) -> String:
	match key:
		HUNGER:
			return "full bar = starving"
		HAPPINESS:
			return "full bar = happy"
		ENERGY:
			return "full bar = restless"
	return ""


# --- Reading the state ----------------------------------------------------

func get_value(key: StringName) -> float:
	return values.get(key, 0.0)


func set_value(key: StringName, value: float) -> void:
	values[key] = clampf(value, 0.0, 100.0)


## How far this need has travelled towards its bad end: 0 is cared for,
## 100 is critical, whichever direction the need happens to run.
func badness(key: StringName) -> float:
	var value: float = get_value(key)
	return 100.0 - value if key == HAPPINESS else value


func level_of(key: StringName) -> Level:
	var bad: float = badness(key)
	if bad >= 100.0 - EPSILON:
		return Level.CRITICAL
	if bad >= WARNING_BADNESS - EPSILON:
		return Level.WARNING
	return Level.FINE


## A snapshot of all three levels, for spotting crossings later.
func levels() -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for key in KEYS:
		out[key] = int(level_of(key))
	return out


static func level_label(level: int) -> String:
	match level:
		int(Level.WARNING):
			return "Getting low"
		int(Level.CRITICAL):
			return "Needs care now"
	return "Fine"


## The need in the worst shape right now, for one-line summaries.
func worst_key() -> StringName:
	var worst: StringName = KEYS[0]
	for key in KEYS:
		if badness(key) > badness(worst):
			worst = key
	return worst


# --- Time passing ---------------------------------------------------------

## Age the dog by seconds, using the given interval table.
##
## The intervals table maps each need key to the number of seconds it takes
## to go from fully cared for to critical, so the drain is 100 / interval per
## second. Values clamp at the bad end: the dog never dies or runs away, it
## just stays sad until someone helps.
func drain(seconds: float, intervals: Dictionary) -> void:
	if seconds <= 0.0:
		return
	for key in KEYS:
		var interval: float = float(intervals.get(key, 0.0))
		if interval <= 0.0:
			continue  # A zero or missing interval means "do not drain this".
		var step: float = 100.0 / interval * seconds
		var value: float = get_value(key)
		value += step if is_rising(key) else -step
		set_value(key, value)


## Apply the time the app was closed.
##
## The caller is responsible for passing the real interval table here, never
## the Demo one. See Needs.gd for why that matters.
func catch_up(elapsed_seconds: float, real_intervals: Dictionary) -> void:
	drain(maxf(elapsed_seconds, 0.0), real_intervals)


## Seconds between two unix timestamps, never negative.
##
## A clock that moved backwards (daylight saving, a corrected system time, a
## dead CMOS battery) would otherwise hand us a negative elapsed time and
## heal the dog for free.
static func elapsed_between(then_unix: float, now_unix: float) -> float:
	return maxf(now_unix - then_unix, 0.0)


## How long until this need hits critical, in seconds.
func seconds_to_critical(key: StringName, intervals: Dictionary) -> float:
	var interval: float = float(intervals.get(key, 0.0))
	if interval <= 0.0:
		return 0.0
	var remaining: float = 100.0 - badness(key)
	if remaining <= EPSILON:
		return 0.0
	return remaining / (100.0 / interval)


## Reads as "~1h 20m", or "now" once the need is already critical.
static func format_countdown(seconds: float) -> String:
	if seconds <= 0.0:
		return "now"
	if seconds < 60.0:
		return "~%ds" % int(ceil(seconds))
	var total_minutes: int = int(ceil(seconds / 60.0))
	if total_minutes < 60:
		return "~%dm" % total_minutes
	var hours: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	if minutes == 0:
		return "~%dh" % hours
	return "~%dh %dm" % [hours, minutes]


## Reads as "3h 12m", for the heading on the "While you were away" card.
static func format_duration(seconds: float) -> String:
	var total_minutes: int = int(floor(maxf(seconds, 0.0) / 60.0))
	if total_minutes < 1:
		return "less than a minute"
	var days: int = total_minutes / 1440
	var hours: int = (total_minutes % 1440) / 60
	var minutes: int = total_minutes % 60
	var parts: PackedStringArray = []
	if days > 0:
		parts.append("%dd" % days)
	if hours > 0:
		parts.append("%dh" % hours)
	if minutes > 0 and days == 0:
		parts.append("%dm" % minutes)
	return " ".join(parts)


# --- Actions --------------------------------------------------------------

## Run one of the care actions: "feed", "play" or "walk".
##
## The effects table is action_effects from settings.json, so the numbers can
## be tuned without touching code. Each action names the needs it sets
## outright (hunger_set) and the ones it merely nudges (happiness_delta).
## Every set happens before every delta, so the result does not depend on
## what order the JSON file happened to list them in.
func apply_action(action: StringName, effects: Dictionary) -> void:
	var spec: Dictionary = effects.get(String(action), {})
	if spec.is_empty():
		return
	for key in KEYS:
		var set_field: String = String(key) + "_set"
		if spec.has(set_field):
			set_value(key, float(spec[set_field]))
	for key in KEYS:
		var delta_field: String = String(key) + "_delta"
		if spec.has(delta_field):
			set_value(key, get_value(key) + float(spec[delta_field]))


# --- Whole-state helpers --------------------------------------------------

func reset_to_cared() -> void:
	for key in KEYS:
		values[key] = cared_value(key)


## A plain Dictionary with String keys, ready for JSON.
func to_dictionary() -> Dictionary:
	var out: Dictionary = {}
	for key in KEYS:
		out[String(key)] = get_value(key)
	return out


## Read values back out of a parsed save file. Anything missing or
## nonsensical keeps its current value rather than breaking the dog.
func from_dictionary(source: Dictionary) -> void:
	for key in KEYS:
		var field: String = String(key)
		if not source.has(field):
			continue
		var raw: Variant = source[field]
		if raw is float or raw is int:
			set_value(key, float(raw))


## One line for the log, for example "hunger 62, happiness 40, energy 75".
func describe() -> String:
	var parts: PackedStringArray = []
	for key in KEYS:
		parts.append("%s %d" % [String(key), roundi(get_value(key))])
	return ", ".join(parts)


## The dog's reaction to how things stand, such as "Biscuit is starving!".
## It lives here so the away card, the in-app banners and the tray
## notifications all say the same thing.
func reaction_line(pet_name: String) -> String:
	var key: StringName = worst_key()
	match level_of(key):
		Level.CRITICAL:
			match key:
				HUNGER:
					return "%s is starving!" % pet_name
				HAPPINESS:
					return "%s is miserable." % pet_name
				ENERGY:
					return "%s is bouncing off the walls!" % pet_name
		Level.WARNING:
			match key:
				HUNGER:
					return "%s is getting hungry." % pet_name
				HAPPINESS:
					return "%s could use some attention." % pet_name
				ENERGY:
					return "%s has energy to burn." % pet_name
	return "%s is doing just fine." % pet_name
