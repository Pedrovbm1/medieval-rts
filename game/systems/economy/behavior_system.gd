class_name BehaviorSystem
extends Node
## Runs every unit's task and every animal's simple brain in one loop.
## - Tasks (gather, hunt, later build/attack) tick each physics frame.
## - Animals: sheep join the first player that comes close (herd), deer run
##   away when hit (flee), boars fight whoever hit them (aggressive).
## - Lure help: when a boar chases a villager near its drop-off, nearby
##   villagers of that player join the hunt.

const BRAIN_INTERVAL: float = 0.25
const HELP_RADIUS_PX: float = 320.0
const HOME_RADIUS_PX: float = 384.0

var world: World
var _brain_timer: float = 0.0


func setup(p_world: World) -> void:
	world = p_world


## Gives `unit` a new task (or null for idle), cancelling the old one.
func assign(unit: Unit, task: UnitTask) -> void:
	if unit.task != null:
		(unit.task as UnitTask).cancel()
	unit.task = task
	unit.queue_redraw()


func release(unit: Unit) -> void:
	if unit.task != null:
		(unit.task as UnitTask).cancel()
		unit.task = null


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_brain_timer += delta
	var brain_tick: bool = _brain_timer >= BRAIN_INTERVAL
	if brain_tick:
		_brain_timer = 0.0
	for unit: Unit in world.units.duplicate():
		if unit.is_dead or not is_instance_valid(unit):
			continue
		unit.attack_cooldown = maxf(0.0, unit.attack_cooldown - delta)
		if unit.task != null:
			var task: UnitTask = unit.task
			task.tick(delta)
			if task.done and unit.task == task:
				unit.task = task.next_task
				unit.queue_redraw()
		elif unit.is_animal():
			_animal(unit, brain_tick)
	for n: ResourceNode in world.resource_nodes.duplicate():
		n.decay(delta)


# ------------------------------------------------------------------ animals

func _animal(animal: Unit, brain_tick: bool) -> void:
	var cfg: Dictionary = animal.data.get("animal", {})
	match String(cfg.get("behavior", "")):
		"herd":
			if brain_tick and animal.owner_id == Unit.OWNER_GAIA:
				_herd(animal, cfg)
		"flee":
			_flee(animal, cfg)
		"aggressive":
			_fight_back(animal, cfg)


func _herd(animal: Unit, cfg: Dictionary) -> void:
	var radius: float = float(cfg.get("convert_radius_px", 192))
	for other: Object in world.movement.spatial.query(animal.position, radius):
		var u: Unit = other as Unit
		if u.owner_id >= 0 and not u.is_animal() and u.position.distance_to(animal.position) <= radius:
			animal.change_owner(u.owner_id)
			return


func _flee(animal: Unit, cfg: Dictionary) -> void:
	var attacker: Unit = animal.last_attacker
	if attacker == null or not is_instance_valid(attacker):
		return
	# One flight per hit: remember the hp we already reacted to.
	if int(animal.brain.get("fled_at_hp", -1)) == animal.hp:
		return
	animal.brain["fled_at_hp"] = animal.hp
	var away: Vector2 = (animal.position - attacker.position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var dest: Vector2 = animal.position + away * float(cfg.get("flee_distance_px", 224))
	dest = dest.clamp(Vector2.ZERO, world.map_size_px - Vector2.ONE)
	world.movement.move_unit(animal, dest)


func _fight_back(animal: Unit, cfg: Dictionary) -> void:
	var foe: Unit = animal.last_attacker
	if foe == null or not is_instance_valid(foe) or foe.is_dead:
		if animal.last_attacker != null:
			animal.last_attacker = null
			world.movement.stop(animal)
		return
	if not animal.brain.has("home"):
		animal.brain["home"] = animal.position
	if animal.position.distance_to(animal.brain["home"]) > float(cfg.get("leash_px", 900)):
		# Too far from its spot: give up and walk back.
		animal.last_attacker = null
		animal.brain.erase("fled_at_hp")
		world.movement.move_unit(animal, animal.brain["home"])
		return
	var reach: float = animal.radius + foe.radius + 8.0
	var dist: float = animal.position.distance_to(foe.position)
	if dist > reach:
		if not animal.is_moving() or animal.goal.distance_to(foe.position) > 32.0:
			world.movement.move_unit(animal, foe.position)
		return
	if animal.is_moving():
		world.movement.stop(animal)
	if animal.attack_cooldown <= 0.0:
		animal.attack_cooldown = float(Dictionary(animal.data.get("combat", {})).get("repeat_s", 1.5))
		world.combat.apply_hit(animal, foe, Combat.hit_damage(animal, foe))
		_call_helpers(animal, foe)


## A boar is mauling a villager near home: villagers around come to help.
func _call_helpers(boar: Unit, victim: Unit) -> void:
	var home: Building = world.economy.nearest_dropoff(victim.owner_id, "food", victim.position)
	if OS.is_debug_build() and bool(DataLoader.rule("debug", "log_tasks", false)):
		print("[REALM] boar strike victim=%s home=%s dist=%.0f" % [victim.name, home.name if home else "none", World.distance_to_rect(victim.position, home.rect()) if home else -1.0])
	if home == null or World.distance_to_rect(victim.position, home.rect()) > HOME_RADIUS_PX:
		return
	for other: Object in world.movement.spatial.query(boar.position, HELP_RADIUS_PX):
		var u: Unit = other as Unit
		if u == victim or u.owner_id != victim.owner_id or not u.can_gather() or u.is_dead:
			continue
		if u.task is HuntTask:
			continue
		if u.position.distance_to(boar.position) <= HELP_RADIUS_PX:
			assign(u, HuntTask.new(u, world, boar))
