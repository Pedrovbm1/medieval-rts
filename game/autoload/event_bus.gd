extends Node
## Global signal hub. Systems emit here; UI and other systems subscribe.
## Keeps nodes decoupled: nobody needs a direct reference to anybody else.

## Emitted once the world has generated its terrain grid.
signal map_generated(width: int, height: int, tile_size: int)
## Emitted when the camera zoom factor changes (0.5 .. 1.5).
signal camera_zoom_changed(zoom_factor: float)
## Emitted by GameState whenever a player resource amount changes.
signal resource_changed(player_id: int, resource: String, amount: int)
