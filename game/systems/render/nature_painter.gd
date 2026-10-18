class_name NaturePainter
extends RefCounted
## Original terrain tiles (with variants), resource sprites and HUD icons.

const DARK: Color = Color(0.12, 0.1, 0.08)


## A 64x64 tile for a terrain id; `variant` changes the speckle pattern.
static func tile(terrain_name: String, base: Color, variant: int, size: int) -> Image:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y: int in size:
		for x: int in size:
			var n: float = Raster.noise(x, y, variant * 31 + 7)
			var n2: float = Raster.noise(x / 4, y / 4, variant * 13 + 3)
			img.set_pixel(x, y, base.lightened(maxf(0.0, n2 * 0.06)).darkened(maxf(0.0, -n2 * 0.06) + (0.05 if n > 0.92 else 0.0)))
	match terrain_name:
		"grass":
			for i: int in 26:
				var x: int = int((Raster.noise(i, variant, 11) * 0.5 + 0.5) * size)
				var y: int = int((Raster.noise(variant, i, 17) * 0.5 + 0.5) * size)
				Raster.line(img, Vector2(x, y), Vector2(x + 1, y - 3), 1.0, base.darkened(0.25))
			if variant == 2:
				Raster.circle(img, Vector2(size * 0.7, size * 0.3), 1.5, Color(0.95, 0.9, 0.4))
				Raster.circle(img, Vector2(size * 0.25, size * 0.75), 1.5, Color(0.95, 0.95, 0.95))
		"water":
			for i: int in 5:
				var y: float = (i + 0.5) * size / 5.0 + variant * 3.0
				var x: float = fmod(i * 23.0 + variant * 17.0, size - 18.0)
				Raster.arc(img, Vector2(x + 8, fmod(y, size)), 6.0, -2.6, -0.5, 1.0, base.lightened(0.25))
		"forest":
			var grass: Color = Color(0.36, 0.55, 0.28)
			img.fill(grass.darkened(0.15))
			var spots: Array = [Vector2(16, 18), Vector2(44, 14), Vector2(30, 40), Vector2(54, 48), Vector2(10, 50)]
			for k: int in spots.size():
				var c: Vector2 = spots[(k + variant) % spots.size()] + Vector2(Raster.noise(k, variant, 5) * 3.0, 0)
				Raster.ellipse(img, c + Vector2(3, 8), Vector2(11, 5), Color(0, 0, 0, 0.25))
				Raster.rect(img, Rect2(c.x - 1.5, c.y + 2, 3, 8), Color(0.38, 0.25, 0.14))
				Raster.blob(img, c, Vector2(11, 10), base, DARK, 1.0)
				Raster.circle(img, c + Vector2(-3, -3), 5.0, base.lightened(0.18))
	return img


static func resource(type_id: String, size: Vector2i, base: Color) -> Image:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: Vector2 = Vector2(size) * 0.5
	match type_id:
		"gold_mine", "stone_mine":
			var rock: Color = Color(0.5, 0.48, 0.45) if type_id == "gold_mine" else base
			var pts: Array = [Vector2(-0.25, 0.1), Vector2(0.15, -0.05), Vector2(0.0, 0.25), Vector2(0.28, 0.22), Vector2(-0.3, -0.2)]
			for p: Vector2 in pts:
				var at: Vector2 = c + p * Vector2(size)
				Raster.blob(img, at, Vector2(size.x * 0.2, size.y * 0.15), rock, DARK, 1.2)
				Raster.circle(img, at + Vector2(-4, -4), size.x * 0.06, rock.lightened(0.2))
			if type_id == "gold_mine":
				for i: int in 9:
					var at2: Vector2 = c + Vector2(Raster.noise(i, 1, 2), Raster.noise(1, i, 4)) * Vector2(size) * 0.35
					Raster.blob(img, at2, Vector2(3.5, 2.8), base, DARK, 0.8)
					Raster.circle(img, at2 + Vector2(-1, -1), 1.2, Color(1, 0.95, 0.7))
		"berry_bush":
			Raster.ellipse(img, c + Vector2(3, 9), Vector2(size.x * 0.4, 6), Color(0, 0, 0, 0.25))
			Raster.blob(img, c, Vector2(size.x * 0.4, size.y * 0.35), Color(0.24, 0.48, 0.22), DARK, 1.2)
			for i: int in 10:
				Raster.circle(img, c + Vector2(Raster.noise(i, 3, 9), Raster.noise(3, i, 1)) * Vector2(size) * 0.28, 2.6, base)
		_:
			# Carcass: a joint of meat on the ground.
			Raster.blob(img, c, Vector2(size.x * 0.3, size.y * 0.2), base, DARK, 1.0)
			Raster.blob(img, c + Vector2(-4, -2), Vector2(size.x * 0.16, size.y * 0.1), Color(0.8, 0.35, 0.3), DARK, 0.8)
			Raster.line(img, c + Vector2(size.x * 0.2, 0), c + Vector2(size.x * 0.34, -4), 2.5, Color(0.95, 0.92, 0.85))
	return img


## 24x24 HUD icons for the four resources.
static func icon(resource: String) -> Image:
	var img: Image = Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match resource:
		"food":
			Raster.blob(img, Vector2(12, 13), Vector2(8, 7.5), Color(0.86, 0.22, 0.18), DARK, 1.0)
			Raster.line(img, Vector2(12, 6), Vector2(14, 2), 1.5, Color(0.4, 0.28, 0.15))
			Raster.ellipse(img, Vector2(16, 4), Vector2(3, 1.5), Color(0.35, 0.65, 0.25))
			Raster.circle(img, Vector2(9, 10), 2.0, Color(1, 0.6, 0.55))
		"wood":
			Raster.framed_polygon(img, PackedVector2Array([Vector2(3, 15), Vector2(17, 6), Vector2(21, 11), Vector2(7, 20)]), Color(0.6, 0.4, 0.2), DARK)
			Raster.blob(img, Vector2(19, 8.5), Vector2(3, 3.5), Color(0.85, 0.7, 0.45), DARK, 0.8)
		"gold":
			Raster.blob(img, Vector2(12, 12), Vector2(8.5, 8.5), Color(0.95, 0.78, 0.2), DARK, 1.0)
			Raster.circle(img, Vector2(12, 12), 5.0, Color(1, 0.88, 0.4))
			Raster.rect(img, Rect2(11, 8, 2, 8), Color(0.8, 0.6, 0.1))
		"stone":
			Raster.blob(img, Vector2(10, 14), Vector2(7, 5.5), Color(0.62, 0.62, 0.6), DARK, 1.0)
			Raster.blob(img, Vector2(16, 10), Vector2(5, 4.5), Color(0.72, 0.72, 0.7), DARK, 1.0)
	return img
