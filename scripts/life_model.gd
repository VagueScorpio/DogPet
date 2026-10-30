class_name LifeModel
extends RefCounted
## Ageing, illness and death, with no nodes and no clock of its own.
##
## The same split as NeedsModel, and for the same reason: time arrives as an
## argument, so the live game, the offline catch-up and the headless tests
## all run the identical code. Death is not something to discover you got
## subtly wrong after somebody's pet has already gone.
##
## None of this applies in Casual play. There the dog ages and nothing else
## happens to it, ever.
##
## Everything is measured in hunger intervals rather than in minutes, so the
## whole of it scales with the care setting: on Demo an illness runs its
## course in a minute, on Long it takes most of a day.

enum Cause {
	NONE,
	STARVATION,
	SICKNESS,
}

## Life stages, in dog-days. Nothing kills the dog at the end of them - the
## owner asked for ageing, not a lifespan.
const PUPPY_DAYS := 3.0
const YOUNG_DAYS := 10.0
const ADULT_DAYS := 40.0

## A newly ill dog starts here rather than at nothing, so the bar is
## visible the moment it appears.
const ILLNESS_START := 4.0

var born_unix: float = 0.0
var age_days: float = 0.0

## 0-100. 100 is fatal, and only in Real play.
var sickness: float = 0.0
var ill: bool = false

## How long hunger has sat at critical. The dog dies when this passes the
## grace period, which is what gives "starving" its meaning.
var starving_seconds: float = 0.0

var alive: bool = true
var died_unix: float = 0.0
var cause: int = Cause.NONE


# --- Reading ---------------------------------------------------------------

## "Puppy", "Young", "Adult" or "Senior".
static func stage_for(days: float) -> String:
	if days < PUPPY_DAYS:
		return "Puppy"
	if days < YOUNG_DAYS:
		return "Young"
	if days < ADULT_DAYS:
		return "Adult"
	return "Senior"


func stage() -> String:
	return stage_for(age_days)


## "4 days old", or hours while it is still very young.
static func format_age(days: float) -> String:
	if days < 1.0:
		var hours: int = int(floor(days * 24.0))
		if hours < 1:
			return "newborn"
		return "%d hour%s old" % [hours, "" if hours == 1 else "s"]
	var whole: int = int(floor(days))
	return "%d day%s old" % [whole, "" if whole == 1 else "s"]


## How long an untreated illness has left, in seconds. Zero when well.
func seconds_to_fatal(hunger_interval: float, config: Dictionary) -> float:
	if not ill or sickness >= 100.0:
		return 0.0
	var to_fatal: float = hunger_interval * _number(config, "sickness_rise_intervals", 1.5)
	if to_fatal <= 0.0:
		return 0.0
	return (100.0 - sickness) / (100.0 / to_fatal)


## The sickness bar's level, using the same three steps as the needs so the
## wording and colours on screen match.
func sickness_level() -> int:
	if sickness >= 100.0 - 0.001:
		return int(NeedsModel.Level.CRITICAL)
	if sickness >= NeedsModel.WARNING_BADNESS:
		return int(NeedsModel.Level.WARNING)
	return int(NeedsModel.Level.FINE)


## How close the dog is to starving to death, 0 to 1. The sickness bar has
## its own value; this is what makes a starving dog visibly urgent.
func starving_fraction(grace_seconds: float) -> float:
	if grace_seconds <= 0.0:
		return 0.0
	return clampf(starving_seconds / grace_seconds, 0.0, 1.0)


# --- Time passing ----------------------------------------------------------

## Age the dog, and in Real play work out whether it fell ill or died.
##
## `roll` is a number from 0 to 1 used for the one illness check this call
## makes. The caller supplies it so that this stays a pure function and the
## tests can decide what happens.
##
## Returns what changed: "fell_ill", "died" and "cause".
func advance(
	seconds: float,
	hunger_is_critical: bool,
	real_play: bool,
	hunger_interval: float,
	config: Dictionary,
	roll: float,
	now_unix: float
) -> Dictionary:
	var news: Dictionary = {"fell_ill": false, "died": false, "cause": Cause.NONE}
	if not alive or seconds <= 0.0 or hunger_interval <= 0.0:
		return news

	age_days += seconds / (hunger_interval * _number(config, "age_day_intervals", 2.0))

	if not real_play:
		# Casual play. Nothing here can happen, and anything left over from
		# a spell of Real play is cleared rather than lying in wait.
		sickness = 0.0
		ill = false
		starving_seconds = 0.0
		return news

	# Starving. The clock only runs while hunger is actually at the bad end,
	# and resets the moment the dog is fed.
	if hunger_is_critical:
		starving_seconds += seconds
	else:
		starving_seconds = 0.0
	var grace: float = hunger_interval * _number(config, "starve_grace_intervals", 1.0)
	if starving_seconds >= grace:
		_die(Cause.STARVATION, now_unix)
		news["died"] = true
		news["cause"] = Cause.STARVATION
		return news

	if ill:
		var to_fatal: float = hunger_interval * _number(config, "sickness_rise_intervals", 1.5)
		if to_fatal > 0.0:
			sickness = minf(100.0, sickness + seconds * (100.0 / to_fatal))
		if sickness >= 100.0:
			_die(Cause.SICKNESS, now_unix)
			news["died"] = true
			news["cause"] = Cause.SICKNESS
		return news

	# Falling ill. Expressed as an average wait rather than a per-tick
	# chance, so one long catch-up is as likely to produce an illness as the
	# same time spent watching - and no more likely.
	var mean: float = hunger_interval * _number(config, "illness_mean_intervals", 8.0)
	if mean > 0.0 and roll < 1.0 - exp(-seconds / mean):
		ill = true
		sickness = maxf(sickness, ILLNESS_START)
		news["fell_ill"] = true
	return news


## A trip to the vet. Returns true if that was enough to finish the job.
##
## One visit may not be: the bar comes down by a fixed amount, so a dog left
## until it is nearly gone needs taking back.
func treat(amount: float) -> bool:
	if not ill:
		return true
	sickness = maxf(0.0, sickness - amount)
	if sickness <= 0.0:
		ill = false
		return true
	return false


func _die(reason: int, now_unix: float) -> void:
	alive = false
	cause = reason
	died_unix = now_unix


static func cause_name(reason: int) -> String:
	match reason:
		Cause.STARVATION:
			return "starvation"
		Cause.SICKNESS:
			return "illness"
	return "unknown"


## What to tell the owner. Plain, and never cute about it.
static func death_line(pet_name: String, reason: int) -> String:
	match reason:
		Cause.STARVATION:
			return "%s starved." % pet_name
		Cause.SICKNESS:
			return "%s did not recover." % pet_name
	return "%s has died." % pet_name


# --- Starting again --------------------------------------------------------

## Begin a new dog. The old one is gone; nothing carries over.
func reset(now_unix: float) -> void:
	born_unix = now_unix
	age_days = 0.0
	sickness = 0.0
	ill = false
	starving_seconds = 0.0
	alive = true
	died_unix = 0.0
	cause = Cause.NONE


# --- Saving ----------------------------------------------------------------

func to_dictionary() -> Dictionary:
	return {
		"born_unix": born_unix,
		"age_days": age_days,
		"sickness": sickness,
		"ill": ill,
		"starving_seconds": starving_seconds,
		"alive": alive,
		"died_unix": died_unix,
		"cause": cause,
	}


func from_dictionary(source: Dictionary) -> void:
	born_unix = _number(source, "born_unix", 0.0)
	age_days = maxf(0.0, _number(source, "age_days", 0.0))
	sickness = clampf(_number(source, "sickness", 0.0), 0.0, 100.0)
	ill = bool(source.get("ill", false))
	starving_seconds = maxf(0.0, _number(source, "starving_seconds", 0.0))
	alive = bool(source.get("alive", true))
	died_unix = _number(source, "died_unix", 0.0)
	cause = int(source.get("cause", Cause.NONE))


static func _number(source: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = source.get(key, fallback)
	if raw is float or raw is int:
		return float(raw)
	return fallback
