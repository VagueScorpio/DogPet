extends SceneTree
## RT-02 probe: a pack's source_url / license_url used to go straight to
## OS.shell_open when the owner clicked the licence link in Settings -> About.
##
## Writes its own harmless payload (a .cmd that creates a marker file) into
## the Godot user data folder, so the probe is self-contained.
##
## Before the fix: the marker appeared - the pack had launched a program.
## After the fix: PackLinks.web_url refuses it, so the link is never armed.
##
## Note it preloads PackLinks rather than CreditsList: CreditsList names the
## AssetLibrary autoload and so cannot compile in a --script run at all, which
## is exactly why the rule was moved out of it.

const Pack := preload("res://scripts/pet_pack.gd")
const Links := preload("res://scripts/pack_links.gd")

func _init() -> void:
	var dir: String = OS.get_user_data_dir().path_join("rt_shell_probe")
	DirAccess.make_dir_recursive_absolute(dir)
	var payload: String = dir.path_join("rt_payload.cmd")
	var marker: String = dir.path_join("rt_shell_marker.txt")
	DirAccess.remove_absolute(marker)

	var f: FileAccess = FileAccess.open(payload, FileAccess.WRITE)
	f.store_line("@echo off")
	f.store_line("> \"%~dp0rt_shell_marker.txt\" echo launched-by-shell_open-from-pack-json")
	f.close()

	# The pack loader still keeps whatever the JSON said, which is fine now
	# that nothing acts on it unchecked.
	var pack = Pack.from_dictionary({
		"id": "evil", "name": "Nice Dog", "kind": "sprite2d",
		"credit": "Someone", "license": "CC-BY 3.0",
		"license_url": payload, "source_url": payload,
		"animations": {"idle": {"file": "idle.png", "frames": 1}},
	}, "res://nowhere")
	print("license_url kept verbatim by the pack loader: ", pack.license_url == payload)

	# What the credits block now does with it.
	var allowed: String = Links.web_url(pack.license_url)
	print("web_url refuses it: ", allowed.is_empty())
	if allowed.is_empty():
		print("the link is never armed, so there is nothing to click")
	else:
		print("STILL ARMED - launching it, as the button would")
		OS.shell_open(allowed)
		var waited: int = 0
		while not FileAccess.file_exists(marker) and waited < 300:
			OS.delay_msec(10)
			waited += 1
	print("marker exists: ", FileAccess.file_exists(marker))

	print("")
	print("--- and the shipped pug pack still links properly ---")
	var real = Pack.load_from_dir(
		ProjectSettings.globalize_path("res://").trim_suffix("/").path_join("assets/pets/pug_3d"))
	print("  license_url allowed: ", Links.is_web_url(real.license_url),
		"   ", real.license_url)
	print("  source_url allowed:  ", Links.is_web_url(real.source_url),
		"   ", real.source_url)
	quit(0)
