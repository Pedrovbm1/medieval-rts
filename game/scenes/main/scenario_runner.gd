class_name ScenarioRunner
extends Node
## Sets up a scenario from data/scenarios.json: map, camera, units, and optional
## scripted orders (auto_orders, wander) for tests and device benchmarks.
## Reports progress as "[REALM] scenario ..." log lines (debug builds).

signal all_arrived(seconds: float)

var world: World
var camera: CameraController
var scenario_id: String = ""
var def: Dictionary = {}
var spawned: Array[Unit] = []
var elapsed: float = 0.0
var arrived_count: int = 0
var finished_at: float = -1.0

var _pending_orders: Array[Dictionary] = []
var _wander_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _report_timer: float = 0.0
var _ordered: bool = false


func start(p_id: String, p_world: World, p_camera: CameraController) -> void:
	scenario_id = p_id
	world = p_world
	camera = p_camera
	# Copy: data tables are shared and must stay read-only.
	def = DataLoader.get_entry("scenarios", scenario_id).duplicate(true)
	_rng.seed = 4242
	var tile: float = float(world.tile_size)

	var origin: Vector2 = world.map_size_px * 0.5
	if bool(def.get("spawn_near_center", false)):
		origin = world.find_open_area(origin, 3)
	var row: Array[Dictionary] = []
	for group: Variant in def.get("units", []):
		if Dictionary(group).has("block"):
			_spawn_block(group, tile)
		else:
			for i: int in int(group.get("count", 1)):
				row.append(group)
	_spawn_row(row, origin)

	var cam: Variant = def.get("camera", "spawn")
	if cam is Array:
		camera.center_on(Vector2(float(cam[0]), float(cam[1])) * tile)
	else:
		camera.center_on(origin)
	if def.has("zoom"):
		camera.zoom_at(camera.get_viewport_rect().size * 0.5, float(def["zoom"]))
	for order: Variant in def.get("auto_orders", []):
		_pending_orders.append(order)
	for unit: Unit in spawned:
		unit.arrived.connect(_on_arrived)
	_log("start units=%d" % spawned.size())


func _spawn_block(group: Dictionary, tile: float) -> void:
	var count: int = int(group.get("count", 1))
	var spacing: float = float(DataLoader.rule("movement", "formation_spacing_px", 40))
	var block: Array = group["block"]
	var start: Vector2 = Vector2(float(block[0]), float(block[1])) * tile
	var cols: int = int(block[2])
	for i: int in count:
		var pos: Vector2 = start + Vector2(i % cols, i / cols) * spacing
		spawned.append(world.spawn_unit(String(group.get("type", "militia")), int(group.get("player", 0)), pos))


## Places single units in one centred row (sandbox).
func _spawn_row(row: Array[Dictionary], origin: Vector2) -> void:
	var step: float = 72.0
	var row_start: float = origin.x - step * (row.size() - 1) * 0.5
	for i: int in row.size():
		var g: Dictionary = row[i]
		spawned.append(world.spawn_unit(String(g.get("type", "militia")), int(g.get("player", 0)), Vector2(row_start + step * i, origin.y)))


func _physics_process(delta: float) -> void:
	if world == null:
		return
	elapsed += delta
	for order: Dictionary in _pending_orders.duplicate():
		if elapsed >= float(order.get("after_s", 0.0)):
			_pending_orders.erase(order)
			var target: Array = order["target"]
			world.movement.command_move(spawned, Vector2(float(target[0]), float(target[1])) * float(world.tile_size))
			_ordered = true
			_log("order target=(%d,%d)" % [int(target[0]), int(target[1])])
	if def.has("wander"):
		_wander(delta)
	if bool(def.get("report_arrival", false)) and _ordered:
		_report_timer += delta
		if _report_timer >= 1.0:
			_report_timer = 0.0
			var moving: int = spawned.filter(func(u: Unit) -> bool: return u.is_moving()).size()
			_log("progress t=%.1f arrived=%d moving=%d" % [elapsed, arrived_count, moving])
			if moving == 0 and finished_at < 0.0:
				finished_at = elapsed
				_log("done t=%.1f arrived=%d/%d" % [elapsed, arrived_count, spawned.size()])
				all_arrived.emit(elapsed)


func _wander(delta: float) -> void:
	var w: Dictionary = def["wander"]
	_wander_timer += delta
	if _wander_timer < float(w.get("every_s", 2.0)):
		return
	_wander_timer = 0.0
	var region: Array = w.get("region", [10, 10, 110, 110])
	var batch: int = int(w.get("batch", 10))
	var start: int = _rng.randi_range(0, maxi(0, spawned.size() - batch))
	var group: Array[Unit] = []
	for i: int in range(start, mini(start + batch, spawned.size())):
		group.append(spawned[i])
	var target: Vector2 = Vector2(_rng.randf_range(float(region[0]), float(region[2])), _rng.randf_range(float(region[1]), float(region[3]))) * float(world.tile_size)
	world.movement.command_move(group, target)


func _on_arrived(_unit: Unit) -> void:
	arrived_count += 1


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[REALM] scenario %s %s" % [scenario_id, msg])
