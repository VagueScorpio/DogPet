class_name CutPreview
extends RefCounted
## What the import wizard shows: the strips that are about to be written,
## rather than the files they were cut from. *(v1.47)*
##
## The two are not the same picture, and the difference is exactly where
## importing goes wrong. What lands in a pack has had its page keyed off,
## every frame trimmed to the drawing on it and stood on one baseline. A dog
## drawn in the colour of its own page comes out hollow; frames drawn all
## over their cells come out walking off the edge of the window. Both of
## those are plain in the strip and invisible in the source file, which is
## why the wizard used to show a sheet that looked perfect and install a pack
## that was not.
##
## Rendered by SheetCutter, the same code the installer runs - a preview
## drawn by anything else is a drawing of a guess.
##
## Pure: cuts in, Images out, no nodes. ImportPreview puts them on screen.

## How many strips are worth rendering for one look. The form asks about up
## to 24 pieces; rendering every one of them each time a letter is typed into
## the name box is not a preview.
const MOST_SHOWN := 3

## Past this many frames only the first few are rendered, and the label says
## so. A numbered run can be hundreds of files, and reading all of them to
## draw a row of thumbnails would stop the window the way SheetPlan's ceiling
## was written to stop it.
const MOST_FRAMES := 48
const SHOWN_FRAMES := 8

## Rendered strips, by what they were cut from. Typing in the name box emits
## the same "something changed" as moving a frame count does, so without this
## the sheets would be re-cut on every keystroke.
var _done: Dictionary = {}

## Kept small: the cache is a convenience, not a store, and each entry holds
## a whole image.
const MOST_KEPT := 12


## The strips for a wizard's sheets list (what ImportForm.answers calls
## "sheets"), as an array of {label, image, partial}.
func of_sheets(sheets: Array) -> Array:
	var shown: Array = []
	for entry in sheets:
		if shown.size() >= MOST_SHOWN:
			break
		var sheet: Dictionary = entry
		var cut: Dictionary = sheet.get("cut", {})
		var whole: int = SheetCutter.frames_in(cut)
		if whole < 1:
			continue
		var partial: bool = whole > MOST_FRAMES
		var image: Image = _strip(_first_few(cut) if partial else cut)
		if image == null:
			continue
		shown.append({
			"label": label_for(sheet, whole, partial),
			"image": image,
			"partial": partial,
		})
	return shown


## What a strip is called on screen: the job it has been given, how many
## frames it holds, and a word when only some of them were drawn.
static func label_for(sheet: Dictionary, whole: int, partial: bool) -> String:
	var state: String = str(sheet.get("state", "")).capitalize()
	var stage: String = str(sheet.get("stage", ""))
	if not stage.is_empty():
		state += " (%s)" % stage
	if partial:
		return "%s - the first %d of %d frames" % [state, SHOWN_FRAMES, whole]
	return "%s - %d frame%s" % [state, whole, "" if whole == 1 else "s"]


## What a cut is, as one string, so a cut that has not changed is not read
## off the disk and keyed again.
static func signature(cut: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append_array(PackedStringArray(cut.get("paths", PackedStringArray())))
	for rect in Array(cut.get("rects", [])):
		parts.append(str(rect))
	parts.append("keyed" if bool(cut.get("key", false)) else "as-is")
	return "|".join(parts)


func _strip(cut: Dictionary) -> Image:
	var mark: String = signature(cut)
	if _done.has(mark):
		return _done[mark]
	var image: Image = SheetCutter.render(cut)
	if image == null:
		return null
	if _done.size() >= MOST_KEPT:
		_done.clear()
	_done[mark] = image
	return image


# The front of a cut, for a run too long to read all of. Enough frames to
# show whether they stand in one place, which is the whole question.
static func _first_few(cut: Dictionary) -> Dictionary:
	var paths: PackedStringArray = cut.get("paths", PackedStringArray())
	var rects: Array = cut.get("rects", [])
	var few: PackedStringArray = []
	var boxes: Array[Rect2i] = []
	for index in mini(SHOWN_FRAMES, mini(paths.size(), rects.size())):
		few.append(paths[index])
		boxes.append(rects[index])
	return {"paths": few, "rects": boxes, "key": bool(cut.get("key", false))}
