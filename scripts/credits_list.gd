class_name CreditsList
extends RefCounted
## Builds the credits block in Settings -> About.
##
## This is not decoration. The default pug is CC-BY 3.0, which requires the
## credit to stay visible, and other packs may carry their own terms. So
## every installed pack's credit line is shown exactly as its author wrote
## it, with its licence and source as links where it gives them, and the
## whole of assets/CREDITS.txt underneath.
##
## The pet currently on screen comes first, because that is the art actually
## being shown.
##
## A pack's licence and source links are only made clickable when PackLinks
## says they are plain web addresses. One that is not is still printed - it has
## to be, since showing the licence URI is part of the attribution - but as
## text, because a clicked link reaches OS.shell_open and a pack is a file
## people download from each other.

# Reached by preload rather than by its class_name, the same way CareSettings
# reaches NeedsModel: a newly added script is not in the editor-generated class
# cache until the editor has rescanned, and neither a headless build nor the
# tests should have to wait for that.
const PackLinks := preload("res://scripts/pack_links.gd")


## Add the credits to a container. `host` owns the link callbacks.
static func build_into(parent: Control, _host: Node) -> void:
	for entry in gather():
		parent.add_child(_entry_block(entry))

	var extra: String = read_credits_file()
	if extra.is_empty():
		return
	parent.add_child(UiBits.heading("From assets/CREDITS.txt", 13, Color(1, 1, 1, 0.75)))
	parent.add_child(UiBits.dim(extra, 11, 0.0, true, Color(1, 1, 1, 0.55)))


## Every installed pack that has something to credit, active pet first.
static func gather() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	if AssetLibrary.active_pet != null:
		_add(entries, AssetLibrary.active_pet.credit, AssetLibrary.active_pet.license,
			AssetLibrary.active_pet.license_url, AssetLibrary.active_pet.source_url,
			"%s (showing now)" % AssetLibrary.active_pet.display_name)

	for pack in AssetLibrary.pets:
		if AssetLibrary.active_pet != null and pack.id == AssetLibrary.active_pet.id:
			continue
		_add(entries, pack.credit, pack.license, pack.license_url, pack.source_url,
			pack.display_name)

	for role in ScenePack.ROLES:
		for room in AssetLibrary.scenes_for(role):
			_add(entries, room.credit, room.license, room.license_url, room.source_url,
				room.display_name)

	return entries


## The whole of assets/CREDITS.txt, which covers the art that ships with
## DogPet whether or not each pack repeats it.
static func read_credits_file() -> String:
	var path: String = Paths.assets_dir.path_join("CREDITS.txt")
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()


static func _add(
	entries: Array[Dictionary], credit: String, license: String,
	license_url: String, source_url: String, who: String
) -> void:
	if credit.strip_edges().is_empty():
		return
	for existing in entries:
		if existing["credit"] == credit:
			return
	entries.append({
		"credit": credit,
		"license": license,
		"license_url": license_url,
		"source_url": source_url,
		"who": who,
	})


static func _entry_block(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)

	box.add_child(UiBits.heading(str(entry["who"]), 12))

	# Exactly as the author wrote it, never reworded.
	box.add_child(UiBits.dim(str(entry["credit"]), 11, 0.0, true, Color(1, 1, 1, 0.65)))

	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 10)
	var any: bool = false

	var licence_url: String = PackLinks.web_url(str(entry["license_url"]))
	if not licence_url.is_empty():
		var label: String = str(entry["license"])
		links.add_child(_link(
			label if not label.is_empty() else "Licence", licence_url
		))
		any = true
	elif not str(entry["license"]).is_empty():
		links.add_child(_plain(str(entry["license"])))
		any = true
	# A licence URI that is not a web address still has to be readable: showing
	# it is a condition of some of the licences this screen exists to satisfy.
	if licence_url.is_empty() and not str(entry["license_url"]).strip_edges().is_empty():
		links.add_child(_plain(str(entry["license_url"])))
		any = true

	var source_url: String = PackLinks.web_url(str(entry["source_url"]))
	if not source_url.is_empty():
		links.add_child(_link("Source", source_url))
		any = true
	elif not str(entry["source_url"]).strip_edges().is_empty():
		links.add_child(_plain(str(entry["source_url"])))
		any = true

	if any:
		box.add_child(links)

	return box


# A URL shown but not armed, in the same quiet style as the rest of the block.
static func _plain(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	return label


# Only ever handed a URL that web_url above has already approved.
static func _link(text: String, url: String) -> LinkButton:
	var button := LinkButton.new()
	button.text = text
	button.tooltip_text = url
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(func() -> void: OS.shell_open(url))
	return button
