class_name ConstructionSystem
extends Node
## Building placement, construction and unit production for every player.
## - start_construction: pay, drop a foundation, send builders.
## - cancel_construction: refund a share of the cost (rules.json), remove it.
## - enqueue / dequeue: production queues, paid on enqueue, refunded on cancel.
## - Trains the head of every queue each physics frame, respecting population.

signal unit_trained(unit: Unit, building: Building)

var world: World
## Building -> cost actually paid for it (refunds use this, not the table).
var _paid: Dictionary = {}


func setup(p_world: World) -> void:
	world = p_world


# ------------------------------------------------------------------ construction

## Why a placement is invalid ("" when it is valid): terrain/occupied/cost/type.
func placement_error(player_id: int, type_id: String, cell: Vector2i, ignore: Array[Unit] = []) -> String:
	var def: Dictionary = DataLoader.get_entry("buildings", type_id)
	if def.is_empty() or not bool(def.get("buildable", true)):
		return "type"
	# "build_era": when a building may be BUILT later than its own era (an
	# extra Town Center from Era III, while the first is Era I).
	if int(def.get("build_era", def.get("era", 1))) > GameState.era_of(player_id):
		return "era"
	if count_limit(player_id, type_id) >= 0 and owned_count(world, player_id, type_id) >= count_limit(player_id, type_id):
		return "limit"
	# A gate may replace one of our own wall segments.
	var replaces: Building = world.wall_at(player_id, cell) if bool(def.get("gate", false)) else null
	if replaces == null and not world.can_place(type_id, cell, ignore):
		return "occupied"
	if not GameState.can_afford(player_id, def.get("cost", {})):
		return "cost"
	return ""


## How many of `type_id` a player may own in their era (buildings.json
## "max_count": {"3": 2, "4": 3}, e.g. extra Town Centers); -1 = no limit.
static func count_limit(player_id: int, type_id: String) -> int:
	var limits: Dictionary = DataLoader.get_entry("buildings", type_id).get("max_count", {})
	if limits.is_empty():
		return -1
	var best: int = 0
	for era: int in range(1, GameState.era_of(player_id) + 1):
		if limits.has(str(era)):
			best = int(limits[str(era)])
	return best


## Own buildings of a type, foundations included.
static func owned_count(p_world: World, player_id: int, type_id: String) -> int:
	var n: int = 0
	for b: Building in p_world.buildings:
		if b.owner_id == player_id and b.building_type == type_id:
			n += 1
	return n


func start_construction(player_id: int, type_id: String, cell: Vector2i, builders: Array[Unit]) -> Building:
	if placement_error(player_id, type_id, cell, builders) != "":
		return null
	var cost: Dictionary = DataLoader.get_entry("buildings", type_id).get("cost", {})
	if not GameState.spend(player_id, cost):
		return null
	var old_wall: Building = world.wall_at(player_id, cell) if bool(DataLoader.get_entry("buildings", type_id).get("gate", false)) else null
	if old_wall != null:
		# Gate on a wall: the segment comes down and its cost comes back.
		for res: String in Dictionary(old_wall.data.get("cost", {})).keys():
			GameState.add_resource(player_id, res, int(old_wall.data["cost"][res]))
		world.remove_building(old_wall)
	var b: Building = world.place_building(type_id, player_id, cell)
	b.make_foundation()
	_paid[b] = cost.duplicate()
	b.completed.connect(_on_completed)
	world.economy.refresh_population()
	for u: Unit in builders:
		if not is_instance_valid(u) or not u.can_gather():
			continue
		if u.task is BuildTask and (u.task as BuildTask).is_building():
			# Already building something: this one waits its turn instead
			# of making the villager drop the unfinished foundation.
			(u.task as BuildTask).queue.append(b)
		else:
			world.behavior.assign(u, BuildTask.new(u, world, b))
	return b


## Builds a straight wall: one 1x1 foundation per free cell, in order from the
## start, stopping when the player runs out of the resource. Returns the
## foundations made (cells already walled or blocked are skipped, not errors).
func start_wall_line(player_id: int, type_id: String, cells: Array[Vector2i], builders: Array[Unit]) -> Array[Building]:
	var made: Array[Building] = []
	for c: Vector2i in cells:
		if placement_error(player_id, type_id, c, builders) == "cost":
			break
		var b: Building = start_construction(player_id, type_id, c, builders)
		if b != null:
			made.append(b)
	if OS.is_debug_build():
		print("[REALM] wall placed %s n=%d of %d" % [type_id, made.size(), cells.size()])
	return made


## Gates open for everyone and close while an enemy is close (with a delay
## before reopening, so they do not flap). Called every physics frame.
var _gate_t: float = 0.0


func _tick_gates(delta: float) -> void:
	if not bool(DataLoader.rule("gates", "auto", true)):
		return
	_gate_t += delta
	if _gate_t < float(DataLoader.rule("gates", "tick_s", 0.25)):
		return
	_gate_t = 0.0
	var close_px: float = float(DataLoader.rule("gates", "close_px", 320))
	var open_px: float = float(DataLoader.rule("gates", "open_px", 400))
	var delay: float = float(DataLoader.rule("gates", "open_delay_s", 1.0))
	var now: float = Time.get_ticks_msec() / 1000.0
	for b: Building in world.buildings:
		if not b.is_gate() or not b.is_complete():
			continue
		var nearest: float = INF
		for other: Object in world.movement.spatial.query(b.position, open_px):
			var u: Unit = other as Unit
			if u.is_dead or u.owner_id < 0 or u.owner_id == b.owner_id:
				continue
			nearest = minf(nearest, u.position.distance_to(b.position))
		if b.is_open and nearest <= close_px:
			# Do not trap a unit standing in the doorway: close once it is clear.
			var standing: bool = world.units.any(func(u: Unit) -> bool: return not u.is_dead and b.rect().has_point(u.position))
			if not standing:
				b.set_gate_open(false, world.nav)
				b._open_since = -1.0
		elif not b.is_open and nearest > open_px:
			if b._open_since < 0.0:
				b._open_since = now
			elif now - b._open_since >= delay:
				b.set_gate_open(true, world.nav)
		elif not b.is_open:
			b._open_since = -1.0


## Removes an unfinished building and refunds part of what was paid.
func cancel_construction(b: Building) -> Dictionary:
	if b == null or not is_instance_valid(b) or b.is_complete():
		return {}
	var ratio: float = float(DataLoader.rule("construction", "cancel_refund", 0.5))
	var refund: Dictionary = {}
	var paid: Dictionary = _paid.get(b, {})
	for res: String in paid.keys():
		var amount: int = int(floorf(int(paid[res]) * ratio))
		if amount > 0:
			GameState.add_resource(b.owner_id, res, amount)
			refund[res] = amount
	_paid.erase(b)
	world.remove_building(b)
	return refund


func _on_completed(b: Building) -> void:
	_paid.erase(b)
	world.economy.refresh_population()
	EventBus.building_completed.emit(b)


# ------------------------------------------------------------------ production

## Whether a player's faction may ever train this unit (unique units).
static func unit_allowed(player_id: int, type_id: String) -> bool:
	var def: Dictionary = DataLoader.get_entry("units", type_id)
	if not def.has("unique_to"):
		return true
	return Array(def["unique_to"]).has(String(GameState.civs.get(player_id, "")))


func can_enqueue(b: Building, type_id: String) -> String:
	if not b.is_complete():
		return "unbuilt"
	if not b.trains().has(type_id) or not unit_allowed(b.owner_id, type_id):
		return "type"
	var def: Dictionary = DataLoader.get_entry("units", type_id)
	if int(def.get("era", 1)) > GameState.era_of(b.owner_id):
		return "era"
	if b.queue.size() >= int(DataLoader.rule("production", "queue_max", 5)):
		return "full"
	if not GameState.can_afford(b.owner_id, def.get("cost", {})):
		return "cost"
	return ""


## Queues a unit or a "#research" item (tech or era). Paid up front.
func enqueue(b: Building, type_id: String) -> bool:
	if TechSystem.is_research(type_id):
		if not b.is_complete() or b.queue.size() >= int(DataLoader.rule("production", "queue_max", 5)) or world.tech.research_error(b, type_id) != "":
			return false
	elif can_enqueue(b, type_id) != "":
		return false
	GameState.spend(b.owner_id, TechSystem.item_cost(type_id))
	b.queue.append(type_id)
	b.changed.emit(b)
	b.queue_redraw()
	return true


func dequeue(b: Building, index: int) -> bool:
	if index < 0 or index >= b.queue.size():
		return false
	var type_id: String = b.queue[index]
	var ratio: float = float(DataLoader.rule("production", "cancel_refund", 1.0))
	var cost: Dictionary = TechSystem.item_cost(type_id)
	for res: String in cost.keys():
		GameState.add_resource(b.owner_id, res, int(floorf(int(cost[res]) * ratio)))
	b.queue.remove_at(index)
	if index == 0:
		b.train_elapsed = 0.0
		b.blocked_by_pop = false
	b.changed.emit(b)
	b.queue_redraw()
	return true


func _physics_process(delta: float) -> void:
	if world != null:
		world.economy.tick_market(delta)
		_tick_gates(delta)
	if world == null:
		return
	world.economy.tick_farms(delta)
	world.economy.tick_relics(delta)
	for b: Building in world.buildings.duplicate():
		if b.queue.is_empty() or not b.is_complete():
			continue
		var type_id: String = b.queue[0]
		var research: bool = TechSystem.is_research(type_id)
		var pop: int = 0 if research else int(DataLoader.get_entry("units", type_id).get("pop", 1))
		var free: bool = research or GameState.pop_used(b.owner_id) + pop <= GameState.pop_cap(b.owner_id)
		if not free:
			if not b.blocked_by_pop:
				b.blocked_by_pop = true
				b.changed.emit(b)
			continue
		if b.blocked_by_pop:
			b.blocked_by_pop = false
			b.changed.emit(b)
		var before: int = int(b.train_progress() * 50.0)
		b.train_elapsed += delta
		if int(b.train_progress() * 50.0) != before:
			b.queue_redraw()
		if b.train_elapsed >= b.train_time_of(type_id) / GameState.modifier(b.owner_id, "research_speed" if research else "train_speed"):
			if research:
				b.queue.remove_at(0)
				b.train_elapsed = 0.0
				world.tech.complete(b.owner_id, type_id)
				b.changed.emit(b)
				b.queue_redraw()
			else:
				_finish_training(b, type_id)


func _finish_training(b: Building, type_id: String) -> void:
	b.queue.remove_at(0)
	b.train_elapsed = 0.0
	var toward: Vector2 = b.rally_point if b.rally_point != Vector2.INF else b.position + Vector2(0, b.rect().size.y)
	var spawn: Vector2 = world.approach_point(b.rect(), toward)
	var unit: Unit = world.spawn_unit(type_id, b.owner_id, spawn)
	if unit.data.has("trade") and world.nearest_trade_post(unit.position) != null:
		# Caravans start their route at once: market <-> trade post.
		world.behavior.assign(unit, TradeTask.new(unit, world, b, world.nearest_trade_post(unit.position)))
	elif b.rally_point != Vector2.INF:
		_send_to_rally(unit, b.rally_point)
	b.changed.emit(b)
	b.queue_redraw()
	unit_trained.emit(unit, b)
	EventBus.unit_trained.emit(unit, b)


## A trained unit walks to the rally point; villagers start working if it is a resource.
func _send_to_rally(unit: Unit, point: Vector2) -> void:
	if unit.can_gather():
		var task: UnitTask = world.task_for_point(unit, point)
		if task != null:
			world.behavior.assign(unit, task)
			return
	world.movement.move_unit(unit, point)
