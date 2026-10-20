class_name SaveGame
extends RefCounted
## Whole-match snapshot <-> plain Dictionary (JSON-safe).
## The terrain is regenerated from the map seed, then the save re-applies
## what changed: cut trees, resource amounts, buildings (with queues and
## construction progress), units (with their current task), explored fog,
## AI memory, match clock and camera.

const VERSION: int = 2


static func snapshot(main: Node) -> Dictionary:
	var world: World = main.get_node("World")
	var rules: MatchRules = main.get_node("MatchRules")
	var camera: CameraController = main.get_node("CameraController")
	var ids: Dictionary = {}  # object -> save id
	var next_id: int = 1
	var buildings: Array = []
	for b: Building in world.buildings:
		ids[b] = next_id
		next_id += 1
	var units: Array = []
	for u: Unit in world.units:
		ids[u] = next_id
		next_id += 1
	var nodes: Array = []
	for i: int in world.resource_nodes.size():
		var n: ResourceNode = world.resource_nodes[i]
		ids[n] = next_id
		next_id += 1
		nodes.append({"id": ids[n], "type": n.resource_type, "cell": [n.cell.x, n.cell.y], "pos": [n.position.x, n.position.y], "amount": n.amount, "free": n.walkable})
	for b: Building in world.buildings:
		var inside: Array = []
		for u: Unit in b.garrison:
			inside.append({"type": u.unit_type, "hp": u.hp, "carry_type": u.carry_type, "carry": u.carry_amount})
		buildings.append({
			"id": ids[b], "type": b.building_type, "owner": b.owner_id, "cell": [b.cell.x, b.cell.y], "hp": b.hp, "open": b.is_open,
			"progress": b.build_progress, "queue": Array(b.queue), "train_elapsed": b.train_elapsed,
			"rally": [b.rally_point.x, b.rally_point.y] if b.rally_point != Vector2.INF else null,
			"garrison": inside, "food_left": b.food_left, "fallow": b.fallow, "reseeds": b.reseeds, "relics": b.relics,
		})
	for u: Unit in world.units:
		units.append({
			"id": ids[u], "type": u.unit_type, "owner": u.owner_id, "pos": [u.position.x, u.position.y], "hp": u.hp,
			"stance": u.stance, "carry_type": u.carry_type, "carry": u.carry_amount, "relic": u.relic,
			"goal": [u.goal.x, u.goal.y] if u.goal != Vector2.INF else null,
			"task": _task_to_dict(u.task, ids),
		})
	var vision: Dictionary = {}
	for p: int in world.vision.grid.states.keys():
		vision[str(p)] = Marshalls.raw_to_base64(world.vision.grid.states[p])
	var ais: Array = []
	for ai: AIController in main.ais:
		var known: Array = []
		for k: Dictionary in ai.known_buildings.values():
			known.append({"pos": [Vector2(k["pos"]).x, Vector2(k["pos"]).y], "type": k["type"]})
		ais.append({"player": ai.player_id, "difficulty": ai.difficulty_id, "elapsed": ai.elapsed, "waves": ai.waves, "known": known})
	return {
		"version": VERSION,
		"scenario": main.get("scenario_id"),
		"map_id": world.map_id,
		"elapsed": rules.elapsed,
		"fair_ai": bool(main.get("fair_ai")),
		"bell_on": bool(main.get("bell_on")),
		"game_state": GameState.to_dict(),
		"terrain": Marshalls.raw_to_base64(world.terrain_grid),
		"trees": world.tree_amounts_dict(),
		"nodes": nodes,
		"buildings": buildings,
		"units": units,
		"vision": vision,
		"ais": ais,
		"camera": [camera.position.x, camera.position.y, camera.get_zoom_factor()],
	}


static func _task_to_dict(task: RefCounted, ids: Dictionary) -> Variant:
	if task == null:
		return null
	if task is GatherTask:
		var g: GatherTask = task
		var d: Dictionary = {"kind": "gather", "step": int(g.step), "anchor": [g.anchor.x, g.anchor.y], "subtype": g.subtype}
		match g.target:
			GatherTask.Target.NODE:
				d["node"] = ids.get(g.node, 0)
			GatherTask.Target.TREE:
				d["tree"] = [g.tree_cell.x, g.tree_cell.y]
			GatherTask.Target.FARM:
				d["farm"] = ids.get(g.farm, 0)
			_:
				d["deliver"] = ids.get(g.dropoff, 0)
		return d
	if task is BuildTask:
		return {"kind": "build", "building": ids.get((task as BuildTask).building, 0)}
	if task is AttackTask:
		var a: AttackTask = task
		return {"kind": "attack", "target": ids.get(a.target, 0), "ordered": a.ordered}
	if task is HuntTask:
		return {"kind": "hunt", "prey": ids.get((task as HuntTask).prey, 0)}
	if task is HealTask:
		return {"kind": "heal", "target": ids.get((task as HealTask).target, 0)}
	return null


## Rebuilds a match from a snapshot into a freshly built World (no scenario run).
static func restore(main: Node, data: Dictionary) -> void:
	var world: World = main.get_node("World")
	GameState.from_dict(data.get("game_state", {}))
	world.apply_terrain(Marshalls.base64_to_raw(String(data.get("terrain", ""))), data.get("trees", {}))
	var by_id: Dictionary = {}
	for nd: Variant in data.get("nodes", []):
		var n: Dictionary = nd
		var node: ResourceNode
		if bool(n.get("free", false)):
			node = world.spawn_carcass(String(n["type"]), Vector2(float(n["pos"][0]), float(n["pos"][1])))
		else:
			node = world.place_resource(String(n["type"]), Vector2i(int(n["cell"][0]), int(n["cell"][1])))
		node.amount = float(n["amount"])
		by_id[int(n["id"])] = node
	for bd: Variant in data.get("buildings", []):
		var b: Dictionary = bd
		var building: Building = world.place_building(String(b["type"]), int(b["owner"]), Vector2i(int(b["cell"][0]), int(b["cell"][1])))
		building.build_progress = float(b["progress"])
		building.hp = int(b["hp"])
		building.food_left = float(b.get("food_left", building.food_left))
		building.fallow = bool(b.get("fallow", false))
		building.reseeds = int(b.get("reseeds", 0))
		building.relics = int(b.get("relics", 0))
		if building.is_gate() and not bool(b.get("open", true)):
			building.set_gate_open(false, world.nav)
		for item: Variant in b.get("queue", []):
			building.queue.append(String(item))
		building.train_elapsed = float(b.get("train_elapsed", 0.0))
		if b.get("rally") != null:
			building.rally_point = Vector2(float(b["rally"][0]), float(b["rally"][1]))
		for gd: Variant in b.get("garrison", []):
			var g: Dictionary = gd
			var inside: Unit = world.spawn_unit(String(g["type"]), building.owner_id, building.position)
			inside.hp = int(g.get("hp", inside.max_hp))
			inside.carry_type = String(g.get("carry_type", ""))
			inside.carry_amount = float(g.get("carry", 0.0))
			world.garrison_unit(inside, building)
		building.queue_redraw()
		by_id[int(b["id"])] = building
	var pending_tasks: Array = []
	for ud: Variant in data.get("units", []):
		var u: Dictionary = ud
		var unit: Unit = world.spawn_unit(String(u["type"]), int(u["owner"]), Vector2(float(u["pos"][0]), float(u["pos"][1])))
		unit.hp = int(u["hp"])
		unit.stance = String(u.get("stance", unit.stance))
		unit.carry_type = String(u.get("carry_type", ""))
		unit.carry_amount = float(u.get("carry", 0.0))
		unit.relic = bool(u.get("relic", false))
		unit.queue_redraw()
		by_id[int(u["id"])] = unit
		pending_tasks.append([unit, u.get("task"), u.get("goal")])
	for entry: Array in pending_tasks:
		var unit: Unit = entry[0]
		var task: UnitTask = _task_from_dict(entry[1], unit, world, by_id)
		if task != null:
			world.behavior.assign(unit, task)
		elif entry[2] != null:
			world.movement.move_unit(unit, Vector2(float(entry[2][0]), float(entry[2][1])))
	world.economy.refresh_population()
	world.recount_relics()
	for key: Variant in Dictionary(data.get("vision", {})).keys():
		var raw: PackedByteArray = Marshalls.base64_to_raw(String(data["vision"][key]))
		if world.vision.grid.states.has(int(key)) and raw.size() == world.vision.grid.width * world.vision.grid.height:
			world.vision.grid.states[int(key)] = raw
	world.vision.refresh()
	var rules: MatchRules = main.get_node("MatchRules")
	rules.elapsed = float(data.get("elapsed", 0.0))
	main.set("bell_on", bool(data.get("bell_on", false)))
	var cam: Array = data.get("camera", [])
	if cam.size() == 3:
		var camera: CameraController = main.get_node("CameraController")
		camera.center_on(Vector2(float(cam[0]), float(cam[1])))
		camera.zoom_at(camera.get_viewport_rect().size * 0.5, float(cam[2]))


static func restore_ais(main: Node, data: Dictionary) -> void:
	# AI setup applies difficulty bonuses (gather_mult, human_bonus) to the
	# multipliers; the save already contains them, so put the saved ones back.
	var saved_state: Dictionary = data.get("game_state", {})
	if saved_state.has("multipliers"):
		GameState.multipliers = GameState._int_keys(saved_state["multipliers"])
	for ad: Variant in data.get("ais", []):
		var a: Dictionary = ad
		for ai: AIController in main.ais:
			if ai.player_id == int(a["player"]):
				ai.elapsed = float(a.get("elapsed", 0.0))
				ai.waves = int(a.get("waves", 0))
				var i: int = 0
				for k: Variant in a.get("known", []):
					i += 1
					ai.known_buildings[-i] = {"pos": Vector2(float(k["pos"][0]), float(k["pos"][1])), "type": String(k["type"]), "ref": null}


static func _task_from_dict(d: Variant, unit: Unit, world: World, by_id: Dictionary) -> UnitTask:
	if d == null:
		return null
	var t: Dictionary = d
	match String(t.get("kind", "")):
		"gather":
			var task: GatherTask = null
			if t.has("node") and by_id.get(int(t["node"])) is ResourceNode:
				task = GatherTask.for_node(unit, world, by_id[int(t["node"])])
			elif t.has("tree") and world.is_tree(Vector2i(int(t["tree"][0]), int(t["tree"][1]))):
				task = GatherTask.for_tree(unit, world, Vector2i(int(t["tree"][0]), int(t["tree"][1])))
			elif t.has("farm") and by_id.get(int(t["farm"])) is Building:
				task = GatherTask.for_farm(unit, world, by_id[int(t["farm"])])
			elif t.has("deliver") and by_id.get(int(t["deliver"])) is Building:
				task = GatherTask.deliver_to(unit, world, by_id[int(t["deliver"])])
			elif t.has("node") and String(t.get("subtype", "")) != "":
				# Its node ran out before the save (the villager was walking to
				# drop off the last load): go on with the same kind of resource.
				var anchor: Vector2 = Vector2(float(t["anchor"][0]), float(t["anchor"][1]))
				var other: ResourceNode = world.find_node_near(String(t["subtype"]), anchor, GatherTask.RETARGET_NODE_PX)
				if other != null:
					task = GatherTask.for_node(unit, world, other)
				elif unit.carry_amount >= 1.0:
					var drop: Building = world.economy.nearest_dropoff(unit.owner_id, unit.carry_type, unit.position)
					if drop != null:
						return GatherTask.deliver_to(unit, world, drop)
			if task != null:
				task.step = int(t.get("step", 0)) as GatherTask.Step
				task.anchor = Vector2(float(t["anchor"][0]), float(t["anchor"][1]))
			return task
		"build":
			if by_id.get(int(t["building"])) is Building:
				return BuildTask.new(unit, world, by_id[int(t["building"])])
		"attack":
			var target: Variant = by_id.get(int(t["target"]))
			if target != null:
				return AttackTask.new(unit, world, target, bool(t.get("ordered", true)))
		"hunt":
			if by_id.get(int(t["prey"])) is Unit:
				return HuntTask.new(unit, world, by_id[int(t["prey"])])
		"heal":
			if by_id.get(int(t["target"])) is Unit:
				return HealTask.new(unit, world, by_id[int(t["target"])])
	return null
