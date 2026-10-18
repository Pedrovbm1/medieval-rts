extends Node
## Match entry point: builds the world for a scenario and wires camera, input,
## selection and HUD together.
## Scenario: `scenario` (set before adding to the tree), else the first line of
## user://scenario.txt (debug builds, for device benchmarks), else "sandbox".

const SCENARIO_FILE: String = "user://scenario.txt"
const IDLE_REFRESH_SECONDS: float = 0.5

var scenario: String = ""
var _idle_cycle: int = 0

@onready var world: World = $World
@onready var camera: CameraController = $CameraController
@onready var order_marker: OrderMarker = $World/OrderMarker
@onready var hud: Hud = $Hud
@onready var selection: SelectionController = $SelectionController
@onready var pointer: PointerManager = $PointerManager
@onready var runner: ScenarioRunner = $ScenarioRunner


func _ready() -> void:
	var scenario_id: String = _resolve_scenario()
	var def: Dictionary = DataLoader.get_entry("scenarios", scenario_id)
	var map_id: String = String(def.get("map", "skirmish_120"))
	GameState.new_match(map_id, "northvale", "northvale")
	world.build_from_map(map_id)
	camera.set_map_bounds(Rect2(Vector2.ZERO, world.map_size_px))
	selection.setup(world, camera, order_marker)
	pointer.setup(camera, selection, hud)

	selection.selection_changed.connect(hud.show_selection)
	selection.building_selected.connect(hud.show_building)
	pointer.box_changed.connect(hud.show_box)
	hud.stop_pressed.connect(selection.order_stop)
	hud.hold_pressed.connect(selection.order_hold)
	hud.deselect_pressed.connect(selection.clear_selection)
	hud.idle_pressed.connect(_on_idle_pressed)

	runner.start(scenario_id, world, camera)
	world.economy.refresh_population()
	hud.refresh_all()
	var idle_timer: Timer = Timer.new()
	idle_timer.wait_time = IDLE_REFRESH_SECONDS
	idle_timer.autostart = true
	idle_timer.timeout.connect(_refresh_idle)
	add_child(idle_timer)
	_refresh_idle()
	if OS.is_debug_build():
		for i: int in mini(runner.spawned.size(), 5):
			var unit: Unit = runner.spawned[i]
			var screen: Vector2 = camera.world_to_screen(unit.position)
			print("[REALM] unit %d %s screen=(%d,%d)" % [i, unit.unit_type, int(screen.x), int(screen.y)])


func _resolve_scenario() -> String:
	if scenario != "":
		return scenario
	if OS.is_debug_build() and FileAccess.file_exists(SCENARIO_FILE):
		var line: String = FileAccess.get_file_as_string(SCENARIO_FILE).strip_edges()
		if not DataLoader.get_entry("scenarios", line).is_empty():
			return line
	return "sandbox"


func _refresh_idle() -> void:
	hud.set_idle_count(world.economy.idle_villagers(GameState.PLAYER_HUMAN).size())


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
