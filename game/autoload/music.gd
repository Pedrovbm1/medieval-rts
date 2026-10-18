extends Node
## Background music with crossfades. Themes are looping files listed in
## data/audio.json ("music"). In a match the calm theme plays; when fighting
## happens on screen (combat_ping) it switches to the battle theme and falls
## back to calm after `battle_hold_s` without new fighting.

var muted: bool = false
var current: String = ""

var _themes: Dictionary = {}
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _volume_db: float = -6.0
var _fade_s: float = 1.5
var _battle_hold_s: float = 25.0
var _battle_until: float = -1.0
var _calm_theme: String = "peace"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var audio: Dictionary = DataLoader.get_table("audio")
	_volume_db = float(audio.get("music_db", -6.0))
	_fade_s = float(audio.get("music_fade_s", 1.5))
	_battle_hold_s = float(audio.get("battle_hold_s", 25.0))
	var table: Dictionary = audio.get("music", {})
	for id: String in table.keys():
		var path: String = String(table[id])
		if ResourceLoader.exists(path):
			_themes[id] = load(path)
		else:
			push_warning("Music: missing " + path)
	_a = _make_player()
	_b = _make_player()


func _make_player() -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.volume_db = -80.0
	p.finished.connect(func() -> void:
		if p.volume_db > -79.0:
			p.play())
	add_child(p)
	return p


## Switches to a theme with a crossfade. "peace" also becomes the calm theme
## the battle music returns to.
func play_theme(id: String) -> void:
	if id != "battle":
		_calm_theme = id
	if id == current or not _themes.has(id):
		return
	current = id
	var old: AudioStreamPlayer = _a
	_a = _b
	_b = old
	_a.stream = _themes[id]
	_a.volume_db = -40.0
	if not muted:
		_a.play()
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_a, "volume_db", _volume_db, _fade_s)
	tw.tween_property(_b, "volume_db", -80.0, _fade_s)
	tw.chain().tween_callback(_b.stop)


## Fighting is visible: switch to (or keep) the battle theme.
func combat_ping() -> void:
	_battle_until = Time.get_ticks_msec() / 1000.0 + _battle_hold_s
	if current != "battle":
		play_theme("battle")


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		_a.stop()
		_b.stop()
	elif current != "" and _themes.has(current):
		_a.stream = _themes[current]
		_a.volume_db = _volume_db
		_a.play()


func stop() -> void:
	current = ""
	_a.stop()
	_b.stop()


func _process(_delta: float) -> void:
	if current == "battle" and Time.get_ticks_msec() / 1000.0 > _battle_until:
		play_theme(_calm_theme)
