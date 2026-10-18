extends Node
## Holds the match state shared by every system: resources, era, population.
## F0 only initialises it from civs.json; economy logic arrives in F3.

const PLAYER_HUMAN: int = 0
const PLAYER_AI: int = 1
const RESOURCE_IDS: PackedStringArray = ["food", "wood", "gold", "stone"]

var current_map_id: String = ""
var era: int = 1
## player_id -> { "food": int, "wood": int, "gold": int, "stone": int }
var resources: Dictionary = {}
## player_id -> civ id
var civs: Dictionary = {}


func _ready() -> void:
	new_match("skirmish_120", "northvale", "northvale")


## Resets the state for a fresh match using starting values from civs.json.
func new_match(map_id: String, human_civ: String, ai_civ: String) -> void:
	current_map_id = map_id
	era = 1
	civs = {PLAYER_HUMAN: human_civ, PLAYER_AI: ai_civ}
	resources = {}
	for player_id: int in civs.keys():
		var civ: Dictionary = DataLoader.get_entry("civs", String(civs[player_id]))
		var starting: Dictionary = civ.get("starting_resources", {})
		var bag: Dictionary = {}
		for res_id: String in RESOURCE_IDS:
			bag[res_id] = int(starting.get(res_id, 0))
		resources[player_id] = bag


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


## Serialises the state to a plain Dictionary (used by SaveManager).
func to_dict() -> Dictionary:
	return {
		"map_id": current_map_id,
		"era": era,
		"civs": civs.duplicate(true),
		"resources": resources.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	current_map_id = String(data.get("map_id", current_map_id))
	era = int(data.get("era", era))
	var raw_civs: Dictionary = data.get("civs", {})
	civs = {}
	for key: Variant in raw_civs.keys():
		civs[int(key)] = String(raw_civs[key])
	var raw_resources: Dictionary = data.get("resources", {})
	resources = {}
	for key: Variant in raw_resources.keys():
		var bag: Dictionary = raw_resources[key]
		var typed_bag: Dictionary = {}
		for res_id: Variant in bag.keys():
			typed_bag[String(res_id)] = int(bag[res_id])
		resources[int(key)] = typed_bag
