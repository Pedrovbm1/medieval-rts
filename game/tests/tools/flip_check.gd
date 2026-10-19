extends Node
## Dev tool (windowed): selects the sandbox units, turns half of them to face
## left, zooms in and saves a screenshot, to check that sprites stay centred
## on their selection circles. Usage:
##   godot --path game tests/tools/flip_check.tscn -- out=<png>


func _ready() -> void:
	var out: String = "user://flip_check.png"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.substr(4)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = OS.get_environment("REALM_SCEN") if OS.has_environment("REALM_SCEN") else "sandbox"
	add_child(main)
	await get_tree().process_frame
	var world: World = main.get_node("World")
	var units: Array[Unit] = []
	for u: Unit in world.units:
		if u.owner_id == 0:
			units.append(u)
	var sel: SelectionController = main.get_node("SelectionController")
	sel.set_selection(units)
	var cam: Camera2D = main.get_node("CameraController")
	cam.position = units[0].position
	cam.zoom = Vector2(2.0, 2.0) if not OS.has_environment("REALM_ZOOM") else Vector2.ONE * float(OS.get_environment("REALM_ZOOM"))
	for i: int in units.size():
		units[i].face_left = i % 2 == 0
		units[i].set_physics_process(false)
		units[i].queue_redraw()
	if OS.has_environment("REALM_FARM"):
		# Farm under the first units: they must stay visible on top of it.
		var farm: Building = world.place_building("farm", 0, world.world_to_cell(units[0].position) + Vector2i(-1, -2))
		for i: int in units.size():
			units[i].position = farm.position + Vector2(-60 + (i % 5) * 30, -50 + (i / 5) * 60)
		cam.position = farm.position
	if OS.has_environment("REALM_BUILD_MENU"):
		var villagers: Array[Unit] = units.filter(func(u: Unit) -> bool: return u.can_gather())
		sel.set_selection(villagers)
		main.get_node("Hud").show_build_menu()
	await get_tree().create_timer(1.0).timeout
	for i: int in units.size():
		units[i].face_left = i % 2 == 0
		units[i].queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[REALM] flip check selected=%d draw_calls=%d" % [sel.selected.size(), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	get_viewport().get_texture().get_image().save_png(out)
	print("[REALM] flip check saved ", out)
	get_tree().quit()
