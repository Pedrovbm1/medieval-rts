class_name PathQueue
extends RefCounted
## Amortised path requests: at most `budget` A* searches per frame, oldest first.
## A newer request from the same owner replaces the pending one.

var budget: int = 8
## Soft time cap per frame (microseconds). At least one path is always computed.
var budget_usec: int = 2500
var total_computed: int = 0
var _pending: Array[Dictionary] = []
var _by_owner: Dictionary = {}


func size() -> int:
	return _pending.size()


## owner: any object id key; callback(path: PackedVector2Array) runs when computed.
## `player`: whose unit walks (closed gates of the other side are walls); -1 = animals.
func request(owner_id: int, from_world: Vector2, to_world: Vector2, callback: Callable, player: int = -1) -> void:
	if _by_owner.has(owner_id):
		var existing: Dictionary = _by_owner[owner_id]
		existing["from"] = from_world
		existing["to"] = to_world
		existing["callback"] = callback
		existing["player"] = player
		return
	var req: Dictionary = {"owner": owner_id, "from": from_world, "to": to_world, "callback": callback, "player": player}
	_pending.append(req)
	_by_owner[owner_id] = req


func cancel(owner_id: int) -> void:
	if not _by_owner.has(owner_id):
		return
	_pending.erase(_by_owner[owner_id])
	_by_owner.erase(owner_id)


## Computes up to `budget` paths with `nav`. Returns how many were computed.
func process(nav: NavGrid) -> int:
	var done: int = 0
	var t0: int = Time.get_ticks_usec()
	while done < budget and not _pending.is_empty():
		if done > 0 and Time.get_ticks_usec() - t0 >= budget_usec:
			break
		var req: Dictionary = _pending.pop_front()
		_by_owner.erase(req["owner"])
		var path: PackedVector2Array = nav.find_path(req["from"], req["to"], int(req.get("player", -1)))
		total_computed += 1
		done += 1
		var cb: Callable = req["callback"]
		if cb.is_valid():
			cb.call(path)
	return done
