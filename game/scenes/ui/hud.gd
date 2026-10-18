class_name Hud
extends CanvasLayer
## Player HUD.
## - Top bar: food / wood / gold / stone, population used/cap, idle bell.
## - Bottom-right panel, rebuilt for what is selected:
##   units -> [Build] Stop / Hold / Deselect; build menu -> one button per
##   building (with cost); placing -> ✓ / ✕ + reason; building -> train
##   buttons, queue, cancel construction.
## Every button is >= 64 px for thumbs; text >= 16 px.

signal stop_pressed
signal hold_pressed
signal deselect_pressed
signal idle_pressed
signal build_pressed
signal build_type_chosen(type_id: String)
signal build_back_pressed
signal place_confirm_pressed
signal place_cancel_pressed
signal train_pressed(type_id: String)
signal dequeue_pressed
signal cancel_construction_pressed

const RESOURCE_ORDER: PackedStringArray = ["food", "wood", "gold", "stone"]
const BUTTON_SIZE: Vector2 = Vector2(120, 72)

enum Mode { NONE, UNITS, BUILD_MENU, PLACING, BUILDING }

@onready var top_bar: PanelContainer = $TopBar
@onready var resource_row: HBoxContainer = $TopBar/Margin/Row/Resources
@onready var pop_label: Label = $TopBar/Margin/Row/PopLabel
@onready var idle_button: Button = $TopBar/Margin/Row/IdleButton
@onready var selection_panel: PanelContainer = $SelectionPanel
@onready var selection_label: Label = $SelectionPanel/Margin/VBox/SelectionLabel
@onready var actions: HFlowContainer = $SelectionPanel/Margin/VBox/Actions
@onready var box_rect: Panel = $BoxRect

var player_id: int = GameState.PLAYER_HUMAN
var mode: Mode = Mode.NONE
var stop_button: Button
var hold_button: Button
var deselect_button: Button
var build_button: Button
var confirm_button: Button
var cancel_place_button: Button
var cancel_construction_button: Button
## type id -> Button (build menu or train buttons), for tests and device scripts.
var type_buttons: Dictionary = {}

var _resource_labels: Dictionary = {}
var _units: Array[Unit] = []
var _building: Building = null
var _place_error: String = ""


func _ready() -> void:
	idle_button.pressed.connect(_emit_click.bind(idle_pressed))
	_build_resource_row()
	box_rect.visible = false
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.population_changed.connect(_on_population_changed)
	_set_mode(Mode.NONE)
	refresh_all()


func refresh_all() -> void:
	for res: String in RESOURCE_ORDER:
		_on_resource_changed(player_id, res, GameState.get_resource(player_id, res))
	_on_population_changed(player_id, GameState.pop_used(player_id), GameState.pop_cap(player_id))


func set_idle_count(count: int) -> void:
	idle_button.text = "%s %d" % [tr("HUD_IDLE"), count]
	idle_button.modulate = Color(1, 0.85, 0.35) if count > 0 else Color(1, 1, 1, 0.6)


# ------------------------------------------------------------------ public views

func show_selection(units: Array[Unit]) -> void:
	_units = units.duplicate()
	if mode == Mode.PLACING:
		return
	_building = null
	_set_mode(Mode.UNITS if not units.is_empty() else Mode.NONE)


func show_building(b: Building) -> void:
	if b == null:
		if mode == Mode.BUILDING:
			_building = null
			_set_mode(Mode.NONE)
		return
	_building = b
	if not b.changed.is_connected(_on_building_changed):
		b.changed.connect(_on_building_changed)
	_set_mode(Mode.BUILDING)


func show_build_menu() -> void:
	_set_mode(Mode.BUILD_MENU)


func show_placing(active: bool, error: String) -> void:
	if active:
		_place_error = error
		if mode != Mode.PLACING:
			_set_mode(Mode.PLACING)
		else:
			_refresh_placing()
	elif mode == Mode.PLACING:
		_set_mode(Mode.UNITS if not _units.is_empty() else Mode.NONE)


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


# ------------------------------------------------------------------ panel modes

func _set_mode(m: Mode) -> void:
	var was_visible: bool = selection_panel.visible
	mode = m
	for child: Node in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	type_buttons.clear()
	stop_button = null
	hold_button = null
	deselect_button = null
	build_button = null
	confirm_button = null
	cancel_place_button = null
	cancel_construction_button = null
	match m:
		Mode.NONE:
			selection_panel.visible = false
			return
		Mode.UNITS:
			_fill_units()
		Mode.BUILD_MENU:
			_fill_build_menu()
		Mode.PLACING:
			_fill_placing()
		Mode.BUILDING:
			_fill_building()
	selection_panel.visible = true
	_fit_panel.call_deferred()
	if OS.is_debug_build():
		if not was_visible:
			_log_button_centers.call_deferred()
		_log_actions.call_deferred()


func _fill_units() -> void:
	var counts: Dictionary = {}
	for unit: Unit in _units:
		counts[unit.unit_type] = int(counts.get(unit.unit_type, 0)) + 1
	var parts: PackedStringArray = PackedStringArray()
	for type_id: String in counts.keys():
		var name_key: String = String(DataLoader.get_entry("units", type_id).get("name_key", type_id))
		parts.append("%d %s" % [counts[type_id], tr(name_key)])
	selection_label.text = ", ".join(parts)
	if _units.any(func(u: Unit) -> bool: return is_instance_valid(u) and u.can_gather()):
		build_button = _add_button(tr("HUD_BUILD"), build_pressed)
	stop_button = _add_button(tr("HUD_STOP"), stop_pressed)
	hold_button = _add_button(tr("HUD_HOLD"), hold_pressed)
	deselect_button = _add_button(tr("HUD_DESELECT"), deselect_pressed)


func _fill_build_menu() -> void:
	selection_label.text = tr("HUD_BUILD")
	var table: Dictionary = DataLoader.get_table("buildings")
	for type_id: String in table.keys():
		var def: Dictionary = table[type_id]
		if not bool(def.get("buildable", true)) or int(def.get("era", 1)) > GameState.era_of(player_id):
			continue
		var text: String = "%s\n%s" % [tr(String(def.get("name_key", type_id))), cost_text(def.get("cost", {}))]
		var b: Button = _add_button(text, Signal(), Vector2(150, 72))
		b.pressed.connect(func() -> void:
			Sfx.play("ui_click")
			build_type_chosen.emit(type_id))
		b.disabled = not GameState.can_afford(player_id, def.get("cost", {}))
		type_buttons[type_id] = b
	_add_button(tr("HUD_BACK"), build_back_pressed)


func _fill_placing() -> void:
	confirm_button = _add_button("✓ " + tr("HUD_CONFIRM"), place_confirm_pressed, Vector2(170, 72))
	cancel_place_button = _add_button("✕ " + tr("HUD_CANCEL"), place_cancel_pressed, Vector2(170, 72))
	_refresh_placing()


func _refresh_placing() -> void:
	match _place_error:
		"":
			selection_label.text = tr("HUD_BUILD")
		"cost":
			selection_label.text = tr("ERR_COST")
		"era":
			selection_label.text = tr("ERR_ERA")
		_:
			selection_label.text = tr("ERR_OCCUPIED")
	if confirm_button != null:
		confirm_button.disabled = _place_error != ""


func _fill_building() -> void:
	if _building == null or not is_instance_valid(_building):
		return
	if not _building.is_complete():
		cancel_construction_button = _add_button(tr("HUD_CANCEL"), cancel_construction_pressed)
	else:
		for type_id: Variant in _building.trains():
			var def: Dictionary = DataLoader.get_entry("units", String(type_id))
			if int(def.get("era", 1)) > GameState.era_of(player_id):
				continue
			var text: String = "%s\n%s" % [tr(String(def.get("name_key", type_id))), cost_text(def.get("cost", {}))]
			var b: Button = _add_button(text, Signal(), Vector2(150, 72))
			var id: String = String(type_id)
			b.pressed.connect(func() -> void:
				Sfx.play("ui_click")
				train_pressed.emit(id))
			type_buttons[id] = b
		if not _building.queue.is_empty():
			_add_button(tr("HUD_REMOVE"), dequeue_pressed)
	deselect_button = _add_button(tr("HUD_DESELECT"), deselect_pressed)
	_refresh_building()


func _refresh_building() -> void:
	if _building == null or not is_instance_valid(_building):
		return
	var text: String = "%s  %d/%d" % [tr(String(_building.data.get("name_key", _building.building_type))), _building.hp, _building.max_hp]
	if not _building.is_complete():
		text += "  %s %d%%" % [tr("HUD_UNDER_CONSTRUCTION"), int(_building.build_progress * 100.0)]
	elif not _building.gather_info().is_empty():
		text += "  (%d/%d)" % [_building.workers.size(), int(_building.gather_info().get("workers", 1))]
	if not _building.queue.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for id: String in _building.queue:
			names.append(String(DataLoader.get_entry("units", id).get("placeholder_glyph", "?")))
		text += "\n%s: %s  %d%%" % [tr("HUD_QUEUE"), " ".join(names), int(_building.train_progress() * 100.0)]
		if _building.blocked_by_pop:
			text += "  " + tr("HUD_POP_FULL")
	selection_label.text = text
	for id: String in type_buttons.keys():
		var def: Dictionary = DataLoader.get_entry("units", id)
		(type_buttons[id] as Button).disabled = not GameState.can_afford(player_id, def.get("cost", {}))


func _on_building_changed(b: Building) -> void:
	if mode != Mode.BUILDING or b != _building:
		return
	var had_cancel: bool = cancel_construction_button != null
	var has_queue_button: bool = actions.get_child_count() > type_buttons.size() + (2 if had_cancel else 1)
	# Rebuild when the button set changes (built, queue emptied/filled); else just relabel.
	if had_cancel == b.is_complete() or has_queue_button == b.queue.is_empty():
		_set_mode(Mode.BUILDING)
	else:
		_refresh_building()


func _process(_delta: float) -> void:
	if mode == Mode.BUILDING and _building != null and is_instance_valid(_building):
		_refresh_building()


# ------------------------------------------------------------------ helpers

## Sizes the panel to its content (after the flow container wrapped its rows)
## and keeps it anchored to the bottom-right corner with a 12 px margin.
func _fit_panel() -> void:
	await get_tree().process_frame
	var min_size: Vector2 = selection_panel.get_combined_minimum_size()
	selection_panel.offset_left = -12.0 - min_size.x
	selection_panel.offset_top = -12.0 - min_size.y
	selection_panel.offset_right = -12.0
	selection_panel.offset_bottom = -12.0


## "50 C 20 O" from a cost dictionary, with localized one-letter resource names.
static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for res: String in RESOURCE_ORDER:
		if cost.has(res):
			parts.append("%d %s" % [int(cost[res]), TranslationServer.translate("RESOURCE_%s_SHORT" % res.to_upper())])
	return " ".join(parts)


func _add_button(text: String, sig: Signal, size: Vector2 = BUTTON_SIZE) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	if not sig.is_null():
		b.pressed.connect(_emit_click.bind(sig))
	actions.add_child(b)
	return b


func _build_resource_row() -> void:
	for res: String in RESOURCE_ORDER:
		var chip: ColorRect = ColorRect.new()
		chip.custom_minimum_size = Vector2(18, 18)
		chip.color = ResourceColors.color(res)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label: Label = Label.new()
		label.custom_minimum_size = Vector2(72, 0)
		resource_row.add_child(chip)
		resource_row.add_child(label)
		_resource_labels[res] = label


func _on_resource_changed(p: int, resource: String, amount: int) -> void:
	if p != player_id or not _resource_labels.has(resource):
		return
	(_resource_labels[resource] as Label).text = str(amount)
	if mode == Mode.BUILD_MENU:
		for type_id: String in type_buttons.keys():
			var def: Dictionary = DataLoader.get_entry("buildings", type_id)
			(type_buttons[type_id] as Button).disabled = not GameState.can_afford(player_id, def.get("cost", {}))


func _on_population_changed(p: int, used: int, cap: int) -> void:
	if p != player_id:
		return
	pop_label.text = "%s %d/%d" % [tr("HUD_POP"), used, cap]
	pop_label.modulate = Color(1, 0.5, 0.4) if used >= cap and cap > 0 else Color.WHITE


## Debug aid: logs every action button centre ("[REALM] hud btn <id>=(x,y)").
func _log_actions() -> void:
	await get_tree().process_frame
	var named: Dictionary = {"build": build_button, "stop": stop_button, "hold": hold_button,
		"deselect": deselect_button, "confirm": confirm_button, "cancel_place": cancel_place_button,
		"cancel_construction": cancel_construction_button}
	for id: String in type_buttons.keys():
		named[id] = type_buttons[id]
	for id: String in named.keys():
		var b: Button = named[id]
		if b != null and is_instance_valid(b) and b.is_visible_in_tree():
			var c: Vector2 = b.get_global_rect().get_center()
			print("[REALM] hud btn %s=(%d,%d)" % [id, int(c.x), int(c.y)])


## Debug aid for automated device tests (adb needs screen coordinates).
func _log_button_centers() -> void:
	if stop_button != null and is_instance_valid(stop_button):
		var c: Vector2 = stop_button.get_global_rect().get_center()
		print("[REALM] hud stop=(%d,%d)" % [int(c.x), int(c.y)])
	var i: Vector2 = idle_button.get_global_rect().get_center()
	print("[REALM] hud idle=(%d,%d)" % [int(i.x), int(i.y)])


func _emit_click(sig: Signal) -> void:
	Sfx.play("ui_click")
	sig.emit()
