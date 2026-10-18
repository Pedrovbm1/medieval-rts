class_name Unit
extends Node2D
## A single unit. Stats come from units.json. Movement is driven by
## MovementSystem (path + steering); this script holds state and draws.
## Placeholder art: a coloured disc with a letter, green ring when selected.

signal arrived(unit: Unit)
signal move_failed(unit: Unit)

enum Stance { AGGRESSIVE, HOLD }

var unit_type: String = ""
var owner_id: int = 0
var data: Dictionary = {}
var radius: float = 12.0
var speed_px: float = 96.0
var arrive_distance: float = 3.0
var hp: int = 1
var stance: Stance = Stance.AGGRESSIVE
var selected: bool = false:
	set(value):
		if selected != value:
			selected = value
			queue_redraw()

# --- movement state (owned by MovementSystem) ---
var goal: Vector2 = Vector2.INF
var path: PackedVector2Array = PackedVector2Array()
var path_i: int = 0
var waiting_path: bool = false
var group_id: int = 0
var repaths: int = 0
var stall_timer: float = 0.0
var best_goal_dist: float = INF

var _color: Color = Color.WHITE
var _glyph: String = ""


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
	arrive_distance = float(DataLoader.rule("movement", "arrive_distance_px", 3))
	_glyph = String(data.get("placeholder_glyph", "?"))
	var colors: Array = DataLoader.rule("players", "colors", ["#3a6fd8", "#d84a3a"])
	_color = Color.html(String(colors[clampi(player_id, 0, colors.size() - 1)]))
	name = "%s_%d" % [type_id, get_instance_id()]


func is_moving() -> bool:
	return goal != Vector2.INF


func clear_move() -> void:
	goal = Vector2.INF
	path = PackedVector2Array()
	path_i = 0
	waiting_path = false
	group_id = 0


func finish_move() -> void:
	clear_move()
	arrived.emit(self)


func fail_move() -> void:
	clear_move()
	move_failed.emit(self)


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
