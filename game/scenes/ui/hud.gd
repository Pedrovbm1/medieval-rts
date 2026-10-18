class_name Hud
extends CanvasLayer
## Player HUD. F1: selection panel (count + Stop / Hold / Deselect) and the
## on-screen selection box. Every button is >= 64 px for thumbs.

signal stop_pressed
signal hold_pressed
signal deselect_pressed

@onready var selection_panel: PanelContainer = $SelectionPanel
@onready var selection_label: Label = $SelectionPanel/Margin/VBox/SelectionLabel
@onready var stop_button: Button = $SelectionPanel/Margin/VBox/Buttons/StopButton
@onready var hold_button: Button = $SelectionPanel/Margin/VBox/Buttons/HoldButton
@onready var deselect_button: Button = $SelectionPanel/Margin/VBox/Buttons/DeselectButton
@onready var box_rect: Panel = $BoxRect


func _ready() -> void:
	stop_button.text = tr("HUD_STOP")
	hold_button.text = tr("HUD_HOLD")
	deselect_button.text = tr("HUD_DESELECT")
	stop_button.pressed.connect(_on_button.bind(stop_pressed))
	hold_button.pressed.connect(_on_button.bind(hold_pressed))
	deselect_button.pressed.connect(_on_button.bind(deselect_pressed))
	selection_panel.visible = false
	box_rect.visible = false


func show_selection(units: Array[Unit]) -> void:
	var was_visible: bool = selection_panel.visible
	selection_panel.visible = not units.is_empty()
	if units.is_empty():
		return
	if not was_visible and OS.is_debug_build():
		_log_button_centers.call_deferred()
	var counts: Dictionary = {}
	for unit: Unit in units:
		counts[unit.unit_type] = int(counts.get(unit.unit_type, 0)) + 1
	var parts: PackedStringArray = PackedStringArray()
	for type_id: String in counts.keys():
		var name_key: String = String(DataLoader.get_entry("units", type_id).get("name_key", type_id))
		parts.append("%d %s" % [counts[type_id], tr(name_key)])
	selection_label.text = ", ".join(parts)


func show_box(active: bool, from_screen: Vector2, to_screen: Vector2) -> void:
	box_rect.visible = active
	if not active:
		return
	var rect: Rect2 = Rect2(from_screen, Vector2.ZERO).expand(to_screen)
	box_rect.position = rect.position
	box_rect.size = rect.size


## True when a screen point lands on an interactive HUD element.
func is_point_over_ui(screen_pos: Vector2) -> bool:
	return selection_panel.visible and selection_panel.get_global_rect().has_point(screen_pos)


## Debug aid for automated device tests (adb needs screen coordinates).
func _log_button_centers() -> void:
	var c: Vector2 = stop_button.get_global_rect().get_center()
	print("[REALM] hud stop=(%d,%d)" % [int(c.x), int(c.y)])


func _on_button(sig: Signal) -> void:
	Sfx.play("ui_click")
	sig.emit()
