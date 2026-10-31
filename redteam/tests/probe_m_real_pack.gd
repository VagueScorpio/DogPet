extends SceneTree
## RT-03 regression check: ordinary packs still import.
##
## A size limit is no good if it refuses real art. This exports the shipped
## pug_pixel and pug_3d packs with the app's own writer and reads them back
## with the app's own reader - the owner's phase 5 test, headlessly.

const Archive := preload("res://scripts/pack_archive.gd")
const Sizes := preload("res://scripts/zip_sizes.gd")
const Pack := preload("res://scripts/pet_pack.gd")

func _init() -> void:
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var work: String = OS.get_user_data_dir().path_join("rt_real_pack")
	DirAccess.make_dir_recursive_absolute(work)

	for id in ["pug_pixel", "pug_3d", "pawsome_3d"]:
		var folder: String = project.path_join("assets/pets/%s" % id)
		if not DirAccess.dir_exists_absolute(folder):
			print(id, ": not installed, skipped")
			continue
		var source = Pack.load_from_dir(folder)
		var zip_path: String = work.path_join("%s.zip" % id)
		DirAccess.remove_absolute(zip_path)

		var write_problems: PackedStringArray = Archive.write_pack(folder, zip_path, source.credit)
		var on_disk: int = FileAccess.open(zip_path, FileAccess.READ).get_length()
		var measured: Dictionary = Sizes.read(zip_path)
		var found: Dictionary = Archive.inspect(zip_path)

		print("")
		print("--- %s ---" % id)
		print("  exported ok:        ", write_problems.is_empty())
		print("  zip on disk:        ", Sizes.describe_bytes(on_disk))
		print("  measurable:         ", str(measured["problem"]).is_empty(),
			"" if str(measured["problem"]).is_empty() else "  (%s)" % measured["problem"])
		print("  unpacks to:         ", Sizes.describe_bytes(int(measured["total"])),
			" in ", measured["sizes"].size(), " entries")
		print("  inspect accepts it: ", found["problems"].is_empty())
		if not found["problems"].is_empty():
			print("  REFUSED: ", found["problems"])

		# And all the way back out onto disk, as an import would.
		var target: String = work.path_join("unpacked_%s" % id)
		var problems: PackedStringArray = Archive.extract(zip_path, str(found["root"]), target)
		print("  extract problems:   ", problems if not problems.is_empty() else "none")
		var reloaded = Pack.load_from_dir(target)
		print("  reloads as usable:  ", reloaded.is_usable(),
			"  kind ", reloaded.kind, ", name ", reloaded.display_name)
		if not reloaded.is_usable():
			print("  PROBLEMS: ", reloaded.problems)
	quit(0)
