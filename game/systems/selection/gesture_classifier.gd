class_name GestureClassifier
extends RefCounted
## Pure touch-gesture state machine. No nodes, no engine input: callers feed
## press/move/release/update with an explicit time in ms, and read back a list
## of gesture dictionaries. That makes every rule testable headless.
##
## Rules (thresholds come from rules.json "input"):
## - 1 finger, released before moving drag_threshold_px  -> "tap" or "double_tap"
## - 1 finger, moves past the threshold before box_hold_ms -> "pan" (camera)
## - 1 finger, held still for box_hold_ms                 -> "box_armed", then
##   dragging draws "box_update" and release gives "box_end" (or "long_press")
## - 2 fingers at any moment                              -> "pinch" (zoom + pan);
##   no tap or box can fire until every finger is lifted, except that a finger
##   left on screen after a pinch keeps panning.

enum Mode { IDLE, PENDING, PAN, BOX, MULTI }

var drag_threshold_px: float = 30.0
var box_hold_ms: int = 350
var double_tap_ms: int = 320
var double_tap_px: float = 48.0

var mode: Mode = Mode.IDLE
## index -> { "start": Vector2, "pos": Vector2, "start_ms": int }
var _pointers: Dictionary = {}
var _primary: int = -1
var _pinch_ids: Array[int] = []
var _pinch_start_distance: float = 1.0
var _pinch_last_mid: Vector2 = Vector2.ZERO
var _last_tap_ms: int = -100000
var _last_tap_pos: Vector2 = Vector2.INF
var _out: Array[Dictionary] = []


func configure(input_rules: Dictionary) -> void:
	drag_threshold_px = float(input_rules.get("drag_threshold_px", drag_threshold_px))
	box_hold_ms = int(input_rules.get("box_hold_ms", box_hold_ms))
	double_tap_ms = int(input_rules.get("double_tap_ms", double_tap_ms))
	double_tap_px = float(input_rules.get("double_tap_px", double_tap_px))


func pointer_count() -> int:
	return _pointers.size()


func has_pointer(index: int) -> bool:
	return _pointers.has(index)


func press(index: int, pos: Vector2, now_ms: int) -> Array[Dictionary]:
	_out = []
	_pointers[index] = {"start": pos, "pos": pos, "start_ms": now_ms}
	if _pointers.size() == 1:
		mode = Mode.PENDING
		_primary = index
	elif _pointers.size() == 2:
		if mode == Mode.BOX:
			_emit("box_cancel", {})
		_start_pinch()
	return _out


func move(index: int, pos: Vector2, now_ms: int) -> Array[Dictionary]:
	_out = []
	if not _pointers.has(index):
		return _out
	var p: Dictionary = _pointers[index]
	var prev: Vector2 = p["pos"]
	p["pos"] = pos
	match mode:
		Mode.PENDING:
			_check_hold(now_ms)
			if mode == Mode.PENDING and Vector2(p["start"]).distance_to(pos) > drag_threshold_px:
				mode = Mode.PAN
				# Include the movement spent crossing the threshold so the map does not lag the finger.
				_emit("pan", {"delta": pos - Vector2(p["start"])})
			elif mode == Mode.BOX:
				_emit("box_update", {"from": Vector2(p["start"]), "to": pos})
		Mode.PAN:
			if index == _primary:
				_emit("pan", {"delta": pos - prev})
		Mode.BOX:
			if index == _primary:
				_emit("box_update", {"from": Vector2(p["start"]), "to": pos})
		Mode.MULTI:
			if _pinch_ids.has(index):
				_emit_pinch()
	return _out


func release(index: int, pos: Vector2, now_ms: int) -> Array[Dictionary]:
	_out = []
	if not _pointers.has(index):
		return _out
	var p: Dictionary = _pointers[index]
	p["pos"] = pos
	var start: Vector2 = p["start"]
	# Evaluate the hold rule while the finger is still registered: a slow frame
	# may skip update() between press and release.
	if mode == Mode.PENDING:
		_check_hold(now_ms)
	_pointers.erase(index)
	match mode:
		Mode.PENDING:
			if mode == Mode.PENDING:
				_emit_tap(start, now_ms)
			elif mode == Mode.BOX:
				_emit("long_press", {"pos": start})
		Mode.PAN:
			if index == _primary:
				_emit("pan_end", {})
		Mode.BOX:
			if index == _primary:
				if start.distance_to(pos) > drag_threshold_px:
					_emit("box_end", {"from": start, "to": pos})
				else:
					_emit("long_press", {"pos": start})
		Mode.MULTI:
			_pinch_ids.erase(index)
			if _pointers.size() >= 2:
				_start_pinch()
			elif _pointers.size() == 1:
				_emit("pinch_end", {})
				# The finger left behind keeps panning; it can never become a tap.
				mode = Mode.PAN
				_primary = int(_pointers.keys()[0])
	if _pointers.is_empty():
		if mode == Mode.MULTI:
			_emit("pinch_end", {})
		mode = Mode.IDLE
		_primary = -1
		_pinch_ids.clear()
	return _out


## Call every frame: promotes a still finger to box mode after box_hold_ms.
func update(now_ms: int) -> Array[Dictionary]:
	_out = []
	if mode == Mode.PENDING:
		_check_hold(now_ms)
	return _out


## Drops every pointer (app lost focus, etc.).
func cancel_all() -> Array[Dictionary]:
	_out = []
	if mode == Mode.BOX:
		_emit("box_cancel", {})
	elif mode == Mode.PAN:
		_emit("pan_end", {})
	elif mode == Mode.MULTI:
		_emit("pinch_end", {})
	_pointers.clear()
	_pinch_ids.clear()
	mode = Mode.IDLE
	_primary = -1
	return _out


func _check_hold(now_ms: int) -> void:
	if mode != Mode.PENDING or not _pointers.has(_primary):
		return
	var p: Dictionary = _pointers[_primary]
	if now_ms - int(p["start_ms"]) < box_hold_ms:
		return
	if Vector2(p["start"]).distance_to(Vector2(p["pos"])) > drag_threshold_px:
		return
	mode = Mode.BOX
	_emit("box_armed", {"pos": Vector2(p["start"])})


func _emit_tap(pos: Vector2, now_ms: int) -> void:
	var is_double: bool = now_ms - _last_tap_ms <= double_tap_ms and pos.distance_to(_last_tap_pos) <= double_tap_px
	if is_double:
		_emit("double_tap", {"pos": pos})
		_last_tap_ms = -100000
		_last_tap_pos = Vector2.INF
	else:
		_emit("tap", {"pos": pos})
		_last_tap_ms = now_ms
		_last_tap_pos = pos


func _start_pinch() -> void:
	if mode == Mode.PAN:
		_emit("pan_end", {})
	mode = Mode.MULTI
	_pinch_ids.clear()
	for key: Variant in _pointers.keys():
		if _pinch_ids.size() < 2:
			_pinch_ids.append(int(key))
	var a: Vector2 = _pointers[_pinch_ids[0]]["pos"]
	var b: Vector2 = _pointers[_pinch_ids[1]]["pos"]
	_pinch_start_distance = maxf(a.distance_to(b), 1.0)
	_pinch_last_mid = (a + b) * 0.5
	_emit("pinch_start", {"center": _pinch_last_mid})


func _emit_pinch() -> void:
	var a: Vector2 = _pointers[_pinch_ids[0]]["pos"]
	var b: Vector2 = _pointers[_pinch_ids[1]]["pos"]
	var mid: Vector2 = (a + b) * 0.5
	_emit("pinch", {
		"center": mid,
		"ratio": a.distance_to(b) / _pinch_start_distance,
		"pan": mid - _pinch_last_mid,
	})
	_pinch_last_mid = mid


func _emit(kind: String, data: Dictionary) -> void:
	data["type"] = kind
	_out.append(data)
