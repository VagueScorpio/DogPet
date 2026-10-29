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
	var incoming := SceneView.new()
	add_child(incoming)
	incoming.setup(pack)

	var leaving: SceneView = _current
	_current = incoming

	if leaving == null or not animate:
		if leaving != null:
			leaving.queue_free()
		transition_finished.emit(role)
		return

	var style: String = transition if not transition.is_empty() else pack.transition
	_busy = true
	if style == ScenePack.TRANSITION_SLIDE:
		await _slide(leaving, incoming)
	else:
		await _fade(leaving, incoming)
	leaving.queue_free()
	_busy = false
	transition_finished.emit(role)


func is_busy() -> bool:
	return _busy


# A cross-fade: the new room is brought up over the old one.
func _fade(leaving: SceneView, incoming: SceneView) -> void:
	incoming.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(incoming, "modulate:a", 1.0, TRANSITION_SECONDS)
	tween.tween_property(leaving, "modulate:a", 0.0, TRANSITION_SECONDS)
	await tween.finished


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
	await tween.finished


func _on_scene_changed(role: String, _pack: ScenePack) -> void:
	if role == current_role and not _busy:
		show_role(role, ScenePack.TRANSITION_FADE, true)
