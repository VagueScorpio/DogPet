class_name SceneStage
extends Control
## Holds the room on screen and changes it without the picture jumping.
##
## Two rooms exist at once only while a transition is running: the one
## leaving and the one arriving. A fade cross-dissolves between them; a
## slide pushes the old one out sideways, which is what makes starting a
## walk feel like going somewhere.

signal transition_finished(role: String)

const TRANSITION_SECONDS := 0.5

var current_role: String = ScenePack.HOME

var _current: SceneView = null
var _busy: bool = false

# Counts transitions started, so one that is overtaken partway through can
# tell that it no longer owns the stage. Two can overlap: a room picked in
# Settings while an action's own transition is still running.
var _generation: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	# If the owner picks a different room for the slot we are showing,
	# swap to it straight away rather than waiting for the next action.
	AssetLibrary.scene_changed.connect(_on_scene_changed)
	show_role(current_role, "", false)


func current_view() -> SceneView:
	return _current


## Put a room on screen. Awaiting this waits for the transition to finish.
##
## The transition normally comes from the room being shown, but an action
## passes its own so that leaving and coming back match each other.
func show_role(role: String, transition: String = "", animate: bool = true) -> void:
	var pack: ScenePack = AssetLibrary.active_scene(role)
	if pack == null:
		Log.warn("No room to show for the \"%s\" slot." % role)
		return

	current_role = role
	_generation += 1
	var mine: int = _generation

	var incoming := SceneView.new()
	add_child(incoming)
	incoming.setup(pack)

	var leaving: SceneView = _current
	_current = incoming

	if leaving == null or not animate:
		if leaving != null:
			leaving.queue_free()
		_busy = false
		transition_finished.emit(role)
		return

	var style: String = transition if not transition.is_empty() else pack.transition
	_busy = true
	if style == ScenePack.TRANSITION_SLIDE:
		_slide(leaving, incoming)
	else:
		_fade(leaving, incoming)

	# Waited out on a timer rather than on the tween itself. A second call
	# arriving mid-transition frees the room this one was animating, which
	# kills its tween without ever emitting finished - and this function
	# would then wait for it for ever, holding _busy true behind it.
	await get_tree().create_timer(TRANSITION_SECONDS).timeout
	if not is_inside_tree():
		return
	if is_instance_valid(leaving):
		leaving.queue_free()

	# Overtaken. The newer call owns the stage and will say so itself when
	# it is done; announcing it here too would tell whoever is waiting that
	# they have arrived in a room that has already been left.
	if mine != _generation:
		return
	_busy = false
	transition_finished.emit(role)


func is_busy() -> bool:
	return _busy


# A cross-fade: the new room is brought up over the old one. Started and
# left to run; show_role above does the waiting.
func _fade(leaving: SceneView, incoming: SceneView) -> void:
	incoming.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(incoming, "modulate:a", 1.0, TRANSITION_SECONDS)
	tween.tween_property(leaving, "modulate:a", 0.0, TRANSITION_SECONDS)


# The new room comes in from the right and pushes the old one off to the
# left, so it reads as travelling rather than simply changing.
func _slide(leaving: SceneView, incoming: SceneView) -> void:
	incoming.position.x = size.x
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(incoming, "position:x", 0.0, TRANSITION_SECONDS)
	tween.tween_property(leaving, "position:x", -size.x, TRANSITION_SECONDS)


func _on_scene_changed(role: String, _pack: ScenePack) -> void:
	# Allowed to interrupt a transition now. It used to be dropped if one
	# was running, which meant picking a room in Settings during an action
	# quietly did nothing; the newer call wins instead.
	if role == current_role:
		show_role(role, ScenePack.TRANSITION_FADE, true)
