class_name VisionSystem
extends Node
## Feeds VisionGrid from every unit and building a few times per second.
## Sight radii come from data (units "sight_px", buildings "sight_px").

const DEFAULT_UNIT_SIGHT: float = 256.0
const DEFAULT_BUILDING_SIGHT: float = 256.0

var world: World
var grid: VisionGrid = VisionGrid.new()
## Fog drawn for the human (null = no fog, e.g. benchmarks and tests).
var fog_layer: FogLayer = null
var fog_enabled: bool = true
var interval: float = 0.25
var last_update_usec: int = 0
var _timer: float = 0.0


func setup(p_world: World) -> void:
	world = p_world
	interval = float(DataLoader.rule("vision", "update_interval_s", 0.25))
	grid.setup(world.map_width, world.map_height, float(world.tile_size), [GameState.PLAYER_HUMAN, GameState.PLAYER_AI])
	refresh()


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_timer += delta
	if _timer >= interval:
		_timer = 0.0
		refresh()


func refresh() -> void:
	var t0: int = Time.get_ticks_usec()
	var sources: Dictionary = {GameState.PLAYER_HUMAN: [], GameState.PLAYER_AI: []}
	for u: Unit in world.units:
		if u.owner_id >= 0 and sources.has(u.owner_id) and not u.is_dead:
			(sources[u.owner_id] as Array).append([u.position, Combat.sight_of(u, DEFAULT_UNIT_SIGHT)])
	for b: Building in world.buildings:
		if sources.has(b.owner_id):
			(sources[b.owner_id] as Array).append([b.position, Combat.sight_of(b, DEFAULT_BUILDING_SIGHT)])
	grid.update(sources)
	if fog_enabled:
		_apply_visibility()
		if fog_layer != null:
			fog_layer.refresh()
	last_update_usec = Time.get_ticks_usec() - t0


## Enemy and wild units, and enemy buildings, are drawn only while the human
## sees them; resources show once explored. Own things are always drawn.
func _apply_visibility() -> void:
	var me: int = GameState.PLAYER_HUMAN
	for u: Unit in world.units:
		u.visible = u.owner_id == me or grid.is_visible(me, u.position)
	for b: Building in world.buildings:
		b.visible = b.owner_id == me or grid.is_visible(me, b.position)
	for n: ResourceNode in world.resource_nodes:
		n.visible = grid.is_explored(me, n.position)
