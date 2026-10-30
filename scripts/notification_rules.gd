class_name NotificationRules
extends RefCounted
## What to say about a need, and whether to say anything at all.
##
## Kept apart from Notifier, which owns the clock, the window and the
## PowerShell call, so the rules themselves can be tested: being told once
## per crossing rather than once per frame is the sort of thing that is easy
## to get wrong and hard to notice until the app has nagged someone fifty
## times in a row.

## Worth speaking up about a move from one level to another?
##
## Only when things got worse. Going from Getting low back to Fine is good
## news and needs no notification - the owner just did something about it.
static func is_worth_announcing(from_level: int, to_level: int) -> bool:
	if to_level <= int(NeedsModel.Level.FINE):
		return false
	return to_level > from_level


## The headline, which is the whole message on a narrow toast.
static func title_for(key: StringName, level: int, pet_name: String) -> String:
	var critical: bool = level >= int(NeedsModel.Level.CRITICAL)
	match key:
		NeedsModel.HUNGER:
			return "%s is starving!" % pet_name if critical else "%s is getting hungry." % pet_name
		NeedsModel.HAPPINESS:
			if critical:
				return "%s is miserable." % pet_name
			return "%s could use some attention." % pet_name
		NeedsModel.ENERGY:
			if critical:
				return "%s is bouncing off the walls!" % pet_name
			return "%s has energy to burn." % pet_name
	return "%s needs you." % pet_name


## The second line: what to actually do about it.
static func body_for(key: StringName, level: int) -> String:
	var critical: bool = level >= int(NeedsModel.Level.CRITICAL)
	match key:
		NeedsModel.HUNGER:
			return "Time to feed." if critical else "A meal would go down well."
		NeedsModel.HAPPINESS:
			return "Time to play." if critical else "A game would cheer them up."
		NeedsModel.ENERGY:
			return "Time for a walk." if critical else "A walk would burn it off."
	return ""


## The tray tooltip: "Hunger 62% - Happiness 40% - Energy 75%".
static func tooltip_for(values: Dictionary, pet_name: String) -> String:
	var parts: PackedStringArray = []
	for key in NeedsModel.KEYS:
		parts.append("%s %d%%" % [NeedsText.display_name(key), roundi(float(values.get(key, 0.0)))])
	return "%s\n%s" % [pet_name, "  -  ".join(parts)]


## Should the tray show its alert icon? Yes as soon as anything is at
## Getting low or worse.
static func wants_alert_icon(levels: Dictionary) -> bool:
	for key in NeedsModel.KEYS:
		if int(levels.get(key, 0)) >= int(NeedsModel.Level.WARNING):
			return true
	return false
