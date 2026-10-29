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
signal library_reloaded()

const PETS_SUBDIR := "pets"
const BUILTIN_PETS_DIR := "res://builtin/pets"

## Every pack good enough to show, in folder order.
var pets: Array[PetPack] = []

## The pack currently on screen. Never null once _ready has run, unless even
## the built-in pack is missing.
var active_pet: PetPack = null

## True when we fell back to the pack inside the exe.
var using_builtin: bool = false


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

	library_reloaded.emit()
	_activate(_find(wanted), false)


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
