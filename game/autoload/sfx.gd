extends Node
## Plays short sound effects by id. Ids map to one file or a list of variants
## in data/audio.json, so sounds change without touching code. A pool of
## players lets rapid sounds overlap instead of cutting each other.
##
## World sounds go through play_at(): they only play when the spot is on
## screen (you hear what you see, like the genre does) and each id has a
## minimum gap so 40 swords hitting at once do not become noise.

const POOL_SIZE: int = 10
const SCREEN_MARGIN: float = 96.0

var muted: bool = false
## Sounds actually played per id (tests read this; headless has no audio).
var played: Dictionary = {}

var _streams: Dictionary = {}  # id -> Array[AudioStream]
var _gap: Dictionary = {}  # id -> min seconds between plays
var _last: Dictionary = {}  # id -> last play time (s)
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _volume_db: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var audio: Dictionary = DataLoader.get_table("audio")
	_volume_db = float(audio.get("sfx_db", 0.0))
	var default_gap: float = float(audio.get("sfx_default_gap_s", 0.05))
	var gaps: Dictionary = audio.get("sfx_gap_s", {})
	var table: Dictionary = audio.get("sfx", {})
	for sfx_id: String in table.keys():
		var paths: Array = table[sfx_id] if table[sfx_id] is Array else [table[sfx_id]]
		var list: Array[AudioStream] = []
		for path: Variant in paths:
			if ResourceLoader.exists(String(path)):
				list.append(load(String(path)))
			else:
				push_warning("Sfx: missing " + String(path))
		_streams[sfx_id] = list
		_gap[sfx_id] = float(gaps.get(sfx_id, default_gap))
	for i: int in POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.volume_db = _volume_db
		add_child(player)
		_players.append(player)


func has_sound(sfx_id: String) -> bool:
	return not (_streams.get(sfx_id, []) as Array).is_empty()


## UI / global sound: always audible (subject to the per-id gap).
func play(sfx_id: String, pitch_jitter: float = 0.0) -> void:
	var list: Array = _streams.get(sfx_id, [])
	if list.is_empty() or muted:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sfx_id, -100.0)) < float(_gap.get(sfx_id, 0.0)):
		return
	_last[sfx_id] = now
	played[sfx_id] = int(played.get(sfx_id, 0)) + 1
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = list[_rng.randi() % list.size()]
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.play()


## World sound at a map position: only if that spot is on screen.
## Returns true if it played (used to wake the battle music).
func play_at(sfx_id: String, world_pos: Vector2) -> bool:
	if sfx_id.is_empty() or not on_screen(world_pos):
		return false
	var before: int = int(played.get(sfx_id, 0))
	play(sfx_id, 0.08)
	return int(played.get(sfx_id, 0)) > before


func on_screen(world_pos: Vector2) -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return false
	var half: Vector2 = vp.get_visible_rect().size * 0.5 / cam.zoom
	var rect: Rect2 = Rect2(cam.get_screen_center_position() - half, half * 2.0).grow(SCREEN_MARGIN)
	return rect.has_point(world_pos)
