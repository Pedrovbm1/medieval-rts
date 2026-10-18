class_name MatchRules
extends Node
## Victory / defeat and match statistics.
## A player with no buildings left (built or under construction) is defeated;
## the other player wins. Checked once per second, not every frame.

signal match_ended(winner_id: int, loser_id: int, seconds: float)

const CHECK_INTERVAL: float = 1.0

var world: World
var elapsed: float = 0.0
var ended: bool = false
var winner_id: int = -1
## Players that started with buildings: only they can lose. With fewer than
## two (sandbox, tests, demos) there is no match to decide.
var contenders: Array[int] = []
var _timer: float = 0.0


func setup(p_world: World) -> void:
	world = p_world
	# Fixed at match start (after the scenario or a save placed the buildings).
	for b: Building in world.buildings:
		if b.owner_id >= 0 and not contenders.has(b.owner_id):
			contenders.append(b.owner_id)
	if contenders.size() < 2:
		contenders = [-1]  # no rival: never end
	EventBus.unit_trained.connect(func(u: Unit, _b: Building) -> void: _bump(u.owner_id, "trained", 1))
	EventBus.unit_removed.connect(_on_unit_removed)
	EventBus.building_removed.connect(func(b: Building) -> void:
		if b.hp <= 0:
			_bump(b.owner_id, "buildings_lost", 1))


func _physics_process(delta: float) -> void:
	if world == null or ended:
		return
	elapsed += delta
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	if contenders.has(-1):
		return
	var alive: Dictionary = {}
	for p: int in contenders:
		alive[p] = false
	for b: Building in world.buildings:
		if alive.has(b.owner_id):
			alive[b.owner_id] = true
	for p: int in alive.keys():
		if not alive[p]:
			var other: int = GameState.PLAYER_AI if p == GameState.PLAYER_HUMAN else GameState.PLAYER_HUMAN
			finish(other, p)
			return


func finish(p_winner: int, loser: int) -> void:
	if ended:
		return
	ended = true
	winner_id = p_winner
	if OS.is_debug_build():
		print("[REALM] match_end winner=%d t=%.0f" % [p_winner, elapsed])
	match_ended.emit(p_winner, loser, elapsed)
	EventBus.match_ended.emit(p_winner, elapsed)


func stat(player_id: int, key: String) -> int:
	return int(Dictionary(GameState.stats.get(player_id, {})).get(key, 0))


func _on_unit_removed(u: Unit) -> void:
	if not u.is_dead or u.owner_id < 0:
		return
	_bump(u.owner_id, "lost", 1)
	if u.last_attacker != null and is_instance_valid(u.last_attacker) and u.last_attacker.owner_id >= 0:
		_bump(u.last_attacker.owner_id, "kills", 1)


func _bump(player_id: int, key: String, amount: int) -> void:
	if not GameState.stats.has(player_id):
		return
	var s: Dictionary = GameState.stats[player_id]
	s[key] = int(s.get(key, 0)) + amount
