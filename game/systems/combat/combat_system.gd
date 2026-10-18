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


func setup(p_world: World) -> void:
	world = p_world
	z_index = 40
	_acquire_interval = float(DataLoader.rule("combat", "acquire_interval_s", 0.25))
	_corpse_seconds = float(DataLoader.rule("combat", "corpse_seconds", 0.8))
	_flash_seconds = float(DataLoader.rule("combat", "hit_flash_s", 0.12))


# ------------------------------------------------------------------ hits

func apply_hit(attacker: Unit, target: Object, dmg: int) -> void:
	if not Combat.target_alive(target):
		return
	if target is Unit:
		var u: Unit = target
		u.take_damage(dmg, attacker)
		if not u.is_dead:
			u.flash_t = _flash_seconds
			_flashing[u] = true
			u.queue_redraw()
	elif target is Building:
		(target as Building).take_damage(dmg, attacker)


func fire(attacker: Unit, target: Object, dmg: int, speed: float) -> void:
	var p: Projectile = null
	for candidate: Projectile in _projectiles:
		if not candidate.active:
			p = candidate
			break
	if p == null:
		p = Projectile.new()
		add_child(p)
		_projectiles.append(p)
	p.launch(attacker, target, dmg, speed)
	shots_fired += 1


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
		for other: Object in world.movement.spatial.query(unit.position, sight):
			var o: Unit = other as Unit
			if o == unit or o.is_dead or o.owner_id < 0 or o.owner_id == unit.owner_id:
				continue
			var d: float = unit.position.distance_to(o.position)
			if d <= sight and d < best_d:
				best_d = d
				best = o
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


func _acquire_targets() -> void:
	for unit: Unit in world.units:
		if unit.is_dead or unit.owner_id < 0 or unit.is_animal() or unit.data.get("combat", {}).is_empty():
			continue
		var stance: Dictionary = unit.stance_data()
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


## Group order: walk to `target` and fight whatever is met on the way.
func attack_move(group: Array[Unit], target: Vector2) -> void:
	var movers: Array[Unit] = group.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead)
	for u: Unit in movers:
		world.behavior.assign(u, null)
		u.attack_move = true
	world.movement.command_move(movers, target)


# ------------------------------------------------------------------ death

## A unit just died: keep it on screen as a fading corpse, then pool it.
func add_corpse(unit: Unit) -> void:
	kills += 1
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
			if Combat.target_alive(p.target) and is_instance_valid(p.attacker):
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
