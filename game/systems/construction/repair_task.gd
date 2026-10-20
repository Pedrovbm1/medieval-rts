class_name RepairTask
extends UnitTask
## Villager mends a damaged, finished building (walls and gates included):
## walk next to it, restore rules repair.hp_per_s each second and pay a share
## of the building's cost as the HP comes back (repair.cost_ratio of the cost
## for the missing HP). Slower right after an enemy hit (repair.under_attack
## _factor). When the building is whole, the villager goes back to what it
## was gathering before. Stops when the owner cannot pay.

const REACH_SLACK: float = 28.0
const MAX_MOVE_ATTEMPTS: int = 6

var building: Building
## What the villager was gathering (resumed when the repair is done).
var resume: GatherTask = null
## Fractions of each resource owed but not yet paid (paid when >= 1).
var _owed: Dictionary = {}
var _attempts: int = 0
## HP restored so far (tests / logs).
var repaired: int = 0
var _carry: float = 0.0


func _init(p_unit: Unit, p_world: World, p_building: Building = null) -> void:
	super(p_unit, p_world)
	kind = "repair"
	building = p_building
	if p_unit.task is GatherTask:
		resume = p_unit.task
	elif p_unit.task is BuildTask:
		resume = (p_unit.task as BuildTask).resume
	elif p_unit.task is RepairTask:
		resume = (p_unit.task as RepairTask).resume


## Whether a villager may repair this building at all.
static func can_repair(unit: Unit, b: Building) -> bool:
	return unit != null and b != null and is_instance_valid(b) and unit.can_gather() 			and b.owner_id == unit.owner_id and b.is_complete() and b.hp < b.max_hp


func tick(delta: float) -> void:
	if building == null or not is_instance_valid(building) or not building.is_complete() or building.hp <= 0:
		finish(_back_to_work())
		return
	if building.hp >= building.max_hp:
		finish(_back_to_work())
		return
	var rect: Rect2 = building.rect()
	if World.distance_to_rect(unit.position, rect) > unit.radius + REACH_SLACK:
		if not unit.is_moving():
			if _attempts >= MAX_MOVE_ATTEMPTS:
				finish()
				return
			_attempts += 1
			go_to(world.approach_point(rect, unit.position))
		return
	if unit.is_moving():
		world.movement.stop(unit)
	_attempts = 0
	if not building.repairers.has(unit):
		building.repairers.append(unit)
		building.queue_redraw()
	unit.mark_working("hammer")
	var rate: float = float(DataLoader.rule("repair", "hp_per_s", 10.0)) * GameState.modifier(unit.owner_id, "build_speed")
	if building.recently_hit(float(DataLoader.rule("repair", "under_attack_s", 5.0))):
		rate *= float(DataLoader.rule("repair", "under_attack_factor", 0.5))
	_carry += rate * delta
	var whole: int = int(floorf(_carry))
	if whole <= 0:
		return
	whole = mini(whole, building.max_hp - building.hp)
	if not _pay(whole):
		finish(_back_to_work())
		return
	_carry -= whole
	building.repair(whole)
	repaired += whole


## Charges the share of the cost for `hp` points. False (nothing charged)
## when the owner cannot afford what is due.
func _pay(hp: int) -> bool:
	var ratio: float = float(DataLoader.rule("repair", "cost_ratio", 0.5))
	var cost: Dictionary = building.data.get("cost", {})
	var due: Dictionary = {}
	for res: String in cost.keys():
		var owed: float = float(_owed.get(res, 0.0)) + float(cost[res]) * ratio * hp / building.max_hp
		var pay: int = int(floorf(owed))
		_owed[res] = owed - pay
		if pay > 0:
			due[res] = pay
	if due.is_empty():
		return true
	if not GameState.can_afford(unit.owner_id, due):
		for res: String in due.keys():
			_owed[res] = float(_owed[res]) + int(due[res])  # keep the debt for a retry
		return false
	return GameState.spend(unit.owner_id, due)


func cancel() -> void:
	if building != null and is_instance_valid(building):
		building.repairers.erase(unit)
		building.queue_redraw()


func _back_to_work() -> UnitTask:
	cancel()
	if resume != null:
		return GatherTask.resume_like(resume, unit, world)
	return null
