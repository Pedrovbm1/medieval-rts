class_name Unit
extends Node2D
## A single unit. Stats come from units.json; this script only moves and draws.
## Placeholder art: a coloured disc with a letter, green ring when selected.
## F1 movement is a straight line to the target (pathfinding arrives in F2).

enum Stance { AGGRESSIVE, HOLD }

var unit_type: String = ""
var owner_id: int = 0
var data: Dictionary = {}
var radius: float = 12.0
var speed_px: float = 96.0
var hp: int = 1
var stance: Stance = Stance.AGGRESSIVE
var selected: bool = false:
	set(value):
		if selected != value:
			selected = value
			queue_redraw()

var move_target: Vector2 = Vector2.INF
var _color: Color = Color.WHITE
var _glyph: String = ""
var _arrive_distance: float = 3.0


## Must be called before adding the unit to the tree.
func setup(type_id: String, player_id: int, world_pos: Vector2) -> void:
	unit_type = type_id
	owner_id = player_id
	position = world_pos
	data = DataLoader.get_entry("units", type_id)
	if data.is_empty():
		push_error("Unit: unknown type " + type_id)
	radius = float(data.get("radius_px", 12))
	hp = int(data.get("hp", 1))
	speed_px = float(data.get("speed", 1.0)) * float(DataLoader.rule("movement", "base_speed_px", 96))
	_arrive_distance = float(DataLoader.rule("movement", "arrive_distance_px", 3))
	_glyph = String(data.get("placeholder_glyph", "?"))
	var colors: Array = DataLoader.rule("players", "colors", ["#3a6fd8", "#d84a3a"])
	_color = Color.html(String(colors[clampi(player_id, 0, colors.size() - 1)]))
	name = "%s_%d" % [type_id, get_instance_id()]


func is_moving() -> bool:
	return move_target != Vector2.INF


func order_move(target: Vector2) -> void:
	move_target = target
	stance = Stance.AGGRESSIVE


func order_stop() -> void:
	move_target = Vector2.INF


func order_hold() -> void:
	move_target = Vector2.INF
	stance = Stance.HOLD


func _physics_process(delta: float) -> void:
	if move_target == Vector2.INF:
		return
	var to_target: Vector2 = move_target - position
	var dist: float = to_target.length()
	var step: float = speed_px * delta
	if dist <= maxf(step, _arrive_distance):
		position = move_target
		move_target = Vector2.INF
		return
	position += to_target / dist * step


func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color(0.35, 1.0, 0.35), 3.0, true)
	draw_circle(Vector2(0, radius * 0.35), radius * 0.95, Color(0, 0, 0, 0.25))  # shadow
	draw_circle(Vector2.ZERO, radius, _color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, _color.darkened(0.45), 2.0, true)
	var font: Font = ThemeDB.fallback_font
	var size: int = int(radius * 1.25)
	var text_size: Vector2 = font.get_string_size(_glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	draw_string(font, Vector2(-text_size.x * 0.5, size * 0.36), _glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, size, Color.WHITE)
