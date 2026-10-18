class_name Projectile
extends Node2D
## An arrow in flight. Pooled by CombatSystem: never freed during a match.
## Homes on the target's current position; damage lands on arrival if the
## target is still alive (missed shots on dead targets just vanish).

var attacker: Node2D = null
var target: Object = null
var damage: int = 1
var speed: float = 600.0
## Area damage radius on impact (0 = single target).
var splash_px: float = 0.0
## Owner of the shot, so splash never hurts its own side.
var shooter_owner: int = -1
var active: bool = false
var _last_target_pos: Vector2 = Vector2.ZERO


func launch(p_attacker: Node2D, p_target: Object, p_damage: int, p_speed: float, p_splash: float = 0.0) -> void:
	attacker = p_attacker
	target = p_target
	damage = p_damage
	speed = p_speed
	splash_px = p_splash
	shooter_owner = int(p_attacker.get("owner_id"))
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


func impact_point() -> Vector2:
	return _last_target_pos


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
	if splash_px > 0.0:
		# Stone from a mangonel.
		draw_texture_rect_region(tex, Rect2(-6, -6, 12, 12), PlaceholderArt.WHITE_RECT, Color(0.45, 0.42, 0.4))
		return
	draw_texture_rect_region(tex, Rect2(-12, -1.5, 24, 3), PlaceholderArt.WHITE_RECT, Color(0.35, 0.25, 0.15))
	draw_texture_rect_region(tex, Rect2(9, -3, 5, 6), PlaceholderArt.WHITE_RECT, Color(0.85, 0.85, 0.9))
