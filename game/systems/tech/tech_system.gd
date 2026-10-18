class_name TechSystem
extends RefCounted
## Eras and technologies (data/eras.json, data/techs.json).
## Research runs through building queues as items prefixed with "#":
## "#era2" at the Town Center, "#forging" at the Blacksmith...
## Effects become per-player modifiers in GameState (multipliers / additions)
## that the other systems already read; existing units are refreshed.

const PREFIX: String = "#"

var world: World


func setup(p_world: World) -> void:
	world = p_world


static func is_research(item: String) -> bool:
	return item.begins_with(PREFIX)


static func era_item(era: int) -> String:
	return "%sera%d" % [PREFIX, era]


## Data block for a queue item: a tech, an era, or a unit.
static func item_def(item: String) -> Dictionary:
	if not is_research(item):
		return DataLoader.get_entry("units", item)
	var id: String = item.substr(PREFIX.length())
	if id.begins_with("era"):
		return DataLoader.get_entry("eras", id.substr(3))
	return DataLoader.get_entry("techs", id)


static func item_cost(item: String) -> Dictionary:
	return item_def(item).get("cost", {})


static func item_time(item: String) -> float:
	var def: Dictionary = item_def(item)
	return float(def.get("research_time", def.get("train_time", 20.0)))


func is_researched(player_id: int, tech_id: String) -> bool:
	return Dictionary(GameState.researched.get(player_id, {})).has(tech_id)


func is_queued(player_id: int, item: String) -> bool:
	for b: Building in world.buildings:
		if b.owner_id == player_id and b.queue.has(item):
			return true
	return false


## Techs a building offers right now (era reached, not done, not queued).
func techs_at(b: Building) -> Array[String]:
	var out: Array[String] = []
	var table: Dictionary = DataLoader.get_table("techs")
	for id: String in table.keys():
		var t: Dictionary = table[id]
		if String(t.get("researched_at", "")) != b.building_type:
			continue
		if int(t.get("era", 1)) > GameState.era_of(b.owner_id) or is_researched(b.owner_id, id) or is_queued(b.owner_id, PREFIX + id):
			continue
		out.append(id)
	out.sort()
	return out


## "" if `b` can research `item` now, else a reason: done | queued | era | type | cost | requires | max.
func research_error(b: Building, item: String) -> String:
	var id: String = item.substr(PREFIX.length())
	if id.begins_with("era"):
		var target: int = int(id.substr(3))
		var rules: Dictionary = DataLoader.get_entry("eras", "_rules")
		if b.building_type != String(rules.get("researched_at", "town_center")):
			return "type"
		if target != GameState.era_of(b.owner_id) + 1 or DataLoader.get_entry("eras", str(target)).is_empty():
			return "max"
		if is_queued(b.owner_id, item):
			return "queued"
		if era_buildings(b.owner_id) < int(DataLoader.get_entry("eras", str(target)).get("requires_buildings", 2)):
			return "requires"
		if not GameState.can_afford(b.owner_id, item_cost(item)):
			return "cost"
		return ""
	var t: Dictionary = DataLoader.get_entry("techs", id)
	if t.is_empty() or String(t.get("researched_at", "")) != b.building_type:
		return "type"
	if is_researched(b.owner_id, id):
		return "done"
	if is_queued(b.owner_id, item):
		return "queued"
	if int(t.get("era", 1)) > GameState.era_of(b.owner_id):
		return "era"
	if not GameState.can_afford(b.owner_id, item_cost(item)):
		return "cost"
	return ""


## Distinct building types of the player's current era (excluding the ones
## eras.json says do not count), complete only. Era advance needs 2.
func era_buildings(player_id: int) -> int:
	var era: int = GameState.era_of(player_id)
	var exclude: Array = DataLoader.get_entry("eras", "_rules").get("exclude_from_requirement", [])
	var types: Dictionary = {}
	for b: Building in world.buildings:
		if b.owner_id == player_id and b.is_complete() and int(b.data.get("era", 1)) == era and not exclude.has(b.building_type):
			types[b.building_type] = true
	return types.size()


## Applies a finished research item.
func complete(player_id: int, item: String) -> void:
	var id: String = item.substr(PREFIX.length())
	if id.begins_with("era"):
		var era: int = int(id.substr(3))
		GameState.set_era(player_id, era)
		EventBus.era_changed.emit(player_id, era)
		if OS.is_debug_build():
			print("[REALM] era player=%d era=%d" % [player_id, era])
		return
	var t: Dictionary = DataLoader.get_entry("techs", id)
	var mults: Dictionary = GameState.multipliers.get(player_id, {})
	var adds: Dictionary = GameState.additions.get(player_id, {})
	for e: Variant in t.get("effects", []):
		var effect: Dictionary = e
		var key: String = String(effect["key"])
		if effect.has("mult"):
			mults[key] = float(mults.get(key, 1.0)) * float(effect["mult"])
		if effect.has("add"):
			adds[key] = float(adds.get(key, 0.0)) + float(effect["add"])
	GameState.multipliers[player_id] = mults
	GameState.additions[player_id] = adds
	var done: Dictionary = GameState.researched.get(player_id, {})
	done[id] = true
	GameState.researched[player_id] = done
	world.refresh_stats(player_id)
	EventBus.tech_researched.emit(player_id, id)
	if OS.is_debug_build():
		print("[REALM] tech player=%d %s" % [player_id, id])


## Every modifier key prefix a tech may use, and who reads it. Used by the
## "no orphan techs" test: an effect outside this list would do nothing.
const CONSUMED_KEYS: PackedStringArray = [
	"gather.", "carry_capacity", "build_speed", "attack.", "armor.", "speed.", "hp.", "range.", "repeat.", "sight.",
]
