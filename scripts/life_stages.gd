class_name LifeStages
extends RefCounted
## Naming and choosing between a pack's life-stage art.
##
## LifeModel ages the dog through four stages of its own - Puppy, Young,
## Adult, Senior - and that never changes, because the care intervals are
## built on it. A pack's art is a different matter: a sheet may hold three
## drawings of the dog, or four, or six, and all of them have to be hung on
## the same four-stage arc.
##
## So this does two jobs. It names however many stages a sheet turned out to
## have, and it says which of them a dog of a given age should be drawn as.
##
## Pure arithmetic and strings: no nodes, no files, nothing to log to.

## The most stages worth telling apart. Past this a sheet is a tile set.
const MAX_STAGES := 8

## The ends never change. A progression always starts at the youngest and
## finishes at the oldest, however many steps it takes to get there.
const FIRST := "puppy"
const LAST := "senior"

## The middle names, in the order they are handed out as a sheet gets
## longer. Four stages take one of them, five take two, and so on.
const MIDDLES: PackedStringArray = [
	"adult", "juvenile", "young_adult", "mature_adult", "older_adult", "elder",
]

## For five stages the owner gave two readings, and which one is right
## depends on where the ageing shows. When the greying starts before the
## last drawing, the extra stage sits late in life and is an older adult;
## when it does not, the extra stage sits early and is a young adult.
const FIVE_EARLY: PackedStringArray = [
	"puppy", "juvenile", "young_adult", "adult", "senior",
]
const FIVE_LATE: PackedStringArray = [
	"puppy", "juvenile", "adult", "older_adult", "senior",
]


## The stage names for a sheet of this many drawings, youngest first.
##
## One drawing is just the dog. Two are a puppy and a grown dog - there is
## no sense in calling one of two "senior" when nothing has greyed yet.
## Three and up always run from puppy to senior.
##
## late_bloom only matters at five, where it picks between the owner's two
## readings; everywhere else it is ignored.
static func names_for(count: int, late_bloom: bool = false) -> PackedStringArray:
	if count <= 1:
		return PackedStringArray(["adult"])
	if count == 2:
		return PackedStringArray(["puppy", "adult"])
	if count == 3:
		return PackedStringArray(["puppy", "adult", "senior"])
	if count == 4:
		return PackedStringArray(["puppy", "juvenile", "adult", "senior"])
	if count == 5:
		return FIVE_LATE.duplicate() if late_bloom else FIVE_EARLY.duplicate()

	# Six and up: the two ends, and as many middles as it takes. Ordered
	# youngest to oldest rather than in the order MIDDLES lists them.
	var wanted: int = mini(count, MAX_STAGES) - 2
	var middle: PackedStringArray = PackedStringArray([
		"juvenile", "young_adult", "adult", "mature_adult", "older_adult", "elder",
	])
	var names: PackedStringArray = PackedStringArray([FIRST])
	for index in wanted:
		names.append(middle[index] if index < middle.size() else "stage_%d" % (index + 2))
	names.append(LAST)
	return names


## "young_adult" as something to show a person: "Young Adult".
static func label_for(name: String) -> String:
	var words: PackedStringArray = name.split("_", false)
	var shown: PackedStringArray = []
	for word in words:
		shown.append(word.substr(0, 1).to_upper() + word.substr(1))
	return " ".join(shown)


## Where a dog of this age sits along its whole life, 0.0 to 1.0.
##
## Piecewise rather than linear in days, because LifeModel's own stages are
## not evenly spaced - a puppy lasts three dog-days and an adult thirty. Each
## of the four takes a quarter of the arc, so a pack of four drawings lines
## up with the four stages exactly, and any other number divides the same
## arc into its own even bands.
##
## Senior is open-ended in LifeModel, so it is given the same span as adult
## for the purpose of this scale and then clamped.
static func progress(age_days: float) -> float:
	var days: float = maxf(0.0, age_days)
	if days < LifeModel.PUPPY_DAYS:
		return _band(days, 0.0, LifeModel.PUPPY_DAYS, 0.0)
	if days < LifeModel.YOUNG_DAYS:
		return _band(days, LifeModel.PUPPY_DAYS, LifeModel.YOUNG_DAYS, 0.25)
	if days < LifeModel.ADULT_DAYS:
		return _band(days, LifeModel.YOUNG_DAYS, LifeModel.ADULT_DAYS, 0.5)
	var senior_span: float = LifeModel.ADULT_DAYS - LifeModel.YOUNG_DAYS
	return minf(1.0, _band(days, LifeModel.ADULT_DAYS, LifeModel.ADULT_DAYS + senior_span, 0.75))


## Which of a pack's drawings a dog of this age should be shown as.
##
## Always in range, so a caller may index straight into the art without
## checking: a count of zero or less answers 0 rather than failing.
static func index_for(age_days: float, count: int) -> int:
	if count <= 1:
		return 0
	return clampi(int(progress(age_days) * float(count)), 0, count - 1)


## The same, by LifeModel's own stage name rather than by age. Used where
## the stage is already in hand and the days are not.
static func index_for_stage(stage: String, count: int) -> int:
	var order: PackedStringArray = PackedStringArray(["Puppy", "Young", "Adult", "Senior"])
	var at: int = order.find(stage)
	if at < 0 or count <= 1:
		return 0
	# The middle of that quarter, so a four-drawing pack maps one to one and
	# a three-drawing pack does not land on a boundary by accident.
	return clampi(int((float(at) + 0.5) / 4.0 * float(count)), 0, count - 1)


# One quarter of the arc, filled in proportion to how far through the band
# the dog is.
static func _band(days: float, from: float, to: float, base: float) -> float:
	var span: float = maxf(0.001, to - from)
	return base + clampf((days - from) / span, 0.0, 1.0) * 0.25
