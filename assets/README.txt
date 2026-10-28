DOGPET ASSETS FOLDER
====================

Everything the app draws comes from this folder. You can change the dog,
the rooms, and the icons without rebuilding the app. After a change, open
Settings > Assets > Reload, or restart the app.


FOLDERS
-------

pets/<any_name>/      One folder per pet. Needs a pet.json file.
scenes/home/          The main room the dog lives in.
scenes/eat/           Shown while feeding.
scenes/play/          Shown while playing.
scenes/walk/          Shown while walking.
ui/                   Tray icons, need icons, button icons (ui.json).
licenses/             License files for the art packs. Keep these.
CREDITS.txt           Credits for all included art. Keep this.


ADD A 3D PET
------------

1. Make a new folder in pets/, for example pets/beagle_3d/
2. Put the model in it as model.glb (or .gltf).
3. Copy pet.json from pets/pug_3d/ and change "id", "name" and "credit".
4. If the dog faces the wrong way, change "rotation_y_degrees"
   (try 90, 180, -90).
5. Size does not matter. The app scales every model to the same height.

If the .glb has its own animations, list them under "animations", for
example: "animations": { "walk": "Walk", "idle": "Idle" }
Any state not listed uses the app's built-in hop, bob and tilt motions.


ADD A 2D PET
------------

1. Make a new folder in pets/, for example pets/corgi_pixel/
2. Add one PNG per animation. Each PNG is a single row of equal-width frames.
3. Copy pet.json from pets/pug_pixel/ and list each file with its
   frame count and speed (fps).
4. "idle" is required. Optional states: happy, sad, eat, play, walk,
   restless, sleep. Missing states fall back to idle.


CHANGE A ROOM
-------------

Edit scenes/<role>/scene.json.

background "type" can be:
  "image"      one picture:  "file": "my_kitchen.png"
  "tiled"      repeating wall and floor tiles
  "generated"  drawn by the app (style "yard" or "park")

Props: "x" and "y" are 0 to 1 across and down the window. "y" is where
the bottom of the prop sits. "scale" is a whole number for pixel art.


SHARING
-------

Settings > Assets > Export pack makes a .zip of one pet or one room.
Settings > Assets > Import pack adds a .zip someone gave you.

Keep the credit line in pet.json when you share a pet. CREDITS.txt lists
the credits for the art that ships with DogPet.
