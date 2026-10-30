class_name NeedsText
extends RefCounted
## The words the needs are described in: names, labels, countdowns and the
## dog's one-line reaction.
##
## Split out of NeedsModel, which is the arithmetic. Keeping the two apart
## means the sums can be read without wading through sentences, and that
## every part of the app says the same thing about the same state: the bars,
## the "While you were away" card, the in-app banners and the Windows
## notifications all come through here.
##
## Pure static functions, no state: the caller passes in what it knows.
## The dependency runs one way only - this script reads the needs' keys and
## levels, and NeedsModel does not know this one exists, because two scripts
## that preload each other will not compile.

# Reached by preload rather than by its class_name, so this compiles with no
# editor-generated class cache - which is how the tests run it.
const NeedKeys := preload("res://scripts/needs_model.gd")


## A friendly name for the UI.
static func display_name(key: StringName) -> String:
	match key:
		NeedKeys.HUNGER:
			return "Hunger"
		NeedKeys.HAPPINESS:
			return "Happiness"
		NeedKeys.ENERGY:
			return "Energy"
	return String(key)


## Said plainly, so nobody has to guess what a full bar means. A full Hunger
## bar is bad news; a full Happiness bar is the opposite.
static func full_bar_means(key: StringName) -> String:
	match key:
		NeedKeys.HUNGER:
			return "full bar = starving"
		NeedKeys.HAPPINESS:
			return "full bar = happy"
		NeedKeys.ENERGY:
			return "full bar = restless"
	return ""


## The word beside the bar. Never the only signal: the colour agrees with
## it, and the countdown says how long is left.
static func level_label(level: int) -> String:
	match level:
		int(NeedKeys.Level.WARNING):
			return "Getting low"
		int(NeedKeys.Level.CRITICAL):
			return "Needs care now"
	return "Fine"


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


## The dog's reaction to the need in the worst shape, such as "Biscuit is
## starving!". NeedsModel works out which need that is and how bad it has
## got; this only puts it into words.
static func reaction_line(key: StringName, level: int, pet_name: String) -> String:
	match level:
		int(NeedKeys.Level.CRITICAL):
			match key:
				NeedKeys.HUNGER:
					return "%s is starving!" % pet_name
				NeedKeys.HAPPINESS:
					return "%s is miserable." % pet_name
				NeedKeys.ENERGY:
					return "%s is bouncing off the walls!" % pet_name
		int(NeedKeys.Level.WARNING):
			match key:
				NeedKeys.HUNGER:
					return "%s is getting hungry." % pet_name
				NeedKeys.HAPPINESS:
					return "%s could use some attention." % pet_name
				NeedKeys.ENERGY:
					return "%s has energy to burn." % pet_name
	return "%s is doing just fine." % pet_name
