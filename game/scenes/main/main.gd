extends Node
## Match entry point: wires world, camera, input, selection and HUD together.

const TEST_UNITS: Array[String] = ["militia", "militia", "militia", "villager", "villager"]

@onready var world: World = $World
@onready var camera: CameraController = $CameraController
@onready var order_marker: OrderMarker = $World/OrderMarker
@onready var hud: Hud = $Hud
@onready var selection: SelectionController = $SelectionController
@onready var pointer: PointerManager = $PointerManager


func _ready() -> void:
	camera.set_map_bounds(Rect2(Vector2.ZERO, world.map_size_px))
	selection.setup(world, camera, order_marker)
	pointer.setup(camera, selection, hud)

	selection.selection_changed.connect(hud.show_selection)
	pointer.box_changed.connect(hud.show_box)
	hud.stop_pressed.connect(selection.order_stop)
	hud.hold_pressed.connect(selection.order_hold)
	hud.deselect_pressed.connect(selection.clear_selection)

	var spawn: Vector2 = world.find_open_area(world.map_size_px * 0.5, 3)
	camera.center_on(spawn)
	_spawn_test_units(spawn)


## F1 sandbox: 3 militia + 2 villagers in a row so selection can be tested.
func _spawn_test_units(center: Vector2) -> void:
	var spacing: float = 72.0
	var start_x: float = center.x - spacing * (TEST_UNITS.size() - 1) * 0.5
	for i: int in TEST_UNITS.size():
		var unit: Unit = world.spawn_unit(TEST_UNITS[i], GameState.PLAYER_HUMAN, Vector2(start_x + spacing * i, center.y))
		if OS.is_debug_build():
			var screen: Vector2 = camera.world_to_screen(unit.position)
			print("[REALM] unit %d %s screen=(%d,%d) view=(%d,%d)" % [
				i, unit.unit_type, int(screen.x), int(screen.y),
				int(camera.get_viewport_rect().size.x), int(camera.get_viewport_rect().size.y)])
