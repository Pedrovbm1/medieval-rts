extends Node
## Dev tool: writes the baked atlas and a composed preview scene to PNG so the
## procedural art can be reviewed without a device. Usage:
##   godot --headless --path game tests/tools/dump_art.tscn -- out=<dir>


func _ready() -> void:
	var out: String = "user://"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.substr(4)
	PlaceholderArt.build()
	var atlas: Image = PlaceholderArt.texture().get_image()
	atlas.save_png(out.path_join("atlas.png"))
	_preview().save_png(out.path_join("preview.png"))
	print("[REALM] art dumped to ", out)
	get_tree().quit()


func _preview() -> Image:
	var tile: int = 64
	var img: Image = Image.create(tile * 14, tile * 9, false, Image.FORMAT_RGBA8)
	var terrain: Dictionary = DataLoader.get_table("terrain").get("types", {})
	var names: Array = ["grass", "grass", "grass", "forest", "water"]
	for y: int in 9:
		for x: int in 14:
			var name: String = "grass"
			if x >= 12:
				name = "water"
			elif y <= 1 and x >= 7:
				name = "forest"
			elif x == 11:
				name = "shore"
			var entry: Dictionary = terrain.get("grass" if name == "shore" else name, {})
			var v: int = absi(x * 73856093 ^ y * 19349663) % PlaceholderTileset.VARIANTS
			var t: Image = NaturePainter.tile(name, Color.html(String(entry.get("color", "#55aa55"))), v, tile)
			img.blit_rect(t, Rect2i(0, 0, tile, tile), Vector2i(x * tile, y * tile))
	var atlas: Image = PlaceholderArt.texture().get_image()
	_put(img, atlas, PlaceholderArt.building_region("town_center", 0), Vector2(64, 192))
	_put(img, atlas, PlaceholderArt.building_region("barracks", 1), Vector2(384, 320))
	_put(img, atlas, PlaceholderArt.building_region("house", 0), Vector2(320, 160))
	_put(img, atlas, PlaceholderArt.building_region("farm", 0), Vector2(64, 448))
	_put(img, atlas, PlaceholderArt.building_region("watch_tower", 1), Vector2(640, 384))
	_put(img, atlas, PlaceholderArt.resource_region("gold_mine"), Vector2(576, 160))
	_put(img, atlas, PlaceholderArt.resource_region("berry_bush"), Vector2(256, 64))
	var units: Array = DataLoader.get_table("units").keys()
	var x0: float = 40.0
	for i: int in units.size():
		var poses: Array = ["idle", "walk0", "attack0", "dead"]
		var r: Rect2 = PlaceholderArt.unit_frame(String(units[i]), i % 2, poses[i % poses.size()] if i > 11 else "idle")
		_put(img, atlas, r, Vector2(x0 + (i % 14) * 56.0, 20.0 + (i / 14) * 56.0 + 0.0))
	return img


func _put(dst: Image, atlas: Image, region: Rect2, at: Vector2) -> void:
	if region.size == Vector2.ZERO:
		return
	dst.blend_rect(atlas, Rect2i(region), Vector2i(at))
