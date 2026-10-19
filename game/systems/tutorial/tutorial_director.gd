class_name TutorialDirector
extends Node
## Runs the guided tutorial from data/tutorial.json: one goal at a time, a
## tip panel at the top, an arrow over the thing to touch, and a Skip button.
## Goals listen to the same EventBus signals the game already emits, so the
## tutorial never needs special code paths in the systems it teaches.

signal step_changed(index: int)
signal finished
signal skip_pressed

const PANEL_TOP: float = 92.0

var world: World
var selection: SelectionController
var player_id: int = 0
var steps: Array = []
var index: int = -1
var done: bool = false

var _progress: float = 0.0
var _move_start: Dictionary = {}  # Unit -> Vector2
var _enemies: Array[Unit] = []
var _panel: PanelContainer
var _title: Label
var _tip: Label
var _count: Label
var _skip: Button
var _arrow: TutorialArrow


func setup(p_world: World, p_selection: SelectionController, hud_layer: Node) -> void:
	world = p_world
	selection = p_selection
	steps = DataLoader.get_table("tutorial").get("steps", [])
	_build_panel(hud_layer)
	_arrow = TutorialArrow.new()
	world.add_child(_arrow)
	EventBus.resources_delivered.connect(_on_delivered)
	EventBus.building_completed.connect(_on_building_completed)
	EventBus.unit_trained.connect(_on_unit_trained)
	_go(0)


func current() -> Dictionary:
	return steps[index] if index >= 0 and index < steps.size() else {}


func _go(i: int) -> void:
	index = i
	_progress = 0.0
	_move_start.clear()
	if index >= steps.size():
		_finish()
		return
	var step: Dictionary = current()
	_title.text = tr(String(step.get("title_key", "")))
	_tip.text = tr(String(step.get("tip_key", "")))
	_count.text = tr("TUT_MISSION") % [int(step.get("mission", 1)), int(DataLoader.get_table("tutorial").get("missions", 5))]
	_fit_panel.call_deferred()
	if String(step.get("goal", "")) == "enemies_dead":
		_spawn_fight(step)
	if i > 0:
		Sfx.play("build_done")
	step_changed.emit(index)


func _finish() -> void:
	done = true
	_title.text = tr("TUT_5_TITLE") if steps.is_empty() else tr(String(Dictionary(steps[steps.size() - 1]).get("title_key", "")))
	_tip.text = tr("TUT_DONE")
	_count.text = ""
	_skip.text = tr("TUT_FINISH")
	_arrow.target = Vector2.INF
	_fit_panel.call_deferred()
	Sfx.play("victory")
	finished.emit()


func _physics_process(_delta: float) -> void:
	if world == null or done or index < 0:
		return
	var step: Dictionary = current()
	match String(step.get("goal", "")):
		"select":
			for u: Unit in selection.selected:
				if u.owner_id == player_id and u.unit_type == String(step.get("unit", "villager")):
					_go(index + 1)
					return
		"move":
			for u: Unit in selection.selected:
				if not _move_start.has(u):
					_move_start[u] = u.position
				elif u.position.distance_to(_move_start[u]) >= float(step.get("distance_px", 160)):
					_go(index + 1)
					return
		"enemies_dead":
			if _enemies.all(func(e: Unit) -> bool: return not is_instance_valid(e) or e.is_dead or not world.units.has(e) or e.owner_id != 1):
				_go(index + 1)
				return
	_arrow.target = _arrow_target(String(step.get("arrow", "none")))


func _on_delivered(p: int, resource: String, amount: int) -> void:
	var step: Dictionary = current()
	if p == player_id and String(step.get("goal", "")) == "delivered" and resource == String(step.get("resource", "food")):
		_progress += amount
		if _progress >= float(step.get("amount", 10)):
			_go(index + 1)


func _on_building_completed(b: Building) -> void:
	var step: Dictionary = current()
	if b.owner_id == player_id and String(step.get("goal", "")) == "building_completed" and b.building_type == String(step.get("building", "house")):
		_go(index + 1)


func _on_unit_trained(u: Unit, _b: Building) -> void:
	var step: Dictionary = current()
	if u.owner_id == player_id and String(step.get("goal", "")) == "unit_trained" and u.unit_type == String(step.get("unit", "villager")):
		_go(index + 1)


## Mission 5: a squad for the player and a small band of raiders nearby.
func _spawn_fight(step: Dictionary) -> void:
	var tc: Building = _own_tc()
	var home: Vector2 = tc.position if tc != null else world.map_size_px * 0.5
	var off: Array = step.get("enemy_offset_cells", [10, 8])
	var own_spot: Vector2 = world.find_open_area(home + Vector2(float(off[0]), float(off[1])) * world.tile_size * 0.4, 2)
	var foe_spot: Vector2 = world.find_open_area(home + Vector2(float(off[0]), float(off[1])) * world.tile_size, 2)
	var own: Dictionary = step.get("spawn_own", {})
	for type_id: String in own.keys():
		for k: int in int(own[type_id]):
			world.spawn_unit(type_id, player_id, own_spot + Vector2((k % 2) * 34.0, (k / 2) * 34.0))
	var foes: Dictionary = step.get("spawn_enemy", {})
	_enemies.clear()
	for type_id: String in foes.keys():
		for k: int in int(foes[type_id]):
			var e: Unit = world.spawn_unit(type_id, 1, foe_spot + Vector2((k % 2) * 34.0, (k / 2) * 34.0))
			_enemies.append(e)


func enemies() -> Array[Unit]:
	return _enemies


func _arrow_target(kind: String) -> Vector2:
	match kind:
		"own_villager":
			for u: Unit in world.units:
				if u.owner_id == player_id and u.can_gather() and not u.is_dead:
					return u.position
		"berries":
			var tc: Building = _own_tc()
			if tc != null:
				var n: ResourceNode = world.find_node_near("berries", tc.position, 2000.0)
				if n != null:
					return n.position
		"town_center":
			var tc2: Building = _own_tc()
			if tc2 != null:
				return tc2.position + Vector2(0, -tc2.rect().size.y * 0.5)
		"enemies":
			for e: Unit in _enemies:
				if is_instance_valid(e) and not e.is_dead:
					return e.position
	return Vector2.INF


func _own_tc() -> Building:
	for b: Building in world.buildings:
		if b.owner_id == player_id and b.building_type == "town_center":
			return b
	return null


func _build_panel(layer: Node) -> void:
	_panel = PanelContainer.new()
	_panel.name = "TutorialPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.custom_minimum_size = Vector2(680, 0)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_tip = Label.new()
	_tip.add_theme_font_size_override("font_size", 18)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(656, 0)
	var row: HBoxContainer = HBoxContainer.new()
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 16)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skip = Button.new()
	_skip.text = tr("TUT_SKIP")
	_skip.custom_minimum_size = Vector2(170, 64)
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		skip_pressed.emit())
	row.add_child(_count)
	row.add_child(_skip)
	box.add_child(_title)
	box.add_child(_tip)
	box.add_child(row)
	margin.add_child(box)
	_panel.add_child(margin)
	layer.add_child(_panel)
	_fit_panel()
	if OS.is_debug_build():
		_log_skip.call_deferred()


## Shrink-wrap the panel to the current text (tips have different lengths)
## and keep it just under the top resource bar.
func _fit_panel() -> void:
	if _panel == null:
		return
	_panel.size = Vector2.ZERO
	_panel.reset_size()
	_panel.position = Vector2((1280.0 - _panel.size.x) * 0.5, PANEL_TOP)


func _log_skip() -> void:
	await get_tree().process_frame
	var c: Vector2 = _skip.get_global_rect().get_center()
	print("[REALM] hud btn %s=(%d,%d)" % [_skip.text, int(c.x), int(c.y)])
