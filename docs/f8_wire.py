import os, sys, json
os.chdir(sys.argv[1])

def edit(p, pairs, append=None):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        if a not in s:
            raise SystemExit("missing in %s: %r" % (p, a[:80]))
        s = s.replace(a, b)
    if append:
        s = s.rstrip('\n') + '\n' + append
    open(p, 'w', encoding='utf-8', newline='\n').write(s)

def jload(p): return json.load(open(p, encoding='utf-8'))
def jdump(p, d):
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(d, indent='\t', ensure_ascii=False) + '\n')

# ---------------- data
r = jload('data/rules.json')
r['save'] = {"autosave_seconds": 120}
r['alerts'] = {"cooldown_s": 6.0}
r['vision']['fog'] = True
jdump('data/rules.json', r)
sc = jload('data/scenarios.json')
for k in ['stress150', 'lake50', 'battle20', 'arena', 'sandbox']:
    sc[k]['fog'] = False
jdump('data/scenarios.json', sc)
a = jload('data/audio.json')
a['sfx']['alert'] = "res://assets/placeholder/sfx/alert.wav"
jdump('data/audio.json', a)
csv = open('data/i18n/ui.csv', encoding='utf-8').read()
csv += '''MENU_CONTINUE,Continuar partida,Continue
MENU_NEW_GAME,Nueva partida,New game
MENU_TUTORIAL,Tutorial,Tutorial
MENU_RESUME,Reanudar,Resume
MENU_SAVE,Guardar partida,Save game
MENU_SAVED,Partida guardada,Game saved
MENU_QUIT,Salir al menú,Quit to menu
ALERT_UNDER_ATTACK,¡Te atacan!,Under attack!
HUD_GROUP_HINT,Mantén para asignar,Hold to assign
'''
open('data/i18n/ui.csv', 'w', encoding='utf-8', newline='\n').write(csv)

# ---------------- GameState.launch
edit('autoload/game_state.gd', [('''## player_id -> { tech_id: true }
var researched: Dictionary = {}''', '''## player_id -> { tech_id: true }
var researched: Dictionary = {}
## Set by the main menu before loading the match scene:
## {"scenario": id, "ai": {"1": "normal"}} or {"load": slot}. Consumed once.
var launch: Dictionary = {}''')])

# ---------------- SaveManager: whole-match payloads
edit('autoload/save_manager.gd', [], append='''

## Saves an arbitrary match snapshot (SaveGame.snapshot) into a slot.
func save_payload(slot: String, payload: Dictionary) -> Error:
	var wrapped: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"saved_unix": Time.get_unix_time_from_system(),
		"match": payload,
	}
	var file: FileAccess = FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(wrapped))
	file.close()
	return OK


## The match snapshot stored in a slot, or {} if missing/corrupt.
func load_payload(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path(slot))) != OK or not (json.data is Dictionary):
		return {}
	return Dictionary(json.data).get("match", {})


## Most recent match slot ("auto" or "manual"), or "" if none.
func latest_slot() -> String:
	var best: String = ""
	var best_t: float = -1.0
	for slot: String in ["auto", "manual"]:
		if not has_save(slot):
			continue
		var json: JSON = JSON.new()
		if json.parse(FileAccess.get_file_as_string(save_path(slot))) != OK or not (json.data is Dictionary):
			continue
		var data: Dictionary = json.data
		if not data.has("match"):
			continue
		var t: float = float(data.get("saved_unix", 0.0))
		if t > best_t:
			best_t = t
			best = slot
	return best
''')

# ---------------- EventBus: attacks
edit('autoload/event_bus.gd', [], append='''## Something of `player_id` was hit by an enemy at `world_pos` (alerts).
signal under_attack(player_id: int, world_pos: Vector2)
''')
edit('scenes/units/unit.gd', [('''	hp = maxi(0, hp - maxi(1, amount))
	if source != null and is_instance_valid(source):
		last_attacker = source''', '''	hp = maxi(0, hp - maxi(1, amount))
	if source != null and is_instance_valid(source):
		last_attacker = source
		if owner_id >= 0 and source.owner_id >= 0 and source.owner_id != owner_id:
			EventBus.under_attack.emit(owner_id, position)''')])
edit('scenes/buildings/building.gd', [('''func take_damage(amount: int, _source: Unit) -> void:
	hp = maxi(0, hp - maxi(1, amount))''', '''func take_damage(amount: int, source: Unit) -> void:
	hp = maxi(0, hp - maxi(1, amount))
	if source != null and is_instance_valid(source) and owner_id >= 0 and source.owner_id >= 0 and source.owner_id != owner_id:
		EventBus.under_attack.emit(owner_id, position)''')])

# ---------------- World: terrain apply for loads, tree dict
edit('scenes/main/world.gd', [('''func _block_is_grass(center: Vector2i, margin: int) -> bool:''', '''## Saved tree amounts (cell key -> wood left), for SaveGame.
func tree_amounts_dict() -> Dictionary:
	var out: Dictionary = {}
	for key: int in _tree_amount.keys():
		out[str(key)] = _tree_amount[key]
	return out


## Applies a saved terrain grid (trees cut since the map was generated) and
## the partial tree amounts. Cells that became grass are freed for paths.
func apply_terrain(saved: PackedByteArray, trees: Dictionary) -> void:
	if saved.size() == terrain_grid.size():
		for i: int in saved.size():
			if saved[i] != terrain_grid[i]:
				terrain_grid[i] = saved[i]
				var cell: Vector2i = Vector2i(i % map_width, i / map_width)
				terrain_layer.set_cell(cell, TERRAIN_SOURCE_ID, Vector2i(saved[i], 0))
				nav.set_terrain_walkable(cell, saved[i] != _forest_id)
	_tree_amount.clear()
	for key: Variant in trees.keys():
		_tree_amount[int(key)] = float(trees[key])
	nav.consume_changes()


func _block_is_grass(center: Vector2i, margin: int) -> bool:''')])

# ---------------- Vision: hide what the human cannot see; fog layer refresh
edit('systems/fog/vision_system.gd', [('''var world: World
var grid: VisionGrid = VisionGrid.new()''', '''var world: World
var grid: VisionGrid = VisionGrid.new()
## Fog drawn for the human (null = no fog, e.g. benchmarks and tests).
var fog_layer: FogLayer = null
var fog_enabled: bool = true'''),
('''	grid.update(sources)
	last_update_usec = Time.get_ticks_usec() - t0''', '''	grid.update(sources)
	if fog_enabled:
		_apply_visibility()
		if fog_layer != null:
			fog_layer.refresh()
	last_update_usec = Time.get_ticks_usec() - t0


## Enemy and wild units, and enemy buildings, are drawn only while the human
## sees them; resources show once explored. Own things are always drawn.
func _apply_visibility() -> void:
	var me: int = GameState.PLAYER_HUMAN
	for u: Unit in world.units:
		u.visible = u.owner_id == me or grid.is_visible(me, u.position)
	for b: Building in world.buildings:
		b.visible = b.owner_id == me or grid.is_visible(me, b.position)
	for n: ResourceNode in world.resource_nodes:
		n.visible = grid.is_explored(me, n.position)''')])

# ---------------- Selection: control groups
edit('systems/selection/selection_controller.gd', [('''var selected: Array[Unit] = []
var selected_building: Building = null''', '''var selected: Array[Unit] = []
var selected_building: Building = null
## Control groups 1-5: number -> Array[Unit]
var groups: Dictionary = {}'''),
('''func clear_selection() -> void:''', '''## Saves the current unit selection as group `n` (1-5).
func assign_group(n: int) -> void:
	_prune()
	groups[n] = selected.duplicate()
	Sfx.play("order_stop")
	_trace("group_assign_%d" % n, Vector2.ZERO)


## Selects group `n`; selecting it again while already selected centres the camera.
func recall_group(n: int) -> void:
	var members: Array = groups.get(n, [])
	var alive: Array[Unit] = []
	for u: Variant in members:
		if is_instance_valid(u) and world.units.has(u):
			alive.append(u)
	groups[n] = alive
	if alive.is_empty():
		return
	var same: bool = alive.size() == selected.size() and alive.all(func(u: Unit) -> bool: return selected.has(u))
	set_selection(alive)
	Sfx.play("select")
	if same:
		var pos: Array[Vector2] = []
		for u: Unit in alive:
			pos.append(u.position)
		camera.center_on_smooth(Formation.centroid(pos))
	_trace("group_recall_%d" % n, Vector2.ZERO)


func clear_selection() -> void:''')])

# ---------------- HUD: minimap, groups, menu
edit('scenes/ui/hud.gd', [('signal research_pressed(item: String)\n', '''signal research_pressed(item: String)
signal group_pressed(n: int)
signal group_held(n: int)
signal menu_save_pressed
signal menu_quit_pressed
'''),
('''var era_label: Label
var banner: Label''', '''var era_label: Label
var banner: Label
var minimap: Minimap
var group_buttons: Array[Button] = []
var menu_button: Button
var pause_panel: PanelContainer = null
var _group_down_ms: Dictionary = {}
var _last_alert_ms: int = -100000
const GROUP_HOLD_MS: int = 500'''),
('''	EventBus.era_changed.connect(_on_era_changed)
	box_rect.visible = false''', '''	EventBus.era_changed.connect(_on_era_changed)
	_build_minimap()
	_build_groups()
	_build_menu_button()
	box_rect.visible = false'''),
('''func is_point_over_ui(screen_pos: Vector2) -> bool:
	if end_panel != null:
		return true''', '''func is_point_over_ui(screen_pos: Vector2) -> bool:
	if end_panel != null or pause_panel != null:
		return true
	if minimap != null and minimap.visible and minimap.get_global_rect().grow(4.0).has_point(screen_pos):
		return true
	if menu_button != null and menu_button.get_global_rect().has_point(screen_pos):
		return true
	for b: Button in group_buttons:
		if b.get_global_rect().has_point(screen_pos):
			return true'''),
], append='''

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
		group_buttons[n - 1].text = str(n) if count == 0 else "%d\\n%d" % [n, count]


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
	for entry: Array in [["MENU_RESUME", close_pause_menu], ["MENU_SAVE", func() -> void: menu_save_pressed.emit()], ["MENU_QUIT", func() -> void: menu_quit_pressed.emit()]]:
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
''')

# ---------------- Main: launch params, load, autosave, groups, menu, fog
edit('scenes/main/main.gd', [
('''var ais: Array[AIController] = []''', '''var ais: Array[AIController] = []
## Tests / menu: a SaveGame snapshot to load instead of running the scenario.
var load_data: Dictionary = {}
var scenario_id: String = ""
var _autosave_timer: float = 0.0'''),
('''func _ready() -> void:
	var scenario_id: String = _resolve_scenario()
	var def: Dictionary = DataLoader.get_entry("scenarios", scenario_id)''', '''func _ready() -> void:
	_consume_launch()
	scenario_id = _resolve_scenario()
	var def: Dictionary = DataLoader.get_entry("scenarios", scenario_id)'''),
('''	runner.start(scenario_id, world, camera)
	world.vision.refresh()''', '''	world.vision.fog_enabled = bool(def.get("fog", DataLoader.rule("vision", "fog", true)))
	if world.vision.fog_enabled:
		var fog: FogLayer = FogLayer.new()
		world.add_child(fog)
		fog.setup(world.vision.grid, world.map_size_px)
		world.vision.fog_layer = fog
	if load_data.is_empty():
		runner.start(scenario_id, world, camera)
	else:
		SaveGame.restore(self, load_data)
	world.vision.refresh()
	hud.minimap.setup(world, camera)
	hud.minimap.jump_to.connect(func(p: Vector2) -> void: camera.center_on(p))
	hud.group_pressed.connect(func(n: int) -> void:
		selection.recall_group(n)
		hud.set_group_count(n, Array(selection.groups.get(n, [])).size()))
	hud.group_held.connect(func(n: int) -> void:
		selection.assign_group(n)
		hud.set_group_count(n, Array(selection.groups.get(n, [])).size()))
	hud.menu_save_pressed.connect(func() -> void:
		save_match("manual")
		hud.close_pause_menu()
		hud.show_banner(tr("MENU_SAVED")))
	hud.menu_quit_pressed.connect(_quit_to_menu)'''),
('''		ai.setup(world, int(key), String(ai_players[key]), ai_seed + int(key) * 101)
		ais.append(ai)''', '''		ai.setup(world, int(key), String(ai_players[key]), ai_seed + int(key) * 101)
		ais.append(ai)
	if not load_data.is_empty():
		SaveGame.restore_ais(self, load_data)'''),
('''func _resolve_scenario() -> String:
	if scenario != "":
		return scenario''', '''## Menu choices (GameState.launch): scenario + AI, or a save slot to load.
func _consume_launch() -> void:
	var launch: Dictionary = GameState.launch
	GameState.launch = {}
	if launch.has("load"):
		var data: Dictionary = SaveManager.load_payload(String(launch["load"]))
		if not data.is_empty():
			load_data = data
			scenario = String(data.get("scenario", "skirmish"))
			var ai_list: Dictionary = {}
			for a: Variant in data.get("ais", []):
				ai_list[int(a["player"])] = String(a["difficulty"])
			ai_override = ai_list
	elif launch.has("scenario"):
		scenario = String(launch["scenario"])
		for key: Variant in Dictionary(launch.get("ai", {})).keys():
			ai_override[int(key)] = String(launch["ai"][key])


func _resolve_scenario() -> String:
	if scenario != "":
		return scenario'''),
], append='''

func _physics_process(delta: float) -> void:
	if rules == null or rules.ended or ais.is_empty():
		return
	_autosave_timer += delta
	if _autosave_timer >= float(DataLoader.rule("save", "autosave_seconds", 120)):
		_autosave_timer = 0.0
		save_match("auto")


func save_match(slot: String) -> Error:
	var err: Error = SaveManager.save_payload(slot, SaveGame.snapshot(self))
	if OS.is_debug_build():
		print("[REALM] saved slot=%s err=%d" % [slot, err])
	return err


func _quit_to_menu() -> void:
	get_tree().paused = false
	if not rules.ended and not ais.is_empty():
		save_match("auto")
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
''')
edit('project.godot', [('run/main_scene="res://scenes/main/main.tscn"', 'run/main_scene="res://scenes/ui/main_menu.tscn"')])
print("f8 wired")
