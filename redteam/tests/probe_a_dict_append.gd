extends SceneTree
## RT probe A: does appending to a PackedStringArray held in a Dictionary
## actually mutate the stored value? PackArchive.inspect relies on it for
## the zip-slip refusal.

func _init() -> void:
	var d: Dictionary = {"problems": PackedStringArray()}
	d["problems"].append("boom")
	print("dict PackedStringArray size after append: ", d["problems"].size())

	var d2: Dictionary = {"problems": [] as Array}
	d2["problems"].append("boom")
	print("dict Array size after append: ", d2["problems"].size())
	quit(0)
