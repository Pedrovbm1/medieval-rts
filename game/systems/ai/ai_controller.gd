class_name AIController
extends Node
## Computer opponent for one player. Thinks every `think_s` seconds (not every
## frame) through 4 phases: opening -> development -> harass -> push.
## Plays fair: it only knows what its own units and buildings have seen
## (VisionGrid) and uses the same systems as the human (build, train, gather,
## attack-move). Every number comes from data/ai.json.

signal attack_ordered(target: Vector2, explored: bool)

const PRODUCTION: PackedStringArray = ["barracks", "archery_range", "stable"]

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
## Saving for an era gives up after a while (e.g. gold ran out) and retries later.
var _saving_since: float = -1.0
var _no_saving_until: float = -1.0
var _wave_was_alive: bool = false


func setup(p_world: World, p_player: int, p_difficulty: String, p_seed: int = 1) -> void:
	world = p_world
	player_id = p_player
	difficulty_id = p_difficulty
	cfg = DataLoader.get_table("ai")
	diff = Dictionary(cfg.get("difficulties", {})).get(difficulty_id, {})
	_think_s = float(diff.get("think_s", 2.0))
	rng.seed = p_seed
	# Hard AI: economic bonus as a gather multiplier on every resource subtype.
	var gm: float = float(diff.get("gather_mult", 1.0))
	if not is_equal_approx(gm, 1.0):
		var mults: Dictionary = GameState.multipliers.get(player_id, {})
		for sub: String in ["berries", "meat", "farm", "wood", "gold", "stone"]:
			mults["gather." + sub] = float(mults.get("gather." + sub, 1.0)) * gm
		GameState.multipliers[player_id] = mults
	var tc: Building = _first_of("town_center")
	home = tc.position if tc != null else world.map_size_px * 0.5
	_build_scout_points()
	name = "AI_%d_%s" % [player_id, difficulty_id]


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
	_economy(villagers)
	_advance(villagers)
	# While saving for an era, keep only the standing army this phase needs.
	var min_army: int = int(float(Dictionary(Dictionary(cfg.get("saving", {})).get("min_army", {})).get(phase, 0)) * float(diff.get("army_mult", 1.0)))
	var army_paused: bool = (saving_for_era and military.size() >= min_army) or saving_for_tech
	if not army_paused:
		_military(villagers, military)
	_scouting()
	if not _defend(military):
		_attack(military)


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
		if PRODUCTION.has(type_id) and want > 0:
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
	var idle: Array[Unit] = military.filter(func(m: Unit) -> bool: return m.task == null and not m.is_moving())
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
		var target: Dictionary = _pick_target(true)
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


func _order_attack(group: Array[Unit], pos: Vector2, kind: String) -> void:
	var explored: bool = world.vision.grid.is_explored(player_id, pos)
	attack_log.append({"t": elapsed, "pos": pos, "explored": explored, "kind": kind})
	world.combat.attack_move(group, pos)
	attack_ordered.emit(pos, explored)
	if OS.is_debug_build():
		print("[REALM] ai %d %s t=%.0f units=%d target=(%d,%d)" % [player_id, kind, elapsed, group.size(), int(pos.x), int(pos.y)])


# ------------------------------------------------------------------ scouting

func _scouting() -> void:
	var scouts: Array[Unit] = world.units.filter(func(u: Unit) -> bool: return u.owner_id == player_id and u.unit_type == "scout" and not u.is_dead)
	for s: Unit in scouts:
		s.stance = "passive"
		if s.is_moving() or s.task != null:
			continue
		var next: Vector2 = _next_scout_point(s.position)
		if next != Vector2.INF:
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
