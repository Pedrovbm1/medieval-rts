class_name BuildTask
extends UnitTask
## Villager constructs a foundation: walk next to it, add progress every frame.
## The first builder works at full speed; each extra one adds a reduced share
## (rules.json construction.extra_builder_factor). When the building is done,
## builders of a farm start farming it and builders of a drop-off start
## gathering what it accepts nearby; otherwise they go idle.

const REACH_SLACK: float = 28.0
const MAX_MOVE_ATTEMPTS: int = 6

var building: Building
var _attempts: int = 0


func _init(p_unit: Unit, p_world: World, p_building: Building = null) -> void:
	super(p_unit, p_world)
	kind = "build"
	building = p_building


func tick(delta: float) -> void:
	if building == null or not is_instance_valid(building):
		finish()
		return
	if building.is_complete():
		finish(_after_build())
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
	unit.mark_working("hammer")
	if not building.builders.has(unit):
		building.builders.append(unit)
	var index: int = building.builders.find(unit)
	var factor: float = 1.0 if index == 0 else float(DataLoader.rule("construction", "extra_builder_factor", 0.6))
	var build_time: float = maxf(1.0, float(building.data.get("build_time", 20.0)))
	building.add_progress(delta / build_time * factor * GameState.modifier(unit.owner_id, "build_speed"))


func cancel() -> void:
	if building != null and is_instance_valid(building):
		building.builders.erase(unit)


func _after_build() -> UnitTask:
	if building == null or not is_instance_valid(building):
		return null
	building.builders.erase(unit)
	if not building.gather_info().is_empty():
		if building.has_free_work_slot(unit):
			return GatherTask.for_farm(unit, world, building)
		return null
	for res: Variant in building.data.get("dropoff", []):
		if String(res) == "wood":
			var cell: Vector2i = world.find_tree_near(building.position, 8)
			if cell.x >= 0:
				return GatherTask.for_tree(unit, world, cell)
		elif String(res) in ["gold", "stone"]:
			var n: ResourceNode = world.find_node_near(String(res), building.position, 512.0)
			if n != null:
				return GatherTask.for_node(unit, world, n)
	return null
