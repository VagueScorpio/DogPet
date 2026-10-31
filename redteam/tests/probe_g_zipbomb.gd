extends SceneTree
## RT-03 probe: PackArchive used to read every zip entry whole into memory
## with no size limit. ZIPReader.read_file allocates whatever an entry's index
## says it is, so a pack zip of a few hundred KB could ask for gigabytes on
## Import pack.
##
## Before the fix: 597 KB zip -> 3,024 MB peak, and inspect ACCEPTED the pack.
## After the fix: refused from the zip's index, memory flat.

const Archive := preload("res://scripts/pack_archive.gd")
const Sizes := preload("res://scripts/zip_sizes.gd")

const BOMB_MB := 600

func _init() -> void:
	var dir: String = OS.get_user_data_dir().path_join("rt_zip_probe")
	DirAccess.make_dir_recursive_absolute(dir)
	var zip_path: String = dir.path_join("bomb.zip")
	DirAccess.remove_absolute(zip_path)

	# Highly compressible padding in front of a perfectly valid manifest, so
	# the JSON parser would skip the padding and accept the pack.
	var manifest := '{"id":"bomb","name":"Bomb","kind":"model3d","model":"m.glb","credit":"x"}'
	var padding: PackedByteArray = PackedByteArray()
	padding.resize(BOMB_MB * 1024 * 1024)
	padding.fill(32)

	var packer := ZIPPacker.new()
	print("packing a ", BOMB_MB, " MB pet.json ...")
	if packer.open(zip_path) != OK:
		print("could not open the zip for writing"); quit(1); return
	packer.start_file("pet.json")
	packer.write_file(padding)
	packer.write_file(manifest.to_utf8_buffer())
	packer.close_file()
	packer.close()
	padding = PackedByteArray()

	var on_disk: int = FileAccess.open(zip_path, FileAccess.READ).get_length()
	print("zip on disk: ", on_disk, " bytes (", "%.1f" % (on_disk / 1024.0), " KB)")

	# What the zip's own index claims, read without decompressing anything.
	var measured: Dictionary = Sizes.read(zip_path)
	print("index readable: ", str(measured["problem"]).is_empty())
	print("declared size of pet.json: ", Sizes.size_of(measured["sizes"], "pet.json"),
		" bytes (", Sizes.describe_bytes(Sizes.size_of(measured["sizes"], "pet.json")), ")")

	# Measured as the change across inspect, not as the process peak: this
	# probe had to build the 600 MB bomb itself to write the zip, so the peak
	# high-water mark is the probe's own doing and says nothing about inspect.
	var before: int = OS.get_static_memory_usage()
	var t0: int = Time.get_ticks_msec()
	var found: Dictionary = Archive.inspect(zip_path)
	var elapsed: int = Time.get_ticks_msec() - t0
	var after: int = OS.get_static_memory_usage()
	print("inspect took ms: ", elapsed)
	print("memory held before inspect: ", before / 1048576, " MB")
	print("memory held after inspect:  ", after / 1048576, " MB")
	print("inspect itself allocated:   ", (after - before) / 1024, " KB")
	print("inspect accepted the pack: ", found["problems"].is_empty())
	if not found["problems"].is_empty():
		print("why: ", found["problems"][0])
	print("amplification refused at: ", "%.0fx" % (float(BOMB_MB * 1024 * 1024) / float(on_disk)))

	# And extracting it must refuse too, in case anything ever calls that
	# without inspecting first.
	var target: String = dir.path_join("unpacked")
	var extract_problems: PackedStringArray = Archive.extract(zip_path, "", target)
	print("extract problems: ", extract_problems)

	DirAccess.remove_absolute(zip_path)
	quit(0)
