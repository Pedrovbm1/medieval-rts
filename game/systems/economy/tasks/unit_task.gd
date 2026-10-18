class_name UnitTask
extends RefCounted
## Base class for a unit behaviour run every physics frame by BehaviorSystem.
## A task ends by setting `done`; it may hand over to `next_task`
## (e.g. a hunt becomes "gather the carcass").

var unit: Unit
var world: World
var done: bool = false
var next_task: UnitTask = null
## Short id for logs, HUD and tests ("gather", "hunt", "build"...).
var kind: String = "task"


func _init(p_unit: Unit, p_world: World) -> void:
	unit = p_unit
	world = p_world


func tick(_delta: float) -> void:
	pass


## Called when the task is replaced or the unit is removed: release claims.
func cancel() -> void:
	pass


func finish(p_next: UnitTask = null) -> void:
	done = true
	next_task = p_next


## Asks the movement system to walk to `pos` unless already heading there.
func go_to(pos: Vector2) -> void:
	if unit.is_moving() and unit.goal.distance_to(pos) < 8.0:
		return
	world.movement.move_unit(unit, pos)
