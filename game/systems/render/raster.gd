class_name Raster
extends RefCounted
## Tiny software rasterizer for baking original sprites into Images at
## startup: filled circles/ellipses/polygons, thick lines, outlines and
## alpha blending. All game art in REALM is drawn with these primitives.


static func blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or c.a <= 0.0:
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
		return
	var under: Color = img.get_pixel(x, y)
	var a: float = c.a + under.a * (1.0 - c.a)
	if a <= 0.0:
		return
	var rgb: Color = (Color(c.r, c.g, c.b) * c.a + Color(under.r, under.g, under.b) * under.a * (1.0 - c.a)) / a
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))


static func ellipse(img: Image, center: Vector2, radii: Vector2, c: Color) -> void:
	var x0: int = floori(center.x - radii.x)
	var x1: int = ceili(center.x + radii.x)
	var y0: int = floori(center.y - radii.y)
	var y1: int = ceili(center.y + radii.y)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var dx: float = (x + 0.5 - center.x) / maxf(radii.x, 0.01)
			var dy: float = (y + 0.5 - center.y) / maxf(radii.y, 0.01)
			var d: float = dx * dx + dy * dy
			if d <= 1.0:
				# Soft 1px edge.
				var edge: float = clampf((1.0 - sqrt(d)) * minf(radii.x, radii.y), 0.0, 1.0)
				blend(img, x, y, Color(c, c.a * edge))


static func circle(img: Image, center: Vector2, r: float, c: Color) -> void:
	ellipse(img, center, Vector2(r, r), c)


## Ellipse with a darker outline of `width` pixels.
static func blob(img: Image, center: Vector2, radii: Vector2, c: Color, outline: Color, width: float = 1.5) -> void:
	ellipse(img, center, radii + Vector2(width, width), outline)
	ellipse(img, center, radii, c)


static func rect(img: Image, r: Rect2, c: Color) -> void:
	for y: int in range(floori(r.position.y), ceili(r.end.y)):
		for x: int in range(floori(r.position.x), ceili(r.end.x)):
			blend(img, x, y, c)


static func framed_rect(img: Image, r: Rect2, c: Color, outline: Color, width: int = 1) -> void:
	rect(img, r.grow(width), outline)
	rect(img, r, c)


## Filled polygon (even-odd scanline).
static func polygon(img: Image, pts: PackedVector2Array, c: Color) -> void:
	if pts.size() < 3:
		return
	var y0: int = floori(pts[0].y)
	var y1: int = ceili(pts[0].y)
	for p: Vector2 in pts:
		y0 = mini(y0, floori(p.y))
		y1 = maxi(y1, ceili(p.y))
	for y: int in range(y0, y1 + 1):
		var sy: float = y + 0.5
		var xs: Array[float] = []
		for i: int in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k: int = 0
		while k + 1 < xs.size():
			for x: int in range(roundi(xs[k]), roundi(xs[k + 1])):
				blend(img, x, y, c)
			k += 2


static func framed_polygon(img: Image, pts: PackedVector2Array, c: Color, outline: Color) -> void:
	var center: Vector2 = Vector2.ZERO
	for p: Vector2 in pts:
		center += p
	center /= pts.size()
	var grown: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in pts:
		grown.append(p + (p - center).normalized() * 1.2)
	polygon(img, grown, outline)
	polygon(img, pts, c)


## Thick line with round caps.
static func line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps: int = maxi(1, ceili(a.distance_to(b) * 2.0))
	for i: int in steps + 1:
		circle(img, a.lerp(b, float(i) / steps), width * 0.5, c)


## Arc polyline (bows, waves).
static func arc(img: Image, center: Vector2, r: float, from_angle: float, to_angle: float, width: float, c: Color) -> void:
	var steps: int = maxi(4, ceili(absf(to_angle - from_angle) * r))
	var prev: Vector2 = center + Vector2.from_angle(from_angle) * r
	for i: int in range(1, steps + 1):
		var p: Vector2 = center + Vector2.from_angle(lerpf(from_angle, to_angle, float(i) / steps)) * r
		line(img, prev, p, width, c)
		prev = p


## Deterministic per-pixel noise in -1..1 (texture speckles).
static func noise(x: int, y: int, seed: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + seed * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 2000) / 1000.0 - 1.0
