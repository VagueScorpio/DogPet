extends Node
## Finds the art on disk and keeps track of which pet is wearing which body.
##
## Every folder under assets/pets/ with a readable pet.json is a pet the
## owner can pick. Nothing here is baked into the exe, so pets can be added,
## swapped or thrown away without rebuilding anything - which is the whole
## point of the loose assets folder.
##
## If assets/ is missing or every pack in it is broken, the built-in pack
## packed inside the exe is used instead and a notice goes in the log. The
## app must never come up with no dog at all.

signal pet_changed(pack: PetPack)
signal scene_changed(role: String, pack: ScenePack)
signal library_reloaded()

const PETS_SUBDIR := "pets"
const SCENES_SUBDIR := "scenes"
const BUILTIN_PETS_DIR := "res://builtin/pets"
const BUILTIN_SCENES_DIR := "res://builtin/scenes"

## Every pack good enough to show, in folder order.
var pets: Array[PetPack] = []

## The pack currently on screen. Never null once _ready has run, unless even
## the built-in pack is missing.
var active_pet: PetPack = null

## Every usable room, grouped by the role it fills. A role can have
## several rooms to choose between; the owner picks in Settings.
var scenes_by_role: Dictionary = {}

## The room showing in each role right now.
var active_scenes: Dictionary = {}

## True when we fell back to the art inside the exe.
var using_builtin: bool = false
var using_builtin_scenes: bool = false


func _ready() -> void:
	# Under --script there is no game, only the headless tests.
	if Paths.tool_script_mode:
		return
	reload()


## Rescan the assets folder from scratch. Settings offers this so art can be
## changed while the app is running.
func reload() -> void:
	var wanted: String = active_pet.id if active_pet != null else Needs.pet_pack_id

	pets = _scan(Paths.assets_subdir(PETS_SUBDIR))
	using_builtin = pets.is_empty()
	if using_builtin:
		Log.warn("No usable pet packs in assets/pets; falling back to the built-in pack.")
		pets = _scan(BUILTIN_PETS_DIR)

	if pets.is_empty():
		Log.error("No pet packs at all, not even the built-in one.")
		active_pet = null
		library_reloaded.emit()
		return

	Log.info("Found %d pet pack%s: %s" % [
		pets.size(),
		"" if pets.size() == 1 else "s",
		", ".join(pet_ids()),
	])

	_scan_scenes()

	library_reloaded.emit()
	_activate(_find(wanted), false)
	_activate_scenes()


# --- Rooms ---------------------------------------------------------------

func _scan_scenes() -> void:
	scenes_by_role = _group_by_role(_scan_scene_dir(Paths.assets_subdir(SCENES_SUBDIR)))
	using_builtin_scenes = scenes_by_role.is_empty()
	if using_builtin_scenes:
		Log.warn("No usable rooms in assets/scenes; falling back to the built-in rooms.")
		scenes_by_role = _group_by_role(_scan_scene_dir(BUILTIN_SCENES_DIR))

	for role in ScenePack.ROLES:
		var rooms: Array = scenes_by_role.get(role, [])
		if rooms.is_empty():
			Log.warn("No room for the \"%s\" slot." % role)
		else:
			Log.info("Rooms for %s: %d (%s)" % [role, rooms.size(), ", ".join(_ids(rooms))])


func _scan_scene_dir(folder: String) -> Array[ScenePack]:
	var found: Array[ScenePack] = []
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for sub in DirAccess.get_directories_at(folder):
		var room_dir: String = folder.path_join(sub)
		if not FileAccess.file_exists(room_dir.path_join(ScenePack.SCENE_JSON)):
			continue
		var pack: ScenePack = ScenePack.load_from_dir(room_dir)
		for problem in pack.problems:
			Log.warn("Room \"%s\": %s" % [pack.id, problem])
		if pack.is_usable():
			found.append(pack)
		else:
			Log.warn("Skipping the room \"%s\"; it fills no known slot." % pack.id)
	return found


# Rooms declare which slot they fill, so the folder can be called anything
# and two rooms can offer themselves for the same slot.
func _group_by_role(rooms: Array[ScenePack]) -> Dictionary:
	var grouped: Dictionary = {}
	for pack in rooms:
		if not grouped.has(pack.role):
			grouped[pack.role] = [] as Array[ScenePack]
		grouped[pack.role].append(pack)
	return grouped


## Every room offering itself for a slot.
func scenes_for(role: String) -> Array[ScenePack]:
	var rooms: Array = scenes_by_role.get(role, [])
	var typed: Array[ScenePack] = []
	for pack in rooms:
		typed.append(pack)
	return typed


## The room showing in a slot, or null if there is none at all.
func active_scene(role: String) -> ScenePack:
	return active_scenes.get(role, null)


## Switch a slot to another room and remember the choice.
func set_active_scene(role: String, id: String) -> void:
	for pack in scenes_for(role):
		if pack.id != id:
			continue
		if active_scenes.get(role, null) == pack:
			return
		active_scenes[role] = pack
		Settings.set_room(role, id)
		Log.info("Room for %s is now %s" % [role, pack.display_name])
		scene_changed.emit(role, pack)
		return
	Log.warn("No room called \"%s\" for the %s slot." % [id, role])


# Pick up each slot's saved choice, falling back to the first room found.
func _activate_scenes() -> void:
	for role in ScenePack.ROLES:
		var rooms: Array[ScenePack] = scenes_for(role)
		if rooms.is_empty():
			active_scenes.erase(role)
			continue
		var wanted: String = Settings.room_for(role)
		var chosen: ScenePack = rooms[0]
		for pack in rooms:
			if pack.id == wanted:
				chosen = pack
				break
		if not wanted.is_empty() and chosen.id != wanted:
			Log.info("The saved room \"%s\" is gone; using %s instead." % [wanted, chosen.id])
		active_scenes[role] = chosen
		scene_changed.emit(role, chosen)


static func _ids(rooms: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for pack in rooms:
		out.append(pack.id)
	return out


# --- Pets ----------------------------------------------------------------

func pet_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for pack in pets:
		ids.append(pack.id)
	return ids


## Switch to another pet. The needs are untouched - it is the same dog in a
## new body, not a new dog.
func set_active_pet(id: String) -> void:
	if active_pet != null and active_pet.id == id:
		return
	var pack: PetPack = _find(id)
	if pack == null:
		Log.warn("No pet pack called \"%s\"." % id)
		return
	_activate(pack, true)


## Every credit line we are showing art for, the active pet's first,
## because that is the one on screen. Settings shows these in About.
func credit_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if active_pet != null and not active_pet.credit.is_empty():
		lines.append(active_pet.credit)
	for pack in pets:
		if pack == active_pet or pack.credit.is_empty():
			continue
		if not lines.has(pack.credit):
			lines.append(pack.credit)
	for role in ScenePack.ROLES:
		for pack in scenes_for(role):
			if pack.credit.is_empty() or lines.has(pack.credit):
				continue
			lines.append(pack.credit)
	return lines


# --- Scanning ------------------------------------------------------------

func _scan(folder: String) -> Array[PetPack]:
	var found: Array[PetPack] = []
	if not DirAccess.dir_exists_absolute(folder):
		return found

	for sub in DirAccess.get_directories_at(folder):
		var pack: PetPack = PetPack.load_from_dir(folder.path_join(sub))
		# A pack with no pet.json at all is almost certainly not meant to be
		# a pack, so it passes without comment. Anything else is worth
		# saying out loud, because the owner probably meant it to work.
		if not FileAccess.file_exists(folder.path_join(sub).path_join(PetPack.PET_JSON)):
			continue
		for problem in pack.problems:
			Log.warn("Pet pack \"%s\": %s" % [pack.id, problem])
		if pack.is_usable():
			found.append(pack)
		else:
			Log.warn("Skipping the pet pack \"%s\"; it cannot be shown." % pack.id)
	return found


func _find(id: String) -> PetPack:
	for pack in pets:
		if pack.id == id:
			return pack
	return null


func _activate(pack: PetPack, remember: bool) -> void:
	var chosen: PetPack = pack
	if chosen == null:
		chosen = pets[0]
		if not Needs.pet_pack_id.is_empty():
			Log.info("The saved pet \"%s\" is gone; using %s instead." % [
				Needs.pet_pack_id, chosen.id,
			])
	active_pet = chosen
	if remember or Needs.pet_pack_id != chosen.id:
		Needs.set_pet_pack_id(chosen.id)
	Log.info("Active pet: %s (%s)" % [chosen.display_name, chosen.kind])
	pet_changed.emit(chosen)
