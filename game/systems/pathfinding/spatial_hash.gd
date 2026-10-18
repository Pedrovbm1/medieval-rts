class_name SpatialHash
extends RefCounted
## Uniform bucket grid for fast "who is near me" queries (steering, combat).
## Rebuilt once per physics frame; cheap for a few hundred entities.
## Buckets are keyed by a packed int (faster than Vector2i keys).

const KEY_STRIDE: int = 65536

var bucket_size: float = 64.0
var _buckets: Dictionary = {}
var _result: Array = []


func _init(p_bucket_size: float = 64.0) -> void:
	bucket_size = p_bucket_size


func clear() -> void:
	_buckets.clear()


func insert(item: Object, pos: Vector2) -> void:
	var key: int = int(floorf(pos.x / bucket_size)) * KEY_STRIDE + int(floorf(pos.y / bucket_size))
	var bucket: Variant = _buckets.get(key)
	if bucket == null:
		_buckets[key] = [item]
	else:
		(bucket as Array).append(item)


## Items whose bucket overlaps the circle (caller filters by exact distance).
## The returned array is reused by the next query: do not keep it.
func query(pos: Vector2, radius: float) -> Array:
	_result.clear()
	var x0: int = int(floorf((pos.x - radius) / bucket_size))
	var x1: int = int(floorf((pos.x + radius) / bucket_size))
	var y0: int = int(floorf((pos.y - radius) / bucket_size))
	var y1: int = int(floorf((pos.y + radius) / bucket_size))
	for kx: int in range(x0, x1 + 1):
		for ky: int in range(y0, y1 + 1):
			var bucket: Variant = _buckets.get(kx * KEY_STRIDE + ky)
			if bucket != null:
				_result.append_array(bucket)
	return _result
