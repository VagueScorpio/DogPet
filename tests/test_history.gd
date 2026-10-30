extends SceneTree
## Headless tests for the record of past pets.
##
## Run them from the project root with:
##
##   godot --headless --path . --script res://tests/test_history.gd
##
## The record outlives every pet in it, so the things worth checking are
## that it survives being written to repeatedly, that it never loses an
## older dog to a newer one, and that a damaged file costs the record
## rather than the app.

const History := preload("res://scripts/pet_history.gd")
const Life := preload("res://scripts/life_model.gd")

const DAY := 86400.0

var _passed: int = 0
var _failed: int = 0
var _path: String = ""


func _initialize() -> void:
	print("")
	print("DogPet history tests")
	print("====================")

	var folder: String = ProjectSettings.globalize_path("user://test_history")
	DirAccess.make_dir_recursive_absolute(folder)
	_path = folder.path_join("history.json")
	_clean()

	_test_empty()
	_test_remembering()
	_test_order_and_trimming()
	_test_broken_file()
	_test_formatting()

	_clean()
	DirAccess.remove_absolute(folder)

	print("")
	print("====================")
	print("%d passed, %d failed" % [_passed, _failed])
	print("TESTS FAILED" if _failed > 0 else "All good.")
	quit(1 if _failed > 0 else 0)


func _record(name: String, born: float, died: float, age: float, cause: int) -> Dictionary:
	return History.make_record(name, born, died, age, cause)


# --- Nothing yet -----------------------------------------------------------

func _test_empty() -> void:
	_begin("A record that does not exist yet")
	var records: Array[Dictionary] = History.load_records(_path)
	_ok("reads as empty", records.is_empty())
	_ok("rather than failing", records != null)


# --- Keeping dogs ----------------------------------------------------------

func _test_remembering() -> void:
	_begin("A dog is remembered")
	_ok("it writes", History.remember(
		_path, _record("Biscuit", 1000.0, 1000.0 + 6.0 * DAY, 6.2, Life.Cause.STARVATION)
	))
	var records: Array[Dictionary] = History.load_records(_path)
	_ok("and comes back", records.size() == 1)
	_ok("with its name", str(records[0]["name"]) == "Biscuit")
	_close("its birthday", float(records[0]["born_unix"]), 1000.0)
	_close("its age", float(records[0]["age_days"]), 6.2)
	_ok("and what took it", int(records[0]["cause"]) == Life.Cause.STARVATION)

	_begin("A second dog does not displace the first")
	History.remember(_path, _record("Rex", 2000.0, 2000.0 + DAY, 1.0, Life.Cause.SICKNESS))
	records = History.load_records(_path)
	_ok("both are kept", records.size() == 2)
	var names: PackedStringArray = []
	for r in records:
		names.append(str(r["name"]))
	_ok("Biscuit is still there", names.has("Biscuit"))
	_ok("and so is Rex", names.has("Rex"))

	_begin("Two dogs with the same name are two dogs")
	History.remember(_path, _record("Biscuit", 9000.0, 9500.0, 2.0, Life.Cause.SICKNESS))
	records = History.load_records(_path)
	_ok("all three are kept", records.size() == 3)


# --- Order and size --------------------------------------------------------

func _test_order_and_trimming() -> void:
	_clean()
	_begin("The newest death comes first")
	History.remember(_path, _record("Oldest", 0.0, 100.0, 1.0, Life.Cause.STARVATION))
	History.remember(_path, _record("Newest", 0.0, 900.0, 1.0, Life.Cause.STARVATION))
	History.remember(_path, _record("Middle", 0.0, 500.0, 1.0, Life.Cause.STARVATION))
	var records: Array[Dictionary] = History.load_records(_path)
	_ok("newest", str(records[0]["name"]) == "Newest")
	_ok("then the middle one", str(records[1]["name"]) == "Middle")
	_ok("then the oldest", str(records[2]["name"]) == "Oldest")

	_begin("The file does not grow forever")
	_clean()
	for index in History.MAX_RECORDS + 20:
		History.remember(_path, _record("Dog%d" % index, 0.0, float(index), 1.0, 1))
	records = History.load_records(_path)
	_ok("it stops at the limit", records.size() == History.MAX_RECORDS)
	_ok("keeping the newest", str(records[0]["name"]) == "Dog%d" % (History.MAX_RECORDS + 19))
	# The oldest fall off the end, which is the right way round.
	var kept: PackedStringArray = []
	for r in records:
		kept.append(str(r["name"]))
	_ok("and dropping the oldest", not kept.has("Dog0"))


# --- When the file is no good ----------------------------------------------

func _test_broken_file() -> void:
	_begin("A damaged record costs the record, not the app")
	_clean()
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{ not json at all")
	file.close()
	var records: Array[Dictionary] = History.load_records(_path)
	_ok("it reads as empty", records.is_empty())
	_ok("and can be written again", History.remember(_path, _record("After", 1.0, 2.0, 1.0, 1)))
	_ok("which works", History.load_records(_path).size() == 1)

	_begin("Entries that are not dogs are skipped")
	_clean()
	file = FileAccess.open(_path, FileAccess.WRITE)
	file.store_string('{"pets": [{"name": "Real"}, 7, "nonsense", {"no_name": true}]}')
	file.close()
	records = History.load_records(_path)
	_ok("only the real one survives", records.size() == 1)
	_ok("and it is the right one", str(records[0]["name"]) == "Real")

	_begin("A file with no pets list at all")
	_clean()
	file = FileAccess.open(_path, FileAccess.WRITE)
	file.store_string('{"format_version": 1}')
	file.close()
	_ok("reads as empty", History.load_records(_path).is_empty())


# --- Reading it back -------------------------------------------------------

func _test_formatting() -> void:
	_begin("Dates read plainly")
	# 1 Jan 2020, 00:00 UTC. The formatter works in local time, so check
	# the shape rather than the exact hour.
	var text: String = History.format_date(1577836800.0)
	_ok("it names a year", text.contains("2019") or text.contains("2020"))
	_ok("and a month", text.contains("Jan") or text.contains("Dec"))
	_ok("and has a time on it", text.contains(":"))
	_ok("nothing is 'unknown'", not text.contains("unknown"))

	_begin("A missing date says so")
	_ok("zero", History.format_date(0.0) == "unknown")
	_ok("negative", History.format_date(-5.0) == "unknown")

	_begin("Real time is reported as well as dog-days")
	# Dog-days and real time differ a lot: on Demo a dog ages a year in an
	# afternoon, so the scoreboard shows both.
	# A birthday of zero means "not recorded", so these need a real one.
	_ok("a day", History.format_lifespan(1000.0, 1000.0 + DAY) == "1d")
	_ok("three hours", History.format_lifespan(1000.0, 1000.0 + 3.0 * 3600.0) == "3h")
	_ok("a nonsense span", History.format_lifespan(500.0, 100.0) == "unknown")
	_ok("no birthday", History.format_lifespan(0.0, 100.0) == "unknown")

	_begin("A record describes itself")
	var line: String = History.describe(
		_record("Biscuit", 0.0, DAY, 4.0, Life.Cause.STARVATION)
	)
	_ok("it names the dog", line.contains("Biscuit"))
	_ok("its age", line.contains("4 days old"))
	_ok("and what took it", line.contains("starvation"))


# --- Small helpers ---------------------------------------------------------

func _clean() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


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
