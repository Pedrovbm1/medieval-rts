extends Node
## Match entry point: builds the world for a scenario and wires camera, input,
## selection and HUD together.
## Scenario: `scenario` (set before adding to the tree), else the first line of
## user://scenario.txt (debug builds, for device benchmarks), else "sandbox".

const SHOT_FILE: String = "user://shot.txt"
const SCENARIO_FILE: String = "user://scenario.txt"
const IDLE_REFRESH_SECONDS: float = 0.5

var scenario: String = ""
## Tests: force AI players, e.g. {0: "hard", 1: "normal"} (overrides the scenario).
var ai_override: Dictionary = {}
## Map chosen in the menu (or restored from a save); "" = the scenario's map.
var map_override: String = ""
## Tests: seed for AI decisions.
var ai_seed: int = 1
## "Fair AI": computer players get no hidden economic bonus (menu default).
## Tests that measure the bonus set it to false.
var fair_ai: bool = true
## Town bell state: true while villagers are sheltered because of it.
var bell_on: bool = false
var ais: Array[AIController] = []
## Tests / menu: a SaveGame snapshot to load instead of running the scenario.
var load_data: Dictionary = {}
## LAN match (NetSession): two humans, lockstep, no AI, no autosave, no speed.
var net_match: bool = false
## Seed every device shares (world RNG); tests set it to compare two runs.
var match_seed: int = 0
## Tests: fixed paths per tick (lockstep mode) even without a network.
var deterministic: bool = false
## Bell state per player (shelter / release); `bell_on` mirrors the local one.
var bell_states: Dictionary = {}
var scenario_id: String = ""
var _autosave_timer: float = 0.0
## Guided tutorial (only in scenarios with "tutorial": true).
var tutorial: TutorialDirector = null
var _idle_cycle: int = 0

@onready var world: World = $World
@onready var camera: CameraController = $CameraController
@onready var order_marker: OrderMarker = $World/OrderMarker
@onready var hud: Hud = $Hud
@onready var selection: SelectionController = $SelectionController
@onready var pointer: PointerManager = $PointerManager
@onready var runner: ScenarioRunner = $ScenarioRunner
@onready var placement: PlacementController = $World/PlacementController
@onready var rules: MatchRules = $MatchRules
@onready var bus: CommandBus = $CommandBus
@onready var lockstep: Lockstep = $Lockstep


func _ready() -> void:
	Music.play_theme("peace")
	_consume_launch()
	scenario_id = _resolve_scenario()
	var def: Dictionary = DataLoader.get_entry("scenarios", scenario_id)
	var map_id: String = map_override if map_override != "" and not DataLoader.get_map(map_override).is_empty() else String(def.get("map", "skirmish_120"))
	GameState.new_match(map_id, "northvale", "northvale")
	world.build_from_map(map_id)
	if match_seed != 0:
		world.set_match_seed(match_seed)
	if net_match or deterministic:
		world.set_deterministic(true)
	camera.set_map_bounds(Rect2(Vector2.ZERO, world.map_size_px))
	bus.setup(world, self)
	selection.bus = bus
	placement.bus = bus
	selection.setup(world, camera, order_marker)
	placement.setup(world, camera)
	pointer.setup(camera, selection, hud, placement)

	selection.selection_changed.connect(hud.show_selection)
	selection.building_selected.connect(hud.show_building)
	pointer.box_changed.connect(hud.show_box)
	hud.stop_pressed.connect(selection.order_stop)
	hud.hold_pressed.connect(selection.order_hold)
	hud.deselect_pressed.connect(selection.clear_selection)
	hud.idle_pressed.connect(_on_idle_pressed)
	hud.build_pressed.connect(hud.show_build_menu)
	hud.build_back_pressed.connect(func() -> void: hud.show_selection(selection.selected))
	hud.build_type_chosen.connect(_on_build_type_chosen)
	hud.place_confirm_pressed.connect(placement.confirm)
	hud.place_cancel_pressed.connect(placement.cancel)
	placement.state_changed.connect(hud.show_placing)
	placement.line_changed.connect(hud.show_line)
	placement.placed.connect(func(_b: Building) -> void: selection.release(placement.builders))
	hud.train_pressed.connect(_on_train_pressed)
	hud.research_pressed.connect(_on_train_pressed)
	hud.sell_pressed.connect(_on_sell_pressed)
	hud.tech = world.tech
	hud.dequeue_pressed.connect(_on_dequeue_pressed)
	hud.cancel_construction_pressed.connect(_on_cancel_construction)
	hud.camera = camera
	if hud.alert_arrow != null:
		hud.alert_arrow.camera = camera
	hud.bell_pressed.connect(ring_bell)
	hud.eject_pressed.connect(_on_eject_pressed)
	hud.economy = world.economy
	hud.buy_pressed.connect(_on_buy_pressed)
	hud.attack_move_pressed.connect(func() -> void: selection.arm_attack_move(not selection.attack_armed))
	hud.formation_pressed.connect(func() -> void: selection.cycle_formation())
	selection.attack_armed_changed.connect(hud.set_attack_armed)
	selection.formation_changed.connect(hud.set_formation)

	world.vision.fog_enabled = bool(def.get("fog", DataLoader.rule("vision", "fog", true)))
	if world.vision.fog_enabled:
		var fog: FogLayer = FogLayer.new()
		world.add_child(fog)
		fog.setup(world.vision.grid, world.map_size_px)
		world.vision.fog_layer = fog
	if load_data.is_empty():
		runner.start(scenario_id, world, camera)
	else:
		SaveGame.restore(self, load_data)
		if OS.is_debug_build():
			print("[REALM] loaded save units=%d buildings=%d" % [world.units.size(), world.buildings.size()])
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
	hud.menu_quit_pressed.connect(_quit_to_menu)
	hud.menu_resign_pressed.connect(func() -> void:
		hud.close_pause_menu()
		bus.submit({"type": "resign", "player": GameState.PLAYER_HUMAN}))
	rules.setup(world)
	hud.can_resign = rules.contenders.has(GameState.PLAYER_HUMAN) and tutorial == null
	rules.match_ended.connect(_on_match_ended)
	hud.retry_pressed.connect(_on_retry)
	var ai_players: Dictionary = ai_override if not ai_override.is_empty() else Dictionary(def.get("ai", {}))
	if net_match:
		ai_players = {}  # two humans; the lockstep layer replaces the AI seat
		_setup_lockstep()
	for key: Variant in ai_players.keys():
		var ai: AIController = AIController.new()
		add_child(ai)
		ai.setup(world, int(key), String(ai_players[key]), ai_seed + int(key) * 101, fair_ai)
		ai.resigned.connect(rules.resign)
		ais.append(ai)
	if not load_data.is_empty():
		SaveGame.restore_ais(self, load_data)
	if bool(def.get("tutorial", false)) and load_data.is_empty():
		tutorial = TutorialDirector.new()
		tutorial.name = "Tutorial"
		add_child(tutorial)
		tutorial.setup(world, selection, hud)
		tutorial.skip_pressed.connect(_quit_to_menu)
	world.economy.refresh_population()
	hud.refresh_all()
	var idle_timer: Timer = Timer.new()
	idle_timer.wait_time = IDLE_REFRESH_SECONDS
	idle_timer.autostart = true
	idle_timer.timeout.connect(_refresh_idle)
	add_child(idle_timer)
	_refresh_idle()
	if OS.is_debug_build() and FileAccess.file_exists(SHOT_FILE):
		# Dev aid: "user://shot.txt" holds seconds; then a screenshot is saved.
		var wait_s: float = float(FileAccess.get_file_as_string(SHOT_FILE).strip_edges())
		get_tree().create_timer(maxf(0.5, wait_s)).timeout.connect(func() -> void:
			var shot: Image = get_viewport().get_texture().get_image()
			shot.save_png("user://shot.png")
			print("[REALM] screenshot user://shot.png"))
	if OS.is_debug_build():
		for i: int in mini(runner.spawned.size(), 5):
			var unit: Unit = runner.spawned[i]
			var screen: Vector2 = camera.world_to_screen(unit.position)
			print("[REALM] unit %d %s screen=(%d,%d)" % [i, unit.unit_type, int(screen.x), int(screen.y)])


## Networked match: the Lockstep node gates World / rules / scripted orders
## until both devices have each turn's commands; the HUD shows stalls,
## desyncs and a lost rival. No speed button (time_scale changes the tick).
func _setup_lockstep() -> void:
	var gated: Array[Node] = [world, rules, runner]
	lockstep.setup(NetSession.local_player, NetSession.players, gated, bus.apply, world.state_hash)
	bus.lockstep = lockstep
	lockstep.waiting_changed.connect(hud.set_waiting)
	lockstep.desync.connect(func(t: int, _mine: int, _theirs: int) -> void:
		hud.show_banner(tr("NET_DESYNC") % t, "critical")
		hud.set_net_status(tr("NET_DESYNC") % t))
	lockstep.peer_lost.connect(func(_p: int) -> void:
		hud.show_banner(tr("NET_PEER_LOST"), "critical")
		hud.set_net_status(tr("NET_PEER_LOST")))
	hud.lock_speed()
	hud.set_net_status(tr("NET_SEAT") % (GameState.PLAYER_HUMAN + 1))
	lockstep.started.connect(func() -> void: hud.set_net_status(""))
	lockstep.start()
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("autoplay"):
		_start_autoplay()


## Debug soak test (`-- autoplay`): every few seconds this seat sends one of
## its units somewhere near home, or trains a villager, through the normal
## command path. Two instances left alone for minutes exercise the lockstep.
var _autoplay_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _start_autoplay() -> void:
	_autoplay_rng.randomize()
	var t: Timer = Timer.new()
	t.wait_time = 4.0
	t.autostart = true
	t.timeout.connect(_autoplay_step)
	add_child(t)


func _autoplay_step() -> void:
	if rules.ended or not lockstep.is_started:
		return
	var p: int = GameState.PLAYER_HUMAN
	var mine: Array[Unit] = []
	var tc: Building = null
	for u: Unit in world.units:
		if u.owner_id == p and not u.is_dead and not u.is_animal():
			mine.append(u)
	for b: Building in world.buildings:
		if b.owner_id == p and b.building_type == "town_center":
			tc = b
	if mine.is_empty() or tc == null:
		return
	if _autoplay_rng.randf() < 0.3:
		if world.construction.can_enqueue(tc, "villager") == "":
			bus.submit({"type": "train", "player": p, "building": tc.sim_id, "item": "villager"})
		return
	var u: Unit = mine[_autoplay_rng.randi_range(0, mine.size() - 1)]
	var dest: Vector2 = tc.position + Vector2.from_angle(_autoplay_rng.randf() * TAU) * _autoplay_rng.randf_range(200.0, 900.0)
	dest = world.nav.cell_center(world.nav.nearest_walkable(world.world_to_cell(dest.clamp(Vector2.ZERO, world.map_size_px - Vector2.ONE))))
	var target: Dictionary = selection.resolve_target(dest)
	bus.submit(CommandBus.order_cmd(p, [u] as Array[Unit], target, dest))
	print("[REALM] autoplay seat=%d turn=%d unit=%d -> (%d,%d) %s" % [p, lockstep.turn, u.sim_id, int(dest.x), int(dest.y), String(target["kind"])])


## Menu choices (GameState.launch): scenario + AI, or a save slot to load.
func _consume_launch() -> void:
	var launch: Dictionary = GameState.launch
	GameState.launch = {}
	if launch.has("net"):
		net_match = true
		scenario = String(launch.get("scenario", "skirmish"))
		map_override = NetSession.map_id
		match_seed = NetSession.match_seed
		fair_ai = true
	elif launch.has("load"):
		var data: Dictionary = SaveManager.load_payload(String(launch["load"]))
		if not data.is_empty():
			load_data = data
			scenario = String(data.get("scenario", "skirmish"))
			map_override = String(data.get("map_id", ""))
			fair_ai = bool(data.get("fair_ai", true))
			var ai_list: Dictionary = {}
			for a: Variant in data.get("ais", []):
				ai_list[int(a["player"])] = String(a["difficulty"])
			ai_override = ai_list
	elif launch.has("scenario"):
		scenario = String(launch["scenario"])
		map_override = String(launch.get("map", ""))
		fair_ai = bool(launch.get("fair", true))
		for key: Variant in Dictionary(launch.get("ai", {})).keys():
			ai_override[int(key)] = String(launch["ai"][key])


func _resolve_scenario() -> String:
	if scenario != "":
		return scenario
	if OS.is_debug_build() and FileAccess.file_exists(SCENARIO_FILE):
		var line: String = FileAccess.get_file_as_string(SCENARIO_FILE).strip_edges()
		if not DataLoader.get_entry("scenarios", line).is_empty():
			return line
	return "sandbox"


## "An army approaches": several enemy soldiers seen marching toward our
## base, once per minute at most (rules.json alerts.*).
var _army_warn_t: float = -999.0


func _check_army_warning() -> void:
	var p: int = GameState.PLAYER_HUMAN
	var now: float = rules.elapsed
	if now - _army_warn_t < float(DataLoader.rule("alerts", "army_warn_s", 60)):
		return
	var tc: Building = null
	for b: Building in world.buildings:
		if b.owner_id == p and b.building_type == "town_center":
			tc = b
			break
	if tc == null:
		return
	var radius: float = float(DataLoader.rule("alerts", "army_radius_px", 2200))
	var seen: int = 0
	var army_at: Vector2 = Vector2.ZERO
	for u: Unit in world.units:
		if u.owner_id < 0 or u.owner_id == p or u.is_dead or u.can_gather():
			continue
		var d: float = u.position.distance_to(tc.position)
		if d < radius and d > 600.0 and world.vision.grid.is_visible(p, u.position):
			seen += 1
			army_at += u.position
	if seen > 0:
		army_at /= seen
	if seen >= int(DataLoader.rule("alerts", "army_min_units", 6)):
		_army_warn_t = now
		hud.show_banner(tr("ALERT_ARMY"), "critical")
		Sfx.play("alert")
		hud.minimap.alert(army_at, "army")
		if hud.alert_arrow != null:
			hud.alert_arrow.point(army_at)
		if OS.is_debug_build():
			print("[REALM] army warning seen=%d" % seen)


func _refresh_idle() -> void:
	_check_army_warning()
	hud.set_idle_count(world.economy.idle_villagers(GameState.PLAYER_HUMAN).size())
	if bell_on and world.garrisoned_units(GameState.PLAYER_HUMAN).is_empty():
		bell_on = false
		bell_states[GameState.PLAYER_HUMAN] = false
	hud.set_bell(bell_on)
	# Relic countdown (mine or the rival's) in the top bar.
	var mine: float = rules.relic_countdown(GameState.PLAYER_HUMAN)
	var theirs: float = -1.0
	for p: int in rules.contenders:
		if p != GameState.PLAYER_HUMAN and p >= 0:
			theirs = maxf(theirs, rules.relic_countdown(p))
	hud.set_relics(world.relics_held(GameState.PLAYER_HUMAN), world.relic_total, mine, theirs)
	var w_mine: float = rules.wonder_countdown(GameState.PLAYER_HUMAN)
	var w_theirs: float = -1.0
	for p: int in rules.contenders:
		if p != GameState.PLAYER_HUMAN and p >= 0:
			w_theirs = maxf(w_theirs, rules.wonder_countdown(p))
	hud.set_wonder(w_mine, w_theirs)


## Town bell. First ring: every villager near a Town Center or tower runs
## inside (rules garrison.bell_radius_px). Second ring: everyone comes out
## and goes back to work. Returns how many units were sent in / let out
## (0 in a networked match, where the command applies a couple of turns later).
func ring_bell() -> int:
	var result: Variant = bus.submit({"type": "bell", "player": GameState.PLAYER_HUMAN})
	Sfx.play("bell")
	return int(result) if result != null else 0


## The bell for any player (CommandBus): shelters or releases their villagers.
## Which of the two is decided from the simulation alone (someone inside or
## on the way in = release), never from a HUD flag: the HUD's idle timer runs
## on the wall clock and must not steer a lockstep match.
func apply_bell(p: int) -> int:
	var n: int = 0
	var sheltering: bool = not world.garrisoned_units(p).is_empty()
	for u: Unit in world.units:
		if u.owner_id == p and u.task is GarrisonTask:
			sheltering = true
			break
	var on: bool = false
	if sheltering:
		for u: Unit in world.units:
			if u.owner_id == p and u.task is GarrisonTask:
				world.behavior.assign(u, null)
		for b: Building in world.buildings:
			if b.owner_id == p:
				n += b.garrison.size()
				world.eject_all(b)
	else:
		n = shelter_villagers(p)
		on = n > 0
	bell_states[p] = on
	if p == GameState.PLAYER_HUMAN:
		bell_on = on
		hud.set_bell(bell_on)
	if OS.is_debug_build():
		print("[REALM] bell player=%d on=%s units=%d" % [p, on, n])
	return n


## Sends every villager of `p` within reach of a sheltering building to the
## nearest one with room (Town Center first). Shared with the AI.
func shelter_villagers(p: int) -> int:
	var radius: float = float(DataLoader.rule("garrison", "bell_radius_px", 1400))
	var shelters: Array[Building] = []
	for b: Building in world.buildings:
		if b.owner_id == p and b.is_complete() and b.garrison_slots() > 0:
			shelters.append(b)
	shelters.sort_custom(func(a: Building, b: Building) -> bool: return (a.building_type == "town_center") and b.building_type != "town_center")
	var room: Dictionary = {}
	for b: Building in shelters:
		room[b] = b.garrison_slots() - b.garrison.size()
	var sent: int = 0
	for u: Unit in world.units.duplicate():
		if u.owner_id != p or u.is_dead or not u.can_gather() or u.task is GarrisonTask:
			continue
		var best: Building = null
		var best_d: float = INF
		for b: Building in shelters:
			if int(room[b]) <= 0 or not b.can_garrison(u):
				continue
			var d: float = u.position.distance_to(b.position)
			if d <= radius and d < best_d:
				best_d = d
				best = b
		if best != null:
			room[best] = int(room[best]) - 1
			world.behavior.assign(u, GarrisonTask.new(u, world, best))
			sent += 1
	return sent


func _on_eject_pressed() -> void:
	var b: Building = selection.selected_building
	if b != null and is_instance_valid(b):
		bus.submit({"type": "eject", "player": GameState.PLAYER_HUMAN, "building": b.sim_id})
		hud.show_building(b)


## Idle bell: select the next idle villager and bring the camera to it.
func _on_idle_pressed() -> void:
	var idle: Array[Unit] = world.economy.idle_villagers(GameState.PLAYER_HUMAN)
	if idle.is_empty():
		return
	_idle_cycle = (_idle_cycle + 1) % idle.size()
	var unit: Unit = idle[_idle_cycle]
	selection.set_selection([unit])
	camera.center_on_smooth(unit.position)
	if OS.is_debug_build():
		print("[REALM] idle_bell selected=%s at=(%d,%d)" % [unit.name, int(unit.position.x), int(unit.position.y)])


func _on_build_type_chosen(type_id: String) -> void:
	var builders: Array[Unit] = selection.selected.filter(func(u: Unit) -> bool: return u.can_gather())
	if builders.is_empty():
		return
	placement.begin(type_id, builders)


## Train / research: checked here first so the HUD can say why not, then
## submitted as a command (applied now in solo play, next turns on LAN).
func _on_train_pressed(type_id: String) -> void:
	var b: Building = selection.selected_building
	if b != null and is_instance_valid(b):
		if world.construction.can_enqueue(b, type_id) != "":
			Sfx.play("error")
			# Say why: which buildings are missing for the era, or what resources.
			var why: String = hud.enqueue_reason(b, type_id)
			if why != "":
				hud.show_banner(why)
			return
		bus.submit({"type": "train", "player": GameState.PLAYER_HUMAN, "building": b.sim_id, "item": type_id})


func _on_sell_pressed(resource: String) -> void:
	var b: Building = selection.selected_building
	if resource != "gold" and world.economy.sell_error(GameState.PLAYER_HUMAN, resource) == "":
		bus.submit({"type": "sell", "player": GameState.PLAYER_HUMAN, "resource": resource})
		Sfx.play("deposit")
	else:
		Sfx.play("error")
	if b != null and is_instance_valid(b):
		hud.show_building(b)


func _on_buy_pressed(resource: String) -> void:
	var b: Building = selection.selected_building
	if resource != "gold" and world.economy.buy_error(GameState.PLAYER_HUMAN, resource) == "":
		bus.submit({"type": "buy", "player": GameState.PLAYER_HUMAN, "resource": resource})
		Sfx.play("deposit")
	else:
		Sfx.play("error")
	if b != null and is_instance_valid(b):
		hud.show_building(b)


func _on_dequeue_pressed() -> void:
	var b: Building = selection.selected_building
	if b != null and is_instance_valid(b) and not b.queue.is_empty():
		bus.submit({"type": "dequeue", "player": GameState.PLAYER_HUMAN, "building": b.sim_id, "index": b.queue.size() - 1})


func _on_cancel_construction() -> void:
	var b: Building = selection.selected_building
	if b != null and is_instance_valid(b):
		bus.submit({"type": "cancel_construction", "player": GameState.PLAYER_HUMAN, "building": b.sim_id})
		selection.select_building(null)


func _on_match_ended(winner_id: int, loser_id: int, seconds: float) -> void:
	for ai: AIController in ais:
		ai.enabled = false
	if ai_override.has(GameState.PLAYER_HUMAN):
		return  # AI vs AI test: no human screen.
	var won: bool = winner_id == GameState.PLAYER_HUMAN
	var why: String = ""
	match rules.reason:
		"town_center":
			why = tr("END_WHY_TC_WIN") if won else tr("END_WHY_TC_LOSS")
		"resign":
			why = tr("END_WHY_RESIGN") if won else ""
		"relics":
			why = tr("END_WHY_RELICS_WIN") if won else tr("END_WHY_RELICS_LOSS")
		"wonder":
			why = tr("END_WHY_WONDER_WIN") if won else tr("END_WHY_WONDER_LOSS")
	var rival: int = loser_id if won else winner_id
	var lines: Array[String] = rules.report_lines(GameState.PLAYER_HUMAN, rival, won)
	if not fair_ai:
		for ai: AIController in ais:
			var bonus: String = AIController.bonus_text(ai.difficulty_id)
			if bonus != "":
				lines.append(tr("REPORT_AI_BONUS") % bonus)
	hud.show_end(won, seconds, GameState.stats.get(GameState.PLAYER_HUMAN, {}), GameState.stats.get(rival, {}), why, lines)


func _on_retry() -> void:
	get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	if rules == null or rules.ended or ais.is_empty() or net_match:
		return
	_autosave_timer += delta
	if _autosave_timer >= float(DataLoader.rule("save", "autosave_seconds", 120)):
		_autosave_timer = 0.0
		save_match("auto")


func save_match(slot: String) -> Error:
	if tutorial != null or net_match:
		return ERR_UNAVAILABLE  # the tutorial is short and not resumable; LAN saves come later
	var err: Error = SaveManager.save_payload(slot, SaveGame.snapshot(self))
	if OS.is_debug_build():
		print("[REALM] saved slot=%s err=%d" % [slot, err])
	return err


func _quit_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if not rules.ended and not ais.is_empty():
		save_match("auto")
	if net_match:
		NetSession.leave()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
