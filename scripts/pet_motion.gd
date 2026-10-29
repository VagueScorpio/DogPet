class_name PetMotion
extends RefCounted
## The procedural animation: a pose worked out from a state and a clock.
##
## This exists because neither 3D pet that ships with DogPet has a rig or a
## single animation clip. They are static meshes. So the life has to come
## from moving the whole dog about - breathing, hopping, tilting, bobbing -
## and that turns out to work just as well on a 2D sprite.
##
## Every function here is static and depends only on its arguments, so the
## same state at the same time always gives the same pose. That makes it
## testable, and it means a state can be scrubbed to any point rather than
## only played forwards. Anything genuinely random - which fidget, whether
## this particular happy spins - is decided by PetAnimator and passed in.

const IDLE := &"idle"
const HAPPY := &"happy"
const SAD := &"sad"
const EAT := &"eat"
const PLAY := &"play"
const WALK := &"walk"
const RESTLESS := &"restless"
const SLEEP := &"sleep"

const STATES: Array[StringName] = [IDLE, HAPPY, SAD, EAT, PLAY, WALK, RESTLESS, SLEEP]

## Fidgets, the small things an idle dog does so it does not look frozen.
const FIDGET_TILT := 0
const FIDGET_LOOK := 1
const FIDGET_HOP := 2
const FIDGET_COUNT := 3

const BREATH_SECONDS := 3.0
const HAPPY_HOP_SECONDS := 0.45
const HAPPY_HOPS := 3
const FIDGET_SECONDS := 0.9


## The pose for a state at a moment in time.
##
## `variation` is a number from 0 to 1 that PetAnimator rolls once when the
## state begins, so that two happy moments are not identical. Pass the same
## value for the same run and the motion stays reproducible.
static func pose_for(state: StringName, time: float, variation: float = 0.0) -> PetPose:
	match state:
		HAPPY:
			return _happy(time, variation)
		SAD:
			return _sad(time)
		EAT:
			return _eat(time)
		PLAY:
			return _play(time)
		WALK:
			return _walk(time)
		RESTLESS:
			return _restless(time, variation)
		SLEEP:
			return _sleep(time)
	return _idle(time)


## A dog doing nothing much: slow breathing, and that is all. The fidgets
## are layered on top of this by the animator.
static func _idle(time: float) -> PetPose:
	var pose := PetPose.new()
	var breath: float = sin(time * TAU / BREATH_SECONDS)
	# Chest out, waist in, so it reads as breathing rather than resizing.
	pose.scale = Vector2(1.0 - 0.01 * breath, 1.0 + 0.02 * breath)
	return pose


## Two or three quick hops with a squash on each landing, and a full spin
## about a third of the time.
static func _happy(time: float, variation: float) -> PetPose:
	var pose := PetPose.new()
	var hop_index: int = int(floor(time / HAPPY_HOP_SECONDS))
	if hop_index >= HAPPY_HOPS:
		return _idle(time)

	var phase: float = fmod(time, HAPPY_HOP_SECONDS) / HAPPY_HOP_SECONDS
	var air: float = sin(phase * PI)            # 0 on the ground, 1 at the top
	var contact: float = pow(1.0 - air, 6.0)    # only near the ground

	pose.offset.y = 0.18 * air
	pose.scale = Vector2(
		1.0 - 0.06 * air + 0.10 * contact,
		1.0 + 0.10 * air - 0.14 * contact
	)

	# Roughly one happy moment in three turns all the way round.
	if variation < 0.3:
		var whole: float = clampf(time / (HAPPY_HOPS * HAPPY_HOP_SECONDS), 0.0, 1.0)
		pose.yaw_degrees = 360.0 * smoothstep(0.0, 1.0, whole)
	return pose


## Lower, slower, nose down, and the colour goes out of it.
static func _sad(time: float) -> PetPose:
	var pose := PetPose.new()
	var breath: float = sin(time * TAU / (BREATH_SECONDS * 2.0))
	pose.offset.y = -0.08
	pose.scale = Vector2(1.0 + 0.01, 1.0 + 0.015 * breath)
	pose.pitch_degrees = 14.0
	# A slow sway, far apart, so it looks listless rather than busy.
	pose.roll_degrees = 4.0 * sin(time * TAU / 7.0)
	pose.tint = Color(0.78, 0.78, 0.84)
	return pose


## Head down at the bowl, nodding about two and a half times a second.
static func _eat(time: float) -> PetPose:
	var pose := PetPose.new()
	var nod: float = 0.5 - 0.5 * cos(time * TAU * 2.5)
	pose.pitch_degrees = 20.0 * nod
	pose.offset.y = -0.03 * nod
	return pose


## Chasing something: a fast run bob, interrupted by a pounce.
static func _play(time: float) -> PetPose:
	var pose := PetPose.new()
	var pounce_cycle: float = 1.6
	var phase: float = fmod(time, pounce_cycle) / pounce_cycle

	if phase > 0.65:
		# The pounce: a big jump with a stretch going up and a squash landing.
		var jump: float = (phase - 0.65) / 0.35
		var air: float = sin(jump * PI)
		pose.offset.y = 0.22 * air
		pose.offset.x = 0.10 * sin(jump * PI)
		pose.scale = Vector2(1.0 - 0.08 * air, 1.0 + 0.12 * air)
		pose.pitch_degrees = -10.0 * air
	else:
		# Running: quick low bobs, leaning into it.
		var run: float = absf(sin(time * TAU * 3.0))
		pose.offset.y = 0.06 * run
		pose.pitch_degrees = -4.0
		pose.roll_degrees = 3.0 * sin(time * TAU * 1.5)

	# Turning back and forth after the toy.
	pose.facing = 1.0 if sin(time * TAU / pounce_cycle) >= 0.0 else -1.0
	return pose


## A steady trot, side on, about four paces a second. The scene scrolls past
## behind this; the dog itself stays put.
static func _walk(time: float) -> PetPose:
	var pose := PetPose.new()
	pose.offset.y = 0.035 * absf(sin(time * TAU * 4.0))
	pose.roll_degrees = 2.0 * sin(time * TAU * 2.0)
	# Side on to the camera, so it reads as going somewhere.
	pose.yaw_degrees = 70.0
	return pose


## Too much energy: pacing back and forth, with the occasional zoomie.
static func _restless(time: float, variation: float) -> PetPose:
	var pose := PetPose.new()
	var pace_cycle: float = 1.6
	var sweep: float = sin(time * TAU / pace_cycle)

	pose.offset.x = 0.28 * sweep
	pose.offset.y = 0.05 * absf(sin(time * TAU * 5.0))
	# Face the way it is actually travelling.
	pose.facing = 1.0 if cos(time * TAU / pace_cycle) >= 0.0 else -1.0

	# Every five seconds or so, a spin. The variation shifts when it lands,
	# so two restless dogs are not in lockstep.
	var zoomie_cycle: float = 5.0
	var zoomie_phase: float = fmod(time + variation * zoomie_cycle, zoomie_cycle) / zoomie_cycle
	if zoomie_phase > 0.88:
		var spin: float = (zoomie_phase - 0.88) / 0.12
		pose.yaw_degrees = 360.0 * smoothstep(0.0, 1.0, spin)
	return pose


## Curled down and barely moving. The floating z's are PetView's doing.
static func _sleep(time: float) -> PetPose:
	var pose := PetPose.new()
	var breath: float = sin(time * TAU / 5.0)
	pose.offset.y = -0.07
	pose.scale = Vector2(1.08, 0.85 + 0.03 * breath)
	pose.roll_degrees = 6.0
	return pose


# --- Fidgets -------------------------------------------------------------

## A small extra movement laid over idle, so a waiting dog keeps living.
## `time` runs from 0 to FIDGET_SECONDS; outside that the fidget is over.
static func fidget_pose(kind: int, time: float) -> PetPose:
	var pose := PetPose.new()
	if time < 0.0 or time > FIDGET_SECONDS:
		return pose
	# Rises and falls over the fidget, so it starts and ends at nothing and
	# never fights the blend into the next state.
	var curve: float = sin(clampf(time / FIDGET_SECONDS, 0.0, 1.0) * PI)
	match kind:
		FIDGET_TILT:
			pose.roll_degrees = 8.0 * curve
		FIDGET_LOOK:
			pose.yaw_degrees = -22.0 * curve
		FIDGET_HOP:
			var air: float = sin(clampf(time / FIDGET_SECONDS, 0.0, 1.0) * PI)
			pose.offset.y = 0.09 * air
			pose.scale = Vector2(1.0 - 0.03 * air, 1.0 + 0.05 * air)
	return pose
