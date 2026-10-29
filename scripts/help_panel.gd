extends Control
## Step-by-step instructions for changing the art, inside the app.
##
## The same ground is covered by assets/README.txt, but that is a text file
## next to the exe, which is exactly where somebody who needs the help will
## not think to look. This is two clicks from the menu bar, and the folder
## it keeps talking about is one button away at the bottom.

@onready var _frame: PanelContainer = %Frame
@onready var _done_button: Button = %DoneButton
@onready var _text: RichTextLabel = %Text
@onready var _open_button: Button = %OpenButton
@onready var _reload_button: Button = %ReloadButton


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.18)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	_frame.add_theme_stylebox_override("panel", style)

	_done_button.pressed.connect(hide)
	_open_button.pressed.connect(_open_folder)
	_reload_button.pressed.connect(func() -> void:
		AssetLibrary.reload()
		Notifier.banner_requested.emit("Assets reloaded.", "")
	)


func open() -> void:
	_text.text = _instructions()
	show()
	_done_button.grab_focus()


func _open_folder() -> void:
	Paths.open_in_file_manager(Paths.assets_dir)


# Written out here rather than loaded from a file so it cannot go missing,
# and so the real folder path can be dropped into it.
func _instructions() -> String:
	return """[b]Everything DogPet draws comes from one folder.[/b]

[color=#9fd8a0]%s[/color]

Nothing is baked into the app, so you can change the dog, the rooms and the icons without rebuilding anything. Use [b]Reload assets[/b] below after a change, or just restart.

[font_size=17]Change the dog for another 3D model[/font_size]

[b]1.[/b] Make a new folder in [code]assets/pets/[/code] - call it anything, for example [code]beagle_3d[/code].
[b]2.[/b] Put your model in it as [code]model.glb[/code]. A [code].gltf[/code] works too.
[b]3.[/b] Copy [code]pet.json[/code] from [code]assets/pets/pug_3d/[/code] into your new folder, and change [code]"id"[/code], [code]"name"[/code] and [code]"credit"[/code].
[b]4.[/b] Reload. Your dog appears in the picker in [b]Settings - Pet[/b].

Size does not matter. DogPet measures every model and scales it so all pets stand the same height with their feet on the floor.

If the dog faces the wrong way, change [code]"rotation_y_degrees"[/code] in its [code]pet.json[/code] - try 90, 180 or -90 until it looks at you. The pug that ships with DogPet is modelled 29 degrees off, which is why its file says -29.

[font_size=17]Change the dog for pixel art[/font_size]

[b]1.[/b] Make a new folder in [code]assets/pets/[/code], for example [code]corgi_pixel[/code].
[b]2.[/b] Add one PNG per animation. Each PNG is a single row of equal-width frames.
[b]3.[/b] Copy [code]pet.json[/code] from [code]assets/pets/pug_pixel/[/code] and list each file with how many frames it has and how fast it runs.
[b]4.[/b] Reload.

[code]idle[/code] is the only one you must provide. [code]walk[/code], [code]happy[/code], [code]sad[/code], [code]eat[/code], [code]play[/code], [code]restless[/code] and [code]sleep[/code] are optional - anything missing falls back to [code]idle[/code] plus DogPet's own hop, bob and tilt.

Pixel art is only ever scaled by whole numbers, and one scale is chosen for the whole pack from its tallest frame, so the dog never changes size between standing still and walking.

[font_size=17]Change a room[/font_size]

Each room is a folder under [code]assets/scenes/[/code] with a [code]scene.json[/code] in it. Edit that file to change the room.

The background can be one of three things:

[b]"image"[/b] - one picture, with [code]"file": "my_room.png"[/code]. It is cropped to fit rather than stretched.
[b]"tiled"[/b] - repeating wall and floor tiles, as the living room and kitchen use.
[b]"generated"[/b] - drawn by DogPet from colours you choose, as the yard and park use.

Props are the things standing about the room. [code]"x"[/code] and [code]"y"[/code] run from 0 to 1 across and down the window, and [code]"y"[/code] is where the [i]bottom[/i] of the prop sits, so things rest on the floor instead of floating. [code]"scale"[/code] is a whole number.

[font_size=17]Add a second room, without losing the first[/font_size]

[b]1.[/b] Copy an existing room folder, for example copy [code]assets/scenes/eat/[/code] to [code]assets/scenes/kitchen_night/[/code].
[b]2.[/b] Open the new [code]scene.json[/code] and change [code]"name"[/code] to something you will recognise.
[b]3.[/b] Leave [code]"role"[/code] alone. That is what says which slot the room fills - [code]home[/code], [code]eat[/code], [code]play[/code] or [code]walk[/code].
[b]4.[/b] Reload, then pick between them in [b]Settings - Rooms[/b].

Any number of rooms can offer themselves for the same slot. The folder name does not matter; the [code]"role"[/code] inside decides.

One thing to know: the [b]walk[/b] room is the only one that moves. A replacement for that slot wants [code]"scroll": true[/code] and a [code]"path"[/code] colour in its background, or it will stand still.

[font_size=17]Give a pet or a room to somebody[/font_size]

[b]Settings - Assets - Export[/b] writes a pet or a room out as a [code].zip[/code], with its credit tucked inside. [b]Import pack[/b] reads one back.

Importing never replaces anything without asking first, and keeps a copy of whatever it replaced in [code]assets/_backup/[/code].

[font_size=17]If something goes wrong[/font_size]

DogPet will not refuse to start. A pet or room it cannot read is skipped, and it says why in [code]saves/dogpet.log[/code]. A room missing its pictures still appears, drawn plainly. If the whole assets folder goes missing, DogPet falls back to a copy of the pug and the four rooms kept inside the app, and tells you so.

So if a change does not show up, the log is the first place to look.

[font_size=17]Keeping credits[/font_size]

Some of the art DogPet ships with is licensed on condition that its credit stays visible - the default pug among it. Every pack's [code]"credit"[/code] line is shown in [b]Settings - About[/b]. Please leave those lines in place, and add your own when you make a pack.
""" % Paths.assets_dir
