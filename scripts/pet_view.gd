extends Control
## The dog on screen, whichever kind of pet it happens to be.
##
## A 3D pet is rendered in a SubViewport with a transparent background, so a
## 3D dog can stand in front of a flat 2D room. A 2D pet is an ordinary
## AnimatedSprite2D. Both get the same poses from the same animator, and
## both get a soft blob shadow underneath, which is what sells the dog as
## standing on a floor rather than floating in front of one.

## Where the dog stands by default: centred, near the bottom. Scenes move
## this in phase 3.
const DEFAULT_SPOT := Vector2(0.5, 0.82)
const SPOT_TWEEN_SECONDS := 0.5

const SHADOW_WIDTH := 128
const SHADOW_HEIGHT := 56

@onready var _shadow: TextureRect = %Shadow
@onready var _viewport_box: SubViewportContainer = %Viewport3D
@onready var _viewport: SubViewport = %SubViewport
@onready var _camera: Camera3D = %Camera3D
@onready var _key_light: DirectionalLight3D = %KeyLight
@onready var _fill_light: DirectionalLight3D = %FillLight
@onready var _pivot: Node3D = %PetPivot
@onready var _facing: Node3D = %PetFacing
@onready var _sprite: AnimatedSprite2D = %Sprite
@onready var _zzz: Control = %Zzz

var animator := PetAnimator.new()

## While true the dog picks its own state from how it is feeling. A care
## action turns this off for as long as it runs, then hands it back.
var follow_mood: bool = true

var _pack: PetPack = null
var _model: Node3D = null
var _clips: AnimationPlayer = null
var _spot: Vector2 = DEFAULT_SPOT
var _sprite_scale: int = 1
var _body_height_px: float = 140.0
var _zzz_labels: Array[Label] = []


func _ready() -> void:
	_setup_camera_and_lights()
	_shadow.texture = _make_blob_texture(SHADOW_WIDTH, SHADOW_HEIGHT)
	_shadow.custom_minimum_size = Vector2(SHADOW_WIDTH, SHADOW_HEIGHT)
	_shadow.size = Vector2(SHADOW_WIDTH, SHADOW_HEIGHT)
	_build_zzz()

	AssetLibrary.pet_changed.connect(show_pack)
	if AssetLibrary.active_pet != null:
		show_pack(AssetLibrary.active_pet)

	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	if follow_mood:
		animator.set_state(Needs.mood_state())
	var pose: PetPose = animator.advance(delta)
	if _pack == null:
		return
	if _pack.kind == PetPack.KIND_SPRITE2D:
		_apply_pose_2d(pose)
	else:
		_apply_pose_3d(pose)
	_apply_shadow(pose)
	_update_zzz(delta)


## Play one state and stay in it, ignoring the mood. Used by the care
## actions, and by the debug picker.
func play_state(state: StringName) -> void:
	follow_mood = false
	animator.set_state(state)


## Go back to following how the dog feels.
func resume_mood() -> void:
	follow_mood = true


# --- Showing a pack -------------------------------------------------------

## Put a pet pack on screen, replacing whatever was there.
func show_pack(pack: PetPack) -> void:
	_pack = pack
	_clear()
	if pack == null:
		return

	if pack.kind == PetPack.KIND_SPRITE2D:
		_show_sprite(pack)
	else:
		_show_model(pack)
	_layout()


func _clear() -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	_clips = null
	_sprite.sprite_frames = null
	_sprite.hide()
	_viewport_box.hide()


func _show_model(pack: PetPack) -> void:
	_model = PetLoader.load_model(pack)
	if _model == null:
		Log.error("Could not show the pet \"%s\"." % pack.id)
		return
	_facing.add_child(_model)
	# Spin the whole pack so the dog looks at the camera. The pug is modelled
	# 29 degrees off, hence the odd number in its pet.json.
	_facing.rotation_degrees.y = pack.rotation_y_degrees
	_clips = PetLoader.find_animation_player(_model)
	if _clips != null:
		Log.info("The pet \"%s\" brought its own animations." % pack.id)
	_viewport_box.show()
	_body_height_px = 0.0  # worked out from the camera in _layout


func _show_sprite(pack: PetPack) -> void:
	var frames: SpriteFrames = PetLoader.build_sprite_frames(pack)
	if frames.get_animation_names().is_empty():
		Log.error("The pet \"%s\" has no usable frames." % pack.id)
		return
	_sprite.sprite_frames = frames
	# One scale for the whole pack, from its tallest frame, so the dog does
	# not change size between standing still and walking.
	_sprite_scale = PetPack.integer_scale(pack.tallest_frame_height(), pack.display_height_px)
	_sprite.scale = Vector2(_sprite_scale, _sprite_scale)
	_sprite.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST if pack.pixel_art
		else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	)
	_body_height_px = pack.tallest_frame_height() * _sprite_scale
	_play_sprite_animation(_state_art_name())
	_sprite.show()


# The pack may not have art for every state; anything missing uses idle, and
# the procedural motion carries the difference.
func _state_art_name() -> String:
	var state: String = String(animator.state)
	if _pack != null and _pack.has_art_for(state):
		return state
	return "idle"


func _play_sprite_animation(name: String) -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(name):
		return
	if _sprite.animation == name and _sprite.is_playing():
		return
	_sprite.animation = name
	# Frames differ in size between animations, so the offset that puts the
	# dog's feet on the ground has to be set again each time.
	var texture: Texture2D = _sprite.sprite_frames.get_frame_texture(name, 0)
	if texture != null:
		var frame: Vector2 = texture.get_size()
		_sprite.offset = Vector2(-frame.x * 0.5, -frame.y)
	_sprite.play()


# --- Applying a pose -----------------------------------------------------

func _apply_pose_3d(pose: PetPose) -> void:
	var unit: float = _pack.target_height
	_pivot.position = Vector3(pose.offset.x * unit, pose.offset.y * unit, 0.0)
	_pivot.scale = Vector3(pose.scale.x, pose.scale.y, pose.scale.x)
	# Only yaw turns a 3D dog. pose.facing is a sprite instruction - mirror
	# yourself - and a model cannot mirror, it can only turn, which at 180
	# degrees means showing the camera its backside.
	_pivot.rotation_degrees = Vector3(
		pose.pitch_degrees,
		pose.yaw_degrees,
		pose.roll_degrees
	)
	# Tinting the whole rendered viewport is the cheapest way to take the
	# life out of a sad dog without touching its materials.
	_viewport_box.modulate = pose.tint


func _apply_pose_2d(pose: PetPose) -> void:
	_play_sprite_animation(_state_art_name())
	var ground: Vector2 = _ground_point()
	_sprite.position = ground + Vector2(
		pose.offset.x * _body_height_px,
		-pose.offset.y * _body_height_px
	)
	# A sprite cannot really turn, so a yaw is shown as a horizontal squeeze,
	# which reads as the same thing at this size.
	#
	# Only when the pack has no art of its own for this state, though. A walk
	# strip is already drawn side on, so squeezing it as well just makes the
	# dog look thin.
	var squeeze: float = 1.0
	if not _pack.has_art_for(String(animator.state)):
		squeeze = lerpf(1.0, absf(cos(deg_to_rad(pose.yaw_degrees))), 0.6)
	var face: float = pose.facing * (1.0 if _pack.faces_right else -1.0)
	_sprite.scale = Vector2(
		_sprite_scale * pose.scale.x * squeeze * face,
		_sprite_scale * pose.scale.y
	)
	_sprite.rotation_degrees = pose.roll_degrees + pose.pitch_degrees * 0.3
	_sprite.modulate = pose.tint


func _apply_shadow(pose: PetPose) -> void:
	var ground: Vector2 = _ground_point()
	var lift: float = clampf(pose.offset.y / 0.25, 0.0, 1.0)
	# Higher dog, smaller and fainter shadow.
	var scale: float = (1.0 - 0.35 * lift) * pose.scale.x
	var width: float = SHADOW_WIDTH * scale * (_body_height_px / 140.0)
	var height: float = SHADOW_HEIGHT * scale * (_body_height_px / 140.0)
	_shadow.size = Vector2(width, height)
	_shadow.position = ground + Vector2(
		pose.offset.x * _body_height_px - width * 0.5,
		-height * 0.5
	)
	_shadow.modulate.a = 0.45 - 0.2 * lift


# --- Where the dog stands ------------------------------------------------

## Move the dog's spot on screen, as a fraction of this view. Scenes use
## this to put the dog by the bowl, on the path, and so on.
func set_pet_spot(spot: Vector2, animate: bool = true) -> void:
	if spot.is_equal_approx(_spot):
		return
	if not animate:
		_spot = spot
		_layout()
		return
	var tween: Tween = create_tween()
	tween.tween_method(_set_spot_now, _spot, spot, SPOT_TWEEN_SECONDS)
	tween.set_trans(Tween.TRANS_SINE)


func _set_spot_now(spot: Vector2) -> void:
	_spot = spot
	_layout()


func _ground_point() -> Vector2:
	return Vector2(size.x * _spot.x, size.y * _spot.y)


# Put everything where it belongs for the current size and spot.
func _layout() -> void:
	if _pack == null:
		return
	if _pack.kind == PetPack.KIND_MODEL3D:
		_layout_3d()
	_zzz.position = _ground_point() + Vector2(_body_height_px * 0.3, -_body_height_px)


# The 3D dog always stands at the world origin, so rather than moving it
# about in the world, the whole viewport is nudged until the point where
# its feet land falls on the spot we want.
func _layout_3d() -> void:
	if _camera == null or _viewport == null:
		return
	_viewport_box.position = Vector2.ZERO
	var feet: Vector2 = _camera.unproject_position(Vector3.ZERO)
	_viewport_box.position = _ground_point() - feet
	# One body height in pixels, measured off the camera, so the shadow and
	# the sleep z's can be sized the same way for both kinds of pet.
	var head: Vector2 = _camera.unproject_position(Vector3(0.0, _pack.target_height, 0.0))
	_body_height_px = maxf(absf(feet.y - head.y), 1.0)


func _setup_camera_and_lights() -> void:
	# A slight three-quarter overhead angle, so the dog is seen a little
	# from above rather than straight on.
	_camera.position = Vector3(0.0, 0.85, 2.2)
	_camera.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	_camera.fov = 40.0
	_key_light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	_key_light.light_energy = 1.1
	_fill_light.rotation_degrees = Vector3(-15.0, 145.0, 0.0)


# --- The sleep z's --------------------------------------------------------

func _build_zzz() -> void:
	for index in 3:
		var label := Label.new()
		label.text = "z"
		label.add_theme_font_size_override("font_size", 14 + index * 4)
		label.modulate = Color(1, 1, 1, 0.0)
		_zzz.add_child(label)
		_zzz_labels.append(label)


func _update_zzz(_delta: float) -> void:
	var sleeping: bool = animator.state == PetMotion.SLEEP
	_zzz.visible = sleeping
	if not sleeping:
		return
	for index in _zzz_labels.size():
		var label: Label = _zzz_labels[index]
		# Each z drifts up and fades, a beat behind the one before it.
		var phase: float = fmod(animator.state_time / 2.4 + index * 0.33, 1.0)
		label.position = Vector2(phase * 18.0, -phase * 46.0)
		label.modulate.a = sin(phase * PI) * 0.8


# A soft dark ellipse, drawn once into a texture. Fading it out towards the
# edge is what makes it read as a shadow rather than a black oval.
static func _make_blob_texture(width: int, height: int) -> ImageTexture:
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var half := Vector2(width * 0.5, height * 0.5)
	for y in height:
		for x in width:
			var dx: float = (x + 0.5 - half.x) / half.x
			var dy: float = (y + 0.5 - half.y) / half.y
			var distance: float = sqrt(dx * dx + dy * dy)
			var alpha: float = clampf(1.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha * alpha))
	return ImageTexture.create_from_image(image)
