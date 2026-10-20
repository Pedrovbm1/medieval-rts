class_name OrderResolver
extends RefCounted
## The one place that decides what a unit does with a tapped target
## (gather, build, attack, hunt, deliver, repair, garrison, relic, trade...).
## Used by the selection (to predict the order for the marker colour and to
## release villagers) and by CommandBus.apply (to really assign the task), so
## a local tap and a networked order always resolve the same way.
## Also turns a target {"kind", "ref"} into plain data and back, so orders can
## travel over the network and be stored for replays.


## The task that fits `unit` on `kind`/`ref`, or null (= plain move).
## kind: own_unit | animal | enemy_unit | node | own_building | enemy_building
##       | neutral_building | tree | ground
static func task_for(world: World, unit: Unit, kind: String, ref: Variant) -> UnitTask:
	if kind == "enemy_unit" or kind == "enemy_building":
		if unit.data.get("combat", {}).is_empty():
			return null
		if bool(Dictionary(unit.data["combat"]).get("buildings_only", false)) and kind == "enemy_unit":
			return null
		return AttackTask.new(unit, world, ref, true)
	if not unit.can_gather():
		if kind == "animal" and not unit.data.get("combat", {}).is_empty():
			return AttackTask.new(unit, world, ref, true)
		if kind == "node" and (ref as ResourceNode).is_relic() and bool(unit.data.get("relic_carrier", false)):
			return RelicTask.new(unit, world, ref)
		if unit.data.has("trade") and kind == "neutral_building" and bool((ref as Building).data.get("trade_post", false)):
			return TradeTask.new(unit, world, world.nearest_market(unit.owner_id, unit.position), ref)
		if unit.data.has("trade") and kind == "own_building" and (ref as Building).data.has("market") and (ref as Building).is_complete():
			return TradeTask.new(unit, world, ref, world.nearest_trade_post(unit.position))
		if kind == "own_building" and unit.relic and bool((ref as Building).data.get("relic_vault", false)) and (ref as Building).is_complete():
			return RelicTask.deliver_to(unit, world, ref)
		if kind == "own_building" and (ref as Building).can_garrison(unit) and (ref as Building).in_danger(world):
			return GarrisonTask.new(unit, world, ref)
		return null
	match kind:
		"tree":
			return GatherTask.for_tree(unit, world, ref)
		"node":
			if (ref as ResourceNode).is_relic():
				return null
			return GatherTask.for_node(unit, world, ref)
		"animal", "own_unit":
			var prey: Unit = ref
			if prey != null and prey.is_animal():
				return HuntTask.new(unit, world, prey)
		"own_building":
			var b: Building = ref
			if not b.is_complete():
				return BuildTask.new(unit, world, b)
			if RepairTask.can_repair(unit, b):
				return RepairTask.new(unit, world, b)
			if not b.gather_info().is_empty():
				return GatherTask.for_farm(unit, world, b)
			if unit.carry_amount >= 1.0 and b.accepts(unit.carry_type):
				return GatherTask.deliver_to(unit, world, b)
			if b.can_garrison(unit) and b.in_danger(world):
				return GarrisonTask.new(unit, world, b)
	return null


## {"kind": "node", "ref": <ResourceNode>} -> {"kind": "node", "node": 12}
static func target_to_dict(target: Dictionary) -> Dictionary:
	var kind: String = String(target.get("kind", "ground"))
	var ref: Variant = target.get("ref")
	var out: Dictionary = {"kind": kind}
	match kind:
		"own_unit", "animal", "enemy_unit":
			if ref is Unit:
				out["unit"] = (ref as Unit).sim_id
		"node":
			if ref is ResourceNode:
				out["node"] = (ref as ResourceNode).sim_id
		"own_building", "enemy_building", "neutral_building":
			if ref is Building:
				out["building"] = (ref as Building).sim_id
		"tree":
			var c: Vector2i = ref
			out["cell"] = [c.x, c.y]
	return out


## The reverse. A target that no longer exists (died, was razed, cut down)
## becomes plain ground, which is what the tap would do a frame later anyway.
static func target_from_dict(world: World, d: Dictionary) -> Dictionary:
	var kind: String = String(d.get("kind", "ground"))
	match kind:
		"own_unit", "animal", "enemy_unit":
			var u: Unit = world.unit_by_id(int(d.get("unit", 0)))
			if u != null and not u.is_dead:
				return {"kind": kind, "ref": u}
		"node":
			var n: ResourceNode = world.node_by_id(int(d.get("node", 0)))
			if n != null:
				return {"kind": kind, "ref": n}
		"own_building", "enemy_building", "neutral_building":
			var b: Building = world.building_by_id(int(d.get("building", 0)))
			if b != null:
				return {"kind": kind, "ref": b}
		"tree":
			var arr: Array = d.get("cell", [-1, -1])
			var c: Vector2i = Vector2i(int(arr[0]), int(arr[1]))
			if world.is_tree(c):
				return {"kind": kind, "ref": c}
	return {"kind": "ground", "ref": null}


static func ids_of(units: Array[Unit]) -> Array:
	var out: Array = []
	for u: Unit in units:
		if is_instance_valid(u) and u.sim_id > 0:
			out.append(u.sim_id)
	return out


## Living units of `player` for a list of ids (others' units are ignored: a
## networked order can only move what its sender owns).
static func units_of(world: World, ids: Array, player: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for id: Variant in ids:
		var u: Unit = world.unit_by_id(int(id))
		if u != null and not u.is_dead and u.owner_id == player and world.units.has(u):
			out.append(u)
	return out


static func vec_to_arr(v: Vector2) -> Array:
	return [v.x, v.y]


static func arr_to_vec(a: Variant) -> Vector2:
	if a is Array and (a as Array).size() == 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
