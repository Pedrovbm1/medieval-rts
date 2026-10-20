class_name Building
extends Node2D
## A building placed on the grid. Stats from buildings.json.
## Blocks its footprint cells in NavGrid unless "walkable" (farms).
## F3: placed already built. F4 adds construction progress and production.

signal destroyed(building: Building)
## Construction finished (HUD, AI, builders react).
signal completed(building: Building)
## Queue / progress changed (HUD refresh).
signal changed(building: Building)

var building_type: String = ""
var owner_id: int = 0
var data: Dictionary = {}
var cell: Vector2i = Vector2i.ZERO
var footprint: Vector2i = Vector2i(2, 2)
var tile_size: float = 64.0
var hp: int = 1
var max_hp: int = 1
var walkable: bool = false
## Draw layer for ground-level buildings; the terrain sits below it (World).
const GROUND_Z: int = -1
## 0..1. Fully built buildings work (drop-off, pop, farm). F4 grows it.
var build_progress: float = 1.0
## Workers currently assigned (farms limit this).
var workers: Array[Unit] = []
## Villagers currently constructing it (order = speed share).
var builders: Array[Unit] = []
## Production: unit type ids waiting; the first one is in training.
var queue: Array[String] = []
var train_elapsed: float = 0.0
## True while the head of the queue waits for free population.
var blocked_by_pop: bool = false
## Where trained units walk to (INF = stay next to the building).
var rally_point: Vector2 = Vector2.INF
## Armed buildings (towers): seconds until the next shot.
var attack_cooldown: float = 0.0
## Gates: open lets everyone through; closed blocks the cell (enemies near).
var is_open: bool = true
var _open_since: float = 0.0
## Units sheltered inside (Town Center, towers): hidden, safe, and each one
## adds an arrow to the building's volley. World.garrison_unit / eject move
## them in and out; `garrison_resume` remembers what each was doing.
var garrison: Array[Unit] = []
var garrison_resume: Dictionary = {}
## Villagers currently repairing it (hammer icon, panel).
var repairers: Array[Unit] = []
## Farms: food left in the current sowing (-1 = endless). When it runs out
## the farm reseeds itself for its cost, or lies fallow until there is wood.
var food_left: float = -1.0
var fallow: bool = false
var reseeds: int = 0
## Monasteries: relics stored inside (gold trickles; all of them = victory).
var relics: int = 0
## Game-clock seconds (Time.get_ticks_msec) of the last enemy hit: repairs
## are slower right after one, and the HUD knows a fight is on.
var last_hit_s: float = -999.0
var selected: bool = false:
	set(value):
		if selected != value:
			selected = value
			queue_redraw()


func setup(type_id: String, player_id: int, origin_cell: Vector2i, p_tile_size: float) -> void:
	building_type = type_id
	owner_id = player_id
	cell = origin_cell
	tile_size = p_tile_size
	data = DataLoader.get_entry("buildings", type_id)
	if data.is_empty():
		push_error("Building: unknown type " + type_id)
	var fp: Array = data.get("footprint", [2, 2])
	footprint = Vector2i(int(fp[0]), int(fp[1]))
	max_hp = int(data.get("hp", 100))
	hp = max_hp
	walkable = bool(data.get("walkable", false))
	food_left = float(Dictionary(data.get("gather", {})).get("amount", -1.0))
	# Walkable buildings (farms) are ground: always under units, whatever
	# their position in the y-sort (villagers used to vanish under farms).
	z_index = GROUND_Z if walkable else 0
	# Node origin at the footprint centre so y-sorting looks right.
	position = (Vector2(cell) + Vector2(footprint) * 0.5) * tile_size
	name = "%s_%d" % [type_id, get_instance_id()]


func is_complete() -> bool:
	return build_progress >= 1.0


## Turns a freshly placed building into a foundation (0% built, low HP).
func make_foundation() -> void:
	build_progress = 0.0
	hp = maxi(1, int(max_hp * float(DataLoader.rule("construction", "foundation_hp_ratio", 0.1))))
	queue_redraw()


## Adds construction progress (0..1). HP rises with it. Returns true on completion.
func add_progress(amount: float) -> bool:
	if is_complete():
		return false
	var before: float = build_progress
	build_progress = minf(1.0, build_progress + amount)
	hp = mini(max_hp, hp + int(ceilf((build_progress - before) * max_hp * 0.9)))
	queue_redraw()
	changed.emit(self)
	if build_progress >= 1.0:
		hp = max_hp
		completed.emit(self)
		return true
	return false


func trains() -> Array:
	return data.get("trains", [])


## Seconds a queue item takes (unit training or "#research").
func train_time_of(item: String) -> float:
	return TechSystem.item_time(item)


## Max HP from data times the owner's "hp.building" techs (current HP keeps its ratio).
func recompute_stats() -> void:
	var new_max: int = maxi(1, int(round(float(data.get("hp", 100)) * Combat.class_mult(owner_id, data, "hp"))))
	if new_max != max_hp:
		hp = clampi(int(round(float(hp) * new_max / max_hp)), 1, new_max)
		max_hp = new_max
		queue_redraw()


func train_progress() -> float:
	if queue.is_empty():
		return 0.0
	return clampf(train_elapsed / train_time_of(queue[0]), 0.0, 1.0)


func rect() -> Rect2:
	return Rect2(Vector2(cell) * tile_size, Vector2(footprint) * tile_size)


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in footprint.y:
		for x: int in footprint.x:
			out.append(cell + Vector2i(x, y))
	return out


func accepts(resource: String) -> bool:
	return is_complete() and Array(data.get("dropoff", [])).has(resource)


func pop_bonus() -> int:
	return int(data.get("pop_bonus", 0)) if is_complete() else 0


## Farm-like buildings: {"resource", "subtype", "workers"}; empty otherwise.
func gather_info() -> Dictionary:
	return data.get("gather", {})


## Takes food from the sowing; endless farms (no "amount") always give.
func take_food(want: float) -> float:
	if food_left < 0.0:
		return want
	if fallow:
		return 0.0
	var got: float = minf(want, food_left)
	food_left -= got
	if food_left <= 0.001:
		food_left = 0.0
		if not reseed():
			fallow = true
			queue_redraw()
			EventBus.farm_fallow.emit(self)
	return got


## Pays the farm's cost again for a fresh sowing (rules farms.auto_reseed).
## False when the owner cannot afford it or the farm is not a finite farm.
func reseed() -> bool:
	var amount: float = float(Dictionary(data.get("gather", {})).get("amount", -1.0))
	if amount <= 0.0 or not bool(DataLoader.rule("farms", "auto_reseed", true)):
		return false
	if not GameState.spend(owner_id, data.get("cost", {})):
		return false
	food_left = amount
	fallow = false
	reseeds += 1
	queue_redraw()
	EventBus.farm_reseeded.emit(self)
	return true


func has_free_work_slot(unit: Unit) -> bool:
	workers = workers.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead)
	if workers.has(unit):
		return true
	return workers.size() < int(gather_info().get("workers", 1))


func take_damage(amount: int, source: Unit) -> void:
	hp = maxi(0, hp - maxi(1, amount))
	if source != null and is_instance_valid(source) and owner_id >= 0 and source.owner_id >= 0 and source.owner_id != owner_id:
		last_hit_s = Time.get_ticks_msec() / 1000.0
		# Ranked alert first (the HUD may swallow the generic one after it).
		EventBus.building_attacked.emit(self, source)
		EventBus.under_attack.emit(owner_id, position)
	queue_redraw()
	if hp == 0:
		Sfx.play_at("collapse", position)
		destroyed.emit(self)


## Restores HP (repairs). Never above max; never on foundations.
func repair(amount: int) -> void:
	if not is_complete() or hp >= max_hp:
		return
	hp = mini(max_hp, hp + maxi(0, amount))
	queue_redraw()


## True while an enemy hit landed less than `window_s` seconds ago.
func recently_hit(window_s: float) -> bool:
	return Time.get_ticks_msec() / 1000.0 - last_hit_s < window_s


## A tap on an own shelter sends units in only while it makes sense: the
## building was hit lately or an enemy soldier is close (otherwise the tap
## just selects the building, which is what a player usually wants).
func in_danger(p_world: World) -> bool:
	if recently_hit(float(DataLoader.rule("garrison", "danger_s", 20.0))):
		return true
	var radius: float = float(DataLoader.rule("garrison", "danger_px", 420.0))
	for other: Object in p_world.movement.spatial.query(position, radius):
		var u: Unit = other as Unit
		if not u.is_dead and u.owner_id >= 0 and u.owner_id != owner_id and not u.can_gather() and u.position.distance_to(position) <= radius:
			return true
	return false


# ------------------------------------------------------------------ garrison

## {"slots", "classes"} for buildings that shelter units; empty otherwise.
func garrison_info() -> Dictionary:
	return data.get("garrison", {})


func garrison_slots() -> int:
	return int(garrison_info().get("slots", 0))


## Whether this unit may shelter here now (own, built, class allowed, room).
func can_garrison(unit: Unit) -> bool:
	var info: Dictionary = garrison_info()
	if info.is_empty() or not is_complete() or unit == null or unit.owner_id != owner_id or unit.is_dead:
		return false
	if garrison.size() >= int(info.get("slots", 0)):
		return false
	var allowed: Array = info.get("classes", [])
	for c: Variant in Combat.classes_of(unit.data):
		if allowed.has(String(c)):
			return true
	return false


## Extra arrows per volley from the sheltered units (rules garrison.arrow_cap).
func garrison_arrows() -> int:
	if data.get("combat", {}).is_empty():
		return 0
	return mini(garrison.size(), int(DataLoader.rule("garrison", "arrow_cap", 10)))


func is_gate() -> bool:
	return bool(data.get("gate", false))


func is_wall() -> bool:
	return Array(data.get("classes", [])).has("wall")


## Opens or closes the gate: a closed gate blocks its cell for everyone.
func set_gate_open(open: bool, nav: NavGrid) -> void:
	if not is_gate() or open == is_open:
		return
	is_open = open
	nav.set_blocked(cells(), not open)
	queue_redraw()
	if OS.is_debug_build():
		print("[REALM] gate %s at=(%d,%d)" % ["open" if open else "closed", cell.x, cell.y])


func _draw() -> void:
	var tex: Texture2D = PlaceholderArt.texture()
	var look: String = building_type
	if is_gate() and is_open:
		look = "gate_open"
	var region: Rect2 = PlaceholderArt.building_region(look, owner_id, GameState.era_of(owner_id) if building_type == "town_center" else 0)
	var half: Vector2 = Vector2(footprint) * tile_size * 0.5
	if is_complete():
		# A fallow farm is bare earth: dim and brown until it is reseeded.
		draw_texture_rect_region(tex, Rect2(-half, region.size), region, Color(0.6, 0.5, 0.42) if fallow else Color.WHITE)
	else:
		# Foundation: faded building + construction progress bar.
		draw_texture_rect_region(tex, Rect2(-half, region.size), region, Color(1, 1, 1, 0.35 + 0.5 * build_progress))
		var bar: Rect2 = Rect2(Vector2(-half.x + 10.0, half.y - 18.0), Vector2(half.x * 2.0 - 20.0, 8.0))
		draw_texture_rect_region(tex, bar, PlaceholderArt.WHITE_RECT, Color(0.1, 0.1, 0.1, 0.85))
		draw_texture_rect_region(tex, Rect2(bar.position + Vector2(1, 1), Vector2((bar.size.x - 2.0) * build_progress, 6.0)), PlaceholderArt.WHITE_RECT, Color(0.95, 0.8, 0.3))
	if not queue.is_empty():
		var tbar: Rect2 = Rect2(Vector2(-half.x + 10.0, -half.y + 18.0), Vector2(half.x * 2.0 - 20.0, 6.0))
		draw_texture_rect_region(tex, tbar, PlaceholderArt.WHITE_RECT, Color(0.1, 0.1, 0.1, 0.85))
		draw_texture_rect_region(tex, Rect2(tbar.position + Vector2(1, 1), Vector2((tbar.size.x - 2.0) * train_progress(), 4.0)), PlaceholderArt.WHITE_RECT, Color(0.4, 0.75, 1.0))
	if selected:
		draw_rect(Rect2(-half, half * 2.0), Color(0.35, 1.0, 0.35), false, 3.0)
	if is_complete() and hp < max_hp:
		_draw_cracks(tex, half)
	if hp < max_hp:
		var top: Vector2 = Vector2(-half.x + 8.0, -half.y - 10.0)
		var w: float = half.x * 2.0 - 16.0
		draw_texture_rect_region(tex, Rect2(top, Vector2(w, 6.0)), PlaceholderArt.WHITE_RECT, Color(0.1, 0.1, 0.1, 0.85))
		var ratio: float = float(hp) / max_hp
		var col: Color = Color(0.3, 0.9, 0.3) if ratio > 0.5 else (Color(0.95, 0.8, 0.2) if ratio > 0.25 else Color(0.95, 0.3, 0.2))
		draw_texture_rect_region(tex, Rect2(top + Vector2(1, 1), Vector2((w - 2.0) * ratio, 4.0)), PlaceholderArt.WHITE_RECT, col)
	if not repairers.is_empty():
		# Hammer over the roof: someone is repairing.
		var at: Vector2 = Vector2(half.x - 22.0, -half.y - 26.0)
		draw_texture_rect_region(tex, Rect2(at + Vector2(6, 4), Vector2(4, 16)), PlaceholderArt.WHITE_RECT, Color(0.55, 0.35, 0.15))
		draw_texture_rect_region(tex, Rect2(at, Vector2(16, 7)), PlaceholderArt.WHITE_RECT, Color(0.95, 0.85, 0.3))
	if relics > 0:
		# Gold boxes on the roof, one per relic.
		for i: int in mini(relics, 6):
			draw_texture_rect_region(tex, Rect2(Vector2(-half.x + 8.0 + i * 14.0, -half.y + 14.0), Vector2(11, 8)), PlaceholderArt.WHITE_RECT, Color(0.98, 0.85, 0.35))
			draw_texture_rect_region(tex, Rect2(Vector2(-half.x + 8.0 + i * 14.0, -half.y + 17.0), Vector2(11, 2)), PlaceholderArt.WHITE_RECT, Color(0.45, 0.3, 0.1))
	if not garrison.is_empty():
		# One dot per sheltered unit along the top edge (up to 10).
		for i: int in mini(garrison.size(), 10):
			draw_texture_rect_region(tex, Rect2(Vector2(-half.x + 6.0 + i * 7.0, -half.y + 4.0), Vector2(5, 5)), PlaceholderArt.WHITE_RECT, Color(1.0, 0.95, 0.6))


## Damage states: dark cracks appear at 60% and spread at 30%, so a wall
## about to fall reads at a glance. Positions come from the cell, so each
## building cracks differently but always the same way.
func _draw_cracks(tex: Texture2D, half: Vector2) -> void:
	var ratio: float = float(hp) / max_hp
	if ratio >= 0.6:
		return
	var n: int = 2 if ratio >= 0.3 else 5
	var seed_v: int = cell.x * 73 + cell.y * 151
	var ink: Color = Color(0.08, 0.06, 0.05, 0.85)
	for i: int in n:
		var h: int = (seed_v + i * 97) % 1000
		var x: float = -half.x + 6.0 + float(h % 100) / 100.0 * (half.x * 2.0 - 14.0)
		var y: float = -half.y * 0.2 + float((h / 10) % 100) / 100.0 * (half.y * 1.1)
		var len_v: float = 6.0 + float(h % 7) * 2.0
		var vertical: bool = (h / 100) % 2 == 0
		draw_texture_rect_region(tex, Rect2(Vector2(x, y), Vector2(2.0, len_v) if vertical else Vector2(len_v, 2.0)), PlaceholderArt.WHITE_RECT, ink)
		draw_texture_rect_region(tex, Rect2(Vector2(x + (2.0 if vertical else len_v * 0.5), y + (len_v * 0.5 if vertical else 2.0)), Vector2(len_v * 0.6, 2.0) if vertical else Vector2(2.0, len_v * 0.6)), PlaceholderArt.WHITE_RECT, ink)
