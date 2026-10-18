extends Node
## Loads every JSON table from res://data/ once at startup.
## All balance and content lives in those files, never in scripts.

const DATA_DIR: String = "res://data/"
const TABLE_FILES: Dictionary = {
	"units": "units.json",
	"buildings": "buildings.json",
	"techs": "techs.json",
	"civs": "civs.json",
	"terrain": "terrain.json",
	"rules": "rules.json",
	"audio": "audio.json",
	"scenarios": "scenarios.json",
	"resources": "resources.json",
	"stances": "stances.json",
	"ai": "ai.json",
	"eras": "eras.json",
}
const MAPS_DIR: String = "res://data/maps/"

var _tables: Dictionary = {}
var _maps: Dictionary = {}
var load_errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()


## (Re)loads every table and map definition from disk.
func reload() -> void:
	_tables.clear()
	_maps.clear()
	load_errors.clear()
	for table_name: String in TABLE_FILES.keys():
		var path: String = DATA_DIR + String(TABLE_FILES[table_name])
		var parsed: Variant = _read_json(path)
		if parsed is Dictionary:
			_tables[table_name] = parsed
		else:
			_tables[table_name] = {}
	_load_maps()


## Returns a whole table (e.g. "units") as a Dictionary. Empty if missing.
func get_table(table_name: String) -> Dictionary:
	return _tables.get(table_name, {})


## Returns one entry of a table, e.g. get_entry("terrain", "grass").
## The result is shared: treat it as read-only (duplicate() before mutating).
func get_entry(table_name: String, entry_id: String) -> Dictionary:
	var table: Dictionary = get_table(table_name)
	return table.get(entry_id, {})


## Reads a tunable from rules.json, e.g. rule("input", "drag_threshold_px", 30).
func rule(section: String, key: String, fallback: Variant) -> Variant:
	var rules: Dictionary = get_table("rules")
	var block: Dictionary = rules.get(section, {})
	return block.get(key, fallback)


## Returns a map definition by id (file name without .json).
func get_map(map_id: String) -> Dictionary:
	return _maps.get(map_id, {})


func get_map_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for key: String in _maps.keys():
		ids.append(key)
	return ids


func _load_maps() -> void:
	var dir: DirAccess = DirAccess.open(MAPS_DIR)
	if dir == null:
		load_errors.append("Cannot open maps dir: " + MAPS_DIR)
		push_error("DataLoader: cannot open " + MAPS_DIR)
		return
	for file_name: String in dir.get_files():
		# Exported builds may list .json.remap / .json.import entries;
		# normalise so editor and export resolve the same map id.
		var clean_name: String = file_name.replace(".remap", "").replace(".import", "")
		if not clean_name.ends_with(".json"):
			continue
		if _maps.has(clean_name.get_basename()):
			continue
		var parsed: Variant = _read_json(MAPS_DIR + clean_name)
		if parsed is Dictionary:
			_maps[clean_name.get_basename()] = parsed


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_errors.append("Missing file: " + path)
		push_error("DataLoader: missing file " + path)
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		var msg: String = "%s:%d %s" % [path, json.get_error_line(), json.get_error_message()]
		load_errors.append(msg)
		push_error("DataLoader: " + msg)
		return null
	return json.data
