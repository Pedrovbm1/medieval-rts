class_name Hud
extends CanvasLayer
## Player HUD.
## - Top bar: food / wood / gold / stone, population used/cap, idle bell.
## - Bottom right: selection panel (units: Stop / Hold / Deselect; building: name + HP).
## - Selection box drawn while dragging.
## Every button is >= 64 px for thumbs; text >= 16 px.

signal stop_pressed
signal hold_pressed
signal deselect_pressed
signal idle_pressed

const RESOURCE_ORDER: PackedStringArray = ["food", "wood", "gold", "stone"]

@onready var top_bar: PanelContainer = $TopBar
@onready var resource_row: HBoxContainer = $TopBar/Margin/Row/Resources
@onready var pop_label: Label = $TopBar/Margin/Row/PopLabel
@onready var idle_button: Button = $TopBar/Margin/Row/IdleButton
@onready var selection_panel: PanelContainer = $SelectionPanel
@onready var selection_label: Label = $SelectionPanel/Margin/VBox/SelectionLabel
@onready var unit_buttons: HBoxContainer = $SelectionPanel/Margin/VBox/Buttons
@onready var stop_button: Button = $SelectionPanel/Margin/VBox/Buttons/StopButton
@onready var hold_button: Button = $SelectionPanel/Margin/VBox/Buttons/HoldButton
@onready var deselect_button: Button = $SelectionPanel/Margin/VBox/Buttons/DeselectButton
@onready var box_rect: Panel = $BoxRect

var player_id: int = GameState.PLAYER_HUMAN
var _resource_labels: Dictionary = {}
var _building: Building = null


func _ready() -> void:
	stop_button.text = tr("HUD_STOP")
	hold_button.text = tr("HUD_HOLD")
	deselect_button.text = tr("HUD_DESELECT")
	stop_button.pressed.connect(_on_button.bind(stop_pressed))
	hold_button.pressed.connect(_on_button.bind(hold_pressed))
	deselect_button.pressed.connect(_on_button.bind(deselect_pressed))
	idle_button.pressed.connect(_on_button.bind(idle_pressed))
	_build_resource_row()
	selection_panel.visible = false
	box_rect.visible = false
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.population_changed.connect(_on_population_changed)
	refresh_all()


func refresh_all() -> void:
	for res: String in RESOURCE_ORDER:
		_on_resource_changed(player_id, res, GameState.get_resource(player_id, res))
	_on_population_changed(player_id, GameState.pop_used(player_id), GameState.pop_cap(player_id))


func set_idle_count(count: int) -> void:
	idle_button.text = "%s %d" % [tr("HUD_IDLE"), count]
	idle_button.modulate = Color(1, 0.85, 0.35) if count > 0 else Color(1, 1, 1, 0.6)


func show_selection(units: Array[Unit]) -> void:
	var was_visible: bool = selection_panel.visible
	_building = null
	unit_buttons.visible = true
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


func show_building(b: Building) -> void:
	_building = b
	if b == null:
		if not unit_buttons.visible:
			selection_panel.visible = false
		return
	unit_buttons.visible = false
	selection_panel.visible = true
	_refresh_building()


func _process(_delta: float) -> void:
	if _building != null and is_instance_valid(_building) and selection_panel.visible:
		_refresh_building()


func _refresh_building() -> void:
	var text: String = "%s  %d/%d" % [tr(String(_building.data.get("name_key", _building.building_type))), _building.hp, _building.max_hp]
	if not _building.gather_info().is_empty():
		text += "  (%d/%d)" % [_building.workers.size(), int(_building.gather_info().get("workers", 1))]
	selection_label.text = text


func show_box(active: bool, from_screen: Vector2, to_screen: Vector2) -> void:
	box_rect.visible = active
	if not active:
		return
	var rect: Rect2 = Rect2(from_screen, Vector2.ZERO).expand(to_screen)
	box_rect.position = rect.position
	box_rect.size = rect.size


## True when a screen point lands on an interactive HUD element.
func is_point_over_ui(screen_pos: Vector2) -> bool:
	if selection_panel.visible and selection_panel.get_global_rect().has_point(screen_pos):
		return true
	return top_bar.get_global_rect().has_point(screen_pos)


func _build_resource_row() -> void:
	for res: String in RESOURCE_ORDER:
		var chip: ColorRect = ColorRect.new()
		chip.custom_minimum_size = Vector2(18, 18)
		chip.color = ResourceColors.color(res)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label: Label = Label.new()
		label.custom_minimum_size = Vector2(72, 0)
		label.tooltip_text = tr("RESOURCE_%s_NAME" % res.to_upper())
		resource_row.add_child(chip)
		resource_row.add_child(label)
		_resource_labels[res] = label


func _on_resource_changed(p: int, resource: String, amount: int) -> void:
	if p != player_id or not _resource_labels.has(resource):
		return
	(_resource_labels[resource] as Label).text = str(amount)


func _on_population_changed(p: int, used: int, cap: int) -> void:
	if p != player_id:
		return
	pop_label.text = "%s %d/%d" % [tr("HUD_POP"), used, cap]
	pop_label.modulate = Color(1, 0.5, 0.4) if used >= cap and cap > 0 else Color.WHITE


## Debug aid for automated device tests (adb needs screen coordinates).
func _log_button_centers() -> void:
	var c: Vector2 = stop_button.get_global_rect().get_center()
	print("[REALM] hud stop=(%d,%d)" % [int(c.x), int(c.y)])
	var i: Vector2 = idle_button.get_global_rect().get_center()
	print("[REALM] hud idle=(%d,%d)" % [int(i.x), int(i.y)])


func _on_button(sig: Signal) -> void:
	Sfx.play("ui_click")
	sig.emit()
