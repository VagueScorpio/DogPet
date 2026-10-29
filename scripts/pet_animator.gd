class_name PetAnimator
extends RefCounted
## Keeps track of which state the dog is in and hands out a pose per frame.
##
## PetMotion knows what each state looks like; this decides which state is
## running, blends between them so nothing snaps, and schedules the small
## idle fidgets that stop a waiting dog from looking frozen.
##
## The blueprint describes the transitions as short tweens. They are done as
## a blend here instead: the pose the dog was holding is mixed into the new
## state's pose over a third of a second. Same result, and it survives a
## state changing again halfway through, which a tween would not.

const BLEND_SECONDS := 0.3
const FIDGET_MIN_GAP := 4.0
const FIDGET_MAX_GAP := 9.0

var state: StringName = PetMotion.IDLE

## How long the current state has been running. PetMotion is driven entirely
## by this, so a state can be scrubbed or restarted at will.
var state_time: float = 0.0

# Rolled once per state so two happy moments are not identical.
var _variation: float = 0.0

# The blend out of whatever the dog was doing before.
var _blend_left: float = 0.0
var _blend_from := PetPose.new()

# The idle fidget: a countdown, then a short movement, then a new countdown.
var _fidget_wait: float = 0.0
var _fidget_time: float = -1.0
var _fidget_kind: int = PetMotion.FIDGET_TILT

var _rng := RandomNumberGenerator.new()
var _current := PetPose.new()


func _init() -> void:
	_rng.randomize()
	_variation = _rng.randf()
	_schedule_fidget()


## Switch states. Asking for the state already running does nothing, so this
## is safe to call every frame from the mood logic.
func set_state(new_state: StringName) -> void:
	if new_state == state:
		return
	_blend_from = _current.duplicate_pose()
	_blend_left = BLEND_SECONDS
	state = new_state
	state_time = 0.0
	_variation = _rng.randf()
	# A fidget belongs to idle; drop it on the way out.
	_fidget_time = -1.0
	_schedule_fidget()


## Start the current state again from the beginning, for a repeated action.
func restart() -> void:
	state_time = 0.0
	_variation = _rng.randf()


## Move time on and return the pose for this frame.
func advance(delta: float) -> PetPose:
	state_time += delta

	var pose: PetPose = PetMotion.pose_for(state, state_time, _variation)

	# Fidgets ride on top of idle only; every other state is busy enough.
	if state == PetMotion.IDLE:
		_advance_fidget(delta)
		if _fidget_time >= 0.0:
			pose.add(PetMotion.fidget_pose(_fidget_kind, _fidget_time))

	if _blend_left > 0.0:
		_blend_left -= delta
		var remaining: float = clampf(_blend_left / BLEND_SECONDS, 0.0, 1.0)
		pose = PetPose.blend(_blend_from, pose, 1.0 - remaining)

	_current = pose
	return pose


## The pose handed out last frame, for anything that needs to look back.
func current_pose() -> PetPose:
	return _current


func _advance_fidget(delta: float) -> void:
	if _fidget_time >= 0.0:
		_fidget_time += delta
		if _fidget_time > PetMotion.FIDGET_SECONDS:
			_fidget_time = -1.0
			_schedule_fidget()
		return
	_fidget_wait -= delta
	if _fidget_wait <= 0.0:
		_fidget_kind = _rng.randi_range(0, PetMotion.FIDGET_COUNT - 1)
		_fidget_time = 0.0


func _schedule_fidget() -> void:
	_fidget_wait = _rng.randf_range(FIDGET_MIN_GAP, FIDGET_MAX_GAP)
