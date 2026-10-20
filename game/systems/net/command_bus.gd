class_name CommandBus
extends Node
## Every order a player gives (move, attack, gather, build, train, research,
## bell, formation...) is a plain Dictionary that goes through `submit`:
##   {"type": "order", "player": 0, "units": [12, 13], "target": {...}, "pos": [x, y]}
## `apply` is the only code that turns a command into changes in the world.
## - Solo match: `submit` applies at once (between two physics ticks, which is
##   the same as "at the start of the next tick") and logs it with its tick.
## - Networked match: `submit` hands the command to the Lockstep node, which
##   schedules it for a later turn and applies it on every device at the same
##   tick through `apply`.
## Commands hold only ints, floats, Strings and Arrays: ENet-friendly and
## JSON-friendly (replays, tests).

signal applied(cmd: Dictionary)

var world: World
## The match scene (bell state, HUD for the local player). May be null in tests.
var main: Node = null
## Set by main in networked matches; null = apply locally at once.
var lockstep: Lockstep = null
## Every command applied, with its tick (replays and the determinism test).
var history: Array[Dictionary] = []
var record_history: bool = true


func setup(p_world: World, p_main: Node = null) -> void:
	world = p_world
	main = p_main


## Local play: applied now, returns apply's result (a Building, a bool...).
## Networked: queued for a later turn, returns null.
func submit(cmd: Dictionary) -> Variant:
	if lockstep != null and lockstep.active:
		lockstep.queue_local(cmd)
		return null
	cmd["tick"] = world.tick + 1
	return apply(cmd)


## Executes a command against the world. Unknown or stale commands (dead
## units, razed buildings) do nothing: both devices skip them the same way.
func apply(cmd: Dictionary) -> Variant:
	if record_history:
		history.append(cmd)
	var player: int = int(cmd.get("player", 0))
	var result: Variant = null
	match String(cmd.get("type", "")):
		"order":
			result = _apply_order(cmd, player)
		"stop":
			for u: Unit in OrderResolver.units_of(world, cmd.get("units", []), player):
				world.behavior.assign(u, null)
				world.movement.stop(u)
		"hold":
			for u: Unit in OrderResolver.units_of(world, cmd.get("units", []), player):
				world.behavior.assign(u, null)
				world.movement.stop(u)
				u.stance = "hold"
		"stance":
			for u: Unit in OrderResolver.units_of(world, cmd.get("units", []), player):
				u.stance = String(cmd.get("stance", "aggressive"))
		"build":
			var cell_arr: Array = cmd.get("cell", [0, 0])
			var builders: Array[Unit] = OrderResolver.units_of(world, cmd.get("builders", []), player)
			result = world.construction.start_construction(player, String(cmd.get("building_type", "")), Vector2i(int(cell_arr[0]), int(cell_arr[1])), builders)
		"build_line":
			var cells: Array[Vector2i] = []
			for c: Variant in cmd.get("cells", []):
				cells.append(Vector2i(int(c[0]), int(c[1])))
			var builders: Array[Unit] = OrderResolver.units_of(world, cmd.get("builders", []), player)
			result = world.construction.start_wall_line(player, String(cmd.get("building_type", "")), cells, builders)
		"train":
			var b: Building = _own_building(cmd, player)
			result = b != null and world.construction.enqueue(b, String(cmd.get("item", "")))
		"dequeue":
			var b: Building = _own_building(cmd, player)
			if b != null:
				var index: int = int(cmd.get("index", b.queue.size() - 1))
				result = index >= 0 and index < b.queue.size() and world.construction.dequeue(b, index)
		"cancel_construction":
			var b: Building = _own_building(cmd, player)
			if b != null:
				result = world.construction.cancel_construction(b)
		"rally":
			var b: Building = _own_building(cmd, player)
			if b != null:
				b.rally_point = OrderResolver.arr_to_vec(cmd.get("pos"))
		"sell":
			result = world.economy.sell(player, String(cmd.get("resource", "")))
		"buy":
			result = world.economy.buy(player, String(cmd.get("resource", "")))
		"eject":
			var b: Building = _own_building(cmd, player)
			if b != null:
				world.eject_all(b)
		"bell":
			if main != null and main.has_method("apply_bell"):
				result = main.apply_bell(player)
		"resign":
			if main != null and main.get("rules") != null:
				(main.get("rules") as MatchRules).resign(player)
		_:
			push_warning("CommandBus: unknown command %s" % String(cmd.get("type", "")))
	applied.emit(cmd)
	return result


## {"units": [ids], "target": {...}, "pos": [x, y], "formation": "line",
##  "attack_move": false}. Each unit gets the task the target calls for;
## the rest walk together in the chosen formation. Returns the order kind
## ("move", "gather", "attack"...) for the marker colour.
func _apply_order(cmd: Dictionary, player: int) -> String:
	var selected: Array[Unit] = OrderResolver.units_of(world, cmd.get("units", []), player)
	if selected.is_empty():
		return ""
	var target: Dictionary = OrderResolver.target_from_dict(world, cmd.get("target", {}))
	var kind: String = String(target["kind"])
	var world_pos: Vector2 = OrderResolver.arr_to_vec(cmd.get("pos"))
	var formation: String = String(cmd.get("formation", "none"))
	var movers: Array[Unit] = []
	var order_kind: String = "move"
	var fighters: Array[Unit] = []
	if bool(cmd.get("attack_move", false)):
		fighters = selected.filter(func(u: Unit) -> bool: return not u.can_gather() and not u.data.get("combat", {}).is_empty())
	for unit: Unit in selected:
		if fighters.has(unit):
			continue
		var task: UnitTask = OrderResolver.task_for(world, unit, kind, target.get("ref"))
		if task != null:
			world.behavior.assign(unit, task)
			order_kind = task.kind if task.kind != "gather" or kind != "own_building" else "deliver"
		else:
			world.behavior.assign(unit, null)
			unit.attack_move = false
			movers.append(unit)
	if not fighters.is_empty():
		world.combat.attack_move(fighters, world_pos, formation)
		order_kind = "attack"
	if not movers.is_empty():
		world.movement.command_move(movers, world_pos, formation)
	return order_kind


func _own_building(cmd: Dictionary, player: int) -> Building:
	var b: Building = world.building_by_id(int(cmd.get("building", 0)))
	if b == null or b.owner_id != player or not world.buildings.has(b):
		return null
	return b


## Builders for an order command (selection, tests).
static func order_cmd(player: int, units: Array[Unit], target: Dictionary, world_pos: Vector2, formation: String = "none", attack_move: bool = false) -> Dictionary:
	return {
		"type": "order", "player": player, "units": OrderResolver.ids_of(units),
		"target": OrderResolver.target_to_dict(target), "pos": OrderResolver.vec_to_arr(world_pos),
		"formation": formation, "attack_move": attack_move,
	}
