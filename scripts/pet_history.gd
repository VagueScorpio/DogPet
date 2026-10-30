class_name PetHistory
extends RefCounted
## The record of every dog that has lived and died.
##
## Written to saves/history.json, apart from pet.json, because it outlives
## every pet in it. Starting a new dog wipes the save; it must not wipe the
## record of the one before.
##
## Every function here is static and touches nothing but the filesystem, so
## the tests can drive it directly - the same shape as SaveFile, and for
## the same reason.

const FORMAT_VERSION := 1

## Enough to remember without the file growing forever. The oldest records
## fall off the end once this is passed.
const MAX_RECORDS := 200


## Add a dog to the record. Returns false only if nothing could be written.
static func remember(path: String, record: Dictionary) -> bool:
	var records: Array[Dictionary] = load_records(path)
	records.append(record)
	# Newest first everywhere, so trimming takes the oldest off the end.
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("died_unix", 0.0)) > float(b.get("died_unix", 0.0))
	)
	if records.size() > MAX_RECORDS:
		records.resize(MAX_RECORDS)
	return save_records(path, records)


## Every dog remembered, newest death first.
static func load_records(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return out
	var raw: Variant = (parsed as Dictionary).get("pets", [])
	if not raw is Array:
		return out
	for entry in (raw as Array):
		if entry is Dictionary and (entry as Dictionary).has("name"):
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("died_unix", 0.0)) > float(b.get("died_unix", 0.0))
	)
	return out


static func save_records(path: String, records: Array[Dictionary]) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"format_version": FORMAT_VERSION,
		"pets": records,
	}, "\t"))
	file.close()
	return true


## Build the record for a dog that has just died.
static func make_record(
	name: String, born_unix: float, died_unix: float, age_days: float, cause: int
) -> Dictionary:
	return {
		"name": name,
		"born_unix": born_unix,
		"died_unix": died_unix,
		"age_days": age_days,
		"cause": cause,
	}


# --- Reading it back -------------------------------------------------------

## "29 Oct 2026, 14:32". Local time, since it is the owner's own history.
static func format_date(unix: float) -> String:
	if unix <= 0.0:
		return "unknown"
	var when: Dictionary = Time.get_datetime_dict_from_unix_time(int(unix))
	var months: PackedStringArray = [
		"Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
	]
	var month: int = clampi(int(when["month"]), 1, 12)
	return "%d %s %d, %02d:%02d" % [
		int(when["day"]), months[month - 1], int(when["year"]),
		int(when["hour"]), int(when["minute"]),
	]


## How long the dog actually existed, in real time, as opposed to the
## dog-days of its age. Useful because the two can differ a lot: a dog on
## Demo speed ages a year in an afternoon.
static func format_lifespan(born_unix: float, died_unix: float) -> String:
	if born_unix <= 0.0 or died_unix <= born_unix:
		return "unknown"
	return NeedsText.format_duration(died_unix - born_unix)


## A one-line summary of the whole record.
static func describe(record: Dictionary) -> String:
	return "%s, %s, died of %s" % [
		str(record.get("name", "?")),
		LifeModel.format_age(float(record.get("age_days", 0.0))),
		LifeModel.cause_name(int(record.get("cause", 0))),
	]
