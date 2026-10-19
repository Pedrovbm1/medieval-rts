class_name TutorialArrow
extends Node2D
## A bouncing arrow drawn in the world above the tutorial's current target.
## Vector2.INF hides it.

var target: Vector2 = Vector2.INF:
	set(value):
		target = value
		visible = value != Vector2.INF

var _t: float = 0.0


func _ready() -> void:
	z_index = 60
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	position = target + Vector2(0, -26.0 - absf(sin(_t * 4.0)) * 12.0)
	queue_redraw()


func _draw() -> void:
	var tip: PackedVector2Array = PackedVector2Array([Vector2(-16, -20), Vector2(16, -20), Vector2(0, 4)])
	var shaft: Rect2 = Rect2(-6, -40, 12, 22)
	draw_rect(shaft.grow(2.0), Color(0.1, 0.08, 0.05))
	draw_colored_polygon(PackedVector2Array([Vector2(-19, -22), Vector2(19, -22), Vector2(0, 7)]), Color(0.1, 0.08, 0.05))
	draw_rect(shaft, Color(1.0, 0.82, 0.25))
	draw_colored_polygon(tip, Color(1.0, 0.82, 0.25))
