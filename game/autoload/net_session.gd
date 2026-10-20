extends Node
## LAN session (autoload "NetSession"): hosts or joins a match over ENet,
## keeps the peer alive across the menu -> match scene change, and carries
## what both devices must agree on before the first tick: map, seed and who
## plays which seat (host = player 0, client = player 1).
## The lobby handshake is one RPC: the host's start_match() tells the client
## the map, the seed and the seat table; both then load the match scene.

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal joined_host
signal join_failed
signal match_starting(map_id: String, match_seed: int)

const MAIN_SCENE: String = "res://scenes/main/main.tscn"
const LAST_IP_FILE: String = "user://last_host_ip.txt"

var active: bool = false
var is_host: bool = false
var map_id: String = "skirmish_120"
var match_seed: int = 0
var local_player: int = 0
## player_id -> peer_id
var players: Dictionary = {}
var port: int = 7777
## Tests run two sessions in one process and must not change the scene.
var change_scene: bool = true
var _peer: ENetMultiplayerPeer = null


func _ready() -> void:
	port = int(DataLoader.rule("net", "port", 7777))
	multiplayer.peer_connected.connect(func(id: int) -> void: peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	multiplayer.connected_to_server.connect(func() -> void: joined_host.emit())
	multiplayer.connection_failed.connect(func() -> void:
		leave()
		join_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void:
		leave()
		join_failed.emit())


## Opens a server for one rival on `p_port` (0 = rules.json net.port).
func host(p_port: int = 0) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_server(p_port if p_port > 0 else port, 1)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = true
	return OK


func join(ip: String, p_port: int = 0) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(ip.strip_edges(), p_port if p_port > 0 else port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = false
	_remember_ip(ip.strip_edges())
	return OK


## Closes the connection and goes back to a solo seat.
func leave() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer = null
	active = false
	is_host = false
	players = {}
	local_player = 0
	GameState.set_local_player(0)


func peer_count() -> int:
	if not active or multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_peers().size()


## Host only: picks the seed, seats the players and starts on both devices.
func start_match(p_map: String) -> bool:
	if not is_host or peer_count() < 1:
		return false
	var rival: int = multiplayer.get_peers()[0]
	var seed_value: int = randi() & 0x7fffffff
	var seats: Dictionary = {0: 1, 1: rival}
	_rpc_start.rpc(p_map, seed_value, seats)
	_begin(p_map, seed_value, seats)
	return true


@rpc("authority", "call_remote", "reliable")
func _rpc_start(p_map: String, seed_value: int, seats: Dictionary) -> void:
	_begin(p_map, seed_value, seats)


func _begin(p_map: String, seed_value: int, seats: Dictionary) -> void:
	map_id = p_map
	match_seed = seed_value
	players = {}
	for k: Variant in seats.keys():
		players[int(k)] = int(seats[k])
	var me: int = multiplayer.get_unique_id()
	local_player = 0
	for p: Variant in players.keys():
		if int(players[p]) == me:
			local_player = int(p)
	GameState.set_local_player(local_player)
	if OS.is_debug_build():
		print("[REALM] net start map=%s seed=%d seat=%d peers=%s" % [map_id, match_seed, local_player, str(players)])
	match_starting.emit(map_id, match_seed)
	if change_scene:
		GameState.launch = {"net": true}
		get_tree().change_scene_to_file(MAIN_SCENE)


## IPv4 addresses of this device on private networks (what the rival types).
static func local_ips() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for ip: String in IP.get_local_addresses():
		if ip.count(".") != 3 or ip.begins_with("127."):
			continue
		if ip.begins_with("192.168.") or ip.begins_with("10.") or _is_172_private(ip):
			out.append(ip)
	for ip: String in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not out.has(ip):
			out.append(ip)
	return out


static func _is_172_private(ip: String) -> bool:
	if not ip.begins_with("172."):
		return false
	var second: int = int(ip.split(".")[1])
	return second >= 16 and second <= 31


func last_ip() -> String:
	if FileAccess.file_exists(LAST_IP_FILE):
		return FileAccess.get_file_as_string(LAST_IP_FILE).strip_edges()
	return ""


func _remember_ip(ip: String) -> void:
	var f: FileAccess = FileAccess.open(LAST_IP_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(ip)
