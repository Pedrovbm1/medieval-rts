class_name PlaceholderArt
extends RefCounted
## Bakes every placeholder sprite (units, buildings, resource nodes) into ONE
## atlas texture at startup, so the renderer can batch the whole map into a few
## draw calls even with 150+ units. Real art in F9 replaces this class, not its
## callers (they only ask for texture() + a region).
##
## A white 4x4 block at the atlas origin is used for tinted bars (HP, progress).

const UNIT_CELL: int = 48
const ATLAS_WIDTH: int = 2048
const WHITE_RECT: Rect2 = Rect2(1, 1, 2, 2)

static var _texture: Texture2D = null
static var _regions: Dictionary = {}


## Variant key for a player (0, 1, ...) or "gaia" for neutral things.
static func variant_key(owner_id: int) -> String:
	return "gaia" if owner_id < 0 else "p%d" % owner_id


static func texture() -> Texture2D:
	if _texture == null:
		build()
	return _texture


static func unit_region(type_id: String, owner_id: int) -> Rect2:
	return region("unit:%s@%s" % [type_id, variant_key(owner_id)])


static func building_region(type_id: String, owner_id: int) -> Rect2:
	return region("bldg:%s@%s" % [type_id, variant_key(owner_id)])


static func resource_region(type_id: String) -> Rect2:
	return region("res:" + type_id)


static func region(key: String) -> Rect2:
	if _texture == null:
		build()
	return _regions.get(key, Rect2())


## (Re)builds the atlas from the data tables. Safe to call again after data reloads.
static func build() -> void:
	var images: Dictionary = {}
	var colors: Array = DataLoader.rule("players", "colors", ["#3a6fd8", "#d84a3a"])
	var tile: int = int(DataLoader.get_table("terrain").get("tile_size", 64))

	var units: Dictionary = DataLoader.get_table("units")
	for type_id: String in units.keys():
		var entry: Dictionary = units[type_id]
		var animal: Dictionary = entry.get("animal", {})
		var glyph: String = String(entry.get("placeholder_glyph", "?"))
		var radius: float = float(entry.get("radius_px", 12))
		if not animal.is_empty():
			images["unit:%s@gaia" % type_id] = _bake_unit(radius, Color.html(String(animal.get("color", "#cccccc"))), glyph)
			for i: int in colors.size():
				images["unit:%s@p%d" % [type_id, i]] = _bake_unit(radius, Color.html(String(animal.get("color", "#cccccc"))), glyph, Color.html(String(colors[i])))
		else:
			for i: int in colors.size():
				images["unit:%s@p%d" % [type_id, i]] = _bake_unit(radius, Color.html(String(colors[i])), glyph)

	var buildings: Dictionary = DataLoader.get_table("buildings")
	for type_id: String in buildings.keys():
		var b: Dictionary = buildings[type_id]
		var fp: Array = b.get("footprint", [2, 2])
		var size: Vector2i = Vector2i(int(fp[0]) * tile, int(fp[1]) * tile)
		for i: int in colors.size():
			images["bldg:%s@p%d" % [type_id, i]] = _bake_building(size, b, Color.html(String(colors[i])))

	var resources: Dictionary = DataLoader.get_table("resources")
	for type_id: String in resources.keys():
		var r: Dictionary = resources[type_id]
		if not r.has("color"):
			continue
		var rfp: Array = r.get("footprint", [1, 1])
		images["res:" + type_id] = _bake_resource(Vector2i(int(rfp[0]) * tile, int(rfp[1]) * tile), r)

	_pack(images)


## Shelf packing: sort by height, fill rows left to right.
static func _pack(images: Dictionary) -> void:
	var keys: Array = images.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return (images[a] as Image).get_height() > (images[b] as Image).get_height())
	var placements: Dictionary = {}
	var x: int = 8
	var y: int = 0
	var row_h: int = 8
	for key: String in keys:
		var img: Image = images[key]
		if x + img.get_width() > ATLAS_WIDTH:
			x = 0
			y += row_h
			row_h = 0
		placements[key] = Vector2i(x, y)
		x += img.get_width()
		row_h = maxi(row_h, img.get_height())
	var height: int = int(nearest_po2(maxi(16, y + row_h)))
	var atlas: Image = Image.create(ATLAS_WIDTH, height, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	atlas.fill_rect(Rect2i(0, 0, 4, 4), Color.WHITE)
	_regions.clear()
	for key: String in keys:
		var img: Image = images[key]
		var at: Vector2i = placements[key]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		_regions[key] = Rect2(at, img.get_size())
	_texture = ImageTexture.create_from_image(atlas)


static func _bake_unit(radius: float, base: Color, glyph: String, ring: Color = Color(0, 0, 0, 0)) -> Image:
	var image: Image = Image.create(UNIT_CELL, UNIT_CELL, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center: Vector2 = Vector2(UNIT_CELL * 0.5, UNIT_CELL * 0.5)
	var outline: Color = base.darkened(0.45) if ring.a == 0.0 else ring
	var outline_w: float = 1.5 if ring.a == 0.0 else 3.0
	var shadow: Color = Color(0, 0, 0, 0.28)
	for y: int in UNIT_CELL:
		for x: int in UNIT_CELL:
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			var d: float = p.distance_to(center)
			if d <= radius - outline_w:
				image.set_pixel(x, y, base)
			elif d <= radius:
				image.set_pixel(x, y, outline)
			elif p.distance_to(center + Vector2(0, radius * 0.35)) <= radius * 0.95:
				image.set_pixel(x, y, shadow)
	var scale: int = 2 if radius >= 12.0 else 1
	var glyph_color: Color = Color.WHITE if base.get_luminance() < 0.6 else Color(0.15, 0.12, 0.1)
	PixelFont.draw_text(image, Vector2i(int(center.x) - PixelFont.text_width(glyph, scale) / 2, int(center.y) - PixelFont.H * scale / 2), glyph, scale, glyph_color)
	return image


static func _bake_building(size: Vector2i, b: Dictionary, owner_color: Color) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var base: Color = Color.html(String(b.get("color", "#8a6d4b")))
	var inset: int = 4
	image.fill(Color(0, 0, 0, 0))
	if bool(b.get("walkable", false)):
		# Field: furrows instead of walls.
		image.fill_rect(Rect2i(inset, inset, size.x - inset * 2, size.y - inset * 2), base.darkened(0.15))
		for row: int in range(inset + 6, size.y - inset, 12):
			image.fill_rect(Rect2i(inset + 4, row, size.x - inset * 2 - 8, 4), base.lightened(0.15))
		_frame(image, Rect2i(inset, inset, size.x - inset * 2, size.y - inset * 2), owner_color, 3)
	else:
		image.fill_rect(Rect2i(inset + 4, inset + 8, size.x - inset * 2 - 4, size.y - inset * 2 - 4), Color(0, 0, 0, 0.3))
		image.fill_rect(Rect2i(inset, inset, size.x - inset * 2 - 4, size.y - inset * 2 - 6), base)
		_frame(image, Rect2i(inset, inset, size.x - inset * 2 - 4, size.y - inset * 2 - 6), base.darkened(0.4), 3)
		image.fill_rect(Rect2i(inset + 3, inset + 3, size.x - inset * 2 - 10, 10), owner_color)
	var glyph: String = String(b.get("placeholder_glyph", "?"))
	var scale: int = 4 if size.x >= 192 else 3
	PixelFont.draw_text(image, Vector2i(size.x / 2 - PixelFont.text_width(glyph, scale) / 2 - 2, size.y / 2 - PixelFont.H * scale / 2 + 2), glyph, scale, Color(1, 1, 1, 0.92))
	return image


static func _bake_resource(size: Vector2i, r: Dictionary) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var base: Color = Color.html(String(r.get("color", "#cccccc")))
	var center: Vector2 = Vector2(size) * 0.5
	var radius: float = minf(size.x, size.y) * 0.42
	for y: int in size.y:
		for x: int in size.x:
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			# Lumpy blob: radius wobbles with angle so mines/bushes read as natural shapes.
			var ang: float = (p - center).angle()
			var wobble: float = 1.0 + 0.12 * sin(ang * 5.0) + 0.06 * sin(ang * 11.0 + 1.3)
			var d: float = p.distance_to(center) / wobble
			if d <= radius - 2.0:
				var shade: float = 0.12 * sin(x * 0.7) * sin(y * 0.6)
				image.set_pixel(x, y, base.lightened(maxf(0.0, shade)).darkened(maxf(0.0, -shade)))
			elif d <= radius:
				image.set_pixel(x, y, base.darkened(0.4))
	var glyph: String = String(r.get("placeholder_glyph", ""))
	var scale: int = 3 if size.x >= 128 else 2
	PixelFont.draw_text(image, Vector2i(size.x / 2 - PixelFont.text_width(glyph, scale) / 2, size.y / 2 - PixelFont.H * scale / 2), glyph, scale, Color(0.1, 0.08, 0.06, 0.85))
	return image


static func _frame(image: Image, rect: Rect2i, color: Color, width: int) -> void:
	image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, width)), color)
	image.fill_rect(Rect2i(rect.position + Vector2i(0, rect.size.y - width), Vector2i(rect.size.x, width)), color)
	image.fill_rect(Rect2i(rect.position, Vector2i(width, rect.size.y)), color)
	image.fill_rect(Rect2i(rect.position + Vector2i(rect.size.x - width, 0), Vector2i(width, rect.size.y)), color)
