class_name BuildingPainter
extends RefCounted
## Paints original building sprites at footprint size (tiles * 64 px), seen
## from a top-down 3/4 angle: walls, sloped roofs, doors, details per type
## and a team-coloured banner so ownership reads instantly.

const DARK: Color = Color(0.14, 0.11, 0.09)
const STONE: Color = Color(0.62, 0.6, 0.56)
const PLANK: Color = Color(0.58, 0.42, 0.26)
const ROOF: Color = Color(0.62, 0.27, 0.2)
const THATCH: Color = Color(0.78, 0.64, 0.34)


static func paint(type_id: String, size: Vector2i, team: Color) -> Image:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var w: float = size.x
	var h: float = size.y
	match type_id:
		"farm":
			_farm(img, w, h, team)
		"town_center":
			_hall(img, w, h, STONE, ROOF, team, true)
			_tower(img, Vector2(w * 0.5, h * 0.36), 16.0, 34.0, STONE.lightened(0.1), ROOF)
			_banner(img, Vector2(w * 0.5, h * 0.06), team, 16.0)
		"house":
			_hall(img, w, h, PLANK, THATCH, team, false)
			_window(img, Vector2(w * 0.3, h * 0.66))
		"lumber_camp":
			_shed(img, w, h, PLANK, THATCH)
			for i: int in 3:
				Raster.blob(img, Vector2(w * 0.25 + i * 10, h * 0.82), Vector2(9, 3.5), Color(0.5, 0.33, 0.18), DARK, 1.0)
				Raster.circle(img, Vector2(w * 0.25 + i * 10 + 9, h * 0.82), 3.0, Color(0.8, 0.65, 0.42))
			_banner(img, Vector2(w * 0.82, h * 0.15), team, 10.0)
		"mining_camp":
			_shed(img, w, h, PLANK, Color(0.45, 0.42, 0.4))
			Raster.framed_rect(img, Rect2(w * 0.55, h * 0.7, 20, 10), Color(0.4, 0.3, 0.2), DARK)
			Raster.circle(img, Vector2(w * 0.6, h * 0.7), 3.5, Color(0.9, 0.78, 0.25))
			Raster.circle(img, Vector2(w * 0.7, h * 0.69), 3.5, Color(0.6, 0.6, 0.6))
			_banner(img, Vector2(w * 0.18, h * 0.15), team, 10.0)
		"barracks":
			_hall(img, w, h, PLANK.darkened(0.1), ROOF.darkened(0.1), team, true)
			for i: int in 4:
				Raster.line(img, Vector2(w * 0.12 + i * 6, h * 0.92), Vector2(w * 0.12 + i * 6 + 3, h * 0.62), 1.5, Color(0.75, 0.75, 0.8))
		"archery_range":
			_hall(img, w, h, PLANK, Color(0.4, 0.5, 0.3), team, true)
			for r: float in [9.0, 6.0, 3.0]:
				Raster.circle(img, Vector2(w * 0.82, h * 0.78), r, Color(0.9, 0.85, 0.7) if int(r) % 2 == 1 else Color(0.8, 0.2, 0.15))
		"stable":
			_hall(img, w, h, PLANK.lightened(0.05), THATCH.darkened(0.1), team, true)
			Raster.blob(img, Vector2(w * 0.8, h * 0.82), Vector2(10, 6), Color(0.85, 0.75, 0.35), DARK, 1.0)
		"siege_workshop":
			_shed(img, w, h, PLANK.darkened(0.15), Color(0.42, 0.4, 0.38))
			Raster.blob(img, Vector2(w * 0.75, h * 0.78), Vector2(10, 10), PLANK.darkened(0.3), DARK, 1.2)
			Raster.circle(img, Vector2(w * 0.75, h * 0.78), 3.0, DARK)
			_banner(img, Vector2(w * 0.15, h * 0.12), team, 12.0)
		"blacksmith":
			_hall(img, w, h, STONE.darkened(0.1), ROOF.darkened(0.25), team, true)
			Raster.framed_rect(img, Rect2(w * 0.7, h * 0.08, 12, 26), STONE.darkened(0.3), DARK)
			Raster.circle(img, Vector2(w * 0.7 + 6, h * 0.06), 5.0, Color(0.4, 0.4, 0.42, 0.7))
			Raster.framed_rect(img, Rect2(w * 0.15, h * 0.8, 16, 7), Color(0.3, 0.3, 0.33), DARK)
		"university":
			_hall(img, w, h, Color(0.82, 0.78, 0.68), Color(0.35, 0.42, 0.62), team, true)
			Raster.blob(img, Vector2(w * 0.5, h * 0.32), Vector2(20, 14), Color(0.42, 0.52, 0.72), DARK, 1.5)
			for i: int in 4:
				Raster.rect(img, Rect2(w * 0.25 + i * 24, h * 0.62, 5, 30), Color(0.92, 0.9, 0.84))
		"monastery":
			_hall(img, w, h, Color(0.78, 0.74, 0.66), ROOF, team, true)
			_tower(img, Vector2(w * 0.78, h * 0.32), 12.0, 40.0, Color(0.8, 0.76, 0.68), ROOF)
			Raster.circle(img, Vector2(w * 0.78, h * 0.28), 4.0, Color(0.85, 0.7, 0.25))
		"watch_tower":
			_tower(img, Vector2(w * 0.5, h * 0.55), 18.0, h * 0.8, STONE, ROOF)
			for i: int in 4:
				Raster.rect(img, Rect2(w * 0.5 - 18 + i * 10, h * 0.12, 6, 6), STONE.lightened(0.15))
			_banner(img, Vector2(w * 0.5, h * 0.02), team, 8.0)
		_:
			_hall(img, w, h, PLANK, ROOF, team, true)
	return img


static func _hall(img: Image, w: float, h: float, wall: Color, roof: Color, team: Color, banner: bool) -> void:
	var inset: float = 5.0
	Raster.rect(img, Rect2(inset + 4, h * 0.45 + 6, w - inset * 2 - 4, h * 0.55 - inset - 2), Color(0, 0, 0, 0.28))
	Raster.framed_rect(img, Rect2(inset, h * 0.42, w - inset * 2, h * 0.55 - inset), wall, DARK, 2)
	# Wall texture: courses of stone/planks.
	for y: int in range(int(h * 0.48), int(h - inset), 7):
		Raster.rect(img, Rect2(inset + 1, y, w - inset * 2 - 2, 1), wall.darkened(0.18))
	# Sloped roof (trapezoid seen from above-front).
	Raster.framed_polygon(img, PackedVector2Array([Vector2(inset - 3, h * 0.46), Vector2(w - inset + 3, h * 0.46), Vector2(w - inset - w * 0.12, h * 0.1), Vector2(inset + w * 0.12, h * 0.1)]), roof, DARK)
	Raster.rect(img, Rect2(inset + w * 0.12, h * 0.1, w - inset * 2 - w * 0.24, 2), roof.lightened(0.25))
	for x: int in range(int(inset + 6), int(w - inset - 4), 9):
		Raster.line(img, Vector2(x, h * 0.44), Vector2(x + (w * 0.5 - x) * 0.25, h * 0.13), 1.0, roof.darkened(0.2))
	# Door
	Raster.framed_rect(img, Rect2(w * 0.5 - 7, h - inset - 18, 14, 16), PLANK.darkened(0.45), DARK)
	if banner:
		_banner(img, Vector2(w - inset - 10, h * 0.48), team, 12.0)


static func _shed(img: Image, w: float, h: float, wall: Color, roof: Color) -> void:
	Raster.framed_rect(img, Rect2(6, h * 0.45, w * 0.6, h * 0.42), wall, DARK, 2)
	Raster.framed_polygon(img, PackedVector2Array([Vector2(3, h * 0.5), Vector2(w * 0.6 + 9, h * 0.5), Vector2(w * 0.6, h * 0.15), Vector2(8, h * 0.15)]), roof, DARK)
	Raster.rect(img, Rect2(10, h * 0.62, w * 0.6 - 8, h * 0.22), wall.darkened(0.45))


static func _tower(img: Image, base_center: Vector2, half_w: float, height: float, wall: Color, roof: Color) -> void:
	var top: float = base_center.y - height * 0.5
	Raster.framed_rect(img, Rect2(base_center.x - half_w, top, half_w * 2, height * 0.7), wall, DARK, 2)
	Raster.framed_polygon(img, PackedVector2Array([Vector2(base_center.x - half_w - 3, top + 2), Vector2(base_center.x + half_w + 3, top + 2), Vector2(base_center.x, top - half_w * 1.1)]), roof, DARK)
	Raster.rect(img, Rect2(base_center.x - 2, top + height * 0.25, 4, 7), DARK)


static func _window(img: Image, at: Vector2) -> void:
	Raster.framed_rect(img, Rect2(at, Vector2(8, 7)), Color(0.95, 0.85, 0.5), DARK)


static func _banner(img: Image, top: Vector2, team: Color, length: float) -> void:
	Raster.line(img, top, top + Vector2(0, length + 8), 1.5, DARK)
	Raster.framed_polygon(img, PackedVector2Array([top + Vector2(1, 1), top + Vector2(1 + length * 0.9, 3), top + Vector2(1, length * 0.55)]), team, DARK)


static func _farm(img: Image, w: float, h: float, team: Color) -> void:
	Raster.framed_rect(img, Rect2(4, 4, w - 8, h - 8), Color(0.45, 0.32, 0.18), team.darkened(0.2), 2)
	for row: int in range(10, int(h) - 8, 10):
		Raster.rect(img, Rect2(8, row, w - 16, 4), Color(0.36, 0.25, 0.13))
		for x: int in range(10, int(w) - 10, 6):
			Raster.circle(img, Vector2(x, row - 2), 2.0, Color(0.55, 0.72, 0.25).lerp(Color(0.85, 0.75, 0.3), Raster.noise(x, row, 3) * 0.5 + 0.5))
