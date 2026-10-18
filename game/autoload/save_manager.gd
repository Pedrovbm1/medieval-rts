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
