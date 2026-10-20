class_name RelicTask
extends UnitTask
## A monk fetches a relic: walk to it, pick it up (the relic leaves the
## ground and travels with the monk), then carry it to the nearest own
## monastery and store it there (gold trickles in from stored relics; holding
## every relic on the map for a while wins). A monk that already carries one
## starts at the delivery. No monastery: the monk keeps the relic and waits.

enum Step { PICK, DELIVER }

const REACH_SLACK: float = 24.0
const MAX_MOVE_ATTEMPTS: int = 8

var relic: ResourceNode = null
var vault: Building = null
var step: Step = Step.PICK
var _attempts: int = 0


func _init(p_unit: Unit, p_world: World, p_relic: ResourceNode = null) -> void:
	super(p_unit, p_world)
	kind = "relic"
	relic = p_relic
	if p_unit.relic or p_relic == null:
		step = Step.DELIVER


## Carry what the monk holds to this monastery.
static func deliver_to(p_unit: Unit, p_world: World, building: Building) -> RelicTask:
	var t: RelicTask = RelicTask.new(p_unit, p_world, null)
	t.vault = building
	t.step = Step.DELIVER
	return t


func tick(_delta: float) -> void:
	match step:
		Step.PICK:
			_tick_pick()
		Step.DELIVER:
			_tick_deliver()


func _tick_pick() -> void:
	if relic == null or not is_instance_valid(relic) or not world.resource_nodes.has(relic):
		finish()
		return
	var rect: Rect2 = relic.rect()
	if World.distance_to_rect(unit.position, rect) > unit.radius + REACH_SLACK:
		if not unit.is_moving():
			if _attempts >= MAX_MOVE_ATTEMPTS:
				finish()
				return
			_attempts += 1
			go_to(relic.position)
		return
	world.movement.stop(unit)
	var at: Vector2 = relic.position
	world.remove_resource(relic)
	relic = null
	unit.relic = true
	unit.queue_redraw()
	Sfx.play_at("deposit", at)
	EventBus.relic_taken.emit(unit.owner_id, at)
	_attempts = 0
	step = Step.DELIVER


func _tick_deliver() -> void:
	if not unit.relic:
		finish()
		return
	if vault == null or not is_instance_valid(vault) or not world.buildings.has(vault) or not vault.is_complete():
		vault = world.nearest_vault(unit.owner_id, unit.position)
		if vault == null:
			finish()  # keep the relic; a monastery may come later
			return
	var rect: Rect2 = vault.rect()
	if World.distance_to_rect(unit.position, rect) > unit.radius + REACH_SLACK:
		if not unit.is_moving():
			if _attempts >= MAX_MOVE_ATTEMPTS:
				finish()
				return
			_attempts += 1
			go_to(world.approach_point(rect, unit.position))
		return
	world.movement.stop(unit)
	unit.relic = false
	unit.queue_redraw()
	vault.relics += 1
	vault.queue_redraw()
	Sfx.play_at("research_done", vault.position)
	EventBus.relic_stored.emit(vault)
	finish()
