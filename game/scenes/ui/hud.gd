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
signal retry_pressed
signal research_pressed(item: String)
signal sell_pressed(resource: String)
signal group_pressed(n: int)
signal group_held(n: int)
signal menu_save_pressed
signal menu_quit_pressed
signal menu_resign_pressed

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
## Set by Main: lists the techs a building offers and why one is unavailable.
var tech: TechSystem = null
var era_label: Label
var banner: Label
var minimap: Minimap
var group_buttons: Array[Button] = []
var menu_button: Button
var speed_button: Button
var queue_row: HBoxContainer
## Main sets this when there is a real match to give up (not sandbox/tutorial).
var can_resign: bool = false
var pause_panel: PanelContainer = null
var _group_down_ms: Dictionary = {}
var _last_alert_ms: int = -100000
const GROUP_HOLD_MS: int = 500
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
var end_panel: PanelContainer = null


func _ready() -> void:
	idle_button.pressed.connect(_emit_click.bind(idle_pressed))
	_build_resource_row()
	era_label = Label.new()
	era_label.custom_minimum_size = Vector2(150, 0)
	pop_label.get_parent().add_child(era_label)
	pop_label.get_parent().move_child(era_label, pop_label.get_index() + 1)
	banner = Label.new()
	banner.add_theme_font_size_override("font_size", 40)
	banner.add_theme_color_override("font_color", Color(1, 0.88, 0.45))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	banner.add_theme_constant_override("outline_size", 8)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(0, 120)
	banner.visible = false
	add_child(banner)
	EventBus.era_changed.connect(_on_era_changed)
	EventBus.building_completed.connect(func(b: Building) -> void:
		if b.owner_id == player_id:
			Sfx.play("build_done"))
	EventBus.unit_trained.connect(func(u: Unit, _b: Building) -> void:
		if u.owner_id == player_id:
			Sfx.play("unit_ready"))
	EventBus.tech_researched.connect(func(p: int, _id: String) -> void:
		if p == player_id:
			Sfx.play("research_done"))
	_build_minimap()
	_build_groups()
	_build_menu_button()
	box_rect.visible = false
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.population_changed.connect(_on_population_changed)
	_set_mode(Mode.NONE)
	refresh_all()


func refresh_all() -> void:
	for res: String in RESOURCE_ORDER:
		_on_resource_changed(player_id, res, GameState.get_resource(player_id, res))
	_on_population_changed(player_id, GameState.pop_used(player_id), GameState.pop_cap(player_id))
	_refresh_era()


func _refresh_era() -> void:
	if era_label != null:
		var era: int = GameState.era_of(player_id)
		era_label.text = "%s %s" % ["I II III IV".split(" ")[clampi(era - 1, 0, 3)], tr(String(DataLoader.get_entry("eras", str(era)).get("name_key", "")))]


func _on_era_changed(p: int, era: int) -> void:
	if p != player_id:
		return
	_refresh_era()
	show_banner("%s: %s" % [tr("ERA_REACHED"), tr(String(DataLoader.get_entry("eras", str(era)).get("name_key", "")))])
	Sfx.play("era_up")
	if mode == Mode.BUILDING:
		_set_mode(Mode.BUILDING)


## Big centred message that fades out after a few seconds (new era...).
func show_banner(text: String) -> void:
	banner.text = text
	banner.visible = true
	banner.modulate = Color.WHITE
	banner.size = Vector2(get_viewport().get_visible_rect().size.x, 60)
	banner.position = Vector2(0, 110)
	var tw: Tween = create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(banner, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: banner.visible = false)


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
		_line_text = ""
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
	if end_panel != null or pause_panel != null:
		return true
	if minimap != null and minimap.visible and minimap.get_global_rect().grow(4.0).has_point(screen_pos):
		return true
	if menu_button != null and menu_button.get_global_rect().has_point(screen_pos):
		return true
	if speed_button != null and speed_button.get_global_rect().has_point(screen_pos):
		return true
	# The tutorial panel (tips + Skip) is added to the HUD by TutorialDirector.
	var tut: Control = get_node_or_null("TutorialPanel") as Control
	if tut != null and tut.visible and tut.get_global_rect().has_point(screen_pos):
		return true
	for b: Button in group_buttons:
		if b.get_global_rect().has_point(screen_pos):
			return true
	if selection_panel.visible and selection_panel.get_global_rect().has_point(screen_pos):
		return true
	return top_bar.get_global_rect().has_point(screen_pos)


# ------------------------------------------------------------------ panel modes

func _set_mode(m: Mode) -> void:
	var was_visible: bool = selection_panel.visible
	mode = m
	if queue_row != null and m != Mode.BUILDING:
		queue_row.visible = false
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
		var plural_key: String = name_key.replace("_NAME", "_PLURAL")
		var shown: String = tr(name_key)
		if int(counts[type_id]) > 1 and tr(plural_key) != plural_key:
			shown = tr(plural_key)
		parts.append("%d %s" % [counts[type_id], shown])
	selection_label.text = ", ".join(parts)
	if _units.size() == 1 and is_instance_valid(_units[0]):
		selection_label.text += "\n" + unit_stats_text(_units[0])
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
		var b: Button = _add_cost_button(tr(String(def.get("name_key", type_id))), def.get("cost", {}), Vector2(150, 76))
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


## Line mode (walls): "tap where it ends (n segments)" + total cost.
var _line_text: String = ""


func show_line(anchored: bool, count: int, cost: Dictionary) -> void:
	if not anchored:
		_line_text = tr("HUD_WALL_START")
	else:
		_line_text = tr("HUD_WALL_LINE") % count
		if count > 0:
			_line_text += "  " + cost_text(cost)
	if mode == Mode.PLACING:
		_refresh_placing()


func _refresh_placing() -> void:
	match _place_error:
		"line":
			selection_label.text = _line_text
		"":
			selection_label.text = _line_text if _line_text != "" else tr("HUD_BUILD")
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
			if int(def.get("era", 1)) > GameState.era_of(player_id) or not ConstructionSystem.unit_allowed(player_id, String(type_id)):
				continue
			var b: Button = _add_cost_button(tr(String(def.get("name_key", type_id))), def.get("cost", {}), Vector2(150, 76))
			var id: String = String(type_id)
			b.pressed.connect(func() -> void:
				Sfx.play("ui_click")
				train_pressed.emit(id))
			type_buttons[id] = b
		if tech != null:
			if _building.building_type == String(DataLoader.get_entry("eras", "_rules").get("researched_at", "town_center")):
				var next: int = GameState.era_of(player_id) + 1
				if not DataLoader.get_entry("eras", str(next)).is_empty():
					_add_research_button(TechSystem.era_item(next), "%s %s" % [tr("ERA_ADVANCE"), tr(String(DataLoader.get_entry("eras", str(next)).get("name_key", "")))])
			for id: String in tech.techs_at(_building):
				_add_research_button(TechSystem.PREFIX + id, tr(String(DataLoader.get_entry("techs", id).get("name_key", id))))
		var market: Dictionary = _building.data.get("market", {})
		for res: Variant in market.get("sells", []):
			_add_sell_button(String(res))
		if not _building.queue.is_empty():
			_add_button(tr("HUD_REMOVE"), dequeue_pressed)
	deselect_button = _add_button(tr("HUD_DESELECT"), deselect_pressed)
	_refresh_building()


## "Vender" with [res icon] 100 -> [gold icon] price underneath.
func _add_sell_button(res: String) -> void:
	var lot: int = int(DataLoader.rule("market", "lot", 100))
	var price: int = tech.world.economy.market_price(player_id, res) if tech != null and tech.world != null else int(DataLoader.rule("market", "start_price", 70))
	var b: Button = _add_cost_button(tr("HUD_SELL"), {res: lot}, Vector2(170, 76))
	b.tooltip_text = tr("HUD_MARKET_HINT")
	var row: HBoxContainer = b.get_node("Cost")
	var arrow: Label = Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", 17)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gold_icon: TextureRect = TextureRect.new()
	gold_icon.texture = PlaceholderArt.icon_texture("gold")
	gold_icon.custom_minimum_size = Vector2(22, 22)
	gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gain: Label = Label.new()
	gain.text = str(price)
	gain.add_theme_font_size_override("font_size", 17)
	gain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	row.add_child(gold_icon)
	row.add_child(gain)
	b.disabled = GameState.get_resource(player_id, res) < lot
	b.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		sell_pressed.emit(res))
	type_buttons["sell:" + res] = b


func _add_research_button(item: String, title: String) -> void:
	var b: Button = _add_cost_button(title, TechSystem.item_cost(item), Vector2(170, 76))
	var def: Dictionary = TechSystem.item_def(item)
	if def.has("desc_key"):
		b.tooltip_text = tr(String(def["desc_key"]))
	b.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		research_pressed.emit(item))
	type_buttons[item] = b


func _refresh_building() -> void:
	if _building == null or not is_instance_valid(_building):
		return
	var text: String = "%s  %d/%d" % [tr(String(_building.data.get("name_key", _building.building_type))), _building.hp, _building.max_hp]
	if not _building.is_complete():
		text += "  %s %d%%" % [tr("HUD_UNDER_CONSTRUCTION"), int(_building.build_progress * 100.0)]
	elif not _building.gather_info().is_empty():
		text += "  (%d/%d)" % [_building.workers.size(), int(_building.gather_info().get("workers", 1))]
	_refresh_queue_row()
	if not _building.queue.is_empty():
		text += "\n%s: %d%%" % [tr("HUD_QUEUE"), int(_building.train_progress() * 100.0)]
		if _building.blocked_by_pop:
			text += "  " + tr("HUD_POP_FULL")
	selection_label.text = text


## The production queue as little portraits (unit idle frames from the atlas;
## research shows the tech's short name) instead of letters like "Q Q Q".
func _refresh_queue_row() -> void:
	if queue_row == null:
		queue_row = HBoxContainer.new()
		queue_row.name = "QueueRow"
		queue_row.add_theme_constant_override("separation", 4)
		selection_label.get_parent().add_child(queue_row)
		selection_label.get_parent().move_child(queue_row, selection_label.get_index() + 1)
	for child: Node in queue_row.get_children():
		queue_row.remove_child(child)
		child.queue_free()
	if _building == null or not is_instance_valid(_building) or _building.queue.is_empty():
		queue_row.visible = false
		return
	queue_row.visible = true
	for i: int in _building.queue.size():
		var id: String = _building.queue[i]
		if TechSystem.is_research(id):
			var l: Label = Label.new()
			var def: Dictionary = TechSystem.item_def(id)
			l.text = tr(String(def.get("name_key", id)))
			l.add_theme_font_size_override("font_size", 15)
			l.custom_minimum_size = Vector2(0, 36)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			queue_row.add_child(l)
			continue
		var pic: TextureRect = TextureRect.new()
		var at: AtlasTexture = AtlasTexture.new()
		at.atlas = PlaceholderArt.texture()
		at.region = PlaceholderArt.unit_frame(id, player_id, "idle")
		pic.texture = at
		pic.custom_minimum_size = Vector2(36, 36)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.modulate = Color.WHITE if i == 0 else Color(1, 1, 1, 0.6)
		pic.tooltip_text = tr(String(DataLoader.get_entry("units", id).get("name_key", id)))
		queue_row.add_child(pic)
	for id: String in type_buttons.keys():
		var btn: Button = type_buttons[id]
		if TechSystem.is_research(id):
			btn.disabled = tech == null or tech.research_error(_building, id) != ""
		else:
			btn.disabled = not GameState.can_afford(player_id, TechSystem.item_cost(id))


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


## A button with the name on top and the cost as resource icons + numbers
## underneath (the same icons as the top bar), instead of letters.
func _add_cost_button(title: String, cost: Dictionary, size: Vector2) -> Button:
	var b: Button = _add_button(title + "\n ", Signal(), size)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Cost"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	for res: String in RESOURCE_ORDER:
		if not cost.has(res) or int(cost[res]) <= 0:
			continue
		var icon: TextureRect = TextureRect.new()
		icon.texture = PlaceholderArt.icon_texture(res)
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var amount: Label = Label.new()
		amount.text = str(int(cost[res]))
		amount.add_theme_font_size_override("font_size", 17)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		row.add_child(amount)
	b.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 6)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Unaffordable buttons dim their cost too.
	b.draw.connect(func() -> void: row.modulate.a = 0.45 if b.disabled else 1.0)
	return b


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
		# Icon from the shared atlas (same texture as the map: no extra draw call).
		var chip: TextureRect = TextureRect.new()
		chip.texture = PlaceholderArt.icon_texture(res)
		chip.custom_minimum_size = Vector2(28, 28)
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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


## End of match: big result, a few stats for both sides, and Retry.
func show_end(won: bool, seconds: float, mine: Dictionary, theirs: Dictionary) -> void:
	if end_panel != null:
		return
	set_speed(1.0)
	_set_mode(Mode.NONE)
	Music.stop()
	Sfx.play("victory" if won else "defeat")
	end_panel = PanelContainer.new()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.theme = selection_panel.theme
	end_panel.add_theme_stylebox_override("panel", selection_panel.get_theme_stylebox("panel"))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_child(box)
	end_panel.add_child(margin)
	var title: Label = Label.new()
	title.text = tr("END_VICTORY") if won else tr("END_DEFEAT")
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.35) if won else Color(1, 0.45, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var dur: Label = Label.new()
	dur.text = "%s %d:%02d" % [tr("END_TIME"), int(seconds) / 60, int(seconds) % 60]
	dur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(dur)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	for cell: String in ["", tr("END_YOU"), tr("END_AI")]:
		grid.add_child(_stat_label(cell))
	var rows: Array = [["END_GATHERED", _sum_gathered(mine), _sum_gathered(theirs)],
		["END_TRAINED", int(mine.get("trained", 0)), int(theirs.get("trained", 0))],
		["END_KILLS", int(mine.get("kills", 0)), int(theirs.get("kills", 0))],
		["END_LOST", int(mine.get("lost", 0)), int(theirs.get("lost", 0))]]
	for row: Array in rows:
		grid.add_child(_stat_label(tr(String(row[0]))))
		grid.add_child(_stat_label(str(row[1])))
		grid.add_child(_stat_label(str(row[2])))
	box.add_child(grid)
	var retry: Button = Button.new()
	retry.text = tr("END_RETRY")
	retry.custom_minimum_size = Vector2(220, 80)
	retry.focus_mode = Control.FOCUS_NONE
	retry.pressed.connect(_emit_click.bind(retry_pressed))
	box.add_child(retry)
	add_child(end_panel)
	end_panel.reset_size()
	end_panel.position = (end_panel.get_viewport_rect().size - end_panel.size) * 0.5


func _stat_label(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	return l


static func _sum_gathered(stats: Dictionary) -> int:
	var total: int = 0
	for v: Variant in Dictionary(stats.get("gathered", {})).values():
		total += int(v)
	return total


## "ATQ 7  ARM 1/3  ALC 352  VEL 96" for one unit, techs included.
static func unit_stats_text(u: Unit) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var attack: Dictionary = u.data.get("combat", {})
	if not attack.is_empty():
		var base: int = 0
		for v: Variant in Dictionary(attack.get("damage", {})).values():
			base += int(v)
		parts.append("%s %d" % [TranslationServer.translate("STAT_ATTACK"), base + Combat.attack_bonus_of(u)])
	var armor: Dictionary = Combat.armor_of(u)
	parts.append("%s %d/%d" % [TranslationServer.translate("STAT_ARMOR"), int(armor.get("hack", 0)), int(armor.get("pierce", 0))])
	if float(attack.get("range_px", 0.0)) > 0.0:
		parts.append("%s %d" % [TranslationServer.translate("STAT_RANGE"), int(Combat.range_of(u))])
	parts.append("%s %d" % [TranslationServer.translate("STAT_SPEED"), int(u.speed_px)])
	parts.append("%s %d/%d" % [TranslationServer.translate("STAT_HP"), u.hp, u.max_hp])
	return "   ".join(parts)


# ------------------------------------------------------------------ F8: minimap, groups, menu

func _build_minimap() -> void:
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(200, 200)
	minimap.size = Vector2(200, 200)
	minimap.position = Vector2(12, get_viewport().get_visible_rect().size.y - 212 - 40)
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	minimap.offset_left = 12
	minimap.offset_right = 212
	minimap.offset_top = -252
	minimap.offset_bottom = -52
	add_child(minimap)
	EventBus.under_attack.connect(_on_under_attack)


func _on_under_attack(p: int, world_pos: Vector2) -> void:
	if p != player_id or minimap == null:
		return
	minimap.alert(world_pos)
	Music.combat_ping()
	var now: int = Time.get_ticks_msec()
	if now - _last_alert_ms > int(float(DataLoader.rule("alerts", "cooldown_s", 6.0)) * 1000.0):
		_last_alert_ms = now
		Sfx.play("alert")
		show_banner(tr("ALERT_UNDER_ATTACK"))


func _build_groups() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.position = Vector2(12, 92)
	for n: int in range(1, 6):
		var b: Button = Button.new()
		b.text = str(n)
		b.custom_minimum_size = Vector2(64, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = tr("HUD_GROUP_HINT")
		b.add_theme_font_size_override("font_size", 22)
		b.button_down.connect(func() -> void: _group_down_ms[n] = Time.get_ticks_msec())
		b.button_up.connect(func() -> void: _group_released(n))
		column.add_child(b)
		group_buttons.append(b)
	add_child(column)


## Short tap recalls the group; holding >= 0.5 s assigns the selection to it.
func _group_released(n: int) -> void:
	var held: int = Time.get_ticks_msec() - int(_group_down_ms.get(n, Time.get_ticks_msec()))
	if held >= GROUP_HOLD_MS:
		group_held.emit(n)
	else:
		group_pressed.emit(n)


func set_group_count(n: int, count: int) -> void:
	if n >= 1 and n <= group_buttons.size():
		group_buttons[n - 1].text = str(n) if count == 0 else "%d\n%d" % [n, count]


func _build_menu_button() -> void:
	menu_button = Button.new()
	menu_button.text = "≡"
	menu_button.custom_minimum_size = Vector2(72, 72)
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.add_theme_font_size_override("font_size", 32)
	menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_button.offset_left = -84
	menu_button.offset_right = -12
	menu_button.offset_top = 8
	menu_button.offset_bottom = 80
	menu_button.pressed.connect(open_pause_menu)
	add_child(menu_button)
	# Game speed: each tap cycles x1 -> x2 -> x3 (rules.json "speed").
	speed_button = Button.new()
	speed_button.text = "x1"
	speed_button.tooltip_text = tr("HUD_SPEED")
	speed_button.custom_minimum_size = Vector2(72, 72)
	speed_button.focus_mode = Control.FOCUS_NONE
	speed_button.add_theme_font_size_override("font_size", 26)
	speed_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	speed_button.offset_left = -164
	speed_button.offset_right = -92
	speed_button.offset_top = 8
	speed_button.offset_bottom = 80
	speed_button.pressed.connect(cycle_speed)
	add_child(speed_button)
	if OS.is_debug_build():
		_log_named.call_deferred(speed_button, "speed")


## Next game speed from rules.json speed.steps (e.g. 1, 2, 3).
func cycle_speed() -> void:
	var steps: Array = DataLoader.rule("speed", "steps", [1.0, 2.0, 3.0])
	var i: int = 0
	for k: int in steps.size():
		if is_equal_approx(float(steps[k]), Engine.time_scale):
			i = (k + 1) % steps.size()
	set_speed(float(steps[i]))
	Sfx.play("ui_click")


func set_speed(value: float) -> void:
	Engine.time_scale = value
	if speed_button != null:
		speed_button.text = "x%d" % int(round(value))


## Pause panel: Resume / Save / Quit to menu. The tree is paused while open.
func open_pause_menu() -> void:
	if pause_panel != null or end_panel != null:
		return
	Sfx.play("ui_click")
	pause_panel = PanelContainer.new()
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.theme = selection_panel.theme
	pause_panel.add_theme_stylebox_override("panel", selection_panel.get_theme_stylebox("panel"))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_child(box)
	pause_panel.add_child(margin)
	Sfx.play("ui_open")
	var entries: Array = [["MENU_RESUME", close_pause_menu], ["MENU_SAVE", func() -> void: menu_save_pressed.emit()]]
	if can_resign:
		entries.append(["MENU_RESIGN", func() -> void: menu_resign_pressed.emit()])
	entries.append(["MENU_QUIT", func() -> void: menu_quit_pressed.emit()])
	for entry: Array in entries:
		var b: Button = Button.new()
		b.text = tr(String(entry[0]))
		b.custom_minimum_size = Vector2(300, 76)
		b.focus_mode = Control.FOCUS_NONE
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		var action: Callable = entry[1]
		b.pressed.connect(func() -> void:
			Sfx.play("ui_click")
			action.call())
		box.add_child(b)
		if OS.is_debug_build():
			_log_named.call_deferred(b, b.text)
	var sound: Button = Button.new()
	sound.custom_minimum_size = Vector2(300, 76)
	sound.focus_mode = Control.FOCUS_NONE
	sound.process_mode = Node.PROCESS_MODE_ALWAYS
	sound.text = tr("MENU_SOUND_OFF") if Sfx.muted else tr("MENU_SOUND_ON")
	sound.pressed.connect(func() -> void:
		Sfx.muted = not Sfx.muted
		Music.set_muted(Sfx.muted)
		sound.text = tr("MENU_SOUND_OFF") if Sfx.muted else tr("MENU_SOUND_ON")
		Sfx.play("ui_click"))
	box.add_child(sound)
	box.move_child(sound, box.get_child_count() - 2)
	add_child(pause_panel)
	pause_panel.reset_size()
	pause_panel.position = (get_viewport().get_visible_rect().size - pause_panel.size) * 0.5
	get_tree().paused = true


func _log_named(b: Button, label: String) -> void:
	await get_tree().process_frame
	if is_instance_valid(b):
		var c: Vector2 = b.get_global_rect().get_center()
		print("[REALM] hud btn %s=(%d,%d)" % [label, int(c.x), int(c.y)])


func close_pause_menu() -> void:
	if pause_panel == null:
		return
	pause_panel.queue_free()
	pause_panel = null
	get_tree().paused = false
