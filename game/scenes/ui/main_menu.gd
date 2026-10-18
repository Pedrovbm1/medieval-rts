extends Control
## Title screen: Continue (latest save), New game with difficulty, Tutorial.
## Hands the choice to the match through GameState.launch, then loads main.
## Debug builds with user://scenario.txt skip straight to the match (device
## benchmarks and automated phone tests).

const MAIN_SCENE: String = "res://scenes/main/main.tscn"

@onready var box: VBoxContainer = $Center/Box
@onready var title: Label = $Center/Box/Title


func _ready() -> void:
	if OS.is_debug_build() and FileAccess.file_exists("user://scenario.txt"):
		_start.call_deferred({})
		return
	title.text = tr("APP_NAME")
	Music.play_theme("menu")
	_show_main()


func _show_main() -> void:
	_clear()
	var latest: String = SaveManager.latest_slot()
	if latest != "":
		_button(tr("MENU_CONTINUE"), func() -> void: _start({"load": latest}))
	_button(tr("MENU_NEW_GAME"), _show_difficulty)
	var tutorial: Button = _button(tr("MENU_TUTORIAL"), func() -> void: _start({"scenario": "tutorial"}))
	tutorial.disabled = DataLoader.get_entry("scenarios", "tutorial").is_empty()


func _show_difficulty() -> void:
	_clear()
	_heading(tr("MENU_CHOOSE_DIFFICULTY"))
	for id: String in ["easy", "normal", "hard"]:
		var key: String = String(Dictionary(Dictionary(DataLoader.get_table("ai").get("difficulties", {})).get(id, {})).get("name_key", id))
		_button(tr(key), func() -> void: _show_maps(id))
	_button(tr("HUD_BACK"), _show_main)


func _show_maps(difficulty: String) -> void:
	_clear()
	_heading(tr("MENU_CHOOSE_MAP"))
	for map_id: Variant in DataLoader.get_entry("scenarios", "_maps").get("list", []):
		var def: Dictionary = DataLoader.get_map(String(map_id))
		if def.is_empty():
			continue
		var id: String = String(map_id)
		_button(tr(String(def.get("name_key", id))), func() -> void: _start({"scenario": "skirmish", "map": id, "ai": {"1": difficulty}}))
	_button(tr("HUD_BACK"), _show_difficulty)


func _start(launch: Dictionary) -> void:
	GameState.launch = launch
	get_tree().change_scene_to_file(MAIN_SCENE)


func _clear() -> void:
	for child: Node in box.get_children():
		if child != title:
			box.remove_child(child)
			child.queue_free()


func _heading(text: String) -> void:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	box.add_child(l)


func _button(text: String, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		action.call())
	box.add_child(b)
	if OS.is_debug_build():
		_log_button.call_deferred(b, text)
	return b


## Debug aid for device tests: "[REALM] menu btn <text>=(x,y)".
func _log_button(b: Button, text: String) -> void:
	await get_tree().process_frame
	if is_instance_valid(b):
		var c: Vector2 = b.get_global_rect().get_center()
		print("[REALM] menu btn %s=(%d,%d)" % [text, int(c.x), int(c.y)])
