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
## Why it ended: "town_center", "buildings" or "resign".
var reason: String = ""
## Players that started with buildings: only they can lose. With fewer than
## two (sandbox, tests, demos) there is no match to decide.
var contenders: Array[int] = []
var _timer: float = 0.0
## Timeline for the end-of-match report: when the first blow between players
## landed, when each player reached each era, the biggest army and workforce
## each one had (sampled every SAMPLE_INTERVAL s) and villagers lost.
const SAMPLE_INTERVAL: float = 10.0
var first_attack_s: float = -1.0
var era_times: Dictionary = {}  # player -> {era: seconds}
var peak_army: Dictionary = {}  # player -> int
var peak_villagers: Dictionary = {}  # player -> int
var villagers_lost: Dictionary = {}  # player -> int
var _sample_t: float = 0.0


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
	EventBus.under_attack.connect(func(_p: int, _pos: Vector2) -> void:
		if first_attack_s < 0.0:
			first_attack_s = elapsed)
	EventBus.era_changed.connect(func(p: int, era: int) -> void:
		var d: Dictionary = era_times.get(p, {})
		d[era] = elapsed
		era_times[p] = d)


## Army and workforce sizes, kept as peaks per player.
func _sample() -> void:
	var army: Dictionary = {}
	var vill: Dictionary = {}
	for u: Unit in world.units:
		if u.owner_id < 0 or u.is_dead or u.is_animal():
			continue
		if u.can_gather():
			vill[u.owner_id] = int(vill.get(u.owner_id, 0)) + 1
		elif not u.data.get("combat", {}).is_empty():
			army[u.owner_id] = int(army.get(u.owner_id, 0)) + 1
	for b: Building in world.buildings:
		for u: Unit in b.garrison:
			if u.can_gather():
				vill[b.owner_id] = int(vill.get(b.owner_id, 0)) + 1
	for p: int in army.keys():
		peak_army[p] = maxi(int(peak_army.get(p, 0)), int(army[p]))
	for p: int in vill.keys():
		peak_villagers[p] = maxi(int(peak_villagers.get(p, 0)), int(vill[p]))


## "Why I won / lost" in plain lines: first attack, eras, peak army and
## workforce, plus one hint about the biggest gap between the two sides.
func report_lines(me: int, them: int, won: bool) -> Array[String]:
	_sample()
	var lines: Array[String] = []
	if first_attack_s >= 0.0:
		lines.append(tr("REPORT_FIRST_ATTACK") % [int(first_attack_s) / 60, int(first_attack_s) % 60])
	lines.append(tr("REPORT_ERAS") % [_eras_text(me), _eras_text(them)])
	var my_army: int = int(peak_army.get(me, 0))
	var their_army: int = int(peak_army.get(them, 0))
	lines.append(tr("REPORT_ARMY") % [my_army, their_army])
	var my_v: int = int(peak_villagers.get(me, 0))
	var their_v: int = int(peak_villagers.get(them, 0))
	lines.append(tr("REPORT_VILLAGERS") % [my_v, int(villagers_lost.get(me, 0)), their_v, int(villagers_lost.get(them, 0))])
	# The hint: the largest gap, phrased for the side that is reading.
	var v_gap: int = their_v - my_v
	var a_gap: int = their_army - my_army
	var my_era2: float = float(Dictionary(era_times.get(me, {})).get(2, INF))
	var their_era2: float = float(Dictionary(era_times.get(them, {})).get(2, INF))
	if not won:
		if v_gap >= 5:
			lines.append(tr("REPORT_HINT_ECO") % v_gap)
		elif a_gap >= 5:
			lines.append(tr("REPORT_HINT_ARMY") % [their_army, my_army])
		elif their_era2 < my_era2 - 60.0:
			lines.append(tr("REPORT_HINT_ERA"))
		elif int(villagers_lost.get(me, 0)) >= 5:
			lines.append(tr("REPORT_HINT_BELL") % int(villagers_lost.get(me, 0)))
		else:
			lines.append(tr("REPORT_HINT_DEFENSE"))
	else:
		if -v_gap >= 5:
			lines.append(tr("REPORT_WIN_ECO") % -v_gap)
		elif -a_gap >= 5:
			lines.append(tr("REPORT_WIN_ARMY") % [my_army, their_army])
		else:
			lines.append(tr("REPORT_WIN_CLOSE"))
	return lines


func _eras_text(p: int) -> String:
	var d: Dictionary = era_times.get(p, {})
	if d.is_empty():
		return "I"
	var parts: PackedStringArray = PackedStringArray()
	var keys: Array = d.keys()
	keys.sort()
	for era: Variant in keys:
		var s: int = int(d[era])
		parts.append("%s %d:%02d" % ["I II III IV".split(" ")[clampi(int(era) - 1, 0, 3)], s / 60, s % 60])
	return ", ".join(parts)


func _physics_process(delta: float) -> void:
	if world == null or ended:
		return
	elapsed += delta
	_timer += delta
	_sample_t += delta
	if _sample_t >= SAMPLE_INTERVAL:
		_sample_t = 0.0
		_sample()
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	if contenders.has(-1):
		return
	# The Town Center is the heart: lose it (built or foundation) and the
	# match is over, no need to hunt every last house.
	var has_tc: Dictionary = {}
	for p: int in contenders:
		has_tc[p] = false
	for b: Building in world.buildings:
		if has_tc.has(b.owner_id) and b.building_type == String(DataLoader.get_entry("eras", "_rules").get("researched_at", "town_center")):
			has_tc[b.owner_id] = true
	for p: int in has_tc.keys():
		if not has_tc[p]:
			var other: int = GameState.PLAYER_AI if p == GameState.PLAYER_HUMAN else GameState.PLAYER_HUMAN
			reason = "town_center"
			finish(other, p)
			return


## A player gives up (the AI when it cannot recover): the rival wins.
func resign(player_id: int) -> void:
	if ended or contenders.has(-1) or not contenders.has(player_id):
		return
	for p: int in contenders:
		if p != player_id:
			reason = "resign"
			finish(p, player_id)
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
	if u.can_gather():
		villagers_lost[u.owner_id] = int(villagers_lost.get(u.owner_id, 0)) + 1
	if u.last_attacker != null and is_instance_valid(u.last_attacker) and u.last_attacker.owner_id >= 0:
		_bump(u.last_attacker.owner_id, "kills", 1)


func _bump(player_id: int, key: String, amount: int) -> void:
	if not GameState.stats.has(player_id):
		return
	var s: Dictionary = GameState.stats[player_id]
	s[key] = int(s.get(key, 0)) + amount
