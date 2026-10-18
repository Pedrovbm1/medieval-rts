class_name EconomySystem
extends RefCounted
## Economy queries and bookkeeping for every player: drop-off lookup,
## deliveries (with stats), population used/cap, idle villagers.

var world: World
var pop_max: int = 100
## Bookkeeping for the "no load is ever lost" invariant (tests, debugging):
## taken = delivered + carried + dropped, per player and resource.
var taken: Dictionary = {}
var dropped: Dictionary = {}


func setup(p_world: World) -> void:
	world = p_world
	pop_max = int(DataLoader.rule("economy", "pop_max", 100))


## Nearest complete building of `player_id` that accepts `resource`, or null.
func nearest_dropoff(player_id: int, resource: String, from: Vector2) -> Building:
	var best: Building = null
	var best_d: float = INF
	for b: Building in world.buildings:
		if b.owner_id != player_id or not b.accepts(resource):
			continue
		var d: float = World.distance_to_rect(from, b.rect())
		if d < best_d:
			best_d = d
			best = b
	return best


func record_taken(player_id: int, resource: String, amount: float) -> void:
	var bag: Dictionary = taken.get(player_id, {})
	bag[resource] = float(bag.get(resource, 0.0)) + amount
	taken[player_id] = bag


func record_dropped(player_id: int, resource: String, amount: float) -> void:
	var bag: Dictionary = dropped.get(player_id, {})
	bag[resource] = float(bag.get(resource, 0.0)) + amount
	dropped[player_id] = bag


## Unit hands its load to the player's stockpile.
func deliver(unit: Unit) -> void:
	# Small epsilon: 9.9999 after many float additions is a full load of 10.
	var amount: int = int(floorf(unit.carry_amount + 0.001))
	if amount > 0 and unit.carry_type != "":
		GameState.add_resource(unit.owner_id, unit.carry_type, amount)
		GameState.record_gathered(unit.owner_id, unit.carry_type, amount)
		EventBus.resources_delivered.emit(unit.owner_id, unit.carry_type, amount)
	# Fractions below 1 stay with the villager for the next trip.
	unit.carry_amount = maxf(0.0, unit.carry_amount - float(amount))


func population_used(player_id: int) -> int:
	var used: int = 0
	for u: Unit in world.units:
		if u.owner_id == player_id and not u.is_animal() and not u.is_dead:
			used += int(u.data.get("pop", 1))
	return used


func population_cap(player_id: int) -> int:
	var cap: int = 0
	for b: Building in world.buildings:
		if b.owner_id == player_id:
			cap += b.pop_bonus()
	return mini(cap, pop_max)


## Recomputes both players' population and notifies the HUD.
func refresh_population() -> void:
	for player_id: int in [GameState.PLAYER_HUMAN, GameState.PLAYER_AI]:
		var used: int = population_used(player_id)
		var cap: int = population_cap(player_id)
		if GameState.set_population(player_id, used, cap):
			EventBus.population_changed.emit(player_id, used, cap)


func idle_villagers(player_id: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in world.units:
		if u.owner_id == player_id and u.can_gather() and u.is_idle():
			out.append(u)
	return out


## Gather rate for a unit on a subtype, including tech multipliers (F7).
func gather_rate(unit: Unit, subtype: String) -> float:
	var rates: Dictionary = unit.data.get("gather_rates", {})
	return float(rates.get(subtype, 0.0)) * GameState.modifier(unit.owner_id, "gather." + subtype)


func carry_capacity(unit: Unit) -> float:
	return float(unit.data.get("carry_capacity", 10)) + GameState.modifier_add(unit.owner_id, "carry_capacity")
