extends Node
## Plays short sound effects by id. Ids map to files in data/audio.json, so
## F9 swaps the sounds without touching code. Small pool of players so rapid
## orders overlap instead of cutting each other.

const POOL_SIZE: int = 6

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	var table: Dictionary = DataLoader.get_table("audio").get("sfx", {})
	for sfx_id: String in table.keys():
		var path: String = String(table[sfx_id])
		if ResourceLoader.exists(path):
			_streams[sfx_id] = load(path)
		else:
			push_warning("Sfx: missing " + path)
	for i: int in POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


func play(sfx_id: String) -> void:
	var stream: AudioStream = _streams.get(sfx_id, null)
	if stream == null:
		return
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.play()
