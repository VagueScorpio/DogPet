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


## Add the credits to a container. `host` owns the link callbacks.
static func build_into(parent: Control, _host: Node) -> void:
	for entry in gather():
		parent.add_child(_entry_block(entry))

	var extra: String = read_credits_file()
	if extra.is_empty():
		return
	var heading := Label.new()
	heading.text = "From assets/CREDITS.txt"
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	parent.add_child(heading)

	var body := Label.new()
	body.text = extra
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(body)


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

	var who := Label.new()
	who.text = str(entry["who"])
	who.add_theme_font_size_override("font_size", 12)
	box.add_child(who)

	# Exactly as the author wrote it, never reworded.
	var credit := Label.new()
	credit.text = str(entry["credit"])
	credit.add_theme_font_size_override("font_size", 11)
	credit.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(credit)

	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 10)
	var any: bool = false
	if not str(entry["license_url"]).is_empty():
		var label: String = str(entry["license"])
		links.add_child(_link(
			label if not label.is_empty() else "Licence", str(entry["license_url"])
		))
		any = true
	elif not str(entry["license"]).is_empty():
		var plain := Label.new()
		plain.text = str(entry["license"])
		plain.add_theme_font_size_override("font_size", 11)
		links.add_child(plain)
		any = true
	if not str(entry["source_url"]).is_empty():
		links.add_child(_link("Source", str(entry["source_url"])))
		any = true
	if any:
		box.add_child(links)

	return box


static func _link(text: String, url: String) -> LinkButton:
	var button := LinkButton.new()
	button.text = text
	button.tooltip_text = url
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(func() -> void: OS.shell_open(url))
	return button
