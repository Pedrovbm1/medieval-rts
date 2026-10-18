class_name HuntTask
extends UnitTask
## Villager hunting: throw spears from range until the animal falls, then
## gather its carcass. Against an aggressive animal (boar) the hunter "lures"
## it back toward the nearest drop-off before standing to fight, so helpers
## near the base can join (BehaviorSystem calls them).

const CHASE_REPATH_PX: float = 48.0
const LURE_STOP_PX: float = 160.0

var prey: Unit = null
var last_seen: Vector2 = Vector2.ZERO
var luring: bool = false
var _lure_point: Vector2 = Vector2.INF


func _init(p_unit: Unit, p_world: World, p_prey: Unit = null) -> void:
	super(p_unit, p_world)
	kind = "hunt"
	prey = p_prey
	if prey != null:
		last_seen = prey.position


func tick(_delta: float) -> void:
	if prey == null or not is_instance_valid(prey) or prey.is_dead:
		_on_prey_gone()
		return
	last_seen = prey.position
	var reach: float = float(unit.data.get("hunt_range_px", unit.radius + prey.radius + 8.0))
	var dist: float = unit.position.distance_to(prey.position) - prey.radius

	if _should_lure():
		luring = true
		if _lure_point == Vector2.INF:
			var home: Building = world.economy.nearest_dropoff(unit.owner_id, "food", unit.position)
			if home != null:
				_lure_point = world.approach_point(home.rect(), unit.position)
		if _lure_point != Vector2.INF and unit.position.distance_to(_lure_point) > LURE_STOP_PX:
			go_to(_lure_point)
			_strike_if_ready(dist, reach)
			return
	if dist <= reach:
		if unit.is_moving() and not luring:
			world.movement.stop(unit)
		_strike_if_ready(dist, reach)
	elif not unit.is_moving() or unit.goal.distance_to(prey.position) > CHASE_REPATH_PX:
		world.movement.move_unit(unit, prey.position)


func _strike_if_ready(dist: float, reach: float) -> void:
	if dist > reach or unit.attack_cooldown > 0.0:
		return
	var dmg: int = int(unit.data.get("hunt_attack", unit.data.get("attack", 1)))
	unit.attack_cooldown = float(unit.data.get("attack_interval", 1.2))
	prey.take_damage(dmg, unit)


## Lure only aggressive prey that is chasing this hunter, far from home.
func _should_lure() -> bool:
	var animal: Dictionary = prey.data.get("animal", {})
	if String(animal.get("behavior", "")) != "aggressive" or prey.last_attacker != unit:
		return false
	return _lure_point == Vector2.INF or unit.position.distance_to(_lure_point) > LURE_STOP_PX


func _on_prey_gone() -> void:
	var carcass: ResourceNode = world.node_at(last_seen, 24.0)
	if carcass != null and carcass.subtype == "meat" and unit.can_gather():
		finish(GatherTask.for_node(unit, world, carcass))
	else:
		finish()
