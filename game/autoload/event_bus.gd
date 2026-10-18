extends Node
## Global signal hub. Systems emit here; UI and other systems subscribe.
## Keeps nodes decoupled: nobody needs a direct reference to anybody else.

## Emitted once the world has generated its terrain grid.
signal map_generated(width: int, height: int, tile_size: int)
## Emitted when the camera zoom factor changes (0.5 .. 1.5).
signal camera_zoom_changed(zoom_factor: float)
## Emitted by GameState whenever a player resource amount changes.
signal resource_changed(player_id: int, resource: String, amount: int)
## Emitted when a player's population used or cap changes.
signal population_changed(player_id: int, used: int, cap: int)
## Entity lifecycle (World emits these).
signal unit_spawned(unit: Unit)
signal unit_removed(unit: Unit)
signal building_added(building: Building)
signal building_removed(building: Building)
## A forest cell was cut down and is now grass.
signal tree_depleted(cell: Vector2i)
## A villager delivered resources to a drop-off.
signal resources_delivered(player_id: int, resource: String, amount: int)
## A foundation finished construction.
signal building_completed(building: Building)
## A building finished training a unit.
signal unit_trained(unit: Unit, building: Building)
