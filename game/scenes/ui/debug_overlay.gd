extends CanvasLayer
## Tiny F0 overlay: FPS, zoom and map size so performance can be checked on device.

const REFRESH_SECONDS: float = 0.25

@onready var label: Label = $Label

const PERF_LOG_SECONDS: float = 2.0

var _elapsed: float = 0.0
var _perf_elapsed: float = 0.0
var _frames: int = 0
var _worst_frame_ms: float = 0.0
var _log_perf: bool = false
var _zoom_factor: float = 1.0
var _map_text: String = ""


func _ready() -> void:
	EventBus.camera_zoom_changed.connect(_on_zoom_changed)
	EventBus.map_generated.connect(_on_map_generated)
	# World is an earlier sibling, so its map_generated already fired before
	# this node connected. Read the current map size straight from the data.
	var map_def: Dictionary = DataLoader.get_map(GameState.current_map_id)
	if not map_def.is_empty():
		_on_map_generated(int(map_def.get("width", 0)), int(map_def.get("height", 0)), 0)
	_log_perf = OS.is_debug_build() and bool(DataLoader.rule("debug", "log_perf", false))
	_refresh()


func _process(delta: float) -> void:
	_frames += 1
	_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)
	_perf_elapsed += delta
	if _perf_elapsed >= PERF_LOG_SECONDS:
		if _log_perf:
			print("[REALM] perf fps=%.1f worst_ms=%.1f draw_calls=%d mem_mb=%.1f nodes=%d" % [
				_frames / _perf_elapsed, _worst_frame_ms,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		_perf_elapsed = 0.0
		_frames = 0
		_worst_frame_ms = 0.0
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_refresh()


func _on_zoom_changed(zoom_factor: float) -> void:
	_zoom_factor = zoom_factor


func _on_map_generated(width: int, height: int, _tile_size: int) -> void:
	_map_text = "%dx%d" % [width, height]


func _refresh() -> void:
	label.text = "%s %d   %s %.2fx   %s %s   DC %d" % [
		tr("HUD_FPS"), Engine.get_frames_per_second(),
		tr("HUD_ZOOM"), _zoom_factor,
		tr("HUD_MAP"), _map_text,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	]
