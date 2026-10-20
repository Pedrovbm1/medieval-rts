class_name Minimap
extends Control
## Touch minimap (bottom-left): terrain baked once, fog on top, dots for
## units/buildings the player can see, camera rectangle, pulsing attack
## alerts. Tap or drag on it to move the camera. Redrawn 4 times a second.

signal jump_to(world_pos: Vector2)

const REDRAW_SECONDS: float = 0.25
const ALERT_SECONDS: float = 4.0

var world: World
var camera: CameraController
var player_id: int = GameState.PLAYER_HUMAN
var _terrain_tex: ImageTexture
var _fog_tex: ImageTexture
var _fog_img: Image
var _timer: float = 0.0
## [world_pos, time_left]
var _alerts: Array = []


func setup(p_world: World, p_camera: CameraController) -> void:
	world = p_world
	camera = p_camera
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bake_terrain()
	_fog_img = Image.create(world.map_width, world.map_height, false, Image.FORMAT_LA8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	EventBus.tree_depleted.connect(func(_c: Vector2i) -> void: _bake_terrain())


## Marks a spot: "attack" (red pulse), "villagers" (yellow pulse), "breach"
## (red cross, a wall fell) or "army" (orange triangle, enemy army seen).
func alert(world_pos: Vector2, kind: String = "attack") -> void:
	for a: Array in _alerts:
		if Vector2(a[0]).distance_to(world_pos) < 600.0:
			# One mark per spot; the newest (most specific) kind wins.
			a[1] = ALERT_SECONDS
			a[2] = kind
			return
	_alerts.append([world_pos, ALERT_SECONDS, kind])


## Kinds currently shown (tests).
func alert_kinds() -> Array[String]:
	var out: Array[String] = []
	for a: Array in _alerts:
		out.append(String(a[2]))
	return out


func _process(delta: float) -> void:
	if world == null:
		return
	for a: Array in _alerts:
		a[1] = float(a[1]) - delta
	_alerts = _alerts.filter(func(a: Array) -> bool: return float(a[1]) > 0.0)
	_timer += delta
	if _timer >= REDRAW_SECONDS or not _alerts.is_empty():
		if _timer >= REDRAW_SECONDS:
			_timer = 0.0
			_update_fog()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var pos: Vector2 = Vector2.INF
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pos = (event as InputEventMouseButton).position
	if pos != Vector2.INF:
		jump_to.emit(to_world(pos))
		accept_event()


## Local minimap point -> world position.
func to_world(local: Vector2) -> Vector2:
	return local / size * world.map_size_px


func to_local_point(world_pos: Vector2) -> Vector2:
	return world_pos / world.map_size_px * size


func _draw() -> void:
	if world == null:
		return
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r.grow(3.0), Color(0.08, 0.07, 0.06, 0.9))
	draw_texture_rect(_terrain_tex, r, false)
	draw_texture_rect(_fog_tex, r, false)
	var grid: VisionGrid = world.vision.grid
	var colors: Array = DataLoader.rule("players", "colors", ["#3a6fd8", "#d84a3a"])
	for b: Building in world.buildings:
		if b.owner_id != player_id and not grid.is_visible(player_id, b.position):
			continue
		var c: Color = Color.html(String(colors[clampi(b.owner_id, 0, colors.size() - 1)]))
		var rr: Rect2 = Rect2(to_local_point(b.rect().position), b.rect().size / world.map_size_px * size)
		draw_rect(rr.grow(0.5), c.lightened(0.2))
	for u: Unit in world.units:
		if u.owner_id < 0:
			continue
		if u.owner_id != player_id and not grid.is_visible(player_id, u.position):
			continue
		var cu: Color = Color.html(String(colors[clampi(u.owner_id, 0, colors.size() - 1)]))
		draw_rect(Rect2(to_local_point(u.position) - Vector2(1.5, 1.5), Vector2(3, 3)), cu.lightened(0.35))
	if camera != null:
		var view: Rect2 = camera.visible_world_rect()
		draw_rect(Rect2(to_local_point(view.position), view.size / world.map_size_px * size), Color(1, 1, 1, 0.9), false, 1.5)
	var t: float = Time.get_ticks_msec() / 1000.0
	for a: Array in _alerts:
		var p: Vector2 = to_local_point(a[0])
		var pulse: float = 6.0 + 6.0 * absf(sin(t * 5.0))
		match String(a[2]):
			"villagers":
				draw_arc(p, pulse, 0.0, TAU, 20, Color(1, 0.9, 0.3, 0.95), 2.0)
			"breach":
				var s: float = 5.0 + 2.0 * absf(sin(t * 4.0))
				draw_line(p + Vector2(-s, -s), p + Vector2(s, s), Color(1, 0.2, 0.15, 0.95), 3.0)
				draw_line(p + Vector2(s, -s), p + Vector2(-s, s), Color(1, 0.2, 0.15, 0.95), 3.0)
			"army":
				var s2: float = 6.0 + 2.0 * absf(sin(t * 4.0))
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s2), p + Vector2(s2, s2), p + Vector2(-s2, s2)]), Color(1, 0.6, 0.15, 0.95))
			_:
				draw_arc(p, pulse, 0.0, TAU, 20, Color(1, 0.25, 0.2, 0.95), 2.0)


func _bake_terrain() -> void:
	var img: Image = Image.create(world.map_width, world.map_height, false, Image.FORMAT_RGB8)
	var types: Dictionary = DataLoader.get_table("terrain").get("types", {})
	var colors: Dictionary = {}
	for name: String in types.keys():
		colors[int(types[name]["id"])] = Color.html(String(types[name].get("color", "#000000")))
	for y: int in world.map_height:
		for x: int in world.map_width:
			img.set_pixel(x, y, colors.get(world.get_terrain_id(Vector2i(x, y)), Color.BLACK))
	for n: ResourceNode in world.resource_nodes:
		var col: Color = Color.html(String(n.data.get("color", "#ffffff")))
		for c: Vector2i in n.cells():
			if c.x >= 0 and c.y >= 0 and c.x < world.map_width and c.y < world.map_height:
				img.set_pixelv(c, col)
	if _terrain_tex == null:
		_terrain_tex = ImageTexture.create_from_image(img)
	else:
		_terrain_tex.update(img)


func _update_fog() -> void:
	var grid: VisionGrid = world.vision.grid
	if not grid.states.has(player_id):
		return
	var states: PackedByteArray = grid.states[player_id]
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(states.size() * 2)
	for i: int in states.size():
		var s: int = states[i]
		bytes[i * 2 + 1] = 255 if s == VisionGrid.UNSEEN else (130 if s == VisionGrid.EXPLORED else 0)
	_fog_img.set_data(world.map_width, world.map_height, false, Image.FORMAT_LA8, bytes)
	_fog_tex.update(_fog_img)
