class_name PointerManager
extends Node
## Single owner of touch input. Feeds every finger into GestureClassifier and
## routes the result: pan/pinch -> camera, tap/box -> SelectionController.
## Fingers that start on top of the HUD are ignored, so buttons never leak
## gestures into the map.

signal box_changed(active: bool, from_screen: Vector2, to_screen: Vector2)

var camera: CameraController
var selection: SelectionController
var hud: Hud
var classifier: GestureClassifier = GestureClassifier.new()

var _pinch_start_zoom: float = 1.0
var _vibrate_ms: int = 25
var _log: bool = false
## Fingers that began on the HUD: index -> true. Ignored until released.
var _ui_fingers: Dictionary = {}


func setup(p_camera: CameraController, p_selection: SelectionController, p_hud: Hud) -> void:
	camera = p_camera
	selection = p_selection
	hud = p_hud
	classifier.configure(DataLoader.get_table("rules").get("input", {}))
	_vibrate_ms = int(DataLoader.rule("input", "box_arm_vibration_ms", 25))
	_log = bool(DataLoader.rule("debug", "log_input", false)) and OS.is_debug_build()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		process_event(event, Time.get_ticks_msec())


func _process(_delta: float) -> void:
	_dispatch(classifier.update(Time.get_ticks_msec()))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_ui_fingers.clear()
		_dispatch(classifier.cancel_all())


## Entry point for real and synthetic (test) touch events.
func process_event(event: InputEvent, now_ms: int) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			if hud != null and hud.is_point_over_ui(touch.position):
				_ui_fingers[touch.index] = true
				return
			_dispatch(classifier.press(touch.index, touch.position, now_ms))
		else:
			if _ui_fingers.has(touch.index):
				_ui_fingers.erase(touch.index)
				return
			_dispatch(classifier.release(touch.index, touch.position, now_ms))
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and not _ui_fingers.has(drag.index):
		_dispatch(classifier.move(drag.index, drag.position, now_ms))


func _dispatch(gestures: Array[Dictionary]) -> void:
	for g: Dictionary in gestures:
		var kind: String = String(g["type"])
		if _log and kind != "pan" and kind != "pinch" and kind != "box_update":
			print("[REALM] gesture ", kind)
		match kind:
			"tap":
				selection.on_tap(g["pos"])
			"double_tap":
				selection.on_double_tap(g["pos"])
			"pan":
				camera.pan_screen(g["delta"])
			"pinch_start":
				_pinch_start_zoom = camera.get_zoom_factor()
			"pinch":
				camera.pan_screen(g["pan"])
				camera.zoom_at(g["center"], _pinch_start_zoom * float(g["ratio"]))
			"box_armed":
				Input.vibrate_handheld(_vibrate_ms)
				box_changed.emit(true, g["pos"], g["pos"])
			"box_update":
				box_changed.emit(true, g["from"], g["to"])
			"box_end":
				box_changed.emit(false, g["from"], g["to"])
				selection.on_box_end(g["from"], g["to"])
			"box_cancel", "long_press":
				box_changed.emit(false, Vector2.ZERO, Vector2.ZERO)
