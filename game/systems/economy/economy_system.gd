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
# ------------------------------------------------------------------ market

## Gold paid for one lot of `resource` at this player's market right now.
func market_price(player_id: int, resource: String) -> int:
	var start: int = int(DataLoader.rule("market", "start_price", 70))
	return int(Dictionary(GameState.market_prices.get(player_id, {})).get(resource, start))


## "" if the player can sell a lot now, else the reason: "no_market", "cost".
func sell_error(player_id: int, resource: String) -> String:
	var has_market: bool = world.buildings.any(func(b: Building) -> bool:
		return b.owner_id == player_id and b.is_complete() and b.data.has("market"))
	if not has_market:
		return "no_market"
	if GameState.get_resource(player_id, resource) < int(DataLoader.rule("market", "lot", 100)):
		return "cost"
	return ""


## Sells one lot for gold; the price of that resource drops for this player.
func sell(player_id: int, resource: String) -> bool:
	if resource == "gold" or sell_error(player_id, resource) != "":
		return false
	var lot: int = int(DataLoader.rule("market", "lot", 100))
	var price: int = market_price(player_id, resource)
	GameState.add_resource(player_id, resource, -lot)
	GameState.add_resource(player_id, "gold", price)
	var prices: Dictionary = GameState.market_prices.get(player_id, {})
	prices[resource] = maxi(int(DataLoader.rule("market", "min_price", 20)), price - int(DataLoader.rule("market", "drop", 4)))
	GameState.market_prices[player_id] = prices
	if OS.is_debug_build():
		print("[REALM] market sell player=%d %d %s -> %d gold (next %d)" % [player_id, lot, resource, price, prices[resource]])
	return true


var _market_t: float = 0.0


## Prices drift back toward the start price over time (called every frame).
func tick_market(delta: float) -> void:
	_market_t += delta
	var every: float = float(DataLoader.rule("market", "recover_s", 20))
	if _market_t < every:
		return
	_market_t = 0.0
	var start: int = int(DataLoader.rule("market", "start_price", 70))
	var step: int = int(DataLoader.rule("market", "recover", 2))
	for p: Variant in GameState.market_prices.keys():
		var prices: Dictionary = GameState.market_prices[p]
		for res: Variant in prices.keys():
			prices[res] = mini(start, int(prices[res]) + step)


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
