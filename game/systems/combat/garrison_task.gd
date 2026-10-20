class_name GarrisonTask
extends UnitTask
## Walk to an own building that shelters units and step inside. The unit
## leaves World.units (safe from arrows and swords) and adds an arrow to the
## building's volley. Ends on the spot if the building fills up or falls.

const REACH_SLACK: float = 28.0
const MAX_MOVE_ATTEMPTS: int = 6

var building: Building
## What the unit was gathering when sent in (handed to the building, so the
## villager goes back to it when it comes out).
var resume: GatherTask = null
var _attempts: int = 0


func _init(p_unit: Unit, p_world: World, p_building: Building = null) -> void:
	super(p_unit, p_world)
	kind = "garrison"
	building = p_building
	if p_unit.task is GatherTask:
		resume = p_unit.task
	elif p_unit.task is BuildTask:
		resume = (p_unit.task as BuildTask).resume
	elif p_unit.task is RepairTask:
		resume = (p_unit.task as RepairTask).resume
	elif p_unit.task is GarrisonTask:
		resume = (p_unit.task as GarrisonTask).resume


func tick(_delta: float) -> void:
	if building == null or not is_instance_valid(building) or not building.can_garrison(unit):
		finish()
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
	# Going in ends the task: World takes the unit out of the match loop.
	# Keep the gather task alive underneath so the building can remember it.
	var b: Building = building
	finish()
	world.garrison_unit(unit, b, resume)
