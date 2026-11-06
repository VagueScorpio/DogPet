extends "res://tests/suite.gd"
## Headless tests for the rooms and the care actions.
##
## Run them from the project root with:
##
##   godot --headless --path . --script res://tests/test_scenes.gd
##
## On a fresh clone, run "godot --headless --path . --import" once first so
## Godot builds its caches.

const Room := preload("res://scripts/scene_pack.gd")
const Plan := preload("res://scripts/action_plan.gd")
const Motion := preload("res://scripts/pet_motion.gd")

const ASSETS_SCENES := "assets/scenes"


func _initialize() -> void:
	_open("DogPet room tests")

	_test_real_rooms()
	_test_roles()
	_test_backgrounds()
	_test_props()
	_test_tile_sizes()
	_test_actions()

	_report()


func _rooms_dir() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").path_join(ASSETS_SCENES)


# --- The rooms that actually ship ----------------------------------------

func _test_real_rooms() -> void:
	_begin("All four shipped rooms load")
	for role in Room.ROLES:
		var room: ScenePack = Room.load_from_dir(_rooms_dir().path_join(role))
		_ok("%s is usable" % role, room.is_usable())
		_ok("%s fills the %s slot" % [role, role], room.role == role)
		if not room.problems.is_empty():
			for problem in room.problems:
				print("          %s" % problem)
		_ok("%s has nothing wrong with it" % role, room.is_valid())

	_begin("Each room is the kind it should be")
	var home: ScenePack = Room.load_from_dir(_rooms_dir().path_join("home"))
	var eat: ScenePack = Room.load_from_dir(_rooms_dir().path_join("eat"))
	var play: ScenePack = Room.load_from_dir(_rooms_dir().path_join("play"))
	var walk: ScenePack = Room.load_from_dir(_rooms_dir().path_join("walk"))

	_ok("the living room is tiled", home.background["type"] == Room.BG_TILED)
	_ok("the kitchen is tiled", eat.background["type"] == Room.BG_TILED)
	_ok("the yard is drawn in code", play.background["type"] == Room.BG_GENERATED)
	_ok("the park is drawn in code", walk.background["type"] == Room.BG_GENERATED)
	_ok("the yard is a yard", play.background["style"] == "yard")
	_ok("the park is a park", walk.background["style"] == "park")

	_begin("Only the park moves")
	_ok("the park scrolls", walk.scrolls())
	_ok("the living room does not", not home.scrolls())
	_ok("the yard does not", not play.scrolls())
	_ok("and the park slides in", walk.transition == Room.TRANSITION_SLIDE)
	_ok("while the others fade", home.transition == Room.TRANSITION_FADE)

	_begin("The rooms carry the props the actions need")
	_ok("the kitchen has a food bowl", not eat.prop_with_role(Room.ROLE_FOOD_BOWL).is_empty())
	_ok("the yard has a toy", not play.prop_with_role(Room.ROLE_TOY).is_empty())
	_ok("the living room needs neither", home.prop_with_role(Room.ROLE_TOY).is_empty())


# --- Which slot a room fills --------------------------------------------

func _test_roles() -> void:
	_begin("A room says which slot it fills")
	# This is what lets a folder be called anything and still be a kitchen,
	# so that a slot can offer several rooms to choose between.
	var named: ScenePack = Room.from_dictionary(
		{"role": "eat", "name": "Night Kitchen"}, "res://rooms/kitchen_at_night"
	)
	_ok("the folder name does not decide the slot", named.role == Room.EAT)
	_ok("but it does become the id", named.id == "kitchen_at_night")
	_ok("and the room keeps its own name", named.display_name == "Night Kitchen")
	_ok("it is usable", named.is_usable())

	_begin("A room with no role falls back to its folder name")
	var unnamed: ScenePack = Room.from_dictionary({}, "res://rooms/play")
	_ok("so the four original folders still work", unnamed.role == Room.PLAY)

	_begin("A room filling no known slot is rejected")
	var nonsense: ScenePack = Room.from_dictionary({"role": "bathroom"}, "res://rooms/odd")
	_ok("it is not usable", not nonsense.is_usable())
	_ok("and it says why", not nonsense.problems.is_empty())

	_begin("An unknown transition falls back to a fade")
	var odd: ScenePack = Room.from_dictionary(
		{"role": "home", "transition": "explode"}, "res://rooms/x"
	)
	_ok("it is reported", not odd.is_valid())
	_ok("but it still works", odd.transition == Room.TRANSITION_FADE)


# --- Backgrounds ---------------------------------------------------------

func _test_backgrounds() -> void:
	_begin("A missing picture never leaves a room blank")
	var missing: ScenePack = Room.from_dictionary({
		"role": "home",
		"background": {"type": "image", "file": "gone.png"},
	}, "res://rooms/x")
	_ok("it falls back to something drawn", missing.background["type"] == Room.BG_GENERATED)
	_ok("the room is still usable", missing.is_usable())
	_ok("and the problem is recorded", not missing.is_valid())

	var half_tiled: ScenePack = Room.from_dictionary({
		"role": "home",
		"background": {"type": "tiled", "wall": "gone.png", "floor": "also_gone.png"},
	}, "res://rooms/x")
	_ok("a missing tile falls back too", half_tiled.background["type"] == Room.BG_GENERATED)

	var unknown: ScenePack = Room.from_dictionary({
		"role": "home", "background": {"type": "hologram"},
	}, "res://rooms/x")
	_ok("so does an unknown type", unknown.background["type"] == Room.BG_GENERATED)

	_begin("Background numbers are kept sensible")
	var silly: ScenePack = Room.from_dictionary({
		"role": "home",
		"background": {"type": "generated", "style": "yard", "ground_ratio": 40.0},
	}, "res://rooms/x")
	_ok("a ground ratio is clamped", float(silly.background["ground_ratio"]) <= 1.0)

	var bad_style: ScenePack = Room.from_dictionary({
		"role": "home", "background": {"type": "generated", "style": "moon"},
	}, "res://rooms/x")
	_ok("an unknown style becomes a yard", bad_style.background["style"] == "yard")

	_begin("Colours are read from the file")
	var coloured: ScenePack = Room.from_dictionary({
		"role": "home",
		"background": {"type": "generated", "style": "yard", "ground": "#112233"},
	}, "res://rooms/x")
	var ground: Color = coloured.background["ground"]
	_ok("the ground colour came through", ground.is_equal_approx(Color("#112233")))

	# RT-18. A scene.json out of somebody else's zip may name a picture
	# outside its own folder. A room that reaches outside itself is broken
	# the same way a room with a missing picture is, so it is treated the
	# same: it falls back to something drawn.
	_begin("A room cannot name pictures outside its own folder")
	var climbing: ScenePack = Room.from_dictionary({
		"role": "home",
		"background": {"type": "image", "file": "../../photo.png"},
	}, "res://rooms/x")
	_ok("a background above the room is refused",
		climbing.background["type"] == Room.BG_GENERATED)
	_ok("and the room still works", climbing.is_usable())

	var absolute: ScenePack = Room.from_dictionary({
		"role": "home",
		"background": {"type": "tiled", "wall": "C:/Windows/x.png", "floor": "f.png"},
	}, "res://rooms/x")
	_ok("so is a drive-absolute tile",
		absolute.background["type"] == Room.BG_GENERATED)

	var prop_out: ScenePack = Room.from_dictionary({
		"role": "home",
		"background": {"type": "generated", "style": "yard"},
		"props": [{"file": "../../bowl.png", "x": 0.5, "y": 0.8, "scale": 1}],
	}, "res://rooms/x")
	_ok("a prop above the room is dropped", prop_out.props.is_empty())
	_ok("and the room keeps working anyway", prop_out.is_usable())


# --- Props ---------------------------------------------------------------

func _test_props() -> void:
	_begin("Props are drawn back to front")
	var eat: ScenePack = Room.load_from_dir(_rooms_dir().path_join("eat"))
	var ordered: bool = true
	for index in range(1, eat.props.size()):
		if float(eat.props[index]["y"]) < float(eat.props[index - 1]["y"]):
			ordered = false
	_ok("the kitchen's props are in order", ordered)
	_ok("and all four survived", eat.props.size() == 4)

	_begin("A prop can claim a job, with a backup")
	var room: ScenePack = Room.from_dictionary({
		"role": "play",
		"props": [
			{"file": "a.png", "x": 0.2, "y": 0.9, "role": "toy_alt"},
			{"file": "b.png", "x": 0.8, "y": 0.5, "role": "toy"},
		],
	}, _rooms_dir().path_join("play"))
	# Those files do not exist in that folder, so both are skipped and the
	# room falls back to having no toy at all - which must not crash.
	_ok("missing props are dropped, not fatal", room.is_usable())

	var real: ScenePack = Room.load_from_dir(_rooms_dir().path_join("play"))
	var toy: Dictionary = real.prop_with_role(Room.ROLE_TOY)
	_ok("the yard's toy is the tennis ball", str(toy["file"]).contains("tennis"))

	_begin("The dog stands beside a prop, not on it")
	var spot: Vector2 = real.spot_for_role(Room.ROLE_TOY)
	var toy_x: float = float(toy["x"])
	_ok("it is nudged towards the middle", absf(spot.x - 0.5) < absf(toy_x - 0.5))
	_ok("but stays on that side of the room", (spot.x - 0.5) * (toy_x - 0.5) > 0.0)
	_close("and stands at the prop's depth", spot.y, float(toy["y"]))

	_begin("With no such prop, the dog stands where the room says")
	var home: ScenePack = Room.load_from_dir(_rooms_dir().path_join("home"))
	var fallback: Vector2 = home.spot_for_role(Room.ROLE_FOOD_BOWL)
	_close("x matches the room's spot", fallback.x, home.pet_spot.x)
	_close("y matches too", fallback.y, home.pet_spot.y)

	_begin("The default standing spot")
	_close("centred", home.pet_spot.x, 0.5)
	_close("near the bottom", home.pet_spot.y, 0.82)
	var custom: ScenePack = Room.from_dictionary(
		{"role": "home", "pet_spot": {"x": 0.3, "y": 0.9}}, "res://rooms/x"
	)
	_close("a room can move it", custom.pet_spot.x, 0.3)


# --- The care actions ----------------------------------------------------

# RT-05. A room is drawn by stepping across and down the window one tile at a
# time, so the cost is the window's area divided by the tile's. A 1x1 pixel
# tile asked for 3.7 million draw calls a frame on a maximised window, which
# froze the app - and the room is remembered, so restarting went straight back
# into it. The scale is raised to suit the tile rather than the room refused.
func _test_tile_sizes() -> void:
	_begin("A room's tiles cannot be small enough to freeze the window")
	var dir: String = ProjectSettings.globalize_path("user://test_tiles")
	DirAccess.make_dir_recursive_absolute(dir)

	for side in [1, 4, 32]:
		var image: Image = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.5, 0.4, 0.3))
		image.save_png(dir.path_join("t%d.png" % side))

	_ok("a 1x1 tile is raised to the minimum", _scale_for(dir, 1, 1) == Room.MIN_TILE_PIXELS)
	_ok("a 4x4 tile is raised to reach it", _scale_for(dir, 4, 1) == 2)
	_ok("a 32x32 tile is left alone", _scale_for(dir, 32, 1) == 1)
	_ok("and keeps a larger scale the author asked for", _scale_for(dir, 32, 4) == 4)
	# The check is on the drawn result, so a scale that is bigger but still not
	# big enough cannot slip through.
	_ok("a 1x1 tile at scale 4 is still raised", _scale_for(dir, 1, 4) == Room.MIN_TILE_PIXELS)
	_ok("and the room says so", not _tiled(dir, 1, 1).problems.is_empty())
	_ok("while an ordinary room stays quiet", _tiled(dir, 32, 4).problems.is_empty())
	_ok("a room with raised tiles is still perfectly usable", _tiled(dir, 1, 1).is_usable())

	for side in [1, 4, 32]:
		DirAccess.remove_absolute(dir.path_join("t%d.png" % side))
	DirAccess.remove_absolute(dir)


func _tiled(dir: String, side: int, asked: int) -> ScenePack:
	return Room.from_dictionary({
		"role": "home", "name": "T",
		"background": {
			"type": "tiled", "wall": "t%d.png" % side,
			"floor": "t%d.png" % side, "tile_scale": asked,
		},
	}, dir)


func _scale_for(dir: String, side: int, asked: int) -> int:
	return int(_tiled(dir, side, asked).background["tile_scale"])


func _test_actions() -> void:
	_begin("Each action knows its room, state and prop")
	_ok("feeding happens in the eat room", Plan.room_role(Plan.FEED) == Room.EAT)
	_ok("playing happens in the play room", Plan.room_role(Plan.PLAY) == Room.PLAY)
	_ok("walking happens in the walk room", Plan.room_role(Plan.WALK) == Room.WALK)

	_ok("feeding plays the eat state", Plan.pet_state(Plan.FEED) == Motion.EAT)
	_ok("playing plays the play state", Plan.pet_state(Plan.PLAY) == Motion.PLAY)
	_ok("walking plays the walk state", Plan.pet_state(Plan.WALK) == Motion.WALK)

	_ok("feeding uses the bowl", Plan.prop_role(Plan.FEED) == Room.ROLE_FOOD_BOWL)
	_ok("playing uses the toy", Plan.prop_role(Plan.PLAY) == Room.ROLE_TOY)
	_ok("walking needs no prop", Plan.prop_role(Plan.WALK) == "")

	_begin("Only feeding sends the dog across the room")
	_ok("the dog walks to its bowl", Plan.walks_to_prop(Plan.FEED))
	_ok("but the toy comes to the dog", not Plan.walks_to_prop(Plan.PLAY))
	_ok("and a walk stays put while the scenery moves", not Plan.walks_to_prop(Plan.WALK))

	_begin("Every action's room really exists")
	for action in Plan.ACTIONS:
		var role: String = Plan.room_role(action)
		_ok("%s has a %s room to go to" % [action, role], Room.ROLES.has(role))
		var room: ScenePack = Room.load_from_dir(_rooms_dir().path_join(role))
		_ok("%s's room loads" % action, room.is_usable())
		var needed: String = Plan.prop_role(action)
		if not needed.is_empty():
			_ok(
				"%s's room has a %s" % [action, needed],
				not room.prop_with_role(needed).is_empty()
			)

	_begin("Nothing else counts as an action")
	_ok("feed does", Plan.is_action(&"feed"))
	_ok("fly does not", not Plan.is_action(&"fly"))
	_ok("there are four, counting the vet", Plan.ACTIONS.size() == 4)
	_ok("three of them are everyday", Plan.EVERYDAY_ACTIONS.size() == 3)
	_ok("the vet is not one of those", not Plan.EVERYDAY_ACTIONS.has(Plan.VET))
	_ok("because it is Real play only", Plan.is_real_play_only(Plan.VET))
	_ok("unlike feeding", not Plan.is_real_play_only(Plan.FEED))
