extends CanvasLayer
## Tiny F0 overlay: FPS, zoom and map size so performance can be checked on device.

const REFRESH_SECONDS: float = 0.25

@onready var label: Label = $Label

var _elapsed: float = 0.0
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
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_refresh()


func _on_zoom_changed(zoom_factor: float) -> void:
	_zoom_factor = zoom_factor


func _on_map_generated(width: int, height: int, _tile_size: int) -> void:
	_map_text = "%dx%d" % [width, height]


func _refresh() -> void:
	label.text = "%s %d   %s %.2fx   %s %s" % [
		tr("HUD_FPS"), Engine.get_frames_per_second(),
		tr("HUD_ZOOM"), _zoom_factor,
		tr("HUD_MAP"), _map_text,
	]
