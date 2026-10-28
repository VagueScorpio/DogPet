class_name CareSettings
extends RefCounted
## The settings data: the shipped defaults, and the pure lookups over them.
##
## No nodes, no autoloads, no file reading. Settings.gd is the autoload that
## owns the file on disk and the signals; this is just the numbers and the
## rules for choosing between them. Splitting it this way is what lets the
## headless tests check the real shipped numbers, and in particular the one
## rule that would be easy to get quietly wrong: the offline catch-up must
## never use Demo Speed.
##
## The tuning numbers live in saves/settings.json rather than in code, so
## they can be changed without a rebuild. These are what gets written when
## the file is missing, and what fills in any key an older file is short of.

# Reached by preload rather than by its class_name, so this script compiles
# with no editor-generated class cache - which is how the tests run it.
const NeedKeys := preload("res://scripts/needs_model.gd")

const FORMAT_VERSION := 1

const FREQUENT := "frequent"
const MODERATE := "moderate"
const LONG := "long"
const DEMO := "demo"

## The three the owner picks from. Demo is a toggle, not a fourth choice.
const CARE_INTERVALS: PackedStringArray = [FREQUENT, MODERATE, LONG]

const DEFAULTS := {
	"format_version": FORMAT_VERSION,
	"care_interval": MODERATE,
	"demo_speed": false,
	# Seconds from fully cared for to critical. Staggered on purpose, so all
	# three needs do not hit critical at the same moment.
	"intervals_seconds": {
		# 40 min / 45 min / 50 min
		FREQUENT: {"hunger": 2400.0, "happiness": 2700.0, "energy": 3000.0},
		# 3 h / 3.5 h / 4 h
		MODERATE: {"hunger": 10800.0, "happiness": 12600.0, "energy": 14400.0},
		# 10 h / 11 h / 12 h
		LONG: {"hunger": 36000.0, "happiness": 39600.0, "energy": 43200.0},
		# 45 s / 50 s / 55 s
		DEMO: {"hunger": 45.0, "happiness": 50.0, "energy": 55.0},
	},
	# What each action does to the needs. A "_set" lands on an exact value;
	# a "_delta" nudges by that much. Every set happens before every delta.
	"action_effects": {
		"feed": {"hunger_set": 0.0, "happiness_delta": 5.0},
		"play": {"happiness_set": 100.0, "energy_delta": -15.0, "hunger_delta": 5.0},
		"walk": {"energy_set": 0.0, "happiness_delta": 10.0, "hunger_delta": 10.0},
	},
	# How long each action's animation runs. Unchanged in Demo mode.
	"action_seconds": {"feed": 5.0, "play": 8.0, "walk": 10.0},
	# How often to speak up again while a need is already critical.
	"critical_reminder_minutes": {
		FREQUENT: 30.0,
		MODERATE: 60.0,
		LONG: 120.0,
		DEMO: 1.0,
	},
	"close_button": "tray",  # "tray" or "quit"
	"start_minimized": false,
	"notifications_enabled": true,
}


## Which interval row the bars drain at right now.
static func live_interval_name(from: Dictionary) -> String:
	if bool(from.get("demo_speed", false)):
		return DEMO
	return care_interval_name(from)


## Which interval row the offline catch-up uses.
##
## Always the real care setting, even when the app was closed with Demo
## Speed left on. Otherwise a 45-second demo row would be applied to hours
## of real absence, and every bar would be maxed the moment the app reopened.
static func catch_up_interval_name(from: Dictionary) -> String:
	return care_interval_name(from)


## The chosen care setting, or Moderate if the file says something odd.
static func care_interval_name(from: Dictionary) -> String:
	var name: String = str(from.get("care_interval", MODERATE))
	return name if CARE_INTERVALS.has(name) else MODERATE


## One row of the interval table, keyed the way NeedsModel wants it.
static func intervals_from(from: Dictionary, name: String) -> Dictionary:
	var table: Dictionary = from.get("intervals_seconds", {})
	var row: Dictionary = table.get(name, table.get(MODERATE, {}))
	return {
		NeedKeys.HUNGER: float(row.get("hunger", 10800.0)),
		NeedKeys.HAPPINESS: float(row.get("happiness", 12600.0)),
		NeedKeys.ENERGY: float(row.get("energy", 14400.0)),
	}


## Copy loaded values over the defaults, but only where the key is one we
## know and the type matches. An older or hand-edited file then gains any new
## keys instead of breaking, and a typo cannot put a String where a number
## belongs.
static func merge_into(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		if not target.has(key):
			continue
		var want: Variant = target[key]
		var got: Variant = source[key]
		if want is Dictionary and got is Dictionary:
			merge_into(want, got)
		elif want is bool and got is bool:
			target[key] = got
		elif want is float and (got is float or got is int):
			target[key] = float(got)
		elif want is int and got is int:
			target[key] = got
		elif want is String and got is String:
			target[key] = got
