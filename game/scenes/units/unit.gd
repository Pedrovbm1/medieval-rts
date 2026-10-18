class_name Unit
extends Node2D
## A single unit. Stats come from units.json. Movement is driven by
## MovementSystem (path + steering); behaviour by a UnitTask run from
## BehaviorSystem. This script holds state and draws from the shared atlas.

signal arrived(unit: Unit)
signal move_failed(unit: Unit)
signal died(unit: Unit)

const OWNER_GAIA: int = -1

var unit_type: String = ""
var owner_id: int = 0
var data: Dictionary = {}
var radius: float = 12.0
var speed_px: float = 96.0
var arrive_distance: float = 3.0
var hp: int = 1
var max_hp: int = 1
## Stance id from data/stances.json: aggressive | defensive | hold | passive.
var stance: String = "aggressive"
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

# --- behaviour state ---
## Current task (gather, hunt, build...). null = idle.
var task: RefCounted = null
## Resource being carried (villagers).
var carry_type: String = ""
var carry_amount: float = 0.0
## Seconds until this unit may strike again.
var attack_cooldown: float = 0.0
## Last unit that damaged this one (animals and F5 aggro use it).
var last_attacker: Unit = null
var is_dead: bool = false
## Free-form memory for simple brains (animals now, AI micro later).
var brain: Dictionary = {}

## Attack-move: while walking, engage enemies met on the way.
var attack_move: bool = false

# --- combat visuals (CombatSystem drives the timers) ---
var winding_up: bool = false
var facing_target: Vector2 = Vector2.ZERO
var flash_t: float = 0.0
var corpse_t: float = 0.0


## Must be called before adding the unit to the tree.
func setup(type_id: String, player_id: int, world_pos: Vector2) -> void:
	unit_type = type_id
	owner_id = player_id
	position = world_pos
	data = DataLoader.get_entry("units", type_id)
	if data.is_empty():
		push_error("Unit: unknown type " + type_id)
	radius = float(data.get("radius_px", 12))
	max_hp = int(data.get("hp", 1))
	hp = max_hp
	stance = String(data.get("stance", "aggressive"))
	speed_px = float(data.get("speed", 1.0)) * float(DataLoader.rule("movement", "base_speed_px", 96))
	arrive_distance = float(DataLoader.rule("movement", "arrive_distance_px", 3))
	name = "%s_%d" % [type_id, get_instance_id()]


func stance_data() -> Dictionary:
	return DataLoader.get_entry("stances", stance)


## Clears every runtime field and signal connection so the node can be reused.
func reset_for_pool() -> void:
	for sig: Signal in [arrived, move_failed, died]:
		for c: Dictionary in sig.get_connections():
			sig.disconnect(c["callable"])
	selected = false
	clear_move()
	repaths = 0
	stall_timer = 0.0
	best_goal_dist = INF
	task = null
	carry_type = ""
	carry_amount = 0.0
	attack_cooldown = 0.0
	last_attacker = null
	attack_move = false
	is_dead = false
	brain = {}
	winding_up = false
	flash_t = 0.0
	corpse_t = 0.0
	modulate = Color.WHITE


func is_moving() -> bool:
	return goal != Vector2.INF


func is_animal() -> bool:
	return data.has("animal")


func can_gather() -> bool:
	return bool(data.get("can_gather", false))


## Idle = alive, no task, not moving. The idle bell counts these villagers.
func is_idle() -> bool:
	return not is_dead and task == null and not is_moving()


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


## Applies damage. Emits `died` once when hp reaches 0 (World removes the unit).
func take_damage(amount: int, source: Unit) -> void:
	if is_dead:
		return
	hp = maxi(0, hp - maxi(1, amount))
	if source != null and is_instance_valid(source):
		last_attacker = source
	queue_redraw()
	if hp == 0:
		is_dead = true
		died.emit(self)


func change_owner(new_owner: int) -> void:
	owner_id = new_owner
	queue_redraw()


func _draw() -> void:
	var tex: Texture2D = PlaceholderArt.texture()
	var region: Rect2 = PlaceholderArt.unit_region(unit_type, owner_id)
	if is_dead:
		# Corpse: flattened, darkened and fading out before going to the pool.
		var fade: float = clampf(corpse_t / 0.8, 0.0, 1.0)
		draw_texture_rect_region(tex, Rect2(Vector2(-region.size.x * 0.5, -region.size.y * 0.25), Vector2(region.size.x, region.size.y * 0.5)), region, Color(0.35, 0.3, 0.3, fade))
		return
	if selected:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color(0.35, 1.0, 0.35), 3.0, true)
	var tint: Color = Color(1.0, 0.45, 0.45) if flash_t > 0.0 else Color.WHITE
	draw_texture_rect_region(tex, Rect2(-region.size * 0.5, region.size), region, tint)
	if winding_up and facing_target != Vector2.ZERO:
		# Wind-up tell: a short bright stroke toward the target before the hit lands.
		var dir: Vector2 = (facing_target - position).normalized()
		draw_set_transform(dir * (radius + 3.0), dir.angle(), Vector2.ONE)
		draw_texture_rect_region(tex, Rect2(0, -2, 10, 4), PlaceholderArt.WHITE_RECT, Color(1, 0.95, 0.6))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hp < max_hp:
		# HP bar from the atlas' white texel: same texture, so it still batches.
		var w: float = radius * 2.0
		var top: Vector2 = Vector2(-radius, -radius - 9.0)
		draw_texture_rect_region(tex, Rect2(top, Vector2(w, 5.0)), PlaceholderArt.WHITE_RECT, Color(0.1, 0.1, 0.1, 0.85))
		var ratio: float = float(hp) / float(max_hp)
		var col: Color = Color(0.3, 0.9, 0.3) if ratio > 0.5 else (Color(0.95, 0.8, 0.2) if ratio > 0.25 else Color(0.95, 0.3, 0.2))
		draw_texture_rect_region(tex, Rect2(top + Vector2(1, 1), Vector2((w - 2.0) * ratio, 3.0)), PlaceholderArt.WHITE_RECT, col)
	if carry_amount >= 1.0:
		# Small carried-resource chip at the shoulder.
		var chip: Color = ResourceColors.color(carry_type)
		draw_texture_rect_region(tex, Rect2(Vector2(radius * 0.4, -radius * 0.9), Vector2(8, 8)), PlaceholderArt.WHITE_RECT, chip)
