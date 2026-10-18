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
	if int(def.get("era", 1)) > GameState.era_of(player_id):
		return "era"
	if not world.can_place(type_id, cell, ignore):
		return "occupied"
	if not GameState.can_afford(player_id, def.get("cost", {})):
		return "cost"
	return ""


func start_construction(player_id: int, type_id: String, cell: Vector2i, builders: Array[Unit]) -> Building:
	if placement_error(player_id, type_id, cell, builders) != "":
		return null
	var cost: Dictionary = DataLoader.get_entry("buildings", type_id).get("cost", {})
	if not GameState.spend(player_id, cost):
		return null
	var b: Building = world.place_building(type_id, player_id, cell)
	b.make_foundation()
	_paid[b] = cost.duplicate()
	b.completed.connect(_on_completed)
	world.economy.refresh_population()
	for u: Unit in builders:
		if is_instance_valid(u) and u.can_gather():
			world.behavior.assign(u, BuildTask.new(u, world, b))
	return b


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


func enqueue(b: Building, type_id: String) -> bool:
	if can_enqueue(b, type_id) != "":
		return false
	GameState.spend(b.owner_id, DataLoader.get_entry("units", type_id).get("cost", {}))
	b.queue.append(type_id)
	b.changed.emit(b)
	b.queue_redraw()
	return true


func dequeue(b: Building, index: int) -> bool:
	if index < 0 or index >= b.queue.size():
		return false
	var type_id: String = b.queue[index]
	var ratio: float = float(DataLoader.rule("production", "cancel_refund", 1.0))
	var cost: Dictionary = DataLoader.get_entry("units", type_id).get("cost", {})
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
	if world == null:
		return
	for b: Building in world.buildings.duplicate():
		if b.queue.is_empty() or not b.is_complete():
			continue
		var type_id: String = b.queue[0]
		var pop: int = int(DataLoader.get_entry("units", type_id).get("pop", 1))
		var free: bool = GameState.pop_used(b.owner_id) + pop <= GameState.pop_cap(b.owner_id)
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
		if b.train_elapsed >= b.train_time_of(type_id):
			_finish_training(b, type_id)


func _finish_training(b: Building, type_id: String) -> void:
	b.queue.remove_at(0)
	b.train_elapsed = 0.0
	var toward: Vector2 = b.rally_point if b.rally_point != Vector2.INF else b.position + Vector2(0, b.rect().size.y)
	var spawn: Vector2 = world.approach_point(b.rect(), toward)
	var unit: Unit = world.spawn_unit(type_id, b.owner_id, spawn)
	if b.rally_point != Vector2.INF:
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
