class_name UnitPainter
extends RefCounted
## Paints one original unit sprite for a pose ("idle", "walk0", "walk1",
## "attack0", "attack1", "dead"), facing right. Shapes are laid out on a
## 48x48 grid, drawn at 2x and shrunk to OUT (64x64): bigger and smoother.
## Team colour goes on tunics / caparisons / siege trim; everything else is
## fixed per unit type so silhouettes are readable at a glance.

const SIZE: int = 48
const OUT: Vector2i = Vector2i(64, 64)
const HAIR: Color = Color(0.32, 0.2, 0.12)
const BOOT: Color = Color(0.28, 0.18, 0.1)
const SKIN: Color = Color(0.93, 0.76, 0.6)
const STEEL: Color = Color(0.72, 0.74, 0.78)
const WOOD: Color = Color(0.55, 0.38, 0.2)
const DARK: Color = Color(0.12, 0.1, 0.09)
const LEATHER: Color = Color(0.45, 0.3, 0.18)


static func paint(type_id: String, team: Color, pose: String) -> Image:
	var img: Image = Raster.begin(Vector2i(SIZE, SIZE), 2.0, 0.4)
	var dead: bool = pose == "dead"
	var step: int = 1 if pose == "walk0" else (-1 if pose == "walk1" else 0)
	var strike: int = 1 if pose == "attack1" else (0 if pose == "attack0" else -1)
	if dead:
		_paint_dead(img, type_id, team)
		return Raster.finish(img, OUT)
	match type_id:
		"sheep":
			_quadruped(img, Color(0.95, 0.94, 0.88), Color(0.15, 0.13, 0.12), step, 9.0, false)
			for i: int in 5:
				Raster.circle(img, Vector2(18 + i * 3.5, 24 + (i % 2) * 2), 4.0, Color(0.98, 0.97, 0.92))
		"deer":
			_quadruped(img, Color(0.7, 0.48, 0.28), Color(0.55, 0.36, 0.2), step, 9.0, false)
			Raster.line(img, Vector2(33, 13), Vector2(30, 6), 1.5, Color(0.4, 0.3, 0.2))
			Raster.line(img, Vector2(33, 13), Vector2(37, 6), 1.5, Color(0.4, 0.3, 0.2))
		"boar":
			_quadruped(img, Color(0.33, 0.24, 0.2), Color(0.2, 0.14, 0.12), step, 10.0, true)
			Raster.line(img, Vector2(36, 22), Vector2(39, 19), 1.5, Color(0.95, 0.93, 0.85))
		"scout":
			_horse(img, Color(0.55, 0.38, 0.22), team, step, false)
			_rider(img, team, Vector2(22, 16), 0.85)
			_weapon_sword(img, Vector2(27, 17), strike)
		"knight":
			_horse(img, Color(0.4, 0.3, 0.22), team, step, true)
			_rider(img, team, Vector2(22, 15), 0.9, true)
			_weapon_lance(img, Vector2(26, 16), strike)
		"camel_rider":
			_camel(img, step)
			_rider(img, team, Vector2(21, 11), 0.85)
			_weapon_sword(img, Vector2(26, 12), strike)
		"ram":
			_ram(img, team, strike)
		"mangonel":
			_mangonel(img, team, strike)
		_:
			_infantry(img, type_id, team, step, strike)
	return Raster.finish(img, OUT)


# ------------------------------------------------------------------ humans

static func _infantry(img: Image, type_id: String, team: Color, step: int, strike: int) -> void:
	var cx: float = 23.0
	Raster.ellipse(img, Vector2(cx, 40.5), Vector2(10, 3.2), Color(0, 0, 0, 0.32))
	# Legs with boots
	var legs: Color = Color(0.36, 0.3, 0.26) if type_id != "monk" else Color(0.38, 0.27, 0.18)
	for side: float in [-1.0, 1.0]:
		var hip: Vector2 = Vector2(cx + side * 3.0, 30)
		var foot: Vector2 = Vector2(cx + side * 3.0 + side * -step * 2.0, 37.5)
		Raster.line(img, hip, foot, 3.4, DARK)
		Raster.line(img, hip, foot, 2.4, legs)
		Raster.blob(img, foot + Vector2(1.0, 0.6), Vector2(2.4, 1.4), BOOT, DARK, 0.6)
	# Back arm (behind the body)
	var tunic: Color = team
	if type_id == "monk":
		tunic = Color(0.45, 0.32, 0.22)
	elif type_id == "villager":
		tunic = team.lerp(Color(0.78, 0.68, 0.52), 0.5)
	Raster.line(img, Vector2(cx - 4, 20), Vector2(cx - 6 + step, 28), 3.6, DARK)
	Raster.line(img, Vector2(cx - 4, 20), Vector2(cx - 6 + step, 28), 2.6, tunic.darkened(0.25))
	# Body: tunic flaring to the hem, belt
	var hem: float = 32.0 if type_id != "monk" else 36.0
	Raster.framed_polygon(img, PackedVector2Array([Vector2(cx - 7.5, hem), Vector2(cx + 7.5, hem), Vector2(cx + 5.5, 18), Vector2(cx - 5.5, 18)]), tunic, DARK)
	Raster.line(img, Vector2(cx, 19), Vector2(cx, hem - 1), 0.8, tunic.darkened(0.3))
	if type_id == "villager":
		Raster.polygon(img, PackedVector2Array([Vector2(cx - 4, 25), Vector2(cx + 4.5, 25), Vector2(cx + 5, hem - 0.5), Vector2(cx - 4.5, hem - 0.5)]), Color(0.9, 0.86, 0.74))
	if type_id in ["swordsman", "militia", "spearman"]:
		Raster.framed_rect(img, Rect2(cx - 5.5, 19, 11, 5), STEEL if type_id != "militia" else LEATHER, DARK)
	if type_id != "monk":
		Raster.rect(img, Rect2(cx - 6, 25, 12, 1.8), LEATHER.darkened(0.3))
		Raster.rect(img, Rect2(cx - 1, 24.7, 2.4, 2.4), Color(0.85, 0.7, 0.3))
	else:
		Raster.rect(img, Rect2(cx - 1, 19, 2, 15), team)  # team sash
		Raster.rect(img, Rect2(cx - 6, 25, 12, 1.2), Color(0.85, 0.75, 0.5))
	# Front arm reaching to the weapon hand
	var hand: Vector2 = Vector2(cx + 6, 23) if strike != 1 else Vector2(cx + 8, 24)
	Raster.line(img, Vector2(cx + 4, 20), hand, 3.6, DARK)
	Raster.line(img, Vector2(cx + 4, 20), hand, 2.6, tunic)
	Raster.circle(img, hand, 1.6, SKIN)
	# Head with hair and face
	Raster.blob(img, Vector2(cx, 13), Vector2(4.6, 4.8), SKIN, DARK, 1.0)
	Raster.ellipse(img, Vector2(cx - 1.2, 10.4), Vector2(4.2, 2.6), HAIR)
	Raster.circle(img, Vector2(cx + 2.4, 13.0), 0.7, DARK)
	Raster.line(img, Vector2(cx + 2.0, 15.6), Vector2(cx + 3.4, 15.4), 0.6, Color(0.55, 0.3, 0.25))
	match type_id:
		"villager":
			Raster.ellipse(img, Vector2(cx, 10.2), Vector2(8, 2.4), Color(0.86, 0.72, 0.38))
			Raster.ellipse(img, Vector2(cx, 8.6), Vector2(4.6, 2.6), Color(0.9, 0.78, 0.45))
			Raster.rect(img, Rect2(cx - 4.4, 9.2, 8.8, 1.0), team)
			_tool(img, Vector2(cx + 6, 24), strike)
		"militia":
			Raster.ellipse(img, Vector2(cx, 10), Vector2(5, 3), LEATHER)
			_weapon_sword(img, Vector2(cx + 6, 22), strike)
		"spearman":
			Raster.ellipse(img, Vector2(cx, 10), Vector2(5, 3.5), STEEL)
			_weapon_spear(img, Vector2(cx + 5, 23), strike)
		"swordsman":
			Raster.ellipse(img, Vector2(cx, 10.5), Vector2(5.5, 4), STEEL)
			Raster.rect(img, Rect2(cx - 1, 10, 6, 1.5), DARK)
			Raster.blob(img, Vector2(cx - 7, 25), Vector2(4, 5.5), team.darkened(0.2), DARK, 1.0)
			_weapon_sword(img, Vector2(cx + 6, 22), strike, 13.0)
		"archer":
			Raster.ellipse(img, Vector2(cx, 10), Vector2(5.5, 4), Color(0.3, 0.42, 0.25))
			_weapon_bow(img, Vector2(cx + 7, 22), strike)
		"skirmisher":
			Raster.ellipse(img, Vector2(cx, 10), Vector2(5, 3), LEATHER)
			Raster.blob(img, Vector2(cx - 6, 25), Vector2(3, 4), Color(0.7, 0.55, 0.3), DARK, 1.0)
			_weapon_javelin(img, Vector2(cx + 5, 20), strike)
		"monk":
			Raster.ellipse(img, Vector2(cx, 11), Vector2(6, 5), Color(0.4, 0.28, 0.2))
			Raster.circle(img, Vector2(cx + 1, 13.5), 3.0, SKIN)
			Raster.line(img, Vector2(cx + 8, 8), Vector2(cx + 8, 38), 2.0, WOOD)
			Raster.circle(img, Vector2(cx + 8, 8), 2.5, Color(0.95, 0.9, 0.55))
		_:
			_weapon_sword(img, Vector2(cx + 6, 22), strike)


static func _rider(img: Image, team: Color, at: Vector2, s: float, armored: bool = false) -> void:
	Raster.framed_polygon(img, PackedVector2Array([at + Vector2(-5, 9) * s, at + Vector2(5, 9) * s, at + Vector2(4, 0), at + Vector2(-4, 0)]), team, DARK)
	Raster.blob(img, at + Vector2(0, -5), Vector2(4, 4), SKIN if not armored else STEEL, DARK, 1.0)
	if armored:
		Raster.rect(img, Rect2(at + Vector2(-1, -6), Vector2(5, 1.5)), DARK)


static func _tool(img: Image, hand: Vector2, strike: int) -> void:
	var tip: Vector2 = hand + (Vector2(6, -9) if strike <= 0 else Vector2(10, 2))
	Raster.line(img, hand, tip, 2.0, WOOD)
	Raster.line(img, tip, tip + Vector2(3, 2), 2.5, STEEL)


static func _weapon_sword(img: Image, hand: Vector2, strike: int, length: float = 11.0) -> void:
	var dir: Vector2 = Vector2(0.45, -1).normalized() if strike <= 0 else Vector2(1, 0.25).normalized()
	Raster.line(img, hand, hand + dir * length, 2.0, STEEL)
	Raster.line(img, hand - dir.orthogonal() * 2.5, hand + dir.orthogonal() * 2.5, 1.5, Color(0.8, 0.65, 0.25))


static func _weapon_spear(img: Image, hand: Vector2, strike: int) -> void:
	var dir: Vector2 = Vector2(0.3, -1).normalized() if strike <= 0 else Vector2(1, -0.1).normalized()
	var base: Vector2 = hand - dir * 8.0
	Raster.line(img, base, hand + dir * 15.0, 1.6, WOOD)
	Raster.polygon(img, PackedVector2Array([hand + dir * 15.0 + dir.orthogonal() * 2.0, hand + dir * 15.0 - dir.orthogonal() * 2.0, hand + dir * 20.0]), STEEL)


static func _weapon_lance(img: Image, hand: Vector2, strike: int) -> void:
	var dir: Vector2 = Vector2(1, -0.35).normalized() if strike <= 0 else Vector2(1, 0.05).normalized()
	Raster.line(img, hand - dir * 6.0, hand + dir * 20.0, 2.0, Color(0.75, 0.7, 0.6))


static func _weapon_bow(img: Image, hand: Vector2, strike: int) -> void:
	var draw: float = 3.0 if strike == 0 else 0.0
	Raster.arc(img, hand + Vector2(-draw, 0), 8.0, -1.2, 1.2, 1.5, WOOD)
	Raster.line(img, hand + Vector2(-draw, 0) + Vector2.from_angle(-1.2) * 8.0, hand + Vector2(-draw - 3.0, 0), 0.8, Color(0.9, 0.9, 0.85))
	Raster.line(img, hand + Vector2(-draw, 0) + Vector2.from_angle(1.2) * 8.0, hand + Vector2(-draw - 3.0, 0), 0.8, Color(0.9, 0.9, 0.85))
	if strike == 0:
		Raster.line(img, hand + Vector2(-6, 0), hand + Vector2(8, 0), 1.0, WOOD)


static func _weapon_javelin(img: Image, hand: Vector2, strike: int) -> void:
	var dir: Vector2 = Vector2(0.6, -1).normalized() if strike <= 0 else Vector2(1, -0.3).normalized()
	Raster.line(img, hand - dir * 4.0, hand + dir * 12.0, 1.4, WOOD)
	Raster.circle(img, hand + dir * 12.0, 1.4, STEEL)


# ------------------------------------------------------------------ mounts & animals

static func _horse(img: Image, coat: Color, team: Color, step: int, barded: bool) -> void:
	Raster.ellipse(img, Vector2(24, 41), Vector2(15, 3.5), Color(0, 0, 0, 0.3))
	for lx: float in [14.0, 19.0, 29.0, 34.0]:
		var swing: float = step * (2.0 if int(lx) % 2 == 0 else -2.0)
		Raster.line(img, Vector2(lx, 30), Vector2(lx + swing, 39), 2.6, coat.darkened(0.25))
	Raster.blob(img, Vector2(24, 27), Vector2(13, 6.5), coat, DARK, 1.2)
	Raster.framed_polygon(img, PackedVector2Array([Vector2(33, 26), Vector2(37, 16), Vector2(43, 18), Vector2(40, 22), Vector2(37, 28)]), coat, DARK)
	Raster.line(img, Vector2(34, 23), Vector2(37.5, 15.5), 1.8, coat.darkened(0.55))  # mane
	Raster.circle(img, Vector2(40, 18.4), 0.8, DARK)  # eye
	Raster.line(img, Vector2(11, 25), Vector2(6, 33), 2.6, coat.darkened(0.5))  # tail
	for lx: float in [14.0, 19.0, 29.0, 34.0]:
		var hoof: float = step * (2.0 if int(lx) % 2 == 0 else -2.0)
		Raster.rect(img, Rect2(lx + hoof - 1.5, 38, 3, 1.6), DARK)
	if barded:
		Raster.ellipse(img, Vector2(24, 29), Vector2(12, 4.5), team)
		Raster.rect(img, Rect2(13, 29, 22, 1.5), Color(0.95, 0.85, 0.4))
	else:
		Raster.rect(img, Rect2(19, 22, 9, 3), team)


static func _camel(img: Image, step: int) -> void:
	var coat: Color = Color(0.8, 0.66, 0.42)
	Raster.ellipse(img, Vector2(24, 42), Vector2(14, 3.5), Color(0, 0, 0, 0.3))
	for lx: float in [15.0, 20.0, 29.0, 33.0]:
		var swing: float = step * (2.0 if int(lx) % 2 == 0 else -2.0)
		Raster.line(img, Vector2(lx, 27), Vector2(lx + swing, 40), 2.4, coat.darkened(0.25))
	Raster.blob(img, Vector2(24, 25), Vector2(12, 5.5), coat, DARK, 1.2)
	Raster.circle(img, Vector2(20, 19), 4.5, coat)
	Raster.circle(img, Vector2(28, 19), 4.0, coat)
	Raster.line(img, Vector2(34, 24), Vector2(39, 13), 3.0, coat)
	Raster.blob(img, Vector2(41, 13), Vector2(3.5, 2.5), coat, DARK, 1.0)


static func _quadruped(img: Image, coat: Color, face: Color, step: int, size: float, tusked: bool) -> void:
	Raster.ellipse(img, Vector2(24, 36), Vector2(size + 4, 3), Color(0, 0, 0, 0.3))
	for lx: float in [18.0, 22.0, 27.0, 31.0]:
		var swing: float = step * (1.5 if int(lx) % 2 == 0 else -1.5)
		Raster.line(img, Vector2(lx, 28), Vector2(lx + swing, 35), 2.2, coat.darkened(0.35))
	Raster.blob(img, Vector2(24, 25), Vector2(size + 2, size * 0.65), coat, DARK, 1.0)
	Raster.blob(img, Vector2(34, 20), Vector2(4.5, 3.5), face, DARK, 1.0)
	Raster.circle(img, Vector2(36, 19), 0.9, Color.WHITE if not tusked else Color(0.9, 0.2, 0.15))


# ------------------------------------------------------------------ siege

static func _ram(img: Image, team: Color, strike: int) -> void:
	Raster.ellipse(img, Vector2(24, 41), Vector2(17, 3.5), Color(0, 0, 0, 0.3))
	var push: float = 4.0 if strike == 1 else 0.0
	Raster.line(img, Vector2(14 + push, 27), Vector2(44 + push, 27), 4.0, WOOD.darkened(0.2))
	Raster.circle(img, Vector2(44 + push, 27), 3.0, STEEL)
	Raster.framed_polygon(img, PackedVector2Array([Vector2(8, 34), Vector2(38, 34), Vector2(34, 16), Vector2(12, 16)]), WOOD, DARK)
	Raster.rect(img, Rect2(12, 18, 22, 2), team)
	for wx: float in [13.0, 33.0]:
		Raster.blob(img, Vector2(wx, 36), Vector2(4, 4), WOOD.darkened(0.35), DARK, 1.0)


static func _mangonel(img: Image, team: Color, strike: int) -> void:
	Raster.ellipse(img, Vector2(24, 41), Vector2(16, 3.5), Color(0, 0, 0, 0.3))
	Raster.framed_rect(img, Rect2(8, 30, 30, 5), WOOD, DARK)
	Raster.line(img, Vector2(14, 30), Vector2(22, 18), 2.5, WOOD)
	Raster.line(img, Vector2(30, 30), Vector2(22, 18), 2.5, WOOD)
	var arm_tip: Vector2 = Vector2(10, 12) if strike == 1 else Vector2(36, 24)
	Raster.line(img, Vector2(22, 20), arm_tip, 2.5, WOOD.lightened(0.15))
	Raster.circle(img, arm_tip, 3.0, Color(0.5, 0.48, 0.45))
	Raster.rect(img, Rect2(9, 31, 28, 1.5), team)
	for wx: float in [12.0, 34.0]:
		Raster.blob(img, Vector2(wx, 37), Vector2(3.5, 3.5), WOOD.darkened(0.35), DARK, 1.0)


# ------------------------------------------------------------------ corpse

static func _paint_dead(img: Image, type_id: String, team: Color) -> void:
	var animal: bool = type_id in ["sheep", "deer", "boar"]
	var big: bool = type_id in ["scout", "knight", "camel_rider", "ram", "mangonel"]
	var w: float = 16.0 if big else 11.0
	Raster.ellipse(img, Vector2(24, 34), Vector2(w + 2, 4.5), Color(0.35, 0.05, 0.05, 0.35))
	var body: Color = team.darkened(0.35) if not animal else Color(0.5, 0.4, 0.32)
	if type_id in ["ram", "mangonel"]:
		body = WOOD.darkened(0.4)
	Raster.blob(img, Vector2(24, 31), Vector2(w, 4.0), body, DARK, 1.0)
	if not animal and not type_id in ["ram", "mangonel"]:
		Raster.circle(img, Vector2(24 + w, 30), 3.5, SKIN.darkened(0.2))
