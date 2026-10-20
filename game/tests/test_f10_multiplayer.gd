extends TestSuite
## F10-mp: lockstep multiplayer foundations.
## (a) Determinism: the same seed and the same commands at the same ticks give
##     the same world hash, tick after tick, in two separate runs (they run
##     one after the other because GameState is a shared autoload).
## (b) LAN lobby and turns: two ENet peers in this process (host + client on
##     localhost, each branch with its own MultiplayerAPI) agree on map and
##     seed, hold the simulation until the rival's turn arrives, apply a
##     command in the same turn on both sides and flag a hash mismatch.

const HASH_EVERY_TICKS: int = 30
const RUN_TICKS: int = 720
const PORT: int = 7791

var main: Node
var world: World


func _open(seed_value: int) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "skirmish"
	main.ai_override = {1: "normal"}
	main.ai_seed = 5
	main.match_seed = seed_value
	main.deterministic = true
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)
	main = null
	world = null


func _tc(owner: int) -> Building:
	for b: Building in world.buildings:
		if b.owner_id == owner and b.building_type == "town_center":
			return b
	return null


func _units(owner: int, gatherers: bool) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in world.units:
		if u.owner_id == owner and u.can_gather() == gatherers and not u.is_animal() and not u.is_dead:
			out.append(u)
	return out


## The script of player 0's match: what gets submitted at which tick. Every
## command is built from the world as it is at that tick (ids, positions), so
## two identical runs build identical commands.
func _scripted_commands(t: int, bus: CommandBus, sel: SelectionController) -> void:
	var tc: Building = _tc(0)
	match t:
		6:
			# Villagers 0-1 cut the nearest tree, 2 mines gold, 3 picks berries.
			var v: Array[Unit] = _units(0, true)
			var tree: Vector2i = world.find_tree_near(tc.position, 30)
			sel.set_selection([v[0], v[1]] as Array[Unit])
			sel.issue_order(world.cell_center(tree), sel.resolve_target(world.cell_center(tree)))
			var gold: ResourceNode = world.find_node_near("gold", tc.position, 4000.0)
			sel.set_selection([v[2]] as Array[Unit])
			sel.issue_order(gold.position, sel.resolve_target(gold.position))
			var berries: ResourceNode = world.find_node_near("berries", tc.position, 4000.0)
			sel.set_selection([v[3]] as Array[Unit])
			sel.issue_order(berries.position, sel.resolve_target(berries.position))
		12:
			bus.submit({"type": "train", "player": 0, "building": tc.sim_id, "item": "villager"})
			bus.submit({"type": "train", "player": 0, "building": tc.sim_id, "item": "villager"})
		60:
			# The scout attack-moves toward the rival in a line; one house goes up.
			var scouts: Array[Unit] = _units(0, false)
			sel.set_selection(scouts)
			sel.arm_attack_move(true)
			sel.formation = "line"
			sel.order_move(_tc(1).position)
			var v: Array[Unit] = _units(0, true)
			var spot: Vector2i = world.find_building_spot("house", tc.position + Vector2(300, 0))
			bus.submit({"type": "build", "player": 0, "building_type": "house", "cell": [spot.x, spot.y], "builders": [v[3].sim_id]})
		240:
			main.ring_bell()
		300:
			main.ring_bell()
		420:
			var v: Array[Unit] = _units(0, true)
			sel.set_selection(v.slice(0, 2))
			sel.order_stop()
			sel.set_selection(v.slice(0, 2))
			sel.order_move(tc.position + Vector2(0, 260))


## Runs inside the physics step, before World ticks: exactly once per tick
## (awaiting physics_frame from a test coroutine can skip ticks when several
## physics steps run in one frame).
class TickProbe extends Node:
	var world: World
	var on_tick: Callable
	func _ready() -> void:
		process_priority = -50
	func _physics_process(_d: float) -> void:
		if world != null and world.map_width > 0:
			on_tick.call(world.tick)


## Runs one match for RUN_TICKS ticks and returns the hash at every 30 ticks.
func _run_match(seed_value: int) -> Dictionary:
	# Set before the first tick: time_scale scales every tick's delta, so a
	# tick simulated at x1 before the change would differ between the runs.
	Engine.time_scale = 2.0
	# Godot applies a new time_scale from the next frame on: wait, or the
	# first tick of the first run gets the old delta (seen in this test).
	await frames(2)
	# The probe goes in before the first physics tick (building the map takes
	# a while and the next frame catches up several ticks at once).
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "skirmish"
	main.ai_override = {1: "normal"}
	main.ai_seed = 5
	main.match_seed = seed_value
	main.deterministic = true
	add_to_tree(main)
	world = main.get_node("World")
	var bus: CommandBus = main.get_node("CommandBus")
	var sel: SelectionController = main.get_node("SelectionController")
	var hashes: Dictionary = {}
	var dumps: Dictionary = {}
	var commands: int = 0
	var probe: TickProbe = TickProbe.new()
	probe.world = world
	probe.on_tick = func(t: int) -> void:
		_scripted_commands(t, bus, sel)
		if t % HASH_EVERY_TICKS == 0 or t <= 60:
			hashes[t] = world.state_hash()
			dumps[t] = world.state_lines()
	main.add_child(probe)
	check(world.tick == 0, "the probe is in place before the first tick (tick %d)" % world.tick)
	while world.tick < RUN_TICKS:
		await physics_frames(1)
	probe.queue_free()
	commands = bus.history.size()
	var cmd_ticks: Array = []
	for c: Dictionary in bus.history:
		cmd_ticks.append(int(c.get("tick", -1)))
	Engine.time_scale = 1.0
	var summary: Dictionary = {"hashes": hashes, "dumps": dumps, "commands": commands, "cmd_ticks": cmd_ticks, "units": world.units.size(),
		"wood": GameState.get_resource(0, "wood"), "buildings": world.buildings.size()}
	await _close()
	return summary


func test_a_same_seed_and_orders_give_the_same_hash_every_30_ticks() -> void:
	var a: Dictionary = await _run_match(777)
	var b: Dictionary = await _run_match(777)
	check(int(a["commands"]) >= 8 and a["cmd_ticks"] == b["cmd_ticks"], "both runs submitted the same %d commands at the same ticks %s / %s" % [int(a["commands"]), str(a["cmd_ticks"]), str(b["cmd_ticks"])])
	check(int(a["wood"]) > 0 or int(a["units"]) > 10, "the match did things: units=%d wood=%d buildings=%d" % [int(a["units"]), int(a["wood"]), int(a["buildings"])])
	var first_diff: int = -1
	var points: int = a["hashes"].size()
	for t: Variant in a["hashes"].keys():
		if not b["hashes"].has(t) or a["hashes"][t] != b["hashes"][t]:
			first_diff = int(t)
			break
	check(points >= RUN_TICKS / HASH_EVERY_TICKS - 1 and points == b["hashes"].size(), "hashes sampled at %d points in both runs" % points)
	if first_diff >= 0:
		# Name the culprit: the first lines that differ at the first bad tick.
		var la: PackedStringArray = a["dumps"].get(first_diff, PackedStringArray())
		var lb: PackedStringArray = b["dumps"].get(first_diff, PackedStringArray())
		var shown: int = 0
		if not la.is_empty() and not lb.is_empty():
			print("  info  headers A: %s | B: %s" % [la[0], lb[0]])
		for i: int in mini(la.size(), lb.size()):
			if la[i] != lb[i] and shown < 6:
				shown += 1
				print("  info  tick %d differs:
        A: %s
        B: %s" % [first_diff, la[i], lb[i]])
		if la.size() != lb.size():
			print("  info  tick %d: %d vs %d lines" % [first_diff, la.size(), lb.size()])
	check(first_diff < 0, "every hash matches (first difference at tick %d)" % first_diff if first_diff >= 0 else "every one of the %d hashes matches between the two runs" % points)
	# A different seed changes the match (so the hash really looks at it).
	var c: Dictionary = await _run_match(778)
	var same: bool = true
	for t: Variant in a["hashes"].keys():
		if c["hashes"].get(t) != a["hashes"][t]:
			same = false
	check(not same, "a different seed gives different hashes (the bell's spread uses the match RNG)")


func test_b_state_hash_sees_a_moved_unit() -> void:
	await _open(1)
	var h0: int = world.state_hash()
	var u: Unit = _units(0, true)[0]
	u.position += Vector2(1, 0)
	check(world.state_hash() != h0, "moving one unit by one pixel changes the hash")
	u.position -= Vector2(1, 0)
	check(world.state_hash() == h0, "and moving it back restores it")
	await _close()


func test_c_commands_resolve_targets_by_simulation_id() -> void:
	await _open(1)
	var bus: CommandBus = main.get_node("CommandBus")
	var v: Unit = _units(0, true)[0]
	var tc: Building = _tc(0)
	check(v.sim_id > 0 and tc.sim_id > 0 and world.unit_by_id(v.sim_id) == v and world.building_by_id(tc.sim_id) == tc, "units and buildings have simulation ids the world can look up")
	var gold: ResourceNode = world.find_node_near("gold", tc.position, 4000.0)
	var target: Dictionary = OrderResolver.target_to_dict({"kind": "node", "ref": gold})
	check(int(target["node"]) == gold.sim_id and OrderResolver.target_from_dict(world, target)["ref"] == gold, "a target travels as {kind, id} and comes back as the node")
	var cmd: Dictionary = CommandBus.order_cmd(0, [v] as Array[Unit], {"kind": "node", "ref": gold}, gold.position)
	check(JSON.stringify(cmd) != "" and cmd["units"] == [v.sim_id], "an order command is plain data: %s" % JSON.stringify(cmd).left(90))
	bus.apply(cmd)
	check(v.task is GatherTask and (v.task as GatherTask).subtype == "gold", "applying it sends the villager to mine gold")
	var stolen: Dictionary = CommandBus.order_cmd(1, [v] as Array[Unit], {"kind": "ground", "ref": null}, tc.position)
	bus.apply(stolen)
	check(v.task is GatherTask, "a command from the other player cannot move my villager")
	var gone: Dictionary = OrderResolver.target_from_dict(world, {"kind": "node", "node": 999999})
	check(String(gone["kind"]) == "ground", "a target that no longer exists becomes plain ground")
	await _close()


# ------------------------------------------------------------------ (b) lobby and lockstep

## A stand-in for the simulation: counts the physics ticks it was allowed to run.
class FakeSim extends Node:
	var ticks: int = 0
	func _physics_process(_d: float) -> void:
		ticks += 1


class NetSide extends RefCounted:
	var branch: Node
	var session: Node
	var lockstep: Lockstep
	var sim: FakeSim
	var applied: Array = []  # [turn, cmd]
	var hash_value: int = 100
	var desyncs: Array = []


func _make_side(name: String) -> NetSide:
	var s: NetSide = NetSide.new()
	s.branch = Node.new()
	s.branch.name = name
	add_to_tree(s.branch)
	runner.get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), s.branch.get_path())
	s.session = load("res://autoload/net_session.gd").new()
	s.session.name = "NetSession"
	s.session.change_scene = false
	s.branch.add_child(s.session)
	return s


func _add_lockstep(s: NetSide, local: int, players: Dictionary) -> void:
	s.sim = FakeSim.new()
	s.sim.name = "Sim"
	s.lockstep = Lockstep.new()
	s.lockstep.name = "Lockstep"
	s.branch.add_child(s.lockstep)
	s.branch.add_child(s.sim)
	var side: NetSide = s
	s.lockstep.setup(local, players, [s.sim] as Array[Node],
		func(cmd: Dictionary) -> void: side.applied.append([side.lockstep.turn, cmd]),
		func() -> int: return side.hash_value)
	s.lockstep.desync.connect(func(t: int, mine: int, theirs: int) -> void: side.desyncs.append([t, mine, theirs]))


func _drop_side(s: NetSide) -> void:
	s.session.leave()
	runner.get_tree().set_multiplayer(null, s.branch.get_path())
	s.branch.queue_free()


func _wait_for(cond: Callable, seconds: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > seconds * 1000.0:
			return false
		await frames(1)
	return true


func test_d_two_peers_in_one_process_agree_on_map_and_seed() -> void:
	GameState.set_local_player(0)
	var host: NetSide = _make_side("HostBranch")
	var client: NetSide = _make_side("ClientBranch")
	var starts: Array = []
	host.session.match_starting.connect(func(m: String, s: int) -> void: starts.append(["host", m, s, host.session.local_player]))
	client.session.match_starting.connect(func(m: String, s: int) -> void: starts.append(["client", m, s, client.session.local_player]))
	check(host.session.host(PORT) == OK, "the host opens an ENet server on port %d" % PORT)
	check(client.session.join("127.0.0.1", PORT) == OK, "the client starts connecting to 127.0.0.1")
	var joined: bool = await _wait_for(func() -> bool: return host.session.peer_count() == 1 and client.session.multiplayer.has_multiplayer_peer() and client.session.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 5.0)
	check(joined, "both sides see the connection (host peers=%d)" % host.session.peer_count())
	check(not client.session.start_match("valle_rio"), "only the host can start the match")
	check(host.session.start_match("valle_rio"), "the host starts the match")
	var both: bool = await _wait_for(func() -> bool: return starts.size() == 2, 5.0)
	check(both, "both sides get the start (%d)" % starts.size())
	if starts.size() == 2:
		check(starts[0][1] == "valle_rio" and starts[1][1] == "valle_rio", "same map on both sides")
		check(starts[0][2] == starts[1][2] and int(starts[0][2]) > 0, "same seed on both sides (%d)" % int(starts[0][2]))
		var seats: Array = [starts[0][3], starts[1][3]]
		seats.sort()
		check(seats == [0, 1] and host.session.local_player == 0 and client.session.local_player == 1, "host plays seat 0, client seat 1")
	check(NetSession.local_ips().size() >= 0, "local_ips() answers (%s)" % ", ".join(NetSession.local_ips()))
	GameState.set_local_player(0)
	# Keep the peers for the lockstep test below.
	_sides = [host, client]


var _sides: Array = []


func test_e_lockstep_holds_the_sim_until_the_rival_turn_arrives() -> void:
	if _sides.size() != 2:
		check(false, "needs the connected peers from test_d")
		return
	var host: NetSide = _sides[0]
	var client: NetSide = _sides[1]
	var client_peer: int = client.session.multiplayer.get_unique_id()
	var players: Dictionary = {0: 1, 1: client_peer}
	_add_lockstep(host, 0, players)
	_add_lockstep(client, 1, players)
	await physics_frames(3)
	check(host.sim.ticks == 0 and not host.lockstep.sim_enabled(), "setup holds the sim before the first turn (%d ticks)" % host.sim.ticks)
	# Start the host alone: ready never completes, the sim is held.
	host.lockstep.start()
	await physics_frames(12)
	check(not host.lockstep.is_started and host.sim.ticks == 0, "with the rival not ready the host sim never ticks (%d)" % host.sim.ticks)
	client.lockstep.start()
	var started: bool = await _wait_for(func() -> bool: return host.lockstep.is_started and client.lockstep.is_started, 5.0)
	check(started, "once both are ready the match starts on both sides")
	var ran: bool = await _wait_for(func() -> bool: return host.lockstep.turn >= 6 and client.lockstep.turn >= 6, 5.0)
	check(ran, "turns advance on both sides (host %d, client %d)" % [host.lockstep.turn, client.lockstep.turn])
	check(absi(host.lockstep.turn - client.lockstep.turn) <= host.lockstep.delay_turns, "the two sides stay within the delay of each other")
	check(host.sim.ticks == host.lockstep.turn * host.lockstep.turn_ticks + host.lockstep.tick_in_turn, "the sim ran exactly turn * turn_ticks ticks (%d)" % host.sim.ticks)
	# A command from the client applies on both sides in the same turn.
	var at: int = client.lockstep.turn
	client.lockstep.queue_local({"type": "stop", "units": [7]})
	var applied: bool = await _wait_for(func() -> bool: return host.applied.size() >= 1 and client.applied.size() >= 1, 5.0)
	check(applied, "the command reaches both sides")
	if applied:
		check(host.applied[0][0] == client.applied[0][0] and int(host.applied[0][0]) >= at + client.lockstep.delay_turns, "it applies in the same turn on both (%d) after the delay" % int(host.applied[0][0]))
		check(int(host.applied[0][1]["player"]) == 1 and host.applied[0][1]["units"] == [7], "with the sender's seat stamped on it")
	# Stall: a pending turn without the client's bundle holds the host's sim.
	client.lockstep.process_mode = Node.PROCESS_MODE_DISABLED
	var stall_turn: int = host.lockstep.turn
	await physics_frames(40)
	check(host.lockstep.turn <= stall_turn + host.lockstep.delay_turns + 1, "without the rival's bundles the host stops after the delay (turn %d -> %d)" % [stall_turn, host.lockstep.turn])
	check(not host.lockstep.sim_enabled() and host.lockstep.stalled_ticks > 0, "and the host's sim is held (stalled ticks %d)" % host.lockstep.stalled_ticks)
	var ticks_held: int = host.sim.ticks
	await physics_frames(10)
	check(host.sim.ticks == ticks_held, "a held sim does not tick at all")
	check(host.lockstep.waiting, "the HUD is told we are waiting")
	client.lockstep.process_mode = Node.PROCESS_MODE_INHERIT
	var resumed: bool = await _wait_for(func() -> bool: return host.lockstep.turn > stall_turn + 4, 5.0)
	check(resumed and not host.lockstep.waiting, "it resumes when the bundles arrive")
	# Desync: the client reports a different hash for a hashed turn.
	client.hash_value = 200
	var hashed: bool = await _wait_for(func() -> bool: return not host.desyncs.is_empty() and not client.desyncs.is_empty(), 8.0)
	check(hashed, "a hash mismatch raises desync on both sides")
	if hashed:
		check(int(host.desyncs[0][0]) % host.lockstep.hash_every_turns == 0 and host.desyncs[0][1] == 100 and host.desyncs[0][2] == 200, "with the turn and both hashes (turn %d: %d vs %d)" % [int(host.desyncs[0][0]), int(host.desyncs[0][1]), int(host.desyncs[0][2])])
	check(host.lockstep.bundles_sent > 10 and host.lockstep.bundles_received > 10, "bundles flowed both ways (%d sent, %d received)" % [host.lockstep.bundles_sent, host.lockstep.bundles_received])
	_drop_side(client)
	_drop_side(host)
	_sides = []
	await frames(3)
	GameState.set_local_player(0)
