class_name PetPose
extends RefCounted
## Where the dog is and how it is holding itself, for one frame.
##
## This is the one language the 3D pets and the 2D sprite pets both speak.
## PetMotion works out a pose from the state and the clock, and PetView
## turns it into either a Node3D transform or a Sprite2D transform. Nothing
## in between needs to know which kind of pet it is looking at.
##
## Distances are in body heights, not pixels or metres, so the same numbers
## suit a 1-unit-tall 3D pug and a 129-pixel-tall sprite. An offset.y of
## 0.18 means "up by 18% of your own height", whoever you are.

## Up is positive y, right is positive x, in body heights.
var offset := Vector2.ZERO

## Squash and stretch. 1,1 is the dog's normal shape.
var scale := Vector2.ONE

## Head tilt, the quizzical sideways lean.
var roll_degrees: float = 0.0

## Nose down (positive) or up (negative).
var pitch_degrees: float = 0.0

## Turning on the spot. 3D pets really turn; sprite pets squeeze
## horizontally instead, which reads as the same thing.
var yaw_degrees: float = 0.0

## Which way the dog faces: 1 for right, -1 for left.
var facing: float = 1.0

## Multiplied over the dog's colours. Used to take the life out of a sad
## dog without needing a second set of art.
var tint := Color.WHITE


func duplicate_pose() -> PetPose:
	var copy := PetPose.new()
	copy.offset = offset
	copy.scale = scale
	copy.roll_degrees = roll_degrees
	copy.pitch_degrees = pitch_degrees
	copy.yaw_degrees = yaw_degrees
	copy.facing = facing
	copy.tint = tint
	return copy


## Add another pose on top of this one, for layering a fidget over idle.
## Offsets and angles add; scales multiply; facing and tint are taken from
## whichever pose is doing the talking.
func add(other: PetPose) -> void:
	offset += other.offset
	scale *= other.scale
	roll_degrees += other.roll_degrees
	pitch_degrees += other.pitch_degrees
	yaw_degrees += other.yaw_degrees


## Part way from one pose to another. This is what keeps a change of state
## from snapping: the animator blends across about a third of a second.
static func blend(from: PetPose, to: PetPose, amount: float) -> PetPose:
	var t: float = clampf(amount, 0.0, 1.0)
	var out := PetPose.new()
	out.offset = from.offset.lerp(to.offset, t)
	out.scale = from.scale.lerp(to.scale, t)
	out.roll_degrees = lerpf(from.roll_degrees, to.roll_degrees, t)
	out.pitch_degrees = lerpf(from.pitch_degrees, to.pitch_degrees, t)
	out.yaw_degrees = lerpf(from.yaw_degrees, to.yaw_degrees, t)
	# Facing is a direction, not a dial. Turning 180 degrees through a blend
	# would look like the dog melting, so it switches at the half-way mark.
	out.facing = to.facing if t >= 0.5 else from.facing
	out.tint = from.tint.lerp(to.tint, t)
	return out
