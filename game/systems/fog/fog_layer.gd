class_name FogLayer
extends Sprite2D
## Fog of war for the human player, drawn as ONE stretched texture with one
## texel per map cell (unseen = black, explored = dim, visible = clear).
## Linear filtering softens the cell edges. Updated whenever VisionSystem
## refreshes (every 0.25 s), so revealing the map lags < 0.5 s.

const UNSEEN_ALPHA: float = 1.0
const EXPLORED_ALPHA: float = 0.55

var player_id: int = GameState.PLAYER_HUMAN
var _image: Image
var _texture: ImageTexture
var _grid: VisionGrid
var last_update_usec: int = 0


func setup(grid: VisionGrid, map_size_px: Vector2) -> void:
	_grid = grid
	_image = Image.create(grid.width, grid.height, false, Image.FORMAT_LA8)
	_texture = ImageTexture.create_from_image(_image)
	texture = _texture
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scale = Vector2(map_size_px.x / grid.width, map_size_px.y / grid.height)
	z_index = 80
	refresh()


func refresh() -> void:
	if _grid == null or not _grid.states.has(player_id):
		return
	var t0: int = Time.get_ticks_usec()
	var states: PackedByteArray = _grid.states[player_id]
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(states.size() * 2)
	var unseen: int = int(UNSEEN_ALPHA * 255.0)
	var explored: int = int(EXPLORED_ALPHA * 255.0)
	for i: int in states.size():
		var s: int = states[i]
		bytes[i * 2] = 0
		bytes[i * 2 + 1] = unseen if s == VisionGrid.UNSEEN else (explored if s == VisionGrid.EXPLORED else 0)
	_image.set_data(_grid.width, _grid.height, false, Image.FORMAT_LA8, bytes)
	_texture.update(_image)
	last_update_usec = Time.get_ticks_usec() - t0
