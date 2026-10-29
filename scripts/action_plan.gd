class_name ActionPlan
extends RefCounted
## What each care action involves, as plain lookups.
##
## Feed, Play and Walk each switch to a room, play an animation state, and
## may use a prop in that room. The names do not all match - feeding happens
## in the "eat" room - so the mapping lives here rather than being spelled
## out in three places, and the tests can check it without a window.
##
## How long each one runs and what it does to the needs are not here; those
## are tuning numbers and live in settings.json.

const FEED := &"feed"
const PLAY := &"play"
const WALK := &"walk"
const ACTIONS: Array[StringName] = [FEED, PLAY, WALK]


## The room this action happens in.
static func room_role(action: StringName) -> String:
	match action:
		FEED:
			return ScenePack.EAT
		PLAY:
			return ScenePack.PLAY
		WALK:
			return ScenePack.WALK
	return ScenePack.HOME


## The animation state the dog plays while it runs.
static func pet_state(action: StringName) -> StringName:
	match action:
		FEED:
			return PetMotion.EAT
		PLAY:
			return PetMotion.PLAY
		WALK:
			return PetMotion.WALK
	return PetMotion.IDLE


## The prop the dog uses, or "" when the action needs none.
##
## Feeding sends the dog over to the bowl; playing throws the toy. A walk
## needs no prop at all - the scenery does the moving.
static func prop_role(action: StringName) -> String:
	match action:
		FEED:
			return ScenePack.ROLE_FOOD_BOWL
		PLAY:
			return ScenePack.ROLE_TOY
	return ""


## True when the dog should walk over to the prop rather than stay put.
static func walks_to_prop(action: StringName) -> bool:
	return action == FEED


static func label(action: StringName) -> String:
	return String(action).capitalize()


static func is_action(name: StringName) -> bool:
	return ACTIONS.has(name)
