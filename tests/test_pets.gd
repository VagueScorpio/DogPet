extends SceneTree
## Headless tests for the pet packs and the procedural animation.
##
## Run them from the project root with:
##
##   godot --headless --path . --script res://tests/test_pets.gd
##
## On a fresh clone, run "godot --headless --path . --import" once first so
## Godot builds its caches.
##
## Prints PASS or FAIL for every check, then exits 0 only if everything
## passed. The same shape as test_needs.gd, and for the same reason: the
## parts worth testing are the ones with no nodes in them.

const Pack := preload("res://scripts/pet_pack.gd")
const Motion := preload("res://scripts/pet_motion.gd")
const Pose := preload("res://scripts/pet_pose.gd")
const Model := preload("res://scripts/needs_model.gd")

const ASSETS_PETS := "assets/pets"

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	print("")
	print("DogPet pet tests")
	print("================")

	_test_real_packs()
	_test_pack_validation()
	_test_fit_transform()
	_test_sprite_scaling()
	_test_mood()
	_test_motion()

	print("")
	print("================")
	print("%d passed, %d failed" % [_passed, _failed])
	print("TESTS FAILED" if _failed > 0 else "All good.")
	quit(1 if _failed > 0 else 0)


# --- The packs that actually ship ----------------------------------------

func _test_real_packs() -> void:
	_begin("The three packs in assets/pets all load")
	var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/").path_join(ASSETS_PETS)

	for id in ["pug_3d", "pawsome_3d", "pug_pixel"]:
		var pack: PetPack = Pack.load_from_dir(root.path_join(id))
		_ok("%s is usable" % id, pack.is_usable())
		if not pack.is_usable():
			for problem in pack.problems:
				print("          %s" % problem)
		_ok("%s has a credit line" % id, not pack.credit.is_empty())
		_ok("%s kept its id" % id, pack.id == id)

	_begin("The default pug is a 3D model facing the camera")
	var pug: PetPack = Pack.load_from_dir(root.path_join("pug_3d"))
	_ok("it is a model3d pack", pug.kind == Pack.KIND_MODEL3D)
	_close("it is turned to face us", pug.rotation_y_degrees, -29.0)
	_ok("its CC-BY credit survived", pug.credit.contains("Smirnoff Alexander"))
	_ok("its licence is recorded", pug.license == "CC-BY 3.0")
	_ok("it has no clips, so motion is procedural", not pug.has_art_for("walk"))

	_begin("The pixel pug's sheets are measured correctly")
	var pixel: PetPack = Pack.load_from_dir(root.path_join("pug_pixel"))
	_ok("it is a sprite2d pack", pixel.kind == Pack.KIND_SPRITE2D)
	_ok("it has idle art", pixel.has_art_for("idle"))
	_ok("it has walk art", pixel.has_art_for("walk"))
	_ok("it has no eat art, so idle stands in", not pixel.has_art_for("eat"))
	var idle: Dictionary = pixel.sprite_animations["idle"]
	var walk: Dictionary = pixel.sprite_animations["walk"]
	_ok("idle is one 45x43 frame", idle["frame_width"] == 45 and idle["frame_height"] == 43)
	_ok("walk is four 43x32 frames", walk["frames"] == 4 and walk["frame_width"] == 43)
	_ok("walk frames are 32 tall", walk["frame_height"] == 32)
	_ok("the tallest frame in the pack is 43", pixel.tallest_frame_height() == 43)


# --- Catching broken packs ----------------------------------------------

func _test_pack_validation() -> void:
	_begin("A pack with nothing wrong passes")
	var good: PetPack = Pack.from_dictionary({
		"id": "test", "name": "Test", "kind": "sprite2d",
		"animations": {"idle": {"file": "nope.png", "frames": 1, "fps": 1}},
		"credit": "someone",
	}, "res://nowhere")
	# The image is missing, so it should complain about exactly that.
	_ok("a missing image is caught", not good.is_usable())

	_begin("Broken packs are caught, not crashed on")
	var bad_kind: PetPack = Pack.from_dictionary(
		{"id": "x", "kind": "hologram", "credit": "c"}, "res://nowhere"
	)
	_ok("an unknown kind is rejected", not bad_kind.is_usable())

	var no_model: PetPack = Pack.from_dictionary(
		{"id": "x", "kind": "model3d", "credit": "c"}, "res://nowhere"
	)
	_ok("a model3d pack with no model file is rejected", not no_model.is_usable())

	var no_idle: PetPack = Pack.from_dictionary({
		"id": "x", "kind": "sprite2d", "credit": "c",
		"animations": {"walk": {"file": "w.png", "frames": 2, "fps": 6}},
	}, "res://nowhere")
	_ok("a sprite pack with no idle is rejected", not no_idle.is_usable())

	var empty: PetPack = Pack.from_dictionary({}, "res://nowhere/mystery")
	_ok("an empty pet.json is rejected", not empty.is_usable())
	_ok("but it still names itself after its folder", empty.id == "mystery")

	_begin("A missing credit line is noted but not fatal")
	var no_credit: PetPack = Pack.from_dictionary(
		{"id": "x", "kind": "model3d", "model": "m.glb"}, "res://nowhere"
	)
	_ok("it is reported", no_credit.problems.has("no credit line"))
	# The model is missing too here, so check the rule itself directly.
	var only_credit := Pack.new()
	only_credit.problems.append("no credit line")
	_ok("on its own it does not stop the dog showing", only_credit.is_usable())
	_ok("though the pack is not strictly valid", not only_credit.is_valid())


# --- Making every dog the same size -------------------------------------

func _test_fit_transform() -> void:
	_begin("Models are scaled to a common height")
	# A box 4 units tall, sitting off-centre and above the floor.
	var bounds := AABB(Vector3(1.0, 5.0, -3.0), Vector3(2.0, 4.0, 6.0))
	var fit: Dictionary = Pack.fit_transform(bounds, 2.0)
	_close("a 4-tall model wanting 2 is halved", fit["scale"], 0.5)
	var offset: Vector3 = fit["offset"]
	_close("it is centred left to right", offset.x, -2.0)
	_close("its feet are brought to the floor", offset.y, -5.0)
	_close("it is centred front to back", offset.z, 0.0)

	_begin("Two very different models end up the same height")
	# Roughly the real case: the two shipped models differ by about 3x.
	var small := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	var large := AABB(Vector3(-1.5, 0.0, -1.5), Vector3(3.0, 3.0, 3.0))
	var small_fit: Dictionary = Pack.fit_transform(small, 1.0)
	var large_fit: Dictionary = Pack.fit_transform(large, 1.0)
	_close("the small one is scaled up to 1", small.size.y * float(small_fit["scale"]), 1.0)
	_close("the large one is scaled down to 1", large.size.y * float(large_fit["scale"]), 1.0)

	_begin("A model with no size does not divide by zero")
	var flat: Dictionary = Pack.fit_transform(AABB(Vector3.ZERO, Vector3.ZERO), 1.0)
	_close("the scale falls back to 1", flat["scale"], 1.0)


func _test_sprite_scaling() -> void:
	_begin("Pixel art is only ever scaled by whole numbers")
	_ok("43px art in a 160px box triples", Pack.integer_scale(43, 160.0) == 3)
	_ok("32px art in the same box could go 5x", Pack.integer_scale(32, 160.0) == 5)
	_ok("art taller than the box still shows at 1x", Pack.integer_scale(200, 160.0) == 1)
	_ok("a zero height does not crash", Pack.integer_scale(0, 160.0) == 1)
	_ok("an exact fit is not rounded down", Pack.integer_scale(40, 160.0) == 4)

	_begin("One scale for the pack, from its tallest frame")
	# The reason this matters: scaling each animation to fit on its own
	# would make the dog change size the moment it started walking.
	var by_tallest: int = Pack.integer_scale(43, 160.0)
	var by_walk_alone: int = Pack.integer_scale(32, 160.0)
	_ok("the two would disagree", by_tallest != by_walk_alone)
	_ok("so the tallest frame decides", by_tallest == 3)


# --- How the dog feels --------------------------------------------------

func _test_mood() -> void:
	_begin("The dog picks a state to match its mood")
	var model := Model.new()

	model.reset_to_cared()
	_ok("a contented dog idles", model.mood_state(-1.0) == &"idle")

	model.set_value(Model.ENERGY, 85.0)
	_ok("energy at 85 makes it restless", model.mood_state(-1.0) == &"restless")
	model.set_value(Model.ENERGY, 84.9)
	_ok("energy at 84.9 does not", model.mood_state(-1.0) == &"idle")

	model.reset_to_cared()
	model.set_value(Model.HAPPINESS, 25.0)
	_ok("happiness at 25 makes it sad", model.mood_state(-1.0) == &"sad")
	model.reset_to_cared()
	model.set_value(Model.HUNGER, 85.0)
	_ok("hunger at 85 makes it sad too", model.mood_state(-1.0) == &"sad")

	_begin("Worse feelings win")
	model.reset_to_cared()
	model.set_value(Model.ENERGY, 90.0)
	model.set_value(Model.HAPPINESS, 10.0)
	_ok("a wound-up miserable dog is restless, not sad", model.mood_state(-1.0) == &"restless")
	model.set_value(Model.ENERGY, 0.0)
	_ok("calm it down and the sadness shows", model.mood_state(-1.0) == &"sad")

	_begin("A care action leaves it pleased for a few seconds")
	model.reset_to_cared()
	_ok("just after an action it is happy", model.mood_state(0.0) == &"happy")
	_ok("three seconds later, still happy", model.mood_state(3.0) == &"happy")
	_ok("after four seconds it settles", model.mood_state(4.0) == &"idle")
	model.set_value(Model.HAPPINESS, 10.0)
	_ok("but a sad dog is not cheered by the clock", model.mood_state(0.0) == &"sad")

	_begin("Every mood is a state the animator knows")
	for mood in [&"idle", &"happy", &"sad", &"restless"]:
		_ok("%s is a real state" % mood, Motion.STATES.has(mood))


# --- The procedural animation -------------------------------------------

func _test_motion() -> void:
	_begin("Every state produces a sane pose")
	for state in Motion.STATES:
		var fine: bool = true
		# Walk through several seconds of each state looking for anything
		# that has gone to infinity, NaN, or inside out.
		for step in 120:
			var pose: PetPose = Motion.pose_for(state, step * 0.05, 0.5)
			if not _pose_is_sane(pose):
				fine = false
				break
		_ok("%s stays sane for six seconds" % state, fine)

	_begin("The same moment always looks the same")
	var first: PetPose = Motion.pose_for(Motion.HAPPY, 0.3, 0.2)
	var again: PetPose = Motion.pose_for(Motion.HAPPY, 0.3, 0.2)
	_close("offset matches", first.offset.y, again.offset.y, 0.0001)
	_close("scale matches", first.scale.y, again.scale.y, 0.0001)

	_begin("States look the way they are described")
	var idle_rest: PetPose = Motion.pose_for(Motion.IDLE, 0.0, 0.0)
	_close("idle starts at its normal size", idle_rest.scale.y, 1.0, 0.001)
	_close("and does not drift off the floor", idle_rest.offset.y, 0.0, 0.001)

	var sad: PetPose = Motion.pose_for(Motion.SAD, 1.0, 0.0)
	_ok("a sad dog sinks", sad.offset.y < 0.0)
	_ok("drops its nose", sad.pitch_degrees > 0.0)
	_ok("and loses some colour", sad.tint.r < 1.0)

	var happy: PetPose = Motion.pose_for(Motion.HAPPY, 0.22, 0.9)
	_ok("a happy dog leaves the ground", happy.offset.y > 0.05)
	var spinning: PetPose = Motion.pose_for(Motion.HAPPY, 1.3, 0.1)
	_ok("and sometimes spins all the way round", spinning.yaw_degrees > 180.0)
	var not_spinning: PetPose = Motion.pose_for(Motion.HAPPY, 1.3, 0.9)
	_close("but usually does not", not_spinning.yaw_degrees, 0.0)

	var walk: PetPose = Motion.pose_for(Motion.WALK, 0.6, 0.0)
	_ok("a walking dog turns side on", absf(walk.yaw_degrees) > 45.0)

	var eat_down: PetPose = Motion.pose_for(Motion.EAT, 0.2, 0.0)
	_ok("an eating dog nods down", eat_down.pitch_degrees > 0.0)

	_begin("A restless dog paces both ways")
	var left: bool = false
	var right: bool = false
	for step in 80:
		var pose: PetPose = Motion.pose_for(Motion.RESTLESS, step * 0.05, 0.0)
		if pose.offset.x < -0.1:
			left = true
		if pose.offset.x > 0.1:
			right = true
	_ok("it goes left", left)
	_ok("and right", right)

	_begin("Blending never jumps")
	var from := Pose.new()
	var to := Pose.new()
	to.offset = Vector2(1.0, 2.0)
	to.roll_degrees = 90.0
	var start: PetPose = Pose.blend(from, to, 0.0)
	var end: PetPose = Pose.blend(from, to, 1.0)
	var middle: PetPose = Pose.blend(from, to, 0.5)
	_close("at 0 it is the old pose", start.offset.y, 0.0)
	_close("at 1 it is the new one", end.offset.y, 2.0)
	_close("halfway is halfway", middle.offset.y, 1.0)
	_close("and angles come along", middle.roll_degrees, 45.0)
	_close("past the end it is clamped", Pose.blend(from, to, 5.0).offset.y, 2.0)

	_begin("Fidgets start and end at nothing")
	for kind in Motion.FIDGET_COUNT:
		var at_start: PetPose = Motion.fidget_pose(kind, 0.0)
		var at_end: PetPose = Motion.fidget_pose(kind, Motion.FIDGET_SECONDS)
		var outside: PetPose = Motion.fidget_pose(kind, Motion.FIDGET_SECONDS + 1.0)
		var quiet: bool = (
			_is_neutral(at_start) and _is_neutral(at_end) and _is_neutral(outside)
		)
		_ok("fidget %d leaves no trace behind it" % kind, quiet)
		var midway: PetPose = Motion.fidget_pose(kind, Motion.FIDGET_SECONDS * 0.5)
		_ok("fidget %d does something in the middle" % kind, not _is_neutral(midway))


# --- Small helpers -------------------------------------------------------

func _pose_is_sane(pose: PetPose) -> bool:
	for value in [
		pose.offset.x, pose.offset.y, pose.scale.x, pose.scale.y,
		pose.roll_degrees, pose.pitch_degrees, pose.yaw_degrees,
	]:
		if not is_finite(value):
			return false
	# A dog that is inside out or ten times its own size is a bug.
	if pose.scale.x <= 0.0 or pose.scale.y <= 0.0:
		return false
	if pose.scale.x > 2.0 or pose.scale.y > 2.0:
		return false
	if absf(pose.offset.x) > 1.0 or absf(pose.offset.y) > 1.0:
		return false
	return absf(pose.facing) == 1.0


func _is_neutral(pose: PetPose) -> bool:
	return (
		pose.offset.length() < 0.0001
		and absf(pose.scale.x - 1.0) < 0.0001
		and absf(pose.scale.y - 1.0) < 0.0001
		and absf(pose.roll_degrees) < 0.0001
		and absf(pose.pitch_degrees) < 0.0001
		and absf(pose.yaw_degrees) < 0.0001
	)


func _begin(section: String) -> void:
	print("")
	print(section)


func _ok(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)


func _close(label: String, got: float, want: float, tolerance: float = 0.01) -> void:
	if absf(got - want) <= tolerance:
		_ok(label, true)
	else:
		_ok(label, false)
		print("          got %.4f, wanted %.4f" % [got, want])
