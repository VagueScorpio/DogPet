extends SceneTree
## RT probe B: PetHistory.format_date on an out-of-range unix timestamp.
## history.json and pet.json are plain text the owner can edit or corrupt,
## and born_unix / died_unix are read back unclamped.

func _init() -> void:
	print("start")
	var t0: int = Time.get_ticks_msec()
	print("sane: ", Time.get_datetime_dict_from_unix_time(1762000000))
	print("sane took ms ", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	print("about to try 1e15 ...")
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(int(1e15))
	print("1e15 -> ", d, " took ms ", Time.get_ticks_msec() - t0)
	quit(0)
