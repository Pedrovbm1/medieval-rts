class_name OrderMarker
extends Node2D
## World-space feedback for a confirmed order: a line from the group to the
## target and a shrinking ring at the target. Lives a fraction of a second.

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _color: Color = Color(0.4, 1.0, 0.4)
var _duration: float = 0.6
var _elapsed: float = 0.0


func _ready() -> void:
	z_index = 50
	visible = false
	set_process(false)


func show_order(from_pos: Vector2, to_pos: Vector2, color: Color) -> void:
	_from = from_pos
	_to = to_pos
	_color = color
	_duration = float(DataLoader.rule("feedback", "order_marker_seconds", 0.6))
	_elapsed = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		visible = false
		set_process(false)
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_elapsed / maxf(_duration, 0.01), 0.0, 1.0)
	var alpha: float = 1.0 - t
	var col: Color = Color(_color, alpha)
	draw_line(_from, _to, Color(_color, alpha * 0.6), 3.0, true)
	draw_arc(_to, lerpf(26.0, 8.0, t), 0.0, TAU, 32, col, 4.0, true)
	draw_circle(_to, 4.0, col)
