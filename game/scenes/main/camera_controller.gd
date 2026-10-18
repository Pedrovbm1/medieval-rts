class_name CameraController
extends Camera2D
## RTS camera. Since F1 it does not read touch input itself: PointerManager owns
## every finger and calls pan_screen / zoom_at. The camera only moves, zooms and
## stays clamped inside the map. Mouse wheel zoom is kept for desktop testing.

const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 1.5
const WHEEL_ZOOM_STEP: float = 0.1
const CENTER_TWEEN_SECONDS: float = 0.25

var map_bounds: Rect2 = Rect2()
var _center_tween: Tween = null


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false
	make_current()


## Sets the world rectangle the camera may show, then re-clamps.
func set_map_bounds(bounds: Rect2) -> void:
	map_bounds = bounds
	position = _clamped(position)


func center_on(world_pos: Vector2) -> void:
	_kill_tween()
	position = _clamped(world_pos)


## Glides to a world position (double tap on ground, idle bell, minimap...).
func center_on_smooth(world_pos: Vector2) -> void:
	_kill_tween()
	_center_tween = create_tween()
	_center_tween.tween_property(self, "position", _clamped(world_pos), CENTER_TWEEN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func get_zoom_factor() -> float:
	return zoom.x


## Moves the view so the map follows a finger that moved by screen_delta.
func pan_screen(screen_delta: Vector2) -> void:
	_kill_tween()
	position = _clamped(position - screen_delta / zoom.x)


## Sets the zoom factor keeping the world point under screen_point fixed.
func zoom_at(screen_point: Vector2, new_factor: float) -> void:
	var factor: float = clampf(new_factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(factor, zoom.x):
		return
	_kill_tween()
	var before: Vector2 = screen_to_world(screen_point)
	zoom = Vector2(factor, factor)
	var after: Vector2 = screen_to_world(screen_point)
	position = _clamped(position + before - after)
	EventBus.camera_zoom_changed.emit(factor)


func screen_to_world(screen_point: Vector2) -> Vector2:
	var view_size: Vector2 = get_viewport_rect().size
	return position + (screen_point - view_size * 0.5) / zoom.x


func world_to_screen(world_pos: Vector2) -> Vector2:
	var view_size: Vector2 = get_viewport_rect().size
	return (world_pos - position) * zoom.x + view_size * 0.5


## World rectangle currently visible on screen.
func visible_world_rect() -> Rect2:
	var view_size: Vector2 = get_viewport_rect().size / zoom.x
	return Rect2(position - view_size * 0.5, view_size)


func _unhandled_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_at(mouse.position, zoom.x + WHEEL_ZOOM_STEP)
	elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_at(mouse.position, zoom.x - WHEEL_ZOOM_STEP)


func _kill_tween() -> void:
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	_center_tween = null


func _clamped(world_pos: Vector2) -> Vector2:
	return clamp_to_bounds(world_pos, map_bounds, get_viewport_rect().size, zoom.x)


## Pure clamp so the visible rectangle stays inside bounds. Static for unit tests.
## If the view is larger than the map on an axis, the camera centres on that axis.
static func clamp_to_bounds(world_pos: Vector2, bounds: Rect2, view_size: Vector2, zoom_factor: float) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return world_pos
	var half_view: Vector2 = view_size * 0.5 / zoom_factor
	var min_pos: Vector2 = bounds.position + half_view
	var max_pos: Vector2 = bounds.end - half_view
	var result: Vector2 = world_pos
	if max_pos.x < min_pos.x:
		result.x = bounds.get_center().x
	else:
		result.x = clampf(world_pos.x, min_pos.x, max_pos.x)
	if max_pos.y < min_pos.y:
		result.y = bounds.get_center().y
	else:
		result.y = clampf(world_pos.y, min_pos.y, max_pos.y)
	return result
