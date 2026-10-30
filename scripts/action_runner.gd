class_name ActionRunner
extends Node
## Runs a care action from beginning to end.
##
## Feed, Play and Walk each follow the same five steps, which is why they
## share one piece of code rather than having three of their own:
##
##   1. lock the buttons, so nothing can be started twice
##   2. transition to the action's room
##   3. play the animation for the action's length
##   4. apply the effect on the needs
##   5. transition home and unlock
##
## The effects land at step 4, after the animation rather than before it, so
## the bars move when the dog has actually been fed rather than the moment
## the button is pressed.

signal started(action: StringName)
signal finished(action: StringName)

## True while an action is running. The buttons watch this.
var running: bool = false

var _stage: SceneStage = null
var _pet: Control = null


func setup(stage: SceneStage, pet: Control) -> void:
	_stage = stage
	_pet = pet


## Run one of "feed", "play" or "walk". Does nothing if one is already
## running, so a second button press during an action is simply ignored.
func run(action: StringName) -> void:
	if running or not ActionPlan.is_action(action):
		return
	if _stage == null or _pet == null:
		Log.error("The action runner was never given a stage to work on.")
		return

	running = true
	started.emit(action)

	var role: String = ActionPlan.room_role(action)
	var room: ScenePack = AssetLibrary.active_scene(role)
	# Both legs of the journey use the same transition, so coming back
	# matches going out instead of sliding one way and fading the other.
	var style: String = room.transition if room != null else ScenePack.TRANSITION_FADE
	var seconds: float = Settings.action_seconds(String(action))

	Log.info("%s: %s for %.0fs" % [ActionPlan.label(action), role, seconds])

	await _stage.show_role(role, style)
	_position_pet(action, room)
	_pet.play_state(ActionPlan.pet_state(action))

	# Playing throws the toy for the dog to chase; the other actions have
	# nothing in the room that needs to move.
	if action == ActionPlan.PLAY and _stage.current_view() != null:
		_stage.current_view().throw_toy(seconds)

	await get_tree().create_timer(seconds).timeout

	Needs.apply_action(action)
	# The vet visit is the one action that does something beyond the three
	# needs: it is what brings the sickness bar down.
	if action == ActionPlan.VET:
		Needs.take_to_vet()

	await _stage.show_role(ScenePack.HOME, style)
	_return_pet()

	running = false
	finished.emit(action)


# Send the dog where the action happens. Feeding means walking over to the
# bowl; the others happen wherever the room says the dog stands.
func _position_pet(action: StringName, room: ScenePack) -> void:
	if room == null:
		return
	var spot: Vector2 = room.pet_spot
	if ActionPlan.walks_to_prop(action):
		spot = room.spot_for_role(ActionPlan.prop_role(action))
	_pet.set_pet_spot(spot)


func _return_pet() -> void:
	var home: ScenePack = AssetLibrary.active_scene(ScenePack.HOME)
	_pet.set_pet_spot(home.pet_spot if home != null else ScenePack.DEFAULT_PET_SPOT)
	_pet.resume_mood()
