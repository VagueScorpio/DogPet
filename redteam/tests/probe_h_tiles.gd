extends SceneTree
## RT-05 probe: SceneView._draw_tiled_background steps by the tile's own size,
## so a 1x1 pixel wall.png used to ask for one draw call per screen pixel,
## every frame. ScenePack now raises the scale; SceneView has a ceiling for a
## tile it could not measure.
##
## Builds real 1x1 and 4x4 PNGs, loads them through the real ScenePack, and
## counts what the real drawing loop would place.

const Pack := preload("res://scripts/scene_pack.gd")
## Mirrors SceneMAX_TILES_PER_AXIS. Not preloaded from it: scene_view.gd
## names the Log autoload, and a --script run is compiled before the autoloads
## have names, so it cannot be loaded here at all.
const MAX_TILES_PER_AXIS := 256

func _init() -> void:
	var dir: String = OS.get_user_data_dir().path_join("rt_tiles")
	DirAccess.make_dir_recursive_absolute(dir)

	print("--- what the pack author writes, and what the loader does with it ---")
	for side in [1, 4, 32]:
		_write_png(dir.path_join("t%d.png" % side), side)
		for asked in [1, 4]:
			var pack = Pack.from_dictionary({
				"role": "home", "name": "T",
				"background": {
					"type": "tiled", "wall": "t%d.png" % side,
					"floor": "t%d.png" % side, "tile_scale": asked,
				},
			}, dir)
			print("  %2dx%-2d tile, tile_scale %d -> loader uses %d%s" % [
				side, side, asked, int(pack.background["tile_scale"]),
				"" if int(pack.background["tile_scale"]) == asked else "   (raised)",
			])

	print("")
	print("--- draw calls per frame, after the loader has had its say ---")
	for window in [Vector2(540, 760), Vector2(2560, 1440)]:
		for side in [1, 32]:
			var pack = Pack.from_dictionary({
				"role": "home", "name": "T",
				"background": {
					"type": "tiled", "wall": "t%d.png" % side,
					"floor": "t%d.png" % side, "tile_scale": 1,
				},
			}, dir)
			var scale: int = int(pack.background["tile_scale"])
			print("  %dx%d window, %dx%d tile: %d draw calls  (scale %d)" % [
				window.x, window.y, side, side,
				_count(window, Vector2(side, side) * scale, 0.38), scale,
			])

	print("")
	print("--- and the shipped rooms are untouched ---")
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	for room in ["home", "eat"]:
		var folder: String = project.path_join("assets/scenes/%s" % room)
		if not DirAccess.dir_exists_absolute(folder):
			continue
		var real = Pack.load_from_dir(folder)
		print("  %s: tile_scale %s, problems %s" % [
			room, real.background.get("tile_scale", "n/a"),
			real.problems if not real.problems.is_empty() else "none",
		])
	quit(0)

# Mirrors SceneView's two loops, including its _tile_step ceiling.
func _count(window: Vector2, tile: Vector2, floor_ratio: float) -> int:
	var floor_y: float = window.y * (1.0 - floor_ratio)
	var calls: int = 0
	for area in [Vector2(window.x, floor_y), Vector2(window.x, window.y - floor_y)]:
		var step: Vector2 = _tile_step(tile, area)
		var rows: int = int(ceil(area.y / step.y))
		var cols: int = int(ceil(area.x / step.x))
		calls += rows * cols
	return calls

func _tile_step(tile: Vector2, area: Vector2) -> Vector2:
	var grow: float = maxf(
		area.x / (tile.x * MAX_TILES_PER_AXIS),
		area.y / (tile.y * MAX_TILES_PER_AXIS)
	)
	return tile if grow <= 1.0 else tile * ceil(grow)

# A real, minimal PNG of one flat colour, so ScenePack can measure it.
func _write_png(path: String, side: int) -> void:
	var image: Image = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.4, 0.3))
	image.save_png(path)
