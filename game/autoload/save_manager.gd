extends Node
## Writes and reads match saves as JSON under user://.
## F0 only ships the plumbing; autosave every 2 min is wired in F8.

const SAVE_DIR: String = "user://"
const SAVE_EXTENSION: String = ".json"
const SAVE_VERSION: int = 1


func save_path(slot: String) -> String:
	return SAVE_DIR + "save_" + slot + SAVE_EXTENSION


## Persists the current GameState into the given slot. Returns OK or an Error.
func save_game(slot: String) -> Error:
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"state": GameState.to_dict(),
	}
	var file: FileAccess = FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK


## Loads a slot into GameState. Returns OK, ERR_DOES_NOT_EXIST or ERR_PARSE_ERROR.
func load_game(slot: String) -> Error:
	var path: String = save_path(slot)
	if not FileAccess.file_exists(path):
		return ERR_DOES_NOT_EXIST
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return ERR_PARSE_ERROR
	if not (json.data is Dictionary):
		return ERR_PARSE_ERROR
	var payload: Dictionary = json.data
	GameState.from_dict(payload.get("state", {}))
	return OK


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(save_path(slot))


func delete_save(slot: String) -> Error:
	if not has_save(slot):
		return ERR_DOES_NOT_EXIST
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path(slot)))


## Saves an arbitrary match snapshot (SaveGame.snapshot) into a slot.
func save_payload(slot: String, payload: Dictionary) -> Error:
	var wrapped: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"saved_unix": Time.get_unix_time_from_system(),
		"match": payload,
	}
	var file: FileAccess = FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(wrapped))
	file.close()
	return OK


## The match snapshot stored in a slot, or {} if missing/corrupt.
func load_payload(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path(slot))) != OK or not (json.data is Dictionary):
		return {}
	return Dictionary(json.data).get("match", {})


## Most recent match slot ("auto" or "manual"), or "" if none.
func latest_slot() -> String:
	var best: String = ""
	var best_t: float = -1.0
	for slot: String in ["auto", "manual"]:
		if not has_save(slot):
			continue
		var json: JSON = JSON.new()
		if json.parse(FileAccess.get_file_as_string(save_path(slot))) != OK or not (json.data is Dictionary):
			continue
		var data: Dictionary = json.data
		if not data.has("match"):
			continue
		var t: float = float(data.get("saved_unix", 0.0))
		if t > best_t:
			best_t = t
			best = slot
	return best
