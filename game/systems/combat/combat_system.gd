class_name CombatSystem
extends Node2D
## Combat runtime for every player:
## - target acquisition by stance (every acquire_interval_s, not per frame),
## - applying hits (flash feedback), arrows from a pool,
## - dying units fade as corpses, then go back to World's unit pool.
## Holds projectile nodes as children (pooled, never freed mid-match).

var world: World
var _acquire_timer: float = 0.0
var _acquire_interval: float = 0.25
var _corpse_seconds: float = 0.8
var _flash_seconds: float = 0.12
var _projectiles: Array[Projectile] = []
var _flashing: Dictionary = {}
var _corpses: Dictionary = {}
## Stats for tests / tuning.
var shots_fired: int = 0
var kills: int = 0
var healed: int = 0
## Damage dealt per attacker unit type (tuning and role tests).
var damage_by_type: Dictionary = {}


func setup(p_world: World) -> void:
	world = p_world
	z_index = 40
	_acquire_interval = float(DataLoader.rule("combat", "acquire_interval_s", 0.25))
	_corpse_seconds = float(DataLoader.rule("combat", "corpse_seconds", 0.8))
	_flash_seconds = float(DataLoader.rule("combat", "hit_flash_s", 0.12))


# ------------------------------------------------------------------ hits

func apply_hit(attacker: Node2D, target: Object, dmg: int) -> void:
	if not Combat.target_alive(target):
		return
	var source: Unit = attacker as Unit if attacker != null and is_instance_valid(attacker) else null
	if attacker != null and is_instance_valid(attacker):
		var kind: String = source.unit_type if source != null else String(attacker.get("building_type"))
		damage_by_type[kind] = int(damage_by_type.get(kind, 0)) + dmg
	_hit_sound(attacker, target)
	if target is Unit:
		var u: Unit = target
		u.take_damage(dmg, source)
		if not u.is_dead:
			u.flash_t = _flash_seconds
			_flashing[u] = true
			u.queue_redraw()
	elif target is Building:
		(target as Building).take_damage(dmg, source)


## Impact sound: swords for melee, thuds for arrows, crashes on buildings.
func _hit_sound(attacker: Node2D, target: Object) -> void:
	var at: Vector2 = (target as Node2D).position
	var id: String = "hit_building"
	if target is Unit:
		var melee: bool = attacker != null and is_instance_valid(attacker) and attacker is Unit 				and float(Dictionary((attacker as Unit).data.get("combat", {})).get("range_px", 0.0)) <= 0.0
		id = "sword" if melee else "arrow_hit"
	if Sfx.play_at(id, at):
		_ping_music(attacker, target)


## Fighting between players (not hunting) on screen: battle music.
func _ping_music(attacker: Object, target: Object) -> void:
	if attacker == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	if int(attacker.get("owner_id")) >= 0 and int(target.get("owner_id")) >= 0:
		Music.combat_ping()


func fire(attacker: Node2D, target: Object, dmg: int, speed: float, splash: float = 0.0) -> void:
	var p: Projectile = null
	for candidate: Projectile in _projectiles:
		if not candidate.active:
			p = candidate
			break
	if p == null:
		p = Projectile.new()
		add_child(p)
		_projectiles.append(p)
	p.launch(attacker, target, dmg, speed, splash)
	shots_fired += 1
	if Sfx.play_at("siege_fire" if splash > 0.0 else "bow", attacker.position):
		_ping_music(attacker, target)


## Area damage around `center`: full damage at the centre, half at the edge.
## Hits every enemy unit and building of the shooter in range (no friendly fire).
func apply_splash(attacker: Node2D, shooter_owner: int, center: Vector2, radius: float, base_damage: int) -> int:
	var hits: int = 0
	Sfx.play_at("siege_hit", center)
	var src: Unit = attacker as Unit if is_instance_valid(attacker) else null
	for other: Object in world.movement.spatial.query(center, radius + 24.0).duplicate():
		var u: Unit = other as Unit
		if u.is_dead or u.owner_id == shooter_owner or u.owner_id < 0:
			continue
		var d: float = maxf(0.0, u.position.distance_to(center) - u.radius)
		if d > radius:
			continue
		var falloff: float = lerpf(1.0, 0.5, clampf(d / radius, 0.0, 1.0))
		var dmg: int = Combat.hit_damage(src, u) if src != null else base_damage
		apply_hit(src, u, maxi(1, int(dmg * falloff)))
		hits += 1
	for b: Building in world.buildings.duplicate():
		if b.owner_id == shooter_owner or b.owner_id < 0:
			continue
		if World.distance_to_rect(center, b.rect()) <= radius:
			var bd: int = Combat.hit_damage(src, b) if src != null else base_damage
			b.take_damage(bd, src)
			hits += 1
	return hits


## Nearest wounded ally (own unit, not an animal) within a healer's sight.
func find_wounded_ally(healer: Unit) -> Unit:
	var sight: float = float(healer.data.get("sight_px", 320))
	var best: Unit = null
	var best_d: float = INF
	for other: Object in world.movement.spatial.query(healer.position, sight):
		var u: Unit = other as Unit
		if u == healer or u.is_dead or u.owner_id != healer.owner_id or u.is_animal() or u.hp >= u.max_hp:
			continue
		var d: float = healer.position.distance_to(u.position)
		if d <= sight and d < best_d:
			best_d = d
			best = u
	return best


func active_projectiles() -> int:
	return _projectiles.filter(func(p: Projectile) -> bool: return p.active).size()


func pooled_projectiles() -> int:
	return _projectiles.size()


# ------------------------------------------------------------------ targeting

## Nearest enemy a unit may engage on its own (stance, sight, buildings_only).
func find_enemy(unit: Unit) -> Object:
	var attack: Dictionary = unit.data.get("combat", {})
	var sight: float = float(unit.data.get("sight_px", 288))
	if String(unit.stance) == "hold":
		sight = maxf(float(attack.get("range_px", 0.0)), unit.radius + 24.0) + 8.0
	var best: Object = null
	var best_d: float = INF
	if not bool(attack.get("buildings_only", false)):
		best = nearest_enemy_unit(unit, sight)
		if best != null:
			best_d = unit.position.distance_to((best as Unit).position)
	if best != null or unit.can_gather():
		return best
	for b: Building in world.buildings:
		if b.owner_id == unit.owner_id or b.owner_id < 0:
			continue
		var d: float = World.distance_to_rect(unit.position, b.rect())
		if d <= sight and d < best_d:
			best_d = d
			best = b
	return best


## Nearest enemy (player-owned) unit within `sight` px, or null.
## With `soldiers_only`, villagers are ignored.
func nearest_enemy_unit(unit: Unit, sight: float, soldiers_only: bool = false) -> Unit:
	var best: Unit = null
	var best_d: float = INF
	for other: Object in world.movement.spatial.query(unit.position, sight):
		var o: Unit = other as Unit
		if o == unit or o.is_dead or o.owner_id < 0 or o.owner_id == unit.owner_id:
			continue
		if soldiers_only and o.can_gather():
			continue
		var d: float = unit.position.distance_to(o.position)
		if d <= sight and d < best_d:
			best_d = d
			best = o
	return best


## Armed buildings (towers) shoot the nearest enemy unit in range.
func _towers(interval: float) -> void:
	for b: Building in world.buildings:
		if b.data.get("combat", {}).is_empty() or not b.is_complete() or b.owner_id < 0:
			continue
		b.attack_cooldown -= interval
		if b.attack_cooldown > 0.0:
			continue
		var reach: float = Combat.range_of(b)
		var targets: Array[Unit] = []
		for other: Object in world.movement.spatial.query(b.position, reach):
			var u: Unit = other as Unit
			if u.is_dead or u.owner_id < 0 or u.owner_id == b.owner_id:
				continue
			if b.position.distance_to(u.position) <= reach:
				targets.append(u)
		if targets.is_empty():
			continue
		targets.sort_custom(func(x: Unit, y: Unit) -> bool: return x.position.distance_squared_to(b.position) < y.position.distance_squared_to(b.position))
		b.attack_cooldown = Combat.repeat_of(b)
		var proj: Dictionary = Dictionary(b.data["combat"]).get("projectile", {})
		# One arrow, plus one per sheltered unit: the volley spreads over the
		# nearest enemies in range (a garrisoned Town Center is a hedgehog).
		var volley: int = 1 + b.garrison_arrows()
		for i: int in volley:
			var target: Unit = targets[i % targets.size()]
			fire(b, target, Combat.hit_damage(b, target), float(proj.get("speed_px", 600)))


func _acquire_targets() -> void:
	_towers(_acquire_interval)
	for unit: Unit in world.units:
		if unit.is_dead or unit.owner_id < 0 or unit.is_animal():
			continue
		if unit.data.has("heal"):
			if unit.task == null and not unit.is_moving():
				var ally: Unit = find_wounded_ally(unit)
				if ally != null:
					world.behavior.assign(unit, HealTask.new(unit, world, ally))
			continue
		if unit.data.get("combat", {}).is_empty():
			continue
		var stance: Dictionary = unit.stance_data()
		if unit.task is AttackTask:
			_prefer_soldiers(unit, unit.task as AttackTask)
			continue
		if unit.task != null:
			continue
		var foe: Unit = unit.last_attacker
		if bool(stance.get("respond_when_hit", false)) and foe != null and is_instance_valid(foe) and not foe.is_dead and foe.owner_id != unit.owner_id:
			world.behavior.assign(unit, AttackTask.new(unit, world, foe, false))
			continue
		if unit.is_moving() and not unit.attack_move:
			continue
		if not bool(stance.get("auto_acquire", false)) and not unit.attack_move:
			continue
		var enemy: Object = find_enemy(unit)
		if enemy != null:
			world.behavior.assign(unit, AttackTask.new(unit, world, enemy, false))


## A unit that picked a building on its own drops it when enemy soldiers
## come close: fighting back beats hitting walls while being cut down.
## Explicit orders (the player tapped the building) are kept.
func _prefer_soldiers(unit: Unit, task: AttackTask) -> void:
	if task.ordered or not (task.target is Building) or bool(Dictionary(unit.data.get("combat", {})).get("buildings_only", false)):
		return
	var threat: Unit = _nearest_attacker(unit, float(unit.data.get("sight_px", 288)))
	if threat == null:
		return
	var next: AttackTask = AttackTask.new(unit, world, threat, false)
	next.resume_to = task.resume_to
	world.behavior.assign(unit, next)


## Nearest enemy within `sight` that is attacking one of `unit`'s side
## (a passing scout or a fleeing villager is not a reason to stop).
func _nearest_attacker(unit: Unit, sight: float) -> Unit:
	var best: Unit = null
	var best_d: float = INF
	for other: Object in world.movement.spatial.query(unit.position, sight):
		var o: Unit = other as Unit
		if o == unit or o.is_dead or o.owner_id < 0 or o.owner_id == unit.owner_id or not (o.task is AttackTask):
			continue
		var victim: Object = (o.task as AttackTask).target
		if not (victim is Unit) or not is_instance_valid(victim) or (victim as Unit).owner_id != unit.owner_id:
			continue
		var d: float = unit.position.distance_to(o.position)
		if d <= sight and d < best_d:
			best_d = d
			best = o
	return best


## Group order: walk to `target` and fight whatever is met on the way.
func attack_move(group: Array[Unit], target: Vector2, formation: String = "none") -> void:
	var movers: Array[Unit] = group.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead)
	for u: Unit in movers:
		world.behavior.assign(u, null)
		u.attack_move = true
	world.movement.command_move(movers, target, formation)


# ------------------------------------------------------------------ death

## A unit just died: keep it on screen as a fading corpse, then pool it.
func add_corpse(unit: Unit) -> void:
	kills += 1
	Sfx.play_at("death", unit.position)
	unit.corpse_t = _corpse_seconds
	unit.selected = false
	_corpses[unit] = true
	unit.queue_redraw()


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_acquire_timer += delta
	if _acquire_timer >= _acquire_interval:
		_acquire_timer = 0.0
		_acquire_targets()
	for p: Projectile in _projectiles:
		if p.active and p.step(delta):
			if p.splash_px > 0.0:
				apply_splash(p.attacker, p.shooter_owner, p.impact_point(), p.splash_px, p.damage)
			elif Combat.target_alive(p.target) and is_instance_valid(p.attacker):
				apply_hit(p.attacker, p.target, p.damage)
			elif Combat.target_alive(p.target):
				apply_hit(null, p.target, p.damage)
			p.deactivate()
	for u: Unit in _flashing.keys():
		if not is_instance_valid(u):
			_flashing.erase(u)
			continue
		u.flash_t -= delta
		if u.flash_t <= 0.0:
			u.flash_t = 0.0
			_flashing.erase(u)
		u.queue_redraw()
	for u: Unit in _corpses.keys():
		u.corpse_t -= delta
		u.queue_redraw()
		if u.corpse_t <= 0.0:
			_corpses.erase(u)
			world.recycle_unit(u)


## Drops pending corpses (match teardown).
func clear() -> void:
	for u: Unit in _corpses.keys():
		world.recycle_unit(u)
	_corpses.clear()
	_flashing.clear()
	for p: Projectile in _projectiles:
		p.deactivate()
