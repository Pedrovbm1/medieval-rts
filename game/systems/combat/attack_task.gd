class_name AttackTask
extends UnitTask
## Attack a unit or building: chase into range, wind up (visible prepare
## time), strike or shoot, recover, repeat. Ordered attacks always chase;
## auto-acquired ones obey the unit's stance (chase / leash / hold).
## When the target dies, aggressive units look for the next enemy nearby.

var target: Object = null
var ordered: bool = false
## Destination of an interrupted attack-move (INF if none).
var resume_to: Vector2 = Vector2.INF
var anchor: Vector2 = Vector2.ZERO
var _windup: float = -1.0
var _attack: Dictionary = {}
var _range: float = 0.0
var _repath_px: float = 48.0
## Times the chase stalled (path ended short of the target). A target that
## cannot be reached exactly (standing on a blocked cell, map edge) is hit
## from a bit farther; after too many stalls the task gives up.
var _stalls: int = 0
const STALL_REACH_PX: float = 48.0
const MAX_STALLS: int = 12


func _init(p_unit: Unit, p_world: World, p_target: Object = null, p_ordered: bool = true) -> void:
	super(p_unit, p_world)
	kind = "attack"
	target = p_target
	ordered = p_ordered
	anchor = p_unit.position
	if p_unit.attack_move and p_unit.goal != Vector2.INF:
		resume_to = p_unit.goal
	_attack = p_unit.data.get("combat", {})
	_range = Combat.range_of(p_unit)
	_repath_px = float(DataLoader.rule("combat", "chase_repath_px", 48))


func tick(delta: float) -> void:
	if not Combat.target_alive(target):
		_next_target()
		return
	var stance: Dictionary = unit.stance_data()
	var gap: float = Combat.gap(unit, target)
	var stalled_close: bool = not unit.is_moving() and _stalls >= 2 and gap <= _range + STALL_REACH_PX
	if gap > _range and not stalled_close:
		_windup = -1.0
		if not ordered and not bool(stance.get("chase", true)):
			finish()
			return
		var leash: float = float(stance.get("leash_px", 768))
		if not ordered and leash > 0.0 and unit.position.distance_to(anchor) > leash:
			finish(_walk_back())
			return
		var tpos: Vector2 = _target_pos()
		if not unit.is_moving():
			_stalls += 1
			if _stalls > MAX_STALLS:
				finish()  # unreachable: let auto-acquire or the player pick another
				return
			world.movement.move_unit(unit, tpos)
		elif unit.goal.distance_to(tpos) > _repath_px:
			world.movement.move_unit(unit, tpos)
		return
	if gap <= _range:
		_stalls = 0
	var min_range: float = float(unit.data.get("min_range_px", 0.0))
	if min_range > 0.0 and gap < min_range:
		# Too close to fire (siege): back off first.
		var away: Vector2 = (unit.position - _target_pos()).normalized()
		if away == Vector2.ZERO:
			away = Vector2.RIGHT
		if not unit.is_moving():
			world.movement.move_unit(unit, unit.position + away * min_range * 1.6)
		_windup = -1.0
		return
	if unit.is_moving():
		world.movement.stop(unit)
	if _windup >= 0.0:
		_windup -= delta
		if _windup <= 0.0:
			_windup = -1.0
			_strike()
		return
	if unit.attack_cooldown <= 0.0:
		_windup = float(_attack.get("prepare_s", 0.3))
		unit.facing_target = _target_pos()
		unit.winding_up = true
		unit.queue_redraw()


func cancel() -> void:
	unit.winding_up = false


func _strike() -> void:
	unit.winding_up = false
	unit.queue_redraw()
	var repeat: float = Combat.repeat_of(unit)
	unit.attack_cooldown = maxf(0.05, repeat - float(_attack.get("prepare_s", 0.3)))
	if not Combat.target_alive(target):
		return
	var dmg: int = Combat.hit_damage(unit, target)
	# Siege charge: the first blow on a building after a rest hits harder
	# (units.json combat.charge {mult, cooldown_s}), so a ram opens a wall fast.
	var charge: Dictionary = _attack.get("charge", {})
	if not charge.is_empty() and unit.charge_cd <= 0.0 and target is Building:
		dmg = int(round(dmg * float(charge.get("mult", 2.0))))
		unit.charge_cd = float(charge.get("cooldown_s", 20.0))
		Sfx.play_at("siege_hit", (target as Building).position)
	var proj: Dictionary = _attack.get("projectile", {})
	if not proj.is_empty():
		world.combat.fire(unit, target, dmg, float(proj.get("speed_px", 600)), float(_attack.get("splash_px", 0.0)))
	else:
		world.combat.apply_hit(unit, target, dmg)


func _target_pos() -> Vector2:
	if target is Building:
		return world.approach_point((target as Building).rect(), unit.position)
	return (target as Node2D).position


## Target gone: aggressive/defensive units pick the next enemy in sight.
func _next_target() -> void:
	unit.winding_up = false
	if bool(unit.stance_data().get("auto_acquire", false)):
		var next: Object = world.combat.find_enemy(unit)
		if next != null:
			target = next
			ordered = false
			_windup = -1.0
			return
	finish(_walk_back() if not ordered else null)


func _walk_back() -> UnitTask:
	if resume_to != Vector2.INF:
		world.movement.move_unit(unit, resume_to)
		unit.attack_move = true
		return null
	if unit.position.distance_to(anchor) > 96.0 and String(unit.stance) != "hold":
		world.movement.move_unit(unit, anchor)
	return null
