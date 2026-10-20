class_name Rubble
extends Node2D
## What is left where a building fell: a few dark stones on the ground that
## fade away. Purely cosmetic (not saved, not blocking). Drawn from the
## atlas' white texel so it batches with everything else.

const STONES: int = 7

var _rect: Rect2
var _life: float = 90.0
var _left: float = 90.0
var _stones: Array[Rect2] = []
var _tint: Array[Color] = []


func setup(rect: Rect2, seconds: float) -> void:
	_rect = rect
	_life = maxf(1.0, seconds)
	_left = _life
	position = rect.get_center()
	z_index = Building.GROUND_Z - 1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(rect.position.x) * 31 + int(rect.position.y) * 17
	var half: Vector2 = rect.size * 0.5
	for i: int in STONES:
		var s: Vector2 = Vector2(rng.randf_range(6.0, 14.0), rng.randf_range(4.0, 9.0))
		var at: Vector2 = Vector2(rng.randf_range(-half.x + 4.0, half.x - 4.0 - s.x), rng.randf_range(-half.y * 0.4, half.y - 4.0 - s.y))
		_stones.append(Rect2(at, s))
		var g: float = rng.randf_range(0.25, 0.42)
		_tint.append(Color(g, g * 0.95, g * 0.9))


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	if _left < 10.0:
		queue_redraw()


func _draw() -> void:
	var tex: Texture2D = PlaceholderArt.texture()
	var a: float = clampf(_left / 10.0, 0.0, 1.0) * 0.9
	for i: int in _stones.size():
		var c: Color = _tint[i]
		c.a = a
		draw_texture_rect_region(tex, _stones[i], PlaceholderArt.WHITE_RECT, c)
