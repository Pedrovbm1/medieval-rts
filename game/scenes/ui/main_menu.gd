extends Control
## Title screen: Continue (latest save), New game with difficulty, Tutorial.
## Hands the choice to the match through GameState.launch, then loads main.
## Debug builds with user://scenario.txt skip straight to the match (device
## benchmarks and automated phone tests).

const MAIN_SCENE: String = "res://scenes/main/main.tscn"

@onready var box: VBoxContainer = $Center/Box
@onready var title: Label = $Center/Box/Title


## Debug builds: `-- net=host[:map]` hosts and starts as soon as a rival
## joins; `-- net=join:IP` joins that host. Two instances on one PC (or PC
## and phone) can then play a LAN match without touching the menu.
var _net_arg: String = ""


func _ready() -> void:
	if OS.is_debug_build() and FileAccess.file_exists("user://scenario.txt"):
		_start.call_deferred({})
		return
	title.text = tr("APP_NAME")
	Music.play_theme("menu")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("net=") and OS.is_debug_build():
			_net_arg = arg.substr(4)
	if _net_arg != "":
		_auto_net.call_deferred()
		return
	_show_main()


func _auto_net() -> void:
	var parts: PackedStringArray = _net_arg.split(":")
	if parts[0] == "host":
		if parts.size() > 1:
			_net_map = parts[1]
		_auto_start = true
		_show_host()
		print("[REALM] net auto host map=%s ips=%s" % [_net_map, ", ".join(NetSession.local_ips())])
	elif parts[0] == "join" and parts.size() > 1:
		_show_join()
		(box.get_node("IpField") as LineEdit).text = parts[1]
		var err: Error = NetSession.join(parts[1])
		print("[REALM] net auto join %s err=%d" % [parts[1], err])
	else:
		_show_main()


## Auto-host (debug): start the match a moment after the rival joins.
var _auto_start: bool = false


func _show_main() -> void:
	_clear()
	var latest: String = SaveManager.latest_slot()
	if latest != "":
		_button(tr("MENU_CONTINUE"), func() -> void: _start({"load": latest}))
	_button(tr("MENU_NEW_GAME"), _show_difficulty)
	_button(tr("MENU_MULTIPLAYER"), _show_multiplayer)
	var tutorial: Button = _button(tr("MENU_TUTORIAL"), func() -> void: _start({"scenario": "tutorial"}))
	tutorial.disabled = DataLoader.get_entry("scenarios", "tutorial").is_empty()


# ------------------------------------------------------------------ multiplayer (LAN)

var _net_status: Label = null
var _net_start: Button = null
var _net_map: String = ""


## "Multijugador": host a match on this Wi-Fi or join one by IP.
func _show_multiplayer() -> void:
	_disconnect_net_signals()
	NetSession.leave()
	_clear()
	_heading(tr("MENU_MULTIPLAYER"))
	_button(tr("MENU_HOST"), _show_host)
	_button(tr("MENU_JOIN"), _show_join)
	_button(tr("HUD_BACK"), _show_main)


func _show_host() -> void:
	_clear()
	var err: Error = NetSession.host()
	if err != OK:
		_heading(tr("MENU_HOST_FAILED") % NetSession.port)
		_button(tr("HUD_BACK"), _show_multiplayer)
		return
	_heading(tr("MENU_HOST"))
	var ips: PackedStringArray = NetSession.local_ips()
	_heading(tr("MENU_YOUR_IP") % (", ".join(ips) if not ips.is_empty() else tr("MENU_NO_IP")))
	var maps: Array = DataLoader.get_entry("scenarios", "_maps").get("list", [])
	if _net_map == "" or not maps.has(_net_map):
		_net_map = String(maps[0]) if not maps.is_empty() else "skirmish_120"
	var map_button: Button = _button(tr("MENU_MAP_LABEL") % tr(String(DataLoader.get_map(_net_map).get("name_key", _net_map))), func() -> void:
		var i: int = maps.find(_net_map)
		_net_map = String(maps[(i + 1) % maps.size()])
		_show_host())
	map_button.add_theme_font_size_override("font_size", 22)
	map_button.custom_minimum_size = Vector2(520, 72)
	_net_status = Label.new()
	_net_status.text = tr("MENU_PLAYER_JOINED") if NetSession.peer_count() > 0 else tr("MENU_WAITING_PLAYER")
	_net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_status.add_theme_font_size_override("font_size", 22)
	box.add_child(_net_status)
	_net_start = _button(tr("MENU_START_MATCH"), func() -> void:
		if not NetSession.start_match(_net_map):
			Sfx.play("error"))
	_net_start.disabled = NetSession.peer_count() == 0
	_button(tr("MENU_CANCEL"), _show_multiplayer)
	_connect_net_signals()


func _show_join() -> void:
	_clear()
	_heading(tr("MENU_JOIN"))
	var ip: LineEdit = LineEdit.new()
	ip.name = "IpField"
	ip.placeholder_text = tr("MENU_IP_HINT")
	ip.text = NetSession.last_ip()
	ip.custom_minimum_size = Vector2(520, 72)
	ip.add_theme_font_size_override("font_size", 28)
	ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	box.add_child(ip)
	_net_status = Label.new()
	_net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_status.add_theme_font_size_override("font_size", 22)
	box.add_child(_net_status)
	var connect_button: Button = _button(tr("MENU_CONNECT"), func() -> void:
		if ip.text.strip_edges() == "":
			Sfx.play("error")
			return
		if NetSession.join(ip.text) == OK:
			_net_status.text = tr("MENU_CONNECTING")
		else:
			_net_status.text = tr("MENU_CONNECT_FAILED"))
	ip.text_submitted.connect(func(_t: String) -> void: connect_button.pressed.emit())
	_button(tr("MENU_CANCEL"), _show_multiplayer)
	_connect_net_signals()


func _connect_net_signals() -> void:
	if not NetSession.peer_joined.is_connected(_on_net_peer_joined):
		NetSession.peer_joined.connect(_on_net_peer_joined)
		NetSession.peer_left.connect(_on_net_peer_left)
		NetSession.joined_host.connect(_on_net_joined_host)
		NetSession.join_failed.connect(_on_net_join_failed)


func _disconnect_net_signals() -> void:
	if NetSession.peer_joined.is_connected(_on_net_peer_joined):
		NetSession.peer_joined.disconnect(_on_net_peer_joined)
		NetSession.peer_left.disconnect(_on_net_peer_left)
		NetSession.joined_host.disconnect(_on_net_joined_host)
		NetSession.join_failed.disconnect(_on_net_join_failed)


func _on_net_peer_joined(_id: int) -> void:
	if NetSession.is_host and is_instance_valid(_net_status):
		_net_status.text = tr("MENU_PLAYER_JOINED")
		if is_instance_valid(_net_start):
			_net_start.disabled = false
		Sfx.play("unit_ready")
		if _auto_start:
			await get_tree().create_timer(1.0).timeout
			if NetSession.is_host and NetSession.peer_count() > 0:
				NetSession.start_match(_net_map)


func _on_net_peer_left(_id: int) -> void:
	if NetSession.is_host and is_instance_valid(_net_status):
		_net_status.text = tr("MENU_WAITING_PLAYER")
		if is_instance_valid(_net_start):
			_net_start.disabled = true


func _on_net_joined_host() -> void:
	if is_instance_valid(_net_status):
		_net_status.text = tr("MENU_CONNECTED_WAIT")


func _on_net_join_failed() -> void:
	if is_instance_valid(_net_status):
		_net_status.text = tr("MENU_CONNECT_FAILED")
		Sfx.play("error")


func _exit_tree() -> void:
	_disconnect_net_signals()


## "Fair AI" (no hidden bonuses for the computer) is the default; the toggle
## below the difficulties flips it for the next match and the cards say
## exactly what each side gets, so a loss never feels like a cheat.
static var fair_ai: bool = true


func _show_difficulty() -> void:
	_clear()
	_heading(tr("MENU_CHOOSE_DIFFICULTY"))
	for id: String in ["easy", "normal", "hard"]:
		var key: String = String(Dictionary(Dictionary(DataLoader.get_table("ai").get("difficulties", {})).get(id, {})).get("name_key", id))
		var b: Button = _button(tr(key) + "\n" + difficulty_card(id, fair_ai), func() -> void: _show_maps(id))
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(520, 96)
	var toggle: Button = _button(tr("MENU_FAIR_ON") if fair_ai else tr("MENU_FAIR_OFF"), func() -> void:
		fair_ai = not fair_ai
		_show_difficulty())
	toggle.add_theme_font_size_override("font_size", 22)
	toggle.custom_minimum_size = Vector2(520, 72)
	_button(tr("HUD_BACK"), _show_main)


## One line per difficulty: what the AI gets and what you get.
static func difficulty_card(id: String, fair: bool) -> String:
	var ai_bonus: String = "" if fair else AIController.bonus_text(id)
	var parts: PackedStringArray = PackedStringArray()
	parts.append(TranslationServer.translate("MENU_AI_BONUS") % (ai_bonus if ai_bonus != "" else TranslationServer.translate("MENU_NO_BONUS")))
	var mine: String = AIController.human_bonus_text(id)
	if mine != "":
		parts.append(TranslationServer.translate("MENU_YOU_BONUS") % mine)
	return "  ·  ".join(parts)


func _show_maps(difficulty: String) -> void:
	_clear()
	_heading(tr("MENU_CHOOSE_MAP"))
	for map_id: Variant in DataLoader.get_entry("scenarios", "_maps").get("list", []):
		var def: Dictionary = DataLoader.get_map(String(map_id))
		if def.is_empty():
			continue
		var id: String = String(map_id)
		_button(tr(String(def.get("name_key", id))), func() -> void: _start({"scenario": "skirmish", "map": id, "ai": {"1": difficulty}, "fair": fair_ai}))
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
