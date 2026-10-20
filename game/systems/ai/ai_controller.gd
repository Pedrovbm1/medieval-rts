class_name AIController
extends Node
## Computer opponent for one player. Thinks every `think_s` seconds (not every
## frame) through 4 phases: opening -> development -> harass -> push.
## Plays fair: it only knows what its own units and buildings have seen
## (VisionGrid) and uses the same systems as the human (build, train, gather,
## attack-move). Every number comes from data/ai.json.

signal attack_ordered(target: Vector2, explored: bool)
## The AI gives up a lost match (no villagers, no army, no way to rebuild).
signal resigned(player_id: int)

const PRODUCTION: PackedStringArray = ["barracks", "archery_range", "stable"]
const ECONOMY_TARGETS: PackedStringArray = ["lumber_camp", "mining_camp", "farm"]

var world: World
var player_id: int = GameState.PLAYER_AI
var difficulty_id: String = "normal"
var diff: Dictionary = {}
var cfg: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var elapsed: float = 0.0
var phase: String = "opening"
var home: Vector2 = Vector2.ZERO
## Enemy buildings this AI has seen: instance id -> {"pos": Vector2, "type": String, "ref": Building}
var known_buildings: Dictionary = {}
## Every attack order: {"t": float, "pos": Vector2, "explored": bool, "kind": String}
var attack_log: Array[Dictionary] = []
var waves: int = 0
var enabled: bool = true

var _think_timer: float = 0.0
var _think_s: float = 2.0
var _scout_points: Array[Vector2] = []
var _harass: Array[Unit] = []
var _last_wave_t: float = -9999.0
## True while the AI saves resources for its next era (no army, no techs).
var saving_for_era: bool = false
## Why it is saving: "cost" (resources for the era) or "requires" (era buildings).
var saving_reason: String = ""
## True while the AI saves for its next technology (military paused briefly).
var saving_for_tech: bool = false
var _last_research_t: float = 0.0
var _last_target: Vector2 = Vector2.INF
## Push waves that died without razing their target: the next one is bigger.
var failed_waves: int = 0
var has_resigned: bool = false
## Scout points ordered and how many times (unreachable ones get skipped).
var _scout_tries: Dictionary = {}
var _scout_goal: Dictionary = {}  # Unit -> Vector2 it was sent to
var _explorers: Array[Unit] = []
var _state_log_t: float = 0.0
var _hopeless_since: float = -1.0
## Saving for an era gives up after a while (e.g. gold ran out) and retries later.
var _saving_since: float = -1.0
var _no_saving_until: float = -1.0
var _wave_was_alive: bool = false


## "Fair" play: the difficulty's hidden economic bonuses (gather_mult,
## production_mult) are off; the AI must win by decisions. The human's own
## bonus on Easy stays (it is shown in the menu, not hidden).
var fair: bool = false


func setup(p_world: World, p_player: int, p_difficulty: String, p_seed: int = 1, p_fair: bool = false) -> void:
	world = p_world
	player_id = p_player
	difficulty_id = p_difficulty
	fair = p_fair
	cfg = DataLoader.get_table("ai")
	diff = Dictionary(Dictionary(cfg.get("difficulties", {})).get(difficulty_id, {})).duplicate()
	if fair:
		diff["gather_mult"] = 1.0
		diff["production_mult"] = 1.0
	_think_s = float(diff.get("think_s", 2.0))
	rng.seed = p_seed
	# Hard AI: economic bonus as a gather multiplier on every resource subtype.
	var gm: float = float(diff.get("gather_mult", 1.0))
	if not is_equal_approx(gm, 1.0):
		var mults: Dictionary = GameState.multipliers.get(player_id, {})
		for sub: String in ["berries", "meat", "farm", "wood", "gold", "stone"]:
			mults["gather." + sub] = float(mults.get("gather." + sub, 1.0)) * gm
		GameState.multipliers[player_id] = mults
	_apply_human_bonus()
	var tc: Building = _first_of("town_center")
	home = tc.position if tc != null else world.map_size_px * 0.5
	_build_scout_points()
	name = "AI_%d_%s" % [player_id, difficulty_id]


## The AI's own hidden bonuses of a difficulty as "+30% recolección, +50%
## producción" (for the menu card and the end report); "" when it has none.
static func bonus_text(difficulty: String) -> String:
	var d: Dictionary = Dictionary(DataLoader.get_table("ai").get("difficulties", {})).get(difficulty, {})
	var parts: PackedStringArray = PackedStringArray()
	var gm: float = float(d.get("gather_mult", 1.0))
	if gm > 1.0:
		parts.append("+%d%% %s" % [int(round((gm - 1.0) * 100.0)), TranslationServer.translate("BONUS_GATHER")])
	var pm: float = float(d.get("production_mult", 1.0))
	if pm > 1.0:
		parts.append("+%d%% %s" % [int(round((pm - 1.0) * 100.0)), TranslationServer.translate("BONUS_PRODUCTION")])
	return ", ".join(parts)


## What the human gets on this difficulty ("tú: +20% recolección") or "".
static func human_bonus_text(difficulty: String) -> String:
	var d: Dictionary = Dictionary(DataLoader.get_table("ai").get("difficulties", {})).get(difficulty, {})
	var bonus: Dictionary = d.get("human_bonus", {})
	var parts: PackedStringArray = PackedStringArray()
	var g: float = float(bonus.get("gather", 1.0))
	if g > 1.0:
		parts.append("+%d%% %s" % [int(round((g - 1.0) * 100.0)), TranslationServer.translate("BONUS_GATHER")])
	var t: float = float(bonus.get("train_speed", 1.0))
	if t > 1.0:
		parts.append("+%d%% %s" % [int(round((t - 1.0) * 100.0)), TranslationServer.translate("BONUS_TRAIN")])
	return ", ".join(parts)


## Easy: the human opponent(s) get a gathering and training bonus
## (ai.json difficulties.easy.human_bonus), so a beginner can win.
func _apply_human_bonus() -> void:
	var bonus: Dictionary = diff.get("human_bonus", {})
	if bonus.is_empty():
		return
	var human: int = GameState.PLAYER_HUMAN
	if human == player_id:
		return
	var mults: Dictionary = GameState.multipliers.get(human, {})
	var g: float = float(bonus.get("gather", 1.0))
	if not is_equal_approx(g, 1.0):
		for sub: String in ["berries", "meat", "farm", "wood", "gold", "stone"]:
			mults["gather." + sub] = float(mults.get("gather." + sub, 1.0)) * g
	var t: float = float(bonus.get("train_speed", 1.0))
	if not is_equal_approx(t, 1.0):
		mults["train_speed"] = float(mults.get("train_speed", 1.0)) * t
	GameState.multipliers[human] = mults


func _physics_process(delta: float) -> void:
	if world == null or not enabled:
		return
	elapsed += delta
	_think_timer += delta
	if _think_timer >= _think_s:
		_think_timer = 0.0
		think()


func think() -> void:
	_update_phase()
	_update_knowledge()
	var villagers: Array[Unit] = []
	var military: Array[Unit] = []
	for u: Unit in world.units:
		if u.owner_id != player_id or u.is_dead or u.is_animal():
			continue
		if u.can_gather():
			villagers.append(u)
		elif u.unit_type != "scout" and not u.data.has("heal"):
			military.append(u)
	if OS.is_debug_build() and elapsed - _state_log_t >= 60.0:
		_state_log_t = elapsed
		print("[REALM] ai %d state t=%.0f phase=%s known=%d scouts=%d army=%d waves=%d explorers=%d bank=f%d w%d g%d s%d" % [player_id, elapsed, phase,
			_known_enemy_buildings(), _my_scouts().size(), military.size(), waves, _explorers.size(),
			GameState.get_resource(player_id, "food"), GameState.get_resource(player_id, "wood"), GameState.get_resource(player_id, "gold"), GameState.get_resource(player_id, "stone")])
	if _check_resign(villagers, military):
		return
	_economy(villagers)
	_trade()
	_buy_for_era()
	_advance(villagers)
	# While saving for an era, keep only the standing army this phase needs.
	var min_army: int = int(float(Dictionary(Dictionary(cfg.get("saving", {})).get("min_army", {})).get(phase, 0)) * float(diff.get("army_mult", 1.0)))
	var army_paused: bool = (saving_for_era and military.size() >= min_army) or saving_for_tech
	if not army_paused:
		_military(villagers, military)
	_scouting()
	_relics(military)
	_repair_home(villagers)
	var raided: bool = _defend(military)
	_bell(raided, military)
	if not raided:
		_attack(military)


## Relics: once there is a monastery, idle monks fetch every relic the AI
## has seen; a monk holding one brings it home. If the rival holds every
## relic (the victory clock is running) the army goes for their monastery.
var _relic_push_t: float = -999.0


func _relics(military: Array[Unit]) -> void:
	if world.relic_total <= 0:
		return
	var vault: Building = world.nearest_vault(player_id, home)
	if vault != null:
		for u: Unit in world.units:
			if u.owner_id != player_id or u.is_dead or not bool(u.data.get("relic_carrier", false)) or u.task is RelicTask:
				continue
			if u.relic:
				world.behavior.assign(u, RelicTask.deliver_to(u, world, vault))
				continue
			if u.task != null and not (u.task is HealTask):
				continue
			var best: ResourceNode = null
			var best_d: float = INF
			for n: ResourceNode in world.resource_nodes:
				if not n.is_relic() or not world.vision.grid.is_explored(player_id, n.position) or _relic_claimed(n):
					continue
				var d: float = u.position.distance_squared_to(n.position)
				if d < best_d:
					best_d = d
					best = n
			if best != null:
				world.behavior.assign(u, RelicTask.new(u, world, best))
				if OS.is_debug_build():
					print("[REALM] ai %d monk fetches relic t=%.0f" % [player_id, elapsed])
	var enemy: int = GameState.PLAYER_HUMAN if player_id != GameState.PLAYER_HUMAN else GameState.PLAYER_AI
	if world.relics_held(enemy) >= world.relic_total and elapsed - _relic_push_t > 30.0:
		for k: Dictionary in known_buildings.values():
			if String(k["type"]) == "monastery":
				_relic_push_t = elapsed
				var free: Array[Unit] = military.filter(func(m: Unit) -> bool: return not (m.task is AttackTask))
				if not free.is_empty():
					_order_attack(free, Vector2(k["pos"]), "relics")
				return


func _relic_claimed(n: ResourceNode) -> bool:
	for u: Unit in world.units:
		if u.owner_id == player_id and u.task is RelicTask and (u.task as RelicTask).relic == n:
			return true
	return false


## Villagers mend the Town Center and towers once the fight is over (same
## repair rules as the player: it costs resources and takes time).
func _repair_home(villagers: Array[Unit]) -> void:
	if villagers.is_empty():
		return
	for b: Building in world.buildings:
		if b.owner_id != player_id or not b.is_complete() or b.hp >= int(b.max_hp * 0.75):
			continue
		if b.building_type != "town_center" and b.data.get("combat", {}).is_empty():
			continue
		if b.recently_hit(8.0) or b.repairers.size() >= 2:
			continue
		var free: Array[Unit] = villagers.filter(func(v: Unit) -> bool: return not (v.task is RepairTask) and not (v.task is BuildTask))
		free.sort_custom(func(x: Unit, y: Unit) -> bool: return x.position.distance_squared_to(b.position) < y.position.distance_squared_to(b.position))
		for i: int in mini(2 - b.repairers.size(), free.size()):
			world.behavior.assign(free[i], RepairTask.new(free[i], world, b))
		return


## Town bell: a raid at home with more attackers than defenders sends the
## villagers inside; once it is quiet for a while they come back out.
var _bell_on: bool = false
var _calm_since: float = -1.0


func _bell(raided: bool, military: Array[Unit]) -> void:
	var tc: Building = _first_of("town_center")
	if tc == null or not tc.is_complete():
		return
	var near: int = 0
	for u: Unit in world.units:
		if u.owner_id >= 0 and u.owner_id != player_id and not u.is_dead and not u.can_gather() and u.position.distance_to(tc.position) < 700.0:
			near += 1
	if near >= 3 and near > military.size() / 2 and not _bell_on:
		var main: Node = get_parent()
		if main != null and main.has_method("shelter_villagers") and int(main.call("shelter_villagers", player_id)) > 0:
			_bell_on = true
			_calm_since = -1.0
			if OS.is_debug_build():
				print("[REALM] ai %d bell t=%.0f threats=%d" % [player_id, elapsed, near])
	elif _bell_on:
		if near > 0 or raided:
			_calm_since = -1.0
			return
		if _calm_since < 0.0:
			_calm_since = elapsed
		elif elapsed - _calm_since >= 15.0:
			for b: Building in world.buildings:
				if b.owner_id == player_id:
					world.eject_all(b)
			_bell_on = false


## Like computer players in the genre, resign when the match is lost:
## no villagers, almost no army and no way to train a villager, for a while.
func _check_resign(villagers: Array[Unit], military: Array[Unit]) -> bool:
	var rcfg: Dictionary = cfg.get("resign", {})
	var tc: Building = _first_of("town_center")
	var villager_cost: int = int(Dictionary(DataLoader.get_entry("units", "villager").get("cost", {})).get("food", 50))
	var can_rebuild: bool = tc != null and tc.is_complete() and GameState.get_resource(player_id, "food") >= villager_cost
	var hopeless: bool = villagers.is_empty() and military.size() < int(rcfg.get("max_army", 3)) and not can_rebuild
	if not hopeless:
		_hopeless_since = -1.0
		return false
	if _hopeless_since < 0.0:
		_hopeless_since = elapsed
	if elapsed - _hopeless_since >= float(rcfg.get("after_s", 30.0)) and not has_resigned:
		has_resigned = true
		enabled = false
		if OS.is_debug_build():
			print("[REALM] ai %d resigns t=%.0f" % [player_id, elapsed])
		resigned.emit(player_id)
	return true


# ------------------------------------------------------------------ phases & knowledge

func minutes() -> float:
	return elapsed / 60.0


func _update_phase() -> void:
	var scaled: float = minutes() / float(diff.get("phase_scale", 1.0))
	for p: Variant in cfg.get("phases", []):
		if scaled < float(p["until_min"]):
			phase = String(p["id"])
			return


func _update_knowledge() -> void:
	var grid: VisionGrid = world.vision.grid
	for b: Building in world.buildings:
		if b.owner_id == player_id or b.owner_id < 0:
			continue
		if grid.is_visible(player_id, b.position):
			known_buildings[b.get_instance_id()] = {"pos": b.position, "type": b.building_type, "ref": b}
	for id: int in known_buildings.keys():
		var k: Dictionary = known_buildings[id]
		# Forget a building only once we SEE that it is gone (memory otherwise).
		if grid.is_visible(player_id, k["pos"]) and (not is_instance_valid(k["ref"]) or not world.buildings.has(k["ref"])):
			known_buildings.erase(id)


# ------------------------------------------------------------------ economy

func _economy(villagers: Array[Unit]) -> void:
	var tcs: Array[Building] = _mine("town_center").filter(func(b: Building) -> bool: return b.is_complete())
	var target: int = _villager_target()
	var queued: int = 0
	for tc: Building in tcs:
		queued += tc.queue.count("villager")
	# Saving for an era: like a player "clicking up" at a set workforce size.
	var pause_at: Dictionary = Dictionary(cfg.get("saving", {})).get("pause_villagers_at", {})
	var next_era: String = str(GameState.era_of(player_id) + 1)
	if saving_for_era and saving_reason == "cost" and pause_at.has(next_era) and villagers.size() >= int(pause_at[next_era]):
		target = 0
	if villagers.size() + queued < target:
		for tc: Building in tcs:
			if tc.queue.size() < 2:
				world.construction.enqueue(tc, "villager")
	var bcfg: Dictionary = cfg.get("buildings", {})
	# Houses before population blocks the queue.
	var free_pop: int = GameState.pop_cap(player_id) - GameState.pop_used(player_id) - queued
	var houses_building: bool = _mine("house").any(func(b: Building) -> bool: return not b.is_complete())
	if free_pop <= int(bcfg.get("house_margin", 4)) and GameState.pop_cap(player_id) < world.economy.pop_max and not houses_building:
		_build("house", home + Vector2(rng.randf_range(-420, 420), rng.randf_range(-420, 420)), villagers, 1)
	# One lumber camp per 15 villagers: trees near the first camp run out and
	# the walk grows, so a second wood line keeps income steady.
	var camps: Array[Building] = _mine("lumber_camp")
	var camps_wanted: int = 0 if villagers.size() < int(bcfg.get("lumber_camp_at_villagers", 6)) else 1 + villagers.size() / 15
	if camps.size() < camps_wanted and not camps.any(func(b: Building) -> bool: return not b.is_complete()):
		var tree: Vector2i = _fresh_tree(camps)
		if tree.x >= 0:
			var t: Vector2 = world.cell_center(tree)
			_build("lumber_camp", t + (home - t).normalized() * 160.0, villagers, 2)
	if villagers.size() >= int(bcfg.get("mining_camp_at_villagers", 10)) and _mine("mining_camp").is_empty():
		var gold: ResourceNode = world.find_node_near("gold", home, 1600.0)
		if gold != null:
			_build("mining_camp", gold.position + (home - gold.position).normalized() * 192.0, villagers, 1)
	var gold_now: ResourceNode = world.find_node_near("gold", home, 3000.0)
	var mining: Array[Building] = _mine("mining_camp")
	if gold_now != null and not mining.is_empty() and villagers.size() >= 20 \
			and not mining.any(func(b: Building) -> bool: return b.position.distance_to(gold_now.position) < world.tile_size * 8 or not b.is_complete()):
		_build("mining_camp", gold_now.position + (home - gold_now.position).normalized() * 192.0, villagers, 1)
	var farms: Array[Building] = _mine("farm")
	var berries: ResourceNode = world.find_node_near("berries", home, 900.0)
	var farm_cap: int = int(bcfg.get("max_farms_while_saving", 4)) if saving_reason == "requires" else int(bcfg.get("max_farms", 10))
	if (minutes() >= float(bcfg.get("farms_from_min", 4)) or berries == null) and farms.size() < farm_cap \
			and not farms.any(func(b: Building) -> bool: return not b.is_complete()):
		_build("farm", home + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300)), villagers, 1)
	_expand(villagers)
	# Buildings of the current era first: they unlock the next era.
	var order: Array = bcfg.keys().filter(func(k: Variant) -> bool: return bcfg[k] is Dictionary)
	var era_now: int = GameState.era_of(player_id)
	order.sort_custom(func(x: Variant, y: Variant) -> bool:
		var ex: int = 0 if int(DataLoader.get_entry("buildings", String(x)).get("era", 1)) == era_now else 1
		var ey: int = 0 if int(DataLoader.get_entry("buildings", String(y)).get("era", 1)) == era_now else 1
		return ex < ey)
	var extra: int = _extra_production()
	for type_id: String in order:
		var want: int = int(Dictionary(bcfg.get(type_id, {})).get(phase, 0))
		if PRODUCTION.has(type_id) and want > 0 and not saving_for_era:
			# Stronger AIs (and any AI floating resources) add production so
			# a bigger economy becomes a bigger army.
			want = int(ceil(want * float(diff.get("production_mult", 1.0)))) + extra
		var bera: int = int(DataLoader.get_entry("buildings", type_id).get("era", 1))
		if saving_for_era and bera == era_now and want == 0 and world.tech.era_buildings(player_id) < 2 and type_id != "siege_workshop":
			want = 1
		var have: Array[Building] = _mine(type_id)
		var era_ok: bool = int(DataLoader.get_entry("buildings", type_id).get("era", 1)) <= GameState.era_of(player_id)
		if era_ok and have.size() < want and not have.any(func(b: Building) -> bool: return not b.is_complete()):
			_build(type_id, _front(), villagers, 2)
	_assign_idle(villagers)
	_rebalance(villagers)


## +1 production building per `float_step` resources banked (capped).
func _extra_production() -> int:
	if phase != "harass" and phase != "push":
		return 0
	var bcfg: Dictionary = cfg.get("buildings", {})
	var bank: int = 0
	for res: String in ["food", "wood", "gold"]:
		bank += GameState.get_resource(player_id, res)
	return mini(int(bcfg.get("float_extra_max", 2)), bank / maxi(1, int(bcfg.get("float_step", 1200))))


## Nearest tree to home that is not already served by one of our camps.
func _fresh_tree(camps: Array[Building]) -> Vector2i:
	var radius: int = 30
	for ring_try: int in 4:
		var probe: Vector2 = home + Vector2.from_angle(rng.randf() * TAU) * world.tile_size * (4 + ring_try * 6)
		var cell: Vector2i = world.find_tree_near(probe if not camps.is_empty() else home, radius)
		if cell.x < 0:
			continue
		var far: bool = true
		for c: Building in camps:
			if c.position.distance_to(world.cell_center(cell)) < world.tile_size * 8:
				far = false
		if far:
			return cell
	return Vector2i(-1, -1) if not camps.is_empty() else world.find_tree_near(home, radius)


## Gives idle villagers work, filling the resource that is furthest below its share.
func _assign_idle(villagers: Array[Unit]) -> void:
	var split: Dictionary = Dictionary(Dictionary(cfg.get("gather_split", {})).get(phase, {})).duplicate()
	if saving_reason == "requires":
		# Era buildings cost wood: lean the economy toward it until they stand.
		split["wood"] = float(split.get("wood", 0.3)) + 0.2
		split["gold"] = maxf(0.0, float(split.get("gold", 0.0)) - 0.1)
		split["food"] = maxf(0.0, float(split.get("food", 0.0)) - 0.1)
	var current: Dictionary = {"food": 0, "wood": 0, "gold": 0, "stone": 0}
	var idle: Array[Unit] = []
	for v: Unit in villagers:
		if v.task is GatherTask:
			var res: String = (v.task as GatherTask).resource
			current[res] = int(current.get(res, 0)) + 1
		elif v.task == null and not v.is_moving():
			idle.append(v)
	for v: Unit in idle:
		var best: String = "food"
		var best_gap: float = -INF
		for res: String in current.keys():
			var gap: float = float(split.get(res, 0.0)) * villagers.size() - float(current[res])
			if gap > best_gap:
				best_gap = gap
				best = res
		var task: UnitTask = _gather_task(v, best)
		if task == null and best != "wood":
			task = _gather_task(v, "wood")
			best = "wood"
		if task != null:
			world.behavior.assign(v, task)
			current[best] = int(current[best]) + 1


## Moves a few gatherers from a resource we are swimming in to one we lack:
## the era (or tech) cost when saving, else anything far below the rest.
## Without this only idle villagers were ever placed, so wood piled up while
## gold ran short and the AI never reached the next era.
func _rebalance(villagers: Array[Unit]) -> void:
	var rcfg: Dictionary = cfg.get("rebalance", {})
	var surplus_at: int = int(rcfg.get("surplus", 600))
	var bank: Dictionary = {}
	for res: String in ["food", "wood", "gold", "stone"]:
		bank[res] = GameState.get_resource(player_id, res)
	var need: Dictionary = {}
	if saving_for_era and saving_reason == "cost":
		var cost: Dictionary = TechSystem.item_cost(TechSystem.era_item(GameState.era_of(player_id) + 1))
		for res: String in cost.keys():
			if int(cost[res]) > int(bank.get(res, 0)):
				need[res] = int(cost[res]) - int(bank.get(res, 0))
	elif saving_for_era and saving_reason == "requires":
		# The era's required buildings are paid in wood.
		var want_wood: int = int(rcfg.get("requires_wood", 350))
		if int(bank["wood"]) < want_wood:
			need["wood"] = want_wood - int(bank["wood"])
	else:
		for res: String in ["food", "wood", "gold"]:
			if int(bank[res]) < int(rcfg.get("low", 150)):
				need[res] = int(rcfg.get("low", 150)) - int(bank[res])
	if need.is_empty():
		return
	var short: String = ""
	for res: String in need.keys():
		if short == "" or int(need[res]) > int(need[short]):
			short = res
	var donor: String = ""
	for res: String in ["wood", "food", "gold", "stone"]:
		if res != short and not need.has(res) and int(bank[res]) >= surplus_at and (donor == "" or int(bank[res]) > int(bank[donor])):
			donor = res
	if donor == "":
		return
	var moved: int = 0
	for v: Unit in villagers:
		if moved >= int(rcfg.get("per_think", 2)):
			break
		if v.task is GatherTask and (v.task as GatherTask).resource == donor and v.carry_amount < 1.0:
			var task: UnitTask = _gather_task(v, short)
			if task == null:
				return
			world.behavior.assign(v, task)
			moved += 1


func _gather_task(v: Unit, res: String) -> UnitTask:
	match res:
		"food":
			for f: Building in _mine("farm"):
				if f.is_complete() and f.has_free_work_slot(v) and f.workers.is_empty():
					return GatherTask.for_farm(v, world, f)
			var berries: ResourceNode = world.find_node_near("berries", home, 900.0)
			if berries != null:
				return GatherTask.for_node(v, world, berries)
			var meat: ResourceNode = world.find_node_near("meat", home, 700.0)
			if meat != null:
				return GatherTask.for_node(v, world, meat)
			for u: Unit in world.units:
				if u.unit_type == "sheep" and (u.owner_id == player_id or u.owner_id < 0) and u.position.distance_to(home) < 700.0:
					return HuntTask.new(v, world, u)
		"wood":
			var camp: Building = world.economy.nearest_dropoff(player_id, "wood", v.position)
			var cell: Vector2i = world.find_tree_near(camp.position if camp != null else home, 25)
			if cell.x >= 0:
				return GatherTask.for_tree(v, world, cell)
		"gold", "stone":
			var n: ResourceNode = world.find_node_near(res, home, 2200.0)
			if n != null:
				return GatherTask.for_node(v, world, n)
	return null


## Starts a building near `near` with `count` builders (idle first, then gatherers).
## The boom: a second Town Center toward the middle of the map once the
## era allows it and the workforce is big enough (buildings.json max_count).
## It trains villagers too and is a closer drop-off for the central veins.
func _expand(villagers: Array[Unit]) -> void:
	var limit: int = ConstructionSystem.count_limit(player_id, "town_center")
	if limit < 0 or saving_for_era or villagers.size() < int(Dictionary(cfg.get("buildings", {})).get("second_tc_at_villagers", 22)):
		return
	var tcs: Array[Building] = _mine("town_center")
	if tcs.size() >= limit or tcs.any(func(b: Building) -> bool: return not b.is_complete()):
		return
	var cost: Dictionary = DataLoader.get_entry("buildings", "town_center").get("cost", {})
	# Keep a cushion: the expansion must not starve houses and soldiers.
	for res: String in cost.keys():
		if GameState.get_resource(player_id, res) < int(cost[res]) + 100:
			return
	var toward: Vector2 = (world.map_size_px * 0.5 - home).normalized()
	var site: Vector2 = home + toward * 760.0 + Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120))
	var b: Building = _build("town_center", site, villagers, 3)
	if b != null and OS.is_debug_build():
		print("[REALM] ai %d second town center t=%.0f at=(%d,%d)" % [player_id, elapsed, b.cell.x, b.cell.y])


## Saving for an era and short of food (or wood) with gold to spare: buy a
## lot at the market instead of waiting on the fields.
func _buy_for_era() -> void:
	if not saving_for_era or saving_reason != "cost":
		return
	var cost: Dictionary = TechSystem.item_cost(TechSystem.era_item(GameState.era_of(player_id) + 1))
	for res: String in ["food", "wood"]:
		var need: int = int(cost.get(res, 0)) - GameState.get_resource(player_id, res)
		if need <= 0:
			continue
		var price: int = world.economy.buy_price(player_id, res)
		if GameState.get_resource(player_id, "gold") >= int(cost.get("gold", 0)) + price + 50 and world.economy.buy(player_id, res):
			return


func _build(type_id: String, near: Vector2, villagers: Array[Unit], count: int) -> Building:
	var cost: Dictionary = DataLoader.get_entry("buildings", type_id).get("cost", {})
	if not GameState.can_afford(player_id, cost):
		return null
	var cell: Vector2i = world.find_building_spot(type_id, near, 25)
	if cell.x < 0:
		return null
	var site: Vector2 = world.cell_center(cell)
	var pool: Array[Unit] = villagers.filter(func(v: Unit) -> bool: return not (v.task is BuildTask))
	pool.sort_custom(func(a: Unit, b: Unit) -> bool:
		var ai: int = 0 if a.task == null else 1
		var bi: int = 0 if b.task == null else 1
		if ai != bi:
			return ai < bi
		return a.position.distance_squared_to(site) < b.position.distance_squared_to(site))
	var builders: Array[Unit] = []
	for v: Unit in pool:
		if builders.size() >= count:
			break
		builders.append(v)
	if builders.is_empty():
		return null
	return world.construction.start_construction(player_id, type_id, cell, builders)


# ------------------------------------------------------------------ eras & techs

## Advance era when the phase asks for it, then spend spare resources on techs.
## Short of gold with a market: sell one lot of whatever piles up most
## (keeping a reserve), like a player does once the mines run dry.
func _trade() -> void:
	var mcfg: Dictionary = cfg.get("market", {})
	var gold: int = GameState.get_resource(player_id, "gold")
	var lots: int = 1
	var floor_gold: int = int(mcfg.get("sell_when_gold_below", 150))
	# Saving for an era that needs gold we do not have (mines run dry late):
	# trade the surplus for it, several lots per turn.
	if saving_for_era and saving_reason == "cost":
		var cost: Dictionary = TechSystem.item_cost(TechSystem.era_item(GameState.era_of(player_id) + 1))
		var need_gold: int = int(cost.get("gold", 0)) - gold
		if need_gold > 0:
			floor_gold = int(cost.get("gold", 0))
			lots = int(mcfg.get("era_lots_per_think", 3))
	if gold >= floor_gold:
		return
	var keep: int = int(mcfg.get("keep_at_least", 400))
	for _k: int in lots:
		var best: String = ""
		for res: String in ["food", "wood", "stone"]:
			var have: int = GameState.get_resource(player_id, res)
			if have >= keep + int(DataLoader.rule("market", "lot", 100)) and (best == "" or have > GameState.get_resource(player_id, best)):
				best = res
		if best == "" or world.economy.sell_error(player_id, best) != "":
			return
		world.economy.sell(player_id, best)


## Workforce goal for the current phase, scaled by difficulty.
func _villager_target() -> int:
	return int(round(float(Dictionary(cfg.get("villager_target", {})).get(phase, 20)) * float(diff.get("villager_mult", 1.0))))


func _advance(villagers: Array[Unit]) -> void:
	var want_era: int = mini(int(Dictionary(cfg.get("eras", {})).get(phase, 1)), int(diff.get("max_era", 4)))
	var era: int = GameState.era_of(player_id)
	var tc: Building = _first_of("town_center")
	saving_for_era = false
	saving_reason = ""
	if tc != null and tc.is_complete() and era < want_era:
		var item: String = TechSystem.era_item(era + 1)
		var err: String = world.tech.research_error(tc, item)
		# Save up while resources or the required buildings are missing.
		saving_for_era = (err == "cost" or err == "requires") and elapsed >= _no_saving_until
		if saving_for_era:
			if _saving_since < 0.0:
				_saving_since = elapsed
			var scfg: Dictionary = cfg.get("saving", {})
			if elapsed - _saving_since > float(scfg.get("max_seconds", 300)):
				# Stuck (e.g. no gold left nearby): play on, try again later.
				saving_for_era = false
				_saving_since = -1.0
				_no_saving_until = elapsed + float(scfg.get("cooldown_seconds", 180))
			else:
				saving_reason = err
				return
		else:
			_saving_since = -1.0
		if err == "":
			# The era comes first: clear villagers waiting in the queue.
			while not tc.queue.is_empty() and not TechSystem.is_research(tc.queue[tc.queue.size() - 1]) and tc.queue.size() > 0 and tc.train_elapsed == 0.0:
				world.construction.dequeue(tc, tc.queue.size() - 1)
			world.construction.enqueue(tc, item)
			return
	_research()


## One technology at a time: the cheapest one available. If nothing was
## researched for a while, save for it (army production pauses briefly).
func _research() -> void:
	saving_for_tech = false
	# Easier AIs skip some research turns (they upgrade less, like weaker players).
	if rng.randf() > float(diff.get("research_chance", 1.0)):
		return
	var gap: float = float(Dictionary(cfg.get("research", {})).get("save_after_s", 90.0))
	var best_item: String = ""
	var best_b: Building = null
	var best_cost: int = 1 << 30
	for b: Building in world.buildings:
		if b.owner_id != player_id or not b.is_complete() or not b.queue.is_empty():
			continue
		for id: String in world.tech.techs_at(b):
			var total: int = 0
			for v: Variant in TechSystem.item_cost(TechSystem.PREFIX + id).values():
				total += int(v)
			if total < best_cost:
				best_cost = total
				best_item = TechSystem.PREFIX + id
				best_b = b
	if best_b == null:
		return
	if world.construction.enqueue(best_b, best_item):
		_last_research_t = elapsed
	elif elapsed - _last_research_t > gap:
		saving_for_tech = true


# ------------------------------------------------------------------ military

func _military(villagers: Array[Unit], military: Array[Unit]) -> void:
	var army: Dictionary = cfg.get("army", {})
	var target_v: int = _villager_target()
	if phase == "opening" or villagers.size() < int(target_v * float(army.get("train_when_villagers_ratio", 0.6))):
		return
	# Easier AIs keep a small standing army (0 = no cap).
	var cap: int = int(diff.get("army_cap", 0))
	if cap > 0 and military.size() >= cap:
		return
	var mix: Dictionary = Dictionary(army.get("mix", {})).duplicate()
	if phase == "push":
		var bonus: Dictionary = army.get("push_mix_bonus", {})
		for k: String in bonus.keys():
			mix[k] = float(mix.get(k, 0.0)) + float(bonus[k])
	var counts: Dictionary = {}
	for m: Unit in military:
		counts[m.unit_type] = int(counts.get(m.unit_type, 0)) + 1
	var rally: Vector2 = home + (_front() - home).normalized() * float(army.get("rally_offset_px", 320))
	for b: Building in world.buildings:
		if b.owner_id != player_id or not b.is_complete() or b.trains().is_empty() or b.building_type == "town_center":
			continue
		b.rally_point = rally
		if b.queue.size() >= 2:
			continue
		var best: String = ""
		var best_gap: float = -INF
		for type_id: Variant in b.trains():
			var id: String = String(type_id)
			if not mix.has(id) or world.construction.can_enqueue(b, id) != "":
				continue
			var share: float = float(counts.get(id, 0)) / maxf(1.0, float(military.size()))
			var gap: float = float(mix[id]) - share
			if gap > best_gap:
				best_gap = gap
				best = id
		if best != "":
			world.construction.enqueue(b, best)
			counts[best] = int(counts.get(best, 0)) + 1


## Enemies seen near home: everyone fights them. Returns true while defending.
func _defend(military: Array[Unit]) -> bool:
	var radius: float = float(Dictionary(cfg.get("army", {})).get("defend_radius_px", 900))
	var threats: Array[Vector2] = []
	for u: Unit in world.units:
		if u.owner_id >= 0 and u.owner_id != player_id and not u.is_dead and u.position.distance_to(home) < radius \
				and world.vision.grid.is_visible(player_id, u.position):
			threats.append(u.position)
	if threats.is_empty():
		return false
	var spot: Vector2 = Formation.centroid(threats)
	var per: int = int(Dictionary(cfg.get("army", {})).get("defenders_per_threat", 2))
	var free: Array[Unit] = military.filter(func(m: Unit) -> bool: return not (m.task is AttackTask))
	free.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_squared_to(spot) < b.position.distance_squared_to(spot))
	var defenders: Array[Unit] = free.slice(0, mini(free.size(), threats.size() * per + 2))
	if not defenders.is_empty():
		world.combat.attack_move(defenders, spot)
	# A small raid does not stop the rest of the army from attacking.
	return threats.size() * per >= military.size()


func _attack(military: Array[Unit]) -> void:
	var army: Dictionary = cfg.get("army", {})
	var mult: float = float(diff.get("army_mult", 1.0))
	# Peace window: no harassment or pushes before this minute (defence still
	# works). Beginners get time to wall up and train before the first fight.
	if elapsed < float(diff.get("first_attack_min", 0.0)) * 60.0:
		return
	var idle: Array[Unit] = military.filter(func(m: Unit) -> bool: return m.task == null and not m.is_moving())
	idle = _press_on(idle)
	if (phase == "harass" or phase == "push") and _known_enemy_buildings() == 0:
		# Nothing of the enemy is known: send part of the army to explore
		# instead of piling soldiers at home forever.
		_explore_with(idle)
		return
	_harass = _harass.filter(func(m: Unit) -> bool: return world.units.has(m))
	if phase == "harass" and _harass.is_empty():
		var size: int = maxi(3, int(float(army.get("harass_group", 6)) * mult))
		if idle.size() >= size:
			var target: Dictionary = _pick_target(false)
			if not target.is_empty():
				_harass = idle.slice(0, size)
				_order_attack(_harass, target["pos"], "harass")
	elif phase == "push":
		var alive: int = _wave_alive(military)
		# A wave that melted away counts as failed: the next one grows.
		if _wave_was_alive and alive < 3:
			failed_waves += 1
		_wave_was_alive = alive >= 3
		var growth: float = 1.0 + float(diff.get("wave_growth", army.get("wave_growth", 0.25))) * failed_waves
		var wave: int = mini(int(army.get("wave_cap", 40)), maxi(4, int(float(army.get("wave_min", 14)) * mult * growth)))
		# A grown wave must stay reachable: never ask for more than 80% of the army.
		wave = mini(wave, maxi(int(float(army.get("wave_min", 14)) * mult), int(military.size() * 0.8)))
		# Stronger AIs hit the economy (camps and farms, where the villagers
		# work) instead of the Town Center: it breaks the enemy's income.
		var target: Dictionary = _pick_economy_target() if bool(diff.get("raid_economy", false)) else {}
		if target.is_empty():
			target = _pick_target(true)
		if target.is_empty():
			return
		if idle.size() >= wave:
			_order_attack(idle, target["pos"], "push")
			waves += 1
			_last_wave_t = elapsed
			_last_target = target["pos"]
			_wave_was_alive = true
		elif waves > 0 and idle.size() >= int(army.get("reinforce_min", 5)) and alive >= int(army.get("reinforce_needs_alive", 5)):
			# Reinforce only a wave that is still fighting; otherwise build up a full one.
			_order_attack(idle, target["pos"], "reinforce")


## Enemy buildings we know about (seen and not seen destroyed).
func _known_enemy_buildings() -> int:
	return known_buildings.size()


func _my_scouts() -> Array[Unit]:
	return world.units.filter(func(u: Unit) -> bool: return u.owner_id == player_id and u.unit_type == "scout" and not u.is_dead)


## A group of idle soldiers sweeps unexplored ground (attack-move, so they
## fight whatever they meet). One group at a time.
func _explore_with(idle: Array[Unit]) -> void:
	_explorers = _explorers.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead and world.units.has(u))
	var acfg: Dictionary = cfg.get("army", {})
	var size: int = int(acfg.get("explore_group", 6))
	if _explorers.is_empty():
		if idle.size() < size:
			return
		_explorers = idle.slice(0, size)
	var lead: Unit = _explorers[0]
	if lead.is_moving() or lead.task != null:
		return
	var next: Vector2 = _next_scout_point(lead.position)
	if next == Vector2.INF:
		_scout_tries.clear()  # everything seen once: sweep again
		return
	_scout_tries[next] = int(_scout_tries.get(next, 0)) + 1
	world.combat.attack_move(_explorers, next)
	if OS.is_debug_build():
		print("[REALM] ai %d explore units=%d to=(%d,%d)" % [player_id, _explorers.size(), int(next.x), int(next.y)])


## Soldiers standing idle out in the field (their target fell and nothing
## else is in sight) go for the nearest enemy building we know about, instead
## of waiting there while reinforcements pile up. Returns the ones left idle.
func _press_on(idle: Array[Unit]) -> Array[Unit]:
	var field_px: float = float(Dictionary(cfg.get("army", {})).get("field_px", 1500))
	var reach_px: float = float(Dictionary(cfg.get("army", {})).get("press_on_px", 1400))
	var left: Array[Unit] = []
	for u: Unit in idle:
		if u.position.distance_to(home) < field_px:
			left.append(u)
			continue
		var best: Building = null
		var best_d: float = reach_px
		for k: Dictionary in known_buildings.values():
			var ref: Variant = k["ref"]
			if not is_instance_valid(ref) or not world.buildings.has(ref):
				continue
			var d: float = u.position.distance_to(Vector2(k["pos"]))
			if d < best_d:
				best_d = d
				best = ref
		if best == null:
			left.append(u)
		else:
			world.behavior.assign(u, AttackTask.new(u, world, best, false))
	return left


## Own soldiers already out near the last wave's target.
func _wave_alive(military: Array[Unit]) -> int:
	if _last_target == Vector2.INF:
		return 0
	return military.filter(func(m: Unit) -> bool: return m.position.distance_to(_last_target) < 1200.0).size()


## Known enemy building to hit: the push goes for the heart (Town Center),
## harassment for the closest outlying building. Empty if nothing is known.
func _pick_target(prefer_center: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = INF
	for k: Dictionary in known_buildings.values():
		var score: float = Vector2(k["pos"]).distance_to(home)
		if prefer_center and String(k["type"]) == "town_center":
			score -= 100000.0
		if not prefer_center and String(k["type"]) == "town_center":
			score += 100000.0
		if score < best_score:
			best_score = score
			best = k
	return best


## Nearest known enemy gathering building (lumber/mining camp, farm).
func _pick_economy_target() -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for k: Dictionary in known_buildings.values():
		if not ECONOMY_TARGETS.has(String(k["type"])):
			continue
		var d: float = Vector2(k["pos"]).distance_to(home)
		if d < best_d:
			best_d = d
			best = k
	return best


func _order_attack(group: Array[Unit], pos: Vector2, kind: String) -> void:
	var explored: bool = world.vision.grid.is_explored(player_id, pos)
	attack_log.append({"t": elapsed, "pos": pos, "explored": explored, "kind": kind})
	# Marching in line: melee in front, archers and siege behind.
	world.combat.attack_move(group, pos, "line")
	attack_ordered.emit(pos, explored)
	if OS.is_debug_build():
		print("[REALM] ai %d %s t=%.0f units=%d target=(%d,%d)" % [player_id, kind, elapsed, group.size(), int(pos.x), int(pos.y)])


# ------------------------------------------------------------------ scouting

func _scouting() -> void:
	var scouts: Array[Unit] = _my_scouts()
	if scouts.is_empty() and _known_enemy_buildings() == 0 and phase != "opening":
		# Lost the scout before finding anyone: train another.
		var tc: Building = _first_of("town_center")
		if tc != null and tc.is_complete() and not tc.queue.has("scout") and world.construction.can_enqueue(tc, "scout") == "":
			world.construction.enqueue(tc, "scout")
	for s: Unit in scouts:
		s.stance = "passive"
		if s.is_moving() or s.task != null:
			continue
		var next: Vector2 = _next_scout_point(s.position)
		if next == Vector2.INF:
			_scout_tries.clear()  # all seen: sweep again (bases move, armies come)
			continue
		_scout_tries[next] = int(_scout_tries.get(next, 0)) + 1
		world.movement.move_unit(s, next)


func _build_scout_points() -> void:
	_scout_points.clear()
	var step: float = world.tile_size * 12.0
	var y: float = step * 0.5
	while y < world.map_size_px.y:
		var x: float = step * 0.5
		while x < world.map_size_px.x:
			_scout_points.append(Vector2(x, y))
			x += step
		y += step


## Closest grid point this AI has not explored yet (a sweeping search).
func _next_scout_point(from: Vector2) -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	for p: Vector2 in _scout_points:
		if world.vision.grid.is_explored(player_id, p) or not world.nav.is_walkable_world(p):
			continue
		# Ordered twice and still unexplored: probably unreachable, skip it.
		if int(_scout_tries.get(p, 0)) >= 2:
			continue
		var d: float = from.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


# ------------------------------------------------------------------ helpers

func _mine(type_id: String) -> Array[Building]:
	return world.buildings.filter(func(b: Building) -> bool: return b.owner_id == player_id and b.building_type == type_id)


func _first_of(type_id: String) -> Building:
	var list: Array[Building] = _mine(type_id)
	return list[0] if not list.is_empty() else null


## A point between home and the map centre: where military buildings and the
## rally go (facing the rest of the map, not the corner).
func _front() -> Vector2:
	return home + (world.map_size_px * 0.5 - home).normalized() * 420.0
