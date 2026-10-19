extends Node
## Holds the match state shared by every system: resources, era, population,
## per-player modifiers (techs) and match statistics.

const PLAYER_HUMAN: int = 0
const PLAYER_AI: int = 1
const RESOURCE_IDS: PackedStringArray = ["food", "wood", "gold", "stone"]

var current_map_id: String = ""
## Era of the human player (kept for the HUD); per-player eras live in `eras`.
var era: int = 1
## player_id -> era (1..4)
var eras: Dictionary = {}
## player_id -> { "food": int, "wood": int, "gold": int, "stone": int }
var resources: Dictionary = {}
## player_id -> civ id
var civs: Dictionary = {}
## player_id -> { "used": int, "cap": int }
var population: Dictionary = {}
## player_id -> { key: multiplier } (e.g. "gather.wood": 1.1). Default 1.0.
var multipliers: Dictionary = {}
## player_id -> { key: flat bonus } (e.g. "carry_capacity": 5). Default 0.
var additions: Dictionary = {}
## player_id -> { "gathered": {res: int}, ... } for end-of-match screens and tests.
var stats: Dictionary = {}
## player_id -> { tech_id: true }
var researched: Dictionary = {}
## Market sell prices: player -> {resource: gold per lot}.
var market_prices: Dictionary = {}
## Set by the main menu before loading the match scene:
## {"scenario": id, "ai": {"1": "normal"}} or {"load": slot}. Consumed once.
var launch: Dictionary = {}


func _ready() -> void:
	new_match("skirmish_120", "northvale", "northvale")


## Resets the state for a fresh match using starting values from civs.json.
func new_match(map_id: String, human_civ: String, ai_civ: String) -> void:
	current_map_id = map_id
	era = 1
	eras = {PLAYER_HUMAN: 1, PLAYER_AI: 1}
	civs = {PLAYER_HUMAN: human_civ, PLAYER_AI: ai_civ}
	resources = {}
	population = {}
	multipliers = {}
	additions = {}
	stats = {}
	researched = {}
	market_prices = {}
	for player_id: int in civs.keys():
		var civ: Dictionary = DataLoader.get_entry("civs", String(civs[player_id]))
		var starting: Dictionary = civ.get("starting_resources", {})
		var bag: Dictionary = {}
		for res_id: String in RESOURCE_IDS:
			bag[res_id] = int(starting.get(res_id, 0))
		resources[player_id] = bag
		population[player_id] = {"used": 0, "cap": 0}
		multipliers[player_id] = {}
		additions[player_id] = {}
		researched[player_id] = {}
		stats[player_id] = {"gathered": {"food": 0, "wood": 0, "gold": 0, "stone": 0}}


func era_of(player_id: int) -> int:
	return int(eras.get(player_id, 1))


func set_era(player_id: int, value: int) -> void:
	eras[player_id] = value
	if player_id == PLAYER_HUMAN:
		era = value


func get_resource(player_id: int, resource: String) -> int:
	var bag: Dictionary = resources.get(player_id, {})
	return int(bag.get(resource, 0))


## Adds (or subtracts, if negative) an amount. Never goes below zero.
func add_resource(player_id: int, resource: String, amount: int) -> void:
	if not resources.has(player_id):
		return
	var bag: Dictionary = resources[player_id]
	var new_value: int = maxi(0, int(bag.get(resource, 0)) + amount)
	bag[resource] = new_value
	EventBus.resource_changed.emit(player_id, resource, new_value)


func can_afford(player_id: int, cost: Dictionary) -> bool:
	for res: String in cost.keys():
		if get_resource(player_id, res) < int(cost[res]):
			return false
	return true


## Subtracts a cost if affordable. Returns false (and changes nothing) otherwise.
func spend(player_id: int, cost: Dictionary) -> bool:
	if not can_afford(player_id, cost):
		return false
	for res: String in cost.keys():
		add_resource(player_id, res, -int(cost[res]))
	return true


func record_gathered(player_id: int, resource: String, amount: int) -> void:
	var gathered: Dictionary = Dictionary(stats.get(player_id, {})).get("gathered", {})
	gathered[resource] = int(gathered.get(resource, 0)) + amount


func gathered(player_id: int, resource: String) -> int:
	return int(Dictionary(Dictionary(stats.get(player_id, {})).get("gathered", {})).get(resource, 0))


## Returns true if the value changed.
func set_population(player_id: int, used: int, cap: int) -> bool:
	var pop: Dictionary = population.get(player_id, {"used": -1, "cap": -1})
	if int(pop.get("used", -1)) == used and int(pop.get("cap", -1)) == cap:
		return false
	population[player_id] = {"used": used, "cap": cap}
	return true


func pop_used(player_id: int) -> int:
	return int(Dictionary(population.get(player_id, {})).get("used", 0))


func pop_cap(player_id: int) -> int:
	return int(Dictionary(population.get(player_id, {})).get("cap", 0))


func modifier(player_id: int, key: String) -> float:
	return float(Dictionary(multipliers.get(player_id, {})).get(key, 1.0))


func modifier_add(player_id: int, key: String) -> float:
	return float(Dictionary(additions.get(player_id, {})).get(key, 0.0))


## Serialises the state to a plain Dictionary (used by SaveManager).
func to_dict() -> Dictionary:
	return {
		"map_id": current_map_id,
		"era": era,
		"eras": eras.duplicate(true),
		"civs": civs.duplicate(true),
		"resources": resources.duplicate(true),
		"multipliers": multipliers.duplicate(true),
		"additions": additions.duplicate(true),
		"stats": stats.duplicate(true),
		"researched": researched.duplicate(true),
		"market_prices": market_prices.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	current_map_id = String(data.get("map_id", current_map_id))
	era = int(data.get("era", era))
	eras = _int_keys(data.get("eras", {PLAYER_HUMAN: era, PLAYER_AI: 1}))
	for k: Variant in eras.keys():
		eras[k] = int(eras[k])
	civs = _int_keys(data.get("civs", {}))
	resources = {}
	var raw_resources: Dictionary = data.get("resources", {})
	for key: Variant in raw_resources.keys():
		var bag: Dictionary = raw_resources[key]
		var typed_bag: Dictionary = {}
		for res_id: Variant in bag.keys():
			typed_bag[String(res_id)] = int(bag[res_id])
		resources[int(key)] = typed_bag
	market_prices = _int_keys(data.get("market_prices", {}))
	multipliers = _int_keys(data.get("multipliers", {}))
	additions = _int_keys(data.get("additions", {}))
	stats = _int_keys(data.get("stats", {}))
	researched = _int_keys(data.get("researched", {}))


## JSON turns int keys into strings; restore them.
func _int_keys(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in raw.keys():
		var value: Variant = raw[key]
		out[int(key)] = value.duplicate(true) if value is Dictionary else value
	return out
