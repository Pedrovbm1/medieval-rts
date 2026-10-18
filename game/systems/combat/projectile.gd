class_name Projectile
extends Node2D
## An arrow in flight. Pooled by CombatSystem: never freed during a match.
## Homes on the target's current position; damage lands on arrival if the
## target is still alive (missed shots on dead targets just vanish).

var attacker: Unit = null
var target: Object = null
var damage: int = 1
var speed: float = 600.0
var active: bool = false
var _last_target_pos: Vector2 = Vector2.ZERO


func launch(p_attacker: Unit, p_target: Object, p_damage: int, p_speed: float) -> void:
	attacker = p_attacker
	target = p_target
	damage = p_damage
	speed = p_speed
	position = p_attacker.position + Vector2(0, -6)
	_last_target_pos = _aim()
	active = true
	visible = true
	rotation = (_last_target_pos - position).angle()
	queue_redraw()


## Moves the arrow. Returns true when it arrived (caller applies damage).
func step(delta: float) -> bool:
	if Combat.target_alive(target):
		_last_target_pos = _aim()
	var to: Vector2 = _last_target_pos - position
	var dist: float = to.length()
	var move: float = speed * delta
	if dist <= move:
		position = _last_target_pos
		return true
	position += to / dist * move
	rotation = to.angle()
	return false


func deactivate() -> void:
	active = false
	visible = false
	attacker = null
	target = null


func _aim() -> Vector2:
	if target is Building:
		return (target as Building).position
	return (target as Node2D).position


func _draw() -> void:
	var tex: Texture2D = PlaceholderArt.texture()
	draw_texture_rect_region(tex, Rect2(-12, -1.5, 24, 3), PlaceholderArt.WHITE_RECT, Color(0.35, 0.25, 0.15))
	draw_texture_rect_region(tex, Rect2(9, -3, 5, 6), PlaceholderArt.WHITE_RECT, Color(0.85, 0.85, 0.9))
