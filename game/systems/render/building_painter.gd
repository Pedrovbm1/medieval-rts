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
	var img: Image = Raster.begin(size, 1.0, 0.3)
	var w: float = size.x
	var h: float = size.y
	if type_id != "farm":
		# Trodden dirt under the building: it sits on the ground, not on top.
		Raster.ellipse(img, Vector2(w * 0.5, h * 0.8), Vector2(w * 0.5, h * 0.2), Color(0.42, 0.34, 0.22, 0.5))
	match type_id:
		"farm":
			_farm(img, w, h, team)
		"town_center":
			_hall(img, w, h, STONE, ROOF, team, true)
			_tower(img, Vector2(w * 0.5, h * 0.36), 16.0, 34.0, STONE.lightened(0.1), ROOF)
			_banner(img, Vector2(w * 0.5, h * 0.06), team, 16.0)
		"house":
			_hall(img, w, h, PLANK, THATCH, team, false)
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
		"market":
			_market(img, w, h, team)
		"watch_tower":
			_tower(img, Vector2(w * 0.5, h * 0.55), 18.0, h * 0.8, STONE, ROOF)
			for i: int in 4:
				Raster.rect(img, Rect2(w * 0.5 - 18 + i * 10, h * 0.12, 6, 6), STONE.lightened(0.15))
			_banner(img, Vector2(w * 0.5, h * 0.02), team, 8.0)
		_:
			_hall(img, w, h, PLANK, ROOF, team, true)
	return Raster.finish(img, size, Color(0.08, 0.06, 0.05, 0.6))


static func _hall(img: Image, w: float, h: float, wall: Color, roof: Color, team: Color, banner: bool) -> void:
	var inset: float = 5.0
	Raster.rect(img, Rect2(inset + 4, h * 0.45 + 6, w - inset * 2 - 4, h * 0.55 - inset - 2), Color(0, 0, 0, 0.28))
	var wall_rect: Rect2 = Rect2(inset, h * 0.42, w - inset * 2, h * 0.55 - inset)
	Raster.framed_rect(img, wall_rect, wall, DARK, 2)
	_wall_texture(img, wall_rect, wall)
	# Windows on wide walls
	if w >= 120.0:
		for wx: float in [w * 0.22, w * 0.78 - 10]:
			_window(img, Vector2(wx, h * 0.6))
	# Chimney behind the roof
	Raster.framed_rect(img, Rect2(w * 0.68, h * 0.04, 9, 18), STONE.darkened(0.15), DARK)
	Raster.circle(img, Vector2(w * 0.68 + 5, h * 0.03), 4.0, Color(0.78, 0.78, 0.8, 0.45))
	# Sloped roof (trapezoid seen from above-front) with shingle rows.
	var roof_pts: PackedVector2Array = PackedVector2Array([Vector2(inset - 3, h * 0.46), Vector2(w - inset + 3, h * 0.46), Vector2(w - inset - w * 0.12, h * 0.1), Vector2(inset + w * 0.12, h * 0.1)])
	Raster.framed_polygon(img, roof_pts, roof, DARK)
	_shingles(img, roof_pts, roof)
	Raster.rect(img, Rect2(inset + w * 0.12, h * 0.1, w - inset * 2 - w * 0.24, 2.5), roof.lightened(0.3))
	Raster.rect(img, Rect2(inset - 3, h * 0.46, w - inset * 2 + 6, 2.5), roof.darkened(0.45))
	# Door with a stone frame, planks and a handle
	var door: Rect2 = Rect2(w * 0.5 - 8, h - inset - 20, 16, 18)
	Raster.framed_rect(img, door.grow(1.5), STONE.darkened(0.25), DARK)
	Raster.rect(img, door, PLANK.darkened(0.45))
	for dx: float in [door.position.x + 5.0, door.position.x + 10.5]:
		Raster.rect(img, Rect2(dx, door.position.y, 1, door.size.y), PLANK.darkened(0.65))
	Raster.circle(img, door.position + Vector2(12.5, 10), 1.0, Color(0.85, 0.7, 0.3))
	if banner:
		_banner(img, Vector2(w - inset - 10, h * 0.48), team, 12.0)


## Stone walls get offset blocks with mortar; wooden walls get planks.
static func _wall_texture(img: Image, r: Rect2, wall: Color) -> void:
	var stone: bool = wall.s < 0.25
	var course: float = 7.0 if stone else 6.0
	var row: int = 0
	var y: float = r.position.y + course
	while y < r.end.y - 1:
		Raster.rect(img, Rect2(r.position.x + 1, y, r.size.x - 2, 1), wall.darkened(0.3))
		if stone:
			var x: float = r.position.x + (7.0 if row % 2 == 0 else 1.0)
			while x < r.end.x - 2:
				Raster.rect(img, Rect2(x, y - course + 1, 1, course - 1), wall.darkened(0.3))
				Raster.rect(img, Rect2(x + 1, y - course + 1, 5, 1), wall.lightened(0.12))
				x += 12.0
		else:
			for k: int in 3:
				var nx: float = r.position.x + 4 + absf(Raster.noise(row, k, 5)) * (r.size.x - 8)
				Raster.circle(img, Vector2(nx, y - course * 0.5), 0.8, wall.darkened(0.4))
		row += 1
		y += course


## Rows of overlapping shingles following the roof slope.
static func _shingles(img: Image, roof: PackedVector2Array, color: Color) -> void:
	var top: float = roof[2].y
	var bottom: float = roof[0].y
	var rows: int = maxi(3, int((bottom - top) / 6.0))
	for i: int in range(1, rows):
		var t: float = float(i) / rows
		var y: float = lerpf(top, bottom, t)
		var x0: float = lerpf(roof[3].x, roof[0].x, t)
		var x1: float = lerpf(roof[2].x, roof[1].x, t)
		Raster.line(img, Vector2(x0 + 1, y), Vector2(x1 - 1, y), 1.0, color.darkened(0.3))
		var x: float = x0 + (3.0 if i % 2 == 0 else 7.0)
		while x < x1 - 2:
			Raster.rect(img, Rect2(x, y - 5, 1, 5), color.darkened(0.22))
			x += 8.0


static func _shed(img: Image, w: float, h: float, wall: Color, roof: Color) -> void:
	var r: Rect2 = Rect2(6, h * 0.45, w * 0.6, h * 0.42)
	Raster.framed_rect(img, r, wall, DARK, 2)
	_wall_texture(img, r, wall)
	var roof_pts: PackedVector2Array = PackedVector2Array([Vector2(3, h * 0.5), Vector2(w * 0.6 + 9, h * 0.5), Vector2(w * 0.6, h * 0.15), Vector2(8, h * 0.15)])
	Raster.framed_polygon(img, roof_pts, roof, DARK)
	_shingles(img, roof_pts, roof)
	Raster.rect(img, Rect2(10, h * 0.62, w * 0.6 - 8, h * 0.22), wall.darkened(0.45))


static func _tower(img: Image, base_center: Vector2, half_w: float, height: float, wall: Color, roof: Color) -> void:
	var top: float = base_center.y - height * 0.5
	var body: Rect2 = Rect2(base_center.x - half_w, top, half_w * 2, height * 0.7)
	Raster.framed_rect(img, body, wall, DARK, 2)
	_wall_texture(img, body, wall)
	Raster.framed_polygon(img, PackedVector2Array([Vector2(base_center.x - half_w - 3, top + 2), Vector2(base_center.x + half_w + 3, top + 2), Vector2(base_center.x, top - half_w * 1.1)]), roof, DARK)
	Raster.rect(img, Rect2(base_center.x - 2, top + height * 0.25, 4, 7), DARK)


static func _window(img: Image, at: Vector2) -> void:
	Raster.framed_rect(img, Rect2(at, Vector2(10, 9)), Color(0.98, 0.86, 0.5), DARK, 2)
	Raster.rect(img, Rect2(at + Vector2(4.5, 0), Vector2(1, 9)), DARK)
	Raster.rect(img, Rect2(at + Vector2(0, 4), Vector2(10, 1)), DARK)
	Raster.rect(img, Rect2(at + Vector2(-3, -1), Vector2(2.5, 11)), PLANK.darkened(0.2))
	Raster.rect(img, Rect2(at + Vector2(10.5, -1), Vector2(2.5, 11)), PLANK.darkened(0.2))


static func _banner(img: Image, top: Vector2, team: Color, length: float) -> void:
	Raster.line(img, top, top + Vector2(0, length + 8), 1.5, DARK)
	Raster.framed_polygon(img, PackedVector2Array([top + Vector2(1, 1), top + Vector2(1 + length * 0.9, 3), top + Vector2(1, length * 0.55)]), team, DARK)


## Open market: three stalls with striped awnings (team colour), crates,
## sacks and a hanging sign.
static func _market(img: Image, w: float, h: float, team: Color) -> void:
	Raster.rect(img, Rect2(6, h * 0.3, w - 12, h * 0.64), Color(0.62, 0.55, 0.42))  # paved square
	for k: int in 5:
		Raster.rect(img, Rect2(8, h * 0.36 + k * h * 0.12, w - 16, 1), Color(0.5, 0.44, 0.33))
	for i: int in 3:
		var x0: float = 10.0 + i * (w - 20.0) / 3.0
		var sw: float = (w - 20.0) / 3.0 - 6.0
		var top: float = h * 0.24 + (i % 2) * h * 0.18
		# Counter
		Raster.framed_rect(img, Rect2(x0, top + 22, sw, 14), PLANK, DARK)
		for gx: float in [x0 + 6, x0 + sw * 0.5, x0 + sw - 8]:
			Raster.circle(img, Vector2(gx, top + 22), 3.5, [Color(0.9, 0.3, 0.2), Color(0.95, 0.75, 0.2), Color(0.45, 0.7, 0.3)][i])
		# Posts
		Raster.rect(img, Rect2(x0 + 1, top + 8, 2.5, 26), PLANK.darkened(0.4))
		Raster.rect(img, Rect2(x0 + sw - 3.5, top + 8, 2.5, 26), PLANK.darkened(0.4))
		# Striped awning
		var awning: PackedVector2Array = PackedVector2Array([Vector2(x0 - 3, top + 12), Vector2(x0 + sw + 3, top + 12), Vector2(x0 + sw - 2, top), Vector2(x0 + 2, top)])
		Raster.framed_polygon(img, awning, Color(0.95, 0.93, 0.86), DARK)
		var stripe: float = x0
		while stripe < x0 + sw:
			Raster.polygon(img, PackedVector2Array([Vector2(stripe, top + 12), Vector2(stripe + 5, top + 12), Vector2(stripe + 5.5, top), Vector2(stripe + 0.5, top)]), team)
			stripe += 10.0
	# Crates and sacks in front
	for i: int in 3:
		Raster.framed_rect(img, Rect2(w * 0.18 + i * 13, h * 0.84, 10, 9), PLANK.lightened(0.1), DARK)
	Raster.blob(img, Vector2(w * 0.72, h * 0.88), Vector2(7, 5), Color(0.85, 0.78, 0.6), DARK, 1.0)
	Raster.blob(img, Vector2(w * 0.8, h * 0.86), Vector2(6, 5), Color(0.82, 0.74, 0.55), DARK, 1.0)
	Raster.circle(img, Vector2(w * 0.76, h * 0.8), 3.5, Color(0.95, 0.78, 0.25))  # coin pile
	_banner(img, Vector2(w * 0.5, h * 0.08), team, 12.0)


static func _farm(img: Image, w: float, h: float, team: Color) -> void:
	Raster.framed_rect(img, Rect2(4, 4, w - 8, h - 8), Color(0.45, 0.32, 0.18), team.darkened(0.2), 2)
	for row: int in range(10, int(h) - 8, 10):
		Raster.rect(img, Rect2(8, row, w - 16, 4), Color(0.36, 0.25, 0.13))
		for x: int in range(10, int(w) - 10, 6):
			Raster.circle(img, Vector2(x, row - 2), 2.0, Color(0.55, 0.72, 0.25).lerp(Color(0.85, 0.75, 0.3), Raster.noise(x, row, 3) * 0.5 + 0.5))
