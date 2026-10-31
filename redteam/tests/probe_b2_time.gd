extends SceneTree

func try_one(label: String, v: float) -> void:
	var t0: int = Time.get_ticks_msec()
	print("trying ", label, " ...")
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(int(v))
	print(label, " -> year ", d.get("year", "?"), " took ms ", Time.get_ticks_msec() - t0)

func _init() -> void:
	try_one("1e17", 1e17)
	try_one("9e18", 9e18)
	try_one("-9e18", -9e18)
	try_one("1e30 (overflows int64)", 1e30)
	print("all done")
	quit(0)
