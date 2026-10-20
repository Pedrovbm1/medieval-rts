class_name Lockstep
extends Node
## Deterministic lockstep for a networked match ("everyone simulates, only
## orders travel"). Time is cut into turns of `turn_ticks` physics ticks. A
## command given during turn T is scheduled for turn T + delay_turns and sent
## to every peer; at the first tick of a turn, every player's bundle for that
## turn must be here, or the simulation is held (process_mode DISABLED on the
## sim nodes) until it arrives. Both devices then apply the same commands in
## the same order (player 0 first) before the same tick runs.
## Every `hash_every_turns` turns the world hash travels with the bundle and
## a mismatch raises `desync` (shown on screen; the match goes on).
## Runs with process_priority -100 so it decides before World ticks.

signal started
signal waiting_changed(waiting: bool)
signal desync(turn: int, mine: int, theirs: int)
signal turn_advanced(turn: int)
signal peer_lost(player: int)

var turn_ticks: int = 6
var delay_turns: int = 2
var hash_every_turns: int = 20
## Seconds of stall before the HUD says "waiting for the rival".
var waiting_banner_s: float = 0.5

var local_player: int = 0
## player_id -> peer_id (the host is peer 1).
var players: Dictionary = {}
## Networked mode on (CommandBus routes submits here).
var active: bool = false
## Both sides ready: the simulation runs.
var is_started: bool = false
var turn: int = 0
var tick_in_turn: int = 0
var waiting: bool = false
var desynced_turn: int = -1
## Nodes whose processing is held while a bundle is missing (World, rules...).
var sim_nodes: Array[Node] = []
## apply_callback(cmd: Dictionary); hash_callback() -> int.
var apply_callback: Callable
var hash_callback: Callable
## Counters for the HUD / tests.
var bundles_sent: int = 0
var bundles_received: int = 0
var commands_applied: int = 0
var stalled_ticks: int = 0

var _pending_local: Array[Dictionary] = []
## turn -> {player -> Array[Dictionary]}
var _bundles: Dictionary = {}
var _my_hashes: Dictionary = {}
## turn -> {player -> hash}
var _their_hashes: Dictionary = {}
var _ready_players: Dictionary = {}
var _ready_resend_t: float = 0.0
var _wait_t: float = 0.0
var _sim_enabled: bool = true


func _ready() -> void:
	process_priority = -100
	turn_ticks = int(DataLoader.rule("net", "turn_ticks", 6))
	delay_turns = int(DataLoader.rule("net", "delay_turns", 2))
	hash_every_turns = int(DataLoader.rule("net", "hash_every_turns", 20))
	waiting_banner_s = float(DataLoader.rule("net", "waiting_banner_s", 0.5))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Wires the node to a match and holds the simulation at once (nothing may
## tick before the first turn). `p_players` maps player id -> peer id.
func setup(p_local: int, p_players: Dictionary, p_sim_nodes: Array[Node], p_apply: Callable, p_hash: Callable) -> void:
	local_player = p_local
	players = p_players.duplicate()
	sim_nodes = p_sim_nodes
	apply_callback = p_apply
	hash_callback = p_hash
	active = true
	_set_sim(false)


## Call once the match scene is built: tells the peers we are ready. The
## first turn runs when every player said so.
func start() -> void:
	active = true
	_set_sim(false)
	_local_ready = true
	_ready_players[local_player] = true
	_send_ready()


## start() was called here (only then do we tell the peers we are ready).
var _local_ready: bool = false


## A local command: scheduled for a later turn and sent to everyone.
func queue_local(cmd: Dictionary) -> void:
	cmd["player"] = local_player
	_pending_local.append(cmd)


func remote_players() -> Array[int]:
	var out: Array[int] = []
	for p: Variant in players.keys():
		if int(p) != local_player:
			out.append(int(p))
	return out


func all_ready() -> bool:
	for p: Variant in players.keys():
		if not _ready_players.has(int(p)):
			return false
	return true


## Every remote player's bundle for `t` is here (turns before the first
## delayed bundle are empty by definition).
func has_turn(t: int) -> bool:
	if t < delay_turns:
		return true
	var by_player: Dictionary = _bundles.get(t, {})
	for p: int in remote_players():
		if not by_player.has(p):
			return false
	return true


func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_started:
		_set_sim(false)
		_ready_resend_t += delta
		if _ready_resend_t >= 0.5:
			_ready_resend_t = 0.0
			_send_ready()
		if not all_ready():
			return
		is_started = true
		started.emit()
	if tick_in_turn == 0:
		if not has_turn(turn):
			_set_sim(false)
			stalled_ticks += 1
			_wait_t += delta
			if _wait_t >= waiting_banner_s and not waiting:
				waiting = true
				waiting_changed.emit(true)
			return
		_set_sim(true)
		_wait_t = 0.0
		if waiting:
			waiting = false
			waiting_changed.emit(false)
		if hash_every_turns > 0 and turn % hash_every_turns == 0 and hash_callback.is_valid():
			_my_hashes[turn] = int(hash_callback.call())
			_compare(turn)
		_apply_turn(turn)
	tick_in_turn += 1
	if tick_in_turn >= turn_ticks:
		_end_turn()


func _apply_turn(t: int) -> void:
	var by_player: Dictionary = _bundles.get(t, {})
	var ids: Array = by_player.keys()
	ids.sort()
	for p: Variant in ids:
		for cmd: Dictionary in by_player[p]:
			commands_applied += 1
			if apply_callback.is_valid():
				apply_callback.call(cmd)
	_bundles.erase(t)


func _end_turn() -> void:
	var target: int = turn + delay_turns
	var bundle: Dictionary = {"turn": target, "cmds": _pending_local.duplicate(true), "hash_turn": -1, "hash": 0}
	if _my_hashes.has(turn):
		bundle["hash_turn"] = turn
		bundle["hash"] = _my_hashes[turn]
	_store(target, local_player, bundle["cmds"])
	_pending_local.clear()
	if not remote_players().is_empty():
		bundles_sent += 1
		_rpc_bundle.rpc(bundle)
	turn += 1
	tick_in_turn = 0
	_prune(turn - 64)
	turn_advanced.emit(turn)


func _store(t: int, player: int, cmds: Array) -> void:
	var by_player: Dictionary = _bundles.get(t, {})
	var list: Array[Dictionary] = []
	for c: Variant in cmds:
		var cmd: Dictionary = (c as Dictionary).duplicate(true)
		cmd["player"] = player
		list.append(cmd)
	by_player[player] = list
	_bundles[t] = by_player


func _compare(t: int) -> void:
	if desynced_turn >= 0 or not _my_hashes.has(t):
		return
	var theirs: Dictionary = _their_hashes.get(t, {})
	for p: Variant in theirs.keys():
		if int(theirs[p]) != int(_my_hashes[t]):
			desynced_turn = t
			if OS.is_debug_build():
				print("[REALM] net DESYNC turn=%d mine=%d theirs=%d" % [t, int(_my_hashes[t]), int(theirs[p])])
			desync.emit(t, int(_my_hashes[t]), int(theirs[p]))
			return
		hashes_matched += 1
		if OS.is_debug_build() and hashes_matched % 10 == 1:
			print("[REALM] net hash ok turn=%d matched=%d stalled_ticks=%d sent=%d recv=%d" % [t, hashes_matched, stalled_ticks, bundles_sent, bundles_received])


## Hash checks that agreed so far (soak tests read this from the log).
var hashes_matched: int = 0


func _prune(before: int) -> void:
	for d: Dictionary in [_my_hashes, _their_hashes]:
		for k: Variant in d.keys():
			if int(k) < before:
				d.erase(k)


func _set_sim(on: bool) -> void:
	if _sim_enabled == on:
		return
	_sim_enabled = on
	for n: Node in sim_nodes:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func sim_enabled() -> bool:
	return _sim_enabled


func _player_of(peer_id: int) -> int:
	for p: Variant in players.keys():
		if int(players[p]) == peer_id:
			return int(p)
	return -1


func _send_ready() -> void:
	if not _local_ready or remote_players().is_empty() or multiplayer.multiplayer_peer == null:
		return
	_rpc_ready.rpc()


func _on_peer_disconnected(peer_id: int) -> void:
	var p: int = _player_of(peer_id)
	if p >= 0 and active:
		peer_lost.emit(p)


# ------------------------------------------------------------------ rpc

@rpc("any_peer", "call_remote", "reliable")
func _rpc_bundle(bundle: Dictionary) -> void:
	var p: int = _player_of(multiplayer.get_remote_sender_id())
	if p < 0 or p == local_player:
		return
	bundles_received += 1
	_store(int(bundle.get("turn", 0)), p, bundle.get("cmds", []))
	var ht: int = int(bundle.get("hash_turn", -1))
	if ht >= 0:
		var by_player: Dictionary = _their_hashes.get(ht, {})
		by_player[p] = int(bundle.get("hash", 0))
		_their_hashes[ht] = by_player
		_compare(ht)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready() -> void:
	var p: int = _player_of(multiplayer.get_remote_sender_id())
	if p < 0:
		return
	var knew: bool = _ready_players.has(p)
	_ready_players[p] = true
	# Answer so a peer whose first "ready" reached us before our node existed
	# still learns we are here (once we are: see _local_ready).
	if not knew:
		_send_ready()
