extends Node
## Match entry point: wires the generated world to the camera.

@onready var world: World = $World
@onready var camera: CameraController = $CameraController


func _ready() -> void:
	camera.set_map_bounds(Rect2(Vector2.ZERO, world.map_size_px))
	camera.center_on(world.map_size_px * 0.5)
