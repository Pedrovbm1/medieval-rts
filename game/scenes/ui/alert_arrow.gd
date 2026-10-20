class_name AlertArrow
extends Control
## Big red arrow at the screen edge pointing at the latest attack while it is
## off screen (a phone shows a small slice of the map; the minimap pulse alone
## is easy to miss). Tapping it is not needed: the minimap jumps there.

const SECONDS: float = 6.0
const MARGIN: float = 70.0

var camera: CameraController
var target: Vector2 = Vector2.INF
var _left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func point(world_pos: Vector2) -> void:
	target = world_pos
	_left = SECONDS


## True while the arrow is up (the attack is recent and off screen).
func is_showing() -> bool:
	return _left > 0.0 and target != Vector2.INF and camera != null and not camera.visible_world_rect().grow(-40.0).has_point(target)


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	queue_redraw()


func _draw() -> void:
	if not is_showing():
		return
	var view: Rect2 = get_viewport_rect()
	var center: Vector2 = view.size * 0.5
	var at: Vector2 = camera.world_to_screen(target)
	var dir: Vector2 = (at - center).normalized()
	if dir == Vector2.ZERO:
		return
	# Where the ray from the centre leaves the (inset) screen rectangle.
	var inner: Rect2 = view.grow(-MARGIN)
	var tx: float = INF
	var ty: float = INF
	if dir.x != 0.0:
		tx = ((inner.end.x if dir.x > 0.0 else inner.position.x) - center.x) / dir.x
	if dir.y != 0.0:
		ty = ((inner.end.y if dir.y > 0.0 else inner.position.y) - center.y) / dir.y
	var tip: Vector2 = center + dir * minf(tx, ty)
	var pulse: float = 1.0 + 0.15 * sin(Time.get_ticks_msec() / 90.0)
	var side: Vector2 = dir.orthogonal()
	var pts: PackedVector2Array = PackedVector2Array([
		tip, tip - dir * 42.0 * pulse + side * 22.0 * pulse, tip - dir * 42.0 * pulse - side * 22.0 * pulse])
	var a: float = clampf(_left / 1.5, 0.0, 1.0)
	draw_colored_polygon(pts, Color(0.05, 0.02, 0.02, 0.8 * a))
	var inner_pts: PackedVector2Array = PackedVector2Array([
		tip - dir * 5.0, tip - dir * 36.0 * pulse + side * 16.0 * pulse, tip - dir * 36.0 * pulse - side * 16.0 * pulse])
	draw_colored_polygon(inner_pts, Color(1.0, 0.25, 0.2, a))
