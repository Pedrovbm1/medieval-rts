class_name HealTask
extends UnitTask
## Support unit (monk) heals a wounded ally: walk into range, restore HP over
## time (data "heal": hp_per_s, range_px), then move on to the next wounded
## ally in sight, or stop.

var target: Unit = null
var _accum: float = 0.0
var _heal: Dictionary = {}


func _init(p_unit: Unit, p_world: World, p_target: Unit = null) -> void:
	super(p_unit, p_world)
	kind = "heal"
	target = p_target
	_heal = p_unit.data.get("heal", {})


func tick(delta: float) -> void:
	if not _valid(target):
		target = world.combat.find_wounded_ally(unit)
		if target == null:
			finish()
			return
	var reach: float = float(_heal.get("range_px", 160))
	var gap: float = Combat.gap(unit, target)
	if gap > reach:
		if not unit.is_moving() or unit.goal.distance_to(target.position) > 48.0:
			world.movement.move_unit(unit, target.position)
		return
	if unit.is_moving():
		world.movement.stop(unit)
	_accum += float(_heal.get("hp_per_s", 3.0)) * delta
	if _accum >= 1.0:
		var amount: int = int(_accum)
		_accum -= amount
		target.heal(amount)
		Sfx.play_at("heal", target.position)
		world.combat.healed += amount


func _valid(u: Unit) -> bool:
	return Combat.target_alive(u) and u.hp < u.max_hp and u.owner_id == unit.owner_id
