class_name Raster
extends RefCounted
## Tiny software rasterizer for baking original sprites into Images at
## startup: filled circles/ellipses/polygons, thick lines, outlines and
## alpha blending. All game art in REALM is drawn with these primitives.
##
## Two global settings let painters keep simple coordinates while getting
## better results:
## - `S` (scale): every coordinate and size is multiplied by it. Painters
##   draw at 2x on a bigger image and `finish()` shrinks it: smooth edges.
## - `shade` (0..1): fills get light from the top-left and shadow at the
##   bottom-right, so flat shapes read as volumes.

static var S: float = 1.0
static var shade: float = 0.0

const LIGHT: Vector2 = Vector2(-0.6, -0.8)


## Starts a sprite: a transparent image `scale_factor` times the final size.
static func begin(size: Vector2i, scale_factor: float = 2.0, shading: float = 0.35) -> Image:
	S = scale_factor
	shade = shading
	var img: Image = Image.create(int(size.x * scale_factor), int(size.y * scale_factor), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


## Ends a sprite: shrink to the final size with filtering, add a soft dark
## outline around the silhouette (readable on any ground) and reset settings.
static func finish(img: Image, size: Vector2i, outline: Color = Color(0.08, 0.06, 0.05, 0.85)) -> Image:
	S = 1.0
	shade = 0.0
	if img.get_width() != size.x or img.get_height() != size.y:
		img.resize(size.x, size.y, Image.INTERPOLATE_CUBIC)
	if outline.a > 0.0:
		silhouette_outline(img, outline)
	return img


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


## Light/shadow for a point of a shape: k in -1..1 (1 = facing the light).
static func lit(c: Color, k: float) -> Color:
	if shade <= 0.0 or c.a < 0.99:
		return c
	return c.lightened(k * shade * 0.6) if k > 0.0 else c.darkened(-k * shade)


static func ellipse(img: Image, center: Vector2, radii: Vector2, c: Color) -> void:
	_ellipse_px(img, center * S, radii * S, c)


static func _ellipse_px(img: Image, center: Vector2, radii: Vector2, c: Color) -> void:
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
				var k: float = -(dx * LIGHT.x + dy * LIGHT.y) * -1.0
				blend(img, x, y, Color(lit(c, k), c.a * edge))


static func circle(img: Image, center: Vector2, r: float, c: Color) -> void:
	ellipse(img, center, Vector2(r, r), c)


## Ellipse with a darker outline of `width` pixels.
static func blob(img: Image, center: Vector2, radii: Vector2, c: Color, outline: Color, width: float = 1.5) -> void:
	var keep: float = shade
	shade = 0.0
	ellipse(img, center, radii + Vector2(width, width), outline)
	shade = keep
	ellipse(img, center, radii, c)


static func rect(img: Image, r: Rect2, c: Color) -> void:
	var p: Rect2 = Rect2(r.position * S, r.size * S)
	var h: float = maxf(1.0, p.size.y)
	for y: int in range(floori(p.position.y), ceili(p.end.y)):
		var k: float = 1.0 - 2.0 * clampf((y - p.position.y) / h, 0.0, 1.0)
		var row: Color = lit(c, k * 0.6)
		for x: int in range(floori(p.position.x), ceili(p.end.x)):
			blend(img, x, y, row)


static func framed_rect(img: Image, r: Rect2, c: Color, outline: Color, width: int = 1) -> void:
	var keep: float = shade
	shade = 0.0
	rect(img, r.grow(width), outline)
	shade = keep
	rect(img, r, c)


## Filled polygon (even-odd scanline), shaded top (light) to bottom (dark).
static func polygon(img: Image, pts: PackedVector2Array, c: Color) -> void:
	if pts.size() < 3:
		return
	var sp: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in pts:
		sp.append(p * S)
	var y0: int = floori(sp[0].y)
	var y1: int = ceili(sp[0].y)
	for p: Vector2 in sp:
		y0 = mini(y0, floori(p.y))
		y1 = maxi(y1, ceili(p.y))
	var h: float = maxf(1.0, y1 - y0)
	for y: int in range(y0, y1 + 1):
		var sy: float = y + 0.5
		var xs: Array[float] = []
		for i: int in sp.size():
			var a: Vector2 = sp[i]
			var b: Vector2 = sp[(i + 1) % sp.size()]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var row: Color = lit(c, (1.0 - 2.0 * (y - y0) / h) * 0.7)
		var k: int = 0
		while k + 1 < xs.size():
			for x: int in range(roundi(xs[k]), roundi(xs[k + 1])):
				blend(img, x, y, row)
			k += 2


static func framed_polygon(img: Image, pts: PackedVector2Array, c: Color, outline: Color) -> void:
	var center: Vector2 = Vector2.ZERO
	for p: Vector2 in pts:
		center += p
	center /= pts.size()
	var grown: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in pts:
		grown.append(p + (p - center).normalized() * 1.2)
	var keep: float = shade
	shade = 0.0
	polygon(img, grown, outline)
	shade = keep
	polygon(img, pts, c)


## Thick line with round caps (not shaded: lines are details).
static func line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var keep: float = shade
	shade = 0.0
	var pa: Vector2 = a * S
	var pb: Vector2 = b * S
	var r: float = width * 0.5 * S
	var steps: int = maxi(1, ceili(pa.distance_to(pb) * 2.0 / S))
	for i: int in steps + 1:
		_ellipse_px(img, pa.lerp(pb, float(i) / steps), Vector2(r, r), c)
	shade = keep


## Arc polyline (bows, waves).
static func arc(img: Image, center: Vector2, r: float, from_angle: float, to_angle: float, width: float, c: Color) -> void:
	var steps: int = maxi(4, ceili(absf(to_angle - from_angle) * r))
	var prev: Vector2 = center + Vector2.from_angle(from_angle) * r
	for i: int in range(1, steps + 1):
		var p: Vector2 = center + Vector2.from_angle(lerpf(from_angle, to_angle, float(i) / steps)) * r
		line(img, prev, p, width, c)
		prev = p


## Dark 1px ring around every opaque area (after shrinking), skipping
## see-through shadows.
static func silhouette_outline(img: Image, c: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var solid: PackedByteArray = PackedByteArray()
	solid.resize(w * h)
	for y: int in h:
		for x: int in w:
			solid[y * w + x] = 1 if img.get_pixel(x, y).a > 0.55 else 0
	for y: int in h:
		for x: int in w:
			if solid[y * w + x] == 1 or img.get_pixel(x, y).a > 0.3:
				continue
			var near: bool = false
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and solid[ny * w + nx] == 1:
					near = true
					break
			if near:
				blend(img, x, y, c)


## Deterministic per-pixel noise in -1..1 (texture speckles).
static func noise(x: int, y: int, seed: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + seed * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 2000) / 1000.0 - 1.0
